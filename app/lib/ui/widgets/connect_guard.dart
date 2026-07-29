import 'package:flutter/material.dart';

import '../../core/models/vpn_status.dart';
import '../../core/platform/interference_scanner.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import 'app_toast.dart';

/// Подключение с проверкой чужого VPN ДО старта.
///
/// Раньше про мешающий туннель узнавали только из ошибки — то есть после
/// минуты ожидания и неудачи. Спрашиваем заранее: чужой TUN держит маршрут по
/// умолчанию, и рядом с ним наш туннель либо не поднимется, либо поднимется
/// криво.
///
/// При ОТКЛЮЧЕНИИ ничего не проверяем: чужой VPN там не мешает, а лишний
/// диалог на кнопке «Отключить» — это уже вредительство.
Future<void> connectWithConflictCheck(
  BuildContext context, AppState state, VoidCallback go) async {
  final busy = state.status.isConnected ||
      state.status.state == VpnConnectionState.connecting;
  if (busy) {
    go(); // это нажатие «Отключить»
    return;
  }

  final conflict = await InterferenceScanner.activeForeignTunnel();
  if (!context.mounted) return;
  if (conflict == null) {
    go();
    return;
  }

  final l = AppLocalizations.of(context);
  final app = conflict.appName!;
  final choice = await showDialog<String>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text(l.conflictDialogTitle),
      content: Text(l.conflictDialogBody(app)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(l.commonCancel)),
        // «Всё равно» оставляем осознанно: чужой адаптер не всегда забирает
        // маршрут по умолчанию, и запрещать пользователю пробовать мы не
        // вправе — он про свой компьютер знает больше нас.
        TextButton(
            onPressed: () => Navigator.pop(dctx, 'anyway'),
            child: Text(l.conflictConnectAnyway)),
        FilledButton(
            onPressed: () => Navigator.pop(dctx, 'close'),
            child: Text(l.conflictCloseAndConnect)),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'anyway') {
    go();
    return;
  }

  final ok = await InterferenceScanner.kill(conflict.pid!);
  if (!context.mounted) return;
  if (!ok) {
    AppToast.show(context, l.toastAppCloseFailed(app), kind: ToastKind.error);
    return;
  }
  // Процесс убит, но АДАПТЕР исчезает не мгновенно: система снимает маршруты
  // с задержкой. Подключаться, пока он жив, — значит наступить ровно на ту
  // проблему, от которой только что избавились.
  final gone = await InterferenceScanner.waitTunnelGone();
  if (!context.mounted) return;
  AppToast.show(context, l.toastAppClosed(app),
      kind: gone ? ToastKind.success : ToastKind.info);
  go();
}
