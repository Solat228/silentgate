import 'dart:async';
import 'dart:io';

import 'adapter_dns_windows.dart';
import '../../core/platform/app_env.dart';
import '../../core/platform/app_log.dart';
import '../../core/platform/ipv6_support.dart';
import '../../core/platform/app_paths.dart';
import '../../core/platform/port_check.dart';
import '../../core/models/traffic_stats.dart';
import '../../core/models/vpn_server.dart';
import '../../core/models/vpn_status.dart';
import '../../core/models/engine_notice.dart';
import '../../core/settings/app_settings.dart';
import '../../core/singbox/singbox_config_builder.dart';
import '../../core/singbox/exit_outbounds.dart';
import '../engine_base.dart';
import '../vpn_engine.dart';
import 'singbox_process.dart';
import 'singbox_stats.dart';
import '../../core/net/dns_fallback_server.dart';
import 'system_proxy.dart';
import 'tun/singbox_router_windows.dart';
import 'tun/tun_router.dart';
import 'xray_paths.dart';
import 'xray_process.dart';
import 'xray_stats.dart';

/// Реализация движка для Windows: запускает xray.exe / sing-box.exe и включает
/// захват трафика (системный прокси или TUN).
///
/// Платформо-независимая половина — сессия, поколения, автовосстановление,
/// выбор конфига и ядра — живёт в [VpnEngineBase].
class WindowsEngine extends VpnEngineBase {
  XrayProcess? _process;

  /// Локальный DNS-форвардер с запасным резолвером (см. _startFallbackDns).
  DnsFallbackServer? _fallbackDns;

  /// Второе прокси-ядро: sing-box для протоколов, которых нет в Xray (hysteria2).
  /// Одновременно с [_process] не работает — какое ядро поднимать, решает
  /// [VpnServer.core]. TUN-инстанс sing-box считается отдельно (`_tunRouter`).
  SingboxProcess? _singbox;
  Timer? _statsTimer;

  /// Сторож зависшего TUN-ядра. См. [AppSettings.tunWatchdogSeconds].
  Timer? _tunWatchdog;

  /// Когда TUN-ядро в последний раз ответило по своему API. `null` — оно ещё
  /// НИ РАЗУ не отвечало, и сторож в этом случае молчит: см. [_startTunWatchdog].
  DateTime? _tunLastAlive;
  StreamSubscription<int>? _exitWatch;
  final TunRouter _tunRouter = SingboxRouterWindows();
  bool _tunActive = false;
  bool _proxySet = false; // чистим системный прокси только если ставили его сами

  /// Идёт ли сейчас опрос счётчиков (Timer.periodic async-колбэки не сериализует).
  bool _polling = false;

  XrayTrafficSnapshot _lastSnapshot = XrayTrafficSnapshot.zero;
  DateTime _lastSampleTime = DateTime.now();

  WindowsEngine({super.ports}) {
    // Восстановление после аварийного выхода прошлого запуска.
    SystemProxy.recoverIfDirty();
  }

  /// ⚠️ СМЕШАННЫЙ РЕЖИМ — ТОЖЕ СИСТЕМНЫЙ ПРОКСИ. При `alsoSetSystemProxy`
  /// прокси прописывается ДОПОЛНИТЕЛЬНО к туннелю, и в локальный порт снова
  /// смотрит WinINET, который креденшелов не передаёт. Проверка одного лишь
  /// `captureMode` пропускала этот случай, и весь прокси-aware трафик получал
  /// бы 407 при включённом по умолчанию пароле.
  @override
  bool systemProxyModeFor(ConnectionOptions options) =>
      options.captureMode != CaptureMode.tun ||
      options.settings.alsoSetSystemProxy;

  /// Один запуск текущей сессии (первичный или повторный при восстановлении).
  @override
  Future<void> startSession() async {
    final session = this.session;
    if (session == null) return;
    final configJson = session.configJson;
    final options = session.options;
    final servers = session.servers;

    // Метка этого запуска: пока мы ждём (подъём ядра, автоподбор TUN — до минут),
    // пользователь мог нажать «Отключить». Тогда поколение сменится, и всё, что
    // мы успели поднять после этого, нужно немедленно погасить, иначе туннель
    // остаётся жить при выключенном на вид VPN.
    final gen = newGeneration();
    bool aborted() => isStale(gen);

    // message: null затирал бы уже выставленное базой «Пробую другой сервер: …»
    // — она ставит его прямо перед этим вызовом, и подпись жила меньше секунды.
    setStatus(
      VpnConnectionState.connecting,
      message: attempt > 0
          ? 'Переподключение (попытка $attempt)…'
          : (status.state == VpnConnectionState.connecting
              ? status.message
              : null),
    );

    final singboxCore = session.core == ProxyCore.singbox;
    final location = XrayPaths.locate();
    final singboxExe = singboxCore ? SingboxProcess.locate() : null;
    if (singboxCore && singboxExe == null) {
      // _cleanup обязателен: при kill switch захват трафика мог остаться с
      // прошлой попытки, и без него интернет остался бы заблокированным.
      await cleanup();
      setStatus(
        VpnConnectionState.error,
        message: 'Для Hysteria2 нужен sing-box.exe рядом с xray.exe.\n'
            'Запустите tools/fetch-singbox.ps1',
      );
      return;
    }
    if (!singboxCore && location == null) {
      await cleanup();
      setStatus(
        VpnConnectionState.error,
        message: 'Не найден xray.exe. Запустите tools/fetch-xray.ps1',
      );
      return;
    }

    // Порты проверяем ДО запуска: если их занял другой VPN-клиент, ядро просто
    // упадёт, и раньше пользователь видел бесполезное «Ядро завершилось при запуске».
    //
    // ⚠️ НО СНАЧАЛА ЖДЁМ СВОЁ ЖЕ ЯДРО. Быстрое «Отключить → Подключить» — гонка
    // с самим собой: прежний xray.exe уже получил kill, а слушающий сокет
    // Windows освобождает не мгновенно. Раньше мы в этот момент либо падали с
    // «код 1», либо объявляли собственный остаток чужим VPN-клиентом и
    // предлагали «закройте Happ» — при том что никакого Happ у пользователя не
    // запущено. Ожидание короткое и только пока порт реально занят.
    // Креды локальных прокси здесь УЖЕ выданы — базой, до сборки конфига
    // (`prepareLocalProxyAuth`). Повторять вызов нельзя: он выдал бы новый
    // пароль, а конфиг ядра остался бы с прежним.
    final corePorts = [ports.socks, ports.http, ports.api];
    var conflict = await PortCheck.findConflict(corePorts);
    if (conflict != null && conflict.heldByOwnCore) {
      AppLog.i('Порт ${conflict.port} ещё держит наше ядро '
          '(${conflict.holder}) — жду освобождения');
      await PortCheck.waitFree(corePorts);
      if (aborted()) return;
      conflict = await PortCheck.findConflict(corePorts);
    }
    if (conflict != null) {
      final message = conflict.fallbackMessage;
      AppLog.e('Конфликт портов: ${message.split("\n").first}');
      await cleanup();
      setStatus(VpnConnectionState.error, message: message);
      return;
    }
    if (aborted()) return;

    try {
      final configPath =
          await _writeConfigJson(configJson, singbox: singboxCore);

      // Одно из двух ядер: Xray или (для hysteria2) sing-box.
      String Function() tailOf;
      bool Function() alive;
      Future<int>? exited;
      if (singboxCore) {
        final process = SingboxProcess();
        // Пишем вывод в файл: у прокси-ядра (hysteria2) диагностики не было
        // вообще — «конфиг валиден, процесс жив, трафика нет» не оставляло
        // ни байта, по которому можно понять причину.
        await process.start(
          executable: singboxExe!,
          configPath: configPath,
          logPath: SingboxProcess.logPathFor(await AppPaths.supportDir()),
        );
        _singbox = process;
        tailOf = () => process.tail;
        alive = () => process.isRunning;
        exited = process.exitCode;
      } else {
        final process = XrayProcess();
        await process.start(
          executable: location!.executable,
          configPath: configPath,
          assetDir: location.assetDir,
          // ⚠️ Вывод Xray В ФАЙЛ — не «на всякий случай». Без него падение
          // ядра выглядело в журнале как «остановилось (код 1)» и ничего
          // больше, хотя сам Xray причину печатает внятно («порт занят»,
          // «конфиг отвергнут»). У sing-box такой файл был давно, у Xray —
          // нет, и разбор жалобы «весь интернет лёг» упирался в пустоту.
          logPath: XrayProcess.logPathFor(await AppPaths.supportDir()),
        );
        _process = process;
        tailOf = () => process.tail;
        alive = () => process.isRunning;
        exited = process.exitCode;
      }

      // Следим за неожиданным падением ядра. Хвост вывода передаём вместе с
      // кодом: код сам по себе ничего не объясняет.
      _exitWatch = exited?.asStream().listen((code) {
        if (status.isConnected || status.state == VpnConnectionState.connecting) {
          onCoreDied(code, tail: tailOf());
        }
      });

      // Небольшая пауза на инициализацию ядра.
      await Future.delayed(const Duration(milliseconds: 500));
      if (!alive()) {
        // Показываем реальную причину из вывода ядра, а не голое «завершилось».
        final tail = tailOf().trim();
        AppLog.e('Ядро не стартовало. Вывод:\n$tail');
        throw StateError(tail.isEmpty
            ? 'Ядро завершилось при запуске (вывод пуст)'
            : 'Ядро завершилось при запуске:\n$tail');
      }

      if (aborted()) {
        await _stopCoreProcesses();
        return;
      }

      if (options.captureMode == CaptureMode.tun) {
        // Туннель мог остаться поднятым с прошлой попытки (kill switch не гасит
        // захват между попытками). Перезапускаем его: иначе элевейтнутый хелпер
        // продолжит работать по СТАРОМУ конфигу — со старым IP сервера в
        // правиле «мимо туннеля», то есть с риском петли и мёртвой сети.
        if (_tunActive) {
          await _tunRouter.stop();
          _tunActive = false;
          await Future.delayed(const Duration(milliseconds: 600));
        }
        // TUN: sing-box поднимает туннель и заворачивает прокси-трафик в SOCKS Xray.
        // start() бросит TunStartException, если туннель реально не поднялся.
        _tunActive = true; // чтобы _cleanup погасил недоподнятый туннель
        // Серверы, назначенные отдельным правилам. Собираются ТЕМ ЖЕ кодом,
        // что на Android, — иначе платформы разъедутся на первом же правиле.
        //
        // ⚠️ Резолвим ДО подъёма туннеля и вместе с серверами сессии: домен,
        // отданный ядру как есть, спрашивался бы уже из-под туннеля и замкнулся
        // сам на себя. На живом тесте это не всплыло только потому, что оба
        // сервера были заданы адресами, — не считать это проверкой.
        final exitHosts = await resolveServerHosts([
          ...servers,
          ...options.exitServers.values,
        ]);
        final exitsBuilt = ExitOutbounds.build(
          servers: options.exitServers,
          resolvedIps: VpnEngineBase.pickOneIpPerHost(exitHosts),
        );
        for (final e in exitsBuilt.skipped.entries) {
          AppLog.i('Сервер правила не поднят: ${e.value} — '
              'эти правила пойдут основным туннелем');
        }
        if (exitsBuilt.outbounds.isNotEmpty) {
          AppLog.i('Мульти-VPN: дополнительных серверов '
              '${exitsBuilt.outbounds.length}');
        }
        await _tunRouter.start(
          options.split,
          exitOutbounds: exitsBuilt.outbounds,
          xraySocksPort: ports.socks,
          xraySocksUser: localInboundUser,
          xraySocksPassword: localInboundPassword,
          options: TunOptions.fromSettings(
            options.settings,
            serverIps: await resolveServerIps(servers),
            // Имена ВСЕЙ инфраструктуры — резолвим только напрямую.
            serverDomains: knownServerDomains,
            // Снимаем ДО подъёма туннеля: после него системный резолвер уже
            // указывает на сам туннель, и «Прямо» резолвилось бы через VPN.
            directDnsUpstream: await _systemDnsServer(),
            // Запасной резолвер под общий DNS — только когда пользователь
            // просил вести DNS через туннель. Без этой галочки прямой трафик и
            // так резолвится локально, и лишнее звено не нужно.
            fallbackDnsPort: await _startFallbackDns(options.settings),
            ipv6Available: await _ipv6Reality(),
            // API туннельного экземпляра — ТОЛЬКО для сторожа зависания.
            //
            // ⚠️ Порт новый, поэтому сверен с обоими ядрами: Xray держит
            // 10808/10809/10085, sing-box-прокси — те же 10808/10809 плюс
            // 10085 под Clash API, на Android туннель занимает 10812. 10813
            // свободен. Урок 10085 и 10809 повторять не будем.
            clashApiPort: _tunApiPort,
            clashApiSecret: singboxApiSecret,
          ),
          // Автоподбор стека/MTU может занять время — показываем, что происходит
          // (#8: отдельная фаза → прогресс-тост, не только строка статуса).
          onProgress: (m) => setStatus(VpnConnectionState.connecting,
              message: m, phase: VpnPhase.tunAutotune),
          // #5 — прекратить перебор, если пользователь отключился за время подбора.
          abort: aborted,
        );
        // Подбор стека/MTU идёт до двух минут — за это время пользователь мог
        // отключиться. Туннель, поднятый уже «после отмены», гасим сразу.
        if (aborted()) {
          await _tunRouter.stop();
          _tunActive = false;
          await _stopCoreProcesses();
          return;
        }
        // Сторож вооружается ТОЛЬКО когда туннель уже стоит: во время
        // автоподбора стека и MTU ядро законно молчит до двух минут.
        _startTunWatchdog(options.settings, aborted);
        // Наблюдение за блокировками — ТОЛЬКО после подъёма туннеля: раньше
        // Clash API ещё не слушает, и опрос уходил бы в пустоту.
        startBlockNotice(
            settings: options.settings,
            apiPort: _tunApiPort,
            secret: singboxApiSecret);
      }

      // ⚠️ СИСТЕМНЫЙ ПРОКСИ СТАВИТСЯ И ВМЕСТО ТУННЕЛЯ, И ВМЕСТЕ С НИМ.
      //
      // Вместе — это «смешанный» режим (у Happ он так и подписан, Mixed):
      // прокси-aware приложения идут коротким путём прямо в http-инбаунд,
      // минуя пользовательский стек туннеля, и отдают ядру ИМЯ ДОМЕНА, а не
      // голый IP.
      //
      // ⚠️ ЦЕНА, КОТОРУЮ ОБЯЗАН ЗНАТЬ ПОЛЬЗОВАТЕЛЬ: у такого соединения нет
      // процесса-владельца — для ядра это локальное подключение с петли.
      // Значит правила ПО ПРИЛОЖЕНИЯМ для прокси-aware программ в смешанном
      // режиме не срабатывают вовсе (правила по сайтам работают, и даже лучше:
      // имя приходит без сниффинга). Интерфейс говорит об этом прямо — молча
      // отдавать неработающие правила мы уже пробовали восемь раз.
      final wantProxy = options.captureMode != CaptureMode.tun ||
          options.settings.alsoSetSystemProxy;
      if (wantProxy) {
        await SystemProxy.set('127.0.0.1:${ports.http}');
        _proxySet = true;
        if (options.captureMode == CaptureMode.tun) {
          AppLog.i('Смешанный режим: туннель + системный прокси на '
              '127.0.0.1:${ports.http}');
        }
      }

      // #4 — пользователь мог нажать «Отключить», пока поднимались ядро и
      // прокси/туннель. Без этой проверки в режиме системного прокси прокси
      // оставался прописанным, а статус вставал в «Подключено» уже ПОСЛЕ отмены.
      if (aborted()) {
        await cleanup();
        return;
      }

      _lastSnapshot = XrayTrafficSnapshot.zero;
      _lastSampleTime = DateTime.now();
      _startStatsPolling(
          singboxCore ? null : location!.executable, singbox: singboxCore);

      // Читаем ДО markConnected(): он и обнуляет счётчик попыток.
      if (attempt > 0) {
        AppLog.i('Соединение восстановлено (попытка $attempt)');
        // Говорим вслух ТОЛЬКО когда перед этим были неудачи: обычное
        // подключение по кнопке в сообщении не нуждается.
        emitNotice(EngineNoticeKind.recovered, 'Соединение восстановлено',
            detail: 'Потребовалось попыток: $attempt');
      }
      markConnected(); // сбрасывает счётчик попыток и запускает grace смены сети
      setStatus(VpnConnectionState.connected);
      // ⚠️ СТРОГО ПОСЛЕ «Подключено», а не рядом с подъёмом туннеля.
      //
      // Условие отмены у наблюдения — `aborted() || !status.isConnected`.
      // Пока вызов стоял выше (рядом со сторожем зависания), статус был ещё
      // `connecting`, и наблюдение глушило себя на ПЕРВОЙ же пробе. Внешне это
      // выглядело как «сторож не работает»: в журнале ни строчки, а живой
      // прогон в VM с отключённым адаптером не дал ничего за три минуты.
      // На Android вызов изначально стоял после статуса — потому там и
      // сработало. Расхождение платформ на ровном месте.
      // ⚠️ В ОБОИХ РЕЖИМАХ ЗАХВАТА, а не только в TUN. Умолчание на Windows —
      // системный прокси (`AppSettings.captureMode`), и с условием
      // `== CaptureMode.tun` на свежей установке сквозной проверки не было
      // ВООБЩЕ: сервер отваливался, ядро исправно отвечало по своему API,
      // приложение показывало «Подключено», и весь трафик машины уходил в
      // мёртвый прокси без единой строчки в журнале. Ровно тот инцидент, ради
      // которого подсистема и написана — только в режиме по умолчанию.
      // Проба ходит в 127.0.0.1:$httpProxyPort, то есть в тот же порт, что и
      // системный прокси; кредов в этом режиме не ставится, 407 невозможен.
      startHealthWatch(aborted);
    } on TunStartException catch (e) {
      // Честная причина из лога sing-box вместо ложного «Подключено».
      AppLog.e('TUN не поднялся: $e');
      // #6 — если пользователь сам отменил (aborted), НЕ затираем его
      // «Отключено» статусом «Ошибка». Проверяем ДО _cleanup (он ++_generation).
      final wasAborted = aborted();
      await cleanup();
      if (!wasAborted) {
        setStatus(VpnConnectionState.error, message: e.toString());
      }
    } catch (e) {
      AppLog.e('Подключение не удалось: $e');
      final wasAborted = aborted();
      // Сеть могла быть ещё не готова (например, сразу после пробуждения) —
      // это как раз случай для повторной попытки.
      if (!wasAborted &&
          await scheduleRetry('не удалось подключиться: $e')) {
        return;
      }
      await cleanup();
      if (!wasAborted) {
        setStatus(VpnConnectionState.error,
            message: 'Не удалось подключиться: $e');
      }
    }
  }

  /// Погасить ядро (и, если [keepCapture] == false, снять захват трафика).
  ///
  /// При включённом kill switch между попытками восстановления захват НЕ снимается:
  /// системный прокси остаётся прописанным на мёртвый порт, TUN продолжает держать
  /// маршрут — приложения получают ошибку соединения вместо утечки мимо VPN.
  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    _statsTimer?.cancel();
    _statsTimer = null;
    _tunWatchdog?.cancel();
    _tunWatchdog = null;
    stopHealthWatch();
    await _exitWatch?.cancel();
    _exitWatch = null;
    await _stopCoreProcesses();

    // ⚠️ Форвардер гасим ВМЕСТЕ С ЯДРОМ, даже при keepCapture. Он ходит через
    // локальный SOCKS ядра, и без ядра его «основной» путь ведёт в никуда: он
    // ждал бы таймаут на каждом запросе и только замедлял бы переподключение.
    // Заново поднимется при следующем старте сессии, с новым портом.
    await _stopFallbackDns();

    if (keepCapture) return;

    if (_tunActive) {
      await _tunRouter.stop();
      _tunActive = false;
    }
    // Не сбрасываем чужой прокси (например, корпоративный): чистим только свой.
    if (_proxySet) {
      await SystemProxy.clear();
      _proxySet = false;
    }
  }

  /// Платформенная часть полной остановки. Счётчик поколений и таймер повтора
  /// живут в базе — [VpnEngineBase.cleanup] увеличивает поколение ДО вызова
  /// этого метода, поэтому проверки «была ли отмена» делаются раньше.
  @override
  Future<void> platformCleanup() async {
    _polling = false;
    _statsTimer?.cancel();
    _statsTimer = null;
    _tunWatchdog?.cancel();
    _tunWatchdog = null;
    stopHealthWatch();
    await _exitWatch?.cancel();
    _exitWatch = null;
    if (_tunActive) {
      await _tunRouter.stop();
      _tunActive = false;
    }
    // Не сбрасываем чужой прокси (например, корпоративный): чистим только свой.
    if (_proxySet) {
      await SystemProxy.clear();
      _proxySet = false;
    }
    await _stopCoreProcesses();
  }

  /// Гасим оба прокси-ядра: какое из них живо, зависит от протокола сессии.
  Future<void> _stopCoreProcesses() async {
    await _process?.stop();
    _process?.dispose();
    _process = null;
    await _singbox?.stop();
    _singbox?.dispose();
    _singbox = null;
  }

  /// Порт Clash API туннельного sing-box. Только петля, только для сторожа.
  static int get _tunApiPort => 10813 + AppEnv.portOffset;

  /// Сторож ЗАВИСШЕГО туннельного ядра.
  ///
  /// ⚠️ ЗАЧЕМ ОН ВООБЩЕ НУЖЕН — разница между «упало» и «зависло».
  ///
  /// Если sing-box ПАДАЕТ, Windows убирает за ним сама: WFP-сессия открыта
  /// динамической, адаптер заведён через `SwDeviceCreate`, поэтому фильтры,
  /// маршруты и сам адаптер снимаются вместе с процессом и сеть возвращается.
  /// Если же процесс ЗАВИС, не снимается ничего: адаптер с метрикой 0 и
  /// маршрутом `0.0.0.0/0` остаётся на месте и глотает весь трафик машины —
  /// включая помеченный «Прямо», которому туннель не нужен вовсе. Снаружи это
  /// «интернет пропал совсем», и само оно не чинится никогда.
  ///
  /// ⚠️ СТОРОЖ ВООРУЖАЕТСЯ ТОЛЬКО ПОСЛЕ ПЕРВОГО УСПЕШНОГО ОТВЕТА.
  ///
  /// Иначе он превращается в убийцу подключения: не смог подняться API (занят
  /// порт, старая сборка ядра, что угодно) — и сторож честно решает, что ядро
  /// зависло, гасит туннель, тот поднимается заново, API снова не отвечает.
  /// Вечный цикл переподключений, причём ровно у тех, у кого что-то не так с
  /// окружением. Поэтому `_tunLastAlive == null` означает «сторож ещё не
  /// вооружён», и в этом состоянии он не делает НИЧЕГО.
  ///
  /// Честная граница: это детектор зависшего ПРОЦЕССА, а не всякого затыка.
  /// HTTP-сервер API живёт в своей горутине, поэтому остановка обработки
  /// пакетов в стеке при живом API сторожем не ловится.
  void _startTunWatchdog(AppSettings settings, bool Function() aborted) {
    _tunWatchdog?.cancel();
    _tunLastAlive = null;
    final limit = settings.tunWatchdogSeconds;
    if (limit <= 0) return; // выключено пользователем

    final startedAt = DateTime.now();
    _tunWatchdog = Timer.periodic(const Duration(seconds: 5), (t) async {
      // Поколение сменилось — сессия уже другая, нам тут делать нечего.
      // Без этой проверки сторож прошлой сессии убивал бы туннель следующей.
      if (aborted() || !_tunActive) {
        t.cancel();
        return;
      }
      if (await _tunApiAlive()) {
        if (_tunLastAlive == null) {
          AppLog.i('Сторож туннеля вооружён: ядро отвечает по своему API');
        }
        _tunLastAlive = DateTime.now();
        return;
      }
      final since = _tunLastAlive;
      if (since == null) {
        // Ни одного ответа так и не было. Через минуту сдаёмся и говорим об
        // этом вслух: молчащий сторож хуже отсутствующего — на него надеются.
        if (DateTime.now().difference(startedAt).inSeconds > 60) {
          AppLog.w('Сторож туннеля НЕ вооружён: ядро ни разу не ответило по '
              'API на порту $_tunApiPort. Зависание отслеживаться не будет.');
          t.cancel();
        }
        return;
      }
      final silent = DateTime.now().difference(since).inSeconds;
      if (silent < limit) return;

      t.cancel();
      AppLog.e('Туннельное ядро не отвечает $silent с — считаю его зависшим. '
          'Снимаю туннель, чтобы система вернула сеть.');
      // Гасим ЖЁСТКО и вместе с захватом: смысл всей затеи в том, чтобы исчез
      // адаптер, иначе трафик так и останется в чёрной дыре. Kill switch здесь
      // не спорит — он защищает от утечки, а утекать при зависшем туннеле
      // нечему: наружу и так ничего не проходит.
      await teardownCore();
      if (!await scheduleRetry('туннельное ядро зависло')) {
        setStatus(VpnConnectionState.error,
            message: 'Туннельное ядро зависло, туннель снят');
      }
    });
  }

  /// Отвечает ли туннельное ядро по своему API. Короткий таймаут: сторож
  /// спрашивает раз в 5 с, и висеть на ответе ему нельзя.
  Future<bool> _tunApiAlive() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 700);
    try {
      final req =
          await client.getUrl(Uri.parse('http://127.0.0.1:$_tunApiPort/version'));
      if (singboxApiSecret.isNotEmpty) {
        req.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $singboxApiSecret');
      }
      final resp = await req.close().timeout(const Duration(milliseconds: 1500));
      await resp.drain<void>();
      // 401 тоже означает «живо»: ядро ответило, просто пароль не понравился.
      // Считать это зависанием — значит убивать рабочий туннель из-за своей же
      // ошибки в передаче секрета.
      return resp.statusCode == 200 || resp.statusCode == 401;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Счётчики трафика: у Xray — `api statsquery`, у sing-box — Clash API.
  void _startStatsPolling(String? executable, {bool singbox = false}) {
    final xrayStats = singbox
        ? null
        : XrayStats(executable: executable!, apiPort: ports.api);
    final singboxStats = singbox ? SingboxStats(apiPort: ports.api, secret: singboxApiSecret) : null;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      // Timer.periodic не сериализует async-колбэки: опрос Xray идёт через
      // Process.run и на нагруженной машине легко перекрывает секунду, а два
      // такта разом дают неверную разницу по времени.
      if (_polling) return;
      _polling = true;
      try {
      final snap =
          await (singboxStats?.query() ?? xrayStats!.query());
      // Опрос не удался — такт ПРОПУСКАЕМ целиком. Раньше сюда приезжал ноль,
      // и он затирал базу: скорость на следующем удачном опросе взлетала до
      // «всего трафика за секунду», а счётчик сессии удваивался.
      if (snap == null) return;
      final now = DateTime.now();
      final dt = now.difference(_lastSampleTime).inMilliseconds / 1000.0;
      final upSpeed = dt > 0 ? ((snap.uplink - _lastSnapshot.uplink) / dt).round() : 0;
      final downSpeed =
          dt > 0 ? ((snap.downlink - _lastSnapshot.downlink) / dt).round() : 0;
      _lastSnapshot = snap;
      _lastSampleTime = now;

      emitStats(TrafficStats(
        uplinkBytes: snap.uplink,
        downlinkBytes: snap.downlink,
        uplinkSpeed: upSpeed < 0 ? 0 : upSpeed,
        downlinkSpeed: downSpeed < 0 ? 0 : downSpeed,
      ));
      } finally {
        _polling = false;
      }
    });
  }

  /// Конфиги ядер лежат рядом, но в разных файлах: TUN-инстанс sing-box пишет
  /// свой (`singbox_config.json`), поэтому прокси-конфиг — `singbox_proxy.json`.
  /// DNS-сервер физического адаптера — резолвер для доменов «Прямо».
  ///
  /// Нужен явным адресом: транспорт `local` в sing-box на Windows означает
  /// системный резолвер, а тот под поднятым TUN закольцовывается сам на себя,
  /// и домен «Прямо» не резолвится вовсе (подтверждено живым тестом).
  ///
  /// Берём ПЕРВЫЙ адрес не-туннельного адаптера. Свой туннель узнаём по
  /// собственным адресам (172.19.0.x / fdfe:dcba:9876::), а не по имени: имя
  /// адаптера на Windows приходит не то — на этом уже обжигались в 0.8.3.
  /// Не нашли — `null`, поведение остаётся прежним.
  /// Реальность IPv6: есть ли он наружу.
  ///
  /// Логируем РЕШЕНИЕ, а не только факт: молчаливое урезание возможностей —
  /// худший вид поведения. Пользователь включил IPv6 в настройках, а получил
  /// туннель без него: он должен видеть, почему.
  Future<bool> _ipv6Reality() async {
    final has = await Ipv6Support.hasGlobalIpv6();
    if (!has) {
      AppLog.i('IPv6 наружу не найден — в туннеле он выключен, иначе '
          'двустековые сайты упирались бы в «unreachable network»');
    }
    return has;
  }

  /// Отвечает ли DNS-сервер. Проверяем ДО подъёма туннеля — потом поздно.
  ///
  /// Обычный запрос A-записи по UDP: если за отведённое время ответа нет,
  /// резолвер считаем непригодным. Секунды хватает — это адрес из локальной
  /// сети или адрес провайдера, дальше идти не нужно.
  static Future<bool> _dnsReachable(String ip) async {
    RawDatagramSocket? sock;
    try {
      final addr = InternetAddress.tryParse(ip);
      if (addr == null) return false;
      sock = await RawDatagramSocket.bind(
          addr.type == InternetAddressType.IPv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4,
          0);
      // Минимальный запрос: A-запись для example.com.
      final query = <int>[
        0x12, 0x34, // id
        0x01, 0x00, // стандартный запрос, рекурсия
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        7, ...'example'.codeUnits, 3, ...'com'.codeUnits, 0,
        0x00, 0x01, 0x00, 0x01,
      ];
      sock.send(query, addr, 53);
      final got = Completer<bool>();
      sock.listen((e) {
        if (e == RawSocketEvent.read && !got.isCompleted) {
          final d = sock?.receive();
          if (d != null && d.data.length > 2) got.complete(true);
        }
      });
      return await got.future
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      sock?.close();
    }
  }

  /// Поднять локальный DNS-форвардер с запасным резолвером и вернуть его порт.
  /// 0 — форвардер не нужен или не поднялся.
  ///
  /// ⚠️ Нужен ТОЛЬКО при «DNS всех приложений через туннель». Без этой галочки
  /// прямой трафик резолвится локально и так, и лишнее звено в пути DNS было бы
  /// чистым риском без выгоды.
  ///
  /// Сбой подъёма НЕ фатален: без форвардера `dns.final` останется прежним
  /// (`dns-proxy`), то есть вернётся поведение до этой правки. Диагностика не
  /// имеет права мешать подключению.
  Future<int> _startFallbackDns(AppSettings s) async {
    await _stopFallbackDns();
    if (s.captureMode != CaptureMode.tun || !s.tunnelDnsForAll) return 0;
    final local = await _systemDnsServer();
    if (local == null || local.isEmpty) {
      AppLog.w('Запасной DNS не поднят: локальный резолвер не определён');
      return 0;
    }
    final upstream = _dnsUpstreamFor(s);
    // ⚠️ ФОРВАРДЕР УМЕЕТ ТОЛЬКО ЛИТЕРАЛЬНЫЙ IPv4. Рукопожатие SOCKS требует
    // адрес байтами; на домене или IPv6 оно молча возвращает false, и КАЖДЫЙ
    // запрос уходит в запас — то есть весь DNS к провайдеру, при внешне
    // исправной работе. Лучше честно не поднимать форвардер: тогда работает
    // прежнее поведение, и оно хотя бы понятное.
    final ip = InternetAddress.tryParse(upstream);
    if (ip == null || ip.type != InternetAddressType.IPv4) {
      AppLog.w('Запасной DNS не поднят: резолвер «$upstream» не литеральный '
          'IPv4-адрес. DNS работает как раньше — целиком через туннель.');
      return 0;
    }
    try {
      final srv = DnsFallbackServer(
        socksPort: ports.socks,
        // Те же креды, что у инбаунда: без них рукопожатие SOCKS отвергается,
        // и форвардер молча уходил бы в запас на КАЖДОМ запросе — то есть
        // весь DNS к провайдеру при внешне исправной работе.
        socksUser: localInboundUser,
        socksPassword: localInboundPassword,
        tunnelDns: upstream,
        localDns: local,
      );
      await srv.start();
      _fallbackDns = srv;
      return srv.port;
    } catch (e) {
      AppLog.w('Запасной DNS не поднялся: $e');
      return 0;
    }
  }

  Future<void> _stopFallbackDns() async {
    final srv = _fallbackDns;
    _fallbackDns = null;
    if (srv == null) return;
    if (srv.queryCount > 0) {
      AppLog.i('Запасной DNS: запросов ${srv.queryCount}, '
          'туннель промолчал ${srv.fallbackCount}, '
          'ушло к провайдеру ${srv.fallbackAnsweredCount}');
    }
    await srv.stop();
  }

  /// Тот же апстрим, что построитель кладёт в `dns-proxy`, и разобранный ТЕМ
  /// ЖЕ кодом — иначе строки расходятся и форвардер спрашивает не тот адрес.
  static String _dnsUpstreamFor(AppSettings s) =>
      SingboxConfigBuilder.dnsHostOf(
          s.dnsMode == DnsMode.custom ? s.dnsCustomServer : '1.1.1.1');

  Future<String?> _systemDnsServer() async {
    try {
      // ⚠️ БЕЗ PowerShell. Прежний `Get-DnsClientServerAddress` — командлет того
      // же семейства CIM, что и изгнанный отсюда `Get-NetAdapter`: на машине
      // владельца он упирался в пятисекундный таймаут, и домены «Прямо»
      // переставали резолвиться молча. Живой тест в VM это подтвердил.
      final list = AdapterDnsWindows.servers()
          // Адреса самого туннеля и заглушки резолвером быть не могут.
          .where((e) => !e.startsWith('172.19.0.'))
          .where((e) => !e.startsWith('fdfe:dcba:9876'))
          .where((e) => e != '0.0.0.0' && e != '127.0.0.1' && e != '::1')
          .toList();

      // ⚠️ Мало НАЙТИ адрес — надо убедиться, что он отвечает.
      //
      // Система охотно отдаёт DNS виртуальных адаптеров (Hyper-V, WSL, Docker).
      // В тестовой VM первым шёл 172.19.128.1 с адаптера Hyper-V: адрес есть,
      // порт 53 закрыт наглухо. Взяв его, мы получали резолвер, который не
      // отвечает никогда, и КАЖДЫЙ домен с правилом «Прямо» переставал
      // открываться — притом что настройка выглядела рабочей.
      for (final ip in list) {
        if (await _dnsReachable(ip)) {
          AppLog.i('Резолвер для «Прямо»: $ip');
          return ip;
        }
        AppLog.w('DNS $ip не отвечает — пробую следующий');
      }
      if (list.isEmpty) {
        AppLog.w('DNS физического адаптера не найден — домены «Прямо» '
            'будут резолвиться системным резолвером');
        return null;
      }
      AppLog.w('Ни один DNS адаптера не ответил — «Прямо» пойдёт системным '
          'резолвером, и домены могут не открыться');
      return null;
    } catch (e) {
      AppLog.w('Не удалось определить DNS адаптера: $e');
      return null;
    }
  }

  Future<String> _writeConfigJson(String json, {bool singbox = false}) async {
    final dir = await AppPaths.supportDir();
    final name = singbox ? 'singbox_proxy.json' : 'xray_config.json';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(json);
    return file.path;
  }

}
