import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/engine/windows/kill_switch_app_selectors.dart';

void main() {
  // Общий набор правил: по имени и по пути, для tunnel и direct, плюс
  // выключенное правило, которое не должно попасть никуда.
  const rules = [
    AppRule(r'C:\old\claude.exe', byName: true, action: AppAction.tunnel),
    AppRule(r'C:\exact\game.exe', byName: false, action: AppAction.tunnel),
    AppRule(r'C:\old\browser.exe', byName: true, action: AppAction.direct),
    AppRule(r'C:\exact\proxy.exe', byName: false, action: AppAction.direct),
    AppRule(r'C:\disabled\ignored.exe',
        byName: true, action: AppAction.tunnel, enabled: false),
  ];

  group('KillSwitchAppSelectors.fromSplitTunnel', () {
    test('onlySelected: имя и путь идут в разные blocked-списки', () {
      final selectors = KillSwitchAppSelectors.fromSplitTunnel(
        const SplitTunnelConfig(mode: SplitMode.onlySelected, apps: rules),
      );

      expect(selectors.blockedAppNames, ['claude.exe']);
      expect(selectors.blockedAppPaths, [r'C:\exact\game.exe']);
      expect(selectors.allowedAppNames, isEmpty);
      expect(selectors.allowedAppPaths, isEmpty);

      // Выключенное правило не попало никуда.
      expect(selectors.blockedAppNames, isNot(contains('ignored.exe')));
      expect(selectors.blockedAppPaths,
          isNot(contains(r'C:\disabled\ignored.exe')));
    });

    test('exceptSelected: имя и путь идут в разные allowed-списки', () {
      final selectors = KillSwitchAppSelectors.fromSplitTunnel(
        const SplitTunnelConfig(mode: SplitMode.exceptSelected, apps: rules),
      );

      expect(selectors.allowedAppNames, ['browser.exe']);
      expect(selectors.allowedAppPaths, [r'C:\exact\proxy.exe']);
      expect(selectors.blockedAppNames, isEmpty);
      expect(selectors.blockedAppPaths, isEmpty);
    });

    test('all: app selectors пусты — действует blockAll', () {
      final selectors = KillSwitchAppSelectors.fromSplitTunnel(
        const SplitTunnelConfig(mode: SplitMode.all, apps: rules),
      );

      expect(selectors.blockedAppNames, isEmpty);
      expect(selectors.blockedAppPaths, isEmpty);
      expect(selectors.allowedAppNames, isEmpty);
      expect(selectors.allowedAppPaths, isEmpty);
    });

    test('порядок правил сохраняется', () {
      const ordered = [
        AppRule(r'C:\a\one.exe', byName: true, action: AppAction.tunnel),
        AppRule(r'C:\b\two.exe', byName: true, action: AppAction.tunnel),
        AppRule(r'C:\c\three.exe', byName: true, action: AppAction.tunnel),
      ];
      final selectors = KillSwitchAppSelectors.fromSplitTunnel(
        const SplitTunnelConfig(mode: SplitMode.onlySelected, apps: ordered),
      );
      expect(selectors.blockedAppNames, ['one.exe', 'two.exe', 'three.exe']);
    });
  });

  group('Страж интеграции: _writeKillSwitchPlan использует селекторы', () {
    // ⚠️ Читаем исходник, а не гоняем сам движок: `_writeKillSwitchPlan`
    // трогает реальный `AppPaths.supportDir()` и мьютекс живого процесса —
    // именно то, чего тесты касаться не должны (см. Глобальные ограничения).
    // Страж проверяет СВЯЗЬ кода, а не поведение рантайма.
    late String source;

    setUpAll(() {
      source = File('lib/engine/windows/windows_engine.dart')
          .readAsStringSync();
    });

    test('вызывает KillSwitchAppSelectors.fromSplitTunnel', () {
      expect(source, contains('KillSwitchAppSelectors.fromSplitTunnel'));
    });

    test('передаёт все четыре списка селекторов в KillSwitchPlanFile.write',
        () {
      expect(source, contains('blockedAppPaths: selectors.blockedAppPaths'));
      expect(source, contains('blockedAppNames: selectors.blockedAppNames'));
      expect(source, contains('allowedAppPaths: selectors.allowedAppPaths'));
      expect(source, contains('allowedAppNames: selectors.allowedAppNames'));
    });

    test('прежней прямой передачи r.path в blocked/allowed AppPaths больше нет',
        () {
      expect(source, isNot(contains('blockedAppPaths: onlySelected')));
      expect(
          source,
          isNot(contains(
              'allowedAppPaths: s.splitTunnel.mode == SplitMode.exceptSelected')));
      // Общий страж: внутри метода не должно остаться inline-цикла,
      // кладущего `r.path` прямо в списки плана.
      final methodStart = source.indexOf('_writeKillSwitchPlan(');
      final methodBody = source.substring(
          methodStart, source.indexOf('\n  Future<', methodStart + 1));
      expect(methodBody, isNot(contains('r.path,')));
    });
  });
}
