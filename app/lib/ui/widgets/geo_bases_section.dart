import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/geo/geo_bases.dart';
import '../../core/geo/geo_bases_controller.dart';
import '../../core/models/traffic_stats.dart';
import '../../l10n/gen/app_localizations.dart';
import 'app_toast.dart';
import 'info_tooltip.dart';
import 'sel_text.dart';

/// Причина отказа, названная СЛОВАМИ.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНЫЙ ТИП, А НЕ ПРОСТО ПОКАЗ СТРОКИ ОШИБКИ. Наружу из
/// [GeoBases] приходит текст исключения — `SocketException: Failed host
/// lookup: 'github.com'` или `HttpException: HTTP 503`. Человеку это не
/// говорит ни что случилось, ни что делать. Разбор вынесен в чистую функцию
/// [geoErrorKind], потому что так его проверяет обычный тест на строках, а не
/// виджет-тест с поднятой сетью.
enum GeoErrorKind {
  /// До сервера обновлений не достучались вовсе.
  network,

  /// Достучались, сервер ответил отказом (4xx/5xx).
  server,

  /// Не смогли записать файл: права на каталог, место на диске.
  write,

  /// Скачали, но это не тот файл: не сошлась сумма, оборвалась закачка.
  corrupt,

  /// Файл целый, но в нём нет категорий, на которые ссылается подписка.
  /// ⚠️ Это НЕ повреждение: замена отменена намеренно, и прежние файлы на
  /// месте. Смешать эти два случая значит посоветовать «попробуйте ещё раз»
  /// там, где повтор даст ровно тот же отказ.
  categories,

  /// Всё остальное — показываем исходный текст, не выдумывая причину.
  other,
}

/// Отнести текст ошибки к одной из понятных причин.
///
/// ⚠️ ПОРЯДОК ПРОВЕРОК ЗНАЧИМ. `FileSystemException` про права несёт в себе и
/// слово `Connection`-независимое, и номер ошибки; `HttpException: HTTP 404`
/// содержит и «HTTP», и адрес. Сначала спрашиваем самые узкие признаки
/// (запись, повреждение), потом код ответа, и только в конце — «связи нет».
GeoErrorKind geoErrorKind(String raw) {
  final s = raw.toLowerCase();
  if (s.contains('нет доступа на запись') ||
      s.contains('permission denied') ||
      s.contains('access is denied') ||
      s.contains('no space left') ||
      s.contains('filesystemexception')) {
    return GeoErrorKind.write;
  }
  // ⚠️ ВЫШЕ ПОВРЕЖДЕНИЯ. Отказ по категориям тоже говорит про «скачанный
  // файл», и общие слова про повреждение перехватили бы его первыми.
  if (s.contains('нет категорий') ||
      s.contains('не удалось прочитать список категорий')) {
    return GeoErrorKind.categories;
  }
  if (s.contains('контрольная сумма') ||
      s.contains('скачан не тот файл') ||
      s.contains('пустой ответ') ||
      s.contains('в файле контрольной суммы не хэш') ||
      s.contains('получено ')) {
    return GeoErrorKind.corrupt;
  }
  if (RegExp(r'http [45]\d\d').hasMatch(s)) return GeoErrorKind.server;
  if (s.contains('socketexception') ||
      s.contains('clientexception') ||
      s.contains('failed host lookup') ||
      s.contains('handshakeexception') ||
      s.contains('timeoutexception') ||
      s.contains('connection')) {
    return GeoErrorKind.network;
  }
  return GeoErrorKind.other;
}

/// Человеческая формулировка причины.
String geoErrorText(AppLocalizations l, String raw) =>
    switch (geoErrorKind(raw)) {
      GeoErrorKind.network => l.geoErrorNetwork,
      GeoErrorKind.server => l.geoErrorServer,
      GeoErrorKind.write => l.geoErrorWrite,
      GeoErrorKind.corrupt => l.geoErrorCorrupt,
      GeoErrorKind.categories => l.geoErrorCategories,
      GeoErrorKind.other => l.geoErrorOther,
    };

/// Подпись на кнопке.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА ДОСЛОВНО: «кнопка "обновить" должна быть "обновить"
/// только если есть что обновлять, иначе она должна быть кнопкой "проверить
/// обновление"». Пока релиз не спрошен, мы НЕ ЗНАЕМ, есть ли новее, и слово
/// «Обновить» обещало бы знание, которого нет. Четыре состояния уже посчитаны
/// контроллером ([GeoAction]) — здесь только подписи, чтобы их проверял
/// обычный тест.
String geoActionLabel(AppLocalizations l, GeoAction action) => switch (action) {
      GeoAction.download => l.geoDownload,
      GeoAction.check => l.geoCheck,
      GeoAction.update => l.geoUpdate,
      GeoAction.upToDate => l.geoCheckAgain,
    };

/// Раздел «Гео-базы маршрутизации» в настройках: что за файлы, целы ли они,
/// когда их проверяли и что предлагает кнопка.
///
/// ⚠️ ПОЧЕМУ ЭТО ЭКРАН, А НЕ АВТОМАТИКА. Файлы весят около 25 МБ — это трафик
/// пользователя, часто мобильный, и качать столько без спроса нельзя. Молчать
/// тоже нельзя: без баз правила панели по странам и категориям из конфига
/// убираются, а человек считает, что они работают. Поэтому состояние видно
/// всегда, а решение принимает он: сначала показываем план (что и сколько),
/// потом качаем.
///
/// ⚠️ РАЗДЕЛ ЕСТЬ НА ОБЕИХ ПЛАТФОРМАХ, И ЭТО НЕ СИММЕТРИЯ РАДИ СИММЕТРИИ.
/// Каталог берётся из [GeoBases.dir] — того самого, откуда файлы читает ядро:
/// на Android это `<filesDir>/SilentGate/geo` (его выставляет
/// `SilentGateApplication.kt` в `XRAY_LOCATION_ASSET`), на Windows — каталог
/// рядом с `xray.exe` (`XrayProcess.start` передаёт его той же переменной).
/// На Windows файлы приезжают вместе с ядром, поэтому там раздел чаще всего
/// показывает «есть» и служит обновлению, а не первой закачке; об этом прямо
/// сказано строкой [AppLocalizations.geoBundledWindows].
class GeoBasesSection extends StatefulWidget {
  const GeoBasesSection({super.key});

  @override
  State<GeoBasesSection> createState() => _GeoBasesSectionState();
}

class _GeoBasesSectionState extends State<GeoBasesSection> {
  /// Почему в каталог нельзя писать. `null` — можно.
  ///
  /// ⚠️ СПРАШИВАЕМ ЗАРАНЕЕ, А НЕ ПОСЛЕ 25 МБ. На Windows установщик кладёт
  /// приложение в `%ProgramFiles%\SilentGate`, а туда обычный пользователь
  /// писать не может: кнопка «Скачать» там — обманка, и узнать об этом в конце
  /// закачки худший из возможных вариантов.
  String? _writeProblem;
  bool _writeChecked = false;

  @override
  void initState() {
    super.initState();
    _checkWrite();
  }

  Future<void> _checkWrite() async {
    final problem = await GeoBases.writeProblem();
    if (!mounted) return;
    setState(() {
      _writeProblem = problem;
      _writeChecked = true;
    });
  }

  static String _size(int bytes) => TrafficStats.formatBytes(bytes);

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _date(DateTime d) =>
      '${_two(d.day)}.${_two(d.month)}.${d.year}';

  static String _dateTime(DateTime d) =>
      '${_date(d)} ${_two(d.hour)}:${_two(d.minute)}';

  /// Согласие на закачку. `false` — человек отказался, и наружу не уходит ни
  /// одного байта (проверку делает сам [GeoBasesController.download]).
  Future<bool> _confirm(GeoDownloadPlan plan) async {
    if (!mounted) return false;
    final l = AppLocalizations.of(context);
    final size = plan.bytes == null ? l.geoSizeUnknown : _size(plan.bytes!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(plan.isUpdate ? l.geoPlanTitleUpdate : l.geoPlanTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.geoPlanFiles(
                plan.files.map((f) => f.fileName).join(', '))),
            const SizedBox(height: 4),
            Text(l.geoPlanSize(size)),
            const SizedBox(height: 12),
            Text(l.geoPlanTraffic,
                style: Theme.of(ctx).textTheme.bodySmall),
            // ⚠️ ЧТО БУДЕТ С ПРЕЖНИМИ ФАЙЛАМИ — сказано ДО замены, а не после.
            // Их молчаливая перезапись 15.08.2026 и стоила владельцу рабочей
            // маршрутизации: вернуться было некуда, а причину он искал в
            // серверах.
            if (plan.isUpdate) ...[
              const SizedBox(height: 8),
              Text(l.geoReplaceWarning,
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(plan.isUpdate ? l.geoUpdate : l.geoDownload),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _press(GeoBasesController c, GeoAction action) async {
    final l = AppLocalizations.of(context);
    switch (action) {
      case GeoAction.check:
      case GeoAction.upToDate:
        await c.check();
      case GeoAction.download:
      case GeoAction.update:
        final ok = await c.download(confirm: _confirm);
        if (!mounted) return;
        if (ok) AppToast.show(context, l.geoDone, kind: ToastKind.success);
    }
  }

  /// Откат к прежним базам — тоже с подтверждением: действие заменяет файлы,
  /// а не показывает что-то.
  Future<void> _restore(GeoBasesController c) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.geoRestoreTitle),
        content: Text(l.geoRestoreBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.geoRestore),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await c.restore();
    if (!mounted) return;
    if (done) AppToast.show(context, l.geoRestored, kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.watch<GeoBasesController>();
    final theme = Theme.of(context);
    final status = c.status;
    final action = c.action;
    // Скачивание невозможно физически — кнопку, которая гарантированно
    // упадёт, не показываем «на всякий случай».
    final blocked = _writeChecked &&
        _writeProblem != null &&
        (action == GeoAction.download || action == GeoAction.update);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.public,
                size: 20,
                color: status != null && !status.ready
                    ? theme.colorScheme.tertiary
                    : null),
            const SizedBox(width: 8),
            Flexible(
                child: Text(l.geoTitle,
                    style: theme.textTheme.titleSmall)),
            InfoTooltip(l.infoGeoAssets, title: l.geoTitle),
          ]),
          const SizedBox(height: 4),
          // Зачем эти файлы вообще нужны: человеку неочевидно, что «гео-базы»
          // — это списки, по которым работают правила панели.
          Text(l.geoWhy, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          // ⚠️ ОТКУДА ФАЙЛЫ — НАЗВАНО ВСЛУХ. Пока источник был написан только
          // в коде, туда однажды подставили другой проект, и никто этого не
          // заметил, пока у владельца не развалилась маршрутизация.
          Text(l.geoSource,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.disabledColor)),
          const SizedBox(height: 8),
          if (status != null) ...[
            for (final f in status.files) _fileLine(l, theme, f),
            const SizedBox(height: 4),
            SelText.technical(l.geoFolder(status.dirPath),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.disabledColor)),
          ],
          if (Platform.isWindows) ...[
            const SizedBox(height: 4),
            Text(l.geoBundledWindows,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.disabledColor)),
          ],
          if (_writeChecked && _writeProblem != null) ...[
            const SizedBox(height: 6),
            _notice(theme, Icons.lock_outline, l.geoNoWrite,
                theme.colorScheme.error),
          ],
          const SizedBox(height: 8),
          _verdict(l, theme, c, action),
          if (c.canRestore) ...[
            const SizedBox(height: 4),
            _backupLine(l, theme, c),
          ],
          const SizedBox(height: 8),
          if (c.busy)
            _progress(l, theme, c)
          else
            // ⚠️ Wrap, а не Row: на узком экране две кнопки в строку не влезают,
            // а обрезанная кнопка отката — это отсутствующая кнопка отката.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: blocked ? null : () => _press(c, action),
                  child: Text(geoActionLabel(l, action)),
                ),
                if (c.canRestore)
                  OutlinedButton(
                    onPressed: blocked ? null : () => _restore(c),
                    child: Text(l.geoRestore),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Строка одного файла: `geoip.dat — 19.2 MB, обновлён 05.08.2026`.
  Widget _fileLine(AppLocalizations l, ThemeData theme, GeoFileStatus f) {
    final (String text, Color? color) = switch (f.health) {
      GeoHealth.ok => (
          l.geoFileOk(_size(f.bytes),
              f.updatedAt == null ? '—' : _date(f.updatedAt!)),
          null
        ),
      GeoHealth.missing => (l.geoFileMissing, theme.colorScheme.tertiary),
      GeoHealth.corrupt => (l.geoFileCorrupt, theme.colorScheme.error),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Icon(f.ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 16, color: color),
        const SizedBox(width: 6),
        Text(f.base.fileName,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.bodySmall),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ),
      ]),
    );
  }

  /// Что именно можно вернуть: состав, объём и от какого числа.
  ///
  /// ⚠️ ДАТА ОБЯЗАТЕЛЬНА. «Есть резервная копия» без даты не отвечает на
  /// единственный вопрос, который человек задаёт перед откатом: вернусь ли я
  /// к тому, что работало.
  Widget _backupLine(
      AppLocalizations l, ThemeData theme, GeoBasesController c) {
    final b = c.backups;
    final bytes = b.fold<int>(0, (a, x) => a + x.bytes);
    DateTime? at;
    for (final x in b) {
      final t = x.at;
      if (t != null && (at == null || t.isAfter(at))) at = t;
    }
    return _notice(
      theme,
      Icons.history,
      l.geoBackupLine(
        b.map((x) => x.base.fileName).join(', '),
        _size(bytes),
        at == null ? '—' : _date(at),
      ),
      theme.disabledColor,
    );
  }

  /// Вердикт: что нам известно про обновление и когда мы это узнали.
  Widget _verdict(AppLocalizations l, ThemeData theme, GeoBasesController c,
      GeoAction action) {
    final error = c.error;
    final children = <Widget>[];

    if (action == GeoAction.download && c.status != null) {
      children.add(_notice(theme, Icons.info_outline, l.geoMissing,
          theme.colorScheme.tertiary));
    }
    if (action == GeoAction.update) {
      final bytes = c.pendingBytes;
      children.add(_notice(
        theme,
        Icons.system_update_alt,
        // ⚠️ ВИДНО, ЧТО ИМЕННО ОБНОВИТСЯ. «Есть обновление» без состава и
        // размера — это просьба нажать вслепую.
        l.geoUpdateAvailable(
          c.pending.map((b) => b.fileName).join(', '),
          bytes == null ? l.geoSizeUnknown : _size(bytes),
        ),
        theme.colorScheme.primary,
      ));
    }
    if (action == GeoAction.upToDate) {
      children.add(_notice(theme, Icons.verified_outlined, l.geoUpToDate,
          theme.colorScheme.primary));
    }
    if (c.outcome == GeoOutcome.downloaded) {
      children.add(_notice(theme, Icons.check_circle_outline, l.geoDone,
          theme.colorScheme.primary));
    }
    if (c.outcome == GeoOutcome.restored) {
      children.add(_notice(theme, Icons.history, l.geoRestored,
          theme.colorScheme.primary));
    }
    if (error != null) {
      children.add(_notice(theme, Icons.error_outline, geoErrorText(l, error),
          theme.colorScheme.error));
      // Исходный текст оставляем ниже и мелким: он нужен для отчёта в
      // поддержку, но объяснять им происходящее нельзя.
      children.add(Padding(
        padding: const EdgeInsets.only(top: 2, left: 22),
        child: SelText.technical(error,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.disabledColor)),
      ));
    }

    final at = c.lastCheckAt;
    children.add(Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        at == null ? l.geoNeverChecked : l.geoLastCheck(_dateTime(at)),
        style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
      ),
    ));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _notice(ThemeData theme, IconData icon, String text, Color? color) =>
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall?.copyWith(color: color)),
          ),
        ]),
      );

  /// Ход работы. ⚠️ Молчащая кнопка на минуту — то же самое, что зависшее
  /// приложение: закачка идёт десятки мегабайт, и полоска здесь не украшение.
  Widget _progress(AppLocalizations l, ThemeData theme, GeoBasesController c) {
    final p = c.progress;
    if (c.checking || p == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ⚠️ Подпись «Спрашиваю выпуск…» — ТОЛЬКО когда мы правда спрашиваем.
        // Занятыми мы бываем и в другие моменты (ждём ответа человека на план,
        // ещё не пришёл первый отчёт о байтах): там честнее показать движение
        // без слов, чем назвать чужое действие.
        if (c.checking) ...[
          Text(l.geoChecking, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
        ],
        const LinearProgressIndicator(),
      ]);
    }
    final total = p.total;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${l.geoDownloading(p.base.fileName)}  ${p.index + 1}/${p.count}',
          style: theme.textTheme.bodySmall),
      const SizedBox(height: 6),
      LinearProgressIndicator(
          value: total == null || total <= 0 ? null : p.received / total),
      const SizedBox(height: 4),
      Text(
        total == null
            ? _size(p.received)
            : l.geoProgressBytes(_size(p.received), _size(total)),
        style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
      ),
    ]);
  }
}
