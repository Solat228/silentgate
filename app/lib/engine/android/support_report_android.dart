import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/app_info.dart';
import '../../core/platform/app_log.dart';
import '../../core/platform/app_paths.dart';
import '../../core/platform/rotating_log.dart';
import '../../core/platform/device_id.dart';
import '../../core/platform/platform_services.dart';
import '../../core/platform/support_context.dart';
import '../../core/settings/app_settings.dart';

/// Отчёт для поддержки на Android.
///
/// Отличие от Windows — способ отдачи. Там отчёт «показывается»: открывается
/// папка с выделенным файлом, затем сам txt. На Android папки, которую можно
/// открыть, у приложения нет — файл лежит в приватном каталоге, недоступном
/// файловым менеджерам. Поэтому [reveal] **копирует текст отчёта в буфер
/// обмена**: пользователю остаётся вставить его в чат поддержки.
///
/// Файл при этом всё равно пишется — на него ссылается путь в диалоге, и он
/// переживает перезапуск, если отчёт понадобится повторно.
///
/// Секретов в отчёте нет: URL подписки маскируется, пароли серверов и токены
/// не выводятся вовсе.
class AndroidSupportReporter implements SupportReporter {
  const AndroidSupportReporter();

  @override
  Future<String> generate({
    required AppSettings settings,
    required SupportContext ctx,
  }) async {
    final b = StringBuffer();

    // Локализованная шапка приходит готовой из UI; ниже — техчасть, она
    // принципиально не переводится (единый язык для разбора обращений).
    b.write(ctx.header);
    b.writeln();

    b.writeln('[Версии]');
    b.writeln('SilentGate: ${AppInfo.version}');
    b.writeln('User-Agent: ${AppInfo.userAgent}');
    b.writeln('Ядро: sing-box (libbox), встроено в приложение');
    b.writeln();

    b.writeln('[Устройство]');
    b.writeln('ОС: Android ${await _safe(deviceIdProvider().osVersion)}');
    b.writeln('Модель: ${await _safe(deviceIdProvider().deviceModel)}');
    b.writeln('Локаль: ${Platform.localeName}');
    b.writeln('Ядер CPU: ${Platform.numberOfProcessors}');
    b.writeln('HWID: ${await _safe(Hwid.get)}');
    b.writeln();

    b.writeln('[Подключение]');
    b.writeln('Статус: ${ctx.statusLine}');
    b.writeln('Подписка: ${_maskUrl(ctx.subscriptionUrl)}');
    b.writeln('Серверов в списке: ${ctx.serverCount}');
    b.writeln('Выбран: ${ctx.activeServer} (ядро ${ctx.activeCore})');
    b.writeln();

    b.writeln('[Настройки]');
    b.writeln('TUN: MTU ${settings.tunMtu}, IPv6 ${settings.tunIpv6}, '
        'обход LAN ${settings.tunBypassLan}');
    b.writeln('DNS: режим ${settings.dnsMode.name}, hijack ${settings.dnsHijack}, '
        'стратегия ${settings.dnsStrategy.name}');
    b.writeln('Автопереподключение: ${settings.autoReconnect}, '
        'kill switch ${settings.killSwitch}, без реального IP ${settings.noRealIp}');
    b.writeln('Раздельное туннелирование: режим ${settings.splitTunnel.mode.name}, '
        'приложений ${settings.splitTunnel.apps.length}, '
        'сайтов ${settings.splitTunnel.sites.length}');
    b.writeln('Пинг: основной ${settings.pingPrimary.name}, '
        'таймаут ${settings.pingTimeoutMs} мс');
    b.writeln('Автообновление подписки: ${settings.autoUpdateEnabled}');
    b.writeln('Уровень лога ядра: ${settings.singboxLogLevel.name}');
    b.writeln();

    b.writeln('==================================================');
    b.writeln('[app.log]');
    b.writeln('==================================================');
    b.writeln(await _safe(AppLog.dump));
    b.writeln();

    b.writeln('==================================================');
    b.writeln('[лог ядра — последние строки]');
    b.writeln('==================================================');
    final core = await _safe(_coreLog);
    b.writeln(core.isEmpty
        ? '(пусто — туннель в этой сессии не поднимался)'
        : core);
    b.writeln();
    b.writeln('=== конец отчёта ===');

    final dir = await AppPaths.supportDir();
    final sup = Directory('${dir.path}${Platform.pathSeparator}support');
    if (!await sup.exists()) await sup.create(recursive: true);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .replaceFirst('T', '_')
        .split('_')
        .take(2)
        .join('_');
    final file =
        File('${sup.path}${Platform.pathSeparator}silentgate-report-$stamp.txt');
    // ⚠️ ТО ЖЕ, ЧТО НА WINDOWS, И ПО ТОЙ ЖЕ ПРИЧИНЕ: маска на весь отчёт в
    // единственном месте, где он становится файлом. Шапка печатает «Выбран:
    // <сервер>» — у безымянного узла это его боевой адрес, и строка приходит из
    // интерфейса, мимо очистки журнала. Платформы здесь обязаны совпадать:
    // отчёт с телефона уезжает в тот же чат.
    await file.writeAsString(SensitiveAddresses.mask(b.toString()));
    return file.path;
  }

  /// Отдаёт отчёт ФАЙЛОМ через системное «Поделиться».
  ///
  /// ⚠️ Раньше сюда копировался ТЕКСТ отчёта целиком, и в чат поддержки он
  /// уезжал десятками сообщений подряд — владелец описал это как «55 страниц
  /// телеграмм текста». Путь к файлу показать тоже нечем: каталог приложения
  /// на Android приватный, и `/data/user/0/…` человеку бесполезен.
  ///
  /// Теперь файл уходит одним вложением: `FileProvider` выдаёт временный
  /// доступ ровно к нему и ровно тому приложению, которое выбрали в системном
  /// окне отправки.
  ///
  /// Буфер обмена остался ЗАПАСНЫМ путём: если провайдер не отдал ссылку
  /// (несовпадение authority, срезанный путь), человек не должен остаться без
  /// единственного способа передать отчёт — он и нужен-то, когда всё сломалось.
  @override
  Future<void> reveal(String path) async {
    final shared = await _shareFile(path);
    if (shared) return;
    AppLog.w('Не удалось отдать отчёт файлом — копирую текстом в буфер обмена');
    final text = await _safe(() => File(path).readAsString());
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<bool> _shareFile(String path) async {
    try {
      final ok = await const MethodChannel('lol.silentgate/launcher')
          .invokeMethod<bool>('shareFile', {'url': path});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Хвост лога ядра — читается С КОНЦА файла. Туда `VpnService` направляет
  /// вывод sing-box и, что важнее, паники Go.
  ///
  /// ⚠️ Раньше здесь был `readAsLines()`, то есть весь файл в память. На
  /// Windows ровно это подвешивало приложение при нажатии «Написать в
  /// поддержку»: лог ядра дорастал до сотен мегабайт. На Android ротации нет
  /// вовсе, так что риск тот же.
  static Future<String> _coreLog() async {
    final dir = await AppPaths.supportDir();
    return RotatingLog.tail(
      '${dir.path}${Platform.pathSeparator}singbox.log',
      lines: 200,
    );
  }

  /// Ни один шаг сбора не должен ронять весь отчёт — он и нужен как раз тогда,
  /// когда что-то сломано.
  static Future<String> _safe(Future<String> Function() f) async {
    try {
      return await f();
    } catch (e) {
      return 'н/д ($e)';
    }
  }

  /// Оставляем схему и хост, путь скрываем: в нём токен подписки.
  static String _maskUrl(String? url) {
    if (url == null || url.isEmpty) return '(нет)';
    try {
      final u = Uri.parse(url);
      return '${u.scheme}://${u.host}/****(скрыто)';
    } catch (_) {
      return '(скрыто)';
    }
  }
}
