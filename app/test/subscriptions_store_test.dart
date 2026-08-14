import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/data/subscriptions_store.dart';

/// Хранилище подписок: самый дорогой файл приложения.
///
/// ⚠️ ЧЕМ БОЛЕЛО. `load()` заворачивал разбор в глухой `catch (_)` и отдавал
/// ПУСТОЙ снимок — без строки в журнале и без сохранения улики. Пустота при
/// этом означала сразу три разных вещи: «файла нет», «файл не прочитался» и
/// «подписок правда нет». Дальше `AppState.init()` принимал её за первое,
/// включал миграцию со старой одно-подписочной версии и перезаписывал файл с
/// четырьмя подписками файлом с одной. Хватало обрезанного файла после убийства
/// процесса или сохранения его блокнотом в «Юникод» (UTF-16: байты перестают
/// быть UTF-8, и `readAsString` падает ещё до разбора).
///
/// ⚠️ А ВОТ ОДИНОЧНОГО BOM НЕ ХВАТАЛО — прежняя формулировка здесь врала.
/// Ведущий `EF BB BF` снимает сам декодер UTF-8 внутри `readAsString`; до
/// `jsonDecode` он не доезжает. Разбор роняет только U+FEFF, доживший до
/// строки, — то есть двойной BOM в файле. Ровно из-за этого прежний тест «BOM
/// от блокнота» оставался зелёным при снятой защите и не стерёг ничего.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sg_subs_store_');
    // ⚠️ ОБЯЗАТЕЛЬНО: без подмены корня тест полез бы в боевой
    // %APPDATA%\SilentGate владельца.
    AppPaths.overrideRoot(tmp);
    // Журнал статичен на весь процесс: без сброса записи одного теста
    // подсказывали бы ответы следующему.
    await AppLog.resetFileForTest();
  });

  tearDown(() async {
    await AppLog.resetFileForTest();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  File subsFile() =>
      File('${tmp.path}${Platform.pathSeparator}subscriptions.json');

  /// Четыре подписки — ровно то, что лежит у владельца.
  String fourSubs() => jsonEncode({
        'activeId': 'sub_1',
        'items': [
          for (var i = 1; i <= 4; i++)
            {
              'id': 'sub_$i',
              'url': 'https://panel.example/sub/token-$i',
              'servers': ['vless://uuid@node$i.example.com:443?type=tcp'],
            },
        ],
      });

  bool loggedContains(String needle) =>
      AppLog.entries.any((e) => e.message.contains(needle));

  /// ⚠️ КОДОМ, А НЕ САМИМ БАЙТОМ. Невидимый символ в исходнике глазами не
  /// проверяется, и на этом классе багов в проекте уже стояли: ESC пропал из
  /// выражения, снимавшего цвет, и цвет снимался наполовину.
  final bom = String.fromCharCode(0xFEFF);

  group('Разбор содержимого (без диска)', () {
    test('⚠️ ПРЕДПОСЫЛКА: jsonDecode НА U+FEFF В СТРОКЕ ПАДАЕТ', () {
      // Ради этого и стоит срез. Утверждение проверяется здесь, а не берётся на
      // веру: если Dart однажды начнёт пропускать BOM сам, защита станет
      // мёртвым кодом — и об этом скажет вот этот тест, а не рассуждение в
      // комментарии.
      expect(() => jsonDecode('$bom{}'), throwsFormatException);
    });

    test('⚠️ BOM В СТРОКЕ НЕ СТОИТ НИ ОДНОЙ ПОДПИСКИ', () {
      // ⚠️ ЗДЕСЬ ИМЕННО СТРОКА, И ЭТО НЕ ТО ЖЕ, ЧТО ФАЙЛ С BOM. Один ведущий
      // BOM в файле снимает сам декодер UTF-8 (`readAsString`), до разбора он не
      // доезжает; в строку U+FEFF попадает, когда BOM в файле НЕ ОДИН (см.
      // дисковый тест ниже) либо когда текст пришёл не из `readAsString`.
      final snap = SubscriptionsStore.parseContent('$bom${fourSubs()}');
      expect(snap, isNotNull);
      expect(snap!.items.length, 4);
      expect(snap.activeId, 'sub_1');
      expect(snap.outcome, SubscriptionsLoadOutcome.loaded);
    });

    test('обрезанный файл — нечитаем, а не пуст', () {
      final cut = fourSubs().substring(0, fourSubs().length ~/ 2);
      expect(SubscriptionsStore.parseContent(cut), isNull);
    });

    test('пустое содержимое — тоже порча (нулевой размер даёт обрезка)', () {
      // Осознанное расхождение с SettingsStorage, где пустой файл значит
      // «настроек ещё нет»: собственная запись идёт через AtomicFile и пустым
      // файлом кончиться не может.
      expect(SubscriptionsStore.parseContent(''), isNull);
      expect(SubscriptionsStore.parseContent('   \n'), isNull);
    });

    test('items не того типа — нечитаем', () {
      expect(SubscriptionsStore.parseContent('{"items": 5}'), isNull);
      expect(SubscriptionsStore.parseContent('[]'), isNull);
    });

    test('мусор вместо записи подписки — нечитаем', () {
      expect(
          SubscriptionsStore.parseContent(
              jsonEncode({'items': ['строка вместо объекта']})),
          isNull);
    });

    test('⚠️ ОДНА БИТАЯ ЗАПИСЬ ДЕЛАЕТ НЕЧИТАЕМЫМ ВЕСЬ ФАЙЛ — ЭТО ВЫБОР', () {
      // Прежний код (`whereType<Map>()`) поднял бы три подписки из четырёх, и
      // это выглядит мягче. Кончается хуже: в памяти их три, ПЕРВОЕ ЖЕ
      // сохранение (переключение подписки, обновление, перетаскивание) запишет
      // на диск три, и четвёртая исчезнет молча и навсегда. Громкий отказ не
      // теряет ничего — файл целиком уезжает в `*.bad` (проверено дисковым
      // тестом ниже).
      final raw = jsonEncode({
        'activeId': 'sub_1',
        'items': [
          {'id': 'sub_1', 'url': 'https://panel.example/sub/token-1'},
          {'id': 'sub_2', 'url': 'https://panel.example/sub/token-2'},
          {'id': 'sub_3', 'url': 'https://panel.example/sub/token-3'},
          // Битая — не та природа элемента в списке серверов.
          {'id': 'sub_4', 'url': 'https://panel.example/sub/token-4',
            'servers': [42]},
        ],
      });
      expect(SubscriptionsStore.parseContent(raw), isNull,
          reason: 'три из четырёх молча — это необратимая потеря четвёртой при '
              'первой же записи');
    });

    test('⚠️ не-строка в списке серверов ловится ЗДЕСЬ, а не в init()', () {
      // `SubscriptionProfile.fromJson` кладёт в serverLinks ЛЕНИВЫЙ
      // cast<String>(): без принудительного обхода исключение прилетело бы уже
      // из `AppState.init()`, мимо всякого catch, — то есть приложение не
      // стартовало бы вовсе.
      final raw = jsonEncode({
        'items': [
          {
            'id': 'sub_1',
            'url': 'https://panel.example/sub/token-1',
            'servers': [42],
          }
        ],
      });
      expect(SubscriptionsStore.parseContent(raw), isNull);
    });

    test('разобранный пустой список — это «подписок нет», и это читаемо', () {
      final snap =
          SubscriptionsStore.parseContent('{"activeId":null,"items":[]}');
      expect(snap, isNotNull);
      expect(snap!.isEmpty, isTrue);
      expect(snap.isReadable, isTrue);
      expect(snap.outcome, SubscriptionsLoadOutcome.loaded);
    });

    test('подписка без адреса пропускается, остальные целы', () {
      final snap = SubscriptionsStore.parseContent(jsonEncode({
        'items': [
          {'id': 'a', 'url': ''},
          {'id': 'b', 'url': 'https://panel.example/sub/b'},
        ],
      }));
      expect(snap!.items.map((p) => p.id), ['b']);
    });
  });

  group('Чтение с диска: три случая, а не один', () {
    test('файла нет — это чистая установка, а не беда', () async {
      final snap = await SubscriptionsStore().load();
      expect(snap.outcome, SubscriptionsLoadOutcome.missing);
      expect(snap.isReadable, isTrue,
          reason: 'миграция со старой версии обязана на этом срабатывать');
    });

    test('файл прочитан — четыре подписки на месте', () async {
      subsFile().writeAsStringSync(fourSubs());
      final snap = await SubscriptionsStore().load();
      expect(snap.outcome, SubscriptionsLoadOutcome.loaded);
      expect(snap.items.length, 4);
    });

    test('⚠️ НЕЧИТАЕМЫЙ ФАЙЛ: ГРОМКО И БЕЗ ПОТЕРИ ДАННЫХ', () async {
      // Обрезанный файл: процесс убили посреди записи.
      final original = fourSubs().substring(0, 120);
      subsFile().writeAsStringSync(original);

      final snap = await SubscriptionsStore().load();

      expect(snap.outcome, SubscriptionsLoadOutcome.unreadable,
          reason: 'пустой список тут неотличим от «подписок нет» — '
              'ровно на этом и терялись четыре подписки');
      expect(snap.isReadable, isFalse);
      final bad = File('${subsFile().path}.bad');
      expect(bad.existsSync(), isTrue,
          reason: 'улику обязаны сохранить: первое же сохранение затрёт файл');
      expect(bad.readAsStringSync(), original,
          reason: 'содержимое обязано доехать до .bad байт в байт — по нему '
              'подписки и восстанавливают руками');
      expect(subsFile().existsSync(), isFalse,
          reason: 'файл отодвинут, а не скопирован');
      expect(loggedContains('Подписки не прочитаны'), isTrue,
          reason: 'молчаливый откат и был главной бедой');
    });

    test('второй нечитаемый файл не затирает первую улику', () async {
      subsFile().writeAsStringSync('{битый 1');
      await SubscriptionsStore().load();
      subsFile().writeAsStringSync('{битый 2');
      await SubscriptionsStore().load();

      expect(File('${subsFile().path}.bad').readAsStringSync(), '{битый 1',
          reason: 'в SettingsStorage оригинал в этом случае УДАЛЯЕТСЯ; для '
              'подписок это недопустимо');
      expect(File('${subsFile().path}.bad.1').readAsStringSync(), '{битый 2');
    });

    test('⚠️ УЛИКУ НЕ ОТОДВИНУЛИ — ЗАПИСЬ ЗАПРЕЩЕНА ЦЕЛИКОМ', () async {
      // Так выглядит файл, занятый антивирусом: прочитать нельзя, отодвинуть
      // нельзя. Здесь тот же тупик воспроизводится занятыми именами — все
      // запасные слоты уже заняты прошлыми поломками.
      subsFile().writeAsStringSync(fourSubs());
      for (var i = 0; i < 10; i++) {
        final path =
            i == 0 ? '${subsFile().path}.bad' : '${subsFile().path}.bad.$i';
        File(path).writeAsStringSync('улика $i');
      }
      // Сам файл при этом нечитаем.
      subsFile().writeAsStringSync('{обрыв');

      final store = SubscriptionsStore();
      final snap = await store.load();
      expect(snap.isReadable, isFalse);
      expect(store.isSealed, isTrue);

      final saved = await store.save(const SubscriptionsSnapshot([], null));
      expect(saved, isFalse,
          reason: 'перезапись при неудаче чтения обязана быть невозможна');
      expect(subsFile().readAsStringSync(), '{обрыв',
          reason: 'данные на диске остались нетронутыми');
    });

    test('⚠️ БАЙТЫ НЕ РАЗБИРАЮТСЯ В ТЕКСТ — ФАЙЛ ТЕМ БОЛЕЕ НЕ ТРОГАЕМ', () async {
      // `readAsString` падает на первом же неверном байте UTF-8, и такие байты
      // в данных появляются: в `app.log` владельца один `0x82` сделал пустым
      // целый раздел отчёта поддержки. Здесь падение прилетает ДО разбора, то
      // есть мимо `parseContent`, — и путь этот отдельный.
      final original = [0x7b, 0xff, 0xfe, 0x22, 0x69, 0x74, 0x65, 0x6d, 0x73];
      File(subsFile().path).writeAsBytesSync(original);

      final store = SubscriptionsStore();
      final snap = await store.load();

      expect(snap.isReadable, isFalse,
          reason: 'иначе миграция сочла бы это чистой установкой');
      expect(store.isSealed, isTrue);
      expect(File(subsFile().path).readAsBytesSync(), original,
          reason: 'НА ЧТЕНИИ файл не трогаем вовсе: помеха бывает преходящей '
              '(антивирус подержал секунду), и следующий запуск поднимет '
              'подписки сам — а отодвинутый файл этого шанса лишает');
      expect(loggedContains('Файл подписок недоступен'), isTrue);

      // ⚠️ А ВОТ ЗАПИСЬ ТРЕБУЕТ ВЫБОРА, И ОН СДЕЛАН В ПОЛЬЗУ ЧЕЛОВЕКА. Раз
      // сохранение запрошено, значит в сессии есть работа, которую иначе
      // потеряют молча. Удалять при этом не приходится ничего: байты уезжают в
      // `*.bad` целиком, и уже это даёт право писать.
      expect(await store.save(const SubscriptionsSnapshot([], null)), isTrue);
      expect(store.isSealed, isFalse);
      expect(File('${subsFile().path}.bad').readAsBytesSync(), original,
          reason: 'байты могли бы пригодиться для восстановления руками');
    });

    test('⚠️ BOM НА ДИСКЕ: ЛОВИТСЯ ТОЛЬКО ДВОЙНОЙ', () async {
      // ⚠️ ЭТОТ ТЕСТ ЗАМЕНИЛ ПРЕЖНИЙ «BOM от блокнота», КОТОРЫЙ НИЧЕГО НЕ ЛОВИЛ.
      // Ревьюер снял срез BOM в `parseContent` — тест на файле с ОДНИМ BOM
      // остался зелёным, потому что ведущий `EF BB BF` снимает сам декодер
      // UTF-8 внутри `readAsString`. До нашего разбора символ доезжает только
      // тогда, когда BOM в файле не один: декодер снимает первый, второй
      // остаётся в строке.
      final json = utf8.encode(fourSubs());
      const bomBytes = [0xEF, 0xBB, 0xBF];

      subsFile().writeAsBytesSync([...bomBytes, ...json]);
      final single = await SubscriptionsStore().load();
      expect(single.items.length, 4,
          reason: 'одиночный BOM разбирается и без нашей защиты — это работа '
              'декодера, а не среза');

      subsFile().writeAsBytesSync([...bomBytes, ...bomBytes, ...json]);
      final twice = await SubscriptionsStore().load();
      expect(twice.items.length, 4,
          reason: 'вот здесь и работает срез: снимите его — будет ноль подписок '
              'и файл в .bad');
      expect(twice.outcome, SubscriptionsLoadOutcome.loaded);
      expect(File('${subsFile().path}.bad').existsSync(), isFalse,
          reason: 'файл читаем — отодвигать нечего');
    });

    test('⚠️ ОДНА БИТАЯ ЗАПИСЬ: ТЕРЯЕМ ГРОМКО, НО НЕ ТЕРЯЕМ НИЧЕГО', () async {
      // Обратная сторона строгости: раз уж отказываемся поднимать три подписки
      // из четырёх, обязаны сохранить все четыре целиком.
      final raw = jsonEncode({
        'activeId': 'sub_1',
        'items': [
          for (var i = 1; i <= 3; i++)
            {'id': 'sub_$i', 'url': 'https://panel.example/sub/token-$i'},
          {'id': 'sub_4', 'url': 'https://panel.example/sub/token-4',
            'servers': [42]},
        ],
      });
      subsFile().writeAsStringSync(raw);

      final snap = await SubscriptionsStore().load();
      expect(snap.outcome, SubscriptionsLoadOutcome.unreadable);
      expect(File('${subsFile().path}.bad').readAsStringSync(), raw,
          reason: 'все четыре, включая три исправные, лежат в улике целиком — '
              'иначе строгость превратилась бы в потерю');
    });

    group('⚠️ Запрет записи снимается, когда причина ушла', () {
      /// Тупик: файл нечитаем, а все запасные имена заняты. Ровно так выглядит
      /// и файл, который держит антивирус, — отодвинуть нельзя ни тот, ни этот.
      Future<SubscriptionsStore> sealedStore() async {
        for (var i = 0; i < 10; i++) {
          final path =
              i == 0 ? '${subsFile().path}.bad' : '${subsFile().path}.bad.$i';
          File(path).writeAsStringSync('улика $i');
        }
        subsFile().writeAsStringSync('{обрыв');
        final store = SubscriptionsStore();
        await store.load();
        expect(store.isSealed, isTrue, reason: 'предпосылка теста');
        return store;
      }

      test('помеха ушла — запись возобновляется В ТОЙ ЖЕ СЕССИИ', () async {
        // ⚠️ ГЛАВНОЕ ЗДЕСЬ. Печать «на всю сессию» хуже исходной беды: человек
        // работает весь день, интерфейс показывает успех, на диск не уходит
        // НИЧЕГО — и перезапуск стирает всю дневную работу. Причина бывает
        // преходящей (антивирус подержал файл секунду на старте), поэтому
        // каждое сохранение обязано перепроверять запрет.
        final store = await sealedStore();

        // Место под улику освободилось (человек убрал старые `.bad`).
        File('${subsFile().path}.bad.3').deleteSync();

        final ok = await store.save(SubscriptionsSnapshot(
            SubscriptionsStore.parseContent(fourSubs())!.items, 'sub_1'));

        expect(ok, isTrue, reason: 'печать обязана сниматься сама');
        expect(store.isSealed, isFalse);
        expect(File('${subsFile().path}.bad.3').readAsStringSync(), '{обрыв',
            reason: 'право на запись даёт сохранённая улика, а не время');
        expect((await SubscriptionsStore().load()).items.length, 4,
            reason: 'работа сессии обязана доехать до диска');
      });

      test('файла больше нет — терять нечего, пишем', () async {
        final store = await sealedStore();
        subsFile().deleteSync();

        expect(await store.save(const SubscriptionsSnapshot([], null)), isTrue);
        expect(store.isSealed, isFalse);
        expect(subsFile().existsSync(), isTrue);
      });

      test('помеха на месте — запрет держится', () async {
        // Обратная сторона: снимать печать «просто так», потому что прошло
        // время, нельзя — данные на диске от этого не перестают быть
        // непрочитанными.
        final store = await sealedStore();

        expect(await store.save(const SubscriptionsSnapshot([], null)), isFalse);
        expect(store.isSealed, isTrue);
        expect(subsFile().readAsStringSync(), '{обрыв');
        expect(loggedContains('Сохранение подписок пропущено'), isTrue);
      });
    });

    test('обычное сохранение читается обратно', () async {
      final store = SubscriptionsStore();
      subsFile().writeAsStringSync(fourSubs());
      final loaded = await store.load();
      expect(await store.save(loaded), isTrue);

      final again = await SubscriptionsStore().load();
      expect(again.items.map((p) => p.url), loaded.items.map((p) => p.url));
      expect(again.activeId, 'sub_1');
    });
  });
}
