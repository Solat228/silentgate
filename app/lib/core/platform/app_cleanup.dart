import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../engine/windows/system_proxy.dart';
import '../../engine/windows/tun/tun_scheduled_task.dart';
import '../../engine/windows/xray_paths.dart';
import 'app_paths.dart';
import 'core_cleanup.dart';
import 'url_scheme_windows.dart';

/// Очистка следов приложения (для деинсталлятора и кнопки «Удалить все данные»).
class AppCleanup {
  /// Без плагинов Flutter — для режима `--cleanup` (вызывается деинсталлятором):
  /// снять системный прокси, снять URL-схему, погасить СВОИ (и только свои —
  /// см. [killOwnCores]) процессы ядра, удалить данные.
  static Future<void> runHeadless() async {
    await SystemProxy.clear();
    await UrlSchemeWindows.unregister();
    // И серверные схемы (vless/vmess/trojan/ss/hysteria2/hy2): если пользователь
    // включал их перехват, после удаления они иначе остаются в реестре и
    // указывают на стёртый exe (в [Registry] установщика их нет — их ставит
    // само приложение). Снятие несуществующих ключей — no-op.
    await UrlSchemeWindows.unregisterServerSchemes();
    await killOwnCores();
    await _deleteTunTask();
    _deleteData();
  }

  /// Погасить ядра — ТОЛЬКО СВОИ, по полному пути процесса.
  ///
  /// ⚠️ Раньше здесь стоял `taskkill /F /IM xray.exe /T` (и то же для
  /// `sing-box.exe`) — гашение ПО ИМЕНИ ОБРАЗА, то есть по всей машине. Эти
  /// имена носят Happ, v2rayTun, NekoBox и ещё десяток клиентов на тех же
  /// ядрах: удаление SilentGate роняло ЧУЖОЙ живой туннель, а связать
  /// пропавший интернет с удалением ДРУГОЙ программы человек не мог.
  ///
  /// Отбор своего от чужого — не свой, а [CoreCleanup.sweepOrphans]: один
  /// разбор на всё приложение. Два независимых разбора одного и того же
  /// неизбежно расходятся — этот класс дефектов в проекте уже ловили.
  ///
  /// Свою папку не нашли — не гасим НИЧЕГО. Цена ошибки несимметрична:
  /// осиротевшее своё ядро подберёт [CoreCleanup.sweepOrphans] при следующем
  /// запуске (а если приложение удалено — поднимать его больше некому), тогда
  /// как чужой убитый туннель не вернуть.
  ///
  /// [assetDir]/[exeDir]/[sweep] — швы для теста; в бою все три берутся сами.
  @visibleForTesting
  static Future<void> killOwnCores({
    String? assetDir,
    String? exeDir,
    Future<void> Function(String dir)? sweep,
  }) async {
    final dir = ownCoreDir(assetDir: assetDir, exeDir: exeDir);
    if (dir == null) return;
    await (sweep ?? CoreCleanup.sweepOrphans)(dir);
  }

  /// Папка НАШИХ ядер с завершающим разделителем, либо null.
  ///
  /// ⚠️ Разделитель в конце — не косметика: [CoreCleanup.sweepOrphans]
  /// сравнивает путь процесса ПРЕФИКСОМ строки, и без него папка
  /// `…\SilentGate` совпала бы с чужой `…\SilentGateFork\xray.exe`.
  ///
  /// Источника два: каталог, откуда мы сами запускаем ядра, и — если xray.exe
  /// там уже стёрт — каталог нашего exe (в релизной раскладке ядра лежат
  /// рядом с ним). Деинсталлятор Inno зовёт `--cleanup` ДО удаления файлов
  /// (`[UninstallRun]`), так что обычно срабатывает первый.
  @visibleForTesting
  static String? ownCoreDir({String? assetDir, String? exeDir}) {
    for (final raw in [
      assetDir ?? XrayPaths.locate()?.assetDir,
      exeDir ?? _ownExeDir(),
    ]) {
      final dir = _normalizeDir(raw);
      if (dir != null) return dir;
    }
    return null;
  }

  static String? _ownExeDir() {
    try {
      return File(Platform.resolvedExecutable).parent.path;
    } catch (_) {
      return null;
    }
  }

  /// Приводит путь к виду, который сравнивает [CoreCleanup.sweepOrphans]
  /// (разделители `\`, ровно один в конце). Возвращает null для того, что
  /// «своей папкой» быть не может.
  static String? _normalizeDir(String? raw) {
    var dir = (raw ?? '').trim().replaceAll('/', r'\');
    while (dir.endsWith(r'\')) {
      dir = dir.substring(0, dir.length - 1);
    }
    if (dir.isEmpty) return null;
    // Корень диска (`C:\`) и голая сетевая шара (`\\server`): под ними лежит
    // вся машина, включая чужие клиенты. Такой «своей папки» не бывает —
    // лучше не погасить своё, чем погасить чужое.
    if (RegExp(r'^[a-zA-Z]:$').hasMatch(dir)) return null;
    if (dir.startsWith(r'\\') && !dir.substring(2).contains(r'\')) return null;
    return '$dir\\';
  }

  /// Задача Планировщика для запуска TUN без UAC (создаётся из приложения).
  static Future<void> _deleteTunTask() async {
    try {
      await Process.run(
          'schtasks', ['/Delete', '/TN', TunScheduledTask.taskName, '/F']);
    } catch (_) {}
  }

  /// Из работающего приложения (кнопка «Удалить все данные»).
  static Future<void> runInApp() async {
    await SystemProxy.clear();
    await UrlSchemeWindows.unregister();
    await UrlSchemeWindows.unregisterServerSchemes();
    _deleteData();
  }

  static void _deleteData() {
    try {
      final dir = AppPaths.supportDirSync();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
