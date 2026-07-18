import 'dart:convert';

// HarnessEntry/HarnessPorts описывают кандидата на пробу и не зависят от ядра,
// поэтому переиспользуются как есть (лежат рядом с Xray-харнессом исторически).
import '../xray/harness_config_builder.dart';
import 'singbox_outbound_factory.dart';

/// Проброс-харнесс на sing-box: по одному локальному `mixed`-inbound'у на
/// кандидата, каждый жёстко смаршрутизирован на свой outbound.
///
/// Зачем отдельно от [HarnessConfigBuilder]: hysteria2 умеет только sing-box,
/// а пинг «через прокси» для таких серверов — единственный работающий (прямая
/// TCP-проба до QUIC-порта молчит всегда).
///
/// Как и Xray-харнесс, НИКОГДА не трогает системный прокси: слушает только
/// 127.0.0.1 и не содержит ни TUN, ни Clash API.
class SingboxHarnessConfigBuilder {
  final HarnessPorts ports;
  const SingboxHarnessConfigBuilder({this.ports = const HarnessPorts(base: 21500)});

  int portFor(int index) => ports.base + index;

  String buildJson(List<HarnessEntry> entries) =>
      const JsonEncoder.withIndent('  ').convert(buildMap(entries));

  Map<String, dynamic> buildMap(List<HarnessEntry> entries) {
    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];

    for (var i = 0; i < entries.length; i++) {
      final inTag = 'in-$i';
      final outTag = 'out-$i';
      inbounds.add({
        'type': 'mixed',
        'tag': inTag,
        'listen': '127.0.0.1',
        'listen_port': portFor(i),
      });
      outbounds.add(SingboxOutboundFactory.build(entries[i].server, tag: outTag));
      rules.add({
        'inbound': [inTag],
        'action': 'route',
        'outbound': outTag,
      });
    }
    outbounds.add({'type': 'direct', 'tag': 'direct'});

    return {
      'log': {'level': 'warn'},
      'inbounds': inbounds,
      'outbounds': outbounds,
      // final нужен ядру как запасной маршрут; сюда трафик проб не попадает.
      'route': {'rules': rules, 'final': 'direct'},
    };
  }
}
