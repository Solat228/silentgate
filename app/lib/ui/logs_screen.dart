import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/traffic_stats.dart';
import '../core/platform/app_log.dart';
import '../core/platform/platform_services.dart';
import '../core/platform/rotating_log.dart';
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

  /// Хук для тестов: даёт дёрнуть ровно один цикл опроса прироста без
  /// ожидания настоящего таймера (`Timer.periodic`, созданный под
  /// `flutter_test`, живёт в поддельном времени, а опрос читает файлы по
  /// РЕАЛЬНОМУ вводу-выводу — эти два мира без явного хука не совмещаются).
  ///
  /// Настоящий экран сам ставит себя сюда в `initState` и снимает в
  /// `dispose`; звать хук можно только между этими моментами.
  @visibleForTesting
  static Future<void> Function()? debugPollOnce;

  /// Тестам: не звать `_load()` из `initState`.
  ///
  /// ⚠️ БЕЗ ЭТОГО ФЛАГА ТЕСТЫ ПАДАЛИ НЕВОСПРОИЗВОДИМО. `initState` вызывает
  /// `_load()` СРАЗУ по `pumpWidget`, то есть ДО того, как тест успевает
  /// обернуть что-либо в `runAsync`, — её чтение файлов уходит в поддельное
  /// время и НИКОГДА не завершается. Зависший `File.readAsBytes()` при этом
  /// не «ничего не делает»: он держит файл открытым на уровне ОС, и
  /// следующая же попытка теста удалить этот файл падает с «файл занят
  /// другим процессом». Тесты сами наполняют экран через [debugPollOnce].
  @visibleForTesting
  static bool debugSkipInitialLoad = false;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  /// Сырой (хронологический, файловый) текст, накопленный за сессию экрана —
  /// пополняется приростом, а не перечитывается целиком (см. [_pollIncrement]).
  /// `null` — ещё не загружено (показываем «Загрузка…»).
  String? _appRaw;
  String? _tunRaw;

  /// Байтовое смещение, докуда каждый файл уже прочитан.
  int _appOffset = 0;
  int _tunOffset = 0;

  final _appScroll = ScrollController();
  final _tunScroll = ScrollController();

  /// Слежение «за концом» лога — решение владельца 29.08.2026: пока
  /// пользователь у конца списка, новые строки сами подъезжают на глаза; стоит
  /// прокрутить прочь — их подстановка перестаёт дёргать его позицию.
  bool _appFollow = true;
  bool _tunFollow = true;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _appScroll.addListener(() => _onScroll(_appScroll, (v) => _appFollow = v));
    _tunScroll.addListener(() => _onScroll(_tunScroll, (v) => _tunFollow = v));
    LogsScreen.debugPollOnce = _pollIncrement;
    if (!LogsScreen.debugSkipInitialLoad) _load();
    _poll = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _pollIncrement());
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (identical(LogsScreen.debugPollOnce, _pollIncrement)) {
      LogsScreen.debugPollOnce = null;
    }
    _appScroll.dispose();
    _tunScroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// «У конца» — с запасом в несколько пикселей: пиксель-в-пиксель сравнение
  /// с плавающей точкой почти никогда не совпадает точно.
  static const _endTolerance = 24.0;

  void _onScroll(ScrollController c, void Function(bool) setFollow) {
    if (!c.hasClients) return;
    setFollow(c.position.pixels >= c.position.maxScrollExtent - _endTolerance);
  }

  /// Прыгнуть в конец там, где слежение включено — ПОСЛЕ кадра: сразу после
  /// `setState` разметка ещё не знает новой высоты контента.
  void _followIfNeeded() => _followAttempt(_followRetries);

  /// Сколько кадров ждать `ScrollController`, у которого ещё нет клиента.
  ///
  /// ⚠️ ЗАЧЕМ ПОВТОР, А НЕ ОДИН ПОСТ-КАДРОВЫЙ ВЫЗОВ. Переключение вкладки
  /// анимировано (300 мс), а `TabBarView` строит страницу, на которую только
  /// что переключились, НЕ мгновенно — её `SingleChildScrollView` получает
  /// клиента через несколько кадров после начала анимации. Один точечный
  /// `addPostFrameCallback`, поставленный в момент переключения, чаще всего
  /// стреляет РАНЬШЕ этого момента и молча ничего не делает. 20 кадров с
  /// запасом перекрывают анимацию при любой частоте кадров.
  static const _followRetries = 20;

  void _followAttempt(int retriesLeft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var pending = false;
      if (_appFollow) {
        if (_appScroll.hasClients) {
          _appScroll.jumpTo(_appScroll.position.maxScrollExtent);
        } else {
          pending = true;
        }
      }
      if (_tunFollow) {
        if (_tunScroll.hasClients) {
          _tunScroll.jumpTo(_tunScroll.position.maxScrollExtent);
        } else {
          pending = true;
        }
      }
      if (pending && retriesLeft > 0) _followAttempt(retriesLeft - 1);
    });
  }

  Future<void> _load() async {
    final app = await AppLog.dump();
    final tun = await platform.tunLog.tail(lines: 400);
    var appLen = 0;
    var tunLen = 0;
    try {
      appLen = await File(await AppLog.filePath()).length();
    } catch (_) {}
    try {
      tunLen = await File(await platform.tunLog.filePath()).length();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _appRaw = app;
      _appOffset = appLen;
      _tunRaw = tun;
      _tunOffset = tunLen;
    });
    _followIfNeeded();
  }

  /// Прирост — читает ТОЛЬКО то, что дописалось с прошлого раза
  /// ([RotatingLog.readSince]), а не файл целиком. Без этого лог ядра на
  /// уровне `debug` (сотни строк в секунду) перечитывался бы полностью на
  /// каждый тик — и подвесил бы интерфейс, а не просто нагрузил его.
  Future<void> _pollIncrement() async {
    await AppLog.flushFile();
    final appChunk =
        await RotatingLog.readSince(await AppLog.filePath(), _appOffset);
    final tunChunk = await RotatingLog.readSince(
        await platform.tunLog.filePath(), _tunOffset);
    if (!mounted) return;
    final appChanged = appChunk.offset != _appOffset || appChunk.text.isNotEmpty;
    final tunChanged = tunChunk.offset != _tunOffset || tunChunk.text.isNotEmpty;
    if (!appChanged && !tunChanged) return; // ничего нового — не дёргаем кадр
    setState(() {
      // Смещение НОВОГО чтения меньше прежнего — файл обрезали или он начался
      // заново (своя кнопка «Удалить этот лог», общая чистка, ротация): текст
      // ЗАМЕНЯЕТСЯ, а не дополняется, иначе на экране осталась бы призрачная
      // хвостовая часть уже стёртого файла.
      if (appChunk.offset < _appOffset) {
        _appRaw = SensitiveAddresses.mask(appChunk.text);
      } else if (appChunk.text.isNotEmpty) {
        _appRaw = (_appRaw ?? '') + SensitiveAddresses.mask(appChunk.text);
      }
      _appOffset = appChunk.offset;

      if (tunChunk.offset < _tunOffset) {
        _tunRaw = tunChunk.text;
      } else if (tunChunk.text.isNotEmpty) {
        _tunRaw = (_tunRaw ?? '') + tunChunk.text;
      }
      _tunOffset = tunChunk.offset;
    });
    _followIfNeeded();
  }

  /// Текст вкладки для показа: пока не загружено — «Загрузка…», пусто — плашка,
  /// иначе — сам лог, без хвостовых пустых строк.
  String _display(String? raw, String loading, String empty) {
    if (raw == null) return loading;
    final trimmed = raw.replaceAll(RegExp(r'\n+$'), '');
    if (trimmed.isEmpty) return empty;
    return trimmed;
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';
  static String _fmtDate(DateTime d) =>
      '${_two(d.day)}.${_two(d.month)}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appText = _display(_appRaw, l.logsLoading, l.logsEmpty);
    final tunText = _display(
        _tunRaw == null ? null : tidySingboxLog(_tunRaw!),
        l.logsLoading,
        l.logsTunEmpty);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.logsTitle),
        bottom: TabBar(
          controller: _tabs,
          // ⚠️ И `_followIfNeeded()` ТОЖЕ: вкладка могла накопить строки, пока
          // была скрыта, — у её `ScrollController` ещё не было клиентов, и
          // прыжок в конец из `_pollIncrement` молча пропускался. Здесь его
          // ретраи (см. [_followAttempt]) застанут страницу, когда анимация
          // переключения её действительно построит.
          onTap: (_) {
            setState(() {});
            _followIfNeeded();
          },
          tabs: [
            Tab(text: l.logsTabApp),
            Tab(text: l.logsTabTun),
          ],
        ),
        actions: [
          // Значок + слово, видимые без наведения — решение владельца
          // 29.08.2026: подсказка по наведению на сенсорном экране (и просто
          // с непривычки) никто не видит.
          TextButton.icon(
            icon: const Icon(Icons.settings),
            label: Text(l.logsSettingsLabel),
            onPressed: _openStorage,
          ),
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(l.logsClearAllLabel),
            onPressed: _openClearAllDialog,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _view(
            text: appText,
            controller: _appScroll,
            onCopy: () => _copy(appText),
            onDeleteCurrent: () => _deleteCurrent(app: true),
          ),
          _view(
            text: tunText,
            controller: _tunScroll,
            onCopy: () => _copy(tunText),
            onDeleteCurrent: () => _deleteCurrent(app: false),
          ),
        ],
      ),
    );
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.copied(context);
  }

  /// Удалить ТОЛЬКО лог текущей вкладки — решение владельца 29.08.2026:
  /// кнопка живёт рядом с копированием, над самим логом, и не требует
  /// подтверждения (в отличие от «Очистить все логи» ниже) — человек уже
  /// смотрит именно в этот лог и явно просит стереть именно его.
  Future<void> _deleteCurrent({required bool app}) async {
    final l = AppLocalizations.of(context);
    final res = await LogMaintenance.cleanSelected(app: app, tun: !app);
    if (!mounted) return;
    setState(() {
      if (app) {
        _appRaw = '';
        _appOffset = 0;
      } else {
        _tunRaw = '';
        _tunOffset = 0;
      }
    });
    AppToast.show(
      context,
      res.isEmpty
          ? l.logsNothingToClean
          : l.logsCleaned(res.files, TrafficStats.formatBytes(res.bytes)),
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
                    if (mounted) await _load();
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

  /// Диалог «Очистить все логи» — с ВЫБОРОМ, что именно чистить (решение
  /// владельца 29.08.2026): галочка на категорию, размер рядом, и период, за
  /// который логи накопились. Удаление — только по нажатию «Очистить»,
  /// снятая галочка категорию не трогает.
  Future<void> _openClearAllDialog() async {
    final l = AppLocalizations.of(context);
    var app = true;
    var tun = true;
    var proxy = true;
    var reports = true;
    // ⚠️ ПЕРЕПИСЬ — ДО `showDialog`, А НЕ ВНУТРИ ЕГО `builder` ЧЕРЕЗ
    // `FutureBuilder`. Каталог логов маленький, чтение — доли секунды, зато
    // диалог сразу открывается с готовыми цифрами: ни лишнего кадра
    // «Загрузка…», ни рассинхрона между нажатием кнопки и результатом.
    final data = await LogMaintenance.inventory();
    if (!mounted) return;
    final days = data.periodDays;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(l.logsClearAllLabel),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: app,
                        onChanged: (v) => setLocal(() => app = v ?? false),
                        title: Text(l.logsClearOptionApp(
                            TrafficStats.formatBytes(
                                data.appLog?.bytes ?? 0))),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: tun,
                        onChanged: (v) => setLocal(() => tun = v ?? false),
                        title: Text(l.logsClearOptionTun(
                            TrafficStats.formatBytes(
                                data.tunLog?.bytes ?? 0))),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: proxy,
                        onChanged: (v) => setLocal(() => proxy = v ?? false),
                        title: Text(l.logsClearOptionProxy(
                            TrafficStats.formatBytes(data.proxyBytes))),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: reports,
                        onChanged: (v) => setLocal(() => reports = v ?? false),
                        title: Text(l.logsClearOptionReports(
                            TrafficStats.formatBytes(data.reportBytes))),
                      ),
                      if (days != null) ...[
                        const Divider(height: 24),
                        Text(
                          l.logsClearPeriod(
                            _fmtDate(data.oldest!),
                            _fmtDate(data.newest!),
                            l.logsDaysCount(days),
                          ),
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l.commonCancel),
                ),
                FilledButton(
                  onPressed: () async {
                    final res = await LogMaintenance.cleanSelected(
                      app: app,
                      tun: tun,
                      proxy: proxy,
                      reports: reports,
                    );
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    if (!mounted) return;
                    AppToast.show(
                      context,
                      res.isEmpty
                          ? l.logsNothingToClean
                          : l.logsCleaned(res.files,
                              TrafficStats.formatBytes(res.bytes)),
                    );
                    setState(() {
                      if (app) {
                        _appRaw = '';
                        _appOffset = 0;
                      }
                      if (tun) {
                        _tunRaw = '';
                        _tunOffset = 0;
                      }
                    });
                  },
                  child: Text(l.logsClearConfirm),
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

  /// Область одного лога: сам текст плюс копирование/удаление в правом
  /// верхнем углу ЭТОЙ области — решение владельца 29.08.2026: кнопки
  /// относятся к конкретному открытому логу, а не к экрану в целом.
  Widget _view({
    required String text,
    required ScrollController controller,
    required VoidCallback onCopy,
    required VoidCallback onDeleteCurrent,
  }) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: controller,
              child: Padding(
                padding: const EdgeInsets.only(top: 48),
                child: SelectableText(
                  text,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            // ⚠️ ОБЯЗАТЕЛЬНО `Material`, А НЕ ГОЛЫЙ `Row`. Кнопки лежат ПОВЕРХ
            // прокручиваемого текста лога — без непрозрачной подложки строки
            // лога просвечивали бы сквозь них.
            child: Material(
              elevation: 2,
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(l.logsCopy),
                  ),
                  TextButton.icon(
                    onPressed: onDeleteCurrent,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(l.logsDeleteCurrentLabel),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
