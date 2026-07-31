import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

void main() {
  test('БЛОК + overrideSites: есть ли reject-правило', () {
    final split = SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      apps: const [
        AppRule('C:\\P\\evil.exe',
            byName: true, action: AppAction.block, overrideSites: true),
        AppRule('C:\\P\\plain.exe', byName: true, action: AppAction.block),
      ],
      sites: const [SiteRule('badsite.com', action: AppAction.block)],
    );
    const b = SingboxConfigBuilder(options: TunOptions());
    final cfg = b.buildMap(split);
    final json = const JsonEncoder.withIndent('  ').convert(cfg);
    File('build/tmp_block_override.json').createSync(recursive: true);
    File('build/tmp_block_override.json').writeAsStringSync(json);
    // ignore: avoid_print
    print(json);
  });

  test('Android: БЛОК + overrideSites в package_name', () {
    final split = SplitTunnelConfig(
      mode: SplitMode.onlySelected,
      apps: const [
        AppRule('com.evil.app', action: AppAction.block, overrideSites: true),
        AppRule('com.plain.app', action: AppAction.block),
      ],
    );
    const b = SingboxConfigBuilder(
        options: TunOptions(platformTun: true), probePort: 10809);
    final json =
        const JsonEncoder.withIndent('  ').convert(b.buildMap(split));
    File('build/tmp_block_android.json').createSync(recursive: true);
    File('build/tmp_block_android.json').writeAsStringSync(json);
    // ignore: avoid_print
    print(json);
  });
}
