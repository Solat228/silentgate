import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/android/platform_services_android.dart';

/// ВЕРСИЯ XRAY В «О ПРОГРАММЕ» НА ANDROID.
///
/// ⚠️ ЧТО СТЕРЕЖЁТСЯ. Поле Xray в `coreVersions` (канал `lol.silentgate/device`)
/// с самого появления AAR было заглушкой `"xray" to null` с комментарием
/// «формат конверта не разобран — честно ставим прочерк». Формат разобран по
/// исходнику libXray (`invoke.go` / `invoke_model.go`): команда `xrayVersion`,
/// ответ `{"success":true,"data":{"version":"…"},"error":""}`. Заглушка снята,
/// и вернуть её незаметно нельзя — версия ядра нужна при разборе жалоб
/// («на каком Xray сидит телефон»), а прочерк там неотличим от честного «н/д».
///
/// ⚠️ ПОЧЕМУ ЧАСТЬ СТРАЖА ЧИТАЕТ ИСХОДНИК KOTLIN, А НЕ ПРОВЕРЯЕТ ПОВЕДЕНИЕ.
/// `flutter test` Kotlin не компилирует и не запускает; в этом проекте ошибку
/// в Kotlin уже ловила ТОЛЬКО сборка APK — на полчаса позже и без подсказки.
/// Чтение текста — единственная проверка, доступная до сборки. Сам разбор
/// ответа ядра здесь не прогнать: проверяется на эмуляторе глазами.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const device = MethodChannel('lol.silentgate/device');

  void mockVersions(Map<String, dynamic>? Function() reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, (call) async {
      if (call.method != 'coreVersions') return null;
      return reply();
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, null);
  });

  group('Dart: разбор ответа канала coreVersions', () {
    final versions = buildAndroidPlatformServices().coreVersions;

    test('обе версии на месте → «xray / sing-box …»', () async {
      mockVersions(() => {'xray': '26.3.27', 'singbox': '1.13.14'});
      expect(await versions.xray(), '26.3.27 / sing-box 1.13.14');
    });

    test('Xray null → показывается только sing-box, без слова «null»', () async {
      // Ровно то, что видел пользователь всё время, пока стояла заглушка:
      // sing-box есть, Xray — нет. Слово «null» в интерфейсе недопустимо.
      mockVersions(() => {'xray': null, 'singbox': '1.13.14'});
      final s = await versions.xray();
      expect(s, 'sing-box 1.13.14');
      expect(s.contains('null'), isFalse);
    });

    test('только Xray → голая версия', () async {
      mockVersions(() => {'xray': '26.3.27', 'singbox': null});
      expect(await versions.xray(), '26.3.27');
    });

    test('обе null → прочерк «н/д»', () async {
      mockVersions(() => {'xray': null, 'singbox': null});
      expect(await versions.xray(), 'н/д');
    });

    test('пробелы вокруг версии срезаются', () async {
      mockVersions(() => {'xray': ' 26.3.27 ', 'singbox': ''});
      expect(await versions.xray(), '26.3.27');
    });

    test('канал бросил → прочерк, а не исключение в build', () async {
      mockVersions(() => throw PlatformException(code: 'boom'));
      expect(await versions.xray(), 'н/д');
    });
  });

  group('⚠️ Kotlin: заглушка «"xray" to null» снята', () {
    const kt =
        'android/app/src/main/kotlin/lol/silentgate/platform/PlatformChannels.kt';

    /// Текст без строк-комментариев: страж не должен ловить сам себя на
    /// собственных пояснениях (в них «"xray" to null» упоминается как история).
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
        })
        .join(String.fromCharCode(10));

    /// Ветка `"coreVersions" -> …` до следующего обработчика канала.
    String coreVersionsBranch(String src) {
      final start = src.indexOf('"coreVersions" ->');
      expect(start, greaterThanOrEqualTo(0),
          reason: 'ветка coreVersions не найдена — страж проверял бы пустоту');
      final next = RegExp(r'\n\s*"[A-Za-z]+" ->').firstMatch(src.substring(start + 1));
      return next == null
          ? src.substring(start)
          : src.substring(start, start + 1 + next.start);
    }

    test('файл на месте', () {
      expect(File(kt).existsSync(), isTrue);
    });

    test('в ветке coreVersions нет безусловного null у Xray', () {
      final branch = coreVersionsBranch(code(kt));
      expect(branch.contains('"xray" to null'), isFalse,
          reason: 'это и была заглушка: прочерк вместо версии ядра');
      expect(branch, contains('"xray" to runCatching'),
          reason: 'версия Xray берётся вызовом, и любой его сбой обязан '
              'превращаться в null, а не ронять весь coreVersions '
              '(иначе пропадёт и sing-box)');
      expect(branch, contains('xrayVersion()'),
          reason: 'ветка обязана звать функцию версии Xray');
    });

    test('версия Xray идёт через конверт LibXray.invoke с командой xrayVersion',
        () {
      final src = code(kt);
      // Имя команды — ровно то, что в `invoke_model.go` libXray
      // (`LibXrayMethodXrayVersion = "xrayVersion"`). Другой регистр или
      // подчёркивание — ядро ответит `unknown method`, и прочерк вернётся.
      expect(src, contains('const val XRAY_VERSION_METHOD = "xrayVersion"'));

      final fnAt = src.indexOf('fun xrayVersion(');
      expect(fnAt, greaterThanOrEqualTo(0), reason: 'функция версии не найдена');
      final body = src.substring(fnAt, src.indexOf('\n    }', fnAt));
      expect(body, contains('LibXray.invoke('),
          reason: 'отдельного метода версии у биндинга нет — только конверт');
      expect(body, contains(r'$XRAY_VERSION_METHOD'),
          reason: 'в конверт обязана уходить именно эта команда, а не копия строки');
    });

    test('разбор ответа: success:false и пустая версия дают null', () {
      final src = code(kt);
      final fnAt = src.indexOf('fun parseXrayVersion(');
      expect(fnAt, greaterThanOrEqualTo(0));
      final body = src.substring(fnAt, src.indexOf('\n    }', fnAt));
      // Служебный отказ ядра (`{"success":false,…,"error":"…"}`) не имеет
      // версии по определению — выдавать оттуда что-либо нельзя.
      expect(body, contains('"success"'));
      expect(body, contains('"version"'));
      expect(body, contains('ifEmpty { null }'),
          reason: 'пустая строка версии — тот же прочерк, а не «версия ""»');
    });

    test('имя команды совпадает с исходником libXray (если он на машине)', () {
      // Единственная автоматическая связь с правдой: константа libXray.
      // Исходники лежат вне репозитория (рецепт — tools/build-android-cores.md),
      // поэтому на чужой машине проверка честно пропускается, а не молчит.
      final model = File(r'C:\dev\android\src\libXray\invoke_model.go');
      if (!model.existsSync()) {
        markTestSkipped('исходники libXray не найдены: C:\\dev\\android\\src\\libXray');
        return;
      }
      final go = model.readAsStringSync();
      final m = RegExp(r'LibXrayMethodXrayVersion\s+LibXrayMethod\s*=\s*"([^"]+)"')
          .firstMatch(go);
      expect(m, isNotNull, reason: 'в libXray нет команды версии — формат сменился');
      expect(code(kt), contains('const val XRAY_VERSION_METHOD = "${m!.group(1)}"'));
    });
  });
}
