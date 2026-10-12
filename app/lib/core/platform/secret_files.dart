import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart'
    show CRYPT_INTEGER_BLOB, CryptProtectData, CryptUnprotectData, LocalFree;

import '../../data/atomic_file.dart';
import 'app_log.dart';
import 'app_paths.dart';

/// Файл данных не расшифровался (другая учётная запись, другой компьютер,
/// сброс пароля администратором). Сам файл сохранён рядом копией
/// `<имя>.undecryptable` — см. [SecretFiles.read].
class SecretDecodeException implements Exception {
  final String path;
  const SecretDecodeException(this.path);
  @override
  String toString() => 'SecretDecodeException: $path';
}

/// Файлы данных с секретами — подписки, настройки, ссылки серверов — на
/// Windows лежат на диске зашифрованными DPAPI (решение владельца 25.09.2026).
///
/// ЧТО ЭТО ДАЁТ И ЧЕГО НЕ ДАЁТ — честно, чтобы никто не пообещал лишнего:
///  * ✅ копия `%APPDATA%\SilentGate`, ушедшая наружу (резервная копия,
///    синхронизация папки, архив для поддержки, диск другого компьютера,
///    другая учётная запись), без входа под этим пользователем не читается;
///  * ❌ от программы, запущенной под ТЕМ ЖЕ пользователем, DPAPI не защищает:
///    ключ выдаётся любому его процессу. Это граница самой Windows, не наша;
///  * ❌ конфиг ядра на время сессии лежит открытым — ядро читает обычный JSON.
///
/// Секреты в этих файлах не только поля вида «пароль»: ключ сервера — это его
/// share-ссылка с UUID, а по ключам построены и пины, и результаты пинга, и
/// правки серверов. Поэтому шифруется файл целиком, а не отдельные поля.
///
/// Формат — текст: метка [magic] и base64 от блока DPAPI. Файл без метки
/// читается как прежний открытый текст — это и есть миграция: следующая запись
/// стора его зашифрует. Обратно тоже работает: портативная копия и Android
/// пишут открыто и зашифрованное прочитают, если окажутся на той же учётной
/// записи Windows.
///
/// ⚠️ ПОРТАТИВНАЯ КОПИЯ ПИШЕТ ОТКРЫТО. Ключ DPAPI привязан к учётной записи, и
/// флешка, вставленная в другой компьютер, принесла бы туда нечитаемые
/// подписки, — у портативной версии весь смысл в том, чтобы переезжать.
abstract final class SecretFiles {
  /// Метка зашифрованного файла. Версия в метке — на случай смены схемы.
  static const magic = 'SGDPAPI1:';

  /// Дополнительная энтропия DPAPI. Секретом не является (код открыт), но
  /// отделяет наши блоки от чужих: общий для всех программ пользователя
  /// `CryptUnprotectData` без неё их не вскроет.
  static final _entropy = utf8.encode('SilentGate data v1');

  static const _uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN

  /// Принудительно включить или выключить шифрование (тесты). `null` — по
  /// платформе.
  @visibleForTesting
  static bool? debugEnabled;

  /// Шифровать ли при записи: Windows, не портативная копия и не под тестами
  /// (тесты читают файлы сторов глазами; путь DPAPI проверяют свои тесты через
  /// [debugEnabled]).
  static bool get enabled =>
      debugEnabled ??
      (Platform.isWindows &&
          !AppPaths.isPortable &&
          !Platform.environment.containsKey('FLUTTER_TEST'));

  /// Зашифровано ли содержимое файла.
  static bool isEncrypted(String stored) => stored.startsWith(magic);

  /// Текст для записи на диск.
  static String encode(String plain) {
    if (!enabled) return plain;
    final blob = protect(Uint8List.fromList(utf8.encode(plain)));
    return '$magic${base64.encode(blob)}';
  }

  /// Текст из прочитанного с диска. Открытый текст отдаётся как есть.
  ///
  /// Бросает [FormatException], если метка есть, а расшифровать не вышло.
  static String decode(String stored) {
    if (!isEncrypted(stored)) return stored;
    final Uint8List blob;
    try {
      blob = base64.decode(stored.substring(magic.length).trim());
    } on FormatException {
      throw const FormatException('битый base64 в зашифрованном файле');
    }
    final plain = unprotect(blob);
    if (plain == null) {
      throw const FormatException('DPAPI не расшифровал файл');
    }
    return utf8.decode(plain);
  }

  /// Прочитать файл стора.
  ///
  /// ⚠️ НЕРАСШИФРОВАННЫЙ ФАЙЛ СОХРАНЯЕТСЯ КОПИЕЙ. Стор на ошибке чтения
  /// откатывается в пустое состояние, а первое же сохранение перепишет файл —
  /// и подписки, которые ещё можно было бы вернуть (вход под прежней учётной
  /// записью), пропали бы. Копия `<имя>.undecryptable` лежит рядом и не
  /// перезаписывается последующими неудачами.
  static Future<String> read(File file) async {
    final stored = await file.readAsString();
    try {
      return decode(stored);
    } on FormatException catch (e) {
      final keep = File('${file.path}.undecryptable');
      try {
        if (!await keep.exists()) await file.copy(keep.path);
      } catch (_) {}
      AppLog.w('Файл данных не расшифрован (${e.message}): '
          '${file.uri.pathSegments.last}; копия — ${keep.uri.pathSegments.last}');
      throw SecretDecodeException(file.path);
    }
  }

  /// Записать файл стора атомарно (см. [AtomicFile]).
  static Future<bool> write(File file, String plain) {
    final String stored;
    try {
      stored = encode(plain);
    } catch (e) {
      // DPAPI не ответил — лучше не записать, чем записать открыто там, где
      // обещано шифрование. Сторы ошибки записи и так переживают.
      AppLog.w('Шифрование файла данных не удалось: $e');
      return Future.value(false);
    }
    return AtomicFile.writeString(file, stored);
  }

  /// `CryptProtectData` в области текущего пользователя.
  @visibleForTesting
  static Uint8List protect(Uint8List data) {
    final out = _call(data, encrypt: true);
    if (out == null) throw StateError('CryptProtectData вернул ошибку');
    return out;
  }

  /// `CryptUnprotectData`; `null` — не расшифровалось.
  @visibleForTesting
  static Uint8List? unprotect(Uint8List data) => _call(data, encrypt: false);

  static Uint8List? _call(Uint8List data, {required bool encrypt}) {
    final input = calloc<CRYPT_INTEGER_BLOB>();
    final entropy = calloc<CRYPT_INTEGER_BLOB>();
    final output = calloc<CRYPT_INTEGER_BLOB>();
    final inBytes = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final entBytes = calloc<Uint8>(_entropy.length);
    try {
      inBytes.asTypedList(data.length).setAll(0, data);
      entBytes.asTypedList(_entropy.length).setAll(0, _entropy);
      input.ref
        ..cbData = data.length
        ..pbData = inBytes;
      entropy.ref
        ..cbData = _entropy.length
        ..pbData = entBytes;
      final ok = encrypt
          ? CryptProtectData(input, nullptr, entropy, nullptr, nullptr,
              _uiForbidden, output)
          : CryptUnprotectData(input, nullptr, entropy, nullptr, nullptr,
              _uiForbidden, output);
      if (ok == 0) return null;
      try {
        return Uint8List.fromList(
            output.ref.pbData.asTypedList(output.ref.cbData));
      } finally {
        LocalFree(output.ref.pbData);
      }
    } finally {
      calloc.free(inBytes);
      calloc.free(entBytes);
      calloc.free(input);
      calloc.free(entropy);
      calloc.free(output);
    }
  }
}
