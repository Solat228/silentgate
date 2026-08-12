import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';

/// Тождественность правила приложения.
///
/// ⚠️ ДЕФЕКТ, РАДИ КОТОРОГО ЭТОТ ФАЙЛ СУЩЕСТВУЕТ. Правило «по имени»
/// сопоставляется с процессом по имени файла, а искалось и хранилось — по
/// ПОЛНОМУ ПУТИ. Программа обновилась, путь сменился — и та же программа
/// заводилась заново. У владельца так набралось четыре строки `claude.exe`
/// (пути `…claude-code-2.1.222-win32…`, `…223…`, `…226…`, `…227…`), внешне
/// неразличимых, и после каждого обновления настройка «ломалась»: срабатывала
/// не та запись, которую он правил.
///
/// Ни компилятор, ни `sing-box check` такое не ловят: правило видно в
/// интерфейсе, лежит в конфиге и выглядит рабочим.
void main() {
  // Реальные пути со скриншота владельца — специально не выдуманные.
  const v222 =
      r'C:\Users\User\.vscode\extensions\anthropic.claude-code-2.1.222-win32-x64\claude.exe';
  const v227 =
      r'C:\Users\User\.vscode\extensions\anthropic.claude-code-2.1.227-win32-x64\claude.exe';

  group('Ключ сопоставления', () {
    test('«по имени» ключуется именем файла, «по пути» — путём', () {
      expect(const AppRule(v222, byName: true).matchKey, 'claude.exe');
      expect(const AppRule(v222).matchKey, v222.toLowerCase());
    });

    test('регистр пути не создаёт вторую запись', () {
      expect(const AppRule(r'C:\App\Chrome.EXE', byName: true).matchKey,
          const AppRule(r'c:\app\chrome.exe', byName: true).matchKey);
    });
  });

  group('Обновление программы не ломает правило', () {
    test('правило «по имени» узнаёт программу по НОВОМУ пути', () {
      const rule = AppRule(v222, byName: true, action: AppAction.tunnel);
      expect(rule.matches(v227), isTrue,
          reason: 'сменился только путь — программа та же');
    });

    test('пикер не предложит добавить уже добавленное после обновления', () {
      const cfg = SplitTunnelConfig(apps: [AppRule(v222, byName: true)]);
      // Ровно то, что делает фильтр списка «Из запущенных».
      expect(cfg.containsApp(v227), isTrue,
          reason: 'иначе после каждого обновления заводится дубль');
    });

    test('правило «по пути» НЕ ловит другой путь с тем же именем', () {
      const rule = AppRule(v222, action: AppAction.tunnel);
      expect(rule.matches(v227), isFalse,
          reason: 'выбравший «по пути» просил именно этот файл');
      expect(rule.matches(v222), isTrue);
    });
  });

  group('Свёртка дублей', () {
    test('четыре записи одной программы становятся одной', () {
      final collapsed = SplitTunnelConfig.dedupeApps(const [
        AppRule(v222, byName: true, action: AppAction.tunnel),
        AppRule(v227, byName: true, action: AppAction.direct),
        AppRule(v222, byName: true, action: AppAction.block),
      ]);
      expect(collapsed, hasLength(1));
      expect(collapsed.single.action, AppAction.block,
          reason: 'запрет переживает свёртку: молча открыть сеть хуже, '
              'чем оставить лишний запрет');
    });

    test('выключенное правило не вытесняет включённое', () {
      // Это МИГРАЦИЯ чужих настроек: выбор вслепую молча убрал бы работающее
      // правило в пользу того, что пользователь сам припарковал галочкой.
      final collapsed = SplitTunnelConfig.dedupeApps(const [
        AppRule(v222, byName: true, action: AppAction.tunnel, enabled: false),
        AppRule(v227, byName: true, action: AppAction.tunnel),
      ]);
      expect(collapsed.single.enabled, isTrue);
    });

    test('«Блок» переживает свёртку — ошибка в сторону доступа опаснее', () {
      // Пользователь ставил запрет намеренно и о его снятии не узнает;
      // лишний запрет он заметит сразу и вернёт сам.
      final collapsed = SplitTunnelConfig.dedupeApps(const [
        AppRule(v222, byName: true, action: AppAction.tunnel),
        AppRule(v227, byName: true, action: AppAction.block),
      ]);
      expect(collapsed.single.action, AppAction.block);
    });

    test('включённое важнее блока: выключенный блок не побеждает', () {
      final collapsed = SplitTunnelConfig.dedupeApps(const [
        AppRule(v222, byName: true, action: AppAction.tunnel),
        AppRule(v227, byName: true, action: AppAction.block, enabled: false),
      ]);
      expect(collapsed.single.action, AppAction.tunnel);
      expect(collapsed.single.enabled, isTrue);
    });

    test('разные программы не схлопываются', () {
      final collapsed = SplitTunnelConfig.dedupeApps(const [
        AppRule(r'C:\a\chrome.exe', byName: true),
        AppRule(r'C:\b\firefox.exe', byName: true),
      ]);
      expect(collapsed, hasLength(2));
    });

    test('правила «по пути» с одним именем — разные записи', () {
      final collapsed = SplitTunnelConfig.dedupeApps(const [
        AppRule(v222),
        AppRule(v227),
      ]);
      expect(collapsed, hasLength(2),
          reason: 'по пути это осознанно разные файлы');
    });

    test('старые настройки чинятся ПРИ ЧТЕНИИ, а не остаются как есть', () {
      // Это миграция: у владельца дубли уже лежат на диске.
      final cfg = SplitTunnelConfig.fromJson({
        'mode': 'onlySelected',
        'apps': [
          {'path': v222, 'byName': true, 'action': 'tunnel'},
          {'path': v227, 'byName': true, 'action': 'tunnel'},
        ],
      });
      expect(cfg.apps, hasLength(1));
    });
  });

  group('Правило находится для правки', () {
    test('appRuleFor возвращает запись по новому пути', () {
      const cfg = SplitTunnelConfig(apps: [
        AppRule(r'C:\x\firefox.exe', byName: true),
        AppRule(v222, byName: true, action: AppAction.block),
      ]);
      expect(cfg.appRuleFor(v227)?.action, AppAction.block);
    });

    test('незнакомая программа не находится', () {
      const cfg = SplitTunnelConfig(apps: [AppRule(v222, byName: true)]);
      expect(cfg.appRuleFor(r'C:\y\notepad.exe'), isNull);
    });
  });
}
