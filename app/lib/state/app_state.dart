import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_info.dart';
import '../core/models/subscription_info.dart';
import '../core/models/subscription_profile.dart';
import '../core/models/subscription_sync.dart';
import '../core/models/traffic_stats.dart';
import '../core/models/vpn_server.dart';
import '../core/models/vpn_status.dart';
import '../core/parser/share_link_parser.dart';
import '../core/platform/app_log.dart';
import '../core/platform/app_paths.dart';
import '../core/platform/network_watcher.dart';
import '../core/platform/hwid_windows.dart';
import '../core/platform/incoming_links.dart';
import '../core/platform/url_scheme_windows.dart';
import '../core/settings/app_settings.dart';
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
      _status = s;
      _trackAutotune(s);
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
  bool get hasServers => _servers.isNotEmpty;

  // ── Инициализация из хранилища ─────────────────────────────────────────────
  Future<void> init() async {
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

    final legacyLinks = (data['servers'] as List?)?.cast<String>() ?? const [];
    if (_profiles.isEmpty && (_subscriptionUrl ?? '').isNotEmpty) {
      _profiles.add(SubscriptionProfile(
        id: SubscriptionProfile.idFor(_subscriptionUrl!),
        url: _subscriptionUrl!,
        info: _info,
        logoPath: _logoPath,
        serverLinks: legacyLinks,
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
    // Логотип на старте НЕ тянем: только при импорте/обновлении подписки
    // (см. importSource/_refreshLogo). Здесь показываем то, что уже в кэше.
  }

  /// Обработать входящую ссылку silentgate:// — импорт ИЛИ управление VPN.
  Future<void> handleIncomingUrl(String url) async {
    final settings = await SettingsStorage().load();

    // Управляющие схемы: connect / disconnect / toggle / update.
    final action = UrlSchemeWindows.controlAction(url);
    if (action != null) {
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
    final payload = UrlSchemeWindows.importPayload(url) ?? url;
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

  /// Все импортированные подписки.
  List<SubscriptionProfile> get subscriptions => List.unmodifiable(_profiles);
  String? get activeSubscriptionId => _activeId;

  SubscriptionProfile? get _activeProfile {
    if (_profiles.isEmpty) return null;
    final i = _profiles.indexWhere((p) => p.id == _activeId);
    return i >= 0 ? _profiles[i] : _profiles.first;
  }

  Future<void> _saveSubscriptions() =>
      _subscriptionsStore.save(SubscriptionsSnapshot(_profiles, _activeId));

  /// Кэшированный логотип профиля по id (если файл ещё на месте), иначе null.
  String? _cachedLogoFor(String id) {
    for (final p in _profiles) {
      if (p.id != id) continue;
      final lp = p.logoPath;
      return (lp != null && lp.isNotEmpty && File(lp).existsSync()) ? lp : null;
    }
    return null;
  }

  /// Запомнить/обновить профиль по итогам загрузки подписки.
  Future<void> _upsertProfile(String url) async {
    final id = SubscriptionProfile.idFor(url);
    // Сохраняем прежний logoUrl профиля — _refreshLogo сравнивает с ним, чтобы
    // не перекачивать неизменившуюся картинку.
    String? keepLogoUrl;
    for (final p in _profiles) {
      if (p.id == id) {
        keepLogoUrl = p.logoUrl;
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
    _loading = true;
    notifyListeners();
    try {
      final result =
          await _subscription.fetch(
        url,
        deviceHeaders: await _deviceHeaders(),
      );
      // #1.1 — что изменилось по сравнению с прошлым составом подписки.
      final before = {for (final s in _subServers) s.key: s.displayName};

      _subServers = result.servers;
      // Панельные конфиги (XRAY_JSON) — на диск: список серверов хранится ссылками,
      // без этого конфиг терялся бы при перезапуске.
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
      _rebuild(); // сам переназначает выбор по ключу сервера
      _info = result.info;
      _subscriptionUrl = url;
      // Выбор и вариацию НЕ сбрасываем: при автообновлении подписки это молча
      // перекидывало пользователя на первый сервер (и теряло fragment/fingerprint).
      // Сбрасываем только если выбранный сервер из подписки пропал.
      if (_selectedIndex < 0 && _servers.isNotEmpty) _selectedIndex = 0;
      await _persist();
      // Мульти-подписки: запоминаем/обновляем профиль и делаем его активным.
      await _upsertProfile(url);
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
      _error = 'Некорректный JSON';
      notifyListeners();
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

  /// Сообщить, что изменилась настройка, требующая переподключения.
  void notePendingRestart(String reason) {
    if (!_status.isConnected) return;
    _pendingRestart = reason;
    notifyListeners();
  }

  void clearPendingRestart() {
    if (_pendingRestart == null) return;
    _pendingRestart = null;
    notifyListeners();
  }

  /// Переподключиться: выключить и снова включить с текущими настройками.
  Future<void> reconnect(AppSettings settings) async {
    _pendingRestart = null;
    notifyListeners();
    await disconnect();
    await toggleConnection(settings);
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
      await _engine.disconnect();
    } else {
      final server = selectedServer;
      if (server == null) {
        _error = 'Сначала выберите сервер';
        notifyListeners();
        return;
      }
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
        ),
      );
    }
  }

  /// Явное отключение (для трея/выхода). No-op только при полностью отключённом
  /// состоянии — connecting/disconnecting тоже гасим (иначе выход сиротит процессы).
  Future<void> disconnect() async {
    if (_status.state != VpnConnectionState.disconnected) {
      await _engine.disconnect();
    }
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
      await _engine.disconnect();
      return;
    }
    if (_servers.isEmpty) {
      _error = 'Сначала импортируйте подписку';
      notifyListeners();
      return;
    }
    // Режим «Авто (лучший сервер)»: если текущий не поднимется после всех попыток,
    // движок переключится на следующий из этого списка. Ручной выбор не подменяем.
    _engine.fallbackServers = _fallbackCandidates();
    await _engine.connectBalancer(
      _servers,
      options: ConnectionOptions(settings: settings),
    );
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _statsSub.cancel();
    _incomingSub.cancel();
    _networkSub.cancel();
    _networkWatcher.dispose();
    _updater.stop();
    _engine.dispose();
    _subscription.close();
    super.dispose();
  }
}
