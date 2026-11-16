import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import 'sel_text.dart';

/// Диалог перезагрузки живого VPN при добавлении нового сайта или при
/// обнаружении расхождения активных соединений с обновлённым списком сайтов.
///
/// Поддерживает постоянную галочку [AppSettings.alwaysReloadVpnOnNewSite].
Future<bool> showVpnReloadPromptDialog(
  BuildContext context, {
  required String domain,
  required SettingsController settingsController,
  required AppState appState,
  required bool isLiveMismatch,
}) async {
  var alwaysReload = settingsController.settings.alwaysReloadVpnOnNewSite;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final l = AppLocalizations.of(ctx);
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.sync_problem_outlined,
                color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(l.liveConnsRouteMismatchTitle)),
          ]),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelText(isLiveMismatch
                    ? l.liveConnsRouteMismatchBody(domain)
                    : l.liveConnsNewSiteReloadBody(domain)),
                const SizedBox(height: 12),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: alwaysReload,
                  onChanged: (v) => setState(() => alwaysReload = v ?? false),
                  title: Text(l.splitAlwaysReloadOnNewSite),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l.liveConnsReloadNow),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );
    },
  );
  if (confirmed != true) return false;
  if (alwaysReload && !settingsController.settings.alwaysReloadVpnOnNewSite) {
    settingsController.update(
      (s) => s.copyWith(alwaysReloadVpnOnNewSite: true),
    );
  }
  unawaited(appState.reconnect(settingsController.settings));
  return true;
}
