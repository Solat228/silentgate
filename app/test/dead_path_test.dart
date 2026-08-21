import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/dead_path_badge.dart';

/// ПРАВИЛО, КОТОРОЕ НЕ МОЖЕТ СРАБОТАТЬ, ОБЯЗАНО ОБ ЭТОМ СКАЗАТЬ.
///
/// ⚠️ ВОСПРОИЗВЕДЕНО ОПЫТОМ В VM 17.08.2026, а не придумано.
/// Правило «по пути» на `C:\testapp-1.0\myapp.exe`, действие «Прямо». Пока файл
/// лежал по этому пути: `router: match[6] process_path_regex=… => route(direct)`,
/// наружу шёл реальный адрес ***.***.***.***. После «обновления» (тот же файл в
/// `C:\testapp-2.0\`) в логе ядра НЕ ОСТАЛОСЬ НИ ОДНОЙ строки `match`, и тот же
/// трафик ушёл в туннель — 185.130.226.42. Настройки при этом сообщали
/// `enabled=True, action=direct`: правило выглядело здоровым.
///
/// Лечение проверено там же: то же правило «по имени» дало
/// `match[6] process_name=myapp.exe => route(direct)` при НАМЕРЕННО оставленном
/// мёртвом пути в записи.
void main() {
  _versionedPathGuards();
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sg_deadpath_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget host(AppRule rule, {VoidCallback? onFix}) => MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DeadPathBadge(
            rule: rule,
            onSwitchToName: onFix ?? () {},
          ),
        ),
      );

  final badge = find.byKey(const Key('deadPathFix'));

  testWidgets('⚠️ ГЛАВНОЕ: исчезнувший файл помечен', (tester) async {
    final gone = '${tmp.path}${Platform.pathSeparator}app-2.0-которого-нет.exe';
    await tester.pumpWidget(host(AppRule(gone, byName: false)));
    await tester.pumpAndSettle();

    if (!DeadPathBadge.appliesOn()) {
      // На мобильных в `path` лежит имя пакета — там проверять нечего.
      expect(badge, findsNothing);
      return;
    }
    expect(badge, findsOneWidget,
        reason: 'ЗДЕСЬ БЫЛА ТИШИНА: правило показывалось здоровым и '
            'не совпадало ни с чем');
  });

  testWidgets('живой файл ничем не помечается', (tester) async {
    // Иначе предупреждение кричало бы всегда, а такое перестают замечать.
    final alive = File('${tmp.path}${Platform.pathSeparator}myapp.exe')
      ..writeAsStringSync('x');
    await tester.pumpWidget(host(AppRule(alive.path, byName: false)));
    await tester.pumpAndSettle();
    expect(badge, findsNothing);
  });

  testWidgets('⚠️ правило «по имени» не помечается даже с мёртвым путём',
      (tester) async {
    // Именно так выглядит вылеченное правило: путь в записи остался старым, но
    // сопоставление от него больше не зависит — это и подтвердил опыт в VM.
    final gone = '${tmp.path}${Platform.pathSeparator}app-1.0-удалён.exe';
    await tester.pumpWidget(host(AppRule(gone, byName: true)));
    await tester.pumpAndSettle();
    expect(badge, findsNothing,
        reason: 'по имени путь не участвует в сопоставлении');
  });

  testWidgets('нажатие переводит правило на сопоставление по имени',
      (tester) async {
    if (!DeadPathBadge.appliesOn()) return;
    var fixed = false;
    final gone = '${tmp.path}${Platform.pathSeparator}нет.exe';
    await tester.pumpWidget(
        host(AppRule(gone, byName: false), onFix: () => fixed = true));
    await tester.pumpAndSettle();
    await tester.tap(badge);
    expect(fixed, isTrue,
        reason: 'у предупреждения обязано быть лечение в один тап: для '
            'программ с версией в пути «по имени» — единственный устойчивый '
            'вариант');
  });

  testWidgets('смена пути на живой снимает пометку', (tester) async {
    if (!DeadPathBadge.appliesOn()) return;
    final gone = '${tmp.path}${Platform.pathSeparator}нет.exe';
    final alive = File('${tmp.path}${Platform.pathSeparator}есть.exe')
      ..writeAsStringSync('x');

    await tester.pumpWidget(host(AppRule(gone, byName: false)));
    await tester.pumpAndSettle();
    expect(badge, findsOneWidget);

    // Пользователь указал программу заново — пометка обязана уйти без
    // пересоздания экрана.
    await tester.pumpWidget(host(AppRule(alive.path, byName: false)));
    await tester.pumpAndSettle();
    expect(badge, findsNothing);
  });
}

/// ⚠️ ВТОРАЯ ПОЛОВИНА ЗАДАЧИ: ПРЕДУПРЕДИТЬ ДО ПОЛОМКИ, А НЕ ПОСЛЕ.
///
/// Пометка выше ждала, пока файл ИСЧЕЗНЕТ. Для программ, которые ставят каждую
/// версию в свой каталог, это опоздание ровно на один цикл: пока стоит
/// `…claude-code-2.1.238-win32-x64\…`, правило совпадает и выглядит исправным,
/// а наутро программа обновилась — и оно молча перестало работать.
///
/// Владелец 21.08.2026: «мне абсолютно похуй, с какой папки будет этот файл,
/// ВСЕ файлы с этим именем должны быть найдены». Проверено живьём в VM: одно и
/// то же имя в двух РАЗНЫХ папках правило `process_name` ловит одинаково, а
/// файл с другим именем в той же папке — не ловит. То есть движок исправен, и
/// чинить надо ровно распознавание хрупкого пути.
void _versionedPathGuards() {
  group('⚠️ Путь с номером версии распознаётся', () {
    test('каталог расширения VS Code — хрупкий', () {
      expect(
          DeadPathBadge.pathLooksVersioned(
              r'C:\Users\U\.vscode\extensions\anthropic.claude-code-2.1.238-win32-x64\resources\native-binary\claude.exe'),
          isTrue);
    });

    test('Squirrel-раскладка app-1.2.3 — хрупкая', () {
      expect(
          DeadPathBadge.pathLooksVersioned(r'C:\Users\U\AppData\Local\X\app-1.2.3\x.exe'),
          isTrue);
    });

    test('⚠️ обратный слэш действительно делит путь', () {
      // Первая редакция делила по `[\/]`, где `\/` — экранированная косая
      // черта: обратный слэш в класс НЕ попадал, путь Windows не делился, и
      // функция всегда отвечала «нет». Проверка, которая никогда не срабатывает,
      // хуже отсутствующей — она создаёт видимость защиты.
      expect(DeadPathBadge.pathLooksVersioned(r'C:\app-1.2.3\x.exe'), isTrue);
      expect(DeadPathBadge.pathLooksVersioned('/opt/app-1.2.3/x'), isTrue);
    });

    test('программы, обновляющиеся на месте, — НЕ хрупкие', () {
      // Ложная тревога здесь дороже пропуска: предупреждение, которое горит у
      // всех подряд, перестают замечать за день.
      for (final p in [
        r'C:\Users\U\AppData\Local\Programs\Microsoft VS Code\Code.exe',
        r'C:\Telegram Desktop\Telegram.exe',
        r'C:\Program Files (x86)\Foo\foo.exe',
        r'C:\Windows\System32\curl.exe',
      ]) {
        expect(DeadPathBadge.pathLooksVersioned(p), isFalse, reason: p);
      }
    });

    test('⚠️ номер версии в ИМЕНИ ФАЙЛА не считается', () {
      // У `python3.10.exe` путь как раз устойчив — меняется имя, а не папка.
      expect(DeadPathBadge.pathLooksVersioned(r'C:\Python\python3.10.exe'),
          isFalse);
    });

    test('пустое и без каталога — не хрупкое', () {
      expect(DeadPathBadge.pathLooksVersioned(''), isFalse);
      expect(DeadPathBadge.pathLooksVersioned('claude.exe'), isFalse);
    });
  });
}
