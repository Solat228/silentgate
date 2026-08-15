// Иконка правила, у которого путь умер после обновления программы.
//
// Жалоба владельца: «снова начали пропадать иконки приложений». На скриншоте
// три правила подряд — у `Telegram.exe` и `Code.exe` иконки есть, у
// `claude.exe` серая заглушка. В его настройках лежит
// `…\anthropic.claude-code-2.1.228-win32-x64\resources\native-binary\claude.exe`,
// а на диске установлены `2.1.232` и `2.1.233`: файла по этому пути НЕТ, и
// достать из него иконку невозможно.
//
// Путь правила при этом трогать нельзя — он уходит в конфиг ядра, — поэтому
// живой файл ищется отдельно. Здесь проверяется именно поиск.
@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/app_icon_windows.dart';

/// Поддельные диск и список процессов: настоящие подкладывать нельзя — тест
/// проверял бы Windows, а не наш поиск. Заодно считает обращения, чтобы видеть,
/// что дорогие источники не дёргаются зря.
class _FakeSources implements ExeSources {
  final Set<String> present;
  final Map<String, List<String>> entries;
  final Map<String, String> running;

  int runningQueries = 0;
  final List<String> listed = [];

  _FakeSources({
    Set<String>? present,
    Map<String, List<String>>? entries,
    Map<String, String>? running,
  })  : present = {...?present?.map((e) => e.toLowerCase())},
        entries = entries ?? const {},
        running = running ?? const {};

  @override
  bool exists(String path) => present.contains(path.toLowerCase());

  @override
  List<String> entriesOf(String dir) {
    listed.add(dir);
    return entries[dir] ?? const [];
  }

  @override
  String? runningPathFor(String exeName) {
    runningQueries++;
    return running[exeName.toLowerCase()];
  }
}

// Настоящие строки из настроек владельца (`silentgate_settings.json`).
const _ext = r'C:\Users\User\.vscode\extensions';
const _tail = r'resources\native-binary\claude.exe';
const _dead = r'anthropic.claude-code-2.1.228-win32-x64';
const _v232 = r'anthropic.claude-code-2.1.232-win32-x64';
const _v233 = r'anthropic.claude-code-2.1.233-win32-x64';

String _claudeIn(String version) => '$_ext\\$version\\$_tail';

/// Все каталоги-предки пути (`C:\a\b\c.exe` → `C:\a`, `C:\a\b`).
Set<String> _ancestors(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  final out = <String>{};
  var prefix = parts.first;
  for (var i = 1; i < parts.length - 1; i++) {
    prefix = '$prefix\\${parts[i]}';
    out.add(prefix);
  }
  return out;
}

void main() {
  group('locateExeForIcon: живой exe для иконки', () {
    test('путь жив — отдаём его и НИЧЕГО не ищем', () {
      const path = r'C:\Telegram Desktop\Telegram.exe';
      final src = _FakeSources(present: {path, ..._ancestors(path)});

      expect(locateExeForIcon(path, src), path);
      // Ни списка процессов, ни чтения каталогов: у большинства правил путь
      // жив, и второй заход обязан стоить ноль.
      expect(src.runningQueries, 0);
      expect(src.listed, isEmpty);
    });

    test('симптом владельца: путь мёртв, программа запущена — берём её путь',
        () {
      final live = _claudeIn(_v233);
      final src = _FakeSources(
        present: {live, ..._ancestors(live)},
        running: {'claude.exe': live},
      );

      expect(locateExeForIcon(_claudeIn(_dead), src), live);
    });

    test('программа не запущена — берём соседнюю версию каталога, САМУЮ НОВУЮ',
        () {
      final live232 = _claudeIn(_v232);
      final live233 = _claudeIn(_v233);
      final src = _FakeSources(
        present: {
          live232,
          live233,
          ..._ancestors(live232),
          ..._ancestors(live233),
        },
        entries: {
          _ext: [_v232, _v233, 'ms-python.python-2024.0.1', 'README.md'],
        },
      );

      expect(locateExeForIcon(_claudeIn(_dead), src), live233);
      // Каталог прочитан ровно один раз.
      expect(src.listed, [_ext]);
    });

    test('версии сравниваются числами: 1.0.10 новее 1.0.9', () {
      const root = r'C:\Users\User\AppData\Local\Discord';
      const live = '$root\\app-1.0.10\\Discord.exe';
      const old = '$root\\app-1.0.9\\Discord.exe';
      final src = _FakeSources(
        // ⚠️ ОБА файла на месте — иначе порядок ничего не решает: поиск просто
        // перебрал бы кандидатов и нашёл единственный существующий, и тест
        // оставался бы зелёным при сортировке строкой.
        present: {live, old, ..._ancestors(live), ..._ancestors(old)},
        entries: {
          root: ['app-1.0.9', 'app-1.0.10', 'Update.exe'],
        },
      );

      // Строкой «app-1.0.9» больше «app-1.0.10», и иконка была бы от старой.
      expect(locateExeForIcon('$root\\app-1.0.8\\Discord.exe', src), live);
    });

    test('у самого нового соседа нужного файла нет — пробуем следующего', () {
      final live232 = _claudeIn(_v232);
      final src = _FakeSources(
        present: {
          live232,
          ..._ancestors(live232),
          // Каталог 2.1.233 есть, а файла в нём нет (обновление на полпути).
          '$_ext\\$_v233',
        },
        entries: {
          _ext: [_v232, _v233],
        },
      );

      expect(locateExeForIcon(_claudeIn(_dead), src), live232);
    });

    test('в правиле голое имя без каталога — спасает запущенный процесс', () {
      const live = r'C:\Program Files\Foo\claude.exe';
      final src = _FakeSources(
        present: {live, ..._ancestors(live)},
        running: {'claude.exe': live},
      );

      expect(locateExeForIcon('claude.exe', src), live);
    });

    test('ничего не нашли — null (одна и та же заглушка, а не «иногда пусто»)',
        () {
      final src = _FakeSources(
        present: {_ext},
        entries: {_ext: const ['ms-python.python-2024.0.1']},
      );

      expect(locateExeForIcon(_claudeIn(_dead), src), isNull);
    });

    test('сосед по шаблону не совпал — чужую программу не подставляем', () {
      const other = '$_ext\\anthropic.other-2.1.233-win32-x64\\$_tail';
      final src = _FakeSources(
        present: {other, ..._ancestors(other)},
        entries: {
          _ext: const ['anthropic.other-2.1.233-win32-x64'],
        },
      );

      expect(locateExeForIcon(_claudeIn(_dead), src), isNull);
    });

    test('в пропавшем сегменте нет цифр — каталог не читаем вовсе', () {
      const path = r'C:\Program Files\Removed\thing.exe';
      final src = _FakeSources(present: const {r'C:\Program Files'});

      expect(locateExeForIcon(path, src), isNull);
      // Версии тут быть не может, значит и перебирать соседей незачем.
      expect(src.listed, isEmpty);
    });

    test('пустой путь и путь без каталога не роняют поиск', () {
      final src = _FakeSources();
      expect(locateExeForIcon('', src), isNull);
      expect(locateExeForIcon('   ', src), isNull);
      expect(locateExeForIcon('claude.exe', src), isNull);
    });
  });

  // Сквозная проверка: настоящий файл, настоящий ExtractIconEx, настоящий
  // фоновый isolate. Без неё зелёными были бы только чистые строки, а связка
  // «нашли путь → достали иконку» осталась бы недоказанной.
  group('AppIconWindows.load: мёртвый путь версии', () {
    late Directory root;
    late String deadPath;

    setUp(() {
      root = Directory.systemTemp.createTempSync('sg-icon-');
      // Имя своё, чтобы поиск не «повезло» разрешить через запущенный процесс:
      // такого процесса на машине нет по построению.
      final live = Directory('${root.path}\\probe-1.0.2')..createSync();
      File(r'C:\Windows\System32\notepad.exe')
          .copySync('${live.path}\\sg-icon-probe.exe');
      deadPath = '${root.path}\\probe-1.0.1\\sg-icon-probe.exe';
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('иконка берётся у соседней версии', () async {
      expect(File(deadPath).existsSync(), isFalse,
          reason: 'путь правила обязан быть мёртвым — иначе тест ничего не '
              'доказывает');

      final png = await AppIconWindows.load(deadPath);
      expect(png, isNotNull,
          reason: 'иконка есть у файла соседней версии, и её надо показать');
      expect(png!.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    });
  });
}
