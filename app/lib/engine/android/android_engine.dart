import '../windows/xray_stats.dart';
import '../windows/singbox_stats.dart';
import '../../core/models/traffic_stats.dart';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/models/engine_notice.dart';
import '../../core/models/vpn_server.dart';
import '../../core/models/vpn_status.dart';
import '../../core/platform/app_log.dart';
import '../../core/probe/proxy_probe.dart';
import '../../core/platform/ipv6_support.dart';
import '../../core/platform/app_paths.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/split_tunnel.dart';
import '../../core/singbox/singbox_config_builder.dart';
import '../../core/xray/override_normalizer.dart';
import '../../core/xray/xray_config_builder.dart';
import '../../core/singbox/singbox_outbound_factory.dart';
import '../../core/singbox/exit_outbounds.dart';
import '../../core/geo/geo_assets.dart';
import '../../core/xray/geodata_fallback.dart';
import '../../core/net/dns_fallback_server.dart';
import '../engine_base.dart';
import '../vpn_engine.dart';

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
  /// Локальный DNS-форвардер с запасным резолвером (см. [startFallbackDns]).
  DnsFallbackServer? _fallbackDns;

  /// Только для теста: ЧЕЙ форвардер сейчас в поле. Нужен именно экземпляр —
  /// «устаревший запуск снёс форвардер живой сессии» отличается от исправного
  /// поведения ровно тем, тот же это объект или уже другой.
  @visibleForTesting
  DnsFallbackServer? get fallbackDns => _fallbackDns;

  /// Поколение запуска, которое ВЛАДЕЕТ поднятым форвардером.
  ///
  /// ⚠️ ТОТ ЖЕ КЛАСС, ЧТО У ТУННЕЛЯ И ПРОКСИ НА WINDOWS, И НА ANDROID ОН
  /// ОСТАВАЛСЯ ОТКРЫТЫМ. Форвардер поднимается внутри сборки [TunOptions], то
  /// есть после нескольких await'ов — резолва серверов (таймаут 5 с на имя) и
  /// запроса DNS физической сети через нативный канал. К этому моменту запуск
  /// мог устареть, а [startFallbackDns] первой же строкой гасил ТО, ЧТО ЛЕЖИТ
  /// В ПОЛЕ: форвардер уже НОВОЙ, живой сессии. Дальше он поднимал свой и
  /// записывал его в то же поле, после чего уходил по `aborted()` — и свой
  /// оставлял слушать порт навсегда.
  ///
  /// У живой сессии при этом `dns.final` указывает на порт, которого больше
  /// нет: при «весь DNS через туннель» имена перестают резолвиться у ВСЕХ
  /// приложений телефона, и само это не чинится. Достижимо просто: запуск A
  /// стоит в таймауте резолва, человек жмёт «Отключить» и «Подключить», запуск
  /// B берёт адрес из кэша и обгоняет A.
  int _fallbackDnsOwnerGen = 0;

  /// ⚠️ Счётчики здесь берутся из Clash API sing-box (порт 10812, с паролем),
  /// а `statsquery` Xray не используется НИ РАЗУ — единственный вызов
  /// `XrayStats` живёт в Windows-движке. Поэтому api-инбаунд Xray на Android не
  /// поднимаем вовсе: он слушает без аутентификации (Xray её для `api` не
  /// поддерживает), а loopback на Android виден любому установленному
  /// приложению — детекторы VPN ищут именно этот порт.
  @override
  bool get readsXrayStats => false;

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
    // ⚠️ ТОЛЬКО ПРОКСИРОВАННЫЙ. На Windows опрашивается отдельное прокси-ядро,
    // а туннель считается своим; на Android ядро ОДНО, и глобальные счётчики
    // Clash API включают всё, что ушло мимо VPN, — правила «Прямо», bypassLan,
    // локальный DNS. Пользователь качал 5 ГБ заведомо мимо туннеля и видел их
    // под кнопкой, рядом с остатком по подписке.
    final stats = SingboxStats(
        apiPort: clashApiPort, secret: _apiSecret, onlyProxy: true);
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
        _pushNotificationDetail(snap, up < 0 ? 0 : up, down < 0 ? 0 : down);
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

  /// Подпись в шторке: сервер и трафик.
  ///
  /// ⚠️ Обновляем ТОЛЬКО при включённом экране. Уведомление, которое никто не
  /// видит, всё равно стоит процессорного времени и батареи — а такт у нас
  /// раз в секунду. Официальный клиент sing-box отписывается от статистики по
  /// `ACTION_SCREEN_OFF` ровно по этой причине.
  String? _lastDetailSent;

  /// Последнее, что уехало в шторку, — чтобы перерисовать её немедленно при
  /// смене раскладки, не дожидаясь очередного такта счётчиков.
  ({XrayTrafficSnapshot snap, int up, int down})? _lastDetail;

  /// Раскладку поменяли на лету: перерисовываем шторку тем же снимком.
  ///
  /// ⚠️ Сбросить `_lastDetailSent` обязательно: он гасит повторную отправку
  /// одинакового содержимого, а здесь содержимое как раз должно поехать
  /// заново — изменилась не цифра, а форма.
  @override
  void onNotificationLayoutChanged() {
    final d = _lastDetail;
    if (d == null) return;
    _lastDetailSent = null;
    unawaited(_pushNotificationDetail(d.snap, d.up, d.down));
  }
  Future<void> _pushNotificationDetail(
      XrayTrafficSnapshot snap, int upSpeed, int downSpeed) async {
    if (!_screenOn) return;
    final server = session?.servers.length == 1
        ? session!.servers.first.displayName
        : null;
    // ⚠️ И СКОРОСТЬ, И НАКОПЛЕННОЕ. Раньше сюда уходил только итог за сессию,
    // и в шторке не было главного — что происходит ПРЯМО СЕЙЧАС: качается файл
    // или соединение стоит. Скорость первой, она меняется каждую секунду;
    // накопленное вторым, оно отвечает на другой вопрос («сколько всего»).
    // ⚠️ СТРЕЛКИ И ПОДПИСИ — В РЕСУРСАХ ANDROID, не здесь.
    //
    // Во-первых, подписи «Текущ»/«Всего» обязаны следовать языку приложения, а
    // сервис переживает смерть Dart-изолята и берёт язык из нативных настроек.
    // Во-вторых, на устройстве владельца стрелки из строки Dart отрисовались
    // мусором ('  и  ij  вместо  ↓  и  ↑): шрифт уведомления подставил
    // чужие глифы. В строковом ресурсе они лежат ровно один раз, и заменить их
    // при повторении проблемы можно в одном месте, не трогая код.
    final nowDown = TrafficStats.formatSpeed(downSpeed);
    final nowUp = TrafficStats.formatSpeed(upSpeed);
    final totalDown = _human(snap.downlink);
    final totalUp = _human(snap.uplink);
    // ⚠️ РАСКЛАДКА ЗАДАНА ВЛАДЕЛЬЦЕМ, не выдумывать свою:
    //   обычная  — [значок + подписка] / сервер / скорость, с кнопками;
    //   короткая — [значок + имя приложения + подписка] / сервер,
    //              без скорости и БЕЗ кнопок.
    //
    // Первая строка уведомления Android — это `subText` рядом со значком, и
    // имя приложения система дописывает туда сама. Поэтому в обеих раскладках
    // подписка едет в subText: в короткой она и даёт «приложение · подписка».
    //
    // ⚠️ Признак раскладки уходит ОТДЕЛЬНЫМ полем. Раньше короткую опознавали
    // по пустой подписке — и это ломалось само собой, когда у подписки не
    // оказывалось имени: обычная раскладка молча превращалась в короткую.
    _lastDetail = (snap: snap, up: upSpeed, down: downSpeed);
    final sub = subscriptionTitle;
    final key = '$compactNotification|$sub|$server|$nowDown|$nowUp|$totalDown|$totalUp'
        '|$subscriptionLogoPath';
    if (key == _lastDetailSent) return; // не дёргать шторку впустую
    _lastDetailSent = key;
    try {
      await _channel.invokeMethod<void>('setNotificationDetail', {
        'sub': sub,
        'server': server ?? '',
        'nowDown': nowDown,
        'nowUp': nowUp,
        'totalDown': totalDown,
        'totalUp': totalUp,
        'compact': compactNotification,
        'logo': subscriptionLogoPath,
      });
    } catch (_) {
      // Уведомление — не критичный путь: туннель важнее.
    }
  }

  /// Только для тестов: живой прогон однажды показал в шторке литерал
  /// `${_human(...)}` вместо числа, и поймать это было нечем.
  @visibleForTesting
  static String humanBytesForTest(int bytes) => _human(bytes);

  /// ⚠️ ЕДИНИЦЫ БЕРУТСЯ ИЗ ОБЩЕГО ФОРМАТТЕРА, а не заводятся здесь свои.
  ///
  /// Раньше тут был собственный список ['Б','КБ','МБ'…], и на английском
  /// интерфейсе шторка показывала «Now: 0 Б/с» — подпись на одном языке, число
  /// на другом. Видно это только глазами на устройстве, компилятор молчит.
  /// `TrafficStats.formatBytes` — тот же источник, что у цифр на главном
  /// экране, поэтому расхождение больше невозможно по построению.
  static String _human(int bytes) => TrafficStats.formatBytes(bytes);



  /// Экран включён. Ставится наблюдателем жизненного цикла приложения.
  bool _screenOn = true;
  set screenOn(bool v) => _screenOn = v;

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  /// Только для тестов: осталась ли работать фоновая обвязка движка.
  ///
  /// Проверить это иначе нечем — таймер и сокет приватны, а снаружи «тикает ли
  /// что-то раз в секунду» не видно вообще: приложение выглядит отключённым.
  ///
  /// ⚠️ ЗДЕСЬ ПЕРЕЧИСЛЕНО ВСЁ, ЧТО ГАСИТ [platformCleanup], И ЭТО ЕГО
  /// ЕДИНСТВЕННЫЙ СТРАЖ. Пока сторож канала сюда не входил, признак ловил один
  /// пункт из трёх: ревьюер удалил из `platformCleanup` и `stopHealthWatch()`,
  /// и `await _stopFallbackDns()` — все тесты остались зелёными. Прежний
  /// комментарий оправдывал пропуск словами «его поле живёт в базе», хотя
  /// `VpnEngineBase.healthWatch` заведён ровно для теста и лежит рядом.
  /// Появится в `platformCleanup` четвёртая подсистема — её место здесь же,
  /// иначе страж снова начнёт молчать.
  ///
  /// `healthWatch` базы помечен `@visibleForTesting`, и анализатор запрещает
  /// читать его из чужой библиотеки. Гасим предупреждение точечно: потребитель
  /// здесь — САМ тестовый геттер, то есть ровно тот случай, ради которого
  /// пометка и ставится. Зеркалить состояние своим полем нельзя: пришлось бы
  /// повторить у себя гейт `aborted()` из `startHealthWatch`, а два разбора
  /// одного условия в этом проекте уже приводили к обходу.
  @visibleForTesting
  bool get backgroundWorkActive =>
      _statsTimer != null ||
      _fallbackDns != null ||
      // ignore: invalid_use_of_visible_for_testing_member
      healthWatch != null;

  /// Порт инбаунда для проб. НЕ 10809: там при панельном профиле садится Xray,
  /// и совпадение порта не давало ядру стартовать вовсе.
  static const probeInboundPort = 10811;

  /// Сервис-чипы и проба активного сервера ходят в наш собственный инбаунд.
  @override
  int get httpProxyPort => probeInboundPort;

  /// ⚠️ Проба ходит через probe-инбаунд, а он закрыт СВОИМИ кредами, не теми,
  /// что у socks Xray. Возьми мы общие — рукопожатие получило бы 407, три
  /// промаха подряд, и приложение переподключалось бы на исправном туннеле.
  @override
  ({String user, String password}) get healthProbeAuth =>
      (user: ProxyProbe.user, password: ProxyProbe.password);

  static const _channel = MethodChannel('lol.silentgate/vpn');
  static const _events = EventChannel('lol.silentgate/vpn_events');

  /// Идёт ли сейчас наш собственный подъём: нужно, чтобы не принять
  /// подтверждение «сервис запущен» за неожиданное падение.
  bool _starting = false;

  /// Опции и правила ЖИВОГО конфига — чтобы заглушка kill switch совпала с ним
  /// поле в поле. Разойдутся хоть в одном (MTU, списки пакетов) — `VpnService`
  /// пересоздаст интерфейс, и на этот миг трафик пойдёт мимо VPN.
  ///
  /// ⚠️ `null` ЗНАЧИТ «НЕ ЗНАЮ», И ЭТО НЕ ТО ЖЕ САМОЕ, ЧТО УМОЛЧАНИЯ. Туннель
  /// на Android переживает смерть изолята: приложение смахнули, открыли заново
  /// — VPN работает, а поля здесь пусты, потому что этот изолят его не
  /// поднимал ([adoptRunningTunnel]). Поэтому `_liveSplit` тоже обнуляемый:
  /// пока он был `const SplitTunnelConfig()`, «правил не знаю» выглядело как
  /// «у пользователя режим „Всё через VPN“ без правил» — и заглушка kill
  /// switch собиралась под чужой туннель. Оба поля ставятся и читаются ПАРОЙ.
  TunOptions? _liveOptions;
  SplitTunnelConfig? _liveSplit;

  /// О реконструкции заглушки уже сказали в журнале. См. [_blackholeJson].
  bool _warnedStubFromSettings = false;

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

  /// Поставить пароль на локальные инбаунды Xray ПЕРЕД отправкой ядру.
  ///
  /// ⚠️ ЗАКРЫВАЕТ ДЫРУ ДЛЯ «АВТО» И ПАНЕЛЬНЫХ ПРОФИЛЕЙ. Для одиночного сервера
  /// конфиг собирается здесь же (`configFor`), и креды туда попадают. А для
  /// автовыбора конфиг приходит ГОТОВЫМ из сессии — его собрал
  /// `balancerSessionFor` ещё до того, как креды сгенерированы, и через
  /// `normalizeOverridePorts` он не проходил. То есть 10808/10809 у самых
  /// частых сценариев оставались открыты любому приложению устройства, хотя
  /// у обычного сервера были уже закрыты.
  ///
  /// Нормализация идемпотентна: порты те же, аккаунты проставляются поверх.
  String _guardXrayInbounds(String json) {
    if (localInboundUser.isEmpty) return json;
    try {
      return normalizeOverridePorts(json,
              socksPort: ports.socks,
              httpPort: ports.http,
              socksUser: localInboundUser,
              socksPassword: localInboundPassword)
          .json;
    } catch (e) {
      // Не смогли — подключение важнее. Но сказать обязаны: порт остался открыт.
      AppLog.w('Не удалось закрыть паролем локальные инбаунды Xray: $e');
      return json;
    }
  }

  /// Убрать ссылки на гео-базы, если самих баз на устройстве нет.
  ///
  /// ⚠️ БЕЗ ЭТОГО ПАНЕЛЬНЫЕ ПРОФИЛИ НА ANDROID НЕ ПОДНИМАЛИСЬ ВООБЩЕ. Xray
  /// резолвит `geoip:`/`geosite:` по файлам НА УСТРОЙСТВЕ, а в APK их нет:
  /// ядро отвергало конфиг целиком и VPN-сервис останавливался. В журнале
  /// владельца — `illegal ip rule: geoip:private > failed to open geoip.dat`.
  /// Ссылки есть в 46 его профилях из 250, то есть «Авто» с российской
  /// маршрутизацией на телефоне не работал.
  ///
  /// Когда базы скачаны, конфиг уходит ядру КАК ЕСТЬ — маршрутизация панели
  /// применяется целиком, как на Windows.
  /// Ядро уже отвергало конфиг из-за гео-баз в этой сессии.
  ///
  /// ⚠️ ФАЙЛЫ НА МЕСТЕ — И ВСЁ РАВНО НЕ ОТКРЫВАЮТСЯ. У владельца на телефоне
  /// (Infinix, Android 11) базы скачаны, лежат в нашем каталоге, первое
  /// подключение проходит — а следующее падает с
  /// `failed to open geoip.dat > stat /system/bin/geoip.dat`. То есть каталог,
  /// который мы задаём переменной окружения, ядро в какой-то момент перестаёт
  /// видеть. Первопричина ищется отдельно; здесь важно другое:
  /// **эта ошибка не должна быть смертельной**.
  ///
  /// Проверять «доступны ли базы» наличием файлов недостаточно — файлы есть.
  /// Единственный надёжный признак — ответ самого ядра, поэтому флаг ставится
  /// по факту отказа и на следующем заходе конфиг чистится.
  bool _geodataUnusable = false;

  /// Прописать каталог гео-баз В САМ КОНФИГ (`"env"`), а не в окружение процесса.
  ///
  /// ⚠️ ЭТО ЕДИНСТВЕННЫЙ СПОСОБ, КОТОРЫЙ РАБОТАЕТ, И ВОТ ПОЧЕМУ.
  /// `android.system.Os.setenv` из `SilentGateApplication` правит окружение
  /// **libc**, а рантайм Go держит СВОЮ копию, снятую при своей инициализации, и
  /// в libc больше не заглядывает. Поэтому `os.Getenv` внутри ядра нашей
  /// переменной не видел НИКОГДА — сколько бы рано мы её ни ставили. Ядро шло
  /// искать базы по умолчанию:
  ///
  /// ```
  /// common/geodata: illegal ip rule: geoip:private
  ///   > failed to open geoip.dat
  ///   > stat /system/bin/geoip.dat: no such file or directory
  /// ```
  ///
  /// Владелец получил это на живом телефоне 15.08.2026: базы лежали на месте, а
  /// VPN не поднимался вовсе. Воспроизведено на эмуляторе `sg-test`.
  ///
  /// Блок `env` внутри конфига Xray применяет СВОИМ `os.Setenv` — уже внутри
  /// Go, — и рантайм его видит. Доказано тестами самого libXray:
  /// `TestInvokeRunXrayAppliesConfigEnv` (работает) и
  /// `TestInvokeIgnoresTopLevelEnv` (на верхнем уровне запроса — игнорируется,
  /// поэтому кладём именно в конфиг, а не рядом с ним).
  ///
  /// ⚠️ Kotlin-строку с `Os.setenv` не убираем: она безвредна и остаётся для
  /// путей, где конфиг собираем не мы (проба libXray строит запрос сама).
  Future<String> _withAssetEnv(String json) async =>
      withAssetEnv(json, (await GeoAssets.dir()).path);

  /// Чистая часть — отдельно и публично: каталог берётся с платформы, а вот
  /// правка конфига обязана быть проверяемой без телефона.
  @visibleForTesting
  static String withAssetEnv(String json, String dir) {
    try {
      final cfg = jsonDecode(json);
      if (cfg is! Map) return json;
      final env = <String, dynamic>{
        // Уважаем то, что уже пришло от панели: она вправе задать своё.
        ...?(cfg['env'] as Map?)?.cast<String, dynamic>(),
      };
      env.putIfAbsent('XRAY_LOCATION_ASSET', () => dir);
      cfg['env'] = env;
      return jsonEncode(cfg);
    } catch (e) {
      // Не смогли — не беда: дальше сработает страховка с чисткой гео-правил.
      AppLog.w('Не удалось прописать каталог гео-баз в конфиг: $e');
      return json;
    }
  }

  Future<String> _guardGeodata(String json) async {
    // ⚠️ ДИАГНОСТИКА, КОТОРАЯ НЕ ВРЁТ. Печатаем только БУЛЕВЫ признаки: сам
    // конфиг в журнал класть нельзя (там UUID и адреса узлов, а журнал уезжает
    // в отчёт поддержки), а путь к каталогу гео-баз бесполезен — он и в
    // сломанном случае выглядит правильным. Настоящий ответ даёт только
    // сравнение «что было на входе» и «что ушло ядру».
    final need = needsGeodata(json);
    final have = await GeoAssets.available();
    if (!need) {
      AppLog.i('Xray-конфиг: ссылок на гео-базы нет');
      return json;
    }
    if (!_geodataUnusable && have) {
      json = await _withAssetEnv(json);
      AppLog.i('Xray-конфиг: ссылки на гео-базы есть, базы скачаны — '
          'отдаю как есть');
      return json;
    }
    final r = stripGeodata(json);
    if (r.report.residual) {
      // Мы вычистили что могли, а ссылки остались — значит есть место, о
      // котором мы не знаем. Ядро сейчас откажет, и лучше сказать об этом
      // заранее, чем оставить «страховка есть, но не сработала».
      AppLog.e('В конфиге остались ссылки на гео-базы после чистки — '
          'ядро, скорее всего, откажет. Это дефект: сообщите разработчику.');
    }
    AppLog.i('Xray-конфиг после чистки: ссылки остались='
        '${needsGeodata(r.json)} (базы скачаны=$have, '
        'ядро их не открыло=$_geodataUnusable)');
    if (r.report.changed) {
      // ⚠️ ДВА РАЗНЫХ СЛУЧАЯ, И ПУТАТЬ ИХ НЕЛЬЗЯ. Сюда попадают и «файлов нет»,
      // и «файлы есть, ядро их не открыло». Прежний текст утверждал «не
      // скачаны» в обоих — то есть врал ровно тому, у кого базы уже лежат на
      // диске, и советовал ему скачать их ещё раз.
      if (have) {
        AppLog.w('Гео-базы на диске есть, но ядро их не открыло — правила по '
            'ним отброшены: ${r.report.describe()}. Этот трафик пойдёт через '
            'VPN, а не напрямую. Помогает перекачивание баз в настройках.');
        emitNotice(EngineNoticeKind.geoAssetsUnusable,
            'Ядро не открыло гео-базы — правила панели по странам отключены');
      } else {
        AppLog.w('Гео-базы не скачаны — правила по ним отброшены: '
            '${r.report.describe()}. Этот трафик пойдёт через VPN, а не '
            'напрямую. Скачать базы можно в настройках.');
        emitNotice(EngineNoticeKind.geoAssetsMissing,
            'Гео-базы не скачаны — правила панели по странам отключены');
      }
    }
    return r.json;
  }

  @override
  Future<void> startSession() async {
    final session = this.session;
    if (session == null) return;

    final gen = newGeneration();
    bool aborted() => isStale(gen);

    // Свежее подключение по кнопке (а не автоповтор) — даём гео-базам ещё один
    // шанс. Иначе один отказ ядра выключал бы правила панели до перезапуска
    // приложения, в том числе после того, как пользователь скачал базы заново.
    //
    // ⚠️ ЗДЕСЬ БЫЛО `attempt == 0`, И ЭТО ОСТАВЛЯЛО ТЕЛЕФОН БЕЗ ИНТЕРНЕТА.
    // Счётчик попыток обнуляет `markConnected()` — в момент ПОДЪЁМА ТУННЕЛЯ, а
    // ядро на Android падает уже после него. Круг выходил такой: конфиг со
    // ссылками на гео-базы → туннель поднялся → счётчик обнулён, kill switch
    // отпустил трафик → Xray умер на тех же базах → флаг «непригодны» → повтор
    // → `attempt == 0` → флаг СНЯТ → снова конфиг с базами. Раз в секунду,
    // бесконечно, с заблокированным трафиком; предел в восемь попыток не
    // достигался никогда. Спрашиваем факт, а не признак.
    if (isFreshUserConnect) _geodataUnusable = false;
    // Новая попытка — снова слушаем события остановки.
    _handlingStop = false;

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
    // Но выданы они УЖЕ — базой, до сборки конфига (`prepareLocalProxyAuth`).
    // ⚠️ Повторять вызов здесь нельзя: в режиме «Авто (лучший сервер)» конфиг
    // приходит готовым из `session.configJson`, и новый пароль разошёлся бы с
    // тем, что уже запечён в конфиге.
    // Системного прокси на Android не бывает вовсе, поэтому ограничение
    // WinINET сюда не приходит: пароль ставится всегда, когда его не отключили.

    try {
      // Ядро выбирается ровно так же, как на Windows (configFor в базе):
      // полный конфиг (правка пользователя или панельный профиль «Авто») —
      // всегда Xray; обычный сервер sing-box поднимает сам.
      // Резолв — ДО сборки конфига: адрес нужен и правилу «мимо туннеля»
      // (ip_cidr), и самому outbound'у. С доменным именем ядро пошло бы за
      // адресом уже из-под поднятого туннеля.
      // ⚠️ ВМЕСТЕ С СЕРВЕРАМИ ВЫХОДОВ. Иначе выход, заданный ДОМЕННЫМ именем,
      // пошёл бы за адресом уже из-под поднятого туннеля: имя спрашивается
      // через туннель, который к этому серверу ещё не построен. На живом тесте
      // это не всплыло только потому, что оба выхода были заданы адресами.
      // Заодно их адреса попадают в `serverIps` — правило «мимо туннеля».
      final hosts = await resolveServerHosts([
        ...session.servers,
        ...session.options.exitServers.values,
      ]);
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
          // Резолвер для «Прямо». Пусто → прежнее поведение (`local`), то
          // есть домен не отрезолвится: лучше знать об этом из лога, чем
          // молча получить «сайт не открывается».
          directDnsUpstream: await _directDns(),
          // Запасной резолвер — тот же, что на Windows. Паритет здесь не
          // формальность: жалоба «прямой трафик отваливается» одинаково
          // возможна на обеих платформах, потому что причина общая — резолв
          // прямого трафика идёт через туннель, а встроенного запаса у ядра
          // нет (проверено sing-box 1.11.15).
          fallbackDnsPort: await startFallbackDns(session.options.settings,
              viaXray: viaXray, gen: gen, aborted: aborted),
          ipv6Available: await _ipv6Reality(),
          // Ядро пишет свой лог САМО: перехватить его вывод здесь нечем —
          // это библиотека в нашем процессе, а redirectStderr ловит только
          // паники Go. Без этого «туннель поднят, трафика нет» не
          // диагностируется вообще.
          logOutput: await _coreLogPath(),
          // Счётчики трафика туннеля: без них цифра под кнопкой стояла на нуле,
          // что бы ни происходило. Пароль — на сессию: этот порт виден любому
          // приложению на телефоне.
          clashApiPort: clashApiPort,
          clashApiSecret: _apiSecret,
      );
      _liveOptions = liveOptions;
      _liveSplit = session.options.split;

      // Именованные выходы мульти-VPN. Собираются ДО построителя, чтобы его
      // единственным источником правды о живых выходах остался список готовых
      // outbound-ов: правило со ссылкой на несобравшийся выход обязано упасть
      // в общий туннель, а не оставить висячий тег (ядро его принимает молча).
      final exitsBuilt = ExitOutbounds.build(
        servers: session.options.exitServers,
        resolvedIps: resolvedIps,
      );
      for (final e in exitsBuilt.skipped.entries) {
        AppLog.i('Выход «${e.key}» не поднят: ${e.value} — '
            'его правила пойдут общим туннелем');
      }
      if (exitsBuilt.outbounds.isNotEmpty) {
        AppLog.i('Мульти-VPN: дополнительных серверов ${exitsBuilt.outbounds.length}');
      }

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
        exitOutbounds: exitsBuilt.outbounds,
        // ⚠️ ПАРИТЕТ С WINDOWS, А НЕ ЛИШНЯЯ СТРОКА. Портов API на Android
        // сегодня нет (`apiExitServerKeys`/`apiToken` сюда не передаются), но
        // состав выходов считает ОБЩИЙ `AppState.exitServerKeysFor`: включи
        // владелец API в настройках — активный сервер получил бы здесь живой
        // тег, и правило «через него» ушло бы вторым соединением к тому же
        // узлу. Разводим источники на обеих платформах одинаково.
        apiOnlyExitKeys: session.options.apiOnlyExitKeys.toList(),
      ).buildJson(session.options.split);

      // Подготовка была долгой — сверяемся с отменой ДО того, как тронем
      // нативный сервис. И убираем СВОЙ форвардер: он уже поднят (внутри сборки
      // опций) и слушает порт, а конфиг с этим портом никуда не поедет.
      if (aborted()) {
        await releaseOwnFallbackDns(gen);
        return;
      }

      _starting = true;
      await _channel.invokeMethod<void>(
          'start',
          startArgs(
            tunJson: tunJson,
            xrayJson: viaXray
                ? await _guardGeodata(_guardXrayInbounds(cfg.json))
                : null,
            readsXrayStats: readsXrayStats,
          ));
      _starting = false;

      // Пользователь мог отключиться, пока шло согласие на VPN.
      if (aborted()) {
        await _channel.invokeMethod<void>('stop');
        await releaseOwnFallbackDns(gen);
        return;
      }

      // ⚠️ ЖДЁМ, ПОКА ТУННЕЛЬ РЕАЛЬНО ПОДНЯЛСЯ.
      //
      // `invokeMethod('start')` возвращается, как только СЕРВИС ПРИНЯЛ команду.
      // Ядра к этому моменту ещё не запущены, `establish()` не вызван,
      // туннеля нет. Раньше «Подключено» ставилось прямо здесь — и статус, и
      // отсчёт времени начинались до того, как хоть один пакет мог пройти.
      // На Windows такого разрыва нет: там `_tunRouter.start` бросает
      // исключение, если туннель не встал, то есть ожидание встроено.
      //
      // Признак берём тот же, что отдаёт шторка и подхват живого туннеля:
      // `running` ставится в сервисе ПОСЛЕ `establish()`, а не по приёму
      // команды.
      if (!await _waitTunnelUp(aborted)) {
        if (aborted()) {
          await releaseOwnFallbackDns(gen);
          return;
        }
        throw StateError('Туннель не поднялся за отведённое время');
      }

      markConnected();
      setStatus(VpnConnectionState.connected);
      _startStatsPolling();
      // Сквозная проверка канала — та же, что на Windows. Паритет здесь
      // не формальность: без неё Android остаётся с проверкой ПРОЦЕССА и
      // не замечает мёртвый туннель при живом ядре.
      startHealthWatch(() => aborted());
      // Наблюдение за блокировками — после того, как туннель поднят: до этого
      // Clash API не слушает.
      startBlockNotice(
          settings: session.options.settings,
          apiPort: clashApiPort,
          secret: _apiSecret);
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

  /// Аргументы нативной команды `start` — ЕДИНСТВЕННАЯ дверь, через которую
  /// конфиги уходят ядрам.
  ///
  /// ⚠️ ПОЧЕМУ ГЕЙТ СТОИТ ЗДЕСЬ, А НЕ В ПОСТРОИТЕЛЕ. api-инбаунд Xray (порт
  /// 10085, без пароля — Xray его для `api` не умеет) создают ЧЕТЫРЕ разных
  /// места: построитель одиночного сервера, построитель автовыбора,
  /// `ensureXrayStats` для панельного профиля и сам панельный конфиг. Гейт на
  /// одном из них уже стоял — и порт всё равно поднимался в режиме «Авто
  /// (лучший сервер)», потому что там конфиг собирает другой метод. Здесь
  /// проходят ВСЕ конфиги без исключения, включая те, которых ещё не написали.
  ///
  /// [readsXrayStats] — тот же предикат, по которому база РЕШАЕТ дописывать
  /// `ensureXrayStats`. Одно решение на добавление и на удаление: разъедься
  /// они, порт снова открывался бы «где-то ещё».
  ///
  /// [xrayJson] == null — Xray в этой сессии не поднимается (обычный сервер
  /// целиком обслуживает sing-box).
  @visibleForTesting
  static Map<String, dynamic> startArgs({
    required String tunJson,
    String? xrayJson,
    bool readsXrayStats = false,
  }) =>
      {
        'config': tunJson,
        if (xrayJson != null)
          'xray_config': readsXrayStats ? xrayJson : stripXrayApi(xrayJson),
      };

  /// Событие от сервиса: туннель поднялся, упал или его отобрала система.
  /// Дождаться, пока сервис доложит о ПОДНЯТОМ туннеле.
  ///
  /// Опросом, а не ожиданием события: события `running` приходят и по другим
  /// поводам (шторка, перезагрузка ядра), и подписываться на них здесь значило
  /// бы дублировать разбор, который уже есть в [_onNativeEvent]. Опрос стоит
  /// один вызов канала в 200 мс и живёт считаные секунды.
  ///
  /// Потолок щедрый: на холодном старте поднимаются оба ядра, а на медленном
  /// устройстве это заметно дольше, чем на эмуляторе. Лучше подождать, чем
  /// объявить отказ там, где туннель встал бы через секунду.
  Future<bool> _waitTunnelUp(
    bool Function() aborted, {
    Duration timeout = const Duration(seconds: 25),
    Duration step = const Duration(milliseconds: 200),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (aborted()) return false;
      try {
        if (await _channel.invokeMethod<bool>('isRunning') ?? false) return true;
      } catch (_) {
        // Канал мог не ответить на миг — это не отказ туннеля.
      }
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future.delayed(step);
    }
  }

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    // ⚠️ Отдельное событие, БЕЗ поля running — и разбирать его надо до всех
    // проверок состояния ниже: они рассчитаны на события туннеля и это
    // выбросили бы как «сервис не запущен».
    final compact = event['compactNotification'];
    if (compact is bool) {
      onCompactToggledInShade?.call(compact);
      return;
    }
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
    // ⚠️ ТОЛЬКО ЕСЛИ ОШИБКИ НЕТ. Признак `byUser` залипал: он ставится на
    // ACTION_STOP, а снимался лишь при УСПЕШНОМ подъёме туннеля. Поэтому
    // отказ старта приезжал сюда одновременно с `byUser: true`, эта ветка
    // срабатывала первой — и настоящий текст ошибки выбрасывался, подменяясь
    // на «Туннель снят пользователем». В журнале владельца из-за этого шли
    // подряд «Подключение по команде пользователя» → «Туннель снят
    // пользователем» без единой ошибки, хотя ядро падало на гео-базах.
    //
    // Нативная сторона теперь сбрасывает признак в начале запуска, но проверка
    // здесь всё равно нужна: два независимых предохранителя дешевле, чем ещё
    // один заход на лог, из которого стёрты отказы.
    if (event['byUser'] == true && (error == null || error.isEmpty)) {
      AppLog.i('Туннель снят пользователем из уведомления');
      unawaited(disconnect()); // ставит _userStopped и гасит статус штатно
      return;
    }

    // ⚠️ Проверка ДО записи в журнал. На один отказ прилетает несколько
    // событий, и без этого одна и та же ошибка ложилась в лог по семь раз
    // подряд — в отчёте владельца это занимало страницы.
    if (_handlingStop) return;

    // Сюда попадает и onRevoke (другой VPN перехватил туннель) — пути,
    // которого на Windows нет вовсе.
    AppLog.e('VPN-сервис остановился: ${error ?? 'без причины'}');

    // Текст из нативного слоя ОБЯЗАН доехать до пользователя. Без этого
    // подключение просто «вылетало» молча, и причину нельзя было назвать
    // даже по логам приложения.
    unawaited(_reportStop(error));
  }

  /// Мы уже разбираем остановку сервиса.
  ///
  /// ⚠️ НА ОДИН ОТКАЗ ПРИЛЕТАЕТ НЕСКОЛЬКО СОБЫТИЙ. Нативная сторона шлёт
  /// состояние из `catch`, потом из `stopTunnel`, потом из `onDestroy` — в
  /// журнале владельца это семь одинаковых «VPN-сервис остановился» в одну и ту
  /// же секунду.
  ///
  /// Первое событие назначало повтор с вычищенным конфигом, а следующие
  /// приходили уже с поднятым `_geodataUnusable`, проваливались мимо ветки
  /// повтора в `cleanup()` — и та ОТМЕНЯЛА только что назначенную попытку
  /// (она увеличивает поколение). Итог: в логе есть и «Повторяю без правил», и
  /// «попытка 1 через 0 с», а повтор не случается никогда. Ровно то, что
  /// владелец видел как «та же ошибка, VPN не включается».
  bool _handlingStop = false;

  Future<void> _reportStop(String? error) async {
    // Повторные события того же отказа не должны трогать ничего: решение уже
    // принято по первому.
    if (_handlingStop) return;
    _handlingStop = true;
    if (error == null || error.isEmpty) {
      await onCoreDied(0);
      return;
    }
    // ⚠️ ГЕО-БАЗЫ — ЕДИНСТВЕННЫЙ СЛУЧАЙ, КОГДА ПОВТОР ОСМЫСЛЕН.
    //
    // Обычно повторять нечего: конфиг тот же, результат будет тот же. Но отказ
    // из-за гео-баз мы умеем обойти — вычистить ссылки на них и подняться без
    // правил по странам и категориям. Пользователю это стоит точности
    // маршрутизации панели, а альтернатива — «Ошибка» и VPN, который вообще не
    // включается. У владельца это выглядело как «первый раз работает, потом
    // перестаёт».
    if (!_geodataUnusable && _isGeodataError(error)) {
      _geodataUnusable = true;
      AppLog.w('Ядро не смогло открыть гео-базы, хотя файлы на месте. '
          'Повторяю без правил по странам и категориям: маршрутизация панели '
          'будет неполной, зато туннель поднимется.');
      await teardownCore();
      if (await scheduleRetry('ядру недоступны гео-базы')) return;
    }

    // Причина известна — показываем её вместо безымянного «ядро остановилось».
    await cleanup();
    setStatus(VpnConnectionState.error, message: error);
  }

  /// Ядро жалуется именно на гео-базы?
  ///
  /// Смотрим на несколько признаков сразу: текст приходит от Xray как цепочка
  /// вложенных причин, и её формулировка меняется от версии к версии.
  static bool _isGeodataError(String e) {
    final s = e.toLowerCase();
    return s.contains('geodata') ||
        s.contains('geoip.dat') ||
        s.contains('geosite.dat');
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    // Ядро уходит — счётчики уходят вместе с ним. Иначе таймер продолжал бы
    // раз в секунду стучаться в мёртвый порт, а на экране висели бы цифры
    // прошлой сессии, выдавая себя за текущие.
    _stopStatsPolling();
    // Сторож канала гоняет пробы через ядро — без ядра ему нечего проверять.
    stopHealthWatch();
    // ⚠️ Форвардер гасим ВМЕСТЕ С ЯДРОМ, даже при keepCapture: он ходит через
    // локальный SOCKS Xray, и без ядра его основной путь ведёт в никуда —
    // остался бы таймаут на каждом запросе и замедлял бы переподключение.
    await _stopFallbackDns();
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
      final stub = await _blackholeJson();
      if (stub == null) {
        // Заглушку не из чего собрать: ни живых опций, ни сессии. Собранная
        // «из чего попало» она не удержала бы туннель, а ПОДМЕНИЛА его чужим
        // интерфейсом — с другими списками пакетов и другим MTU.
        AppLog.w('Kill switch: удержать туннель нечем — параметры живого '
            'туннеля неизвестны. Гашу, чтобы не подменять интерфейс наугад.');
        await _stopService();
        return;
      }
      try {
        await _channel.invokeMethod<void>('start', startArgs(tunJson: stub));
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
  ///
  /// `null` — собирать не из чего (см. [blackholeInputs]).
  Future<String?> _blackholeJson() async {
    final reconstructed = _liveOptions == null || _liveSplit == null;
    final inputs = blackholeInputs(
      live: _liveOptions,
      liveSplit: _liveSplit,
      session: session?.options,
      // Признак берётся тем же вызовом, что и при подъёме живого туннеля, и он
      // кэширован на процесс — то есть при неизменившейся сети даёт тот же
      // ответ, а значит и тот же набор адресов интерфейса.
      ipv6Available: await Ipv6Support.hasGlobalIpv6(),
      logOutput: await _coreLogPath(),
    );
    if (inputs == null) return null;
    // ⚠️ Один раз на движок, а не на попытку. При kill switch попытки не
    // кончаются вовсе (три в минуту), и строка на каждую превратила бы отчёт
    // поддержки в простыню из одного и того же предложения.
    if (reconstructed && !_warnedStubFromSettings) {
      _warnedStubFromSettings = true;
      AppLog.w('Kill switch: опций живого туннеля нет (его поднял прошлый '
          'запуск интерфейса) — собираю заглушку из настроек сессии. Совпадёт '
          'с живым туннелем, пока настройки не менялись после его подъёма.');
    }
    return SingboxConfigBuilder(
      xraySocksPort: ports.socks,
      // В заглушке проб нет: слушать порт, из которого всё равно ничего не
      // выйдет, незачем — и это лишняя поверхность.
      options: inputs.options.asBlackhole(),
    ).buildJson(inputs.split);
  }

  /// Из чего собирается заглушка kill switch.
  ///
  /// ⚠️ ЗАГЛУШКА ИЗ УМОЛЧАНИЙ — НЕ УДЕРЖАНИЕ ТУННЕЛЯ, А ПОДМЕНА ЕГО ЧУЖИМ.
  /// Опции живого туннеля живут в памяти изолята, а туннель на Android
  /// изолят переживает: после возврата в свёрнутое приложение
  /// ([adoptRunningTunnel]) их нет. Прежний код в этом случае подставлял
  /// `const TunOptions(platformTun: true)` и пустой `SplitTunnelConfig`, и
  /// получалось вот что:
  ///
  ///  * у пользователя режим «только выбранные» → живой интерфейс собран с
  ///    `include_package`, заглушка — с `exclude_package` со своим пакетом.
  ///    `VpnService` строит ДРУГОЙ интерфейс, и в него заходит ВЕСЬ телефон, а
  ///    там всё уходит в reject: приложения, которые пользователь СОЗНАТЕЛЬНО
  ///    держал вне VPN, остаются без сети — и остаются надолго, потому что при
  ///    kill switch попытки не кончаются;
  ///  * наоборот, при `route_address` («в туннель только эти подсети») или
  ///    выключенном IPv6 у заглушки другой набор адресов и маршрутов —
  ///    интерфейс пересоздаётся, и на этот миг трафик идёт мимо VPN. Это ровно
  ///    то окно, ради закрытия которого заглушка и существует.
  ///
  /// Поэтому: знаем живые опции — берём их (точнее ничего нет). Не знаем, но
  /// есть сессия — собираем ТЕМ ЖЕ кодом из ТЕХ ЖЕ настроек, из которых
  /// туннель и поднимался (`TunOptions.fromSettings`); совпадёт, пока
  /// настройки и наличие IPv6 не изменились с момента подъёма. Нет и сессии —
  /// возвращаем `null`: пусть вызывающий честно погасит туннель, а не
  /// подменяет его наугад.
  @visibleForTesting
  static ({TunOptions options, SplitTunnelConfig split})? blackholeInputs({
    required TunOptions? live,
    required SplitTunnelConfig? liveSplit,
    required ConnectionOptions? session,
    required bool ipv6Available,
    String? logOutput,
  }) {
    if (live != null && liveSplit != null) {
      return (options: live, split: liveSplit);
    }
    if (session == null) return null;
    return (
      options: TunOptions.fromSettings(
        session.settings,
        android: true,
        ipv6Available: ipv6Available,
        logOutput: logOutput,
      ),
      split: session.split,
    );
  }

  /// Файл, куда ядро пишет свой лог. Один путь на живой конфиг и на заглушку:
  /// разные значения дали бы разный `log.output` у одного и того же туннеля.
  static Future<String> _coreLogPath() async =>
      '${(await AppPaths.supportDir()).path}'
      '${Platform.pathSeparator}singbox.log';

  /// Платформенная часть полной остановки.
  ///
  /// ⚠️ ТАЙМЕРЫ ГАСЯТСЯ ЗДЕСЬ, А НЕ ТОЛЬКО В [teardownCore]. `cleanup()` в базе
  /// зовёт ТОЛЬКО этот метод — не `teardownCore`, — поэтому после обычного
  /// «Отключить» (и после провала подъёма) продолжали жить: опрос счётчиков
  /// раз в секунду (сокет в мёртвый порт на каждом такте, то есть пробуждение
  /// процесса в бесконечность), сторож канала со своей пробой раз в 45 с через
  /// мёртвый прокси и локальный DNS-форвардер — открытый UDP-порт на loopback,
  /// который на Android виден любому приложению и который при отсутствии
  /// туннеля пересылает запросы провайдеру. Windows-движок гасит всё это в
  /// своём `platformCleanup` с самого начала — расхождение платформ на ровном
  /// месте.
  @override
  Future<void> platformCleanup() async {
    _stopStatsPolling();
    stopHealthWatch();
    await _stopFallbackDns();
    // Туннеля, который мы знали, больше нет — и «знаю его параметры» обязано
    // перестать быть правдой вместе с ним. Иначе следующая заглушка kill
    // switch собралась бы по ПРОШЛОМУ подключению: пользователь успел сменить
    // сервер и настройки, а мы держали бы интерфейс от предыдущего.
    _liveOptions = null;
    _liveSplit = null;
    await _stopService();
  }

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

  /// Поднять локальный DNS-форвардер с запасным резолвером. 0 — не нужен.
  ///
  /// ⚠️ ТОЛЬКО КОГДА ТРАФИК ИДЁТ ЧЕРЕЗ XRAY. Форвардер спрашивает туннельный
  /// резолвер через локальный SOCKS Xray; когда сервер поднимает сам sing-box
  /// (hysteria2 и прочее, что Xray не умеет), такого SOCKS нет вовсе, и
  /// форвардер уходил бы в запас на КАЖДОМ запросе — то есть весь DNS шёл бы
  /// мимо туннеля, причём молча. Лучше не поднимать его совсем: тогда работает
  /// прежнее поведение, и оно честное.
  ///
  /// [gen] — поколение запуска, который его поднимает; [aborted] — тот же
  /// предикат отмены, которым сверяется весь остальной [startSession]. Свой
  /// (`isStale(gen)`) означал бы два независимых ответа на один вопрос, а чем
  /// это кончается, в проекте уже записано отдельным уроком.
  @visibleForTesting
  Future<int> startFallbackDns(AppSettings s,
      {required bool viaXray,
      required int gen,
      required bool Function() aborted}) async {
    // ⚠️ ГЕЙТ ДО ПЕРВОГО ДЕЙСТВИЯ, А НЕ ПОСЛЕ. Ниже стоит `_stopFallbackDns()`,
    // и он снимает форвардер ИЗ ПОЛЯ — а там уже может стоять форвардер живой
    // сессии (см. [_fallbackDnsOwnerGen]). Устаревший запуск обязан уйти,
    // ничего не тронув и ничего не подняв: поднятое им никто бы не погасил.
    if (aborted()) {
      AppLog.i('Запасной DNS не поднимаю: запуск устарел, форвардер живой '
          'сессии не трогаю');
      return 0;
    }
    await _stopFallbackDns();
    if (!s.tunnelDnsForAll) return 0;
    // ⚠️ ГЕЙТ ПО ФАКТУ ЗАПУСКА XRAY, А НЕ ПО НАЛИЧИЮ ПАРОЛЯ. Раньше здесь
    // стояло `localInboundUser.isEmpty`, и это два РАЗНЫХ предиката, которые
    // разошлись в обе стороны сразу:
    //
    //  • пароль выдаётся ВСЕГДА (настройка включена по умолчанию), поэтому на
    //    обычном сервере подписки — где Xray не поднимается вовсе и SOCKS 10808
    //    некому слушать — форвардер всё-таки поднимался. Каждый запрос стучался
    //    в мёртвый порт, мгновенно получал отказ и уходил к резолверу
    //    ПРОВАЙДЕРА. А `dns.final` при поднятом форвардере переключён на него,
    //    то есть к провайдеру уходили ВСЕ имена устройства — при настройке,
    //    которая обещает ровно обратное;
    //  • пользователь, снявший пароль, лишался запасного резолвера молча, даже
    //    когда Xray работает.
    if (!viaXray) return 0;
    final local = await _directDns();
    if (local == null || local.isEmpty) {
      AppLog.w('Запасной DNS не поднят: резолвер физической сети неизвестен');
      return 0;
    }
    // Разбираем ТЕМ ЖЕ кодом, что и построитель конфига, и требуем чистый
    // IPv4 — см. подробности в одноимённом методе Windows-движка.
    final upstream = SingboxConfigBuilder.dnsHostOf(
        s.dnsMode == DnsMode.custom ? s.dnsCustomServer : '1.1.1.1');
    final ip = InternetAddress.tryParse(upstream);
    if (ip == null || ip.type != InternetAddressType.IPv4) {
      AppLog.w('Запасной DNS не поднят: резолвер «$upstream» не литеральный '
          'IPv4-адрес. DNS работает как раньше — целиком через туннель.');
      return 0;
    }
    try {
      final srv = DnsFallbackServer(
        socksPort: ports.socks,
        socksUser: localInboundUser,
        socksPassword: localInboundPassword,
        tunnelDns: upstream,
        localDns: local,
      );
      await srv.start();
      _fallbackDns = srv;
      _fallbackDnsOwnerGen = gen;
      return srv.port;
    } catch (e) {
      AppLog.w('Запасной DNS не поднялся: $e');
      return 0;
    }
  }

  /// Снять форвардер, если его поднял запуск [gen]. Чужой не трогаем — ровно
  /// как Windows-движок не трогает чужой туннель и чужой системный прокси.
  ///
  /// ⚠️ Зовётся на КАЖДОМ раннем выходе [startSession] после сборки опций:
  /// `cleanup()` там не вызывается, а форвардер уже слушает UDP-порт на петле
  /// — и конфиг с этим портом никуда не поедет. Без снятия он остался бы
  /// слушать навсегда.
  @visibleForTesting
  Future<void> releaseOwnFallbackDns(int gen) async {
    if (_fallbackDns == null || _fallbackDnsOwnerGen != gen) return;
    await _stopFallbackDns();
  }

  /// ⚠️ Сторож канала здесь БОЛЬШЕ НЕ ГАСИТСЯ. Он жил тут по совпадению — и
  /// это значило, что остановить сторожа мог только тот, кто заодно трогает
  /// DNS-форвардер. Оба места, где он должен умирать (`teardownCore` и
  /// `platformCleanup`), зовут `stopHealthWatch()` сами и явно.
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
