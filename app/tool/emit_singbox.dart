// Печатает sing-box TUN-конфиг для валидации ядром:
//   dart run tool/emit_singbox.dart [all|only] [system|gvisor|mixed]
//                                   [dns-system|dns-vpn|dns-custom] [no-ipv6] [no-strict]
//   sing-box check -c sb.json
// В набор приложений включены все три действия (Прямо/Туннель/Блок) для проверки.
import 'dart:io';

import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

void main(List<String> args) {
  final mode =
      args.contains('only') ? SplitMode.onlySelected : SplitMode.all;
  final stack = ['system', 'gvisor', 'mixed']
      .where(args.contains)
      .cast<String?>()
      .firstOrNull;
  final dnsMode = args.contains('dns-system')
      ? DnsMode.system
      : args.contains('dns-custom')
          ? DnsMode.custom
          : DnsMode.vpn;

  final split = SplitTunnelConfig(
    mode: mode,
    apps: const [
      AppRule(r'C:\Windows\System32\notepad.exe', action: AppAction.direct),
      AppRule(r'C:\Program Files\Discord\Discord.exe',
          byName: true, action: AppAction.tunnel),
      AppRule(r'C:\Program Files\Ads\ads.exe',
          byName: true, action: AppAction.block),
    ],
    sites: const [
      SiteRule('youtube.com', action: AppAction.direct),
      SiteRule('ads.example', action: AppAction.block),
    ],
  );

  final options = TunOptions(
    stack: stack,
    strictRoute: !args.contains('no-strict'),
    ipv6: !args.contains('no-ipv6'),
    dnsMode: dnsMode,
    dnsServer: dnsMode == DnsMode.custom ? '9.9.9.9' : '1.1.1.1',
    excludeCidrs: const ['10.8.0.0/24'],
    serverIps: const ['203.0.113.7', '2001:db8::1'],
  );
  stdout.write(SingboxConfigBuilder(options: options).buildJson(split));
}
