import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/platform/app_log.dart';

/// Управление системным прокси Windows (WinINET) через реестр + уведомление
/// wininet.dll о смене настроек. Это MVP-способ перехвата трафика: без TUN-драйвера
/// и без прав администратора. Применяется к WinINET/WinHTTP-приложениям (браузеры и др.).
///
/// Полный перехват (включая UDP и приложения, игнорирующие прокси) — это TUN-режим (этап M5).
class SystemProxy {
  static const String _regKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  // Маркер «прокси установлен нами» — чтобы восстановиться после аварийного выхода.
  static File get _markerFile => File(markerPathOverride ??
      '${Directory.systemTemp.path}\\silentgate_proxy.lock');

  /// Путь маркера. Подменяется ТОЛЬКО тестами.
  ///
  /// ⚠️ МАРКЕР — БОЕВОЕ СОСТОЯНИЕ, А НЕ ВРЕМЕННЫЙ ФАЙЛ. По нему следующий
  /// запуск понимает, что прошлый упал с включённым прокси, и снимает его.
  /// Тест, писавший в общий `%TEMP%`, стёр бы настоящий маркер владельца —
  /// и его приложение после аварии не восстановилось бы, оставив машину без
  /// интернета и без единого объяснения в журнале.
  @visibleForTesting
  static String? markerPathOverride;

  /// Установить системный прокси на host:port (обычно 127.0.0.1:10809).
  ///
  /// ⚠️ ВОЗВРАЩАЕТ УСПЕХ, А НЕ `void`, И ЭТО НЕ КОСМЕТИКА. Раньше `reg add`
  /// запускался и его код возврата не смотрел никто: при отказе (политика
  /// домена, повреждённый профиль, запрет записи в HKCU) приложение считало
  /// перехват включённым, показывало «Подключено», а трафик шёл мимо туннеля
  /// — под реальным адресом. Молчаливый провал ровно того способа захвата,
  /// который стоит по умолчанию.
  static Future<bool> set(String hostPort) async {
    final ok = await _reg(
            'адрес прокси', ['/v', 'ProxyServer', '/t', 'REG_SZ', '/d', hostPort, '/f']) &&
        await _reg('список исключений', [
          '/v', 'ProxyOverride', '/t', 'REG_SZ',
          '/d', 'localhost;127.*;10.*;172.16.*;192.168.*;<local>', '/f',
        ]) &&
        await _reg('включение прокси',
            ['/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
    _notifyChanged();
    try {
      _markerFile.writeAsStringSync(hostPort);
    } catch (e) {
      // Маркер — единственный след «мы включили прокси» для следующего
      // запуска. Без него авария оставит пользователя без интернета, и понять
      // почему будет нечем.
      AppLog.w('Системный прокси: маркер не записан ($e) — '
          'после аварийного выхода прокси придётся снять вручную');
    }
    if (ok) {
      AppLog.i('Системный прокси включён: $hostPort');
    } else {
      AppLog.e('Системный прокси НЕ включён — трафик пойдёт мимо туннеля');
    }
    return ok;
  }

  /// Снять системный прокси.
  static Future<bool> clear() async {
    final ok = await _reg(
        'выключение прокси', ['/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
    _notifyChanged();
    try {
      if (_markerFile.existsSync()) _markerFile.deleteSync();
    } catch (_) {}
    // ⚠️ Неснятый прокси — это «интернет пропал вообще»: система продолжает
    // слать всё на порт, которого больше нет. Такая жалоба обязана иметь в
    // журнале свою строку, иначе она неотличима от поломки провайдера.
    if (ok) {
      AppLog.i('Системный прокси снят');
    } else {
      AppLog.e('Системный прокси НЕ снят — интернет может не работать, '
          'пока настройки прокси Windows не выключены вручную');
    }
    return ok;
  }

  /// Восстановление при старте: если прошлый запуск упал с включённым прокси,
  /// маркер остался — снимаем прокси, чтобы у пользователя не «пропал» интернет.
  static Future<void> recoverIfDirty() async {
    try {
      if (_markerFile.existsSync()) {
        // ⚠️ САМАЯ ЦЕННАЯ СТРОКА ВО ВСЁМ ФАЙЛЕ. Она означает «прошлый запуск
        // умер, не убрав за собой» — то есть по ней видно и сам факт аварии, и
        // причину жалобы «после сбоя браузер не открывал сайты». Без неё
        // восстановление проходило совершенно молча.
        AppLog.w('Прошлый запуск завершился аварийно с включённым системным '
            'прокси — снимаю');
        await clear();
      }
    } catch (e) {
      AppLog.e('Не удалось снять прокси после аварийного запуска: $e');
    }
  }

  /// Чем запускать `reg.exe`. Подменяется ТОЛЬКО тестами.
  ///
  /// ⚠️ БЕЗ ЭТОЙ ТОЧКИ ТЕСТ ПРОВЕРИТЬ РАЗБОР ОТКАЗА НЕ МОЖЕТ, не тронув
  /// настройки прокси машины, на которой идёт прогон. У владельца в этот
  /// момент может работать VPN — и тест, честно вызвавший `clear()`, оборвал
  /// бы ему соединение. Правило проекта на этот счёт прямое: прогон тестов не
  /// трогает боевое окружение.
  @visibleForTesting
  static Future<ProcessResult> Function(String exe, List<String> args) runner =
      Process.run;

  /// Вернуть боевой запуск (между тестами).
  @visibleForTesting
  static void resetRunnerForTests() => runner = Process.run;

  /// Одна правка реестра. `false` — правка НЕ применилась.
  static Future<bool> _reg(String what, List<String> args) async {
    try {
      final r = await runner('reg', ['add', _regKey, ...args]);
      if (r.exitCode == 0) return true;
      // Текст ошибки `reg.exe` приходит в кодировке консоли и бывает пустым —
      // код возврата поэтому называем всегда, а текст только если он есть.
      final err = '${r.stderr}'.trim();
      AppLog.e('Системный прокси, $what: reg вернул ${r.exitCode}'
          '${err.isEmpty ? '' : ' — $err'}');
      return false;
    } catch (e) {
      AppLog.e('Системный прокси, $what: $e');
      return false;
    }
  }

  // ── wininet.dll: InternetSetOptionW для мгновенного применения ─────────────
  static void _notifyChanged() {
    try {
      final wininet = DynamicLibrary.open('wininet.dll');
      final setOption = wininet.lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer, Uint32),
          int Function(int, int, Pointer, int)>('InternetSetOptionW');
      const internetOptionSettingsChanged = 39;
      const internetOptionRefresh = 37;
      setOption(0, internetOptionSettingsChanged, nullptr, 0);
      setOption(0, internetOptionRefresh, nullptr, 0);
    } catch (_) {
      // Не критично: настройки применятся при следующем создании соединения.
    }
  }
}
