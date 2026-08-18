import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/platform/app_paths.dart';
import '../../core/platform/core_cleanup.dart';
import '../../core/platform/rotating_log.dart';

import 'xray_paths.dart';

/// Запуск sing-box как **прокси-ядра** (обычные права).
///
/// Не путать с [TunHelper]: тот поднимает sing-box с TUN-адаптером и требует
/// администратора. Здесь sing-box слушает только 127.0.0.1, поэтому UAC не нужен.
class SingboxProcess {
  Process? _process;

  /// Последние строки вывода — чтобы показать реальную причину падения.
  ///
  /// 200, а не 30: на уровне `info`/`debug` ядро выдаёт десятки строк стартовой
  /// болтовни, и при 30 строках FATAL вытеснялся из хвоста раньше, чем его
  /// успевали прочитать.
  final List<String> _tail = [];
  static const _tailMax = 200;

  String get tail => _tail.join('\n');

  /// Файловый лог (опционально). До него причину отказа прокси-ядра было
  /// физически негде посмотреть: конфиг валиден, процесс жив, трафика нет —
  /// и ни байта диагностики. TUN-ядро свой лог пишет с 0.8.0, прокси-ядро нет.
  RotatingLog? _log;

  /// Завершение дренажа stdout/stderr. `Process.exitCode` НЕ гарантирует, что
  /// последние строки уже доставлены, — а именно они и объясняют смерть ядра.
  Future<void> get outputDone =>
      Future.wait(_drains).then((_) {}, onError: (_) {});
  final List<Future<void>> _drains = [];

  /// Запущен И ещё жив: sing-box падает на старте от одной опечатки в конфиге,
  /// а «мы его стартовали» — недостаточный признак (порт так и не откроется,
  /// и это выглядело как «все серверы недоступны»).
  bool _exited = false;
  bool get isRunning => _process != null && !_exited;

  /// Путь к sing-box.exe: он лежит рядом с xray.exe (см. tools/fetch-singbox.ps1).
  static String? locate() {
    final loc = XrayPaths.locate();
    if (loc == null) return null;
    final path = '${loc.assetDir}${Platform.pathSeparator}sing-box.exe';
    return File(path).existsSync() ? path : null;
  }

  /// Лог прокси-ядра. Имя отличается от `singbox.log` (TUN) намеренно: при
  /// hysteria2 в TUN-режиме оба ядра живут одновременно, и общий файл превратил
  /// бы диагностику в кашу из двух потоков.
  ///
  /// [name] переопределяет имя файла — нужен маршрутизатору выходов режима
  /// «Только прокси» (задача 3b): он может жить ОДНОВРЕМЕННО с этим же
  /// классом, поднятым под hysteria2-прокси, и общее имя смешало бы два
  /// потока лога в один файл.
  static String logPathFor(Directory supportDir, {String name = 'singbox_proxy.log'}) =>
      '${supportDir.path}${Platform.pathSeparator}$name';

  /// Хвост лога прокси-ядра (для отчёта поддержки и экрана логов).
  ///
  /// [name] — как у [logPathFor]: по умолчанию читает лог обычного
  /// прокси-ядра (hysteria2), но им же читается лог маршрутизатора выходов
  /// режима «Только прокси» (`singbox_exit_router.log`, задача 3b) — иначе
  /// его сбой был бы недиагностируем: конфиг молча не поднялся, а строчки об
  /// этом никто не читает.
  ///
  /// ⚠️ Читается ЧЕРЕЗ РОТАЦИЮ ([RotatingLog.tailAcrossRotation]): при
  /// достижении порога прежняя часть уезжает в `*.prev.log`, и обычный `tail`
  /// показал бы начало новой части вместо строк, которые ядро выдало перед
  /// смертью, — то есть пустоту ровно в том случае, ради которого лог заведён.
  static Future<String> tailLog(
          {int lines = 200, String name = 'singbox_proxy.log'}) async =>
      RotatingLog.tailAcrossRotation(
          logPathFor(await AppPaths.supportDir(), name: name),
          lines: lines);

  Future<void> start({
    required String executable,
    required String configPath,
    String? logPath,
  }) async {
    if (_process != null) throw StateError('Ядро уже запущено');
    if (logPath != null) {
      // ⚠️ `keepPrevious` + общий с TUN-ядром потолок. Прокси-ядро свой лог и
      // раньше не обрезало при старте, но порог в 512 КБ стирал его В НОЛЬ —
      // а на уровне `debug` это две-три минуты истории. Разбирать по такому
      // логу обрыв, замеченный человеком минутами позже, нечем: он уже стёрт.
      _log = RotatingLog(logPath,
          maxBytes: RotatingLog.coreLogMaxBytes, keepPrevious: true);
      await _log!.open();
      await _log!.write(
          '--- запуск прокси-ядра ${DateTime.now().toIso8601String()} (конфиг $configPath)');
    }
    final proc = await Process.start(
      executable,
      ['run', '-c', configPath],
      workingDirectory: File(executable).parent.path,
    );
    _process = proc;
    _exited = false;
    // Windows не убивает детей вместе с родителем — регистрируем, чтобы
    // погасить при выходе и не оставить работающее ядро после закрытия.
    CoreCleanup.register(proc);
    unawaited(proc.exitCode.then((code) {
      _exited = true;
      CoreCleanup.unregister(proc);
      // Код возврата — половина диагноза: «жив» и «умер молча» выглядят в
      // конфиге одинаково, а в логе различаются.
      unawaited(_log?.write('--- sing-box (прокси) завершился, код $code') ??
          Future<void>.value());
    }));

    void onLine(String line) {
      _tail.add(line);
      if (_tail.length > _tailMax) _tail.removeAt(0);
      unawaited(_log?.write(line) ?? Future<void>.value());
    }

    _drains
      ..add(proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onLine, onError: (_) {})
          .asFuture<void>())
      ..add(proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onLine, onError: (_) {})
          .asFuture<void>());
  }

  Future<int>? get exitCode => _process?.exitCode;

  Future<void> stop() async {
    final proc = _process;
    _process = null;
    // ⚠️ `_log` НЕ обнуляем здесь. Обработчики `onLine` и `exitCode` читают
    // именно ПОЛЕ, поэтому раннее обнуление выбрасывало всё, что ядро выдало
    // при убийстве, — вместе со строкой «завершился, код N». То есть ровно ту
    // диагностику, ради которой лог и заводили.
    if (proc == null) {
      final orphan = _log;
      _log = null;
      await orphan?.close();
      return;
    }
    CoreCleanup.unregister(proc);
    proc.kill();
    await proc.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    // Дожидаемся ДОСТАВКИ вывода: `exitCode` завершается раньше, чем stdout
    // и stderr дочитаны до конца, — последние строки иначе теряются.
    await outputDone.timeout(const Duration(seconds: 2), onTimeout: () {});
    final log = _log;
    _log = null;
    await log?.close();
    _tail.clear();
    _drains.clear();
  }

  void dispose() {}
}
