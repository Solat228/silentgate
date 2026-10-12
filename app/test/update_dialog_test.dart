import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/state/app_update_controller.dart';
import 'package:silentgate/ui/widgets/update_dialog.dart';

import 'helpers/update_ui_harness.dart';

/// ОКНО «ДОСТУПНО ОБНОВЛЕНИЕ».
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ (унаследовано от прежнего окна «Что нового»).
/// Владелец прислал снимок 19.08.2026: описание релиза вывалилось на весь
/// экран сырым markdown, без кнопки закрытия. Вёрстку никто не смотрел на
/// узком экране — поэтому окно строится на ОДИННАДЦАТИ настоящих разрешениях,
/// и на каждом проверяется одно: ничего не переполнилось, кнопки видны.
///
/// И новое в 1.14.0: кнопки окна теперь не открывают ссылку, а ЗОВУТ
/// контроллер — «Обновить» качает и ставит, «Позже» и «Пропустить» —
/// разные решения. Контроллер здесь настоящий (см. [UpdateUiHarness]),
/// поэтому проверяется то, что реально произойдёт, а не вызов заглушки.
void main() {
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
    // ⚠️ Альбомная ориентация телефона — самый тесный случай по ВЫСОТЕ.
    'телефон, альбомная': Size(800, 360),
  };

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

  late UpdateUiHarness h;

  setUp(() {
    h = UpdateUiHarness.create();
  });

  tearDown(() => h.dispose());

  /// Довести контроллер до «доступна версия» (режим «спрашивать»).
  Future<AppRelease> offer(WidgetTester t,
      {String version = '1.14.1', String notes = realNotes}) async {
    final r = h.publish(version, notes: notes);
    h.checkResult = () => UpdateCheckResult.available(r);
    await h.controller.checkNow();
    expect(h.controller.phase, UpdatePhase.available);
    return r;
  }

  /// Экран с кнопкой, открывающей окно, — как на главном.
  Widget opener({LinkOnlyReason? reason}) => Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showUpdateDialog(context, h.controller, linkReason: reason),
              child: const Text('открыть'),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester t, {LinkOnlyReason? reason, Size? size}) async {
    final s = size ?? const Size(420, 900);
    t.view.physicalSize = s;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(h.wrap(opener(reason: reason)));
    await t.tap(find.text('открыть'));
    await t.pumpAndSettle();
  }

  group('⚠️ Вёрстка на настоящих телефонах', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} — ничего не переполняется, кнопки на экране',
          (t) async {
        await offer(t);
        h.vpnActive = true; // самый длинный вариант: с предупреждением о VPN
        await open(t, size: entry.value);

        expect(t.takeException(), isNull,
            reason: '${entry.key}: вёрстка переполнилась');
        for (final key in const [
          'updateDialogSkip',
          'updateDialogLater',
          'updateDialogInstall',
        ]) {
          final f = find.byKey(Key(key));
          expect(f, findsOneWidget, reason: '${entry.key}: нет $key');
          final box = t.getRect(f);
          expect(box.bottom, lessThanOrEqualTo(entry.value.height),
              reason: '${entry.key}: $key за нижней границей');
          expect(box.right, lessThanOrEqualTo(entry.value.width),
              reason: '${entry.key}: $key за правой границей');
        }
      });
    }
  });

  group('⚠️ Окно облегает содержимое (живой прогон 24.09.2026)', () {
    // Сам `AlertDialog` занимает весь маршрут; видимое окно — его Material.
    Rect dialogRect(WidgetTester t) => t.getRect(find
        .descendant(of: find.byType(AlertDialog), matching: find.byType(Material))
        .first);

    const shortNotes = '## Стенд\n- Одна строка.\n- Вторая строка.';

    testWidgets('короткое описание: окно не растянуто на весь телефон',
        (t) async {
      await offer(t, notes: shortNotes);
      await open(t, size: const Size(411, 890));
      final dialog = dialogRect(t);
      expect(dialog.height, lessThan(890 * 0.6),
          reason: 'две строки описания растягивали окно пустотой до кнопок');
      expect(t.takeException(), isNull);
    });

    testWidgets('длинное описание упирается в потолок и прокручивается',
        (t) async {
      final long = List.generate(80, (i) => '- строка $i').join('\n');
      await offer(t, notes: long);
      await open(t, size: const Size(411, 890));
      expect(t.takeException(), isNull);
      final install = t.getRect(find.byKey(const Key('updateDialogInstall')));
      expect(install.bottom, lessThanOrEqualTo(890));
      final lastLine = t.getRect(find.text('•  строка 79'));
      expect(lastLine.top, greaterThan(dialogRect(t).bottom),
          reason: 'конец списка — за прокруткой, а не за краем экрана');
    });

    testWidgets(
        'телефон: «Обновить» во всю ширину сверху, «Пропустить» и «Позже» '
        'одним рядом под ней', (t) async {
      await offer(t, notes: shortNotes);
      await open(t, size: const Size(360, 800));
      final install = t.getRect(find.byKey(const Key('updateDialogInstall')));
      final skip = t.getRect(find.byKey(const Key('updateDialogSkip')));
      final later = t.getRect(find.byKey(const Key('updateDialogLater')));
      expect(install.bottom, lessThanOrEqualTo(skip.top));
      expect(skip.center.dy, closeTo(later.center.dy, 1),
          reason: 'второстепенные — в один ряд, а не столбиком');
      expect(install.width, greaterThan(skip.width + later.width),
          reason: 'главная кнопка — во всю ширину');
    });

    testWidgets('десктоп: три кнопки одним рядом, главная последней',
        (t) async {
      await offer(t, notes: shortNotes);
      await open(t, size: const Size(1040, 820));
      final install = t.getRect(find.byKey(const Key('updateDialogInstall')));
      final skip = t.getRect(find.byKey(const Key('updateDialogSkip')));
      final later = t.getRect(find.byKey(const Key('updateDialogLater')));
      expect(skip.center.dy, closeTo(install.center.dy, 1));
      expect(later.center.dy, closeTo(install.center.dy, 1));
      expect(install.left, greaterThan(later.left));
    });
  });

  group('Текст читаемый, а не сырая разметка', () {
    testWidgets('⚠️ звёздочек и решёток на экране нет', (t) async {
      await offer(t);
      await open(t, size: const Size(360, 800));
      final texts = [
        ...t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
        ...t
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((w) => w.data ?? ''),
      ].join(' ');
      expect(texts.contains('**'), isFalse, reason: 'осталась разметка жирного');
      expect(texts.contains('##'), isFalse, reason: 'остался заголовок markdown');
      expect(texts.contains(']('), isFalse, reason: 'осталась ссылка markdown');
    });

    test('⚠️ разбор разметки: заголовки, списки, ссылки', () {
      final lines = UpdateDialog.formatNotes(realNotes);
      expect(lines.any((l) => l.heading && l.text.contains('1.9.1')), isTrue);
      expect(lines.any((l) => l.bullet), isTrue);
      // Ссылка превращается в свой ТЕКСТ, а не в адрес.
      expect(lines.any((l) => l.text.contains('BACKLOG')), isTrue);
      expect(lines.any((l) => l.text.contains('docs/BACKLOG.md')), isFalse);
      expect(lines.any((l) => l.text.trim() == '---'), isFalse);
    });

    test('пустое описание не роняет разбор', () {
      expect(UpdateDialog.formatNotes(''), isEmpty);
      expect(UpdateDialog.formatNotes('\n\n---\n\n'), isEmpty);
    });
  });

  group('Кнопки зовут контроллер', () {
    testWidgets('«Пропустить эту версию» записывает версию и закрывает окно',
        (t) async {
      await offer(t);
      await open(t);
      await t.tap(find.byKey(const Key('updateDialogSkip')));
      await t.pumpAndSettle();

      expect(h.settings.settings.appUpdateSkippedVersion, '1.14.1');
      expect(h.controller.offerIsSkipped, isTrue);
      expect(find.byKey(const Key('updateDialogSkip')), findsNothing);
      expect(h.installer.launches, isEmpty, reason: 'пропуск — не установка');
    });

    testWidgets('«Позже» только откладывает: ничего не качается и не пишется',
        (t) async {
      await offer(t);
      await open(t);
      await t.tap(find.byKey(const Key('updateDialogLater')));
      await t.pumpAndSettle();

      expect(h.controller.postponed, isTrue);
      expect(h.settings.settings.appUpdateSkippedVersion, isNull,
          reason: '«Позже» — не «пропустить»: версию не запоминаем');
      expect(h.controller.phase, UpdatePhase.available);
      expect(h.installer.launches, isEmpty);
    });

    testWidgets('«Обновить» без VPN: скачать, проверить подпись, поставить',
        (t) async {
      await offer(t);
      await open(t);
      expect(find.byKey(const Key('updateDialogVpnWarning')), findsNothing,
          reason: 'предупреждение только при живом VPN');
      await t.tap(find.byKey(const Key('updateDialogInstall')));
      await t.pumpAndSettle();

      expect(h.installer.launches, hasLength(1));
      expect(h.installer.launches.single.version, '1.14.1');
      expect(h.installer.launches.single.forceQuit, isFalse);
      expect(h.installer.launches.single.allowDowngrade, isFalse);
    });

    testWidgets(
        '⚠️ живой VPN: предупреждение на экране, и только тогда forceQuit',
        (t) async {
      await offer(t);
      h.vpnActive = true;
      await open(t);
      expect(find.byKey(const Key('updateDialogVpnWarning')), findsOneWidget);
      await t.tap(find.byKey(const Key('updateDialogInstall')));
      await t.pumpAndSettle();

      expect(h.installer.launches, hasLength(1));
      expect(h.installer.launches.single.forceQuit, isTrue,
          reason: 'человек видел предупреждение — установщику можно '
              'закрыть приложение вместе с VPN');
    });

    testWidgets('ставить самим нельзя: вместо «Обновить» — причина и страница',
        (t) async {
      await offer(t);
      await open(t, reason: LinkOnlyReason.portable);
      expect(find.byKey(const Key('updateDialogInstall')), findsNothing,
          reason: 'кнопка, которая ничего не сможет, — обманка');
      expect(find.byKey(const Key('updateDialogOpenPage')), findsOneWidget);
      expect(find.byKey(const Key('updateDialogLinkReason')), findsOneWidget);
    });
  });
}
