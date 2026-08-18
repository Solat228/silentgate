import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_nav.dart';
import '../../l10n/gen/app_localizations.dart';
import '../app_info.dart';
import '../models/traffic_stats.dart';
import '../models/vpn_status.dart';
import 'app_log.dart';
import 'core_cleanup.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../../ui/widgets/connect_guard.dart';

/// Трей + умное закрытие: крестик сворачивает в трей (по умолчанию) или закрывает
/// (по настройке), с диалогами про активный VPN и «не спрашивать больше».
class TrayWindow with WindowListener, TrayListener {
  static final TrayWindow instance = TrayWindow._();
  TrayWindow._();

  /// Имя приложения с версией: заголовок окна и первая строка подсказки трея.
  ///
  /// ⚠️ ВЕРСИЯ ЖИВЁТ РОВНО В ЭТИХ ДВУХ МЕСТАХ (решение владельца) — шапка
  /// внутри приложения остаётся без неё. Смысл: увидеть версию, не открывая
  /// «О программе», в том числе когда окно свёрнуто в трей и видно только
  /// значок. Имя и версию берём из [AppInfo], а не литералом: бренд может
  /// смениться, и тогда правка не должна расползаться по интерфейсу.
  static String get nameWithVersion => '${AppInfo.name} ${AppInfo.version}';

  /// Параметры окна.
  ///
  /// Вынесены из [init] отдельно, чтобы заголовок проверялся тестом: сам
  /// [init] поднимает плагины и в юнит-тесте не запускается.
  ///
  /// ⚠️ ЗАГОЛОВОК СТАВИТСЯ ЗДЕСЬ И БОЛЬШЕ НИГДЕ. `show()`/`hide()` его не
  /// трогают, поэтому версия переживает сворачивание в трей и возврат из него;
  /// нативный runner создаёт окно со своим именем, но `waitUntilReadyToShow`
  /// перезаписывает его один раз при старте. Любой будущий `setTitle` в другом
  /// месте — это потерянная версия после первого же сворачивания, и стережёт
  /// это `test/window_title_test.dart`.
  static WindowOptions get windowOptions => WindowOptions(
        size: const Size(1040, 820),
        minimumSize: const Size(980, 800),
        center: true,
        title: nameWithVersion,
        titleBarStyle: TitleBarStyle.normal,
      );

  Future<void> init() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    trayManager.addListener(this);
    // Окно показываем ТОЛЬКО когда оно готово и с ЯВНЫМ размером. Раньше задавался
    // лишь минимальный размер, а стартовый — нет: первый кадр рисовался в
    // дефолтном размере рантайма, и интерфейс «съезжал», пока окно не подвигать.
    // waitUntilReadyToShow держит окно скрытым до первого корректного кадра.
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true); // крестик → onWindowClose
      await windowManager.show();
      await windowManager.focus();
    });
    await _setupTray();
  }

  /// Значок трея сейчас показывает «подключено»? `null` — ещё не ставили.
  ///
  /// ⚠️ НУЖЕН РОВНО ДЛЯ ТОГО, ЧТОБЫ НЕ ЗВАТЬ `setIcon` ВПУСТУЮ. Поток статуса
  /// тикает раз в секунду на обновлении счётчиков трафика, а `setIcon` в
  /// tray_manager создаёт HICON и НЕ освобождает прежний. Смена значка на
  /// каждом такте — это утечка дескрипторов на всё время работы приложения.
  bool? _trayConnected;

  /// Путь к значку состояния. Оба файла едут в поставке рядом.
  String _trayIconPath(bool connected) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final name = connected ? 'tray_icon.ico' : 'tray_icon_off.ico';
    return '$exeDir\\data\\flutter_assets\\assets\\$name';
  }

  /// Показать в трее состояние VPN: серый знак — выключен, фиолетовый — включён.
  Future<void> setConnected(bool connected) async {
    // Подсказку обновляем ВСЕГДА, даже когда значок менять не нужно: она
    // показывает сервер и скорость, а не состояние.
    _connected = connected;
    _syncTooltipTicker();
    await _pushTooltip();
    if (_trayConnected == connected) return; // см. _trayConnected
    _trayConnected = connected;
    await _applyTrayIcon(connected);
  }

  Future<void> _applyTrayIcon(bool connected) async {
    final path = _trayIconPath(connected);
    // ⚠️ ПРОВЕРЯЕМ ФАЙЛ САМИ. Плагин отвечает успехом, даже когда Windows не
    // смогла загрузить значок: расширение `.ico` нигде не сверяется с
    // содержимым, и, например, PNG под именем `.ico` даёт ПУСТОЙ трей — без
    // ошибки, без исключения и без строчки в журнале. Молчащий трей потом
    // ищут часами, а причина всё это время лежит в имени файла.
    if (!File(path).existsSync()) {
      AppLog.e('Значок трея не найден: $path — трей останется пустым');
      return;
    }
    try {
      await trayManager.setIcon(path);
    } catch (e) {
      AppLog.e('Не удалось поставить значок трея: $e');
    }
  }

  Future<void> _setupTray() async {
    try {
      await _applyTrayIcon(_trayConnected ?? false);
      await _pushTooltip();
      // Контекст на старте может быть ещё не готов — тогда русский фолбэк; меню
      // пересобирается при смене языка (refreshTrayMenu из переключателя языка).
      final ctx = _ctx;
      final l = ctx != null ? AppLocalizations.of(ctx) : null;
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: l?.trayShow ?? 'Показать'),
        MenuItem(key: 'toggle', label: l?.trayToggle ?? 'Подключить / Отключить'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: l?.trayQuit ?? 'Выход'),
      ]));
    } catch (_) {}
  }

  /// Пересобрать меню трея (напр. после смены языка интерфейса).
  Future<void> refreshTrayMenu() => _setupTray();

  /// Контекст навигатора — или `null`, если дерева ещё (или уже) нет.
  ///
  /// ⚠️ ОБЁРНУТО В try/catch, И ЭТО НЕ ПЕРЕСТРАХОВКА. `GlobalKey.currentContext`
  /// внутри спрашивает `WidgetsBinding.instance`, а тот БРОСАЕТ исключение,
  /// пока привязка не инициализирована. Подсказку трея обновляет
  /// `setConnected`, который зовётся из `AppState` на смену статуса — в том
  /// числе на раннем старте, когда виджетов ещё нет, и в юнит-тестах без
  /// биндинга. Поймано падением шести тестов `api_handlers_test`: там AppState
  /// поднимается без дерева вовсе.
  BuildContext? get _ctx {
    try {
      return navigatorKey.currentContext;
    } catch (_) {
      return null;
    }
  }

  /// Гарантированное завершение (#4). `windowManager.destroy()` изнутри `onWindowClose`
  /// на Windows может зависнуть намертво (deadlock в window_manager при preventClose),
  /// поэтому: прячем окно сразу (визуально закрылись), каждую операцию ограничиваем
  /// таймаутом и в конце жёстко завершаем процесс.
  Future<void> _destroy() async {
    try {
      await windowManager.hide().timeout(const Duration(seconds: 1));
    } catch (_) {}
    try {
      await trayManager.destroy().timeout(const Duration(seconds: 1));
    } catch (_) {}
    try {
      await windowManager
          .setPreventClose(false)
          .timeout(const Duration(seconds: 1));
      await windowManager.destroy().timeout(const Duration(seconds: 2));
    } catch (_) {}
    // Ядра гасим ПЕРЕД exit: Windows не убивает дочерние процессы вместе с
    // родителем, и всё, что осталось живым (в т.ч. пинг-харнесс, который как
    // раз работал в момент закрытия), продолжало бы висеть после выхода.
    CoreCleanup.killChildren();
    exit(0); // подписки/таймеры не должны держать мёртвый процесс
  }

  // ── Закрытие окна ───────────────────────────────────────────────────────────
  @override
  void onWindowClose() async {
    final ctx = _ctx;
    if (ctx == null) {
      await _destroy();
      return;
    }
    final controller = ctx.read<SettingsController>();
    final settings = controller.settings;
    final state = ctx.read<AppState>();
    // Учитываем и «подключение…»: xray/sing-box уже могли стартовать,
    // а выход без disconnect осиротил бы их вместе с системным прокси.
    final vpnActive = state.status.isConnected ||
        state.status.state == VpnConnectionState.connecting;

    if (settings.closeToTray) {
      // #1.1 — сворачивание; спросить (если не «не спрашивать»)
      if (!settings.dontAskOnClose) {
        final res = await _askMinimize(ctx);
        if (res == null) return; // отмена — окно остаётся
        if (res.quit) {
          // «Не спрашивать» вместе с «Закрыть полностью» значит не «больше не
          // сворачивать молча», а «крестик должен закрывать»: иначе галочка
          // приводила бы ровно к тому поведению, от которого пользователь
          // только что отказался.
          if (res.dontAsk) {
            controller.update((s) => s.copyWith(closeToTray: false));
          }
          if (vpnActive && await _askCloseWithVpn(ctx) != 'quit') return;
          await state.disconnect();
          await _destroy();
          return;
        }
        if (res.dontAsk) {
          controller.update((s) => s.copyWith(dontAskOnClose: true));
        }
      }
      await windowManager.hide();
    } else {
      // Полное закрытие
      if (vpnActive) {
        // #1.2 — всегда спрашивать при активном VPN
        final choice = await _askCloseWithVpn(ctx);
        if (choice != 'quit') return; // 'stay' / null — остаёмся
      }
      // disconnect сам no-op, если отключены; страхует и от гонки disconnecting.
      await state.disconnect();
      await _destroy();
    }
  }

  // ── Трей ─────────────────────────────────────────────────────────────────────
  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final ctx = _ctx;
    switch (menuItem.key) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'toggle':
        if (ctx != null) {
          // Через ту же проверку, что и кнопка на главном экране: включение из
          // трея — такое же включение, и мешающий чужой туннель мешает ему
          // ровно так же. Окно приложения при этом может быть скрыто, поэтому
          // сначала показываем его — иначе диалог остался бы незамеченным.
          final state = ctx.read<AppState>();
          final settings = ctx.read<SettingsController>().settings;
          final busy = state.status.isConnected ||
              state.status.state == VpnConnectionState.connecting;
          if (!busy) {
            await windowManager.show();
            await windowManager.focus();
          }
          if (ctx.mounted) {
            await connectWithConflictCheck(
                ctx, state, () => state.toggleConnection(settings));
          }
        }
        break;
      case 'quit':
        // Без гейта на isConnected: disconnect сам no-op при отключённом VPN,
        // а при «подключении…» корректно гасит уже запущенные процессы.
        if (ctx != null) await ctx.read<AppState>().disconnect();
        await _destroy();
        break;
    }
  }

  // ── Диалоги ──────────────────────────────────────────────────────────────────
  Future<({bool quit, bool dontAsk})?> _askMinimize(BuildContext ctx) {
    final l = AppLocalizations.of(ctx);
    bool dontAsk = false;
    return showDialog<({bool quit, bool dontAsk})>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setState) => AlertDialog(
          title: Text(l.trayMinimizeTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.trayMinimizeBody),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: dontAsk,
                onChanged: (v) => setState(() => dontAsk = v ?? false),
                title: Text(l.trayDontAsk),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx), // отмена → null
                child: Text(l.commonCancel)),
            // Выход из приложения прямо отсюда: раньше единственным способом
            // закрыть его было лезть в настройки и менять поведение крестика.
            TextButton(
                onPressed: () =>
                    Navigator.pop(dctx, (quit: true, dontAsk: dontAsk)),
                child: Text(l.trayCloseFully)),
            FilledButton(
                onPressed: () =>
                    Navigator.pop(dctx, (quit: false, dontAsk: dontAsk)),
                child: Text(l.trayMinimizeOk)),
          ],
        ),
      ),
    );
  }

  Future<String?> _askCloseWithVpn(BuildContext ctx) {
    final l = AppLocalizations.of(ctx);
    return showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text(l.trayVpnTitle),
        content: Text(l.trayVpnBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, 'stay'),
              child: Text(l.trayStay)),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, 'quit'),
              child: Text(l.trayQuitVpn)),
        ],
      ),
    );
  }

  /// Подсказка трея говорит, что kill switch сейчас держит трафик.
  ///
  /// ⚠️ Единственное место, где это видно при свёрнутом окне. Без него человек
  /// наблюдает пропавший интернет, считает приложение сломанным и выключает
  /// VPN — то есть делает ровно то, от чего защита оберегала. Полноценное
  /// системное уведомление Windows потребовало бы новой зависимости; подсказка
  /// есть уже сейчас и решает главную задачу — объяснить причину.
  static Future<void> setBlocked(bool blocked) async {
    instance._blocked = blocked;
    await instance._pushTooltip();
  }

  // ── Подсказка трея: РОВНО ДВЕ СТРОКИ ────────────────────────────────────────

  /// ⚠️ WINDOWS МОЛЧА РЕЖЕТ ПОДСКАЗКУ НА 127 СИМВОЛАХ.
  ///
  /// В `NOTIFYICONDATA` поле `szTip` — это `WCHAR[128]`, то есть 127 символов
  /// плюс завершающий ноль. Всё, что длиннее, обрезается оболочкой без ошибки,
  /// без исключения и без строчки в журнале: длинное имя сервера просто
  /// съедало бы вторую строку со скоростью, и никто бы не понял почему.
  /// Считаем в кодовых блоках UTF-16 — ровно то, что считает Windows, и ровно
  /// то, что даёт `String.length` в Dart.
  static const int tooltipLimit = 127;

  /// Текущая скорость для подсказки — и ТОЛЬКО она.
  ///
  /// ⚠️ Накопленного за сессию здесь быть не должно (решение владельца): в
  /// подсказку помещаются две строки, и «сколько всего» видно в самом
  /// приложении, а «что происходит прямо сейчас» — больше нигде.
  @visibleForTesting
  static String speedLine(TrafficStats stats) =>
      '↓ ${TrafficStats.formatSpeed(stats.downlinkSpeed)}'
      '   ↑ ${TrafficStats.formatSpeed(stats.uplinkSpeed)}';

  /// Собрать подсказку: первая строка — приложение и сервер, вторая — скорость.
  ///
  /// Обрезается ТОЛЬКО первая строка: скорость коротка, известна по длине и
  /// нужна целиком — потерять половину числа хуже, чем не дочитать имя сервера.
  @visibleForTesting
  static String composeTooltip({
    String? server,
    String? speed,
    String? blocked,
  }) {
    // Имя С ВЕРСИЕЙ: у свёрнутого в трей приложения подсказка — единственное
    // место, где версию видно вообще (заголовок окна скрыт вместе с окном).
    final name = nameWithVersion;
    final note = blocked?.trim() ?? '';
    // Блокировка трафика важнее сервера и скорости: пока kill switch держит
    // канал, объяснять надо именно это.
    if (note.isNotEmpty) return _clip('$name — $note', tooltipLimit);

    final srv = server?.trim() ?? '';
    final first = srv.isEmpty ? name : '$name — $srv';
    final second = speed?.trim() ?? '';
    if (second.isEmpty) return _clip(first, tooltipLimit);
    // -1 — перевод строки. Он тоже занимает место в szTip.
    final room = tooltipLimit - second.length - 1;
    if (room <= 0) return _clip(second, tooltipLimit); // теоретический предел
    return '${_clip(first, room)}\n$second';
  }

  /// Обрезать до [limit] кодовых блоков UTF-16, не разрушая символы.
  static String _clip(String text, int limit) {
    if (limit <= 0) return '';
    if (text.length <= limit) return text;
    if (limit == 1) return '…';
    return '${_trimBroken(text.substring(0, limit - 1))}…';
  }

  /// Снять с хвоста «половинку» символа, оставшуюся после обрезания.
  ///
  /// ⚠️ Эмодзи в UTF-16 занимает ДВА кодовых блока, а флаг страны — ЧЕТЫРЕ
  /// (две буквы-индикатора). Рез посередине даёт либо недопустимую строку с
  /// одиноким суррогатом, либо половину флага — в трее это квадрат или чужая
  /// буква. Имена серверов у панели почти всегда начинаются с флага, так что
  /// случай не теоретический.
  static String _trimBroken(String s) {
    var out = s;
    if (out.isNotEmpty && _isHighSurrogate(out.codeUnitAt(out.length - 1))) {
      out = out.substring(0, out.length - 1);
    }
    final runes = out.runes.toList();
    // ⚠️ СЧИТАЕМ ЧЁТНОСТЬ ХВОСТОВОЙ ЦЕПОЧКИ, а не одну букву перед ней.
    //
    // Флаги в имени идут подряд («🇩🇪🇳🇱»), и проверка «сосед тоже
    // индикатор?» на такой цепочке всегда отвечает «да» — половина флага
    // проходила насквозь. Флаг — ровно ДВЕ буквы, значит нечётная цепочка в
    // конце и есть разрезанный флаг: лишнюю букву убираем.
    var run = 0;
    while (run < runes.length &&
        _isRegionalIndicator(runes[runes.length - 1 - run])) {
      run++;
    }
    if (run.isOdd) out = String.fromCharCodes(runes.take(runes.length - 1));
    return out;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  static bool _isRegionalIndicator(int rune) =>
      rune >= 0x1F1E6 && rune <= 0x1F1FF;

  /// Kill switch держит трафик — подсказка говорит об этом вместо сервера.
  bool _blocked = false;

  /// Состояние по последнему вызову [setConnected].
  bool _connected = false;

  /// Последнее, что реально уехало в трей: одинаковый текст в Win32 гонять
  /// незачем, а такт у подсказки секундный.
  String? _lastTip;

  /// ⚠️ СВОЙ ТАКТ, ПОТОМУ ЧТО СТАТУС ТИКАЕТ НЕ КАЖДУЮ СЕКУНДУ.
  ///
  /// Движок шлёт статус только на СМЕНУ состояния (`setStatus`), а счётчики
  /// идут отдельным потоком, до трея не доходящим. Без своего такта в
  /// подсказке навсегда застыла бы скорость той секунды, когда VPN включили.
  /// Такт живёт только на время соединения и стоит одного чтения состояния.
  Timer? _tipTicker;

  void _syncTooltipTicker() {
    _tipTicker?.cancel();
    _tipTicker = null;
    if (_connected) {
      _tipTicker = Timer.periodic(
          const Duration(seconds: 1), (_) => unawaited(_pushTooltip()));
    }
  }

  Future<void> _pushTooltip() async {
    final tip = _currentTooltip();
    if (tip == _lastTip) return;
    _lastTip = tip;
    try {
      await trayManager.setToolTip(tip);
    } catch (_) {
      // Трея может не быть (запуск без окна) — не повод падать.
    }
  }

  String _currentTooltip() {
    if (_blocked) {
      return composeTooltip(blocked: _blockedNote());
    }
    if (!_connected) return composeTooltip();
    final ctx = _ctx;
    if (ctx == null) return composeTooltip();
    try {
      final state = ctx.read<AppState>();
      final l = AppLocalizations.of(ctx);
      // Имя сервера отдаём как есть: это данные, а не интерфейсный текст.
      // Автовыбор имени не имеет — берём ту же подпись, что и главный экран.
      final server = state.selectedServer?.displayName ?? l.homeAutoBest;
      return composeTooltip(server: server, speed: speedLine(state.stats));
    } catch (_) {
      // Состояние ещё не подключено к дереву — подсказка не тот повод падать.
      return composeTooltip();
    }
  }

  /// Текст про удержанный трафик.
  ///
  /// Остаётся русским литералом, как и был: своего ключа в ARB у него нет, а
  /// заводить его ради одной строки значит оставить восемь языков без перевода.
  String _blockedNote() => 'соединение потеряно, трафик заблокирован';
}
