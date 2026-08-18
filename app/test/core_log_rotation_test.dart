import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/rotating_log.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/windows/singbox_process.dart';
import 'package:silentgate/engine/windows/tun/tun_helper.dart';

/// Логи ЯДЕР копятся с ротацией и переживают перезапуск ядра.
///
/// ⚠️ ЗАЧЕМ ЭТОТ ФАЙЛ. 19.08.2026 у владельца было два обрыва туннеля (01:29 и
/// 02:20), отчёт поддержки собран в 02:21:56 — а в `singbox.log` к моменту
/// разбора лежали 55 секунд с 02:44:42 (187 КБ). Окна ни одной из аварий не
/// осталось, и утечку по логам не удалось ни доказать, ни опровергнуть, хотя
/// отчёт поддержки делают ровно ради этого.
///
/// Виноваты были ДВА независимых стирания, и тесты ниже стерегут оба:
///  1. `TunHelper.run` начинал каждую сессию ядра с `truncate()`. Но новая
///     сессия — это и есть восстановление после обрыва: журнал аварии
///     уничтожался перезапуском, который аварией и вызван. Плюс автоподбор
///     стека и MTU делает до девяти запусков подряд.
///  2. `RotatingLog` при достижении порога обнулял файл. На уровне `debug`
///     (а он у владельца включён) 512 КБ набегали за две с половиной минуты —
///     столько истории и хранилось.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sg_corelog_');
    // Хозяйство логов (`LogMaintenance`) резолвит каталог данных само —
    // без подмены тест ушёл бы в боевой `%APPDATA%` владельца.
    AppPaths.overrideRoot(tmp);
  });

  tearDown(() async {
    AppPaths.resetForTests();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  String p(String name) => '${tmp.path}${Platform.pathSeparator}$name';

  String prevOf(String name) => RotatingLog.previousPathFor(p(name));

  /// Строка РОВНО в 50 байт вместе с переводом строки.
  ///
  /// ⚠️ Только ASCII и только фиксированная длина. Первая версия этих тестов
  /// писала русские строки переменной длины, и число ротаций зависело от
  /// длины числа в тексте: тест то ловил дефект, то нет. Здесь порог кратен
  /// длине строки, поэтому «после какой строки произойдёт сдвиг» — не догадка.
  String fixed(String tag) => tag.padRight(49, '-');

  /// Порог, кратный [fixed]: сдвиг ровно после каждых 20 строк.
  const rollAfter = 20;
  const threshold = 50 * rollAfter;

  /// Номер строки `L007` → 7; всё остальное отбрасывается.
  int? indexOf(String line) =>
      int.tryParse(RegExp(r'^L(\d+)').firstMatch(line)?.group(1) ?? '');

  List<int> indexesIn(String text) => const LineSplitter()
      .convert(text)
      .map(indexOf)
      .whereType<int>()
      .toList();

  // ──────────────────────────────────────────────────────────────────────────
  group('перезапуск ядра не стирает журнал прошлой сессии', () {
    test('вторая сессия дописывает, а не начинает файл заново', () async {
      final path = p('singbox.log');

      // Сессия 1: ядро поднялось, пожаловалось и умерло.
      final first =
          await TunHelper.openSessionLog(path, '--- запуск sing-box 1');
      await first.write('ERROR тут был обрыв 01:29');
      await first.write('--- sing-box завершился, код 1');
      await first.close();

      // Сессия 2 — то самое автопереподключение, которое раньше и стирало
      // улику. Ровно этот вызов раньше делал `truncate()`.
      final second =
          await TunHelper.openSessionLog(path, '--- запуск sing-box 2');
      await second.write('INFO туннель поднят');
      await second.close();

      final text = await File(path).readAsString();
      expect(text.contains('ERROR тут был обрыв 01:29'), isTrue,
          reason: 'на старом поведении строка обрыва исчезала при '
              'первом же восстановлении — разбирать было нечего');
      expect(text.contains('--- запуск sing-box 1'), isTrue,
          reason: 'по накопленному логу сессии обязаны различаться');
      expect(text.contains('--- запуск sing-box 2'), isTrue);
      expect(text.indexOf('--- запуск sing-box 1'),
          lessThan(text.indexOf('--- запуск sing-box 2')),
          reason: 'порядок сессий — хронологический');
    });

    test('девять попыток автоподбора TUN не съедают историю', () async {
      final path = p('autotune.log');
      final first = await TunHelper.openSessionLog(path, '--- сессия 0');
      await first.write('FATAL исходная причина отказа');
      await first.close();

      // `SingboxRouterWindows` перебирает до девяти комбинаций стека и MTU,
      // и каждая — новый запуск хелпера.
      for (var i = 1; i <= 9; i++) {
        final log = await TunHelper.openSessionLog(path, '--- сессия $i');
        await log.write('попытка $i');
        await log.close();
      }

      final text = await File(path).readAsString();
      expect(text.contains('FATAL исходная причина отказа'), isTrue,
          reason: 'иначе к концу перебора остаётся лог ПОСЛЕДНЕЙ попытки, '
              'а нужна первопричина');
    });

    test('лог сессии ядра заведён с хранением прежней части', () async {
      final log = await TunHelper.openSessionLog(p('flags.log'), '--- старт');
      addTearDown(log.close);
      expect(log.keepPrevious, isTrue,
          reason: 'без этого накопление бессмысленно: порог всё равно '
              'обнулял бы файл каждые несколько минут');
      expect(log.maxBytes, RotatingLog.coreLogMaxBytes);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('ротация по порогу', () {
    test('старое уезжает в *.prev.log, свежее остаётся в основном', () async {
      final path = p('roll.log');
      final log = RotatingLog(path, maxBytes: threshold, keepPrevious: true);
      await log.open();
      // Ровно одна ротация: 30 строк при сдвиге после 20-й.
      for (var i = 0; i < 30; i++) {
        await log.write(fixed('L${i.toString().padLeft(3, '0')}'));
      }
      await log.flush();
      await log.close();

      final prev = File(prevOf('roll.log'));
      expect(await prev.exists(), isTrue,
          reason: 'на старом поведении файл обнулялся, и первые 20 строк '
              'просто исчезали');

      final prevIdx = indexesIn(await prev.readAsString());
      final curIdx = indexesIn(await File(path).readAsString());
      expect(prevIdx.first, 0,
          reason: 'самое старое лежит в предыдущей части');
      expect(prevIdx.last, rollAfter - 1);
      expect(curIdx.first, rollAfter,
          reason: 'текущая часть начинается ровно там, где кончилась прежняя '
              '— ни одна строка не имеет права пропасть на стыке');
      expect(curIdx.last, 29, reason: 'самое свежее — в текущей');
    });

    test('на диске не больше двух частей', () async {
      final path = p('cap.log');
      final log = RotatingLog(path, maxBytes: threshold, keepPrevious: true);
      await log.open();
      for (var i = 0; i < 400; i++) {
        await log.write(fixed('L${i.toString().padLeft(3, '0')}'));
      }
      await log.flush();
      await log.close();

      final logs = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.log'))
          .toList();
      expect(logs.length, 2,
          reason: 'частей ровно две: текущая и предыдущая. Третья означала бы '
              'вторую, никем не управляемую политику хранения');
      var total = 0;
      for (final f in logs) {
        total += await f.length();
      }
      expect(total, lessThanOrEqualTo(threshold * 2),
          reason: 'потолок расхода — ровно два порога, лог не растёт без '
              'предела (была беда с 758 МБ)');

      final tail = await RotatingLog.tailAcrossRotation(path, lines: 1);
      expect(indexOf(tail), 399,
          reason: 'после любого числа сдвигов последняя строка на месте');
    });

    test('строки, записанные перед самой ротацией, не теряются', () async {
      final path = p('tail.log');
      final log = RotatingLog(path, maxBytes: threshold, keepPrevious: true);
      await log.open();
      // 18 строк шума, затем две важные — и только потом сдвиг.
      for (var i = 0; i < 18; i++) {
        await log.write(fixed('L${i.toString().padLeft(3, '0')}'));
      }
      await log.write(fixed('ERROR канал умер'));
      await log.write(fixed('--- sing-box завершился, код 2'));
      // Дальше ядро подняли заново — сдвиг случается ЗДЕСЬ, и обе строки выше
      // оказываются в предыдущей части.
      for (var i = 20; i < 25; i++) {
        await log.write(fixed('L${i.toString().padLeft(3, '0')}'));
      }
      await log.flush();
      await log.close();

      expect(await File(prevOf('tail.log')).exists(), isTrue,
          reason: 'сдвиг обязан был произойти — иначе тест ничего не проверяет');
      final current = await File(path).readAsString();
      expect(current.contains('ERROR канал умер'), isFalse,
          reason: 'предпосылка теста: в текущей части этих строк уже нет');

      final across = await RotatingLog.tailAcrossRotation(path, lines: 25);
      expect(across.contains('ERROR канал умер'), isTrue,
          reason: 'ради этих строк лог и читают');
      expect(across.contains('--- sing-box завершился, код 2'), isTrue);
    });

    test('хвост через ротацию склеивает части в хронологическом порядке',
        () async {
      final path = p('across.log');
      final log = RotatingLog(path, maxBytes: threshold, keepPrevious: true);
      await log.open();
      for (var i = 0; i < 30; i++) {
        await log.write(fixed('L${i.toString().padLeft(3, '0')}'));
      }
      await log.flush();
      await log.close();

      final across = await RotatingLog.tailAcrossRotation(path, lines: 25);
      final idx = indexesIn(across);
      expect(idx.length, 25,
          reason: 'текущей части (10 строк) не хватило — недостающее берётся '
              'из предыдущей, иначе отчёт поддержки показал бы десять строк');
      expect(idx, equals(List<int>.from(idx)..sort()),
          reason: 'предыдущая часть обязана идти ВЫШЕ текущей');
      expect(idx.first, 5);
      expect(idx.last, 29, reason: 'последняя строка — самая свежая');

      final onlyCurrent = await RotatingLog.tail(path, lines: 25);
      expect(indexesIn(onlyCurrent).length, lessThan(25),
          reason: 'именно из-за этого обычного tail и было мало');
    });

    test('без keepPrevious поведение прежнее: соседнего файла не появляется',
        () async {
      final path = p('plain.log');
      final log = RotatingLog(path, maxBytes: threshold);
      await log.open();
      for (var i = 0; i < 100; i++) {
        await log.write(fixed('L${i.toString().padLeft(3, '0')}'));
      }
      await log.flush();
      await log.close();
      expect(await File(prevOf('plain.log')).exists(), isFalse,
          reason: 'флаг выключен по умолчанию — иначе каждый лог в проекте '
              'молча удвоил бы расход места');
    });

    test('гость не ротирует чужой лог', () async {
      final path = p('shared.log');
      final owner =
          RotatingLog(path, maxBytes: 1 << 20, keepPrevious: true);
      await owner.open();
      await owner.write('владелец');
      await owner.flush();

      final guest = RotatingLog(path, maxBytes: 50, keepPrevious: true);
      await guest.open();
      expect(guest.isOwner, isFalse);
      for (var i = 0; i < 30; i++) {
        await guest.write('гость $i');
      }
      await guest.flush();
      await guest.close();
      await owner.close();

      expect(await File(prevOf('shared.log')).exists(), isFalse,
          reason: 'ротация из второй копии обнулила бы файл первой, и Windows '
              'залила бы разрыв нулями — та же болезнь, что и с обрезкой');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('согласование со сроком хранения', () {
    test('предыдущая часть называется *.log и видна хозяйству логов', () async {
      expect(RotatingLog.previousPathFor(r'C:\x\singbox.log'),
          r'C:\x\singbox.prev.log');
      expect(RotatingLog.previousPathFor(r'C:\x\singbox.log').endsWith('.log'),
          isTrue,
          reason: 'перепись и чистка ходят по маске *.log; имя вида '
              '`singbox.log.1` выпало бы из обеих');

      final path = p('kept.log');
      final log = RotatingLog(path, maxBytes: threshold, keepPrevious: true);
      await log.open();
      for (var i = 0; i < 30; i++) {
        await log.write(fixed('L${i.toString().padLeft(3, '0')}'));
      }
      await log.flush();
      await log.close();

      final inv = await LogMaintenance.inventory(dir: tmp);
      expect(inv.logs.map((e) => e.name), contains('kept.prev.log'),
          reason: 'иначе на диске завёлся бы файл, которого не видно ни на '
              'экране логов, ни в подсчёте занятого места');
    });

    test('предыдущая часть удаляется той же настройкой срока хранения',
        () async {
      final prev = File(prevOf('old.log'));
      await prev.writeAsString('древние строки\n');
      await prev.setLastModified(
          DateTime.now().subtract(const Duration(days: 40)));

      final res = await LogMaintenance.clean(
          maxAge: LogRetention.month.maxAge, dir: tmp);
      expect(res.files, 1);
      expect(await prev.exists(), isFalse,
          reason: 'вторая политика хранения не заводится: чистит та же '
              'настройка LogRetention');
    });

    test('«Очистить логи» стирает и предыдущую часть', () async {
      final path = p('wipe.log');
      final log = RotatingLog(path, maxBytes: threshold, keepPrevious: true);
      await log.open();
      for (var i = 0; i < 30; i++) {
        await log.write(fixed('L${i.toString().padLeft(3, '0')}'));
      }
      await log.flush();
      expect(await File(prevOf('wipe.log')).exists(), isTrue);

      await log.truncate();
      await log.close();

      expect(await File(prevOf('wipe.log')).exists(), isFalse,
          reason: 'человек нажал «очистить» и вправе ожидать, что данных не '
              'осталось; ротация — другое действие и историю БЕРЕЖЁТ');
      expect(await File(path).length(), 0);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('прокси-ядро', () {
    test('его хвост тоже читается через ротацию', () async {
      final path = SingboxProcess.logPathFor(tmp, name: 'singbox_proxy.log');
      final log = RotatingLog(path, maxBytes: threshold, keepPrevious: true);
      await log.open();
      await log.write(fixed('FATAL прокси-ядро не поднялось'));
      for (var i = 1; i < 25; i++) {
        await log.write(fixed('L${i.toString().padLeft(3, '0')}'));
      }
      await log.flush();
      await log.close();

      expect((await File(path).readAsString()).contains('FATAL'), isFalse,
          reason: 'предпосылка теста: причина отказа уже уехала в предыдущую '
              'часть');
      final tail = await SingboxProcess.tailLog(lines: 30);
      expect(tail.contains('FATAL прокси-ядро не поднялось'), isTrue,
          reason: 'обычный tail показал бы только шум после сдвига — отчёт '
              'поддержки остался бы без причины отказа');
    });

    test('потолок части лога рассчитан на десятки минут уровня debug', () {
      // 19.08.2026: 187 КБ за 55 секунд, то есть ~3,4 КБ/с.
      const bytesPerSecond = 187 * 1024 / 55;
      const minutes = RotatingLog.coreLogMaxBytes / bytesPerSecond / 60;
      expect(minutes, greaterThanOrEqualTo(30),
          reason: 'меньше — и обрыв, замеченный человеком через полчаса, снова '
              'окажется вытеснен из лога (прежние 512 КБ давали 2,5 минуты)');
      expect(RotatingLog.coreLogMaxBytes * 2,
          lessThanOrEqualTo(32 * 1024 * 1024),
          reason: 'две части не имеют права превратиться в прежние 758 МБ');
    });
  });
}
