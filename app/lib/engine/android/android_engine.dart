import '../windows/xray_stats.dart';
import '../windows/singbox_stats.dart';
import '../../core/models/traffic_stats.dart';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/models/vpn_server.dart';
import '../../core/models/vpn_status.dart';
import '../../core/platform/app_log.dart';
import '../../core/probe/proxy_probe.dart';
import '../../core/platform/ipv6_support.dart';
import '../../core/platform/app_paths.dart';
import '../../core/settings/split_tunnel.dart';
import '../../core/singbox/singbox_config_builder.dart';
import '../../core/singbox/singbox_outbound_factory.dart';
import '../engine_base.dart';

/// Движок Android: туннель поднимает `libbox` (sing-box) внутри
/// `SilentGateVpnService`.
///
/// Платформо-независимая половина (сессия, поколения, автовосстановление,
/// выбор конфига и ядра) живёт в [VpnEngineBase] и общая с Windows. Здесь
/// остаётся только мост к нативному сервису.
///
/// Дескриптор туннеля передаётся инверсией управления: ядро зовёт
/// `PlatformInterface.openTun`, сервис строит `VpnService.Builder` и
/// возвращает fd. Подробности — `tools/build-android-cores.md`.
///
/// ## Как выбирается ядро
///
/// Ровно как на Windows — через `configFor` в базе: полный конфиг (правка
/// пользователя или панельный профиль «Авто» с `balancers`/`burstObservatory`)
/// поднимает Xray, а туннель заворачивает трафик в его локальный SOCKS.
/// Обычный сервер sing-box обслуживает сам, и тогда промежуточный SOCKS не
/// нужен: outbound встраивается прямо в конфиг туннеля.
///
/// Оба ядра живут в ОДНОМ AAR: раздельные gomobile-библиотеки конфликтуют
/// общим Go-рантаймом (`go.Seq`), и собрать их вместе иначе нельзя
/// (`tools/build-android-cores.md`).
class AndroidEngine extends VpnEngineBase {
  AndroidEngine({super.ports}) {
    _events.receiveBroadcastStream().listen(_onNativeEvent);
  }

  /// Порт и пароль Clash API — счётчиков трафика туннеля.
  ///
  /// ⚠️ НЕ [XrayPorts.api] (10085). На Windows там сидит api-инбаунд Xray, но
  /// это ДРУГОЙ процесс; на Android оба ядра живут в ОДНОМ, и `SilentGateVpnService`
  /// поднимает Xray ПЕРВЫМ (иначе sing-box успел бы отправить трафик в мёртвый
  /// SOCKS). Xray занимал 10085 своим dokodemo-door, sing-box просил тот же порт
  /// под clash_api и падал с «address already in use» — а `startTunnel` на любое
  /// исключение снимает туннель целиком. То есть «Авто (лучший сервер)»,
  /// панельные профили «🎬 Авто …» и вообще всё, что идёт через Xray, не
  /// подключалось ВОВСЕ, а обычный одиночный VLESS работал (там Xray не
  /// поднимается) — поэтому на простом тесте дефект не показывался.
  /// Ровно тот же урок уже выучен на 10809 (см. [probeInboundPort]).
  ///
  /// ⚠️ Пароль генерируется на КАЖДУЮ сессию. На телефоне локальный порт видит
  /// любое установленное приложение, а sing-box без `secret` отдаёт метаданные
  /// соединений всем подряд и с CORS `*` — то есть и любой открытой странице.
  static const clashApiPort = 10812;

  /// ⚠️ НЕ `final`, и это не мелочь. Пароль обязан пережить смерть изолята.
  ///
  /// На Android `VpnService` живёт дольше интерфейса: пользователь смахнул
  /// приложение — туннель работает, открыл заново — поднимается НОВЫЙ изолят.
  /// Пока пароль генерировался в конструкторе, после такого возврата
  /// [adoptRunningTunnel] опрашивал Clash API с паролем, которого туннель
  /// никогда не видел: ядро отвечало 401, такт опроса пропускался ВСЕГДА, и на
  /// экране висели «0 Б / 0 Б» и нулевая скорость при идущей закачке. Это
  /// штатный, а не редкий сценарий Android.
  ///
  /// Поэтому пароль сохраняется рядом с данными приложения и перечитывается при
  /// подхвате. Каталог приложения на Android недоступен другим приложениям —
  /// защита от них, ради которой пароль и заведён, не слабеет.
  String _apiSecret = _randomSecret();

  static String _randomSecret() {
    final rnd = Random.secure();
    return List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  /// Файл с паролем текущего туннеля.
  static Future<File> _secretFile() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}clash_api_secret');
  }

  /// Новый пароль на новую сессию + запись рядом с данными приложения.
  Future<void> _rotateApiSecret() async {
    _apiSecret = _randomSecret();
    try {
      await (await _secretFile()).writeAsString(_apiSecret, flush: true);
    } catch (e) {
      // Не фатально: подключение важнее счётчиков. Потеряется только трафик
      // после возврата в приложение — и об этом будет строка в логе.
      AppLog.w('Не удалось сохранить пароль Clash API: $e');
    }
  }

  /// Пароль туннеля, поднятого прошлым запуском интерфейса.
  Future<bool> _restoreApiSecret() async {
    try {
      final f = await _secretFile();
      if (!await f.exists()) return false;
      final v = (await f.readAsString()).trim();
      if (v.isEmpty) return false;
      _apiSecret = v;
      return true;
    } catch (e) {
      AppLog.w('Не удалось прочитать пароль Clash API: $e');
      return false;
    }
  }

  Timer? _statsTimer;
  XrayTrafficSnapshot _lastSnap = const XrayTrafficSnapshot(0, 0);
  DateTime _lastSnapAt = DateTime.now();
  bool _statsBusy = false;

  /// Опрос счётчиков раз в секунду.
  ///
  /// ⚠️ Такт, в котором опрос не удался, ПРОПУСКАЕТСЯ целиком. Приехавший ноль
  /// затёр бы базу, и на следующем удачном опросе скорость взлетела бы до
  /// «весь трафик за одну секунду», а счётчик сессии удвоился. Ровно на этом
  /// уже обжигались в Windows-движке.
  void _startStatsPolling() {
    _statsTimer?.cancel();
    _lastSnap = const XrayTrafficSnapshot(0, 0);
    _lastSnapAt = DateTime.now();
    final stats = SingboxStats(apiPort: clashApiPort, secret: _apiSecret);
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_statsBusy) return;
      _statsBusy = true;
      try {
        final snap = await stats.query();
        if (snap == null) return;
        final now = DateTime.now();
        final dt = now.difference(_lastSnapAt).inMilliseconds / 1000.0;
        final up = dt > 0 ? ((snap.uplink - _lastSnap.uplink) / dt).round() : 0;
        final down =
            dt > 0 ? ((snap.downlink - _lastSnap.downlink) / dt).round() : 0;
        _lastSnap = snap;
        _lastSnapAt = now;
        emitStats(TrafficStats(
          uplinkBytes: snap.uplink,
          downlinkBytes: snap.downlink,
          uplinkSpeed: up < 0 ? 0 : up,
          downlinkSpeed: down < 0 ? 0 : down,
        ));
      } finally {
        _statsBusy = false;
      }
    });
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  /// Порт инбаунда для проб. НЕ 10809: там при панельном профиле садится Xray,
  /// и совпадение порта не давало ядру стартовать вовсе.
  static const probeInboundPort = 10811;

  /// Сервис-чипы и проба активного сервера ходят в наш собственный инбаунд.
  @override
  int get httpProxyPort => probeInboundPort;

  static const _channel = MethodChannel('lol.silentgate/vpn');
  static const _events = EventChannel('lol.silentgate/vpn_events');

  /// Идёт ли сейчас наш собственный подъём: нужно, чтобы не принять
  /// подтверждение «сервис запущен» за неожиданное падение.
  bool _starting = false;

  /// Опции и правила ЖИВОГО конфига — чтобы заглушка kill switch совпала с ним
  /// поле в поле. Разойдутся хоть в одном (MTU, списки пакетов) — `VpnService`
  /// пересоздаст интерфейс, и на этот миг трафик пойдёт мимо VPN.
  TunOptions? _liveOptions;
  SplitTunnelConfig _liveSplit = const SplitTunnelConfig();

  /// Подхватить туннель, поднятый ПРОШЛЫМ запуском интерфейса.
  ///
  /// ⚠️ На Android интерфейс и туннель живут врозь: `VpnService` переживает
  /// смерть Activity, а состояние движка — нет. Без этой проверки приложение
  /// после возврата показывало «Отключено» при РАБОТАЮЩЕМ VPN, и нажатие
  /// Connect поднимало ВТОРОЙ сеанс поверх живого. Нативная сторона умела
  /// отвечать на `isRunning` с самого начала — её просто никто не спрашивал.
  ///
  /// Сессии здесь нет (конфиг остался в умершем изоляте), поэтому честно
  /// показываем «подключено», но без данных о сервере: пользователь видит
  /// правду и может переподключиться сам.
  @override
  Future<void> adoptRunningTunnel() async {
    try {
      final running = await _channel.invokeMethod<bool>('isRunning') ?? false;
      if (!running || status.isConnected) return;
      AppLog.i('Подхвачен туннель, поднятый прошлым запуском интерфейса');
      // Пароль Clash API — от ТОГО запуска: свежесгенерированный туннель не
      // знает, и счётчики навсегда остались бы нулями (401 на каждый такт).
      if (!await _restoreApiSecret()) {
        AppLog.w('Пароль Clash API прошлой сессии не найден — '
            'счётчики трафика будут пустыми до переподключения');
      }
      markConnected();
      setStatus(VpnConnectionState.connected);
      _startStatsPolling();
    } catch (e) {
      AppLog.w('Не удалось спросить состояние туннеля: $e');
    }
  }

  @override
  Future<void> startSession() async {
    final session = this.session;
    if (session == null) return;

    final gen = newGeneration();
    bool aborted() => isStale(gen);

    setStatus(VpnConnectionState.connecting);
    // Пароль — на КАЖДУЮ сессию, и он же кладётся на диск: следующий запуск
    // интерфейса подхватит этот туннель и должен уметь его опросить.
    await _rotateApiSecret();
    // ⚠️ Инбаунд проб закрывается паролем на ту же сессию. На Android loopback
    // НЕ изолирован: без пароля к 127.0.0.1:10811 подключается любое
    // установленное приложение и получает наш VPN целиком — выходной IP, квоту
    // подписки и обход раздельного туннелирования, включая приложения, которым
    // пользователь поставил «Блок» (правило `probe-in → proxy` стоит выше
    // пользовательских). Креды только в памяти: на диск и в логи не пишутся.
    ProxyProbe.user = 'sg';
    ProxyProbe.password = _randomSecret();
    // Те же соображения — для локальных инбаундов Xray (10808/10809): они
    // поднимаются при панельных профилях и без пароля так же открыты всем.
    localInboundUser = 'sg';
    localInboundPassword = _randomSecret();

    try {
      // Ядро выбирается ровно так же, как на Windows (configFor в базе):
      // полный конфиг (правка пользователя или панельный профиль «Авто») —
      // всегда Xray; обычный сервер sing-box поднимает сам.
      // Резолв — ДО сборки конфига: адрес нужен и правилу «мимо туннеля»
      // (ip_cidr), и самому outbound'у. С доменным именем ядро пошло бы за
      // адресом уже из-под поднятого туннеля.
      final hosts = await resolveServerHosts(session.servers);
      if (aborted()) return;
      final serverIps = hosts.values.expand((e) => e).toSet().toList();
      final resolvedIps = VpnEngineBase.pickOneIpPerHost(hosts);

      // ⚠️ Сессия из НЕСКОЛЬКИХ серверов — это «Авто (лучший сервер)»: база
      // уже собрала конфиг с балансировщиком (Xray `balancers` +
      // `burstObservatory`) либо с `urltest` (sing-box) по ВСЕМ серверам и
      // положила его в `session.configJson`. Пересобирать его из
      // `servers.first`, как делалось здесь, значило подключаться к ПЕРВОМУ
      // серверу списка и выдавать это за автовыбор: ни балансировщика, ни
      // замеров, ни переключения на быстрый узел. Windows этот конфиг берёт
      // (`windows_engine.dart:56`), Android — молча выбрасывал.
      final multi = session.servers.length > 1;
      final cfg = multi
          ? (json: session.configJson, core: session.core, full: true)
          : configFor(session.servers.first, session.options,
              resolvedIps: resolvedIps);
      // ⚠️ Признак «поднимать Xray» — ФАКТ полного конфига, а не протокол
      // первого сервера.
      //
      // Прежнее условие (`multi || !supports(first)`) отбрасывало панельный
      // профиль «Авто …» и правку из JSON-редактора для ЛЮБОГО сервера, чей
      // протокол умеет sing-box, — то есть практически для всех серверов
      // Remnawave: у панельного профиля `protocol` берётся с первого
      // прокси-outbound'а и обычно равен vless, а `supports('vless')` == true.
      // Собранный базой конфиг молча выбрасывался, вместо него в туннель
      // встраивался outbound ОДНОГО (первого) узла профиля. Подключение при
      // этом успешно, трафик идёт через VPN — поэтому дефект и не бросался в
      // глаза: молча пропадали балансировщик, `burstObservatory`, панельный
      // RU-routing и сама правка пользователя.
      final viaXray = cfg.core == ProxyCore.xray &&
          (cfg.full || !SingboxOutboundFactory.supports(session.servers.first));

      // Когда сервер поднимает Xray, туннель заворачивает трафик в его
      // локальный SOCKS — как на Windows. Когда справляется sing-box, лишний
      // переход не нужен, и outbound встраивается прямо в конфиг туннеля.
      final liveOptions = TunOptions.fromSettings(
          session.options.settings,
          serverIps: serverIps,
          // Имена ВСЕЙ инфраструктуры — резолвим только напрямую.
          serverDomains: knownServerDomains,
          android: true,
          blockPagePort: await startBlockPage(session.options),
          // Резолвер для «Прямо». Пусто → прежнее поведение (`local`), то
          // есть домен не отрезолвится: лучше знать об этом из лога, чем
          // молча получить «сайт не открывается».
          directDnsUpstream: await _directDns(),
          ipv6Available: await _ipv6Reality(),
          // Ядро пишет свой лог САМО: перехватить его вывод здесь нечем —
          // это библиотека в нашем процессе, а redirectStderr ловит только
          // паники Go. Без этого «туннель поднят, трафика нет» не
          // диагностируется вообще.
          logOutput: '${(await AppPaths.supportDir()).path}'
              '${Platform.pathSeparator}singbox.log',
          // Счётчики трафика туннеля: без них цифра под кнопкой стояла на нуле,
          // что бы ни происходило. Пароль — на сессию: этот порт виден любому
          // приложению на телефоне.
          clashApiPort: clashApiPort,
          clashApiSecret: _apiSecret,
      );
      _liveOptions = liveOptions;
      _liveSplit = session.options.split;

      final tunJson = SingboxConfigBuilder(
        xraySocksPort: ports.socks,
        probePort: probeInboundPort,
        probeUser: ProxyProbe.user,
        probePassword: ProxyProbe.password,
        // Туннель ходит в соседний Xray через его локальный SOCKS — с тем же
        // паролем, что стоит на инбаунде. Разойдутся — трафик встанет.
        xraySocksUser: localInboundUser,
        xraySocksPassword: localInboundPassword,
        options: liveOptions,
        // При нескольких серверах на sing-box собранный базой конфиг уже
        // содержит `urltest` по всем узлам — встраивать outbound одного
        // сервера нельзя, это снова свело бы автовыбор к первому.
        proxyOutboundGroup: (!viaXray && cfg.full)
            ? _outboundsOf(cfg.json)
            : null,
        proxyOutbound: (viaXray || cfg.full)
            ? null
            : SingboxOutboundFactory.build(
                session.servers.first,
                resolvedIp:
                    resolvedIps[session.servers.first.address.trim()],
              ),
      ).buildJson(session.options.split);

      if (aborted()) return;

      _starting = true;
      await _channel.invokeMethod<void>('start', {
        'config': tunJson,
        if (viaXray) 'xray_config': cfg.json,
      });
      _starting = false;

      // Пользователь мог отключиться, пока шло согласие на VPN.
      if (aborted()) {
        await _channel.invokeMethod<void>('stop');
        return;
      }

      markConnected();
      setStatus(VpnConnectionState.connected);
      _startStatsPolling();
    } on PlatformException catch (e) {
      _starting = false;
      // Отказ в согласии — не ошибка подключения, а решение пользователя:
      // повторять его автоматически бессмысленно.
      final wasAborted = aborted();
      await cleanup();
      if (wasAborted) return;
      if (e.code == 'consent_denied') {
        setStatus(VpnConnectionState.error, message: e.message);
        return;
      }
      if (await scheduleRetry('не удалось подключиться: ${e.message}')) return;
      setStatus(VpnConnectionState.error, message: e.message);
    } catch (e) {
      _starting = false;
      final wasAborted = aborted();
      await cleanup();
      if (wasAborted) return;
      if (await scheduleRetry('не удалось подключиться: $e')) return;
      setStatus(VpnConnectionState.error, message: '$e');
    }
  }

  /// Событие от сервиса: туннель поднялся, упал или его отобрала система.
  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final running = event['running'] == true;
    final error = (event['error'] as String?)?.trim();

    if (running || _starting) return;
    if (!status.isConnected && status.state != VpnConnectionState.connecting) {
      return;
    }

    // ⚠️ КНОПКА «ОТКЛЮЧИТЬ» В ШТОРКЕ — ЭТО ОТКЛЮЧЕНИЕ, А НЕ ПАДЕНИЕ ЯДРА.
    //
    // Раньше признака не было, и такая остановка приходила сюда неотличимой от
    // смерти ядра (`running=false`, `error=null`). Дальше — `onCoreDied` →
    // `scheduleRetry` → автоповтор, включённый по умолчанию, — и VPN
    // поднимался обратно через 0,8 с. То есть самый привычный способ его
    // выключить (шторка, приложение свёрнуто) делал ровно обратное. При
    // выключенном автоповторе вместо этого показывалась ложная ошибка
    // «Ядро sing-box остановилось (код 0)», уводившая разбор в сторону.
    if (event['byUser'] == true) {
      AppLog.i('Туннель снят пользователем из уведомления');
      unawaited(disconnect()); // ставит _userStopped и гасит статус штатно
      return;
    }

    // Сюда попадает и onRevoke (другой VPN перехватил туннель) — пути,
    // которого на Windows нет вовсе.
    AppLog.e('VPN-сервис остановился: ${error ?? 'без причины'}');

    // Текст из нативного слоя ОБЯЗАН доехать до пользователя. Без этого
    // подключение просто «вылетало» молча, и причину нельзя было назвать
    // даже по логам приложения.
    unawaited(_reportStop(error));
  }

  Future<void> _reportStop(String? error) async {
    if (error == null || error.isEmpty) {
      await onCoreDied(0);
      return;
    }
    // Причина известна — показываем её вместо безымянного «ядро остановилось».
    // Повторять попытку смысла нет: конфиг тот же, результат будет тот же.
    await cleanup();
    setStatus(VpnConnectionState.error, message: error);
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    // Ядро уходит — счётчики уходят вместе с ним. Иначе таймер продолжал бы
    // раз в секунду стучаться в мёртвый порт, а на экране висели бы цифры
    // прошлой сессии, выдавая себя за текущие.
    _stopStatsPolling();
    // Kill switch: между попытками переподключения туннель ОСТАЁТСЯ поднятым,
    // но никуда не ведёт — трафик фейлится, а не утекает мимо VPN.
    //
    // Раньше здесь сервис гасился целиком, и на время всех попыток (backoff до
    // 20 с, до 8 попыток — это минуты) весь трафик шёл напрямую. Настройка при
    // этом была включена и печаталась в отчёте: пользователь считал себя
    // защищённым, а защиты не было вовсе.
    //
    // libbox владеет дескриптором сам, поэтому «погасить ядро, оставив fd» тут
    // невозможно. Вместо этого перезагружаем ядро конфигом-заглушкой: тот же
    // туннель, те же маршруты, но весь трафик уходит в reject.
    if (keepCapture) {
      try {
        await _channel.invokeMethod<void>('start', {'config': _blackholeJson()});
        AppLog.i('Kill switch: туннель удержан, трафик блокируется');
        // Сказать об этом в шторке. Приложение в этот момент чаще всего закрыто,
        // и другого способа объяснить пропавший интернет у нас нет: без
        // объяснения человек решит, что сломалось, и выключит VPN — то есть
        // сделает ровно то, от чего защита оберегала.
        try {
          await _channel.invokeMethod<void>('showBlocked');
        } catch (_) {
          // Уведомление не критично: туннель удержан, это главное.
        }
        return;
      } catch (e) {
        // Не смогли удержать — честнее погасить, чем оставить неизвестное
        // состояние: иначе туннель мог бы жить со СТАРЫМ конфигом.
        AppLog.w('Kill switch: не удалось удержать туннель ($e), гашу');
      }
    }
    await _stopService();
  }

  /// Туннель, который никуда не ведёт: маршруты на месте, весь трафик в reject.
  ///
  /// Собирается тем же билдером, чтобы совпадали адреса, MTU и списки пакетов —
  /// иначе система пересоздала бы интерфейс, и на этот миг трафик пошёл бы
  /// мимо VPN, то есть ровно то, что kill switch и предотвращает.
  String _blackholeJson() {
    // Из ТЕХ ЖЕ опций, что и живой конфиг: иначе не совпадут MTU и пакетные
    // списки, система пересоздаст интерфейс, и в этот миг трафик уйдёт мимо
    // VPN — ровно то окно, которое kill switch и закрывает.
    final base = _liveOptions ?? const TunOptions(platformTun: true);
    return SingboxConfigBuilder(
      xraySocksPort: ports.socks,
      // В заглушке проб нет: слушать порт, из которого всё равно ничего не
      // выйдет, незачем — и это лишняя поверхность.
      options: base.asBlackhole(),
    ).buildJson(_liveSplit);
  }

  @override
  Future<void> platformCleanup() async => _stopService();

  Future<void> _stopService() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      AppLog.w('Не удалось остановить VPN-сервис: $e');
    }
  }

  /// Прокси-outbound'ы из конфига, собранного базой (без служебного `direct`).
  ///
  /// Для «Авто» база строит полноценный конфиг прокси-ядра: узлы + группа
  /// `urltest` с тегом `proxy`. Туннелю нужны именно они — свой `direct` он
  /// добавляет сам, а два одноимённых outbound'а ядро отвергает.
  static List<Map<String, dynamic>>? _outboundsOf(String configJson) {
    try {
      final map = jsonDecode(configJson);
      if (map is! Map) return null;
      final outs = map['outbounds'];
      if (outs is! List) return null;
      final list = outs
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((e) => e['tag'] != 'direct')
          .toList();
      return list.isEmpty ? null : list;
    } catch (e) {
      AppLog.w('Не удалось разобрать конфиг автовыбора: $e');
      return null;
    }
  }

  /// DNS физической сети — для доменов с правилом «Прямо».
  ///
  /// ⚠️ Без него ядро оставляет транспорт `local`, и такие домены не
  /// резолвятся ВООБЩЕ. Проверено живым запуском в эмуляторе: сайт «Туннель»
  /// открывался, «Блок» блокировался, а «Прямо» отвечал «No address
  /// associated with hostname». Тот же дефект чинили на Windows.
  /// Реальность IPv6: есть ли он наружу.
  ///
  /// Логируем РЕШЕНИЕ, а не только факт: молчаливое урезание возможностей —
  /// худший вид поведения. Пользователь включил IPv6 в настройках, а получил
  /// туннель без него — он должен видеть, почему.
  static Future<bool> _ipv6Reality() async {
    final has = await Ipv6Support.hasGlobalIpv6();
    if (!has) {
      AppLog.i('IPv6 наружу не найден — в туннеле он выключен, иначе '
          'двустековые сайты упирались бы в «unreachable network»');
    }
    return has;
  }

  static Future<String?> _directDns() async {
    try {
      final dns = await const MethodChannel('lol.silentgate/device')
          .invokeMethod<String>('directDns');
      final v = (dns ?? '').trim();
      return v.isEmpty ? null : v;
    } catch (e) {
      AppLog.w('DNS физической сети недоступен: $e');
      return null;
    }
  }
}
