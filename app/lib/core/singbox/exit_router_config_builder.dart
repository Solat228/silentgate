import 'dart:convert';

import '../net/api_ports.dart';
import '../settings/app_settings.dart';
import '../settings/split_tunnel.dart';
import 'api_exit_guard.dart';
import 'exit_tags.dart';

/// Маршрутизатор выходов для режимов без TUN (`systemProxy`, `proxyOnly` и
/// автономного фонового режима API при выключенном VPN).
///
/// **Почему он вообще существует.** Порты серверов из `ApiPorts` живут в
/// конфиге sing-box, а туннельный sing-box на Windows стартует ТОЛЬКО
/// при `captureMode == CaptureMode.tun`. Решение — отдельный экземпляр
/// sing-box: чистый маршрутизатор выходов БЕЗ прав администратора (туннеля
/// нет — поднимается через `SingboxProcess`).
///
/// ⚠️ Он НАМЕРЕННО не похож на TUN-конфиг (`SingboxConfigBuilder`):
///  * НЕТ `tun`-инбаунда — трафик приходит только в явно открытые порты;
///  * По умолчанию НЕТ `dns`-секции (для обратной совместимости с лёгким
///    конфигом), но при `enableDnsViaExit == true` создаются изолированные
///    DNS-резолверы на каждый выход (`detour: exit-<id>`);
///  * НЕТ обычных правил раздельного туннелирования («Прямо», «Туннель через
///    другой сервер») — у порта уже есть адресат, назначенный самим фактом
///    обращения к нему.
class ExitRouterConfigBuilder {
  /// Ключи серверов, которым нужен отдельный порт (см. `ApiPorts.forServer`).
  final List<String> serverKeys;

  /// Токен API — базовый гейт канала (и пароль по умолчанию в режиме `apiToken`).
  final String token;

  /// Готовые outbound-ы серверов — С УЖЕ ПРОСТАВЛЕННЫМИ тегами (см. `exitTagFor`).
  final List<Map<String, dynamic>> exitOutbounds;

  /// Применять ли блок-правила раздельного туннелирования к этим портам.
  final bool applyRules;

  /// Правила раздельного туннелирования — источник блок-списка при [applyRules].
  final SplitTunnelConfig split;

  /// Липкие и ручные назначения портов `serverKey -> port`.
  final Map<String, int> assignedPorts;

  /// Управляющий порт API (чтобы исключить коллизии с ручными портами).
  final int controlPort;

  /// Включён ли фиксированный порт «Умный Автовыбор» (`10818`).
  final bool autoPortEnabled;

  /// Номер порта «Умный Автовыбор».
  final int autoPort;

  /// Ключи серверов-кандидатов пула «Умный Автовыбор».
  final List<String> autoPoolKeys;

  /// URL и интервал проверки для `urltest` порта «Умный Автовыбор».
  final String urltestUrl;
  final int urltestIntervalSec;

  /// Номер порта «Прямо» (`10819`).
  final int directPort;

  /// Режим авторизации на локальных прокси-портах API.
  final ApiProxyAuthMode authMode;
  final String customUser;
  final String customPassword;

  /// Изолировать ли DNS каждого порта через его же выход.
  final bool enableDnsViaExit;
  final String dnsServer;
  final String? directDnsUpstream;

  const ExitRouterConfigBuilder({
    required this.serverKeys,
    required this.token,
    required this.exitOutbounds,
    this.applyRules = false,
    this.split = const SplitTunnelConfig(),
    this.assignedPorts = const {},
    this.controlPort = ApiPorts.control,
    this.autoPortEnabled = false,
    this.autoPort = ApiPorts.auto,
    this.autoPoolKeys = const [],
    this.urltestUrl = 'https://www.gstatic.com/generate_204',
    this.urltestIntervalSec = 180,
    this.directPort = ApiPorts.direct,
    this.authMode = ApiProxyAuthMode.apiToken,
    this.customUser = '',
    this.customPassword = '',
    this.enableDnsViaExit = false,
    this.dnsServer = '1.1.1.1',
    this.directDnsUpstream,
  });

  /// Теги, которые реально есть в [exitOutbounds].
  Set<String> get _liveExitTags => {
        for (final o in exitOutbounds)
          if (o['tag'] is String) o['tag'] as String,
      };

  List<String> get _liveAutoCandidateTags => [
        for (final k in autoPoolKeys)
          if (_liveExitTags.contains(exitTagFor(k))) exitTagFor(k),
      ];

  Map<String, dynamic>? get _autoOutbound =>
      (autoPortEnabled && token.isNotEmpty)
          ? buildApiAutoOutbound(
              candidateTags: _liveAutoCandidateTags,
              url: urltestUrl,
              intervalSec: urltestIntervalSec,
            )
          : null;

  List<Map<String, dynamic>> get _serverInbounds => buildApiExitInbounds(
        serverKeys: serverKeys,
        token: token,
        liveExitTags: _liveExitTags,
        assignedPorts: assignedPorts,
        controlPort: controlPort,
        autoPort: autoPort,
        directPort: directPort,
        authMode: authMode,
        customUser: customUser,
        customPassword: customPassword,
      );

  List<Map<String, dynamic>> _buildAutoInbound(bool hasAutoOutbound) =>
      buildApiAutoInbound(
        token: token,
        hasAutoOutbound: hasAutoOutbound,
        enabled: autoPortEnabled,
        port: autoPort,
        authMode: authMode,
        customUser: customUser,
        customPassword: customPassword,
      );

  List<Map<String, dynamic>> get _directInbound => buildApiDirectInbound(
        token: token,
        port: directPort,
        authMode: authMode,
        customUser: customUser,
        customPassword: customPassword,
      );

  Map<String, dynamic> buildMap() {
    final autoOb = _autoOutbound;
    final serverInbounds = _serverInbounds;
    final autoInbound = _buildAutoInbound(autoOb != null);
    final directInbound = _directInbound;
    final inbounds = [...serverInbounds, ...autoInbound, ...directInbound];
    final tags = [for (final i in inbounds) '${i['tag']}'];

    final rules = <Map<String, dynamic>>[
      if (enableDnsViaExit && inbounds.isNotEmpty)
        {'protocol': 'dns', 'action': 'hijack-dns'},
      if (applyRules && userRulesActive(split) && tags.isNotEmpty)
        ...apiExitBlockGuardRules(split: split, inboundTags: tags),
      ...buildApiExitRules(serverInbounds),
      ...buildApiAutoRule(autoInbound),
      ...buildApiDirectRule(directInbound),
    ];

    final routeMap = <String, dynamic>{
      'rules': rules,
      'final': 'direct',
    };

    final cfg = <String, dynamic>{
      'log': {'level': 'warn', 'timestamp': true},
      'inbounds': inbounds,
      'outbounds': [
        ...exitOutbounds,
        if (autoOb != null) autoOb,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': routeMap,
    };

    if (enableDnsViaExit && token.isNotEmpty) {
      final cleanDns =
          dnsServer.trim().isEmpty ? '1.1.1.1' : dnsServer.trim();
      final localUp = (directDnsUpstream ?? '').trim();
      final dnsServers = <Map<String, dynamic>>[
        if (localUp.isNotEmpty)
          {
            'tag': 'dns-local',
            'type': 'udp',
            'server': localUp,
          }
        else
          {
            'tag': 'dns-local',
            'type': 'local',
          },
        for (final tag in _liveExitTags.toList()..sort())
          {
            'type': 'tcp',
            'tag': 'dns-$tag',
            'server': cleanDns,
            'detour': tag,
          },
        if (autoOb != null)
          {
            'type': 'tcp',
            'tag': 'dns-api-auto',
            'server': cleanDns,
            'detour': apiAutoOutboundTag,
          },
      ];
      final dnsRules = <Map<String, dynamic>>[
        for (final i in serverInbounds)
          {
            'inbound': [i['tag']],
            'server': 'dns-${apiExitOutboundOf('${i['tag']}')}',
          },
        for (final i in autoInbound)
          {
            'inbound': [i['tag']],
            'server': 'dns-api-auto',
          },
        for (final i in directInbound)
          {
            'inbound': [i['tag']],
            'server': 'dns-local',
          },
      ];
      cfg['dns'] = {
        'servers': dnsServers,
        'rules': dnsRules,
        'final': 'dns-local',
      };
      routeMap['default_domain_resolver'] = 'dns-local';
    }

    return cfg;
  }

  String buildJson() =>
      const JsonEncoder.withIndent('  ').convert(buildMap());
}
