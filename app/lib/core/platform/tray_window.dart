import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_nav.dart';
import '../../l10n/gen/app_localizations.dart';
import '../models/vpn_status.dart';
import 'core_cleanup.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../../ui/widgets/connect_guard.dart';

/// Трей + умное закрытие: крестик сворачивает в трей (по умолчанию) или закрывает
/// (по настройке), с диалогами про активный VPN и «не спрашивать больше».
class TrayWindow with WindowListener, TrayListener {
  static final TrayWindow instance = TrayWindow._();
  TrayWindow._();

  Future<void> init() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    trayManager.addListener(this);
    // Окно показываем ТОЛЬКО когда оно готово и с ЯВНЫМ размером. Раньше задавался
    // лишь минимальный размер, а стартовый — нет: первый кадр рисовался в
    // дефолтном размере рантайма, и интерфейс «съезжал», пока окно не подвигать.
    // waitUntilReadyToShow держит окно скрытым до первого корректного кадра.
    const options = WindowOptions(
      size: Size(1040, 820),
      minimumSize: Size(980, 800),
      center: true,
      title: 'SilentGate',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPreventClose(true); // крестик → onWindowClose
      await windowManager.show();
      await windowManager.focus();
    });
    await _setupTray();
  }

  Future<void> _setupTray() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final iconPath =
          '$exeDir\\data\\flutter_assets\\assets\\tray_icon.ico';
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('SilentGate');
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

  BuildContext? get _ctx => navigatorKey.currentContext;

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
}
