import 'package:flutter/material.dart';
import 'widgets/app_toast.dart';
import 'package:flutter/services.dart';

import '../core/platform/app_log.dart';
import '../core/platform/platform_services.dart';
import '../core/platform/singbox_log_format.dart';
import '../l10n/gen/app_localizations.dart';

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
