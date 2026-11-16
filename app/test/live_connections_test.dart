import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/live_connections.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';

void main() {
  group('LiveConnectionsSnapshot.fromClashJson & section ordering', () {
    test('classifies VPN, blocked and direct, filters loopback, omits empty blocked section', () {
      final raw = {
        'connections': [
          {
            'id': 'c-vpn',
            'upload': 1200,
            'download': 48000,
            'start': '2026-11-02T12:00:02Z',
            'chains': ['proxy'],
            'rule': 'domain_suffix=anthropic.com',
            'metadata': {
              'network': 'tcp',
              'host': 'claude.ai',
              'destinationIP': '160.79.104.10',
              'destinationPort': '443',
              'processPath': r'C:\Program Files\Google\Chrome\Application\chrome.exe',
            },
          },
          {
            'id': 'c-direct',
            'upload': 500,
            'download': 3000,
            'start': '2026-11-02T12:00:01Z',
            'chains': ['direct'],
            'rule': 'final',
            'metadata': {
              'network': 'tcp',
              'host': 'ya.ru',
              'destinationIP': '77.88.55.242',
              'destinationPort': 443,
              'process': 'chrome.exe',
            },
          },
          {
            'id': 'c-loopback',
            'upload': 10,
            'download': 10,
            'chains': ['direct'],
            'rule': 'loop',
            'metadata': {
              'network': 'tcp',
              'host': '127.0.0.1',
              'destinationIP': '127.0.0.1',
              'destinationPort': 10808,
              'process': 'xray.exe',
            },
          },
        ],
      };

      final snap = LiveConnectionsSnapshot.fromClashJson(raw);
      expect(snap.totalCount, 2, reason: 'internal loopback/core connection must be ignored');
      expect(snap.vpn.single.host, 'claude.ai');
      expect(snap.vpn.single.process, 'chrome.exe');
      expect(snap.direct.single.host, 'ya.ru');
      expect(snap.blocked, isEmpty);

      // Section order when blocked is empty: ONLY [vpn, direct] (no blocked section!)
      expect(
        [for (final s in snap.sections) s.kind],
        [LiveRouteKind.vpn, LiveRouteKind.direct],
      );
    });

    test('includes blocked section in strict order [vpn, blocked, direct] when blocked > 0', () {
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [
          SiteRule('ads.example.com', action: AppAction.block),
        ],
      );
      final raw = {
        'connections': [
          {
            'id': '1',
            'chains': ['proxy-out'],
            'metadata': {'host': 'github.com', 'destinationPort': 443},
          },
          {
            'id': '2',
            'chains': <String>[], // sing-box action:reject leaves chains empty
            'rule': 'domain_suffix',
            'metadata': {'host': 'sub.ads.example.com', 'destinationPort': 443},
          },
          {
            'id': '3',
            'chains': ['direct'],
            'metadata': {'host': 'gosuslugi.ru', 'destinationPort': 443},
          },
        ],
      };

      final snap = LiveConnectionsSnapshot.fromClashJson(raw, split: split);
      expect(snap.vpn, hasLength(1));
      expect(snap.blocked, hasLength(1));
      expect(snap.direct, hasLength(1));
      expect(
        [for (final s in snap.sections) s.kind],
        [LiveRouteKind.vpn, LiveRouteKind.blocked, LiveRouteKind.direct],
      );
    });
  });

  group('detectRoutingMismatch & mostSpecificSiteRule', () {
    test('detects newly added tunnel site still flowing direct', () {
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [
          SiteRule('anthropic.com', action: AppAction.tunnel),
        ],
      );
      final snap = LiveConnectionsSnapshot(
        direct: [
          const LiveConnectionEntry(
            id: 'd1',
            host: 'api.anthropic.com',
            destinationIp: '160.79.104.10',
            destinationPort: 443,
            network: 'tcp',
            process: 'chrome.exe',
            chains: ['direct'],
            rule: 'final',
            uploadBytes: 100,
            downloadBytes: 200,
            start: null,
            route: LiveRouteKind.direct,
          ),
        ],
      );

      expect(
        detectRoutingMismatch(snap, split, noRealIp: false),
        'anthropic.com',
      );
    });

    test('more specific subdomain direct rule overrides parent tunnel rule without false alarm', () {
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [
          SiteRule('example.com', action: AppAction.tunnel),
          SiteRule('cdn.example.com', action: AppAction.direct),
        ],
      );
      expect(
        mostSpecificSiteRule(split.sites, 'img.cdn.example.com', port: 443)?.domain,
        'cdn.example.com',
      );

      final snap = LiveConnectionsSnapshot(
        direct: [
          const LiveConnectionEntry(
            id: 'd2',
            host: 'img.cdn.example.com',
            destinationIp: '93.184.216.34',
            destinationPort: 443,
            network: 'tcp',
            process: 'chrome.exe',
            chains: ['direct'],
            rule: 'domain_suffix',
            uploadBytes: 100,
            downloadBytes: 200,
            start: null,
            route: LiveRouteKind.direct,
          ),
        ],
      );

      expect(detectRoutingMismatch(snap, split, noRealIp: false), isNull);
    });

    test('ignores connection from app with overrideSites enabled', () {
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [
          AppRule(r'C:\App\curl.exe', action: AppAction.direct, overrideSites: true),
        ],
        sites: [
          SiteRule('anthropic.com', action: AppAction.tunnel),
        ],
      );
      final snap = LiveConnectionsSnapshot(
        direct: [
          const LiveConnectionEntry(
            id: 'd3',
            host: 'anthropic.com',
            destinationIp: '160.79.104.10',
            destinationPort: 443,
            network: 'tcp',
            process: 'curl.exe',
            chains: ['direct'],
            rule: 'process_name',
            uploadBytes: 10,
            downloadBytes: 20,
            start: null,
            route: LiveRouteKind.direct,
          ),
        ],
      );

      expect(detectRoutingMismatch(snap, split, noRealIp: false), isNull);
    });

    test('filters silentgate.exe and whitelist-bypass.exe loop-prevention direct connections (SiteFavicon regression)', () {
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [
          SiteRule('fbsbx.com', action: AppAction.tunnel),
        ],
      );
      final raw = {
        'connections': [
          {
            'id': 'favicon-1',
            'chains': ['direct'],
            'rule': 'process_name=silentgate.exe',
            'metadata': {
              'network': 'tcp',
              'host': 'fbsbx.com',
              'destinationIP': '157.240.241.35',
              'destinationPort': 443,
              'processPath': r'C:\Users\User\AppData\Local\Programs\SilentGate\silentgate.exe',
            },
          },
          {
            'id': 'wb-1',
            'chains': ['direct'],
            'rule': 'process_name=whitelist-bypass.exe',
            'metadata': {
              'network': 'udp',
              'host': 'vk.com',
              'destinationIP': '87.240.137.158',
              'destinationPort': 443,
              'process': 'whitelist-bypass.exe',
            },
          },
        ],
      };

      final snap = LiveConnectionsSnapshot.fromClashJson(raw, split: split);
      expect(snap.totalCount, 0);
      expect(detectRoutingMismatch(snap, split, noRealIp: false), isNull);
    });

    test('ignores technical QUIC UDP:443 reject on tunneled sites and blocked apps without overrideSites', () {
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: [
          AppRule(r'C:\App\telemetry.exe', action: AppAction.block, overrideSites: false),
        ],
        sites: [
          SiteRule('fbsbx.com', action: AppAction.tunnel),
        ],
      );
      final raw = {
        'connections': [
          {
            'id': 'quic-downgrade',
            'chains': <String>[],
            'rule': 'network=udp port=443 action=reject',
            'metadata': {
              'network': 'udp',
              'host': 'fbsbx.com',
              'destinationIP': '157.240.241.35',
              'destinationPort': 443,
              'process': 'chrome.exe',
            },
          },
          {
            'id': 'blocked-app',
            'chains': <String>[],
            'rule': 'process_name=telemetry.exe action=reject',
            'metadata': {
              'network': 'tcp',
              'host': 'fbsbx.com',
              'destinationIP': '157.240.241.35',
              'destinationPort': 443,
              'process': 'telemetry.exe',
            },
          },
        ],
      };

      final snap = LiveConnectionsSnapshot.fromClashJson(raw, split: split);
      // QUIC UDP:443 downgrade is dropped from snapshot; telemetry.exe remains in blocked
      // because its app rule really is AppAction.block, but does NOT trigger site mismatch!
      expect(snap.blocked, hasLength(1));
      expect(snap.blocked.single.process, 'telemetry.exe');
      expect(detectRoutingMismatch(snap, split, noRealIp: false), isNull);
    });

    test('splitRoutingSignature changes on site, app, or noRealIp edits', () {
      const base = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [SiteRule('fbsbx.com', action: AppAction.tunnel)],
      );
      final sig0 = splitRoutingSignature(base, noRealIp: false);
      expect(splitRoutingSignature(base, noRealIp: false), sig0);
      expect(splitRoutingSignature(base, noRealIp: true), isNot(sig0));
      expect(
        splitRoutingSignature(
          base.copyWith(
            sites: [...base.sites, const SiteRule('google.dev', action: AppAction.tunnel)],
          ),
          noRealIp: false,
        ),
        isNot(sig0),
      );
      expect(
        splitRoutingSignature(
          base.copyWith(
            apps: [const AppRule(r'C:\App\chrome.exe', byName: true, action: AppAction.direct)],
          ),
          noRealIp: false,
        ),
        isNot(sig0),
      );
    });
  });
}

