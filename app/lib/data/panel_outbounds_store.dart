import 'dart:convert';
import 'dart:io';

import '../core/platform/app_paths.dart';

/// Что панель прислала для конкретного сервера (формат XRAY_JSON).
class PanelConfig {
  /// Авторитетный outbound (для обычных серверов).
  final String? outbound;

  /// Полный конфиг профиля — для «Авто …» с балансировщиком и десятками серверов.
  final String? fullConfig;

  const PanelConfig({this.outbound, this.fullConfig});

  bool get isEmpty => (outbound ?? '').isEmpty && (fullConfig ?? '').isEmpty;

  Map<String, dynamic> toJson() => {
        if (outbound != null) 'outbound': outbound,
        if (fullConfig != null) 'config': fullConfig,
      };

  factory PanelConfig.fromJson(Object? j) {
    // Старый формат — просто строка с outbound'ом.
    if (j is String) return PanelConfig(outbound: j);
    if (j is Map) {
      return PanelConfig(
        outbound: j['outbound'] as String?,
        fullConfig: j['config'] as String?,
      );
    }
    return const PanelConfig();
  }
}

/// Конфиги, присланные панелью, по ключу сервера.
///
/// Хранятся отдельно, потому что список серверов на диске — это только share-ссылки;
/// без этого стора панельный конфиг терялся при каждом перезапуске, и приложение
/// снова пересобирало outbound'ы из ссылок (ломая автовыбор и просмотр JSON).
class PanelOutboundsStore {
  static const _fileName = 'panel_outbounds.json';

  Future<File> _file() async {
    final dir = await AppPaths.supportDir();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<Map<String, PanelConfig>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final data = jsonDecode(await f.readAsString());
      if (data is! Map) return {};
      final result = <String, PanelConfig>{};
      for (final e in data.entries) {
        final cfg = PanelConfig.fromJson(e.value);
        if (!cfg.isEmpty) result['${e.key}'] = cfg;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, PanelConfig> configs) async {
    try {
      final f = await _file();
      await f.writeAsString(
          jsonEncode({for (final e in configs.entries) e.key: e.value.toJson()}));
    } catch (_) {}
  }
}
