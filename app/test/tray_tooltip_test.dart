import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/app_info.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/platform/tray_window.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/home_screen.dart';

/// Две жалобы владельца, ради которых это написано.
///
/// 1. Подсказка трея показывала четыре строки — сервер, скорость и НАКОПЛЕННЫЙ
///    за сессию трафик. Просьба: «просто в 2 строчки инфа о сервере и текущая
///    скорость». Плюс невидимая мина Windows: `szTip` в `NOTIFYICONDATA` —
///    это `WCHAR[128]`, и всё, что длиннее 127 символов, оболочка отрезает
///    МОЛЧА. Длинное имя сервера съедало бы строку со скоростью целиком.
/// 2. Плашка с именем активного сервера над кнопкой Connect «поплыла»:
///    содержимое не помещалось и наезжало на колонки проверок сервисов.
void main() {
  /// Снимок с РАЗНЫМИ скоростью и накопленным: только так тест отличает одно
  /// от другого. Накопленное — 7 ГБ, скорость — мегабайты и килобайты.
  const stats = TrafficStats(
    uplinkBytes: 3 * 1024 * 1024 * 1024,
    downlinkBytes: 7 * 1024 * 1024 * 1024,
    uplinkSpeed: 300 * 1024,
    downlinkSpeed: 1536 * 1024,
  );

  group('Подсказка трея — ровно две строки', () {
    test('сервер и скорость, и больше ничего', () {
      final tip = TrayWindow.composeTooltip(
          server: 'Germany #3', speed: TrayWindow.speedLine(stats));
      final lines = tip.split('\n');
      expect(lines, hasLength(2),
          reason: 'владелец просил ДВЕ строки: сервер и текущая скорость');
      expect(lines.first, contains('Germany #3'));
      expect(lines.first, contains(AppInfo.name),
          reason: 'по подсказке должно быть понятно, чьё это окно в трее');
      expect(lines[1], contains('1.5 MB/s'));
      expect(lines[1], contains('300 KB/s'));
    });

    test('накопленного за сессию в подсказке НЕТ', () {
      final tip = TrayWindow.composeTooltip(
          server: 'Germany #3', speed: TrayWindow.speedLine(stats));
      expect(tip, isNot(contains(TrafficStats.formatBytes(stats.downlinkBytes))),
          reason: 'скачано за сессию видно в приложении; в подсказке это '
              'третья и четвёртая строки, которых быть не должно');
      expect(tip, isNot(contains(TrafficStats.formatBytes(stats.uplinkBytes))));
    });

    test('длинное имя сервера не выталкивает скорость за 127 символов', () {
      final speed = TrayWindow.speedLine(stats);
      final tip = TrayWindow.composeTooltip(
          server: 'Нидерланды Амстердам премиум канал для просмотра видео '
              'и работы, узел номер двадцать семь, резервный',
          speed: speed);
      expect(tip.length, lessThanOrEqualTo(TrayWindow.tooltipLimit),
          reason: 'Windows режет szTip молча — если не уложились, пользователь '
              'просто не увидит остаток и не узнает почему');
      final lines = tip.split('\n');
      expect(lines, hasLength(2));
      expect(lines[1], speed,
          reason: 'резать надо ИМЯ: скорость коротка и нужна целиком, '
              'половина числа хуже недочитанного имени');
      expect(lines.first, endsWith('…'),
          reason: 'обрезали — так и покажем, а не оборвём на полуслове');
    });

    test('предел выдержан на именах любой длины', () {
      final speed = TrayWindow.speedLine(stats);
      for (var n = 0; n < 220; n++) {
        final tip =
            TrayWindow.composeTooltip(server: 'x' * n, speed: speed);
        expect(tip.length, lessThanOrEqualTo(TrayWindow.tooltipLimit),
            reason: 'длина имени $n');
      }
    });

    test('обрезание не рвёт эмодзи и флаги пополам', () {
      final speed = TrayWindow.speedLine(stats);
      // Флаг — ЧЕТЫРЕ кодовых блока UTF-16 (две буквы-индикатора по паре
      // суррогатов). Рез в любом из трёх мест внутри него даёт либо
      // недопустимую строку, либо половину флага. Перебираем сдвиги, чтобы
      // граница реза прошла по каждому из них.
      for (var pad = 0; pad < 40; pad++) {
        final name = '${'a' * pad}${'🇩🇪🇳🇱🎬' * 12}';
        final tip = TrayWindow.composeTooltip(server: name, speed: speed);
        expect(_hasLoneSurrogate(tip), isFalse,
            reason: 'одинокий суррогат при сдвиге $pad: $tip');
        expect(_hasHalfFlag(tip), isFalse,
            reason: 'половина флага при сдвиге $pad: $tip');
      }
    });

    test('без соединения — просто имя приложения', () {
      expect(TrayWindow.composeTooltip(), AppInfo.name);
    });

    test('удержанный трафик перебивает сервер и скорость', () {
      final tip = TrayWindow.composeTooltip(
          server: 'Germany #3',
          speed: TrayWindow.speedLine(stats),
          blocked: 'соединение потеряно, трафик заблокирован');
      expect(tip.split('\n'), hasLength(1));
      expect(tip, contains('трафик заблокирован'));
      expect(tip.length, lessThanOrEqualTo(TrayWindow.tooltipLimit));
    });
  });

  group('Плашка активного сервера не наезжает на соседей', () {
    Widget host(Widget child) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: child)),
        );

    /// ⚠️ Размер задаётся ОКНУ, а не виджету: поверхность теста по умолчанию
    /// 800×600 зажала бы строку, и плашка «уместилась» бы по чужой причине.
    void setWindow(WidgetTester tester, double width) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.reset);
    }

    /// Та же раскладка, что на главном экране: кнопка посередине, по бокам —
    /// колонки проверок сервисов, которые плашка и закрывала собой.
    Future<void> pumpRow(WidgetTester tester, String? name) async {
      await tester.pumpWidget(host(Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Expanded(child: SizedBox(height: 120)),
          ActiveServerOverlay(
            name: name,
            child: const SizedBox(key: Key('btn'), width: 148, height: 148),
          ),
          const Expanded(child: SizedBox(height: 120)),
        ],
      )));
      await tester.pump();
    }

    testWidgets('длинное имя обрезается, а не растягивает плашку', (t) async {
      setWindow(t, 1040);
      await pumpRow(
          t,
          'Нидерланды Амстердам премиум канал для просмотра видео и работы, '
          'узел номер двадцать семь');
      expect(t.takeException(), isNull);

      final btn = t.getRect(find.byKey(const Key('btn')));
      final label = t.getRect(find.byType(ActiveServerLabel));
      const bleed = ActiveServerOverlay.bleed;
      expect(label.left, greaterThanOrEqualTo(btn.left - bleed - 0.5),
          reason: 'плашка вылезла влево на ${btn.left - label.left} px — '
              'ровно этим она и наезжала на левую колонку проверок');
      expect(label.right, lessThanOrEqualTo(btn.right + bleed + 0.5),
          reason: 'плашка вылезла вправо на ${label.right - btn.right} px');
      expect(label.width, lessThanOrEqualTo(ActiveServerLabel.maxWidth + 0.5));

      final para = t.renderObject<RenderParagraph>(find.descendant(
          of: find.byType(ActiveServerLabel), matching: find.byType(Text)));
      expect(para.didExceedMaxLines, isTrue,
          reason: 'имя не влезло — значит должно быть обрезано многоточием, '
              'а не выдавить плашку за её границы');
    });

    testWidgets('короткое имя не растягивается во всю ширину', (t) async {
      setWindow(t, 1040);
      await pumpRow(t, 'DE-1');
      final label = t.getRect(find.byType(ActiveServerLabel));
      expect(label.width, lessThan(120),
          reason: 'плашка обязана ужиматься по содержимому: иначе короткое имя '
              'болталось бы посреди пилюли во всю кнопку');
    });

    testWidgets('имя с флагом тоже укладывается', (t) async {
      setWindow(t, 1040);
      await pumpRow(t, '🇩🇪 Германия Франкфурт узел 12 премиум');
      expect(t.takeException(), isNull);
      final btn = t.getRect(find.byKey(const Key('btn')));
      final label = t.getRect(find.byType(ActiveServerLabel));
      expect(label.left,
          greaterThanOrEqualTo(btn.left - ActiveServerOverlay.bleed - 0.5));
      expect(label.right,
          lessThanOrEqualTo(btn.right + ActiveServerOverlay.bleed + 0.5));
    });

    testWidgets('без имени плашки нет вовсе', (t) async {
      setWindow(t, 1040);
      await pumpRow(t, null);
      expect(find.byType(ActiveServerLabel), findsNothing);
    });

    testWidgets('на узком экране плашка не выходит за края', (t) async {
      setWindow(t, 360);
      await pumpRow(t, 'Нидерланды Амстердам премиум узел двадцать семь');
      expect(t.takeException(), isNull);
      final label = t.getRect(find.byType(ActiveServerLabel));
      expect(label.left, greaterThanOrEqualTo(0));
      expect(label.right, lessThanOrEqualTo(360));
    });
  });
}

/// Строка содержит суррогат без пары — то есть символ, разрезанный пополам.
bool _hasLoneSurrogate(String s) {
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    final high = u >= 0xD800 && u <= 0xDBFF;
    final low = u >= 0xDC00 && u <= 0xDFFF;
    if (high) {
      if (i + 1 >= s.length) return true;
      final n = s.codeUnitAt(i + 1);
      if (n < 0xDC00 || n > 0xDFFF) return true;
      i++; // пара целая — пропускаем её низкую половину
    } else if (low) {
      return true;
    }
  }
  return false;
}

/// Нечётная цепочка букв-индикаторов = флаг, разрезанный пополам.
bool _hasHalfFlag(String s) {
  var run = 0;
  for (final r in s.runes) {
    if (r >= 0x1F1E6 && r <= 0x1F1FF) {
      run++;
    } else {
      if (run.isOdd) return true;
      run = 0;
    }
  }
  return run.isOdd;
}
