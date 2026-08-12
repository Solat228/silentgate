import 'package:flutter/material.dart';
import 'widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/traffic_stats.dart';
import '../core/platform/app_log.dart';
import '../core/platform/platform_services.dart';
import '../core/platform/singbox_log_format.dart';
import '../core/settings/app_settings.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/settings_controller.dart';

/// Логи приложения и ядра — чтобы диагностировать без запуска из консоли.
///
/// «Приложение» — `%APPDATA%\SilentGate\app.log` (импорт подписки и её формат,
/// пинг, автонастройка, подключения). «TUN (sing-box)» — `singbox.log`.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  // null — ещё не загружено (показываем «Загрузка…»); '' — лог пуст (плашка).
  String? _app;
  String? _tun;

  @override
  void initState() {
    super.initState();
    _reload();
    AppLog.addListener(_onLog);
  }

  @override
  void dispose() {
    AppLog.removeListener(_onLog);
    _tabs.dispose();
    super.dispose();
  }

  void _onLog() {
    if (mounted) _reload();
  }

  Future<void> _reload() async {
    final app = await AppLog.dump();
    final tun = await platform.tunLog.tail(lines: 400);
    if (!mounted) return;
    setState(() {
      _app = app;
      // Лог ядра показываем причёсанным: смещение часового пояса в конец
      // строки, цветовые последовательности прочь. Файл при этом не трогаем.
      _tun = tidySingboxLog(tun);
    });
  }

  /// Текст вкладки для показа: пока не загружено — «Загрузка…», пусто — плашка,
  /// иначе — сам лог.
  String _display(String? raw, String loading, String empty) {
    if (raw == null) return loading;
    if (raw.trim().isEmpty) return empty;
    return _newestFirst(raw);
  }

  /// ⚠️ НОВЫЕ ЗАПИСИ СВЕРХУ. Разворот ТОЛЬКО при показе — файл на диске
  /// остаётся дописываемым в естественном порядке, иначе каждая новая строка
  /// требовала бы переписать его целиком.
  ///
  /// Смотрят в лог всегда за одним и тем же: что случилось ТОЛЬКО ЧТО. Раньше
  /// для этого надо было мотать в самый низ — на несколько тысяч строк, каждый
  /// раз.
  static String _newestFirst(String raw) {
    final lines = raw.split('\n');
    // Хвостовой перевод строки не должен превратиться в пустую строку сверху.
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines.reversed.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appText = _display(_app, l.logsLoading, l.logsEmpty);
    final tunText = _display(_tun, l.logsLoading, l.logsTunEmpty);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.logsTitle),
        bottom: TabBar(
          controller: _tabs,
          onTap: (_) => setState(() {}),
          tabs: [
            Tab(text: l.logsTabApp),
            Tab(text: l.logsTabTun),
          ],
        ),
        actions: [
          // Размер логов и срок их хранения — отдельным окном, а не полосой
          // сверху: место на экране принадлежит самому логу, а размер смотрят
          // раз в жизни. До этой кнопки узнать его можно было только
          // проводником.
          IconButton(
            tooltip: l.logsRetentionTitle,
            icon: const Icon(Icons.folder_outlined),
            onPressed: _openStorage,
          ),
          IconButton(
            tooltip: l.logsRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          IconButton(
            tooltip: l.logsCopy,
            icon: const Icon(Icons.copy),
            onPressed: () {
              final current = _tabs.index == 0 ? appText : tunText;
              Clipboard.setData(ClipboardData(text: current));
              AppToast.copied(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.logsCopied)),
              );
            },
          ),
          IconButton(
            tooltip: l.logsClearApp,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await AppLog.clear();
              await _reload();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_view(appText), _view(tunText)],
      ),
    );
  }

  /// Окно «сколько всё это занимает и сколько хранить».
  ///
  /// Держит СВОЁ состояние переписи (`inv`) и перечитывает её после чистки:
  /// иначе кнопка «Удалить старые сейчас» отработала бы, а цифры остались
  /// прежними — и выглядело бы, что она ничего не делает.
  Future<void> _openStorage() async {
    final l = AppLocalizations.of(context);
    final settings = context.read<SettingsController>();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        // Перепись строится ОДИН раз и пересоздаётся только после чистки:
        // считать её на каждый кадр значило бы перечитывать мегабайтные файлы
        // при каждом нажатии в диалоге.
        var inventory = LogMaintenance.inventory();
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(l.logsTitle),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FutureBuilder<LogInventory>(
                        future: inventory,
                        builder: (_, snap) {
                          final data = snap.data;
                          if (data == null) return Text(l.logsLoading);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final f in data.logs)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    l.logsFileLine(f.name,
                                        TrafficStats.formatBytes(f.bytes),
                                        f.lines),
                                    textDirection: TextDirection.ltr,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text(l.logsReportsLine(data.reportCount,
                                  TrafficStats.formatBytes(data.reportBytes))),
                            ],
                          );
                        },
                      ),
                      const Divider(height: 24),
                      Consumer<SettingsController>(
                        builder: (_, c, __) =>
                            DropdownButtonFormField<LogRetention>(
                          initialValue: c.settings.logRetention,
                          decoration:
                              InputDecoration(labelText: l.logsRetentionTitle),
                          items: [
                            for (final r in LogRetention.values)
                              DropdownMenuItem(
                                  value: r, child: Text(_retentionLabel(l, r))),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            settings.update((s) => s.copyWith(logRetention: v));
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(l.logsRetentionInfo,
                          style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final res = await LogMaintenance.clean(
                        maxAge: settings.settings.logRetention.maxAge);
                    if (!ctx.mounted) return;
                    AppToast.show(
                      ctx,
                      res.isEmpty
                          ? l.logsNothingToClean
                          : l.logsCleaned(res.files,
                              TrafficStats.formatBytes(res.bytes)),
                    );
                    setLocal(() => inventory = LogMaintenance.inventory());
                    if (mounted) await _reload();
                  },
                  child: Text(l.logsCleanNow),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l.commonClose),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _retentionLabel(AppLocalizations l, LogRetention r) {
    switch (r) {
      case LogRetention.day:
        return l.logsRetentionDay;
      case LogRetention.twoWeeks:
        return l.logsRetentionTwoWeeks;
      case LogRetention.month:
        return l.logsRetentionMonth;
      case LogRetention.never:
        return l.logsRetentionNever;
    }
  }

  Widget _view(String text) => Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox.expand(
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      );
}
