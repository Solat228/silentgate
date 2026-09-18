import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';

/// Импорт/экспорт правил раздельного туннелирования (кнопки на экране).
///
/// ⚠️ РАЗБОР ЧУЖОГО ТЕКСТА — САМОЕ ОПАСНОЕ МЕСТО: импорт ЗАМЕНЯЕТ все правила.
/// Значит `tryDecode` обязан отвергать всё, что не помечено нами, и никогда не
/// бросать — иначе случайный JSON из буфера снёс бы настройки пользователя.
void main() {
  final sample = SplitTunnelConfig(
    mode: SplitMode.onlySelected,
    apps: [
      AppRule('chrome.exe', byName: true, action: AppAction.tunnel),
      AppRule('C:/games/steam.exe', byName: false, action: AppAction.direct),
    ],
    sites: [
      SiteRule('youtube.com', action: AppAction.tunnel),
      SiteRule('ads.example.com', port: 8443, action: AppAction.block),
    ],
  );

  group('SplitTunnelBackup — круговой перенос', () {
    test('encode → tryDecode сохраняет режим, приложения, сайты и галочку', () {
      final text = SplitTunnelBackup.encode(sample, blockNotice: true);
      final got = SplitTunnelBackup.tryDecode(text);
      expect(got, isNotNull);
      expect(got!.blockNotice, isTrue);
      expect(got.split.mode, SplitMode.onlySelected);
      expect(got.split.apps.map((a) => a.path),
          containsAll(['chrome.exe', 'C:/games/steam.exe']));
      expect(got.split.sites.map((s) => s.domain),
          containsAll(['youtube.com', 'ads.example.com']));
      expect(
          got.split.sites.firstWhere((s) => s.domain == 'ads.example.com').port,
          8443);
      expect(
          got.split.sites.firstWhere((s) => s.domain == 'ads.example.com').action,
          AppAction.block);
    });

    test('blockNotice=false переносится как false, а не теряется', () {
      final got =
          SplitTunnelBackup.tryDecode(SplitTunnelBackup.encode(sample, blockNotice: false));
      expect(got!.blockNotice, isFalse);
    });

    test('текст экспорта — валидный JSON с меткой silentgate', () {
      final j = jsonDecode(SplitTunnelBackup.encode(sample, blockNotice: true));
      expect(j['silentgate'], 'split-tunnel');
      expect(j['splitTunnel'], isA<Map>());
    });
  });

  group('SplitTunnelBackup — отвергает чужое, не бросает', () {
    test('пустая строка → null', () {
      expect(SplitTunnelBackup.tryDecode(''), isNull);
      expect(SplitTunnelBackup.tryDecode('   '), isNull);
    });

    test('не-JSON → null', () {
      expect(SplitTunnelBackup.tryDecode('это не json'), isNull);
      expect(SplitTunnelBackup.tryDecode('vless://abc@1.2.3.4:443'), isNull);
    });

    test('JSON без нашей метки → null (чужой конфиг не подменит правила)', () {
      expect(SplitTunnelBackup.tryDecode('{"mode":"all","apps":[]}'), isNull);
      expect(
          SplitTunnelBackup.tryDecode('{"silentgate":"other","splitTunnel":{}}'),
          isNull);
    });

    test('метка есть, но splitTunnel не объект → null', () {
      expect(
          SplitTunnelBackup.tryDecode(
              '{"silentgate":"split-tunnel","splitTunnel":"нет"}'),
          isNull);
    });

    test('корректная метка без blockNoticeEnabled → blockNotice == null', () {
      final text =
          '{"silentgate":"split-tunnel","splitTunnel":{"mode":"all","apps":[],"sites":[]}}';
      final got = SplitTunnelBackup.tryDecode(text);
      expect(got, isNotNull);
      expect(got!.blockNotice, isNull);
      expect(got.split.mode, SplitMode.all);
    });
  });
}
