import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/geo/sha256.dart';
import 'package:silentgate/core/update/release_signing.dart';
import 'package:silentgate/core/update/update_manifest.dart';
import 'package:silentgate/core/update/update_signature.dart';

/// ИНСТРУМЕНТ ПОДПИСИ РЕЛИЗА: ТО, ЧТО ОН ПИШЕТ, ПРИЛОЖЕНИЕ ПРИМЕТ.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. `tool/sign_release.dart` и проверка в приложении
/// — два конца одного контракта, и они никогда не компилируются вместе:
/// инструмент запускается владельцем руками при выпуске. Расхождение (другой
/// хэш, другая сериализация, подпись не над теми байтами) обнаружилось бы у
/// пользователей — «обновление не устанавливается» на каждом релизе.
/// Поэтому логика вынесена в `release_signing.dart`, и здесь она прогоняется
/// на временных файлах СВОИМ ключом: файл владельца из `signing/` тест не
/// читает никогда.
void main() {
  late Directory tmp;
  final seed = List<int>.generate(32, (i) => (i * 17 + 5) & 0xff);
  final pubBase64 = base64
      .encode(ed.public(ed.newKeyFromSeed(Uint8List.fromList(seed))).bytes);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_sign_release_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) =>
      File('${tmp.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(bytes);

  group('buildManifest', () {
    test('размер и sha256 каждого файла совпадают с Sha256.ofFile', () async {
      final a = write('SilentGateSetup-1.14.1.exe',
          List<int>.generate(70000, (i) => (i * 7) & 0xff));
      final b = write('SilentGate-1.14.1-arm64-v8a.apk', utf8.encode('apk'));
      final m = await buildManifest('1.14.1', 'stable', [a, b]);

      expect(m.version, '1.14.1');
      expect(m.channel, 'stable');
      expect(m.assets, hasLength(2));

      final ma = m.assetNamed('SilentGateSetup-1.14.1.exe')!;
      expect(ma.size, 70000);
      expect(ma.sha256, await Sha256.ofFile(a));

      final mb = m.assetNamed('SilentGate-1.14.1-arm64-v8a.apk')!;
      expect(mb.size, 3);
      expect(mb.sha256, await Sha256.ofFile(b));
      expect(mb.sha256, Sha256.ofBytes(utf8.encode('apk')));
    });

    test('имя актива — базовое имя файла, без каталога', () async {
      final f = write('SilentGateSetup-1.14.1.exe', [1, 2, 3]);
      final m = await buildManifest('1.14.1', 'stable', [f]);
      expect(m.assets.single.name, 'SilentGateSetup-1.14.1.exe');
    });

    test('версия нормализуется: ведущий v снимается', () async {
      final f = write('x.exe', [1]);
      final m = await buildManifest('v1.14.1', 'stable', [f]);
      expect(m.version, '1.14.1');
    });

    test('результат проходит validateManifest для каждого актива', () async {
      final f = write('SilentGateSetup-1.14.1.exe', [1, 2, 3]);
      final m = await buildManifest('1.14.1', 'beta', [f]);
      expect(
        validateManifest(m,
            expectedVersion: '1.14.1',
            assetName: 'SilentGateSetup-1.14.1.exe',
            betaAllowed: true),
        isNull,
      );
    });

    test('неизвестный канал — ArgumentError до чтения файлов', () async {
      final f = write('x.exe', [1]);
      expect(
          () => buildManifest('1.14.1', 'nightly', [f]), throwsArgumentError);
    });

    test('пустой список файлов — ArgumentError', () async {
      expect(() => buildManifest('1.14.1', 'stable', const []),
          throwsArgumentError);
    });

    test('два файла с одним именем — ArgumentError', () async {
      // Приложение ищет актив по имени; два одинаковых имени с разными
      // хэшами — манифест, у которого нет однозначного ответа.
      final sub = Directory('${tmp.path}${Platform.pathSeparator}sub')
        ..createSync();
      final a = write('same.exe', [1]);
      final b = File('${sub.path}${Platform.pathSeparator}same.exe')
        ..writeAsBytesSync([2]);
      expect(
          () => buildManifest('1.14.1', 'stable', [a, b]), throwsArgumentError);
    });

    test('пустая версия — ArgumentError', () async {
      final f = write('x.exe', [1]);
      expect(() => buildManifest('  ', 'stable', [f]), throwsArgumentError);
    });
  });

  group('signManifestBytes', () {
    test('подпись над байтами манифеста проверяется своим публичным ключом',
        () async {
      final f = write('SilentGateSetup-1.14.1.exe', [9, 8, 7]);
      final m = await buildManifest('1.14.1', 'stable', [f]);
      final bytes = utf8.encode(m.toJson());
      final sig = signManifestBytes(bytes, seed);
      expect(UpdateSignature.verify(bytes, sig, publicKeyBase64: pubBase64),
          isTrue);
    });

    test('подмена одного байта манифеста → verify false', () async {
      final f = write('SilentGateSetup-1.14.1.exe', [9, 8, 7]);
      final m = await buildManifest('1.14.1', 'stable', [f]);
      final bytes = utf8.encode(m.toJson());
      final sig = signManifestBytes(bytes, seed);

      // Меняем цифру размера — самая «безобидная» на вид подмена.
      final text = m.toJson().replaceFirst('"size":3', '"size":4');
      expect(text, isNot(m.toJson()));
      expect(
        UpdateSignature.verify(utf8.encode(text), sig,
            publicKeyBase64: pubBase64),
        isFalse,
      );
    });

    test('подпись — base64 ровно 64 байт', () {
      final sig = signManifestBytes(utf8.encode('{}'), seed);
      expect(base64.decode(sig), hasLength(64));
    });
  });

  group('parseSeed', () {
    test('одна строка base64 с переводом строки → 32 байта', () {
      expect(parseSeed('${base64.encode(seed)}\n'), seed);
      expect(parseSeed('${base64.encode(seed)}\r\n'), seed);
      expect(parseSeed('  ${base64.encode(seed)}  '), seed);
    });

    test('не 32 байта или не base64 → FormatException', () {
      expect(() => parseSeed(''), throwsFormatException);
      expect(() => parseSeed('???'), throwsFormatException);
      expect(() => parseSeed(base64.encode(List<int>.filled(31, 0))),
          throwsFormatException);
      expect(() => parseSeed(base64.encode(List<int>.filled(64, 0))),
          throwsFormatException);
    });
  });

  group('имена файлов манифеста', () {
    test('по версии без v, для беты — полный тег', () {
      expect(manifestFileName('1.14.1'), 'SilentGate-1.14.1.manifest.json');
      expect(signatureFileName('1.14.1'), 'SilentGate-1.14.1.manifest.sig');
      expect(manifestFileName('v1.14.1-beta.1'),
          'SilentGate-1.14.1-beta.1.manifest.json');
    });
  });

  group('writeSignedManifest', () {
    test('пишет .json и .sig рядом с первым файлом; sig — над байтами .json',
        () async {
      final sub = Directory('${tmp.path}${Platform.pathSeparator}out')
        ..createSync();
      final f =
          File('${sub.path}${Platform.pathSeparator}SilentGateSetup-1.14.1.exe')
            ..writeAsBytesSync([1, 2, 3, 4]);
      final m = await buildManifest('1.14.1', 'stable', [f]);
      final written = writeSignedManifest(m, seed, besides: f);

      expect(written.manifest.path,
          '${sub.path}${Platform.pathSeparator}SilentGate-1.14.1.manifest.json');
      expect(written.signature.path,
          '${sub.path}${Platform.pathSeparator}SilentGate-1.14.1.manifest.sig');

      final jsonBytes = written.manifest.readAsBytesSync();
      final sig = written.signature.readAsStringSync().trim();
      expect(UpdateSignature.verify(jsonBytes, sig, publicKeyBase64: pubBase64),
          isTrue);
      // Файл манифеста читается обратно тем же разбором, что в приложении.
      final back = UpdateManifest.parse(utf8.decode(jsonBytes));
      expect(back, isNotNull);
      expect(back!.assetNamed('SilentGateSetup-1.14.1.exe')?.size, 4);
    });

    // Инструмент после записи сверяет подпись с ключом, ВШИТЫМ в приложение:
    // чужой ключ в signing/ дал бы релиз, который не примет ни одна копия.
    test('signedManifestVerifies: свой ключ — да, вшитый чужой — нет',
        () async {
      final f =
          File('${tmp.path}${Platform.pathSeparator}SilentGateSetup-1.14.2.exe')
            ..writeAsBytesSync([5, 6, 7]);
      final m = await buildManifest('1.14.2', 'stable', [f]);
      final written = writeSignedManifest(m, seed, besides: f);
      expect(
          signedManifestVerifies(written, publicKeyBase64: pubBase64), isTrue);
      // Тестовый seed не парный боевому ключу — сверка с умолчанием обязана
      // отказать (это и ловит перепутанный ключ перед публикацией).
      expect(signedManifestVerifies(written), isFalse);
      // Подпись испорчена на диске — тоже отказ, а не исключение.
      written.signature.writeAsStringSync('not-base64!!');
      expect(
          signedManifestVerifies(written, publicKeyBase64: pubBase64), isFalse);
    });
  });
}
