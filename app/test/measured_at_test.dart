import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/measured_at.dart';
import 'package:silentgate/ui/widgets/ping_chip.dart';

/// «Когда была проверка» — одинаково у пинга и у скорости.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА (1.4.3, со свежей сборки): «у замера скорости в
/// подсказке видно, КОГДА была проверка, а у пинга — только время суток».
/// Обе подсказки звали общий метод, но сам метод отвечал по-разному: замеру
/// сегодняшнего дня он давал голое «14:05», вчерашнему — дату со временем.
/// Так и выходило, что рядом стоят два ответа на разные вопросы.
///
/// Здесь стережётся ровно это: (1) свежий замер описывается ОТНОСИТЕЛЬНО
/// («5 минут назад»), давний — ДАТОЙ, и голого времени суток не бывает вовсе;
/// (2) обе плашки берут строку из одной функции, то есть разойтись не могут.
void main() {
  final now = DateTime(2026, 8, 14, 14, 5);

  group('momentAge: пороги, а не «на глаз»', () {
    test('меньше минуты — «только что»', () {
      expect(momentAge(now.subtract(const Duration(seconds: 1)), now),
          const MomentAge(MomentKind.justNow));
      expect(momentAge(now.subtract(const Duration(seconds: 59)), now),
          const MomentAge(MomentKind.justNow));
    });

    test('минуты — от ровной минуты до 59', () {
      expect(momentAge(now.subtract(const Duration(minutes: 1)), now),
          const MomentAge(MomentKind.minutesAgo, 1));
      expect(momentAge(now.subtract(const Duration(minutes: 59)), now),
          const MomentAge(MomentKind.minutesAgo, 59));
    });

    test('часы — от часа до порога относительного показа', () {
      expect(momentAge(now.subtract(const Duration(minutes: 60)), now),
          const MomentAge(MomentKind.hoursAgo, 1));
      expect(
          momentAge(
              now.subtract(kMomentRelativeLimit - const Duration(minutes: 1)),
              now),
          const MomentAge(MomentKind.hoursAgo, 11));
    });

    test('за порогом — дата, а не «11 часов назад»', () {
      expect(momentAge(now.subtract(kMomentRelativeLimit), now),
          const MomentAge(MomentKind.absolute));
      expect(momentAge(now.subtract(const Duration(days: 3)), now),
          const MomentAge(MomentKind.absolute));
    });

    test('⚠️ момент из будущего не даёт «−3 минуты назад»', () {
      // Бывает без всяких ошибок в коде: поправка часов по сети, замер за долю
      // секунды до сравнения. Отрицательное число читается как поломка.
      expect(momentAge(now.add(const Duration(minutes: 3)), now),
          const MomentAge(MomentKind.justNow));
    });
  });

  group('Подсказки пинга и скорости', () {
    /// Обе плашки на одном экране с ОДНИМ И ТЕМ ЖЕ моментом замера.
    Future<({String ping, String speed})> tips(
        WidgetTester tester, DateTime at) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(children: [
            PingChip(
                result: PingResult(
                    outcome: PingOutcome.ok,
                    latencyMs: 42,
                    verification: PingVerification.passed,
                    measuredAt: at)),
            // Пинг плашке скорости больше не нужен: она существует ТОЛЬКО там,
            // где замер реально был (прочерк «—» у непроверенных серверов
            // отменён владельцем 18.08.2026).
            SpeedChip(speed: ServerSpeed(mbps: 24.4, measuredAt: at)),
          ]),
        ),
      ));
      await tester.pump();
      String tipOf(Type chip) => tester
              .widget<Tooltip>(find.descendant(
                  of: find.byType(chip), matching: find.byType(Tooltip)))
              .message ??
          '';
      return (ping: tipOf(PingChip), speed: tipOf(SpeedChip));
    }

    /// Хвост подсказки после подписи «Замер: » — то самое место, где пинг и
    /// скорость расходились.
    String moment(String tip) {
      final line = tip.split('\n').firstWhere((s) => s.startsWith('Замер: '),
          orElse: () => '');
      return line.replaceFirst('Замер: ', '');
    }

    testWidgets('свежий замер — «5 минут назад» У ОБЕИХ, а не время суток',
        (tester) async {
      final t = await tips(
          tester, DateTime.now().subtract(const Duration(minutes: 5)));
      expect(moment(t.ping), '5 минут назад',
          reason: 'ЗДЕСЬ БЫЛ ДЕФЕКТ: пинг показывал «14:05» — «во сколько» '
              'вместо «когда»');
      expect(moment(t.speed), '5 минут назад');
      expect(moment(t.ping), moment(t.speed),
          reason: 'две плашки рядом обязаны говорить об одном одинаково');
    });

    testWidgets('замер минутной свежести — «только что»', (tester) async {
      final t = await tips(
          tester, DateTime.now().subtract(const Duration(seconds: 20)));
      expect(moment(t.ping), 'только что');
      expect(moment(t.speed), 'только что');
    });

    testWidgets('давний замер — с ДАТОЙ, и тоже у обеих одинаково',
        (tester) async {
      final at = DateTime.now().subtract(const Duration(days: 2));
      final t = await tips(tester, at);
      expect(moment(t.ping), moment(t.speed));
      expect(moment(t.ping), contains('${at.year}'),
          reason: 'без даты «14:05» двухдневной давности читается как свежий '
              'замер — ровно то, ради чего строку и заводили');
      expect(moment(t.ping), isNot(contains('назад')));
    });

    testWidgets('замера не было — строки времени нет вовсе', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: PingChip(
              result: PingResult(
                  outcome: PingOutcome.ok,
                  latencyMs: 42,
                  verification: PingVerification.passed)),
        ),
      ));
      await tester.pump();
      final tip = tester
              .widget<Tooltip>(find.descendant(
                  of: find.byType(PingChip), matching: find.byType(Tooltip)))
              .message ??
          '';
      expect(tip, isNot(contains('Замер')));
    });
  });

  group('Формат берётся из одной функции', () {
    testWidgets('measuredAtLine переводит UTC в местное время сам',
        (tester) async {
      // ⚠️ `toLocal()` живёт ВНУТРИ общей функции: на диске моменты лежат в
      // UTC, и забытый перевод сдвинул бы подсказку на часовой пояс. Проверяем
      // на давнем моменте — там в строке есть время суток.
      late String line;
      final utc = DateTime.utc(2026, 8, 1, 9, 30);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(builder: (context) {
            line = measuredAtLine(context, utc);
            final local = utc.toLocal();
            expect(
                line,
                contains(MaterialLocalizations.of(context)
                    .formatShortDate(local)),
                reason: 'дата обязана быть местной, а не UTC');
            return const SizedBox.shrink();
          }),
        ),
      ));
      await tester.pump();
      expect(line, startsWith('Замер: '));
    });
  });
}
