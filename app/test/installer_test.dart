import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_instance_mutex.dart';

/// СТРАЖ УСТАНОВЩИКА.
///
/// ⚠️ РАДИ ЧЕГО. Всё, что проверяется ниже, — это договорённости МЕЖДУ файлами,
/// которые не связаны ничем: скрипт Inno не компилируется вместе с Dart, а
/// сервер обновлений вообще живёт на другой машине. Ни компилятор, ни
/// анализатор, ни один из 1500 остальных тестов не заметят, если стороны
/// разъедутся, — а расплата приходит в готовой поставке.
///
/// Каждый пункт ниже соответствует дефекту, ПОЙМАННОМУ ЖИВЫМ ПРОГОНОМ в VM
/// `SG-Test` 16.08.2026, а не выдуманному сценарию.
void main() {
  final iss = File('../installer/silentgate.iss');
  final text = iss.existsSync() ? iss.readAsStringSync() : '';

  setUpAll(() {
    expect(iss.existsSync(), isTrue,
        reason: 'скрипт установщика — часть поставки, тест обязан его видеть');
  });

  /// Значения в `.iss` пишутся через макросы препроцессора (`{#MyAppSite}`),
  /// поэтому сырую строку сверять бессмысленно — разворачиваем `#define`, как
  /// это сделает ISCC. Иначе тест проверял бы наличие макроса, а не значения.
  final defines = {
    for (final m in RegExp(r'^#define\s+(\w+)\s+"([^"]*)"', multiLine: true)
        .allMatches(text))
      m.group(1)!: m.group(2)!,
  };

  String expand(String v) {
    var out = v;
    for (final e in defines.entries) {
      out = out.replaceAll('{#${e.key}}', e.value);
    }
    return out;
  }

  String? setting(String key) {
    final m = RegExp('^$key=(.*)\$', multiLine: true).firstMatch(text);
    final raw = m?.group(1)?.trim();
    return raw == null ? null : expand(raw);
  }

  group('Обновление поверх запущенного приложения', () {
    test('⚠️ ГЛАВНОЕ: имя мьютекса в приложении и в установщике — одно', () {
      // Разойдутся — установщик перестанет замечать запущенное приложение и
      // вернётся ровно к тому отказу, ради которого мьютекс и заводили:
      // код возврата 5, версия на диске прежняя, объяснения нет.
      expect(setting('AppMutex'), AppInstanceMutex.name);
    });

    test('мьютекс годен как имя объекта ядра', () {
      // Обратный слэш разделяет пространство имён (`Global\...`), поэтому
      // внутри имени он недопустим; пустое имя ядро молча примет за анонимный
      // объект, который установщику не найти никогда.
      expect(AppInstanceMutex.name, isNotEmpty);
      expect(AppInstanceMutex.name, isNot(contains(r'\')));
    });

    test('Restart Manager оставлен включённым', () {
      // Он бесполезен против свёрнутого в трей окна, но нужен там, где окна
      // нет вовсе. Мьютекс его не заменяет, а страхует.
      expect(setting('CloseApplications'), 'yes');
    });

    test('⚠️ приложение НЕ перезапускается установщиком само', () {
      // Оно поднимает VPN и просит UAC под TUN: всплывший сам собой запрос
      // прав после установки читается как чужое вмешательство.
      expect(setting('RestartApplications'), 'no');
    });
  });

  group('Откат назад не проходит молча', () {
    test('⚠️ ГЛАВНОЕ: сравнение версий вообще есть', () {
      // Inno сам версии НЕ сравнивает. Живой прогон: установщик 1.4.3 поверх
      // установленной 1.5.1 откатил программу назад с кодом возврата 0 —
      // ни вопроса, ни предупреждения.
      expect(text, contains('function CompareVersions'));
      expect(text, contains('function InitializeSetup'));
    });

    test('версии сравниваются по числам, а не по строкам', () {
      // Строкой «1.4.10» меньше «1.4.9». Ту же ловушку уже стережёт
      // app_update_test.dart для проверки обновлений внутри приложения.
      expect(text, contains('StrToIntDef'));
    });

    test('GUID установки задан один раз', () {
      // [Code] ищет установленную версию по ключу `<AppId>_is1`. Второй литерал
      // GUID означал бы, что проверка отката однажды начнёт смотреть не туда и
      // замолчит, ничего не сломав заметно.
      final guids = RegExp(r'B7F3B2A1-5C2E-4E7A-9F1D-51E4C0DE0001')
          .allMatches(text)
          .length;
      expect(guids, 1, reason: 'GUID обязан жить в #define MyAppId');
    });

    test('тихий режим остаётся пригодным для автоматизации', () {
      // Вопросы в /SILENT задавать некому: там их никто не увидит, а установка
      // повиснет. Ветка обязана существовать явно.
      expect(text, contains('WizardSilent'));
    });
  });

  group('Обещанное поставкой', () {
    test('⚠️ имя файла сверено с сервером обновлений', () {
      // Эндпоинт /api/app-version ссылается на SilentGateSetup-<версия>.exe
      // (docs/APP_UPDATE_SERVER.md §3). Лишний дефис здесь = 404 по кнопке
      // «Скачать» у каждого пользователя.
      expect(setting('OutputBaseFilename'), 'SilentGateSetup-{#ShortVersion}');
    });

    test('в имени файла три числа, без номера сборки', () {
      expect(text, contains('#define ShortVersion'));
      expect(text, contains('RPos(".", MyAppVersion)'));
    });

    test('⚠️ путь к сборке задаётся снаружи и не переопределяется молча', () {
      // Без #ifndef строка в репозитории побеждала аргумент /DReleaseDir, и
      // 16.08.2026 из папки 1.4.3 собрался установщик с именем 1.5.1.
      expect(text, contains('#ifndef ReleaseDir'));
    });

    test('текст лицензии показывается и существует', () {
      // Клиент под GPL-3.0: текст обязан ехать с поставкой.
      final lic = setting('LicenseFile');
      expect(lic, isNotNull);
      expect(File('../installer/${lic!}').existsSync(), isTrue,
          reason: 'путь в .iss считается от папки скрипта');
    });

    test('значок установщика существует', () {
      final ico = setting('SetupIconFile');
      expect(ico, isNotNull);
      expect(File('../installer/${ico!}').existsSync(), isTrue);
    });

    test('ссылки на сайт и поддержку заполнены', () {
      // Пустыми они и были: человек, нашедший SilentGate в списке
      // установленного, никуда не мог из него уйти.
      for (final k in ['AppPublisherURL', 'AppSupportURL', 'AppUpdatesURL']) {
        expect(setting(k), startsWith('https://'), reason: '$k пуст');
      }
    });

    test('данные пользователя удаляются при удалении программы', () {
      expect(text, contains(r'Type: filesandordirs; Name: "{userappdata}\SilentGate"'));
      expect(text, contains('--cleanup'));
    });
  });

  group('Языки мастера', () {
    List<String> languages() =>
        RegExp(r'^Name: "(\w+)"; MessagesFile:', multiLine: true)
            .allMatches(text)
            .map((m) => m.group(1)!)
            .toList();

    test('⚠️ ГЛАВНОЕ: перевод есть у КАЖДОГО объявленного языка', () {
      // Недостающий перевод Inno подставляет из ПЕРВОГО объявленного языка
      // (у нас — русского) и сообщает об этом всего лишь предупреждением:
      // сборка считается успешной, а француз видит русский текст. Ровно так и
      // вышло при первой компиляции 16.08.2026 — 17 предупреждений, exit 0.
      // Тот же принцип, что у l10n_test.dart для ARB: половинчатый перевод
      // обязан ронять тест, а не проходить незамеченным.
      final byKey = <String, Set<String>>{};
      for (final m in RegExp(r'^(\w+)\.(\w+)=', multiLine: true)
          .allMatches(text.split('[CustomMessages]').last)) {
        byKey.putIfAbsent(m.group(2)!, () => <String>{}).add(m.group(1)!);
      }
      expect(byKey, isNotEmpty, reason: 'секция [CustomMessages] не разобралась');
      for (final e in byKey.entries) {
        expect(e.value, containsAll(languages()),
            reason: 'у сообщения ${e.key} нет перевода на '
                '${languages().toSet().difference(e.value).join(", ")}');
      }
    });

    test('⚠️ файл в UTF-8 с BOM', () {
      // Inno 6 определяет кодировку по BOM; без него берётся системная кодовая
      // страница (на машине владельца — cp1251), и весь нелатинский текст —
      // русский, турецкий, арабский — превращается в мусор. Свежий ISCC UTF-8
      // распознаёт и без BOM, но полагаться на недокументированное
      // автоопределение в файле с восемью языками не за чем.
      final head = iss.readAsBytesSync().take(3).toList();
      expect(head, [0xEF, 0xBB, 0xBF]);
    });

    test('⚠️ восемь языков — потолок поставки Inno, а не недоработка', () {
      // Приложение знает 10 языков; в Inno 6 нет ни фарси, ни китайского.
      // Тест зафиксирован, чтобы «недостающие два» не считали забытыми.
      final langs = RegExp(r'^Name: "(\w+)"; MessagesFile:', multiLine: true)
          .allMatches(text)
          .map((m) => m.group(1))
          .toList();
      expect(langs, containsAll(['ru', 'en', 'es', 'fr', 'de', 'pt', 'tr', 'ar']));
      expect(langs, isNot(contains('fa')));
      expect(langs, isNot(contains('zh')));
    });
  });

  group('Мьютекс берёт не всякая копия', () {
    test('портативная и изолированная копии установку не блокируют', () {
      // Они не держат файлов в {app}: портативная живёт на флешке,
      // изолированная заводится именно ради невмешательства.
      final src =
          File('lib/core/platform/app_instance_mutex.dart').readAsStringSync();
      expect(src, contains('AppEnv.portOffset == 0'));
      expect(src, contains('_isPortable'));
    });

    test('сбой мьютекса не мешает приложению запуститься', () {
      final src =
          File('lib/core/platform/app_instance_mutex.dart').readAsStringSync();
      expect(src, contains('catch'),
          reason: 'без мьютекса приложение работает точно так же — хуже '
              'становится только обновлению поверх');
    });
  });
}
