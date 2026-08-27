import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/process_list_windows.dart';
import 'package:silentgate/engine/windows/wfp_rules.dart';

/// В WFP можно передать только appId ПОЛНОГО пути: имя из правила «по имени»
/// становится таким путём лишь для живого процесса на момент подъёма защиты.
void main() {
  KillSwitchPlan planWith({
    bool blockAll = false,
    List<String> blockedPaths = const [],
    List<String> allowedPaths = const [],
    List<String> blockedNames = const [],
    List<String> allowedNames = const [],
  }) =>
      KillSwitchPlan(
        allowServerIps: const {'203.0.113.10'},
        allowOwnBinaries: true,
        allowLoopback: true,
        allowLan: true,
        blockedAppPaths: blockedPaths,
        allowedAppPaths: allowedPaths,
        blockedAppNames: blockedNames,
        allowedAppNames: allowedNames,
        blockAll: blockAll,
      );

  group('Имена выбранных приложений материализуются в полные пути', () {
    test('сохраняет явные пути и добавляет все живые совпадения', () {
      final plan = planWith(
        blockedPaths: const [r'C:\explicit\fixed.exe'],
        blockedNames: const ['claude.exe'],
        allowedNames: const ['browser.exe'],
      );

      final materialized = plan.withMaterializedAppPaths([
        const RunningProcess(1, 'claude.exe', r'C:\one\claude.exe'),
        const RunningProcess(2, 'CLAUDE.EXE', r'D:\two\claude.exe'),
        const RunningProcess(3, 'browser.exe', r'C:\one\browser.exe'),
        const RunningProcess(4, 'editor.exe', r'C:\other\editor.exe'),
      ]);

      expect(materialized.blockedAppPaths, [
        r'C:\explicit\fixed.exe',
        r'C:\one\claude.exe',
        r'D:\two\claude.exe',
      ]);
      expect(materialized.allowedAppPaths, [r'C:\one\browser.exe']);
      expect(materialized.blockedAppNames, ['claude.exe']);
      expect(materialized.allowedAppNames, ['browser.exe']);
    });

    test('сравнивает basename без учёта регистра', () {
      final materialized = planWith(blockedNames: const ['ClAuDe.ExE'])
          .withMaterializedAppPaths([
        const RunningProcess(1, 'claude.exe', r'C:\one\claude.exe'),
      ]);

      expect(materialized.blockedAppPaths, [r'C:\one\claude.exe']);
    });

    test('одинаковое имя в двух каталогах даёт оба полных пути', () {
      final materialized = planWith(blockedNames: const ['claude.exe'])
          .withMaterializedAppPaths([
        const RunningProcess(1, 'claude.exe', r'C:\one\claude.exe'),
        const RunningProcess(2, 'claude.exe', r'D:\two\claude.exe'),
      ]);

      expect(materialized.blockedAppPaths,
          [r'C:\one\claude.exe', r'D:\two\claude.exe']);
    });

    test('не добавляет невыбранный процесс', () {
      final materialized = planWith(blockedNames: const ['claude.exe'])
          .withMaterializedAppPaths([
        const RunningProcess(1, 'editor.exe', r'C:\other\editor.exe'),
      ]);

      expect(materialized.blockedAppPaths, isEmpty);
    });

    test('не дублирует один путь без учёта регистра', () {
      final materialized = planWith(
        blockedPaths: const [r'C:\one\claude.exe'],
        blockedNames: const ['claude.exe'],
      ).withMaterializedAppPaths([
        const RunningProcess(1, 'claude.exe', r'c:\ONE\CLAUDE.EXE'),
        const RunningProcess(2, 'claude.exe', r'C:\one\claude.exe'),
      ]);

      expect(materialized.blockedAppPaths, [r'C:\one\claude.exe']);
    });

    test('селектор без живого процесса не делает план непустым', () {
      final materialized = planWith(blockedNames: const ['claude.exe'])
          .withMaterializedAppPaths(const []);

      expect(materialized.blockAll, isFalse);
      expect(materialized.blockedAppPaths, isEmpty);
      expect(materialized.isEmpty, isTrue);
    });

    test('материализация следует за списком процессов', () {
      // Правило по имени — это подписка, состав путей обязан меняться вслед за живыми процессами.
      final plan = planWith(blockedNames: const ['claude.exe']);
      final first = plan.withMaterializedAppPaths([
        const RunningProcess(1, 'claude.exe', r'C:\one\claude.exe'),
      ]);
      final second = plan.withMaterializedAppPaths([
        const RunningProcess(1, 'claude.exe', r'C:\one\claude.exe'),
        const RunningProcess(2, 'claude.exe', r'D:\two\claude.exe'),
      ]);
      expect(first.blockedAppPaths, isNot(contains(r'D:\two\claude.exe')));
      expect(second.blockedAppPaths, contains(r'D:\two\claude.exe'));
    });
  });
}
