import 'dart:async';

import '../core/models/vpn_server.dart';
import '../core/models/vpn_status.dart';
import '../core/net/api_ports.dart';
import '../core/net/api_secrets.dart';
import '../core/net/api_server.dart';
import '../core/net/ip_info.dart';
import '../core/platform/app_log.dart';
import '../core/settings/app_settings.dart';
import '../core/singbox/exit_outbounds.dart';
import '../core/util/country_flag.dart';
import 'app_state.dart';
import 'probe_controller.dart';
import 'settings_controller.dart';

/// Обработчики API поверх состояния приложения.
///
/// ⚠️ Список запрещённых полей (`apiSecretMarkers`/`assertNoSecrets`) живёт в
/// `core/net/api_secrets.dart`, а не здесь: барьер, который реально не даёт
/// секрету уйти в сокет, стоит в `LocalApiServer._write` — на границе, откуда
/// уходит КАЖДЫЙ ответ, а не только те, что прошли через этот класс. Здесь
/// секрет всё ещё нельзя класть в поля ответа НАМЕРЕННО (это первый, а не
/// единственный барьер), но проверять это в рантайме — забота транспорта.
class AppStateApiHandlers implements ApiHandlers {
  AppStateApiHandlers(this.state, this.probe, this.settings);

  final AppState state;
  final ProbeController probe;
  final SettingsController settings;

  /// Сервер, ЧЕРЕЗ КОТОРЫЙ ИДЁТ ТРАФИК; `null` — сессии нет либо мы не знаем
  /// точно (подхват чужого живого туннеля).
  ///
  /// ⚠️ ОТЧЁТ ВЛАДЕЛЬЦА 02.09.2026: «/v1/status → connected, Германия 1.4, tun
  /// — а реальный выход Кемерово». Часть расхождения была прямо здесь: в поле
  /// `server` стоял ВЫБРАННЫЙ в списке сервер. Клик по другой строке живой
  /// туннель не трогает (появляется лишь плашка «переподключитесь»), значит
  /// после клика выбран B, а трафик по-прежнему идёт через A — и статус
  /// называл B.
  String? get _connectedServerName {
    final key = state.connectedServerKey;
    if (key == null) return null;
    for (final s in state.allSubscriptionServers()) {
      if (s.key == key) return s.displayName;
    }
    return null;
  }

  /// Чем меряется настоящий выход машины (БЕЗ прокси). Подменяется в тестах; `null` — боевой путь.
  static Future<IpInfo?> Function()? egressLookup;

  /// Чем меряется выход конкретного локального порта API. Подменяется в тестах; `null` — боевой путь.
  static Future<IpInfo?> Function({
    required int port,
    required String user,
    required String password,
  })? portLookup;

  static String _authModeLabel(ApiProxyAuthMode mode) => switch (mode) {
        // ⚠️ Нельзя отдавать строку `apiToken`: она в чёрном списке секретов
        // `apiSecretMarkers` как имя поля настроек!
        ApiProxyAuthMode.apiToken => 'token',
        ApiProxyAuthMode.none => 'none',
        ApiProxyAuthMode.custom => 'custom',
      };

  static ({String user, String password}) _proxyCredsFor(AppSettings s) =>
      switch (s.apiProxyAuthMode) {
        ApiProxyAuthMode.apiToken => (user: 'sg', password: s.apiToken),
        ApiProxyAuthMode.none => (user: '', password: ''),
        ApiProxyAuthMode.custom => (
            user: s.apiProxyCustomUser.trim(),
            password: s.apiProxyCustomPassword,
          ),
      };

  @override
  Future<Map<String, dynamic>> status({bool verify = false}) async {
    final st = settings.settings;
    return {
      'state': state.status.state.name,
      'server': _connectedServerName,
      'selectedServer': state.selectedServer?.displayName,
      'captureMode': st.captureMode.name,
      'connectedSeconds': state.connectedFor?.inSeconds,
      'pinging': probe.running,
      'standalonePortsActive': state.standaloneApiPortsRunning,
      'autoPort': st.apiAutoPortEnabled ? st.apiAutoPort : null,
      'directPort': st.apiDirectPort,
      if (verify) 'egress': await _egress(),
    };
  }

  Future<Map<String, dynamic>> _egress() async {
    try {
      final info = await (egressLookup ?? IpInfoService.lookup)();
      if (info == null) {
        return {'ok': false, 'error': 'не удалось узнать внешний адрес'};
      }
      return {'ok': true, ...info.toJson()};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> _probeLocalPort(int port, AppSettings st) async {
    final creds = _proxyCredsFor(st);
    final sw = Stopwatch()..start();
    try {
      final info = portLookup != null
          ? await portLookup!(
              port: port,
              user: creds.user,
              password: creds.password,
            )
          : await IpInfoService.lookup(
              proxyPort: port,
              proxyUser: creds.user,
              proxyPassword: creds.password,
              timeout: const Duration(seconds: 8),
            );
      sw.stop();
      if (info == null) {
        return {
          'ok': false,
          'port': port,
          'latencyMs': sw.elapsedMilliseconds,
          'error': 'порт не ответил или выход недоступен',
        };
      }
      return {
        'ok': true,
        'port': port,
        'latencyMs': sw.elapsedMilliseconds,
        ...info.toJson(),
      };
    } catch (e) {
      sw.stop();
      return {
        'ok': false,
        'port': port,
        'latencyMs': sw.elapsedMilliseconds,
        'error': '$e',
      };
    }
  }

  @override
  Future<List<Map<String, dynamic>>> servers({
    bool allSubscriptions = false,
  }) async {
    if (!allSubscriptions) {
      return [
        for (final s in state.servers)
          {
            'key': apiServerId(s.key),
            'name': s.displayName,
            'country': FlagUtil.isoFromName(s.remark),
            'protocol': s.protocol,
            'isAutoProfile': s.isPanelProfile,
            'canBeExit': canBeExitServer(s),
            'pingMs': probe.resultFor(s).latencyMs,
            'working': probe.resultFor(s).working,
          },
      ];
    }

    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final g in state.allSubscriptionsGrouped()) {
      final subId =
          g.profile != null ? apiSubscriptionId(g.profile!.url) : 'local';
      final subTitle = g.profile?.safeTitle ?? 'Локальные';
      for (final s in g.servers) {
        if (!seen.add(s.key)) continue;
        out.add({
          'key': apiServerId(s.key),
          'name': s.displayName,
          'country': FlagUtil.isoFromName(s.remark),
          'protocol': s.protocol,
          'isAutoProfile': s.isPanelProfile,
          'canBeExit': canBeExitServer(s),
          'subscriptionId': subId,
          'subscription': subTitle,
          'activeSubscription': g.active,
          'pingMs': probe.resultFor(s).latencyMs,
          'working': probe.resultFor(s).working,
        });
      }
    }
    return out;
  }

  @override
  Future<List<Map<String, dynamic>>> exits({bool verify = false}) async {
    final st = settings.settings;
    if (!ApiPorts.exitPortsActive(st)) {
      return const [];
    }

    final groups = state.allSubscriptionsGrouped();
    final subTitleByKey = <String, String>{};
    for (final g in groups) {
      final title = g.profile?.safeTitle;
      if (title == null || title.isEmpty) continue;
      for (final s in g.servers) {
        subTitleByKey.putIfAbsent(s.key, () => title);
      }
    }

    final allCatalog = state.allSubscriptionServers();
    final effectiveKeys = ApiPorts.effectiveServerKeys(st, allCatalog);
    final portMap = ApiPorts.resolvePortMap(
      effectiveKeys,
      assignedPorts: st.apiAssignedPorts,
      controlPort: st.apiControlPort,
      autoPort: st.apiAutoPort,
      directPort: st.apiDirectPort,
    );
    final autoPoolKeys = ApiPorts.autoPoolServerKeys(
      st,
      activeServers: state.servers,
      allServers: allCatalog,
    );
    final authMode = _authModeLabel(st.apiProxyAuthMode);
    final creds = _proxyCredsFor(st);
    final authRequired = creds.user.isNotEmpty;
    final listening =
        state.status.isConnected || state.standaloneApiPortsRunning;

    final out = <Map<String, dynamic>>[];

    if (st.apiAutoPortEnabled && autoPoolKeys.isNotEmpty) {
      out.add({
        'serverKey': 'auto',
        'kind': 'auto',
        'name': 'Умный Автовыбор',
        'port': st.apiAutoPort,
        'poolSize': autoPoolKeys.length,
        'authMode': authMode,
        'authRequired': authRequired,
        'listening': listening,
      });
    }

    for (final s in allCatalog) {
      if (!effectiveKeys.contains(s.key)) continue;
      if (!canBeExitServer(s)) continue;
      final port = portMap[s.key];
      if (port == null) continue;
      out.add({
        'serverKey': apiServerId(s.key),
        'kind': 'server',
        'name': s.displayName,
        'country': FlagUtil.isoFromName(s.remark),
        if (subTitleByKey.containsKey(s.key))
          'subscription': subTitleByKey[s.key],
        'isAutoProfile': s.isPanelProfile,
        'pingMs': probe.resultFor(s).latencyMs,
        'working': probe.resultFor(s).working,
        'port': port,
        'authMode': authMode,
        'authRequired': authRequired,
        'listening': listening,
      });
    }

    out.add({
      'serverKey': null,
      'kind': 'direct',
      'name': 'Прямо',
      'port': st.apiDirectPort,
      'authMode': authMode,
      'authRequired': authRequired,
      'listening': listening,
    });

    if (verify) {
      const batchSize = 6;
      for (var i = 0; i < out.length; i += batchSize) {
        final end = (i + batchSize < out.length) ? i + batchSize : out.length;
        final slice = out.sublist(i, end);
        final results = await Future.wait(
          slice.map((entry) => _probeLocalPort(entry['port'] as int, st)),
        );
        for (var j = 0; j < slice.length; j++) {
          slice[j]['egress'] = results[j];
        }
      }
    }

    return out;
  }

  @override
  Future<Map<String, dynamic>> traffic() async => {
        'uplinkBytes': state.sessionUplinkBytes,
        'downlinkBytes': state.sessionDownlinkBytes,
      };

  @override
  Future<Map<String, dynamic>> subscription() async {
    final activeProf = state.activeSubscription;
    final safeTitle = activeProf != null
        ? activeProf.safeTitle
        : (state.info.title ?? '');
    return {
      'title': safeTitle,
      'usedBytes': state.info.usedBytes,
      'totalBytes': state.info.totalBytes,
      'unlimited': state.info.unlimitedTraffic,
      'expiresAt': state.info.expiresAt?.toIso8601String(),
    };
  }

  @override
  Future<List<Map<String, dynamic>>> subscriptions() async {
    final activeId = state.activeSubscription?.id;
    return [
      for (final p in state.subscriptions)
        {
          'id': apiSubscriptionId(p.url),
          'title': p.safeTitle,
          'active': p.id == activeId,
          'isLocal': p.isLocal,
          'serverCount': p.serverLinks.length,
          'usedBytes': p.info.usedBytes,
          'totalBytes': p.info.totalBytes,
          'unlimited': p.info.unlimitedTraffic,
          'expiresAt': p.info.expiresAt?.toIso8601String(),
        },
    ];
  }

  @override
  Future<ApiResult> selectSubscription({String? id, String? title}) async {
    final subs = state.subscriptions;
    if (subs.isEmpty) {
      return const ApiResult.fail(
        'subscription_not_found',
        'Нет добавленных подписок',
      );
    }
    if ((id ?? '').trim().isNotEmpty) {
      final wantId = id!.trim();
      final match = subs
          .where((p) => apiSubscriptionId(p.url) == wantId)
          .firstOrNull;
      if (match == null) {
        return const ApiResult.fail(
          'subscription_not_found',
          'Подписка не найдена',
        );
      }
      await state.switchSubscription(match.id);
      return const ApiResult.ok();
    }
    if ((title ?? '').trim().isNotEmpty) {
      final wantTitle = title!.trim().toLowerCase();
      final matches = subs
          .where((p) => p.safeTitle.trim().toLowerCase() == wantTitle)
          .toList();
      if (matches.isEmpty) {
        return const ApiResult.fail(
          'subscription_not_found',
          'Подписка с таким названием не найдена',
        );
      }
      if (matches.length > 1) {
        return const ApiResult.fail(
          'ambiguous_title',
          'Под это название подходит несколько подписок — используйте id',
        );
      }
      await state.switchSubscription(matches.single.id);
      return const ApiResult.ok();
    }
    return const ApiResult.fail(
      'subscription_required',
      'Укажите id или title подписки',
    );
  }

  @override
  Future<ApiResult> refreshSubscription({String? id, bool all = false}) async {
    if (all) {
      for (final p in state.subscriptions) {
        if (!p.isHttpUrl) continue;
        unawaited(state.refreshSubscription(id: p.id).catchError((e) {
          AppLog.w('Обновление подписки по API не завершилось: $e');
          return false;
        }));
      }
      return const ApiResult.ok();
    }
    if ((id ?? '').trim().isNotEmpty) {
      final wantId = id!.trim();
      final match = state.subscriptions
          .where((p) => apiSubscriptionId(p.url) == wantId)
          .firstOrNull;
      if (match == null) {
        return const ApiResult.fail(
          'subscription_not_found',
          'Подписка не найдена',
        );
      }
      if (!match.isHttpUrl) {
        return const ApiResult.fail(
          'local_subscription',
          'Локальная подписка не обновляется по сети',
        );
      }
      unawaited(state.refreshSubscription(id: match.id).catchError((e) {
        AppLog.w('Обновление подписки по API не завершилось: $e');
        return false;
      }));
      return const ApiResult.ok();
    }
    unawaited(state.refreshSubscription().catchError((e) {
      AppLog.w('Обновление активной подписки по API не завершилось: $e');
      return false;
    }));
    return const ApiResult.ok();
  }

  @override
  Future<ApiResult> configureExits(Map<String, dynamic> body) async {
    final allCatalog = state.allSubscriptionServers();
    VpnServer? findByApiId(String target) {
      for (final s in allCatalog) {
        if (apiServerId(s.key) == target || s.key == target) return s;
      }
      return null;
    }

    final customPorts = <String, int?>{};
    final assignObj = body['assignPort'];
    if (assignObj != null) {
      if (assignObj is! Map) {
        return const ApiResult.fail(
          'invalid_assign_port',
          'assignPort должен быть объектом {"server": "...", "port": 10825}',
        );
      }
      final srvId = '${assignObj['server'] ?? assignObj['id'] ?? ''}'.trim();
      final srv = findByApiId(srvId);
      if (srv == null) {
        return const ApiResult.fail('server_not_found', 'Сервер не найден');
      }
      final rawP = assignObj['port'];
      if (rawP == null) {
        customPorts[srv.key] = null;
      } else {
        final pNum = rawP is int ? rawP : int.tryParse('$rawP');
        final cur = settings.settings;
        if (pNum == null ||
            ApiPorts.isReservedSystemPort(
              pNum,
              controlPort: cur.apiControlPort,
              autoPort: cur.apiAutoPort,
              directPort: cur.apiDirectPort,
            )) {
          return const ApiResult.fail(
            'invalid_port',
            'Порт недопустим или зарезервирован под внутренние нужды SilentGate',
          );
        }
        customPorts[srv.key] = pNum;
      }
    }
    final assignMapObj = body['assignPorts'];
    if (assignMapObj != null) {
      if (assignMapObj is! Map) {
        return const ApiResult.fail(
          'invalid_assign_port',
          'assignPorts должен быть объектом {"srv-...": 10825}',
        );
      }
      final cur = settings.settings;
      for (final entry in assignMapObj.entries) {
        final srv = findByApiId('${entry.key}'.trim());
        if (srv == null) {
          return const ApiResult.fail('server_not_found', 'Сервер не найден');
        }
        if (entry.value == null) {
          customPorts[srv.key] = null;
        } else {
          final pNum =
              entry.value is int ? entry.value as int : int.tryParse('${entry.value}');
          if (pNum == null ||
              ApiPorts.isReservedSystemPort(
                pNum,
                controlPort: cur.apiControlPort,
                autoPort: cur.apiAutoPort,
                directPort: cur.apiDirectPort,
              )) {
            return const ApiResult.fail(
              'invalid_port',
              'Порт недопустим или зарезервирован под внутренние нужды SilentGate',
            );
          }
          customPorts[srv.key] = pNum;
        }
      }
    }

    ApiProxyAuthMode? nextAuthMode;
    if (body['authMode'] is String) {
      nextAuthMode = switch ((body['authMode'] as String).trim()) {
        'token' || 'default' || 'bearer' => ApiProxyAuthMode.apiToken,
        'none' => ApiProxyAuthMode.none,
        'custom' => ApiProxyAuthMode.custom,
        _ => null,
      };
      if (nextAuthMode == null) {
        return const ApiResult.fail(
          'invalid_auth_mode',
          'authMode должен быть token, none или custom',
        );
      }
    }

    ApiAutoPoolScope? nextScope;
    final rawScope = body['autoPoolScope'] ?? body['autoPool'];
    if (rawScope is String) {
      nextScope = switch (rawScope.trim()) {
        'allSubscriptions' || 'all' => ApiAutoPoolScope.allSubscriptions,
        'activeSubscription' || 'active' => ApiAutoPoolScope.activeSubscription,
        'checkedOnly' || 'checked' || 'selectedExits' => ApiAutoPoolScope.checkedOnly,
        _ => null,
      };
      if (nextScope == null) {
        return const ApiResult.fail(
          'invalid_scope',
          'autoPoolScope должен быть allSubscriptions, activeSubscription или checkedOnly',
        );
      }
    }

    final modeStr = body['mode'] is String ? (body['mode'] as String).trim() : null;

    await settings.update((s) {
      var keys = List<String>.from(s.apiExitServerKeys);
      var assigned = Map<String, int>.from(s.apiAssignedPorts);

      if (body['clear'] == true || modeStr == 'clear') {
        keys = <String>[];
        if (body['resetSticky'] == true) {
          assigned = <String, int>{};
        }
      }
      if (body['enableAllAuto'] == true || modeStr == 'all_auto') {
        final set = keys.toSet();
        for (final srv in allCatalog) {
          if (srv.isPanelProfile && canBeExitServer(srv)) {
            set.add(srv.key);
          }
        }
        keys = set.toList();
      }
      if (body['enableAll'] == true || modeStr == 'all_servers') {
        final set = keys.toSet();
        for (final srv in allCatalog) {
          if (set.length >= ApiPorts.maxServers) break;
          if (canBeExitServer(srv)) {
            set.add(srv.key);
          }
        }
        keys = set.toList();
      }
      if (body['servers'] is List) {
        final nextKeys = <String>[];
        for (final item in body['servers'] as List) {
          final srv = findByApiId('$item'.trim());
          if (srv != null && !nextKeys.contains(srv.key)) {
            nextKeys.add(srv.key);
          }
        }
        keys = nextKeys;
      }
      if (body['addServers'] is List) {
        for (final item in body['addServers'] as List) {
          final srv = findByApiId('$item'.trim());
          if (srv != null && !keys.contains(srv.key)) {
            keys.add(srv.key);
          }
        }
      }
      if (body['removeServers'] is List) {
        for (final item in body['removeServers'] as List) {
          final srv = findByApiId('$item'.trim());
          if (srv != null) {
            keys.remove(srv.key);
          }
        }
      }
      for (final entry in customPorts.entries) {
        if (entry.value == null) {
          assigned.remove(entry.key);
        } else {
          if (!keys.contains(entry.key)) {
            keys.add(entry.key);
          }
          assigned.removeWhere((_, v) => v == entry.value);
          assigned[entry.key] = entry.value!;
        }
      }

      assigned = ApiPorts.assignStickyPorts(
        keys,
        assigned,
        controlPort: s.apiControlPort,
        autoPort: s.apiAutoPort,
        directPort: s.apiDirectPort,
      );

      return s.copyWith(
        apiExitServerKeys: keys,
        apiAssignedPorts: assigned,
        apiAutoPortEnabled: body['autoPortEnabled'] is bool
            ? body['autoPortEnabled'] as bool
            : s.apiAutoPortEnabled,
        apiAutoIncludeAutoProfiles: body['autoIncludeAutoProfiles'] is bool
            ? body['autoIncludeAutoProfiles'] as bool
            : s.apiAutoIncludeAutoProfiles,
        apiKeepAliveWhenDisconnected: body['keepAliveWhenDisconnected'] is bool
            ? body['keepAliveWhenDisconnected'] as bool
            : s.apiKeepAliveWhenDisconnected,
        apiDnsViaExit: body['dnsViaExit'] is bool
            ? body['dnsViaExit'] as bool
            : s.apiDnsViaExit,
        apiAutoPoolScope: nextScope ?? s.apiAutoPoolScope,
        apiProxyAuthMode: nextAuthMode ?? s.apiProxyAuthMode,
      );
    });
    return const ApiResult.ok();
  }

  @override
  Future<Map<String, dynamic>> testExit({int? port, String? serverKey}) async {
    final st = settings.settings;
    if (!ApiPorts.exitPortsActive(st)) {
      return {
        'ok': false,
        'error': 'API выключен или не задан токен',
      };
    }
    var targetPort = port;
    if (targetPort == null && (serverKey ?? '').trim().isNotEmpty) {
      final want = serverKey!.trim();
      if (want == 'auto') {
        targetPort = st.apiAutoPort;
      } else if (want == 'direct') {
        targetPort = st.apiDirectPort;
      } else {
        final allCatalog = state.allSubscriptionServers();
        final effectiveKeys = ApiPorts.effectiveServerKeys(st, allCatalog);
        final portMap = ApiPorts.resolvePortMap(
          effectiveKeys,
          assignedPorts: st.apiAssignedPorts,
          controlPort: st.apiControlPort,
          autoPort: st.apiAutoPort,
          directPort: st.apiDirectPort,
        );
        for (final srv in allCatalog) {
          if (apiServerId(srv.key) == want || srv.key == want) {
            targetPort = portMap[srv.key];
            break;
          }
        }
      }
    }
    if (targetPort == null || targetPort <= 0) {
      return {
        'ok': false,
        'error': 'порт не найден — укажите port или server с активным портом',
      };
    }
    return _probeLocalPort(targetPort, st);
  }

  bool get _live =>
      state.status.isConnected ||
      state.status.state == VpnConnectionState.connecting;

  Future<void> _connectTo(int index) async {
    state.selectServer(index);
    if (_live) {
      await state.reconnect(settings.settings);
    } else {
      await state.toggleConnection(settings.settings);
    }
  }

  @override
  Future<ApiResult> connect({
    String? serverKey,
    String? name,
    bool auto = false,
  }) async {
    if (auto) {
      if (_live) {
        await state.reconnectAuto(settings.settings);
      } else {
        await state.connectAuto(settings.settings);
      }
      return const ApiResult.ok();
    }
    if ((serverKey ?? '').isNotEmpty) {
      var i = state.servers.indexWhere(
        (s) => apiServerId(s.key) == serverKey || s.key == serverKey,
      );
      if (i < 0) {
        // Поиск в других подписках: если нашли — переключаемся на эту подписку!
        for (final p in state.subscriptions) {
          final subServers = state.serversOfSubscription(p.id);
          final hit = subServers.any(
            (s) => apiServerId(s.key) == serverKey || s.key == serverKey,
          );
          if (hit) {
            await state.switchSubscription(p.id);
            i = state.servers.indexWhere(
              (s) => apiServerId(s.key) == serverKey || s.key == serverKey,
            );
            break;
          }
        }
      }
      if (i < 0) {
        return const ApiResult.fail('server_not_found', 'Сервер не найден');
      }
      await _connectTo(i);
      return const ApiResult.ok();
    }
    if ((name ?? '').isNotEmpty) {
      final matches = [
        for (var i = 0; i < state.servers.length; i++)
          if (state.servers[i].displayName == name) i,
      ];
      if (matches.isEmpty) {
        return const ApiResult.fail('server_not_found', 'Сервер не найден');
      }
      if (matches.length > 1) {
        return const ApiResult.fail(
          'ambiguous_name',
          'Под это имя подходит несколько серверов',
        );
      }
      await _connectTo(matches.first);
      return const ApiResult.ok();
    }
    return const ApiResult.fail(
      'server_required',
      'Укажите server, name или auto',
    );
  }

  @override
  Future<ApiResult> disconnect() async {
    await state.disconnect();
    return const ApiResult.ok();
  }

  @override
  Future<ApiResult> ping({bool allSubscriptions = false}) async {
    final targets =
        allSubscriptions ? state.allSubscriptionServers() : state.servers;
    unawaited(probe.pingAll(targets, settings.settings).catchError((e) {
      AppLog.w('Пинг по команде API не завершился: $e');
    }));
    return const ApiResult.ok();
  }
}
