import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/update_notes_dialog.dart';

/// ОКНО «ЧТО НОВОГО» ОБЯЗАНО ЧИТАТЬСЯ И ЗАКРЫВАТЬСЯ НА ЛЮБОМ ТЕЛЕФОНЕ.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. Владелец прислал снимок 19.08.2026: описание релиза
/// вывалилось на весь экран сырым markdown — со звёздочками, дефисами и
/// заголовками, — без кнопки закрытия и без возможности отказаться от показа.
/// Причина простая: тело релиза с GitHub (это весь раздел changelog, тысячи
/// символов) уходило в ТОСТ целиком.
///
/// ⚠️ И ГЛАВНЫЙ УРОК НЕ В ЭТОМ. Вёрстку никто не смотрел на узком экране —
/// проверяли на десктопе, где места хватает. Поэтому здесь окно строится на
/// ДЕСЯТИ настоящих разрешениях, от самого тесного iPhone SE до планшета, и на
/// каждом проверяется одно и то же: ничего не переполнилось, кнопка закрытия
/// видна и нажимаема.
void main() {
  /// Настоящие разрешения (логические точки, портрет), самые ходовые.
  const screens = <String, Size>{
    'iPhone SE 1 (самый тесный)': Size(320, 568),
    'iPhone SE 2/3, 8': Size(375, 667),
    'Android 360×640': Size(360, 640),
    'Android 360×800 (самый ходовой)': Size(360, 800),
    'iPhone 14/15': Size(390, 844),
    'Pixel 7/8': Size(393, 873),
    'Samsung S23': Size(412, 915),
    'iPhone 11/XR': Size(414, 896),
    'iPhone Pro Max': Size(428, 926),
    'планшет, портрет': Size(800, 1280),
    // ⚠️ Альбомная ориентация телефона — самый тесный случай по ВЫСОТЕ, и
    // именно на ней кнопки уезжают за край, если высота диалога задана числом.
    'телефон, альбомная': Size(800, 360),
  };

  /// Настоящий текст релиза — с той самой разметкой, что была на снимке.
  const realNotes = '''
## [1.9.1] — 2026-08-19

**Журнал ядра перестал уничтожаться восстановлением.** PATCH.

### Исправлено

- **⚠️ ГЛАВНОЕ: `singbox.log` перезаписывался при каждом перезапуске ядра.**
  Разбор любого обрыва был физически невозможен: восстановление уничтожало
  свидетельство аварии.
- **Уведомление о заблокированном сайте жило меньше секунды.** Счётчик трафика
  тикает раз в секунду и безусловно возвращал «Подключено».

---

### Известное ограничение

- Настоящий kill switch в эту версию не вошёл. Подробности — [BACKLOG](docs/BACKLOG.md).
''';

  Widget host(Size size, {String notes = realNotes}) => MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ru'),
          home: Scaffold(
            body: UpdateNotesDialog(
              version: '1.9.1',
              notes: notes,
              onDownload: () {},
              onNeverShow: () {},
            ),
          ),
        ),
      );

  group('⚠️ Вёрстка на десяти настоящих телефонах', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} — ничего не переполняется, закрыть можно',
          (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);

        await t.pumpWidget(host(entry.value));
        await t.pumpAndSettle();

        // ⚠️ ГЛАВНОЕ: переполнение вёрстки Flutter сообщает исключением, и без
        // этой проверки тест зеленел бы на экране, где текст уехал за край.
        expect(t.takeException(), isNull,
            reason: '${entry.key}: вёрстка переполнилась');

        final close = find.byKey(const Key('updateNotesClose'));
        expect(close, findsOneWidget, reason: '${entry.key}: нет кнопки закрытия');

        // Кнопка обязана быть В ПРЕДЕЛАХ экрана: найденный виджет ещё не значит
        // видимый — ровно так кнопки и уезжали за границу.
        final box = t.getRect(close);
        expect(box.bottom, lessThanOrEqualTo(entry.value.height),
            reason: '${entry.key}: кнопка закрытия за нижней границей');
        expect(box.right, lessThanOrEqualTo(entry.value.width),
            reason: '${entry.key}: кнопка закрытия за правой границей');
      });
    }
  });

  group('Текст читаемый, а не сырая разметка', () {
    testWidgets('⚠️ звёздочек и решёток на экране нет', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(const Size(360, 800)));
      await t.pumpAndSettle();

      // Собираем весь видимый текст и ищем следы markdown.
      final texts = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join(' ');
      expect(texts.contains('**'), isFalse, reason: 'осталась разметка жирного');
      expect(texts.contains('##'), isFalse, reason: 'остался заголовок markdown');
      expect(texts.contains(']('), isFalse, reason: 'осталась ссылка markdown');
    });

    test('⚠️ разбор разметки: заголовки, списки, ссылки', () {
      final lines = UpdateNotesDialog.formatNotes(realNotes);

      expect(lines.any((l) => l.heading && l.text.contains('1.9.1')), isTrue,
          reason: 'заголовок версии обязан остаться заголовком');
      expect(lines.any((l) => l.bullet), isTrue,
          reason: 'пункты списка обязаны остаться пунктами');
      // Ссылка превращается в свой ТЕКСТ, а не в адрес: адрес человеку не
      // нужен, а строку он растягивает так, что она уезжает за край.
      expect(lines.any((l) => l.text.contains('BACKLOG')), isTrue);
      expect(lines.any((l) => l.text.contains('docs/BACKLOG.md')), isFalse);
      // Горизонтальные линейки выброшены целиком.
      expect(lines.any((l) => l.text.trim() == '---'), isFalse);
    });

    test('пустое описание не роняет разбор', () {
      expect(UpdateNotesDialog.formatNotes(''), isEmpty);
      expect(UpdateNotesDialog.formatNotes('\n\n---\n\n'), isEmpty);
    });
  });

  group('Кнопки делают то, что обещают', () {
    testWidgets('⚠️ «Больше не показывать» гасит окно и закрывает его',
        (t) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      var hidden = false;
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => UpdateNotesDialog(
                    version: '1.9.1',
                    notes: realNotes,
                    onNeverShow: () => hidden = true,
                  ),
                ),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('открыть'));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('updateNotesNeverShow')));
      await t.pumpAndSettle();

      expect(hidden, isTrue, reason: 'настройка обязана взводиться');
      expect(find.byKey(const Key('updateNotesClose')), findsNothing,
          reason: 'окно обязано закрыться вместе с нажатием');
    });

    testWidgets('кнопка «Скачать» не рисуется, когда ссылки нет', (t) async {
      t.view.physicalSize = const Size(400, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ru'),
        home: const Scaffold(
          body: UpdateNotesDialog(version: '1.9.1', notes: 'что-то'),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('updateNotesDownload')), findsNothing,
          reason: 'кнопка, ведущая никуда, хуже отсутствующей');
      expect(find.byKey(const Key('updateNotesClose')), findsOneWidget);
    });
  });
}
