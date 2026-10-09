import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/models/server_override.dart';
import 'package:silentgate/core/models/subscription_sync.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/util/server_rekey.dart';
import 'package:silentgate/core/xray/outbound_variant.dart';
import 'package:silentgate/state/probe_controller.dart';

/// Панель переписала ссылку сервера (ротация `publicKey`/`shortId`/`sni`), а
/// сервер тот же. Всё, что лежало по старому ключу, обязано переехать на новый —
/// иначе пин держит нерабочие креды, а правило «через Германию» молча уходит в
/// основной туннель (см. `server_rekey.dart`).
void main() {
  const uuid = '00000000-0000-0000-0000-000000000000';

  String link({String pbk = 'OLD', String name = 'Германия 1'}) =>
      'vless://$uuid@203.0.113.10:443?type=tcp&security=reality'
      '&encryption=none&sni=a.example.org&fp=chrome&pbk=$pbk&sid=ab'
      '#${Uri.encodeComponent(name)}';

  // Без expect: разбор идёт при объявлении main(), вне теста.
  VpnServer parse(String l) => ShareLinkParser.tryParse(l)!;

  final oldDe = parse(link());
  final newDe = parse(link(pbk: 'NEW'));
  final other = parse(link(name: 'США 1', pbk: 'US'));

  test('ключи действительно разные — иначе тестировать нечего', () {
    expect(oldDe.key, isNot(newDe.key));
    expect(oldDe.identityKey, newDe.identityKey);
  });

  group('SubscriptionSyncResult.rekey', () {
    SubscriptionSyncResult diff(List<VpnServer> a, List<VpnServer> b) =>
        SubscriptionSyncResult.diff(
          before: a,
          after: b,
          withPanelConfig: 0,
          panelProfiles: 0,
          at: DateTime(2026, 10, 10),
        );

    test('сменившийся ключ даёт пару «старый → новый»', () {
      final r = diff([oldDe, other], [newDe, other]).rekey;
      expect(r, {oldDe.key: newDe.key});
    });

    test('без смены ключей — пусто', () {
      expect(diff([oldDe, other], [oldDe, other]).rekey, isEmpty);
    });
  });

  group('ServerRekey.pins', () {
    test('старая запись заменяется новой НА ТОМ ЖЕ МЕСТЕ', () {
      final out = ServerRekey.pins([other, oldDe], {oldDe.key: newDe});
      expect(out.map((s) => s.key), [other.key, newDe.key]);
      expect(identical(out[1], newDe), isTrue,
          reason: 'заменяется весь сервер — в старом старые креды');
    });

    test('новая уже закреплена — дубль не появляется', () {
      final out = ServerRekey.pins([oldDe, newDe], {oldDe.key: newDe});
      expect(out.map((s) => s.key), [newDe.key]);
    });

    test('пустая карта — тот же список', () {
      final list = [oldDe];
      expect(identical(ServerRekey.pins(list, const {}), list), isTrue);
    });
  });

  group('ServerRekey.overrides', () {
    const v = OutboundVariant(fingerprint: 'firefox');

    test('вариация переезжает, старая запись уходит', () {
      final r = ServerRekey.overrides(
          {oldDe.key: const ServerOverride(variant: v)},
          {oldDe.key: newDe.key});
      expect(r.moved, 1);
      expect(r.droppedJson, 0);
      expect(r.overrides.containsKey(oldDe.key), isFalse);
      expect(r.overrides[newDe.key]!.variant!.fingerprint, 'firefox');
    });

    test('⚠️ ручной JSON НЕ переезжает: в нём старые publicKey/uuid', () {
      final r = ServerRekey.overrides(
          {oldDe.key: const ServerOverride(variant: v, rawJson: '{"x":1}')},
          {oldDe.key: newDe.key});
      expect(r.droppedJson, 1);
      expect(r.overrides[newDe.key]!.rawJson, isNull);
      expect(r.overrides[newDe.key]!.variant, isNotNull);
      expect(r.overrides[oldDe.key]!.rawJson, '{"x":1}');
      expect(r.overrides[oldDe.key]!.variant, isNull,
          reason: 'копия вариации на мёртвом ключе не нужна');
    });

    test('только JSON — ничего не переезжает, но учитывается', () {
      final r = ServerRekey.overrides(
          {oldDe.key: const ServerOverride(rawJson: '{"x":1}')},
          {oldDe.key: newDe.key});
      expect(r.moved, 0);
      expect(r.droppedJson, 1);
      expect(r.overrides.containsKey(newDe.key), isFalse);
    });

    test('у нового ключа своя правка — она важнее', () {
      const mine = OutboundVariant(fingerprint: 'safari');
      final r = ServerRekey.overrides({
        oldDe.key: const ServerOverride(variant: v),
        newDe.key: const ServerOverride(variant: mine),
      }, {
        oldDe.key: newDe.key
      });
      expect(r.moved, 0);
      expect(r.overrides[newDe.key]!.variant!.fingerprint, 'safari');
    });
  });

  group('ServerRekey.map', () {
    test('значение переезжает, старый ключ удаляется', () {
      final out = ServerRekey.map({'a': 1, 'x': 9}, {'a': 'b'});
      expect(out, {'b': 1, 'x': 9});
    });

    test('конфликт без merge — побеждает существующее', () {
      expect(ServerRekey.map({'a': 1, 'b': 2}, {'a': 'b'}), {'b': 2});
    });

    test('конфликт с merge — решает merge', () {
      final out = ServerRekey.map({'a': 5, 'b': 2}, {'a': 'b'},
          merge: (have, inc) => inc > have ? inc : have);
      expect(out, {'b': 5});
    });
  });

  group('ServerRekey.settings', () {
    test('выход правила и порт API переезжают на новый ключ', () {
      final s = AppSettings(
        splitTunnel: SplitTunnelConfig(
          mode: SplitMode.onlySelected,
          apps: [
            AppRule('chrome.exe',
                byName: true, action: AppAction.tunnel, serverKey: oldDe.key),
            const AppRule('app.exe', byName: true),
          ],
          sites: [
            SiteRule('example.com',
                action: AppAction.tunnel, serverKey: oldDe.key),
          ],
        ),
        apiExitServerKeys: [oldDe.key, other.key],
      );
      final out = ServerRekey.settings(s, {oldDe.key: newDe.key});
      expect(out.splitTunnel.apps[0].serverKey, newDe.key);
      expect(out.splitTunnel.apps[1].serverKey, isNull);
      expect(out.splitTunnel.sites[0].serverKey, newDe.key);
      expect(out.apiExitServerKeys, [newDe.key, other.key]);
    });

    test('порт API: старый и новый ключ в списке — без дубля', () {
      final s = AppSettings(apiExitServerKeys: [oldDe.key, newDe.key]);
      final out = ServerRekey.settings(s, {oldDe.key: newDe.key});
      expect(out.apiExitServerKeys, [newDe.key]);
    });

    test('⚠️ ссылаться не на что — ТОТ ЖЕ объект (иначе лишний переподъём)',
        () {
      final s = AppSettings(apiExitServerKeys: [other.key]);
      expect(identical(ServerRekey.settings(s, {oldDe.key: newDe.key}), s),
          isTrue);
    });
  });
  group('ProbeController.rekeyResults', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_rekey_probe_');
      AppPaths.overrideRoot(tmp);
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('результат пинга переезжает и переживает перезапуск', () async {
      final probe = ProbeController();
      probe.setResult(
          oldDe, const PingResult(outcome: PingOutcome.ok, latencyMs: 42));
      await probe.rekeyResults({oldDe.key: newDe.key});
      expect(probe.resultFor(newDe).latencyMs, 42);
      expect(probe.resultFor(oldDe).outcome, PingOutcome.untested,
          reason: 'на мёртвом ключе мусор не копится');

      final again = ProbeController();
      await again.init();
      expect(again.resultFor(newDe).latencyMs, 42,
          reason: 'перенос обязан попасть на диск');
    });
  });
}
