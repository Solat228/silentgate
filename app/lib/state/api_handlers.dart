import '../core/net/api_ports.dart';
import '../core/net/api_server.dart';
import '../core/util/country_flag.dart';
import 'app_state.dart';
import 'probe_controller.dart';
import 'settings_controller.dart';

/// Поля, которых в ответах API быть НЕ ДОЛЖНО.
///
/// ⚠️ Явный список, а не «по умолчанию не отдаём». Креды локального прокси
/// лежат в глобальных статиках процесса, а последний сегмент URL подписки у
/// Remnawave — это секрет: «отдать состояние» без списка означало бы отдать
/// ключ от туннеля и от подписки одним GET-запросом.
const apiSecretMarkers = <String>[
  'apiToken',
  'localProxyPassword',
  'localProxyUser',
  'subscriptionUrl',
  'rawJsonOverride',
  'rawPanelConfig',
];

/// Бросает [StateError], если в сериализованном ответе встретилось запрещённое.
void assertNoSecrets(String json) {
  for (final m in apiSecretMarkers) {
    if (json.contains(m)) {
      throw StateError('В ответе API запрещённое поле: $m');
    }
  }
}

/// Обработчики API поверх состояния приложения.
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
    final keys = settings.settings.apiExitServerKeys;
    return [
      for (final s in state.servers)
        if (keys.contains(s.key))
          {
            'serverKey': s.key,
            'name': s.displayName,
            'country': FlagUtil.isoFromName(s.remark),
            'port': ApiPorts.forServer(keys, s.key),
          },
      {'serverKey': null, 'name': 'Прямо', 'port': ApiPorts.direct},
    ];
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

  @override
  Future<ApiResult> connect(
      {String? serverKey, String? name, bool auto = false}) async {
    if (auto) {
      await state.connectAuto(settings.settings);
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
      state.selectServer(i);
      await state.toggleConnection(settings.settings);
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
      state.selectServer(matches.first);
      await state.toggleConnection(settings.settings);
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
