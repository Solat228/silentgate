import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Единый каталог данных приложения — ЕДИНСТВЕННАЯ точка платформозависимости
/// всего дискового слоя: восемь сторов, логи, кэши иконок и отчёты поддержки
/// строят пути только отсюда.
///
/// **Windows:** фиксированный `%APPDATA%\SilentGate`, а не
/// `getApplicationSupportDirectory` — сознательно, чтобы установщик и режим
/// `--cleanup` могли гарантированно вычистить данные при удалении.
///
/// **Android:** `getApplicationSupportDirectory()` — путь известен только
/// асинхронно, поэтому перед первым синхронным обращением обязателен [init]
/// (зовётся из `main`). Систему очистки там писать не нужно: данные удаляет
/// сама ОС вместе с приложением.
class AppPaths {
  static const dirName = 'SilentGate';

  static Directory? _cached;

  /// ⚠️ ПОД ТЕСТАМИ БОЕВОЙ КАТАЛОГ НЕ ОТДАЁТСЯ НИКОГДА.
  ///
  /// Стоит здесь, а не в тестах, по той же причине, что барьер секретов стоит в
  /// `LocalApiServer._write`, а не в обработчиках: это ЕДИНСТВЕННОЕ место,
  /// откуда все восемь сторов, логи и кэши узнают путь. Тест, забывший про
  /// изоляцию, обходит любую договорённость молча.
  ///
  /// ⚠️ ЭТО НЕ ПРЕДОСТОРОЖНОСТЬ, А РАЗБОР СЛУЧИВШЕГОСЯ. 14.08.2026 ревью
  /// доказало опытом: `update_on_start_test` поднимал настоящий `AppState`, а
  /// `_maybeRefreshOnStart` уходит в `unawaited` — тест успевал закончиться и
  /// позвать [resetForTests] РАНЬШЕ, чем досчитывала цепочка импорта. Дальше
  /// она резолвила путь заново, получала `%APPDATA%\SilentGate` и переписывала
  /// боевой `subscriptions.json`: 37 КБ с четырьмя реальными подписками
  /// превращались в 501 байт с выдуманной. Данные владельца уцелели только
  /// потому, что клиент был запущен и через 26 минут переписал файл из памяти.
  ///
  /// Тест, которому каталог нужен, объявляет его сам через [overrideRoot];
  /// тест, которому не нужен, получает исключение с адресом лечения, а не
  /// тихую запись в чужие данные.
  static bool get _underTest =>
      Platform.environment.containsKey('FLUTTER_TEST') &&
      !_productionRootAllowedInTests;

  /// Единственное законное исключение — тест САМОГО этого класса: проверить
  /// вычисление боевого пути, не вычислив его, нельзя. Названо длинно нарочно,
  /// чтобы его не поставили «чтобы тест позеленел»: любому другому тесту нужен
  /// [overrideRoot], а не это.
  @visibleForTesting
  static bool productionRootAllowedInTests = false;

  static bool get _productionRootAllowedInTests => productionRootAllowedInTests;

  /// Разово вычисляет корень данных. Вызывать из `main` ДО построения UI и
  /// любых сторов. Идемпотентна; на Windows не обязательна (там путь
  /// вычисляется синхронно), на Android — обязательна.
  static Future<Directory> init() async {
    final known = _cached;
    if (known != null) return known;

    if (_underTest) _refuseProductionRoot('AppPaths.init()');

    Directory dir;
    if (Platform.isWindows) {
      dir = Directory(_windowsBase());
    } else {
      try {
        final base = await getApplicationSupportDirectory();
        dir = Directory('${base.path}${Platform.pathSeparator}$dirName');
      } catch (_) {
        // Сюда попадают host-тесты вне Flutter-биндингов (плагина нет,
        // MissingPluginException) и отказ платформы отдать каталог — уходим во
        // временную папку, как и при пустом APPDATA на Windows.
        dir = Directory(_tempBase());
      }
    }
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _cached = dir;
  }

  /// Подменить корень данных (тесты и изолированные копии).
  ///
  /// На Windows изоляция исторически делается подменой переменной `APPDATA`;
  /// на других платформах переменной среды нет, поэтому нужен явный хук.
  static void overrideRoot(Directory dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cached = dir;
  }

  /// Сбросить кэш (между тестами).
  static void resetForTests() => _cached = null;

  static Directory supportDirSync() {
    final known = _cached;
    if (known != null) return known;

    if (_underTest) _refuseProductionRoot('AppPaths.supportDirSync()');

    // Windows умеет вычислить путь синхронно — сохраняем прежнее поведение
    // (и работоспособность до вызова init, например в режиме `--cleanup`).
    if (Platform.isWindows) {
      final dir = Directory(_windowsBase());
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return _cached = dir;
    }

    throw StateError(
      'AppPaths.init() не был вызван: на ${Platform.operatingSystem} корень '
      'данных известен только асинхронно. Вызовите AppPaths.init() в main() '
      'до обращения к хранилищам.',
    );
  }

  static Future<Directory> supportDir() async => _cached ?? await init();

  /// Имя файла-метки портативной сборки. Лежит рядом с `silentgate.exe`.
  ///
  /// ⚠️ ИМЕННО ФАЙЛ-МЕТКА, А НЕ ФЛАГ СБОРКИ. Портативная и обычная версии — один
  /// и тот же бинарник: так их невозможно перепутать при выпуске, и человек
  /// может сделать портативную сам, положив файл рядом. Обратное тоже верно:
  /// удалил метку — приложение вернулось к общему каталогу и увидело прежние
  /// подписки.
  static const portableMarker = 'portable.txt';

  /// Каталог данных портативной сборки — рядом с exe.
  ///
  /// ⚠️ НЕ `data`, И ЭТО НЕ ПРИДИРКА. `data` — СОБСТВЕННАЯ папка Flutter в
  /// windows-сборке: там лежат `app.so`, `icudtl.dat` и ресурсы. Первая
  /// редакция портативного режима писала именно туда — поймано живым запуском.
  /// Цена ошибки: обновление портативной версии делается распаковкой архива
  /// ПОВЕРХ, а `data` при этом обязана перезаписаться целиком — вместе с
  /// подписками, настройками и журналом пользователя.
  static const portableDirName = 'sg-data';

  /// Портативный корень: `<каталог с exe>\sg-data`, если рядом лежит метка.
  ///
  /// ⚠️ ЗАЧЕМ. У «покет»-версии смысл ровно один — не оставлять следов на чужой
  /// машине. Если данные всё равно уходят в `%APPDATA%`, портативность
  /// оказывается обещанием, которого нет: подписки, ключи локальных портов и
  /// журнал останутся на рабочем компьютере после того, как флешку вынули.
  ///
  /// ⚠️ ПРОВЕРЯЕМ ВОЗМОЖНОСТЬ ПИСАТЬ, А НЕ ТОЛЬКО НАЛИЧИЕ МЕТКИ. Портативную
  /// версию носят на флешках и запускают из папок, куда писать нельзя (`Program
  /// Files`, диск только на чтение). Молча оказаться без данных хуже, чем
  /// откатиться в `%APPDATA%`: там приложение хотя бы работает.
  static String? _portableBase() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final marker = File('$exeDir${Platform.pathSeparator}$portableMarker');
      if (!marker.existsSync()) return null;
      final dir = Directory('$exeDir${Platform.pathSeparator}$portableDirName');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      // Пробная запись: право на создание каталога ещё не значит право писать
      // в него (сетевые диски, наследование запретов).
      final probe = File('${dir.path}${Platform.pathSeparator}.writable');
      probe.writeAsStringSync('');
      probe.deleteSync();
      return dir.path;
    } catch (_) {
      return null;
    }
  }

  static String _windowsBase() {
    final portable = _portableBase();
    if (portable != null) return portable;
    final appData = Platform.environment['APPDATA'];
    return (appData != null && appData.isNotEmpty)
        ? '$appData${Platform.pathSeparator}$dirName'
        : _tempBase();
  }

  static String _tempBase() =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}$dirName';

  static Never _refuseProductionRoot(String caller) => throw StateError(
        '$caller под тестами: корень данных не задан.\n'
        'Тест обратился к каталогу данных, не объявив свой, — а боевой здесь '
        'отдавать нельзя: именно так тест переписал реальный '
        'subscriptions.json владельца (14.08.2026).\n'
        'Лечение в setUp:\n'
        "  final tmp = Directory.systemTemp.createTempSync('sg_test_');\n"
        '  AppPaths.overrideRoot(tmp);\n'
        'и в tearDown — AppPaths.resetForTests() плюс удаление tmp.\n'
        '⚠️ Если падение прилетело ПОСЛЕ окончания теста, каталог сбросили '
        'раньше, чем досчитала фоновая цепочка (unawaited): дождитесь её до '
        'resetForTests, иначе путь резолвится заново уже без подмены.',
      );
}
