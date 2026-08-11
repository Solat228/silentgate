import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_info.dart';
import '../core/models/subscription_info.dart';
import '../core/models/subscription_profile.dart';
import '../core/models/subscription_sync.dart';
import '../core/models/traffic_stats.dart';
import '../core/util/server_search.dart';
import '../core/util/country_flag.dart';
import '../core/util/reorder.dart';
import '../core/models/vpn_server.dart';
import '../core/models/vpn_status.dart';
import '../core/models/engine_notice.dart';
import '../core/net/api_ports.dart';
import '../core/net/api_server.dart';
import '../core/parser/share_link_parser.dart';
import '../core/platform/app_log.dart';
import '../core/platform/desktop_notice.dart';
import '../core/platform/tray_window.dart';
import '../core/platform/app_paths.dart';
import '../core/platform/network_watcher.dart';
import '../core/platform/device_id.dart';
import '../core/platform/incoming_links.dart';
import '../core/url_scheme.dart';
import '../core/settings/app_settings.dart';
import '../core/settings/split_tunnel.dart';
import '../core/subscription/subscription_logo.dart';
import '../core/subscription/subscription_service.dart';
import '../core/subscription/subscription_updater.dart';
import '../core/subscription/xray_json_subscription.dart';
import '../core/xray/outbound_variant.dart';
import '../core/models/server_override.dart';
import '../data/app_storage.dart';
import '../data/panel_outbounds_store.dart';
import '../data/pinned_store.dart';
import '../data/server_overrides_store.dart';
import '../data/subscriptions_store.dart';
import '../data/settings_storage.dart';
import '../engine/engine_factory.dart';
import '../engine/vpn_engine.dart';
import 'api_handlers.dart';
import 'app_error.dart';
import 'probe_controller.dart';
import 'settings_controller.dart';

/// Центральное состояние приложения. UI подписывается через Provider.
class AppState extends ChangeNotifier {
  final VpnEngine _engine;
  final SubscriptionService _subscription;
  final AppStorage _storage;

  AppState({
    VpnEngine? engine,
    SubscriptionService? subscription,
    AppStorage? storage,
    String? initialUrl,
  })  : _engine = engine ?? createVpnEngine(),
        _subscription = subscription ?? SubscriptionService(),
        _storage = storage ?? AppStorage(),
        _initialUrl = initialUrl {
    _statusSub = _engine.statusStream.listen((s) {
      final was = _status.state;
      final wasBlocking = _status.blocking;
      _status = s;
      _trackAutotune(s);
      // ⚠️ Kill switch держит трафик — сказать об этом ТАМ, ГДЕ ВИДНО.
      //
      // Окно чаще всего свёрнуто в трей: человек видит только пропавший
      // интернет и решает, что сломалось приложение. Самое естественное
      // действие после этого — выключить VPN, то есть ровно то, от чего защита
      // и оберегала. Подсказка трея видна при свёрнутом окне, а карточка в
      // интерфейсе — когда его развернут.
      if (s.blocking != wasBlocking) {
        unawaited(_reflectBlocking(s.blocking));
      }
      // Значок в трее показывает состояние: серый — выключен, фиолетовый —
      // включён. Трей — единственное место на Windows, где состояние видно
      // всегда, в том числе при свёрнутом окне.
      //
      // ⚠️ Зовём на КАЖДОМ событии, но сам метод молча выходит, если состояние
      // не изменилось: поток статуса тикает раз в секунду на обновлении
      // счётчиков, а смена значка в tray_manager течёт дескрипторами.
      if (Platform.isWindows) {
        unawaited(TrayWindow.instance.setConnected(s.isConnected));
      }
      // ⚠️ ОТСЧЁТ ИДЁТ ОТ НАЖАТИЯ ПОЛЬЗОВАТЕЛЯ И ПЕРЕПОДКЛЮЧЕНИЕМ НЕ СБРАСЫВАЕТСЯ.
      //
      // Решение владельца (11.08.2026): «таймер считается с 1 нажатия кнопки
      // юзером (или url коммандой), и отключается так же вручную».
      //
      // Здесь была обратная логика, и она мешала: при обрыве статус мигает
      // connecting → connected, и таймер начинал считать заново. Человек,
      // отошедший от компьютера, возвращался к цифре «0:12» и не мог понять,
      // сколько на самом деле держится сессия. Пусть лучше показывает время с
      // момента, когда ОН включил VPN, — это единственная точка отсчёта, про
      // которую он знает наверняка.
      //
      // Точку ставит [markUserConnect], а снимает [markUserDisconnect] — оба
      // зовутся с путей пользовательских команд (кнопка и url-схема). Здесь мы
      // отсчёт не трогаем ВООБЩЕ, иначе он снова поедет за статусом.

      // Наблюдатель за сетью работает только при живом подключении и молчит, пока мы
      // сами что-то делаем: подъём туннеля перестраивает маршруты, и без паузы это
      // считалось бы «сменой сети» (именно так возникал цикл переподключений).
      if (s.state == VpnConnectionState.connecting ||
          s.state == VpnConnectionState.disconnecting) {
        _networkWatcher.suspend();
      } else if (s.isConnected) {
        if (was == VpnConnectionState.connected) {
          _networkWatcher.resume();
        } else {
          _networkWatcher.start();
        }
      } else {
        _networkWatcher.stop();
      }
      notifyListeners();
    });
    _networkSub = _networkWatcher.changes.listen((sig) {
      AppLog.w('Сменилось сетевое окружение');
      _engine.onNetworkChanged();
    });
    // Заблокированные сайты: движок замечает их по снимку соединений ядра,
    // а показать сообщение может только интерфейс — здесь и передаём.
    _blockedSub = _engine.blockedHostEvents.listen((host) {
      _lastBlockedHost = host;
      notifyListeners();
    });
    // Заметки движка: обрыв, восстановление, отказ, блокировка. Показать их
    // может только интерфейс — здесь копим последнюю, а снимает её тот, кто
    // показал ([clearNotice]).
    _noticeSub = _engine.notices.listen((n) {
      _pendingNotice = n;
      // ⚠️ ГЕО-ВЕРДИКТ ЗАПОМИНАЕТСЯ, А НЕ ТОЛЬКО ВСПЛЫВАЕТ. Момент подключения
      // на Android — ровно тот момент, когда приложение чаще всего НЕ на
      // экране: сверху диалог согласия VPN, стартует сервис. Всплывашка,
      // показанная в эту секунду, до человека не доходит, и жалоба звучит как
      // «предложение докачать гео-файлы как будто не происходит».
      if (n.kind == EngineNoticeKind.geoAssetsMissing ||
          n.kind == EngineNoticeKind.geoAssetsUnusable) {
        _geoVerdict = n.kind;
      }
      // ⚠️ И СИСТЕМНОЕ УВЕДОМЛЕНИЕ ТОЖЕ — иначе на Windows его не увидят.
      //
      // Карточка внутри приложения видна только при открытом окне, а оно почти
      // всегда свёрнуто в трей. 10.08.2026 проверка канала честно отработала и
      // переподняла туннель, карточка показалась — а владелец её не увидел
      // вовсе. Показываем только то, что требует внимания: обычные заметки
      // остаются внутри приложения, чтобы их не начали отмахивать не читая.
      if (n.isProblem) {
        final detail = (n.detail ?? '').trim();
        unawaited(DesktopNotice.show(
            n.text, detail.isEmpty ? 'SilentGate' : detail));
      }
      notifyListeners();
    });
    _statsSub = _engine.statsStream.listen((s) {
      // Итог за сессию приложения: счётчики ядра обнуляются при каждом переподключении,
      // поэтому копим разницу отдельно (сбрасывается только перезапуском приложения).
      if (s.uplinkBytes >= _lastUp && s.downlinkBytes >= _lastDown) {
        _sessionUp += s.uplinkBytes - _lastUp;
        _sessionDown += s.downlinkBytes - _lastDown;
      } else {
        // Счётчики ядра поехали назад — значит стартовало новое ядро.
        _sessionUp += s.uplinkBytes;
        _sessionDown += s.downlinkBytes;
      }
      _lastUp = s.uplinkBytes;
      _lastDown = s.downlinkBytes;
      _stats = s;
      notifyListeners();
    });
    _incomingSub = IncomingLinks.stream.listen(handleIncomingUrl);
    _updater = SubscriptionUpdater(
      onRefresh: () async {
        if (_subscriptionUrl != null) await refreshSubscription();
      },
      onMessage: (m) {
        _updateMessage = m;
        notifyListeners();
      },
    );
  }

  late final SubscriptionUpdater _updater;
  String? _updateMessage;
  String? get updateMessage => _updateMessage;

  final String? _initialUrl;
  late final StreamSubscription _statusSub;
  late final StreamSubscription _statsSub;
  StreamSubscription<String>? _blockedSub;
  StreamSubscription<EngineNotice>? _noticeSub;

  /// Последний замеченный заблокированный сайт — для всплывающего сообщения.
  ///
  /// ⚠️ Именно ПОЛЕ, а не поток наружу: интерфейс перестраивается при переходах
  /// между экранами, и подписка в виджете теряла бы события. Значение
  /// сбрасывает тот, кто его показал ([clearBlockedHost]), иначе сообщение
  /// всплывало бы заново на каждой перерисовке.
  String? _lastBlockedHost;
  String? get lastBlockedHost => _lastBlockedHost;
  void clearBlockedHost() => _lastBlockedHost = null;

  /// Заметка движка, которую ещё никто не показал.
  ///
  /// ⚠️ Снимается ТЕМ, КТО ПОКАЗАЛ ([clearNotice]), а не по таймеру. Иначе при
  /// каждой перерисовке всплывало бы одно и то же сообщение — на этих граблях
  /// в проекте уже стояли с итогами пинга и автонастройки.
  EngineNotice? _pendingNotice;
  EngineNotice? get pendingNotice => _pendingNotice;

  /// Что не так с гео-базами по мнению ЯДРА. `null` — всё в порядке.
  ///
  /// Держится отдельно от [pendingNotice]: та снимается сразу после показа, а
  /// этот вердикт должен висеть на экране, пока человек его не закроет. Ставит
  /// его только движок (`_guardGeodata`), снимает — успешное скачивание баз
  /// либо подключение, на котором ядро больше не жаловалось.
  EngineNoticeKind? _geoVerdict;
  EngineNoticeKind? get geoVerdict => _geoVerdict;

  /// Забыть вердикт: базы скачаны заново, либо человек закрыл плашку.
  void clearGeoVerdict() {
    if (_geoVerdict == null) return;
    _geoVerdict = null;
    notifyListeners();
  }
  void clearNotice() => _pendingNotice = null;
  late final StreamSubscription _incomingSub;
  late final StreamSubscription _networkSub;

  /// Следит за сменой сети (Wi-Fi ↔ кабель, сон): туннель поверх старого адаптера
  /// мёртв, даже если процессы живы.
  final NetworkWatcher _networkWatcher = NetworkWatcher();

  final PinnedStore _pinnedStore = PinnedStore();
  final ServerOverridesStore _overridesStore = ServerOverridesStore();
  final Map<String, ServerOverride> _overrides = {};

  /// Конфиги от панели (XRAY_JSON) по ключу сервера. На диске список серверов —
  /// это только ссылки, поэтому панельный конфиг храним отдельно, иначе он терялся
  /// бы при перезапуске и outbound'ы снова пересобирались из ссылок.
  final PanelOutboundsStore _panelOutboundsStore = PanelOutboundsStore();
  final Map<String, PanelConfig> _panelConfigs = {};

  // ── Состояние ──────────────────────────────────────────────────────────────
  String? _subscriptionUrl;
  List<VpnServer> _servers = []; // объединённый список (закреплённые + подписка)
  List<VpnServer> _subServers = []; // из подписки
  final List<VpnServer> _pinned = []; // закреплённые/правленые (переживают подписку)
  int _selectedIndex = -1;
  OutboundVariant _selectedVariant = OutboundVariant.none;
  SubscriptionInfo _info = SubscriptionInfo.empty;
  VpnStatus _status = const VpnStatus.disconnected();
  TrafficStats _stats = TrafficStats.zero;

  // #8 — автоподбор стека/MTU TUN: отслеживаем для прогресс-тоста (как пинг/
  // автонастройку). Иначе перебор виден только строкой статуса.
  TunAutotuneTracking _autotune = const TunAutotuneTracking();

  /// Трафик за всё время работы приложения (переживает переподключения; сбрасывается
  /// только перезапуском). Счётчики ядра обнуляются на каждом новом процессе Xray.
  int _sessionUp = 0, _sessionDown = 0, _lastUp = 0, _lastDown = 0;
  bool _loading = false;
  String? _error;

  /// Код ошибки для тех случаев, которые приложение распознаёт само.
  ///
  /// Динамические ошибки (текст исключения от сети/ядра) остаются строкой в
  /// [_error] и не переводятся; известные состояния несут код, а текст к нему
  /// подбирает UI — у состояния нет `AppLocalizations`.
  AppErrorCode? _errorCode;
  String? _logoPath; // #2 — кэшированная аватарка подписки

  /// #1/#1.1 — итог последнего обновления подписки (что добавилось/удалилось).
  SubscriptionSyncResult? _lastSync;
  bool _refreshing = false;

  String? get subscriptionUrl => _subscriptionUrl;
  List<VpnServer> get servers => List.unmodifiable(_servers);
  int get selectedIndex => _selectedIndex;
  VpnServer? get selectedServer =>
      (_selectedIndex >= 0 && _selectedIndex < _servers.length)
          ? _servers[_selectedIndex]
          : null;
  OutboundVariant get selectedVariant => _selectedVariant;
  SubscriptionInfo get info => _info;

  /// Путь к кэшированной аватарке подписки (#2), либо null.
  String? get logoPath => _logoPath;

  /// Итог последнего обновления подписки (для баннера и экрана логов).
  SubscriptionSyncResult? get lastSync => _lastSync;

  /// Идёт обновление подписки (крутилка на кнопке).
  bool get refreshing => _refreshing;
  VpnStatus get status => _status;
  TrafficStats get stats => _stats;

  /// Момент, когда пользователь ВКЛЮЧИЛ VPN. null — выключен.
  ///
  /// Хранится здесь, а не в виджете: интерфейс пересоздаётся при переходах между
  /// экранами, и таймер, живущий в нём, обнулялся бы на каждом возврате.
  ///
  /// ⚠️ Это момент НАЖАТИЯ, а не момент подъёма туннеля. Обрывы и
  /// переподключения его не двигают — см. [markUserConnect].
  DateTime? _connectedAt;

  /// Сколько прошло с включения VPN. null — выключен.
  ///
  /// ⚠️ Не зависит от `isConnected`: во время переподключения таймер обязан
  /// продолжать идти, иначе он снова начнёт прыгать на каждом обрыве.
  Duration? get connectedFor {
    final at = _connectedAt;
    if (at == null) return null;
    return DateTime.now().difference(at);
  }

  /// Пользователь включил VPN — ставим точку отсчёта ЗАНОВО.
  ///
  /// Зовётся со всех путей включения по команде человека: кнопка, автовыбор,
  /// url-схема. Все они входят сюда только когда VPN не поднят, то есть это
  /// всегда НОВАЯ сессия.
  ///
  /// ⚠️ РАНЬШЕ ЗДЕСЬ БЫЛО `??=`, И ЭТО БЫЛА ОШИБКА. Точку отсчёта снимают
  /// только `markUserDisconnect` с трёх путей Dart, а сессия кончается и мимо
  /// них: неудачное подключение, «Отключить» из шторки Android и плитки
  /// быстрых настроек, `onRevoke` при перехвате другим VPN. Точка залипала, и
  /// следующее включение показывало часы от прошлого раза — «подключился
  /// утром, выключил из шторки днём, включил вечером» давало сразу 8 часов.
  /// Снять залипшее значение из интерфейса было нечем.
  ///
  /// Переподключение таймер по-прежнему не трогает: оно идёт мимо этого
  /// метода.
  void markUserConnect() {
    _connectedAt = DateTime.now();
    // Новая попытка — новый разговор про гео-базы: прошлый вердикт мог
    // относиться к другому серверу, а базы с тех пор могли и скачать.
    _geoVerdict = null;
  }

  /// Пользователь выключил VPN — отсчёт снят.
  void markUserDisconnect() {
    _connectedAt = null;
  }

  /// Локальный http-прокси порт активного ядра (для живой проверки сервисов).
  int get httpProxyPort => _engine.httpProxyPort;

  // #8 — состояние автоподбора TUN для прогресс-тоста (логика — в [TunAutotuneTracking]).
  bool get tunAutotuning => _autotune.running;
  String? get tunAutotuneMessage => _autotune.message;
  DateTime? get tunAutotuneFinishedAt => _autotune.finishedAt;
  bool get tunAutotuneSucceeded => _autotune.succeeded;

  void _trackAutotune(VpnStatus s) =>
      _autotune = _autotune.next(s, DateTime.now());

  /// Итог за сессию приложения: отправлено / получено.
  int get sessionUplinkBytes => _sessionUp;
  int get sessionDownlinkBytes => _sessionDown;
  bool get loading => _loading;
  String? get error => _error;

  /// Код распознанной ошибки (null — ошибки нет либо она динамическая).
  AppErrorCode? get errorCode => _errorCode;
  bool get hasServers => _servers.isNotEmpty;

  // ── Инициализация из хранилища ─────────────────────────────────────────────
  Future<void> init() async {
    // Туннель на Android переживает смерть интерфейса — подхватываем его ДО
    // всего остального, иначе первые кадры покажут «Отключено» при работающем
    // VPN, а Connect поднимет второй сеанс поверх живого.
    await _engine.adoptRunningTunnel();
    // ⚠️ Подхваченный туннель тоже получает точку отсчёта, иначе таймера не
    // будет ВООБЩЕ: на Android сервис переживает смерть интерфейса, и после
    // возврата в приложение нажатия кнопки уже не случится.
    //
    // Момент исходного включения нам неизвестен — сервис его не хранит, — так
    // что отсчёт начинается с подхвата. Это честнее пустого места: цифра
    // означает «столько прошло с возврата в приложение», а не «столько живёт
    // туннель». Показывать нечего лучше, чем показывать заведомо неверное.
    if (_engine.status.isConnected) markUserConnect();

    // Разовая чистка СТАРОГО общего логотипа: раньше все подписки писали картинку
    // в один `sub_logo.*`, из-за чего после смены подписки висела чужая/устаревшая.
    // Теперь у каждой подписки свой файл `sub_logo_<id>.*`; старые общие удаляем.
    await _cleanLegacyLogos();

    final data = await _storage.load();
    _subscriptionUrl = data['subscriptionUrl'] as String?;
    final logo = data['logoPath'] as String?;
    if (logo != null && !_isLegacyLogo(logo) && File(logo).existsSync()) {
      _logoPath = logo;
    }
    // #5 — восстановить карточку подписки (иначе до ручного «Обновить» она пустая).
    if (data['info'] is Map<String, dynamic>) {
      _info = SubscriptionInfo.fromJson(data['info'] as Map<String, dynamic>);
    }
    // Конфиги панели грузим ПЕРВЫМИ: профили «Авто …» хранятся как `panel://…`
    // и восстанавливаются только из них (обычный парсер ссылок их не знает).
    _overrides
      ..clear()
      ..addAll(await _overridesStore.load());
    _panelConfigs
      ..clear()
      ..addAll(await _panelOutboundsStore.load());

    // Подписки: несколько профилей, активный — один. Старое одно-подписочное
    // состояние мигрируется в профиль №1 при первом запуске новой версии.
    final snapshot = await _subscriptionsStore.load();
    _profiles
      ..clear()
      ..addAll(snapshot.items);
    _activeId = snapshot.activeId;
    _backfillAddedAt();

    final legacyLinks = (data['servers'] as List?)?.cast<String>() ?? const [];
    if (_profiles.isEmpty && (_subscriptionUrl ?? '').isNotEmpty) {
      _profiles.add(SubscriptionProfile(
        id: SubscriptionProfile.idFor(_subscriptionUrl!),
        url: _subscriptionUrl!,
        info: _info,
        logoPath: _logoPath,
        serverLinks: legacyLinks,
        addedAt: DateTime.now(),
      ));
      _activeId = _profiles.first.id;
      await _saveSubscriptions();
      AppLog.i('Подписка перенесена в новый формат профилей');
    }

    final active = _activeProfile;
    if (active != null) {
      _subscriptionUrl = active.url;
      _info = active.info;
      if ((active.logoPath ?? '').isNotEmpty &&
          !_isLegacyLogo(active.logoPath!) &&
          File(active.logoPath!).existsSync()) {
        _logoPath = active.logoPath;
      } else {
        _logoPath = null;
      }
    }

    final rawLinks = active?.serverLinks ?? legacyLinks;
    _subServers =
        rawLinks.map(_serverFromStoredLink).whereType<VpnServer>().toList();
    final pinnedLinks = await _pinnedStore.load();
    _pinned
      ..clear()
      ..addAll(pinnedLinks.map(_serverFromPinned).whereType<VpnServer>());
    _rebuild();
    _selectedIndex = (data['selectedIndex'] as int?) ?? (_servers.isNotEmpty ? 0 : -1);
    if (_selectedIndex >= _servers.length) {
      _selectedIndex = _servers.isNotEmpty ? 0 : -1;
    }
    final variantJson = data['selectedVariant'];
    _selectedVariant = variantJson is Map<String, dynamic>
        ? OutboundVariant.fromJson(variantJson)
        : OutboundVariant.none;
    notifyListeners();

    // Deep link, с которым приложение было запущено (silentgate://…).
    final url = _initialUrl;
    if (url != null) {
      await handleIncomingUrl(url);
    }
    await _maybeStartUpdater();
    // ⚠️ ТОЛЬКО ЗДЕСЬ, В КОНЦЕ: подхват туннеля идёт первой строкой init(), но
    // сервер и настройки к тому моменту ещё не прочитаны с диска. Без сессии
    // движка автопереподключение и kill switch молча не работают — см.
    // VpnEngineBase.armAdoptedSession.
    await _armAdoptedSession();
    // Логотип на старте НЕ тянем: только при импорте/обновлении подписки
    // (см. importSource/_refreshLogo). Здесь показываем то, что уже в кэше.
  }

  /// Отдать движку сессию для туннеля, подхваченного от прошлого запуска.
  /// Собираем ровно из того же, из чего идёт обычное подключение, — иначе
  /// восстановленная сессия описывала бы не тот туннель, что работает.
  Future<void> _armAdoptedSession() async {
    if (!_status.isConnected || _servers.isEmpty) return;
    final s = await SettingsStorage().load();
    // «Авто (лучший сервер)» — сессия по всему списку, как в connectAuto.
    if (_selectedIndex < 0) {
      _engine.fallbackServers = _fallbackCandidates();
      await _engine.armAdoptedSession(
          _servers, ConnectionOptions(settings: s, exitServers: _exitServers(s)));
      return;
    }
    final server = _servers[_selectedIndex];
    final ov = _overrides[server.key];
    final srv = (ov?.rawJson != null && ov!.rawJson!.isNotEmpty)
        ? server.copyWith(rawJsonOverride: ov.rawJson)
        : server;
    await _engine.armAdoptedSession([srv],
        ConnectionOptions(
            variant: ov?.variant ?? _selectedVariant,
            settings: s,
            exitServers: _exitServers(s)));
  }

  /// Выбрать сервер по имени из подписки. false — не нашли.
  ///
  /// Сначала ищем ТОЧНОЕ совпадение имени (без флаг-эмодзи и регистра): у
  /// панелей встречаются «Германия» и «Германия 2», и подстрочный поиск выбрал
  /// бы первый попавшийся. Не нашли точного — падаем на обычный поиск, тот же,
  /// что в строке поиска списка: по имени, стране, адресу, протоколу.
  /// Отдать движку имена ВСЕЙ инфраструктуры: серверы подписки и её хост.
  ///
  /// Без этого списка резолв имён других серверов уходит в туннель, который сам
  /// их и ждёт, — и подключение зависает целиком. Обновляем на каждой
  /// пересборке списка: состав серверов меняется при каждом обновлении подписки.
  /// Отдать движку то, что он сам не знает: название подписки и выбранную
  /// раскладку шторки. Движок про подписки и настройки интерфейса не в курсе.
  /// ⚠️ [settings] ОБЯЗАТЕЛЕН, когда настройку только что поменяли.
  ///
  /// Раньше метод всегда читал значение С ДИСКА, а вызывался сразу после
  /// `controller.update(...)`, которую никто не ждал: запись идёт через
  /// временный файл с переименованием, и к моменту чтения на диске лежало ещё
  /// СТАРОЕ значение. Движку доставалось прежнее, шторка не менялась — ровно
  /// жалоба владельца «не работает кнопка смены шторки».
  ///
  /// Чтение с диска осталось только для стартового вызова, когда в памяти
  /// настроек ещё нет.
  /// Подписать владельца настроек на кнопку сворачивания в шторке.
  ///
  /// Вызывается из `main.dart`: сохранить выбор может только тот, у кого есть
  /// настройки, а движку они не принадлежат.
  set onCompactToggledInShade(void Function(bool compact)? handler) =>
      _engine.onCompactToggledInShade = handler;

  Future<void> publishNotificationLayout({AppSettings? settings}) async {
    _engine.subscriptionTitle = _info.title ?? '';
    // Значок подписки в шторке: тот же файл, что показывается в карточке.
    _engine.subscriptionLogoPath = _logoPath ?? '';
    _engine.compactNotification =
        (settings ?? await SettingsStorage().load()).compactNotification;
  }

  LocalApiServer? _api;

  /// Поколение вызовов [applyApiSettings] — тот же приём, что у сессий
  /// движка (`EngineBase._generation`/`newGeneration`/`isStale`).
  ///
  /// ⚠️ РАУНД РЕВЬЮ 1, НАХОДКА 5. Метод не был awaitится с гарантией
  /// единственности: два вызова подряд (например, две быстрые правки токена)
  /// могли ОБА дойти до `await _api?.stop()`/`await srv.start()`, и который из
  /// них последним запишет `_api`, зависело от порядка возврата из await —
  /// ссылка на уже стартовавший `HttpServer` терялась молча (сокет остаётся
  /// слушать, а `stop()` его больше никогда не найдёт). Здесь — как в
  /// движке: вызов, переставший быть последним, не трогает `_api` и гасит за
  /// собой сервер, если успел его поднять.
  int _apiGeneration = 0;

  /// Поднять или погасить API по настройкам.
  ///
  /// ⚠️ ТОЛЬКО WINDOWS. На Android локальные порты видит любое установленное
  /// приложение, и отдельная история по безопасности там ещё не проработана.
  /// Правило проекта: где нет изоляции, канал не поднимается вовсе.
  ///
  /// [port] переопределяется только тестами — прод всегда использует
  /// `ApiPorts.control`, иначе `LocalApiServer` не поднялся бы на другом.
  Future<void> applyApiSettings(AppSettings s, ProbeController probe,
      SettingsController settings,
      {int port = ApiPorts.control}) async {
    final gen = ++_apiGeneration;
    await _api?.stop();
    // Пока мы ждали остановки прошлого сервера, могла прилететь ещё одна
    // правка настроек и запустить параллельный вызов, который уже успел
    // стать текущим поколением. Наш вызов устарел — не трогаем `_api`.
    if (gen != _apiGeneration) return;
    _api = null;
    if (!Platform.isWindows || !s.apiEnabled) return;
    final srv = LocalApiServer(
      token: s.apiToken,
      handlers: AppStateApiHandlers(this, probe, settings),
      port: port,
    );
    final started = await srv.start();
    if (gen != _apiGeneration) {
      // Устарели уже ПОСЛЕ старта: сервер поднялся, но хозяином становится
      // более новый вызов. Не гасим за собой чужой сервер — чужой (новый)
      // вызов ещё до него не дошёл, — только СВОЙ, если он поднялся.
      if (started) await srv.stop();
      return;
    }
    if (started) _api = srv;
    notifyListeners();
  }

  void _publishServerDomains() {
    final domains = <String>{};
    for (final s in _servers) {
      final a = s.address.trim();
      if (a.isNotEmpty) domains.add(a);
    }
    // Хост подписки: её автообновление тоже не должно ходить через туннель,
    // иначе обновиться нельзя ровно тогда, когда серверы перестали работать.
    for (final p in _profiles) {
      final h = Uri.tryParse(p.url)?.host ?? '';
      if (h.isNotEmpty) domains.add(h);
    }
    _engine.knownServerDomains = domains.toList();
  }

  bool _selectServerByName(String name) {
    String norm(String v) =>
        FlagUtil.strip(v).toLowerCase().replaceAll('ё', 'е').trim();
    final want = norm(name);

    var idx = _servers.indexWhere((s) => norm(s.remark) == want);
    if (idx < 0) {
      final hits = ServerSearch.matchIndices(_servers, name);
      if (hits.isEmpty) return false;
      idx = hits.first;
    }
    if (idx == _selectedIndex) return true;
    _selectedIndex = idx;
    AppLog.i('Сервер выбран по имени из ссылки: ${_servers[idx].displayName}');
    unawaited(_persist());
    notifyListeners();
    return true;
  }

  /// Обработать входящую ссылку silentgate:// — импорт ИЛИ управление VPN.
  Future<void> handleIncomingUrl(String url) async {
    final settings = await SettingsStorage().load();

    // Управляющие схемы: connect / disconnect / toggle / update.
    final action = AppUrlScheme.controlAction(url);
    if (action != null) {
      // Выбор сервера ПО ИМЕНИ, которое присылает подписка:
      // `silentgate://connect?server=Польша 1.5`.
      //
      // Это единственный способ переключать сервер снаружи. Прямая правка файла
      // состояния не годится: при загрузке выбор ремапится по ключу сервера, и
      // записанный индекс либо бьёт в чужой сервер, либо теряется вовсе —
      // проверено на 16 прогонах, все ушли через один и тот же узел.
      final wanted = AppUrlScheme.serverName(url);
      if (wanted != null && (action == 'connect' || action == 'toggle')) {
        if (!_selectServerByName(wanted)) {
          _error = 'Сервер «$wanted» не найден';
          notifyListeners();
          return;
        }
      }
      switch (action) {
        case 'connect':
          if (!_status.isConnected &&
              _status.state != VpnConnectionState.connecting) {
            await toggleConnection(settings);
          }
          break;
        case 'disconnect':
          await disconnect();
          break;
        case 'toggle':
          await toggleConnection(settings);
          break;
        case 'update':
          if (_subscriptionUrl != null) await refreshSubscription();
          break;
      }
      return;
    }

    // Импорт: разворачиваем silentgate://import?url=… / ?config=… во внутреннее
    // значение (URL подписки или ссылка сервера), остальное — как есть.
    final payload = AppUrlScheme.importPayload(url) ?? url;
    await importSource(payload);
    if (_error == null &&
        hasServers &&
        !_status.isConnected &&
        settings.autoConnectAfterImport) {
      await toggleConnection(settings);
    }
  }

  Future<void> _persist() async {
    await _storage.save({
      'subscriptionUrl': _subscriptionUrl,
      'servers': _subServers.map((s) => s.rawLink).toList(),
      'selectedIndex': _selectedIndex,
      'selectedVariant': _selectedVariant.toJson(),
      'logoPath': _logoPath,
      'info': _info.toJson(), // #5 — карточка подписки полная сразу после запуска
    });
  }

  /// Пересобрать отображаемый список: закреплённые сверху + подписка (dedupe по ключу),
  /// с применением JSON-override к объектам (для подключения и пинга).
  ///
  /// Выбор следует за СЕРВЕРОМ, а не за позицией: пин вставляет наверх и сдвигает
  /// список — без ремапа по ключу Connect молча подключал бы другой сервер.
  void _rebuild() {
    final prevKey = (_selectedIndex >= 0 && _selectedIndex < _servers.length)
        ? _servers[_selectedIndex].key
        : null;

    final pinnedKeys = _pinned.map((s) => s.key).toSet();
    final base = [
      ..._pinned,
      ..._subServers.where((s) => !pinnedKeys.contains(s.key)),
    ];
    _servers = base.map((s) {
      var srv = s;
      // Конфиг панели (пережил перезапуск в отдельном сторе): для обычных серверов —
      // авторитетный outbound, для профилей «Авто …» — полный конфиг с балансировщиком.
      final panel = _panelConfigs[srv.key];
      if (panel != null) {
        if ((srv.rawOutboundJson ?? '').isEmpty &&
            (panel.outbound ?? '').isNotEmpty) {
          srv = srv.copyWith(rawOutboundJson: panel.outbound);
        }
        if ((srv.rawPanelConfig ?? '').isEmpty &&
            (panel.fullConfig ?? '').isNotEmpty) {
          srv = srv.copyWith(rawPanelConfig: panel.fullConfig);
        }
      }
      final ov = _overrides[srv.key];
      if (ov?.rawJson != null &&
          ov!.rawJson!.isNotEmpty &&
          (srv.rawJsonOverride == null || srv.rawJsonOverride!.isEmpty)) {
        srv = srv.copyWith(rawJsonOverride: ov.rawJson);
      }
      return srv;
    }).toList();

    // ⚠️ ДО любых ранних выходов ниже: движку нужен полный список имён, иначе
    // резолв чужих серверов уйдёт в туннель и подключение зациклится.
    _publishServerDomains();
    unawaited(publishNotificationLayout());
    // Здесь же, а не в конце метода: ниже есть ранний выход, и указатель
    // «чей это сервер» на самом частом пути (сервер тот же) не обновлялся бы.
    _rebuildOwnerIndex();

    if (prevKey != null) {
      final idx = _servers.indexWhere((s) => s.key == prevKey);
      // Сервер пропал из подписки — встаём на первый, а не на «соседа по индексу».
      _selectedIndex = idx >= 0 ? idx : (_servers.isNotEmpty ? 0 : -1);
      return;
    }
    if (_selectedIndex >= _servers.length) {
      _selectedIndex = _servers.isNotEmpty ? 0 : -1;
    }
  }

  /// Удалить подписку (закреплённые серверы остаются).
  // ── Мульти-подписки ────────────────────────────────────────────────────────
  final SubscriptionsStore _subscriptionsStore = SubscriptionsStore();
  final List<SubscriptionProfile> _profiles = [];
  String? _activeId;

  /// Все импортированные подписки — В ТОМ ПОРЯДКЕ, В КОТОРОМ ИХ ПОКАЗЫВАТЬ.
  ///
  /// ⚠️ НИКАКОЙ СОРТИРОВКИ ЗДЕСЬ НЕТ И БЫТЬ НЕ ДОЛЖНО. Порядок — это данные:
  /// по умолчанию он совпадает с порядком добавления (новая подписка встаёт в
  /// конец), а дальше его задаёт сам пользователь перетаскиванием. Сортировка
  /// по названию или по числу серверов переставляла бы список у него под
  /// руками — в меню из четырёх подписок человек целится мышью по памяти.
  List<SubscriptionProfile> get subscriptions => List.unmodifiable(_profiles);
  String? get activeSubscriptionId => _activeId;

  /// Проставить дату добавления профилям из старых файлов.
  ///
  /// Даты там нет вовсе, и без этого все подписки выглядели бы добавленными
  /// одновременно. Берём порядок в файле (он и есть порядок добавления) и
  /// раскладываем метки назад по минуте на позицию — так первая в списке
  /// оказывается самой старой, как и было на самом деле.
  void _backfillAddedAt() {
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _profiles.length; i++) {
      if (_profiles[i].addedAt != null) continue;
      _profiles[i] = _profiles[i].copyWith(
          addedAt: now.subtract(Duration(minutes: _profiles.length - i)));
      changed = true;
    }
    if (changed) unawaited(_saveSubscriptions());
  }

  /// Переставить подписку в списке (перетаскивание в меню переключателя).
  ///
  /// Индексы — как их отдаёт `ReorderableListView`; поправка на них живёт в
  /// [reordered], там же и объяснена.
  Future<void> reorderSubscriptions(int oldIndex, int newIndex) async {
    final next = reordered(_profiles, oldIndex, newIndex);
    // Порядок не изменился — не трогаем диск и не дёргаем перерисовку.
    if (identical(next.length, _profiles.length)) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (next[i].id != _profiles[i].id) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _profiles
      ..clear()
      ..addAll(next);
    // ⚠️ СНАЧАЛА УВЕДОМИТЬ, ПОТОМ ПИСАТЬ НА ДИСК. Запись файла — это await, а
    // список перерисовывается сразу после броска: пока мы ждали диск, строка
    // успевала отскочить на старое место и лишь потом прыгнуть на новое.
    // Хуже косметики: в этом же окне у списка на экране был СТАРЫЙ порядок, а
    // в памяти уже новый, и второе быстрое перетаскивание отдало бы индексы
    // старого порядка — переставилась бы не та подписка.
    _rebuildOwnerIndex();
    notifyListeners();
    unawaited(_saveSubscriptions());
  }

  SubscriptionProfile? get _activeProfile {
    if (_profiles.isEmpty) return null;
    final i = _profiles.indexWhere((p) => p.id == _activeId);
    return i >= 0 ? _profiles[i] : _profiles.first;
  }

  Future<void> _saveSubscriptions() {
    _rebuildOwnerIndex();
    return _subscriptionsStore.save(SubscriptionsSnapshot(_profiles, _activeId));
  }

  /// Ссылка сервера → id подписки, которой он принадлежит.
  final Map<String, String> _ownerByLink = {};

  /// Пересобрать указатель «чей это сервер».
  ///
  /// ⚠️ АКТИВНАЯ ПОДПИСКА ИМЕЕТ ПРИОРИТЕТ. Один и тот же сервер вполне может
  /// лежать в двух подписках сразу — тогда он СВОЙ, и подрисовывать ему чужой
  /// значок нельзя. Поэтому активную раскладываем первой, а остальные —
  /// только на свободные места.
  void _rebuildOwnerIndex() {
    _ownerByLink.clear();
    final active = _activeProfile;
    if (active != null) {
      for (final link in active.serverLinks) {
        _ownerByLink[link] = active.id;
      }
    }
    for (final p in _profiles) {
      if (p.id == active?.id) continue;
      for (final link in p.serverLinks) {
        _ownerByLink.putIfAbsent(link, () => p.id);
      }
    }
  }

  /// Подписка, из которой пришёл сервер, если она НЕ активная сейчас.
  ///
  /// Нужна закреплённым серверам: пины общие и переживают переключение
  /// подписки, поэтому в списке рядом оказываются серверы из разных подписок —
  /// внешне неотличимые. Мини-профиль (значок подписки + её имя) возвращает
  /// строке происхождение. Свой сервер и сервер без известного владельца
  /// (например, вставленный руками `json://`) дают null — подрисовывать
  /// нечего.
  SubscriptionProfile? foreignSubscriptionOf(VpnServer server) {
    final id = _ownerByLink[server.rawLink];
    // ⚠️ СВЕРЯЕМСЯ С `_activeProfile`, А НЕ С СЫРЫМ `_activeId`. Индекс выше
    // строится по `_activeProfile`, а у того есть запасной вариант «первый в
    // списке» — на случай, когда `activeId` указывает на профиль, которого нет
    // (загрузчик выбрасывает профили с пустым url; файл могли править руками).
    // Пока сравнение шло с `_activeId`, эти двое расходились, и тогда значок
    // «чужая подписка» получал КАЖДЫЙ сервер списка — с именем той самой
    // подписки, которая сейчас и открыта.
    if (id == null || id == _activeProfile?.id) return null;
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Кэшированный логотип профиля по id (если файл ещё на месте), иначе null.
  String? _cachedLogoFor(String id) {
    for (final p in _profiles) {
      if (p.id != id) continue;
      final lp = p.logoPath;
      return (lp != null && lp.isNotEmpty && File(lp).existsSync()) ? lp : null;
    }
    return null;
  }

  /// Обновить профиль НА ДИСКЕ, не трогая экран.
  ///
  /// Нужно, когда загрузка подписки вернулась уже после того, как пользователь
  /// переключился на другую: выбрасывать свежие данные жалко (в следующий раз
  /// он увидит их без повторного запроса), а показывать — нельзя, он смотрит
  /// на чужую подписку. Профиль, которого уже нет, НЕ воскрешаем.
  Future<void> _updateProfileQuietly(
      String url, SubscriptionInfo info, List<VpnServer> servers) async {
    final id = SubscriptionProfile.idFor(url);
    final i = _profiles.indexWhere((p) => p.id == id);
    if (i < 0) return; // подписку удалили, пока ждали ответ
    _profiles[i] = _profiles[i].copyWith(
      info: info,
      serverLinks: servers.map((s) => s.rawLink).toList(),
    );
    await _saveSubscriptions();
  }

  /// Запомнить/обновить профиль по итогам загрузки подписки.
  Future<void> _upsertProfile(String url) async {
    final id = SubscriptionProfile.idFor(url);
    // Сохраняем прежний logoUrl профиля — _refreshLogo сравнивает с ним, чтобы
    // не перекачивать неизменившуюся картинку.
    String? keepLogoUrl;
    // ⚠️ И прежнюю дату добавления: обновление подписки — не повторное
    // добавление. Иначе профиль каждый раз «молодел» бы, а с ним ехал бы
    // и порядок по дате.
    DateTime? keepAddedAt;
    for (final p in _profiles) {
      if (p.id == id) {
        keepLogoUrl = p.logoUrl;
        keepAddedAt = p.addedAt;
        break;
      }
    }
    final profile = SubscriptionProfile(
      id: id,
      url: url,
      info: _info,
      logoPath: _logoPath,
      logoUrl: keepLogoUrl,
      serverLinks: _subServers.map((s) => s.rawLink).toList(),
      addedAt: keepAddedAt ?? DateTime.now(),
    );
    final i = _profiles.indexWhere((p) => p.id == id);
    if (i >= 0) {
      _profiles[i] = profile;
    } else {
      _profiles.add(profile);
    }
    _activeId = id;
    await _saveSubscriptions();
  }

  /// Переключиться на другую подписку: список серверов, карточка и логотип —
  /// её собственные. Пины, override и пинги общие (ключ = сам сервер).
  Future<void> switchSubscription(String id) async {
    final i = _profiles.indexWhere((p) => p.id == id);
    if (i < 0 || id == _activeId) return;
    final p = _profiles[i];
    _activeId = id;
    _subscriptionUrl = p.url;
    _info = p.info;
    _logoPath = (p.logoPath ?? '').isNotEmpty && File(p.logoPath!).existsSync()
        ? p.logoPath
        : null;
    _subServers =
        p.serverLinks.map(_serverFromStoredLink).whereType<VpnServer>().toList();
    _lastSync = null;
    _rebuild();
    if (_selectedIndex < 0 && _servers.isNotEmpty) _selectedIndex = 0;
    await _saveSubscriptions();
    await _persist();
    await _maybeStartUpdater();
    AppLog.i('Активная подписка: ${p.title} (${_subServers.length} серверов)');
    if (_status.isConnected) {
      _pendingRestart = 'Подписка переключена — переподключитесь, чтобы применить';
    }
    notifyListeners();
  }

  /// Есть ли закреплённые серверы (спрашиваем при удалении подписки, #5).
  bool get hasPinned => _pinned.isNotEmpty;
  int get pinnedCount => _pinned.length;

  /// Удалить подписку. [removePinned] — заодно убрать закреплённые серверы:
  /// они переживают подписку, и без явного вопроса пользователь не понимает,
  /// почему список не опустел.
  Future<void> deleteSubscription({bool removePinned = false}) async {
    // Удаляем активный профиль; если остались другие — переключаемся на первый.
    _profiles.removeWhere((p) => p.id == _activeId);
    final next = _profiles.isNotEmpty ? _profiles.first : null;
    _activeId = next?.id;
    await _saveSubscriptions();

    if (next != null) {
      _subscriptionUrl = next.url;
      _info = next.info;
      _logoPath = next.logoPath;
      _subServers = next.serverLinks
          .map(_serverFromStoredLink)
          .whereType<VpnServer>()
          .toList();
      if (removePinned) {
        _pinned.clear();
        await _pinnedStore.save(const []);
      }
      _rebuild();
      await _persist();
      AppLog.i('Подписка удалена, активной стала «${next.title}»');
      notifyListeners();
      return;
    }

    _subServers = [];
    _subscriptionUrl = null;
    _info = SubscriptionInfo.empty;
    _lastSync = null;
    if (removePinned) {
      _pinned.clear();
      await _pinnedStore.save(const []);
      _overrides.clear();
      await _overridesStore.save(_overrides);
    }
    _panelConfigs.clear();
    await _panelOutboundsStore.save(_panelConfigs);
    _rebuild();
    _updater.stop();
    await _persist();
    AppLog.i('Подписка удалена'
        '${removePinned ? " вместе с закреплёнными" : ""}');
    notifyListeners();
  }

  /// Запустить/остановить автообновление в зависимости от настроек и наличия подписки.
  Future<void> _maybeStartUpdater() async {
    final s = await SettingsStorage().load();
    if (s.autoUpdateEnabled && _subscriptionUrl != null) {
      // Интервал: по умолчанию наше значение (приоритет ВЫШЕ подписки). Галочка
      // «брать из подписки» → интервал панели (наш — фолбэк, если панель молчит).
      final hours = resolveAutoUpdateIntervalHours(
        preferSubscription: s.autoUpdatePreferSubscription,
        subscriptionHours: _info.updateIntervalHours,
        fieldHours: s.autoUpdateIntervalHours,
      );
      _updater.start(intervalHours: hours);
    } else {
      _updater.stop();
    }
  }

  bool isPinned(VpnServer server) => _pinned.any((s) => s.key == server.key);

  Future<void> togglePin(VpnServer server) async {
    if (isPinned(server)) {
      _pinned.removeWhere((s) => s.key == server.key);
    } else {
      _pinned.insert(0, server); // #3 — закреплённый встаёт наверх списка
    }
    await _pinnedStore.save(_pinned.map((s) => s.rawLink).toList());
    _rebuild();
    await _persist(); // selectedIndex мог смениться вместе с порядком
    notifyListeners();
  }

  Future<void> removeServer(VpnServer server) async {
    _subServers.removeWhere((s) => s.key == server.key);
    _pinned.removeWhere((s) => s.key == server.key);
    await _pinnedStore.save(_pinned.map((s) => s.rawLink).toList());
    // Список серверов на диске живёт в профиле подписки: без этого удалённый
    // сервер возвращался после каждого перезапуска.
    await _syncActiveProfileServers();
    _rebuild();
    await _persist();
    notifyListeners();
  }

  /// Записать текущий состав серверов в активный профиль подписки.
  Future<void> _syncActiveProfileServers() async {
    if (_profiles.isEmpty) return;
    final i = _profiles.indexWhere((p) => p.id == _activeId);
    if (i < 0) return;
    _profiles[i] = _profiles[i]
        .copyWith(serverLinks: _subServers.map((s) => s.rawLink).toList());
    await _saveSubscriptions();
  }

  /// Сохранить правку сервера (из редактора). Правленый сервер закрепляется, чтобы пережить подписку.
  Future<void> saveEditedServer(VpnServer original, VpnServer edited) async {
    _pinned.removeWhere((s) => s.key == original.key);
    _pinned.add(edited);
    await _pinnedStore.save(_pinned.map((s) => s.rawLink).toList());
    _rebuild();
    final idx = _servers.indexWhere((s) => s.key == edited.key);
    if (idx >= 0) _selectedIndex = idx;
    notifyListeners();
  }

  // ── Override серверов (не связан с пином, переживает; #8.1) ──────────────────
  ServerOverride? overrideFor(VpnServer s) => _overrides[s.key];

  /// #6 — сохранённая вариация сервера (для пинга: без неё fragment-серверы «n/a»).
  OutboundVariant variantFor(VpnServer s) =>
      _overrides[s.key]?.variant ?? OutboundVariant.none;

  Future<void> setJsonOverride(VpnServer server, String? json) async {
    final cur = _overrides[server.key] ?? const ServerOverride();
    final next = (json == null || json.trim().isEmpty)
        ? cur.copyWith(clearJson: true)
        : cur.copyWith(rawJson: json);
    if (next.isEmpty) {
      _overrides.remove(server.key);
    } else {
      _overrides[server.key] = next;
    }
    await _overridesStore.save(_overrides);
    notifyListeners();
  }

  Future<void> setVariant(VpnServer server, OutboundVariant variant) async {
    final cur = _overrides[server.key] ?? const ServerOverride();
    _overrides[server.key] = cur.copyWith(variant: variant);
    await _overridesStore.save(_overrides);
    notifyListeners();
  }

  Future<void> clearOverride(VpnServer server) async {
    _overrides.remove(server.key);
    await _overridesStore.save(_overrides);
    notifyListeners();
  }

  /// Закрепить сервер с рабочей вариацией (из автонастройки; #1).
  ///
  /// #3 — вставляем В НАЧАЛО: `add` уводил найденные в конец блока закреплённых
  /// (а если закреплены все серверы — в самый конец списка), хотя они должны быть сверху.
  Future<void> pinWithVariant(VpnServer server, OutboundVariant variant) async {
    final idx = _pinned.indexWhere((s) => s.key == server.key);
    if (idx != 0) {
      if (idx > 0) _pinned.removeAt(idx);
      _pinned.insert(0, server);
      await _pinnedStore.save(_pinned.map((s) => s.rawLink).toList());
    }
    await setVariant(server, variant);
    _rebuild();
    notifyListeners();
  }

  // ── Импорт подписки ─────────────────────────────────────────────────────────
  /// Принимает URL подписки, deep link silentgate://import-sub?url=… или одиночную share-ссылку.
  Future<void> importSource(String input) async {
    _error = null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    // #8 — вставленный JSON-конфиг: кастом-сервер, НЕ трактуем как URL (иначе зависание).
    if (trimmed.startsWith('{')) {
      await _importJsonConfig(trimmed);
      return;
    }

    // Одиночная share-ссылка — без сети.
    //
    // Добавляется как ЗАКРЕПЛЁННЫЙ сервер, а не подменяет собой список подписки:
    //  * раньше вставка ссылки стирала из UI все серверы подписки, а после
    //    перезапуска сама же и пропадала (список читается из профиля подписки);
    //  * для hysteria2 это вообще основной способ добавить сервер — Remnawave
    //    такие ссылки в XRAY_JSON не отдаёт.
    final single = ShareLinkParser.tryParse(trimmed);
    if (single != null) {
      _pinned.removeWhere((s) => s.key == single.key);
      _pinned.insert(0, single);
      await _pinnedStore.save(_pinned.map((s) => s.rawLink).toList());
      _rebuild();
      final idx = _servers.indexWhere((s) => s.key == single.key);
      _selectedIndex = idx >= 0 ? idx : 0;
      _selectedVariant = OutboundVariant.none;
      await _persist();
      notifyListeners();
      return;
    }

    final url = _extractSubUrl(trimmed);
    // Импорт ДРУГОЙ подписки не должен показывать логотип прежней: сразу ставим
    // логотип целевого профиля (если он уже в кэше) либо снимаем совсем — до
    // буквы названия, пока _refreshLogo не подтянет актуальную картинку.
    final incomingId = SubscriptionProfile.idFor(url);
    if (incomingId != _activeId) {
      _logoPath = _cachedLogoFor(incomingId);
    }
    // ⚠️ КАКАЯ ПОДПИСКА БЫЛА АКТИВНА, КОГДА МЫ ПОШЛИ В СЕТЬ.
    //
    // `SubscriptionService.fetch` идёт без своего таймаута — ждать можно
    // десятки секунд, и всё это время переключатель подписок остаётся
    // нажимаемым (блокируется только кнопка «Обновить»). Пользователь уходит
    // на другую подписку, экран честно показывает её серверы и карточку — а
    // потом возвращается ответ ПРЕЖНЕЙ и молча подменяет всё: список серверов,
    // карточку, активную подписку, логотип, сводку изменений. И это ещё
    // персистится, то есть переживает перезапуск.
    //
    // Признак устаревания — смена активной подписки за время ожидания, а НЕ
    // «пришло не то, что сейчас активно»: импорт ВТОРОЙ подписки обязан
    // сделать её активной, и запретить это было бы новой поломкой.
    final startedActive = _activeId;
    _loading = true;
    notifyListeners();
    try {
      final result =
          await _subscription.fetch(
        url,
        deviceHeaders: await _deviceHeaders(),
      );
      // Панельные конфиги ключуются САМИМ СЕРВЕРОМ и общие для всех подписок —
      // их сохраняем в любом случае, устарел ответ или нет.
      var withOutbound = 0, withFullConfig = 0;
      for (final s in result.servers) {
        final ob = s.rawOutboundJson;
        final full = s.rawPanelConfig;
        if ((ob ?? '').isEmpty && (full ?? '').isEmpty) continue;
        if ((ob ?? '').isNotEmpty) withOutbound++;
        if ((full ?? '').isNotEmpty) withFullConfig++;
        _panelConfigs[s.key] = PanelConfig(outbound: ob, fullConfig: full);
      }
      await _panelOutboundsStore.save(_panelConfigs);

      if (_activeId != startedActive) {
        // Пользователь ушёл на другую подписку. Данные не выбрасываем — кладём
        // в её профиль на диск, чтобы при возврате они уже были свежими.
        await _updateProfileQuietly(url, result.info, result.servers);
        AppLog.i('Ответ подписки пришёл после переключения на другую — '
            'записан в её профиль, экран не трогаем '
            '(${result.servers.length} серверов)');
        return;
      }

      // #1.1 — что изменилось по сравнению с прошлым составом подписки.
      final before = {for (final s in _subServers) s.key: s.displayName};

      _subServers = result.servers;
      // Панель увела редиректом — дальше ходим по новому адресу, иначе после
      // выключения старого домена обновления молча прекратятся.
      final effectiveUrl = result.movedTo ?? url;
      _rebuild(); // сам переназначает выбор по ключу сервера
      _info = result.info;
      _subscriptionUrl = effectiveUrl;
      // Выбор и вариацию НЕ сбрасываем: при автообновлении подписки это молча
      // перекидывало пользователя на первый сервер (и теряло fragment/fingerprint).
      // Сбрасываем только если выбранный сервер из подписки пропал.
      if (_selectedIndex < 0 && _servers.isNotEmpty) _selectedIndex = 0;
      await _persist();
      // Мульти-подписки: запоминаем/обновляем профиль и делаем его активным.
      await _upsertProfile(effectiveUrl);
      await _maybeStartUpdater();
      // Аватарку тянем ЗДЕСЬ (импорт/обновление), не в фоне и не на старте.
      await _refreshLogo(url);

      final after = {for (final s in result.servers) s.key: s.displayName};
      _lastSync = SubscriptionSyncResult(
        total: result.servers.length,
        added: [
          for (final e in after.entries)
            if (!before.containsKey(e.key)) e.value,
        ],
        removed: [
          for (final e in before.entries)
            if (!after.containsKey(e.key)) e.value,
        ],
        withPanelConfig: withOutbound,
        panelProfiles: withFullConfig,
        at: DateTime.now(),
      );
      AppLog.i('Подписка обновлена: ${_lastSync!.summary} '
          '(конфиг панели: $withOutbound, профилей «Авто»: $withFullConfig)');
    } catch (e) {
      _error = e.toString();
      _errorCode = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Восстановление сервера из сохранённой ссылки.
  ///
  /// `panel://…` — профиль «Авто …» от панели: его нельзя разобрать как share-ссылку,
  /// сервер собирается из сохранённого полного конфига.
  VpnServer? _serverFromStoredLink(String link) {
    if (link.startsWith('panel://')) {
      final cfg = _panelConfigs[link]?.fullConfig;
      if (cfg == null || cfg.isEmpty) return null;
      return XrayJsonSubscription.fromPanelConfig(cfg);
    }
    return ShareLinkParser.tryParse(link);
  }

  // ── Импорт полного JSON-конфига как кастом-сервера (#8) ─────────────────────
  VpnServer? _serverFromPinned(String link) {
    if (link.startsWith('json://')) {
      final ov = _overrides[link];
      return ov?.rawJson != null ? _customServerFromJson(link, ov!.rawJson!) : null;
    }
    return _serverFromStoredLink(link);
  }

  VpnServer _customServerFromJson(String key, String json) {
    String addr = 'config';
    int port = 0;
    try {
      final data = jsonDecode(json);
      final outs = data is Map ? data['outbounds'] : null;
      if (outs is List) {
        for (final o in outs) {
          if (o is! Map) continue;
          final settings = o['settings'];
          final list =
              settings is Map ? (settings['vnext'] ?? settings['servers']) : null;
          if (list is List && list.isNotEmpty && list.first is Map) {
            addr = '${(list.first as Map)['address'] ?? 'config'}';
            port = ((list.first as Map)['port'] as num?)?.toInt() ?? 0;
            break;
          }
        }
      }
    } catch (_) {}
    return VpnServer(
      protocol: 'vless',
      remark: '📋 Импортированный конфиг',
      address: addr,
      port: port,
      id: '',
      network: 'tcp',
      security: 'none',
      rawLink: key,
      rawJsonOverride: json,
    );
  }

  Future<void> _importJsonConfig(String json) async {
    try {
      jsonDecode(json);
    } catch (_) {
      _fail(AppErrorCode.invalidJson);
      return;
    }
    final key = 'json://${json.hashCode.toUnsigned(32)}';
    final server = _customServerFromJson(key, json);
    _pinned.removeWhere((s) => s.key == key);
    _pinned.add(server);
    await _pinnedStore.save(_pinned.map((s) => s.rawLink).toList());
    _overrides[key] = ServerOverride(rawJson: json);
    await _overridesStore.save(_overrides);
    _rebuild();
    _selectedIndex = _servers.indexWhere((s) => s.key == key);
    _error = null;
    notifyListeners();
  }

  // ── Аватарка подписки ───────────────────────────────────────────────────────
  /// Тянет логотип подписки. Вызывается ТОЛЬКО при импорте/обновлении подписки
  /// (не в фоне и не на старте). Неудача не ломает подписку.
  Future<void> _refreshLogo(String url) async {
    // За какую подписку тянем логотип. Если во время сетевого ожидания
    // пользователь ПЕРЕКЛЮЧИТ подписку — не записываем результат в чужой профиль.
    final startedId = _activeId ?? SubscriptionProfile.idFor(url);
    bool switchedAway() => (_activeId ?? SubscriptionProfile.idFor(url)) != startedId;
    // Есть ли уже валидная картинка (чтобы не мигать на букву из-за разовой ошибки).
    bool haveLogo() =>
        (_logoPath ?? '').isNotEmpty && File(_logoPath!).existsSync();
    try {
      final finder = SubscriptionLogo();
      // Логотип ищем автоматически: заголовок ответа панели (`x-logo-url`, если
      // задан) → брендинг панели `/assets/.app-config-v2.json` → разбор страницы.
      final imageUrl = _info.logoUrl?.trim().isNotEmpty == true
          ? _info.logoUrl!.trim()
          : await finder.findUrl(url);
      finder.close();
      if (switchedAway()) return; // подписку переключили — молча выходим
      if (imageUrl == null || imageUrl.isEmpty) {
        // Адрес не нашли. Если картинка уже была — НЕ снимаем её (разовый сбой
        // сети/панели не должен мигать на букву); если не было — показываем букву.
        if (!haveLogo()) {
          AppLog.w('Логотип подписки не найден — показываем букву названия.');
          await _setLogo(null);
        } else {
          AppLog.w('Логотип подписки временно не найден — оставляю прежний.');
        }
        return;
      }

      // Не изменился адрес логотипа и файл на месте — оставляем старую картинку,
      // ничего не перекачиваем (требование: «если не изменилась — оставляй»).
      final active = _activeProfile;
      if (active != null &&
          active.logoUrl == imageUrl &&
          (active.logoPath ?? '').isNotEmpty &&
          File(active.logoPath!).existsSync()) {
        if (_logoPath != active.logoPath) {
          _logoPath = active.logoPath;
          notifyListeners();
        }
        AppLog.i('Логотип подписки не изменился ($imageUrl) — оставляю прежний.');
        return;
      }

      AppLog.i('Логотип подписки: пробую $imageUrl');
      // Своё имя файла на подписку — чтобы логотипы разных подписок не затирали
      // друг друга (раньше всё писалось в один sub_logo.*, и после смены подписки
      // висела старая картинка).
      final name = 'sub_logo_$startedId';
      final finder2 = SubscriptionLogo();
      final path = await finder2.download(imageUrl, cacheName: name);
      finder2.close();
      if (switchedAway()) return; // переключились за время скачивания
      if (path == null) {
        AppLog.w('Логотип найден ($imageUrl), но не скачался — оставляю прежний, '
            'если он был, иначе букву названия.');
        if (!haveLogo()) await _setLogo(null);
        return;
      }
      AppLog.i('Логотип подписки скачан: $path');
      await _setLogo(path, sourceUrl: imageUrl);
    } catch (_) {}
  }

  /// Старый общий файл логотипа (без id подписки в имени): `sub_logo.png/.jpg…`.
  static bool _isLegacyLogo(String path) {
    final name = path.split(RegExp(r'[\\/]')).last.toLowerCase();
    return RegExp(r'^sub_logo\.[a-z0-9]+$').hasMatch(name);
  }

  /// Удаляет старые общие `sub_logo.*` (у каждой подписки теперь свой файл).
  Future<void> _cleanLegacyLogos() async {
    try {
      final dir = await AppPaths.supportDir();
      for (final f in dir.listSync()) {
        if (f is File && _isLegacyLogo(f.path)) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Установить/снять путь логотипа активной подписки и сохранить.
  /// [sourceUrl] — адрес, откуда взята картинка (для сравнения при обновлении).
  Future<void> _setLogo(String? path, {String? sourceUrl}) async {
    _logoPath = path;
    final active = _activeProfile;
    if (active != null) {
      final i = _profiles.indexWhere((p) => p.id == active.id);
      if (i >= 0) {
        _profiles[i] = _profiles[i].copyWith(
          logoPath: path,
          logoUrl: sourceUrl,
          clearLogo: path == null,
        );
        await _saveSubscriptions();
      }
    }
    await _persist();
    notifyListeners();
  }

  /// Обновить текущую подписку из сети.
  Future<void> refreshSubscription() async {
    final url = _subscriptionUrl;
    if (url == null) return;
    // Второе обновление поверх идущего пишет в те же поля: автообновление по
    // таймеру легко наложится на нажатую руками кнопку. Кнопка на время работы
    // гаснет, а таймер о ней не знает — гейт нужен здесь.
    if (_refreshing) {
      AppLog.i('Обновление подписки уже идёт — повторный запуск пропущен');
      return;
    }
    // #1 — видимый признак работы: кнопка показывает крутилку, по завершении
    // выводится сводка «N серверов · +2 · −1».
    _refreshing = true;
    _lastSync = null;
    notifyListeners();
    AppLog.i('Обновление подписки…');
    try {
      await importSource(url);
      if (_error != null) AppLog.e('Обновление подписки: $_error');
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// Скрыть сводку об обновлении (по крестику/таймауту).
  void clearSyncResult() {
    if (_lastSync == null) return;
    _lastSync = null;
    notifyListeners();
  }

  String _extractSubUrl(String input) {
    if (input.startsWith('silentgate://')) {
      final uri = Uri.tryParse(input);
      final u = uri?.queryParameters['url'];
      if (u != null && u.isNotEmpty) return u;
    }
    return input;
  }

  Future<Map<String, String>> _deviceHeaders() async {
    final h = await DeviceHeaders.build();
    return {...h, 'X-App-Version': AppInfo.version};
  }

  void selectServer(int index) {
    if (index < 0 || index >= _servers.length) return;
    final wasKey = selectedServer?.key;
    _selectedIndex = index;
    _selectedVariant = OutboundVariant.none; // ручной выбор — обычная вариация
    // #13 — при активном VPN смена сервера НЕ применяется на лету: предлагаем
    // переподключиться, вместо того чтобы молча оставить старый туннель.
    if (_status.isConnected && wasKey != _servers[index].key) {
      _pendingRestart = 'Выбран другой сервер — переподключитесь, чтобы применить';
    }
    _persist();
    notifyListeners();
  }

  /// #13/#13.1 — что-то изменилось, но применится только после переподключения.
  String? _pendingRestart;
  String? get pendingRestart => _pendingRestart;

  /// Чем именно вызван ожидающий перезапуск — для журнала, а не для экрана.
  ///
  /// На экране висит одна общая фраза «переподключитесь, чтобы применить»;
  /// в журнал нужна конкретика, иначе перезапуск выглядит беспричинным.
  String _pendingRestartDetail = '';

  /// Сообщить, что изменилась настройка, требующая переподключения.
  void notePendingRestart(String reason, {List<String> fields = const []}) {
    if (!_status.isConnected) return;
    _pendingRestart = reason;
    if (fields.isNotEmpty) _pendingRestartDetail = fields.join(', ');
    notifyListeners();
  }

  void clearPendingRestart() {
    if (_pendingRestart == null) return;
    _pendingRestart = null;
    notifyListeners();
  }

  /// Переподключиться: выключить и снова включить с текущими настройками.
  Future<void> reconnect(AppSettings settings) =>
      _reconnectWith(() => toggleConnection(settings));

  /// Переподключиться в режиме «Авто (лучший сервер)» — тот же путь, что
  /// [reconnect], но с автовыбором вместо текущего выбранного сервера.
  ///
  /// ⚠️ Нужен отдельно, а не сводится к `reconnect`: `connectAuto`, как и
  /// `toggleConnection`, — ПЕРЕКЛЮЧАТЕЛЬ (см. её же комментарий), и повторный
  /// вызов на уже живом канале отключил бы VPN вместо смены режима на «Авто».
  /// Нужен команде локального API `connect(auto: true)`, отправленной, пока
  /// канал уже поднят (раунд ревью 1, находка 3).
  Future<void> reconnectAuto(AppSettings settings) =>
      _reconnectWith(() => connectAuto(settings));

  /// Общее тело [reconnect]/[reconnectAuto]: снять, поднять заново через
  /// [connectFn], сохранить отсчёт таймера сессии.
  Future<void> _reconnectWith(Future<void> Function() connectFn) async {
    // ⚠️ БЕЗ ЭТОЙ СТРОКИ ПЕРЕЗАПУСК НЕ ОСТАВЛЯЛ В ЖУРНАЛЕ НИЧЕГО.
    //
    // В логе владельца шесть перезапусков туннеля подряд шли без единого
    // слова о причине: «Автопереподключение: <причина>» пишется только на пути
    // восстановления после обрыва, а перезапуск по правке настроек идёт мимо
    // него — сразу в connect(). Разобрать такой лог нельзя: обрыв связи и
    // собственная правка пользователя выглядят одинаково.
    AppLog.i('Перезапуск туннеля по команде пользователя'
        '${_pendingRestartDetail.isEmpty ? '' : ' (изменено: $_pendingRestartDetail)'}');
    _pendingRestart = null;
    _pendingRestartDetail = '';
    notifyListeners();
    // ⚠️ Отсчёт таймера ПЕРЕЖИВАЕТ этот перезапуск. Пользователь VPN не
    // выключал — он поправил настройку, а туннель мы перетряхиваем сами. Сброс
    // счётчика тут выглядел бы как разрыв сессии, которого не было.
    final keepSince = _connectedAt;
    await disconnect();
    await connectFn();
    // ⚠️ ВОССТАНАВЛИВАЕМ ТОЛЬКО ТО, ЧТО СЕЙЧАС ИДЁТ. Ожидание внутри
    // `connectFn` длится до двух минут (автоподбор стека и MTU на Windows).
    // За это время пользователь успевает нажать «Отключить» в трее или
    // прислать `silentgate://disconnect` — тогда отсчёт уже снят, и слепое
    // присваивание воскресило бы его: VPN выключен, а часы идут, и следующее
    // включение показывает чужое время. Непустое значение здесь означает, что
    // подключение состоялось и `markUserConnect` поставил свою точку.
    if (keepSince != null && _connectedAt != null) _connectedAt = keepSince;
  }

  /// Применить результат автонастройки: закрепить с вариацией и выбрать (без подключения).
  Future<void> applyAutoConfigResult(VpnServer server, OutboundVariant variant) async {
    await pinWithVariant(server, variant);
    final idx = _servers.indexWhere((s) => s.key == server.key);
    if (idx >= 0) _selectedIndex = idx;
    _selectedVariant = variant;
    await _persist();
    notifyListeners();
  }

  // ── Подключение ─────────────────────────────────────────────────────────────
  Future<void> toggleConnection(AppSettings settings) async {
    if (_status.isConnected || _status.state == VpnConnectionState.connecting) {
      AppLog.i('Отключение по команде пользователя');
      markUserDisconnect();
      await _engine.disconnect();
    } else {
      AppLog.i('Подключение по команде пользователя');
      final server = selectedServer;
      if (server == null) {
        _fail(AppErrorCode.pickServerFirst);
        return;
      }
      // Точка отсчёта таймера — ЗДЕСЬ, на нажатии, а не на подъёме туннеля:
      // иначе переподключение снова начнёт обнулять счётчик.
      // ⚠️ Но СТРОГО ПОСЛЕ проверки сервера: нажатие без выбранного сервера
      // (свежая установка, удалили все серверы) заводило часы там, где
      // подключения не будет вовсе, а снять их было нечем.
      markUserConnect();
      final ov = _overrides[server.key];
      final srv = (ov?.rawJson != null && ov!.rawJson!.isNotEmpty)
          ? server.copyWith(rawJsonOverride: ov.rawJson)
          : server;
      _engine.fallbackServers = const []; // ручной выбор не подменяем
      await _engine.connect(
        srv,
        options: ConnectionOptions(
          variant: ov?.variant ?? _selectedVariant,
          settings: settings,
          exitServers: _exitServers(settings),
        ),
      );
    }
  }

  /// Явное отключение (для трея/выхода). No-op только при полностью отключённом
  /// состоянии — connecting/disconnecting тоже гасим (иначе выход сиротит процессы).
  Future<void> disconnect() async {
    markUserDisconnect();
    if (_status.state != VpnConnectionState.disconnected) {
      await _engine.disconnect();
    }
  }

  /// Серверы именованных выходов: ключ правила → живые серверы.
  ///
  /// ⚠️ РАЗРЕШАЕТСЯ ЗДЕСЬ, А НЕ В ДВИЖКЕ. Правило хранит КЛЮЧ сервера
  /// (share-ссылку), и сопоставить его с живым `VpnServer` можно только по
  /// полному каталогу — а каталог есть только тут. Хранить в правиле индекс
  /// было бы короче и неверно: список перестраивается при каждом обновлении
  /// подписки, и правило уехало бы на соседний сервер. Этой ошибкой мы уже
  /// платили за пины и оверрайды.
  ///
  /// Владелец разрешил брать выходы из РАЗНЫХ подписок одновременно, поэтому
  /// ищем по всему `_servers` — объединённому списку, — не разбирая, откуда
  /// сервер пришёл.
  /// Серверы, на которые ссылаются правила раздельного туннелирования.
  ///
  /// ⚠️ Собираем ИЗ ПРАВИЛ, а не из отдельного списка: правило указывает на
  /// сервер напрямую, и любой другой источник рано или поздно разойдётся с тем,
  /// что видит пользователь.
  ///
  /// Основной сервер сессии сюда НЕ попадает — он уже в конфиге под тегом
  /// `proxy`. Иначе к одному узлу держались бы два соединения, а панель
  /// показывала бы удвоенный «онлайн».
  Map<String, VpnServer> _exitServers(AppSettings settings) {
    if (_servers.isEmpty) return const {};
    final wanted = <String>{
      for (final r in settings.splitTunnel.sites)
        if (r.action == AppAction.tunnel && (r.serverKey ?? '').isNotEmpty)
          r.serverKey!,
      for (final r in settings.splitTunnel.apps)
        if (r.enabled &&
            r.action == AppAction.tunnel &&
            (r.serverKey ?? '').isNotEmpty)
          r.serverKey!,
    };
    // Серверы, которым пользователь выдал отдельный порт, тоже обязаны получить
    // outbound — иначе порт не создастся (построитель проверяет живые теги).
    for (final key in settings.apiExitServerKeys) {
      if (key.isNotEmpty) wanted.add(key);
    }
    if (wanted.isEmpty) return const {};
    wanted.remove(selectedServer?.key);
    final byKey = <String, VpnServer>{
      for (final s in _servers)
        if (s.key.isNotEmpty) s.key: s,
    };
    final out = <String, VpnServer>{};
    for (final k in wanted) {
      final srv = byKey[k];
      if (srv == null) continue;
      // Правка из JSON-редактора применяется и здесь — иначе сервер вёл бы
      // себя не так, как тот же сервер, выбранный вручную.
      final ov = _overrides[srv.key];
      out[k] = (ov?.rawJson != null && ov!.rawJson!.isNotEmpty)
          ? srv.copyWith(rawJsonOverride: ov.rawJson)
          : srv;
    }
    return out;
  }

  /// Кандидаты на подмену в режиме «Авто»: сначала профили «Авто …» от панели
  /// (у них свой балансировщик), затем обычные серверы. Порядок — как в списке,
  /// то есть закреплённые и найденные автонастройкой идут первыми.
  List<VpnServer> _fallbackCandidates() {
    final profiles = _servers.where((s) => s.isPanelProfile).toList();
    final plain = _servers.where((s) => !s.isPanelProfile).toList();
    return [...profiles, ...plain].take(5).toList();
  }

  /// Автовыбор лучшего сервера (balancer + burstObservatory по всем серверам).
  Future<void> connectAuto(AppSettings settings) async {
    if (_status.isConnected || _status.state == VpnConnectionState.connecting) {
      markUserDisconnect();
      await _engine.disconnect();
      return;
    }
    if (_servers.isEmpty) {
      _fail(AppErrorCode.importSubscriptionFirst);
      return;
    }
    // Режим «Авто (лучший сервер)»: если текущий не поднимется после всех попыток,
    // движок переключится на следующий из этого списка. Ручной выбор не подменяем.
    markUserConnect();
    _engine.fallbackServers = _fallbackCandidates();
    await _engine.connectBalancer(
      _servers,
      options: ConnectionOptions(
          settings: settings, exitServers: _exitServers(settings)),
    );
  }

  /// Распознанная ошибка: код для UI + русский фолбэк в [_error] (он уходит
  /// в лог и отчёт поддержки, которые не переводятся).
  void _fail(AppErrorCode code) {
    _errorCode = code;
    _error = code.fallback;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    _errorCode = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _statsSub.cancel();
    _incomingSub.cancel();
    _networkSub.cancel();
    _blockedSub?.cancel();
    _noticeSub?.cancel();
    _networkWatcher.dispose();
    _updater.stop();
    _engine.dispose();
    _subscription.close();
    super.dispose();
  }

  /// Показать/снять признак «kill switch держит трафик» вне окна приложения.
  ///
  /// На Windows это подсказка трея: полноценное системное уведомление
  /// потребовало бы новой зависимости, а подсказка есть уже сейчас и видна при
  /// свёрнутом окне. На Android то же самое делает уведомление сервиса — оно
  /// живёт в шторке и работает при закрытом приложении (см. `showBlocked`).
  Future<void> _reflectBlocking(bool blocking) async {
    if (!Platform.isWindows) return;
    try {
      await TrayWindow.setBlocked(blocking);
    } catch (_) {
      // Трей может быть недоступен (запуск без окна) — не повод падать.
    }
  }

}
