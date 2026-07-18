// Полная диагностика подписки: что приложение реально получает от панели и во что
// это превращается. VPN не поднимается.
//
//   dart run tool/diag_subscription.dart "<sub-url>" [--emit <индекс профиля>]
//
// С `--emit N` печатает в stdout готовый конфиг N-го профиля (для `xray run -test`).
import 'dart:convert';
import 'dart:io';

import 'package:silentgate/core/subscription/subscription_service.dart';
import 'package:silentgate/core/xray/override_normalizer.dart';
import 'package:silentgate/core/xray/xray_config_builder.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Укажите URL подписки');
    exit(1);
  }
  final emitIdx =
      args.contains('--emit') ? int.tryParse(args[args.indexOf('--emit') + 1]) : null;

  final res = await SubscriptionService().fetch(args[0]);
  final servers = res.servers;
  final profiles = servers.where((s) => s.isPanelProfile).toList();
  final plain = servers.where((s) => !s.isPanelProfile).toList();

  stderr.writeln('Подписка: ${res.info.title ?? "—"}');
  stderr.writeln('Серверов всего: ${servers.length}  '
      '(профилей «Авто»: ${profiles.length}, обычных: ${plain.length})');
  stderr.writeln('С конфигом панели: '
      '${servers.where((s) => (s.rawOutboundJson ?? "").isNotEmpty).length}');
  stderr.writeln('');

  stderr.writeln('--- Профили «Авто» (применяются целиком) ---');
  for (var i = 0; i < profiles.length; i++) {
    final s = profiles[i];
    final cfg = jsonDecode(s.rawPanelConfig!) as Map;
    final outs = (cfg['outbounds'] as List).length;
    final bal = ((cfg['routing'] as Map?)?['balancers'] as List?)?.length ?? 0;
    final burst = cfg.containsKey('burstObservatory') ? 'burst' : '—';
    stderr.writeln('[$i] ${s.displayName}: '
        'outbound=$outs, balancer=$bal, $burst, '
        '${s.rawPanelConfig!.length} Б');
  }

  // --emit-all <dir>: выгрузить конфиги ВСЕХ профилей для проверки ядром.
  if (args.contains('--emit-all')) {
    final dir = Directory(args[args.indexOf('--emit-all') + 1])
      ..createSync(recursive: true);
    for (var i = 0; i < profiles.length; i++) {
      final norm = normalizeOverridePorts(profiles[i].rawPanelConfig!,
          socksPort: 10808, httpPort: 10809);
      File('${dir.path}${Platform.pathSeparator}profile_$i.json')
          .writeAsStringSync(norm.json);
    }
    stderr.writeln('Выгружено профилей: ${profiles.length} → ${dir.path}');
    exit(0);
  }

  if (emitIdx != null && emitIdx >= 0 && emitIdx < profiles.length) {
    // Ровно то, что уйдёт в ядро при подключении к этому профилю.
    final norm = normalizeOverridePorts(profiles[emitIdx].rawPanelConfig!,
        socksPort: 10808, httpPort: 10809);
    stderr.writeln('\nДописаны inbound: ${norm.addedInbounds}');
    stdout.write(const JsonEncoder.withIndent('  ')
        .convert(jsonDecode(norm.json)));
  } else {
    // Конфиг автовыбора приложения по обычным серверам.
    stdout.write(const XrayConfigBuilder().buildBalancerJson(plain));
  }
  exit(0);
}
