import '../core/models/vpn_status.dart';
import '../core/net/api_ports.dart';
import '../core/net/api_server.dart';
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

  @override
  Future<Map<String, dynamic>> status() async => {
        'state': state.status.state.name,
        'server': state.selectedServer?.displayName,
        'captureMode': settings.settings.captureMode.name,
        'connectedSeconds': state.connectedFor?.inSeconds,
      };

  @override
  Future<List<Map<String, dynamic>>> servers() async => [
        for (final s in state.servers)
          {
            'key': s.key,
            'name': s.displayName,
            'country': FlagUtil.isoFromName(s.remark),
            'protocol': s.protocol,
            'pingMs': probe.resultFor(s).latencyMs,
            'working': probe.resultFor(s).working,
          },
      ];

  @override
  Future<List<Map<String, dynamic>>> exits() async {
    final st = settings.settings;
    // ⚠️ ТОТ ЖЕ ГЕЙТ, ЧТО РЕШАЕТ, СОЗДАВАТЬ ЛИ ИНБАУНДЫ (`ApiPorts.exitsActive`,
    // её же читают `buildApiExitInbounds`/`buildApiDirectInbound`). Список не
    // рекламирует порт, которого нет физически: при выключенном API или
    // пустом токене ни один из этих mixed-инбаундов не поднимется — ни
    // серверный, ни «Прямо». В штатной работе сюда и не дойти (управляющий
    // сервер сам не стартует без токена — см. `AppState.applyApiSettings`),
    // но обработчик обязан быть верным сам по себе, а не полагаться на это.
    if (!ApiPorts.exitsActive(enabled: st.apiEnabled, token: st.apiToken)) {
      return const [];
    }
    final keys = st.apiExitServerKeys;
    final out = <Map<String, dynamic>>[];
    for (final s in state.servers) {
      if (!keys.contains(s.key)) continue;
      // Ключ мог оказаться за пределами топ-40 (`ApiPorts.maxServers`) —
      // тогда порта физически нет, и `port: null` дал бы вызывающему битый
      // адрес `http://sg:токен@127.0.0.1:None` (см. `tools/silentgate.py`,
      // `proxies_for`). Запись без порта не отдаём вовсе: молчаливое
      // исключение честнее заведомо нерабочего адреса.
      final port = ApiPorts.forServer(keys, s.key);
      if (port == null) continue;
      out.add({
        'serverKey': s.key,
        'name': s.displayName,
        'country': FlagUtil.isoFromName(s.remark),
        'port': port,
      });
    }
    out.add({'serverKey': null, 'name': 'Прямо', 'port': ApiPorts.direct});
    return out;
  }

  @override
  Future<Map<String, dynamic>> traffic() async => {
        'uplinkBytes': state.sessionUplinkBytes,
        'downlinkBytes': state.sessionDownlinkBytes,
      };

  @override
  Future<Map<String, dynamic>> subscription() async => {
        'title': state.info.title,
        'usedBytes': state.info.usedBytes,
        'totalBytes': state.info.totalBytes,
        'unlimited': state.info.unlimitedTraffic,
        'expiresAt': state.info.expiresAt?.toIso8601String(),
      };

  /// Канал живой (поднят или в процессе подъёма) — то состояние, в котором
  /// `toggleConnection`/`connectAuto` вместо «подключить» ОТКЛЮЧАЮТ (это
  /// переключатели одной кнопки на главном экране, которая нажимается только
  /// при «не подключено»).
  bool get _live =>
      state.status.isConnected ||
      state.status.state == VpnConnectionState.connecting;

  /// Выбрать сервер и подключиться — СМЕНОЙ сервера, если канал уже живой, а
  /// не отключением.
  ///
  /// ⚠️ РАУНД РЕВЬЮ 1, НАХОДКА 3. Раньше здесь стоял голый
  /// `state.toggleConnection(...)`: на живом соединении он уходил в ветку
  /// ОТКЛЮЧЕНИЯ (это переключатель), и команда API «подключись к серверу X»
  /// молча выключала VPN и отвечала `{"ok": true}`. `state.reconnect(...)` —
  /// тот же путь, что использует подсказка «переподключитесь» в
  /// `home_screen.dart` (#13): disconnect + connect с сохранением отсчёта
  /// таймера сессии, а не голое выключение.
  Future<void> _connectTo(int index) async {
    state.selectServer(index);
    if (_live) {
      await state.reconnect(settings.settings);
    } else {
      await state.toggleConnection(settings.settings);
    }
  }

  @override
  Future<ApiResult> connect(
      {String? serverKey, String? name, bool auto = false}) async {
    if (auto) {
      // Тот же класс бага, что и у `_connectTo`: `connectAuto` — тоже
      // переключатель, и на живом канале сам отключает VPN вместо смены
      // режима на «Авто».
      if (_live) {
        await state.reconnectAuto(settings.settings);
      } else {
        await state.connectAuto(settings.settings);
      }
      return const ApiResult.ok();
    }
    // ⚠️ КЛЮЧ, А НЕ ИМЯ. Ключ (share-ссылка) стабилен и переживает
    // переименование на панели; имя панель меняет когда угодно, и скрипт,
    // написанный по имени, тихо сломался бы.
    if ((serverKey ?? '').isNotEmpty) {
      final i = state.servers.indexWhere((s) => s.key == serverKey);
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
      // ⚠️ Молча выбрать первый значило бы подключить не туда.
      if (matches.length > 1) {
        return const ApiResult.fail(
            'ambiguous_name', 'Под это имя подходит несколько серверов');
      }
      await _connectTo(matches.first);
      return const ApiResult.ok();
    }
    return const ApiResult.fail(
        'server_required', 'Укажите server, name или auto');
  }

  @override
  Future<ApiResult> disconnect() async {
    await state.disconnect();
    return const ApiResult.ok();
  }

  @override
  Future<ApiResult> ping() async {
    await probe.pingAll(state.servers, settings.settings);
    return const ApiResult.ok();
  }
}
