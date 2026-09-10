import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/network_recovery.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/settings_screen.dart';

/// ВОССТАНОВЛЕНИЕ СЕТИ: ДВА НАБОРА КОМАНД, ДВА ПРЕДУПРЕЖДЕНИЯ, ДВЕ КНОПКИ.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. `NetworkRecovery` запускает от имени администратора
/// команды, которые МЕНЯЮТ СЕТЬ МАШИНЫ. До 10.09.2026 кнопка была одна и
/// запускала их все разом — в том числе `ipconfig /release` (отпускает аренду
/// DHCP на ВСЕХ адаптерах, включая виртуальные коммутаторы Hyper-V: ровно этим
/// владелец дважды оставался без сети), `netsh int ip reset` (стирает
/// статические адреса и маршруты) и `netsh winsock reset` (ломает стороннее ПО
/// в стеке и требует перезагрузки).
///
/// Главный страж всего файла — тот, что проверяет ФИЗИЧЕСКОЕ ОТСУТСТВИЕ этой
/// тройки в мягком наборе. Всё остальное здесь — про то, что человека
/// предупредили и спросили.
///
/// Последнее — не паранойя: «написано и не вызывается» в этом проекте ловили
/// четырежды (связки провайдеров без `lazy: false`, гейт пинга на двух точках
/// входа из четырёх, порт «Прямо» из документации без инбаунда, кнопка
/// подбора). Поэтому страж нажимает НАСТОЯЩИЕ строки настроек и смотрит, дошло
/// ли дело до исполнителя и С КАКИМ набором.
///
/// ⚠️ Исполнитель подменён ([NetworkRecovery.runnerForTests]). Настоящий вызов
/// сбросил бы winsock и IP-стек той машины, где идёт прогон.
void main() {
  /// Мягкий набор — ЗАКРЫТЫЙ список, сверяется целиком и по порядку.
  ///
  /// ⚠️ ИМЕННО ЦЕЛИКОМ, А НЕ «СОДЕРЖИТ». Команда, дописанная сюда, выполнится
  /// по кнопке, чьё подтверждение обещает «ничего не стирается, перезагрузка не
  /// нужна». Тест на вхождение такую дописку проспал бы молча.
  const expectedSoft = <String>[
    'ipconfig /flushdns',
    'netsh winhttp reset proxy',
    'netsh interface ip delete arpcache',
    r'reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /f',
    r'reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /f',
  ];

  /// Полный набор — тоже закрытый список: мягкий целиком, следом добавка.
  const expectedFull = <String>[
    ...expectedSoft,
    'ipconfig /release',
    'ipconfig /renew',
    'netsh winsock reset',
    'netsh int ip reset',
  ];

  /// Опасные куски команд и слово, по которому их узнают в тексте
  /// подтверждения ПОЛНОГО сброса.
  ///
  /// Слова латинские, поэтому проверяются во ВСЕХ переводах: «winsock», «DHCP»,
  /// «Hyper-V», «VirtualBox» и «IP» на всех десяти языках пишутся одинаково, и
  /// подменять эту проверку на русский текст значило бы стеречь один язык из
  /// десяти.
  const dangerous = <String>[
    'ipconfig /release',
    'netsh winsock reset',
    'netsh int ip reset',
  ];

  /// «IP» как ОТДЕЛЬНОЕ слово.
  ///
  /// ⚠️ Границы обязательны в обе стороны. Без них «ip» находится внутри
  /// `ipconfig` (тогда страж на отсутствие в мягком тексте краснел бы зря) и
  /// внутри турецкого «ipucu» — то есть проверка молча зависела бы от языка.
  final ipWord = RegExp(r'(?<![a-zа-яё0-9])ip(?![a-zа-яё0-9])');

  group('состав наборов', () {
    test('мягкий набор непуст и совпадает с ожидаемым целиком', () {
      expect(NetworkRecovery.softCommands, isNotEmpty,
          reason: 'пустой список означает кнопку, которая ничего не делает');
      expect(NetworkRecovery.softCommands, expectedSoft,
          reason: 'состав МЯГКОГО набора изменился — убедитесь, что новая '
              'команда ничего не стирает и не требует перезагрузки, иначе ей '
              'место в полном сбросе');
    });

    test('полный набор непуст и совпадает с ожидаемым целиком', () {
      expect(NetworkRecovery.fullCommands, isNotEmpty);
      expect(NetworkRecovery.fullCommands, expectedFull,
          reason: 'состав ПОЛНОГО набора изменился — сверьте текст '
              'подтверждения: он обязан назвать поимённо всё, что будет стёрто');
    });

    test('⚠️ полный набор ВКЛЮЧАЕТ мягкий целиком и в том же порядке', () {
      // Кнопка полного сброса обещает «всё то же самое и сверх того». Стоит
      // спискам разъехаться (правку внесли в один) — и полный сброс начнёт
      // делать МЕНЬШЕ мягкого, оставаясь при этом опасным.
      expect(
          NetworkRecovery.fullCommands
              .take(NetworkRecovery.softCommands.length),
          NetworkRecovery.softCommands,
          reason: 'мягкий набор перестал быть началом полного — списки '
              'разъехались; полный обязан собираться ИЗ мягкого');
      for (final cmd in NetworkRecovery.softCommands) {
        expect(NetworkRecovery.fullCommands, contains(cmd));
      }
    });

    test('⚠️ ГЛАВНОЕ: опасных команд в мягком наборе нет физически', () {
      // Не «не должно быть по замыслу», а «их там нет». Мягкая кнопка — это
      // обещание, что после неё машина останется той же: аренда DHCP на месте,
      // статические адреса целы, перезагрузка не нужна.
      final joined = NetworkRecovery.softCommands.join('\n');
      for (final cmd in dangerous) {
        expect(NetworkRecovery.softCommands, isNot(contains(cmd)),
            reason: 'команда «$cmd» просочилась в МЯГКИЙ набор — она стирает '
                'аренду DHCP/статику или требует перезагрузки, а подтверждение '
                'мягкой кнопки обещает обратное');
      }
      for (final marker in const ['release', 'winsock', 'int ip reset']) {
        expect(joined, isNot(contains(marker)),
            reason: 'в мягком наборе появился «$marker» — это уже не мягкое '
                'восстановление');
      }
    });

    test('опасные команды все на месте в полном наборе', () {
      // Обратная сторона: вынести их из полного набора «на всякий случай» —
      // значит оставить кнопку, которая ничем не отличается от мягкой, но
      // пугает текстом.
      for (final cmd in dangerous) {
        expect(NetworkRecovery.fullCommands, contains(cmd));
      }
    });
  });

  group('⚠️ подтверждение ПОЛНОГО сброса называет всё поимённо', () {
    // Человек узнаёт об отпущенной аренде DHCP на виртуальных коммутаторах и о
    // стёртой статике ТОЛЬКО отсюда: в интерфейсе больше нигде об этом не
    // сказано, а после нажатия будет поздно.
    for (final locale in AppLocalizations.supportedLocales) {
      test('язык ${locale.languageCode}', () {
        final l = lookupAppLocalizations(locale);
        final body = l.networkFullResetConfirmBody.toLowerCase();
        for (final marker in const [
          'winsock',
          'dhcp',
          'hyper-v',
          'virtualbox',
        ]) {
          expect(body, contains(marker),
              reason: 'в тексте подтверждения полного сброса '
                  '(${locale.languageCode}) не сказано про «$marker»: '
                  '«${l.networkFullResetConfirmBody}»');
        }
        expect(ipWord.hasMatch(body), isTrue,
            reason: 'сброс IP-стека стирает статические адреса, а в тексте '
                '(${locale.languageCode}) про IP ни слова');
        // И сам факт перезагрузки — тоже словами. Проверяем на языках, где
        // корень известен точно; остальные держит паритет `l10n_test`.
        if (locale.languageCode == 'ru') {
          expect(body, contains('перезагрузк'));
        }
        if (locale.languageCode == 'en') {
          expect(body, contains('reboot'));
        }
      });
    }
  });

  group('⚠️ подтверждение МЯГКОГО восстановления не пугает зря', () {
    for (final locale in AppLocalizations.supportedLocales) {
      test('язык ${locale.languageCode}', () {
        final l = lookupAppLocalizations(locale);
        final body = l.networkSoftRecoverConfirmBody.toLowerCase();
        // Тексты перепутали местами либо в мягкий набор дописали опасное — и
        // человек, которому предлагают безобидную чистку кешей, читает про
        // winsock и DHCP. Он откажется от того, что ему как раз помогло бы.
        for (final marker in const ['winsock', 'dhcp', 'virtualbox']) {
          expect(body, isNot(contains(marker)),
              reason: 'мягкое подтверждение (${locale.languageCode}) грозит '
                  '«$marker», хотя мягкий набор этого не делает: '
                  '«${l.networkSoftRecoverConfirmBody}»');
        }
        expect(ipWord.hasMatch(body), isFalse,
            reason: 'мягкое подтверждение (${locale.languageCode}) говорит про '
                'IP-стек, которого не трогает');
      });
    }
  });

  group('⚠️ кнопка подтверждения — глагол, а не «ОК»', () {
    // «ОК» на диалоге, который сейчас отпустит аренду DHCP, не говорит человеку
    // ничего: он подтверждает не действие, а факт прочтения.
    for (final locale in AppLocalizations.supportedLocales) {
      test('язык ${locale.languageCode}', () {
        final l = lookupAppLocalizations(locale);
        for (final label in [
          l.networkSoftRecoverConfirmOk,
          l.networkFullResetConfirmOk,
        ]) {
          expect(label.trim(), isNotEmpty);
          expect(label.trim().toLowerCase(), isNot(l.commonOk.toLowerCase()),
              reason: 'кнопка подтверждения (${locale.languageCode}) — «ОК», '
                  'а должна называть действие глаголом');
        }
        expect(l.networkSoftRecoverConfirmOk, isNot(l.commonCancel));
      });
    }
  });

  group('⚠️ обе кнопки настроек доходят до исполнителя', () {
    late List<bool> runs;

    setUp(() {
      runs = <bool>[];
      NetworkRecovery.runnerForTests = (full) async {
        runs.add(full);
        return true;
      };
    });

    tearDown(() => NetworkRecovery.runnerForTests = null);

    /// Настоящие строки настроек — те же, что строит экран.
    ///
    /// ⚠️ Через [buildSettingsSections], а не своей копией `ListTile`: копия
    /// проверяла бы код, которого в приложении нет. Ровно на этом обжигались в
    /// `provider_wiring_test`.
    Widget host() => MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(builder: (context) {
              final sections = buildSettingsSections(
                  context, const AppSettings(), SettingsController());
              final network = sections
                  .where((s) => s.id == SettingsSectionIds.network)
                  .toList();
              expect(network, hasLength(1),
                  reason: 'раздел «Сеть» пропал из настроек — кнопкам '
                      'восстановления стало неоткуда взяться');
              return ListView(
                children: [
                  for (final r in network.single.rows) r.build(context),
                ],
              );
            }),
          ),
        );

    final l = lookupAppLocalizations(const Locale('ru'));

    testWidgets('в разделе «Сеть» есть обе строки, а не одна', (t) async {
      await t.pumpWidget(host());
      expect(find.text(l.networkSoftRecoverTitle), findsOneWidget,
          reason: 'мягкое восстановление пропало из настроек — остаётся только '
              'опасная кнопка');
      expect(find.text(l.networkFullResetTitle), findsOneWidget);
    });

    testWidgets('мягкая: нажатие показывает своё подтверждение и НЕ запускает',
        (t) async {
      await t.pumpWidget(host());
      await t.tap(find.text(l.networkSoftRecoverTitle));
      await t.pumpAndSettle();

      expect(find.text(l.networkSoftRecoverConfirmBody), findsOneWidget,
          reason: 'диалог подтверждения не показан');
      expect(find.text(l.networkFullResetConfirmBody), findsNothing,
          reason: 'мягкая кнопка показывает предупреждение полного сброса — '
              'обработчики перепутаны местами');
      // ⚠️ ГЛАВНОЕ В ЭТОМ ТЕСТЕ. Правка сети, запущенная ДО ответа человека, —
      // это действие, которого он не просил.
      expect(runs, isEmpty,
          reason: 'восстановление пошло ещё до того, как человек ответил');
    });

    testWidgets('мягкая: подтверждение зовёт run(full: false)', (t) async {
      await t.pumpWidget(host());
      await t.tap(find.text(l.networkSoftRecoverTitle));
      await t.pumpAndSettle();

      await t.tap(
          find.widgetWithText(FilledButton, l.networkSoftRecoverConfirmOk));
      await t.pumpAndSettle();

      expect(runs, [false],
          reason: 'мягкая кнопка либо ничего не запускает, либо запускает '
              'ПОЛНЫЙ сброс — а он стирает статику и требует перезагрузки');
    });

    testWidgets('полный: нажатие показывает своё подтверждение и НЕ запускает',
        (t) async {
      await t.pumpWidget(host());
      await t.tap(find.text(l.networkFullResetTitle));
      await t.pumpAndSettle();

      expect(find.text(l.networkFullResetConfirmBody), findsOneWidget);
      expect(find.text(l.networkSoftRecoverConfirmBody), findsNothing);
      expect(runs, isEmpty,
          reason: 'полный сброс пошёл до ответа человека');
    });

    testWidgets('полный: подтверждение зовёт run(full: true)', (t) async {
      await t.pumpWidget(host());
      await t.tap(find.text(l.networkFullResetTitle));
      await t.pumpAndSettle();

      await t
          .tap(find.widgetWithText(FilledButton, l.networkFullResetConfirmOk));
      await t.pumpAndSettle();

      expect(runs, [true],
          reason: 'кнопка подтверждения ничего не запускает либо запускает '
              'мягкий набор — строка выглядит рабочей и делает не то');
    });

    testWidgets('«Отмена» не запускает ничего — ни у мягкой, ни у полной',
        (t) async {
      for (final title in [
        l.networkSoftRecoverTitle,
        l.networkFullResetTitle,
      ]) {
        await t.pumpWidget(host());
        await t.tap(find.text(title));
        await t.pumpAndSettle();

        await t.tap(find.widgetWithText(TextButton, l.commonCancel));
        await t.pumpAndSettle();

        expect(runs, isEmpty, reason: 'отказ человека проигнорирован ($title)');
      }
    });
  });
}
