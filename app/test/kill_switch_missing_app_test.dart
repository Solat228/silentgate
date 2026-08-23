import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/wfp_layout.dart';
import 'package:silentgate/engine/windows/wfp_rules.dart';

/// УСТАРЕВШЕЕ ПРАВИЛО НА ПРОГРАММУ НЕ ДОЛЖНО ЛОМАТЬ ПОДКЛЮЧЕНИЕ ЦЕЛИКОМ.
///
/// ⚠️ ЧТО СЛУЧИЛОСЬ 23.08.2026. У владельца VPN перестал подключаться совсем:
/// пинг шёл, а «Подключение…» висело вечно. На каждой из девяти комбинаций
/// автоподбора TUN в журнале стояла одна пара строк:
///
/// ```
/// kill switch: правило «SilentGate: блок claude.exe» отвергнуто, код 3 — откатываю всё
/// НЕ ЗАПУСКАЮ ЯДРО: kill switch включён, но блокировка не поднялась.
/// ```
///
/// Код 3 — `ERROR_PATH_NOT_FOUND`: `FwpmGetAppIdFromFileName0` не выдаёт
/// идентификатор для файла, которого нет. Правило раздельного туннелирования
/// указывало на каталог с номером версии (`…claude-code-2.1.238-win32-x64\…`),
/// программа обновилась — каталог сменился.
///
/// ⚠️ ГЛАВНЫЙ УРОК НЕ ПРО WFP. Сошлись ТРИ решения, каждое верное по
/// отдельности: подъём фильтров одной транзакцией «либо всё, либо ничего»;
/// запрет стартовать ядру, если обещанная блокировка не поднялась; и правило
/// «по пути», которое устаревает молча. Вместе они превратили устаревшую строку
/// в списке в невозможность подключиться. Дефекта не было ни в одном из трёх —
/// он был на их стыке, и ни один тест такое не ловил.
void main() {
  KillSwitchPlan planWith({
    List<String> blocked = const [],
    List<String> allowed = const [],
  }) =>
      KillSwitchPlan(
        allowServerIps: const {'198.51.100.10'},
        allowOwnBinaries: true,
        ownBinaryPaths: const [r'C:\app\silentgate.exe'],
        allowLoopback: true,
        allowLan: true,
        blockedAppPaths: blocked,
        allowedAppPaths: allowed,
        blockAll: false,
      );

  /// Существуют все, кроме путей из [missing].
  bool Function(String) existsExcept(Set<String> missing) =>
      (p) => !missing.contains(p);

  group('⚠️ Пропавшая программа выбрасывается, а не валит план', () {
    test('путь, которого нет, уходит из списка блокировки', () {
      const gone = r'C:\Users\u\.vscode\extensions\claude-code-2.1.238\claude.exe';
      const alive = r'C:\Telegram Desktop\Telegram.exe';
      final r = planWith(blocked: const [gone, alive])
          .withoutMissingApps(existsExcept({gone}));
      expect(r.skipped, [gone]);
      expect(r.plan.blockedAppPaths, [alive],
          reason: 'живой путь обязан остаться');
    });

    test('то же для списка «мимо VPN»', () {
      // ⚠️ Второй список забыть проще всего: именно на нём уже терялись данные
      // при копировании плана (см. withOwnBinaries).
      const gone = r'C:\gone\app.exe';
      final r = planWith(allowed: const [gone, r'C:\ok\ok.exe'])
          .withoutMissingApps(existsExcept({gone}));
      expect(r.skipped, [gone]);
      expect(r.plan.allowedAppPaths, [r'C:\ok\ok.exe']);
    });

    test('⚠️ ПРОПУЩЕННОЕ ВОЗВРАЩАЕТСЯ ВЫЗЫВАЮЩЕМУ', () {
      // Молчаливое отбрасывание вернуло бы ту же болезнь: правило видно в
      // интерфейсе и не делает ничего.
      final r = planWith(blocked: const [r'C:\a\one.exe', r'C:\b\two.exe'])
          .withoutMissingApps(existsExcept({r'C:\a\one.exe', r'C:\b\two.exe'}));
      expect(r.skipped, hasLength(2));
    });

    test('когда всё на месте — возвращается ТОТ ЖЕ план', () {
      // Лишняя пересборка плана — лишний шанс потерять поле при копировании.
      final p = planWith(blocked: const [r'C:\ok\ok.exe']);
      final r = p.withoutMissingApps((_) => true);
      expect(r.skipped, isEmpty);
      expect(identical(r.plan, p), isTrue);
    });
  });

  group('⚠️ Защита от этого не слабеет', () {
    test('остальные правила плана целы', () {
      const gone = r'C:\gone\app.exe';
      final r = planWith(blocked: const [gone]).withoutMissingApps(existsExcept({gone}));
      expect(r.plan.blockAll, isFalse);
      expect(r.plan.allowServerIps, {'198.51.100.10'});
      expect(r.plan.allowLoopback, isTrue);
      expect(r.plan.allowLan, isTrue);
      expect(r.plan.ownBinaryPaths, [r'C:\app\silentgate.exe']);
    });

    test('⚠️ набор фильтров теряет РОВНО одно правило', () {
      // Сравниваем ГОТОВЫЕ правила, а не поля руками: перечень полей уже
      // однажды разошёлся с реальностью и потерял allowedAppPaths молча.
      //
      // ⚠️ Живая программа в списке обязательна: без неё план становится
      // пустым целиком, и сравнивать было бы не с чем — отдельный случай
      // «устарели все» разобран ниже.
      const gone = r'C:\gone\app.exe';
      const alive = r'C:\Telegram Desktop\Telegram.exe';
      final full = buildWfpRules(planWith(blocked: const [gone, alive]));
      final cleaned = buildWfpRules(planWith(blocked: const [gone, alive])
          .withoutMissingApps(existsExcept({gone}))
          .plan);
      expect(full.length - cleaned.length, 1);
      final lost = full
          .map((r) => r.name)
          .toSet()
          .difference(cleaned.map((r) => r.name).toSet());
      expect(lost, {'SilentGate: блок app.exe'});
      expect(cleaned.map((r) => r.name),
          contains('SilentGate: блок Telegram.exe'),
          reason: 'живое правило обязано уцелеть');
    });

    test('⚠️ УСТАРЕЛИ ВСЕ ПРАВИЛА — ЭТО «НЕЧЕГО БЛОКИРОВАТЬ», А НЕ ОТКАЗ', () {
      // Худший случай режима «только отмеченные»: единственная отмеченная
      // программа пропала с диска. План становится ПУСТЫМ — и это законное
      // состояние: блокировать в такой настройке действительно нечего.
      //
      // ⚠️ ЗДЕСЬ ПРЯТАЛАСЬ ВТОРАЯ ДВЕРЬ К ТОЙ ЖЕ БЕДЕ. Прежний гейт в
      // помощнике видел только «блокировка не поднялась» и запрещал ядру
      // стартовать — то есть kill switch без единой отмеченной программы делал
      // подключение невозможным сам по себе, без всяких пропавших путей.
      // Различать обязан вызывающий: пустой план — «не требуется», а не «не
      // смогли». Страж на самом гейте — ниже, в разделе про помощника.
      const gone = r'C:\gone\app.exe';
      final r =
          planWith(blocked: const [gone]).withoutMissingApps(existsExcept({gone}));
      expect(r.plan.isEmpty, isTrue,
          reason: 'план без блокировок обязан честно называть себя пустым');
      expect(buildWfpRules(r.plan), isEmpty);
    });
  });

  group('⚠️ Стражи по исходнику: помощник это зовёт и не молчит', () {
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join(String.fromCharCode(10));

    late String helper;
    setUp(() => helper = code('lib/engine/windows/tun/tun_helper.dart'));

    test('чистка вызывается ДО подъёма фильтров', () {
      final clean = helper.indexOf('withoutMissingApps(');
      final engage = helper.indexOf('KillSwitchWfp.engage(');
      expect(clean, greaterThan(0), reason: 'чистки нет вовсе');
      expect(engage, greaterThan(clean),
          reason: 'подъём обязан идти ПОСЛЕ выбрасывания пропавших');
    });

    test('⚠️ поднимается ИМЕННО очищенный план', () {
      // Легко написать чистку и передать дальше исходный план: тесты выше
      // останутся зелёными, а подключение — сломанным.
      final at = helper.indexOf('KillSwitchWfp.engage(');
      expect(helper.substring(at, at + 40), contains('cleaned.plan'));
    });

    test('каждый пропуск называется в журнале', () {
      expect(helper, contains('cleaned.skipped'));
      expect(helper, contains('пропущено — файла нет на диске'));
    });

    test('⚠️ ГЕЙТ СПРАШИВАЕТ «ОБЯЗАНА ЛИ», А НЕ «ПРОСИЛИ ЛИ»', () {
      // «Блокировку просили» и «без блокировки нельзя» — разные утверждения.
      // Пустой план (нечего блокировать) отвечает на первый вопрос «да», а на
      // второй — «нет»; спутав их, гейт запрещал подключение там, где защищать
      // нечего по построению.
      final at = helper.indexOf('НЕ ЗАПУСКАЮ ЯДРО');
      expect(at, greaterThan(0), reason: 'гейт исчез совсем');
      final head = helper.substring(0, at);
      final guard = head.lastIndexOf('if (hold == null &&');
      expect(guard, greaterThan(0));
      expect(head.substring(guard, at), contains('_mustHaveKillSwitch('),
          reason: 'гейт снова спрашивает «просили ли» — пустой план запретит '
              'подключение');
    });

    test('⚠️ пустой план не требует блокировки', () {
      final at = helper.indexOf('static bool _mustHaveKillSwitch(');
      expect(at, greaterThan(0), reason: 'предиката нет вовсе');
      final body = helper.substring(at, at + 700);
      expect(body, contains('withoutMissingApps('),
          reason: 'иначе пропавшие пути снова сделают план «непустым»');
      expect(body, contains('!cleaned.isEmpty'),
          reason: 'решение обязано опираться на пустоту ОЧИЩЕННОГО плана');
    });
  });
}
