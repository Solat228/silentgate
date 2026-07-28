import 'dart:io';

import '../../core/app_info.dart';
import '../../core/platform/app_log.dart';
import '../../core/platform/app_paths.dart';
import '../../core/platform/device_id.dart';
import '../../core/platform/support_context.dart';
import '../../core/settings/split_tunnel.dart';
import '../../core/settings/app_settings.dart';
import 'singbox_process.dart';
import 'tun/tun_helper.dart';
import 'xray_paths.dart';
import 'xray_version.dart';

export '../../core/platform/support_context.dart';

/// Сборка отчёта для техподдержки в один текстовый файл.
///
/// Что внутри: шапка с местом под ОПИСАНИЕ ПРОБЛЕМЫ (её заполняет пользователь),
/// версии приложения и ядер, ОС, HWID, ключевые настройки, состояние подключения
/// и логи (`app.log` + хвост `singbox.log`). Файл пользователь просматривает сам
/// и отправляет в чат поддержки — поэтому секреты (пароли серверов, токен
/// подписки) в отчёт НЕ попадают, а URL подписки маскируется.
class SupportReport {
  /// Возвращает путь к созданному файлу.
  static Future<String> generate({
    required AppSettings settings,
    required SupportContext ctx,
  }) async {
    final b = StringBuffer();

    // Локализованная шапка (собрана в UI из AppLocalizations). Дальше —
    // техническая информация, она НЕ переводится (единый язык для разбора).
    b.write(ctx.header);
    b.writeln();

    // ── Версии и окружение ────────────────────────────────────────────────
    b.writeln('[Версии]');
    b.writeln('SilentGate: ${AppInfo.version}');
    b.writeln('User-Agent: ${AppInfo.userAgent}');
    b.writeln('Xray: ${await _safe(XrayVersion.get)}');
    b.writeln('sing-box: ${await _singboxVersion()}');
    b.writeln();
    b.writeln('[Система]');
    b.writeln('ОС: ${Platform.operatingSystemVersion}');
    b.writeln('Локаль: ${Platform.localeName}');
    b.writeln('Ядер CPU: ${Platform.numberOfProcessors}');
    b.writeln('HWID: ${await _safe(Hwid.get)}');
    b.writeln('Ядра найдены: xray.exe=${XrayPaths.locate() != null}, '
        'sing-box.exe=${SingboxProcess.locate() != null}');
    b.writeln();

    // ── Состояние подключения ─────────────────────────────────────────────
    b.writeln('[Подключение]');
    b.writeln('Статус: ${ctx.statusLine}');
    b.writeln('Подписка: ${_maskUrl(ctx.subscriptionUrl)}');
    b.writeln('Серверов в списке: ${ctx.serverCount}');
    b.writeln('Выбран: ${ctx.activeServer} (ядро ${ctx.activeCore})');
    b.writeln();

    // ── Настройки (без секретов) ──────────────────────────────────────────
    b.writeln('[Настройки]');
    b.writeln('Захват: ${settings.captureMode.name}');
    b.writeln('TUN-стек: ${settings.tunStack.name}, MTU ${settings.tunMtu}, '
        'strictRoute ${settings.tunStrictRoute}, IPv6 ${settings.tunIpv6}');
    b.writeln('DNS: режим ${settings.dnsMode.name}, hijack ${settings.dnsHijack}, '
        'стратегия ${settings.dnsStrategy.name}');
    // noRealIp обязателен в отчёте: он переписывает маршруты правил «Прямо», и
    // без него жалобы вида «сайт всё равно идёт через VPN» неотличимы от
    // поломки маршрутизации.
    b.writeln('Автопереподключение: ${settings.autoReconnect}, '
        'kill switch ${settings.killSwitch}, '
        'без реального IP ${settings.noRealIp}');
    final st = settings.splitTunnel;
    b.writeln('Раздельное туннелирование: режим ${st.mode.name}, '
        'приложений ${st.apps.length}, сайтов ${st.sites.length}'
        '${settings.noRealIp ? ', с реальным IP разрешено '
            '${st.apps.where((a) => a.action == AppAction.direct && a.allowRealIp).length + st.sites.where((s) => s.action == AppAction.direct && s.allowRealIp).length}' : ''}');
    b.writeln('Пинг: основной ${settings.pingPrimary.name}, '
        'запасной ${settings.pingFallback.name}, '
        'двухфазный ${settings.pingTwoPhase}, таймаут ${settings.pingTimeoutMs} мс');
    b.writeln('Автообновление подписки: ${settings.autoUpdateEnabled}, '
        'проверка обновлений приложения: ${settings.appUpdateCheck}');
    b.writeln('Уровень лога sing-box: ${settings.singboxLogLevel.name}');
    b.writeln();

    // ── Логи ──────────────────────────────────────────────────────────────
    b.writeln('==================================================');
    b.writeln('[app.log]');
    b.writeln('==================================================');
    b.writeln(await _safe(AppLog.dump));
    b.writeln();
    // Два ядра — два лога. Раньше сюда попадал только TUN-лог, и подпись
    // «TUN/hysteria2 не поднимались» была неверной: прокси-ядро hysteria2 в
    // этот файл не пишет вовсе, поэтому его отказ по отчёту не диагностировался.
    final dirForLogs = await AppPaths.supportDir();
    b.writeln('==================================================');
    b.writeln('[singbox.log — TUN-ядро, последние строки]'
        '${await _mtime(TunHelper.logPathFor(dirForLogs))}');
    b.writeln('==================================================');
    final sb = await _safe(() => TunHelper.tailLog(lines: 200));
    b.writeln(sb.isEmpty ? '(пусто — TUN в этой сессии не поднимался)' : sb);
    b.writeln();
    b.writeln('==================================================');
    b.writeln('[singbox_proxy.log — прокси-ядро (hysteria2), последние строки]'
        '${await _mtime(SingboxProcess.logPathFor(dirForLogs))}');
    b.writeln('==================================================');
    final sbp = await _safe(() => SingboxProcess.tailLog(lines: 200));
    b.writeln(sbp.isEmpty
        ? '(пусто — прокси-ядро sing-box в этой сессии не поднималось)'
        : sbp);
    b.writeln();

    b.writeln('=== конец отчёта ===');

    final dir = await AppPaths.supportDir();
    final sup = Directory('${dir.path}${Platform.pathSeparator}support');
    if (!await sup.exists()) await sup.create(recursive: true);
    // Метка времени в имени (до микросекунд) — чтобы отчёты не затирали друг
    // друга. Двоеточия/точки в имени файла Windows не разрешает — заменяем.
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .replaceFirst('T', '_')
        .split('_')
        .take(2)
        .join('_');
    final file = File('${sup.path}${Platform.pathSeparator}'
        'silentgate-report-$stamp.txt');
    await file.writeAsString(b.toString());
    return file.path;
  }

  /// Показать отчёт пользователю в СТРОГОМ порядке: СНАЧАЛА открыть папку (с
  /// выделенным файлом — чтобы было видно, куда сохранилось и что перетащить в
  /// Telegram), И ТОЛЬКО ПОТОМ сам txt-файл в редакторе (чтобы вписать описание
  /// проблемы). Небольшая пауза между шагами гарантирует, что окно Проводника
  /// успеет появиться раньше редактора и порядок не «схлопнется».
  static Future<void> reveal(String path) async {
    // 1) Папка с выделенным файлом.
    try {
      await Process.run('explorer', ['/select,', path]);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 900));
    // 2) Сам файл лога.
    try {
      await Process.run('cmd', ['/c', 'start', '', path], runInShell: true);
    } catch (_) {}
  }

  static Future<String> _singboxVersion() async {
    try {
      final exe = SingboxProcess.locate();
      if (exe == null) return 'не найдено';
      final r = await Process.run(exe, ['version'])
          .timeout(const Duration(seconds: 3));
      final m =
          RegExp(r'sing-box\s+version\s+([^\s]+)').firstMatch('${r.stdout}');
      return m != null ? m.group(1)! : 'неизвестно';
    } catch (_) {
      return 'неизвестно';
    }
  }

  /// Прячем токен подписки: оставляем схему и хост, путь маскируем.
  static String _maskUrl(String? url) {
    final u = (url ?? '').trim();
    if (u.isEmpty) return '(нет)';
    try {
      final p = Uri.parse(u);
      final host = p.host.isEmpty ? '?' : p.host;
      return '${p.scheme}://$host/****(скрыто)';
    } catch (_) {
      return '(скрыто)';
    }
  }

  static Future<String> _safe(Future<String> Function() f) async {
    try {
      return await f();
    } catch (e) {
      return 'н/д ($e)';
    }
  }

  /// Время последней записи в лог — в скобках к заголовку секции.
  ///
  /// Без него отчёт врёт: `singbox.log` при старте TUN только УСЕКАЕТСЯ, а не
  /// удаляется, поэтому лог прошлой сессии выглядит как текущий, и разбор
  /// уходит не в ту сторону.
  static Future<String> _mtime(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return '';
      return ' (изменён ${(await f.lastModified()).toIso8601String()})';
    } catch (_) {
      return '';
    }
  }
}
