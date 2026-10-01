import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/settings/split_tunnel_text.dart';

void main() {
  group('Сайты: разбор текстового списка', () {
    test('⚠️ голый список доменов равен ручному вводу в поле', () {
      // Ради этого сценария формат и переделывали: человек берёт чужой список,
      // вставляет целиком и ничего не правит.
      final p = parseSiteRules('youtube.com\nnetflix.com\n',
          defaultAction: AppAction.tunnel);
      expect(p.badLines, isEmpty);
      expect(p.rules.map((s) => s.domain), ['youtube.com', 'netflix.com']);
      expect(p.rules.every((s) => s.action == AppAction.tunnel), isTrue);
      expect(p.rules.every((s) => s.serverKey == null), isTrue);
      expect(p.rules.every((s) => !s.allowRealIp), isTrue);
    });

    test('действие по умолчанию берётся от режима, а не прибито к туннелю', () {
      final p =
          parseSiteRules('example.com', defaultAction: AppAction.direct);
      expect(p.rules.single.action, AppAction.direct);
    });

    test('секции переключают действие', () {
      final p = parseSiteRules('''
[tunnel]
a.com
[direct]
b.com
[block]
c.com
''', defaultAction: AppAction.tunnel);
      expect(p.rules.map((s) => s.action),
          [AppAction.tunnel, AppAction.direct, AppAction.block]);
    });

    test('⚠️ неизвестная секция не меняет действие, но и не проглатывается', () {
      final p = parseSiteRules('[tunnel]\na.com\n[непонятно]\nb.com',
          defaultAction: AppAction.direct);
      expect(p.rules.map((s) => s.action),
          [AppAction.tunnel, AppAction.tunnel],
          reason: 'опечатка в заголовке не должна менять действие у хвоста');
      expect(p.badLines, ['[непонятно]'],
          reason: 'иначе опечатка в заголовке тихо уводит правила не туда');
    });

    test('порт, схема и www разбираются как при ручном вводе', () {
      final p = parseSiteRules(
          'https://www.Example.COM:8443/lk?x=1\nhttp://old.example.org',
          defaultAction: AppAction.tunnel);
      expect(p.rules[0].domain, 'example.com');
      expect(p.rules[0].port, 8443);
      expect(p.rules[0].insecureScheme, isFalse);
      expect(p.rules[1].domain, 'old.example.org');
      expect(p.rules[1].port, isNull);
      expect(p.rules[1].insecureScheme, isTrue,
          reason: 'явный http:// — это замок в списке');
    });

    test('пустые строки и комментарии пропускаются молча', () {
      final p = parseSiteRules('\n# это список для работы\n\na.com\n',
          defaultAction: AppAction.tunnel);
      expect(p.rules.map((s) => s.domain), ['a.com']);
      expect(p.badLines, isEmpty);
    });

    test('⚠️ строка без точки не становится доменом, но и не пропадает молча',
        () {
      final p = parseSiteRules('Мой список сайтов\na.com',
          defaultAction: AppAction.tunnel);
      expect(p.rules.map((s) => s.domain), ['a.com']);
      expect(p.badLines, ['Мой список сайтов'],
          reason: 'человек обязан увидеть, что именно не взяли');
    });

    test('повтор внутри одного текста берётся один раз', () {
      final p = parseSiteRules('a.com\na.com\nA.COM',
          defaultAction: AppAction.tunnel);
      expect(p.rules, hasLength(1));
    });

    test('один домен с разными портами — разные записи', () {
      final p = parseSiteRules('a.com\na.com:443',
          defaultAction: AppAction.tunnel);
      expect(p.rules.map((s) => s.port), [null, 443]);
    });

    test('флаг real-ip читается', () {
      final p =
          parseSiteRules('a.com real-ip', defaultAction: AppAction.direct);
      expect(p.rules.single.allowRealIp, isTrue);
    });
  });

  group('Сайты: выход записывается именем, а не ключом', () {
    const key = 'vless://uuid@203.0.113.10:443?type=tcp#DE';

    test('⚠️ в тексте нет ни ключа сервера, ни адреса', () {
      final text = encodeSiteRules(
          const [SiteRule('a.com', action: AppAction.tunnel, serverKey: key)],
          exitNameOf: (_) => 'Германия 2');
      expect(text, contains('exit="Германия 2"'));
      expect(text, isNot(contains('vless')));
      expect(text, isNot(contains('203.0.113.10')));
      expect(text, isNot(contains('uuid')));
    });

    test('имя с пробелом переживает круг', () {
      final text = encodeSiteRules(
          const [SiteRule('a.com', action: AppAction.tunnel, serverKey: key)],
          exitNameOf: (_) => 'Германия 2');
      final back = parseSiteRules(text,
          defaultAction: AppAction.tunnel,
          exitKeyOf: (n) => n == 'Германия 2' ? key : null);
      expect(back.rules.single.serverKey, key);
    });

    test('имя, которому нет сервера, читается как общий туннель', () {
      final back = parseSiteRules('a.com exit=Атлантида',
          defaultAction: AppAction.tunnel, exitKeyOf: (_) => null);
      expect(back.rules.single.serverKey, isNull,
          reason: 'висячий тег в конфиге опаснее — sing-box check его не ловит');
    });

    test('выход не пишется, если имени для ключа нет', () {
      final text = encodeSiteRules(
          const [SiteRule('a.com', action: AppAction.tunnel, serverKey: key)],
          exitNameOf: (_) => null);
      expect(text, isNot(contains('exit=')));
    });
  });

  group('Сайты: круг экспорт → импорт', () {
    test('все поля переживают круг', () {
      const src = [
        SiteRule('a.com', action: AppAction.tunnel),
        SiteRule('b.com', port: 8443, action: AppAction.direct, allowRealIp: true),
        SiteRule('c.com', action: AppAction.direct, insecureScheme: true),
        SiteRule('d.com', action: AppAction.block),
      ];
      final back =
          parseSiteRules(encodeSiteRules(src), defaultAction: AppAction.tunnel);
      expect(back.rules, hasLength(src.length));
      for (var i = 0; i < src.length; i++) {
        final a = src[i], b = back.rules[i];
        expect(b.domain, a.domain);
        expect(b.port, a.port);
        expect(b.action, a.action);
        expect(b.allowRealIp, a.allowRealIp);
        expect(b.insecureScheme, a.insecureScheme);
      }
    });

    test('группы идут туннель → прямо → блок', () {
      final text = encodeSiteRules(const [
        SiteRule('c.com', action: AppAction.block),
        SiteRule('a.com', action: AppAction.tunnel),
        SiteRule('b.com', action: AppAction.direct),
      ]);
      expect(text.indexOf('[tunnel]'), lessThan(text.indexOf('[direct]')));
      expect(text.indexOf('[direct]'), lessThan(text.indexOf('[block]')));
    });

    test('пустой список даёт пустой текст, а не заголовки', () {
      expect(encodeSiteRules(const []), isEmpty);
    });
  });

  group('Приложения: разбор', () {
    test('⚠️ способ сопоставления выводится из самой строки', () {
      final p = parseAppRules(
          'Telegram.exe\nC:\\Telegram Desktop\\Telegram.exe',
          defaultAction: AppAction.tunnel);
      expect(p.rules[0].byName, isTrue);
      expect(p.rules[1].byName, isFalse,
          reason: 'правило «по имени» с полным путём потеряло бы программу '
              'после её обновления');
    });

    test('путь с пробелами в кавычках не рвётся на токены', () {
      final p = parseAppRules('"C:\\Program Files\\App\\a.exe" off',
          defaultAction: AppAction.tunnel);
      expect(p.rules.single.path, r'C:\Program Files\App\a.exe');
      expect(p.rules.single.enabled, isFalse);
    });

    test('флаги off / real-ip / before-sites читаются', () {
      final p = parseAppRules('a.exe off real-ip before-sites',
          defaultAction: AppAction.direct);
      final r = p.rules.single;
      expect(r.enabled, isFalse);
      expect(r.allowRealIp, isTrue);
      expect(r.overrideSites, isTrue);
    });

    test('голая строка — включённое правило с действием режима', () {
      final p = parseAppRules('a.exe', defaultAction: AppAction.direct);
      expect(p.rules.single.enabled, isTrue);
      expect(p.rules.single.action, AppAction.direct);
      expect(p.rules.single.overrideSites, isFalse);
    });

    test('повтор по ключу сопоставления берётся один раз', () {
      final p = parseAppRules('a.exe\nA.EXE', defaultAction: AppAction.tunnel);
      expect(p.rules, hasLength(1));
    });

    test('круг экспорт → импорт сохраняет поля', () {
      const src = [
        AppRule('a.exe', byName: true, action: AppAction.tunnel),
        AppRule(r'C:\x\b.exe', action: AppAction.direct, enabled: false),
        AppRule('c.exe',
            byName: true, action: AppAction.block, overrideSites: true),
      ];
      final back =
          parseAppRules(encodeAppRules(src), defaultAction: AppAction.tunnel);
      expect(back.rules, hasLength(3));
      for (var i = 0; i < src.length; i++) {
        expect(back.rules[i].matchKey, src[i].matchKey);
        expect(back.rules[i].action, src[i].action);
        expect(back.rules[i].enabled, src[i].enabled);
        expect(back.rules[i].overrideSites, src[i].overrideSites);
        expect(back.rules[i].byName, src[i].byName);
      }
    });

    test('⚠️ в тексте приложений тоже нет ключей серверов', () {
      const key = 'vless://uuid@203.0.113.10:443#DE';
      final text = encodeAppRules(
          const [AppRule('a.exe', byName: true, action: AppAction.tunnel, serverKey: key)],
          exitNameOf: (_) => 'Германия');
      expect(text, contains('exit=Германия'));
      expect(text, isNot(contains('203.0.113.10')));
    });
  });

  group('Слияние: добавить в готовый список', () {
    const current = [
      SiteRule('a.com', action: AppAction.tunnel),
      SiteRule('b.com', action: AppAction.direct),
    ];

    test('новые — в added, такие же — в unchanged, иные — в conflicts', () {
      final plan = planSiteMerge(current, const [
        SiteRule('c.com', action: AppAction.tunnel), // новый
        SiteRule('a.com', action: AppAction.tunnel), // такой же
        SiteRule('b.com', action: AppAction.block), // спор
      ]);
      expect(plan.added.map((s) => s.domain), ['c.com']);
      expect(plan.unchanged.map((s) => s.domain), ['a.com']);
      expect(plan.conflicts, hasLength(1));
      expect(plan.conflicts.single.current.action, AppAction.direct);
      expect(plan.conflicts.single.incoming.action, AppAction.block);
    });

    test('⚠️ спор по порту не придумывается: a.com и a.com:443 — разные записи',
        () {
      final plan = planSiteMerge(
          current, const [SiteRule('a.com', port: 443, action: AppAction.block)]);
      expect(plan.conflicts, isEmpty);
      expect(plan.added, hasLength(1));
    });

    test('применение без перезаписи не трогает спорные', () {
      final plan = planSiteMerge(current, const [
        SiteRule('c.com', action: AppAction.tunnel),
        SiteRule('b.com', action: AppAction.block),
      ]);
      final out = applySiteMerge(current, plan, overwriteConflicts: false);
      expect(out.map((s) => s.domain), ['a.com', 'b.com', 'c.com']);
      expect(out[1].action, AppAction.direct, reason: 'правка человека цела');
    });

    test('применение с перезаписью меняет спорные на месте', () {
      final plan = planSiteMerge(
          current, const [SiteRule('b.com', action: AppAction.block)]);
      final out = applySiteMerge(current, plan, overwriteConflicts: true);
      expect(out.map((s) => s.domain), ['a.com', 'b.com'],
          reason: 'порядок существующих записей не меняется');
      expect(out[1].action, AppAction.block);
    });

    test('changes() честно говорит, изменится ли что-нибудь', () {
      final onlyConflict = planSiteMerge(
          current, const [SiteRule('b.com', action: AppAction.block)]);
      expect(onlyConflict.changes(overwriteConflicts: false), isFalse);
      expect(onlyConflict.changes(overwriteConflicts: true), isTrue);
    });

    test('слияние приложений спрашивает ключ сопоставления, а не путь', () {
      // Правило «по имени» обязано узнать ту же программу после обновления,
      // когда полный путь уже другой.
      const have = [AppRule('claude.exe', byName: true, action: AppAction.tunnel)];
      final plan = planAppMerge(
          have, const [AppRule('claude.exe', byName: true, action: AppAction.block)]);
      expect(plan.added, isEmpty);
      expect(plan.conflicts, hasLength(1));
    });

    test('применение приложений сохраняет порядок и дописывает новые', () {
      const have = [AppRule('a.exe', byName: true, action: AppAction.tunnel)];
      final plan = planAppMerge(
          have, const [AppRule('b.exe', byName: true, action: AppAction.direct)]);
      final out = applyAppMerge(have, plan, overwriteConflicts: false);
      expect(out.map((a) => a.name), ['a.exe', 'b.exe']);
    });
  });
}
