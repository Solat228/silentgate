import 'dart:convert';
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
    // ⚠️ ПРЕЖНИЕ НАСТРОЙКИ ЗАПОМИНАЕМ ДО ПРАВКИ, И ТОЛЬКО ОДИН РАЗ (MS1, 19.10).
    //
    // До 1.17.0 снятие просто выключало прокси. У человека с собственным
    // прокси (корпоративный, Fiddler, другой клиент) после отключения VPN он
    // оставался выключенным, а адрес — нашим: его настройку мы молча стирали.
    // Снимок пишется в маркер ДО первой правки — авария посреди трёх правок
    // тоже должна вернуть исходное. Повторный `set` поверх живого (смена
    // сервера, переподключение) снимок НЕ перезаписывает: иначе «прежним»
    // стал бы наш собственный адрес.
    final prev = _readMarker() ?? await _snapshot(hostPort);
    _writeMarker(hostPort, prev);
    final ok = await _reg(
            'адрес прокси', ['/v', 'ProxyServer', '/t', 'REG_SZ', '/d', hostPort, '/f']) &&
        await _reg('список исключений', [
          '/v', 'ProxyOverride', '/t', 'REG_SZ',
          '/d', 'localhost;127.*;10.*;172.16.*;192.168.*;<local>', '/f',
        ]) &&
        await _reg('включение прокси',
            ['/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
    _notifyChanged();
    if (ok) {
      AppLog.i('Системный прокси включён: $hostPort');
    } else {
      AppLog.e('Системный прокси НЕ включён — трафик пойдёт мимо туннеля');
    }
    return ok;
  }

  /// Снять системный прокси: вернуть настройки, какими они были до [set].
  ///
  /// Снимка нет (маркер старого формата или пропал) — просто выключаем
  /// прокси, как до 1.17.0.
  static Future<bool> clear() async {
    final prev = _readMarker();
    final bool ok;
    if (prev == null) {
      ok = await _reg('выключение прокси',
          ['/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
    } else {
      ok = await _restore(prev);
    }
    _notifyChanged();
    try {
      if (_markerFile.existsSync()) _markerFile.deleteSync();
    } catch (_) {}
    // ⚠️ Неснятый прокси — это «интернет пропал вообще»: система продолжает
    // слать всё на порт, которого больше нет. Такая жалоба обязана иметь в
    // журнале свою строку, иначе она неотличима от поломки провайдера.
    if (ok) {
      AppLog.i(prev != null && prev.enabled
          ? 'Системный прокси снят, возвращён прежний'
          : 'Системный прокси снят');
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

  /// Прочитать прежние настройки прокси.
  ///
  /// [ours] — наш адрес: если включённым стоит ОН (прошлый запуск упал, а
  /// маркер пропал), то «прежнего» прокси у человека не было, и возвращать
  /// туда трафик значит оставить его без интернета.
  static Future<ProxySnapshot> _snapshot(String ours) async {
    final enable = await _query('ProxyEnable');
    final server = await _query('ProxyServer');
    final override = await _query('ProxyOverride');
    final enabled = enable != null && parseRegDword(enable) == 1;
    if (enabled && server == ours) {
      AppLog.w('Системный прокси уже указывал на наш порт — прежнего '
          'прокси нет, после отключения он будет выключен');
      return ProxySnapshot(enabled: false, server: null, override: override);
    }
    return ProxySnapshot(enabled: enabled, server: server, override: override);
  }

  /// Вернуть снимок. Значения, которых не было, удаляются, а не обнуляются:
  /// пустой `ProxyServer` и отсутствующий — для части программ разное.
  static Future<bool> _restore(ProxySnapshot p) async {
    Future<bool> put(String name, String? value) => value == null
        ? _regDelete(name)
        : _reg('возврат $name',
            ['/v', name, '/t', 'REG_SZ', '/d', value, '/f']);
    // Выключаем ПЕРВЫМ: пока адрес возвращается, система не должна слать
    // трафик на порт, которого вот-вот не станет.
    final off = await _reg('выключение прокси',
        ['/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
    final server = await put('ProxyServer', p.server);
    final override = await put('ProxyOverride', p.override);
    final on = !p.enabled ||
        await _reg('включение прежнего прокси',
            ['/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
    return off && on && server && override;
  }

  /// Значение из `Internet Settings`; `null` — значения нет.
  static Future<String?> _query(String name) async {
    try {
      final r = await runner('reg', ['query', _regKey, '/v', name]);
      if (r.exitCode != 0) return null;
      return parseRegValue('${r.stdout}', name);
    } catch (e) {
      AppLog.w('Системный прокси: не прочитать $name ($e)');
      return null;
    }
  }

  static Future<bool> _regDelete(String name) async {
    try {
      final r = await runner('reg', ['delete', _regKey, '/v', name, '/f']);
      // Значения и так нет — это успех, а не отказ.
      return r.exitCode == 0 || await _query(name) == null;
    } catch (e) {
      AppLog.e('Системный прокси, удаление $name: $e');
      return false;
    }
  }

  /// Снимок из маркера; `null` — маркера нет или он старого формата.
  static ProxySnapshot? _readMarker() {
    try {
      if (!_markerFile.existsSync()) return null;
      return parseMarker(_markerFile.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  static void _writeMarker(String hostPort, ProxySnapshot prev) {
    try {
      _markerFile.writeAsStringSync(
          jsonEncode({'set': hostPort, 'prev': prev.toJson()}));
    } catch (e) {
      // Маркер — единственный след «мы включили прокси» для следующего
      // запуска. Без него авария оставит пользователя без интернета, и понять
      // почему будет нечем.
      AppLog.w('Системный прокси: маркер не записан ($e) — '
          'после аварийного выхода прокси придётся снять вручную');
    }
  }

  /// Снимок из текста маркера. Маркер старого формата (просто `адрес:порт`)
  /// снимка не несёт — `null`.
  @visibleForTesting
  static ProxySnapshot? parseMarker(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['prev'] is! Map) return null;
      return ProxySnapshot.fromJson((j['prev'] as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  /// Значение [name] из вывода `reg query`: строка вида
  /// `    ProxyServer    REG_SZ    127.0.0.1:8080`. Пустое значение — `''`.
  @visibleForTesting
  static String? parseRegValue(String output, String name) {
    final re = RegExp(
        '^[ \\t]*${RegExp.escape(name)}[ \\t]+REG_\\w+(?:[ \\t]+(.*))?\$',
        caseSensitive: false,
        multiLine: true);
    final m = re.firstMatch(output.replaceAll('\r', ''));
    if (m == null) return null;
    return (m.group(1) ?? '').trim();
  }

  /// `0x1` → 1. Не разобралось — `null`.
  @visibleForTesting
  static int? parseRegDword(String v) {
    final t = v.trim().toLowerCase();
    return t.startsWith('0x')
        ? int.tryParse(t.substring(2), radix: 16)
        : int.tryParse(t);
  }

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

/// Настройки системного прокси до того, как их поменяло приложение.
class ProxySnapshot {
  const ProxySnapshot({required this.enabled, this.server, this.override});

  final bool enabled;

  /// `ProxyServer`; `null` — значения не было.
  final String? server;

  /// `ProxyOverride`; `null` — значения не было.
  final String? override;

  Map<String, Object?> toJson() =>
      {'enabled': enabled, 'server': server, 'override': override};

  static ProxySnapshot fromJson(Map<String, Object?> j) => ProxySnapshot(
        enabled: j['enabled'] == true,
        server: j['server'] as String?,
        override: j['override'] as String?,
      );
}
