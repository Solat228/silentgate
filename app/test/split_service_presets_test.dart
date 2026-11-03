import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_service_presets.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/settings_screen.dart';
import 'package:silentgate/ui/widgets/service_checks_row.dart';

void main() {
  group('SplitServicePresets: каталог и переключение доменов', () {
    test('каталог совпадает по порядку и составу с ServiceChecks.catalog и ProbeService.values',
        () {
      final services = SplitServicePresets.catalog.map((p) => p.service).toList();
      expect(services, ServiceChecks.catalog);
      expect(services.toSet(), ProbeService.values.toSet());
    });

    test('все домены пресетов нормализованы, содержат бренд-домен и не пересекаются',
        () {
      final seen = <String, ProbeService>{};
      for (final preset in SplitServicePresets.catalog) {
        expect(preset.domains, isNotEmpty, reason: preset.service.name);
        expect(
          preset.domains,
          contains(preset.service.domain),
          reason: '${preset.service.name} обязан включать свой основной домен',
        );
        for (final d in preset.domains) {
          expect(d, normalizeDomain(d), reason: 'домен не нормализован: $d');
          expect(
            seen.containsKey(d),
            isFalse,
            reason: 'домен $d дублируется между ${seen[d]} и ${preset.service}',
          );
          seen[d] = preset.service;
        }
      }
    });

    test('включение и выключение YouTube в режиме onlySelected (tunnel)', () {
      const initial = [
        SiteRule('example.org', action: AppAction.tunnel),
        SiteRule('youtube.com', port: 8443, action: AppAction.direct),
      ];
      expect(
        SplitServicePresets.isPresetActive(
            initial, ProbeService.youtube, AppAction.tunnel),
        isFalse,
      );

      final on = SplitServicePresets.togglePreset(
        initial,
        ProbeService.youtube,
        action: AppAction.tunnel,
      );
      expect(on.added, isTrue);
      expect(
        SplitServicePresets.isPresetActive(
            on.sites, ProbeService.youtube, AppAction.tunnel),
        isTrue,
      );
      expect(
        on.sites.any((r) => r.domain == 'googlevideo.com' && r.action == AppAction.tunnel),
        isTrue,
      );
      // Правило с портом и сторонний сайт не тронуты.
      expect(
        on.sites.any((r) => r.domain == 'youtube.com' && r.port == 8443),
        isTrue,
      );
      expect(on.sites.any((r) => r.domain == 'example.org'), isTrue);

      final off = SplitServicePresets.togglePreset(
        on.sites,
        ProbeService.youtube,
        action: AppAction.tunnel,
      );
      expect(off.added, isFalse);
      expect(
        SplitServicePresets.isPresetActive(
            off.sites, ProbeService.youtube, AppAction.tunnel),
        isFalse,
      );
      expect(off.sites, initial);
    });

    test('если один домен сервиса уже был с другим действием, пресет переводит его в текущее',
        () {
      const initial = [
        SiteRule('discord.com', action: AppAction.direct, allowRealIp: true),
      ];
      final on = SplitServicePresets.togglePreset(
        initial,
        ProbeService.discord,
        action: AppAction.tunnel,
      );
      expect(on.added, isTrue);
      expect(
        SplitServicePresets.isPresetActive(
            on.sites, ProbeService.discord, AppAction.tunnel),
        isTrue,
      );
      final updated = on.sites.firstWhere((r) => r.domain == 'discord.com');
      expect(updated.action, AppAction.tunnel);
      expect(updated.allowRealIp, isTrue, reason: 'флаги записи сохраняются');
    });

    test('мессенджеры со звонками/MTProto и Steam помечены needsAppRuleHint', () {
      for (final s in [
        ProbeService.telegram,
        ProbeService.discord,
        ProbeService.whatsapp,
        ProbeService.steam,
      ]) {
        expect(SplitServicePresets.presetFor(s).needsAppRuleHint, isTrue,
            reason: s.name);
      }
      expect(
        SplitServicePresets.presetFor(ProbeService.youtube).needsAppRuleHint,
        isFalse,
      );
    });
  });

  group('Пояснение в разделе проверок сервисов и запрет длинного тире в ARB', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sg_checks_note_');
      AppPaths.overrideRoot(tmp);
    });

    tearDown(() {
      AppPaths.resetForTests();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('в разделе проверок видна подсказка и переход к раздельному туннелированию',
        (tester) async {
      final controller = SettingsController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => SettingsBody(
                sections: buildSettingsSections(ctx, controller.settings, controller)
                    .where((s) => s.id == SettingsSectionIds.checks)
                    .toList(),
                query: '',
                collapsed: const {},
                onToggleSection: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('connectChecksNotSplitNote')), findsOneWidget);
      expect(find.byKey(const Key('connectChecksOpenSplitTunnel')), findsOneWidget);
    });

    test('ни один ARB-файл не содержит длинного тире «—» или «——»', () {
      final dir = Directory('lib/l10n');
      final arbFiles = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))
          .toList();
      expect(arbFiles.length, greaterThanOrEqualTo(10));
      for (final f in arbFiles) {
        final raw = f.readAsStringSync();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in map.entries) {
          if (entry.key.startsWith('@')) continue;
          final val = entry.value;
          if (val is String) {
            expect(val.contains('\u2014'), isFalse,
                reason: '${f.path} -> ${entry.key} содержит длинное тире');
          }
        }
      }
    });
  });
}
