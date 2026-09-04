import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/exit_health.dart';

/// СТОРОЖ НА КАЖДЫЙ ВЫХОД, А НЕ ТОЛЬКО НА ОСНОВНОЙ ТУННЕЛЬ.
///
/// ⚠️ ЗАЧЕМ. Сторож канала щупает ОДИН порт — основной прокси (10809). Если
/// умрёт выход в Эстонию, к которому привязано правило по сайту, не заметит
/// никто: ни строки в журнале, ни переподключения — правило просто перестанет
/// работать, а человек будет думать, что сайт лёг сам. Владелец 02.09.2026:
/// «Германия наебнулась, а параллельный сайт на Эстонии?» — вот про это.
///
/// Здесь только логика счёта: сама проба (Clash API sing-box, `/proxies/<tag>/
/// delay`) подменяется, таймер не крутится — тикаем руками.
void main() {
  test('три промаха подряд → выход объявлен мёртвым РОВНО ОДИН РАЗ', () async {
    final down = <String>[];
    final h = ExitHealth(
      tags: const ['exit-a'],
      probe: (_) async => false,
      failuresToDeclareDown: 3,
    );
    h.start(onExitDown: (tag) async => down.add(tag));

    await h.tick();
    await h.tick();
    expect(down, isEmpty, reason: 'два промаха — ещё не приговор');
    await h.tick();
    expect(down, ['exit-a']);
    await h.tick();
    await h.tick();
    expect(down, ['exit-a'],
        reason: 'мёртвый выход не должен долбить уведомлениями каждый такт');
  });

  test('один промах не считается: сброс на первом же ответе', () async {
    var answers = [false, true, false, false, true];
    final down = <String>[];
    final h = ExitHealth(
      tags: const ['exit-a'],
      probe: (_) async => answers.removeAt(0),
      failuresToDeclareDown: 3,
    );
    h.start(onExitDown: (tag) async => down.add(tag));
    for (var i = 0; i < 5; i++) {
      await h.tick();
    }
    expect(down, isEmpty,
        reason: 'ни разу не было трёх промахов подряд');
  });

  test('выходы считаются НЕЗАВИСИМО: смерть одного не трогает другой',
      () async {
    final down = <String>[];
    final h = ExitHealth(
      tags: const ['exit-de', 'exit-ee'],
      probe: (tag) async => tag == 'exit-ee',
      failuresToDeclareDown: 3,
    );
    h.start(onExitDown: (tag) async => down.add(tag));
    for (var i = 0; i < 4; i++) {
      await h.tick();
    }
    expect(down, ['exit-de']);
  });

  test('восстановление сообщается один раз и снова вооружает приговор',
      () async {
    var alive = false;
    final down = <String>[];
    final up = <String>[];
    final h = ExitHealth(
      tags: const ['exit-a'],
      probe: (_) async => alive,
      failuresToDeclareDown: 2,
    );
    h.start(
      onExitDown: (tag) async => down.add(tag),
      onExitRecovered: (tag, missed) => up.add('$tag:$missed'),
    );
    await h.tick();
    await h.tick();
    expect(down, ['exit-a']);

    alive = true;
    await h.tick();
    expect(up, ['exit-a:2'], reason: 'сколько промахов было — полезно журналу');
    await h.tick();
    expect(up, hasLength(1), reason: 'живой выход не «восстанавливается» каждый такт');

    alive = false;
    await h.tick();
    await h.tick();
    expect(down, ['exit-a', 'exit-a'],
        reason: 'после восстановления новая смерть обязана быть замечена');
  });

  test('отменённый сторож не тикает и не зовёт колбэки', () async {
    var probes = 0;
    final h = ExitHealth(
      tags: const ['exit-a'],
      probe: (_) async {
        probes++;
        return false;
      },
      failuresToDeclareDown: 1,
    );
    final down = <String>[];
    h.start(onExitDown: (tag) async => down.add(tag), aborted: () => true);
    await h.tick();
    expect(probes, 0);
    expect(down, isEmpty);
  });

  test('без выходов сторож не вооружается вовсе', () {
    final h = ExitHealth(tags: const [], probe: (_) async => true);
    expect(h.isArmed, isFalse);
    h.start(onExitDown: (_) async {});
    expect(h.isArmed, isFalse, reason: 'тикать не по чему');
  });

/// ПРОМАХ ПРИ МЁРТВОМ ОСНОВНОМ КАНАЛЕ НИЧЕГО НЕ ГОВОРИТ О ВЫХОДЕ.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА: «Это блять вообще что, у меня НЕТ таких правил» —
/// десяток уведомлений о мёртвых выходах подряд. Один источник спама уже
/// закрыт (выходы, поднятые только ради портов локального API, молчат).
/// Второй — здесь: выходы живут ВНУТРИ основного туннеля, и когда падает он,
/// не отвечает ни один из них. Сторож честно считает промахи и через три такта
/// объявляет мёртвыми ВСЕ разом — хотя ни один из них не сломан.
///
/// ⚠️ ПОЧЕМУ НЕ ГОДИТСЯ ПРАВИЛО «МОЛЧАТЬ, ЕСЛИ УМЕРЛИ ВСЕ». Оно уже есть и
/// решает другую задачу — не слать десять заметок вместо одной. Но счётчики при
/// этом всё равно накручиваются, выходы остаются помеченными мёртвыми, и после
/// восстановления канала интерфейс продолжает врать, пока не пройдёт ещё цикл
/// проб. Промах надо не подавлять на выходе, а НЕ ЗАСЧИТЫВАТЬ.

  group('⚠️ Основной канал мёртв — промахи выходов не считаются', () {
    test('при мёртвом канале приговора нет, сколько ни тикай', () async {
      final down = <String>[];
      var alive = false;
      final h = ExitHealth(
        tags: const ['exit-aaa', 'exit-bbb'],
        probe: (_) async => false,
        mainChannelAlive: () => alive,
      );
      h.start(onExitDown: (t) async => down.add(t));
      for (var i = 0; i < 5; i++) {
        await h.tick();
      }
      expect(down, isEmpty,
          reason: 'выходы объявлены мёртвыми из-за падения ОБЩЕГО туннеля');
      expect(h.downTags, isEmpty);
      h.stop();
    });

    test('счётчик не обнуляется, а замирает', () async {
      // ⚠️ Обнулять было бы отдельным дефектом: выход, который действительно
      // умер, получал бы прощение на каждом мигании основного канала и не был
      // бы объявлен мёртвым НИКОГДА.
      final down = <String>[];
      var alive = true;
      final h = ExitHealth(
        tags: const ['exit-aaa'],
        probe: (_) async => false,
        mainChannelAlive: () => alive,
        failuresToDeclareDown: 3,
      );
      h.start(onExitDown: (t) async => down.add(t));
      await h.tick();
      await h.tick(); // два промаха при живом канале
      alive = false;
      for (var i = 0; i < 4; i++) {
        await h.tick(); // канал лёг — эти не считаются
      }
      expect(down, isEmpty, reason: 'третий промах засчитан при мёртвом канале');
      alive = true;
      await h.tick(); // вот он, настоящий третий
      expect(down, ['exit-aaa']);
      h.stop();
    });

    test('без указания проверки канала ведёт себя как раньше', () async {
      // Обратная совместимость: параметр необязателен, и вторая платформа,
      // которая его не передаёт, не должна молча перестать сторожить.
      final down = <String>[];
      final h = ExitHealth(tags: const ['exit-aaa'], probe: (_) async => false);
      h.start(onExitDown: (t) async => down.add(t));
      for (var i = 0; i < 3; i++) {
        await h.tick();
      }
      expect(down, ['exit-aaa']);
      h.stop();
    });
  });

  group('⚠️ Такты не накладываются и гейт спрашивается на каждом выходе', () {
    test('пока идёт проход, второй такт не начинается', () async {
      // `Timer.periodic` не ждёт асинхронный обработчик, а проход по 41
      // выходу с пятисекундным таймаутом длится дольше интервала в 60 с.
      // Без флага занятости в воздухе оказывались три-четыре прохода разом,
      // и КАЖДЫЙ прибавлял свой промах: приговор приходил за один реальный
      // цикл вместо трёх, а человек получал пачку заметок.
      var inFlight = 0;
      var peak = 0;
      final h = ExitHealth(
        tags: const ['exit-a', 'exit-b'],
        probe: (_) async {
          inFlight++;
          if (inFlight > peak) peak = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          inFlight--;
          return true;
        },
      );
      h.start(onExitDown: (_) async {});
      // Три такта подряд, не дожидаясь друг друга, — как это делает таймер.
      final all = Future.wait([h.tick(), h.tick(), h.tick()]);
      await all;
      expect(peak, 1,
          reason: 'проходы наложились — промахи будут расти кратно');
      h.stop();
    });

    test('⚠️ канал умер в СЕРЕДИНЕ прохода — остаток не засчитывается', () async {
      // Проход длится минуты, и канал успевает умереть внутри него. Гейт,
      // спрошенный один раз на входе, пропускал бы промахи всем оставшимся
      // выходам уже после смерти канала — мимо той самой защиты, ради
      // которой он и заводился.
      var alive = true;
      var probed = 0;
      final h = ExitHealth(
        tags: const ['a', 'b', 'c', 'd'],
        probe: (_) async {
          probed++;
          if (probed == 2) alive = false; // канал лёг после второго выхода
          return false;
        },
        mainChannelAlive: () => alive,
        failuresToDeclareDown: 1,
      );
      final down = <String>[];
      h.start(onExitDown: (t) async => down.add(t));
      await h.tick();
      expect(probed, 2, reason: 'после смерти канала проход обязан оборваться');
      expect(down, ['a', 'b'],
          reason: 'выходы c и d приговорены уже при мёртвом канале');
      h.stop();
    });
  });
}
