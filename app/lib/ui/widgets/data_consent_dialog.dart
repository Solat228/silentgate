import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_store.dart';
import '../../core/platform/app_launcher.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/settings_controller.dart';
import '../layout/adaptive.dart';

/// Окно раскрытия данных и согласия (сборка Google Play).
///
/// Правила Play требуют заметного раскрытия ДО отправки идентификатора
/// устройства и явного выбора — оба варианта равноправны, отказ не ломает
/// приложение (подписка просто грузится без заголовков устройства). Что
/// именно отправляется и почему — `core/privacy/device_info_consent.dart`.
///
/// [mandatory] — первый запуск: окно нельзя смахнуть, нужен ответ. Из
/// настроек оно открывается обычным (закрыть = ничего не менять).
///
/// Возвращает выбор человека; `null` — закрыл, не выбрав.
Future<bool?> showDataConsentDialog(
  BuildContext context, {
  bool mandatory = false,
}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: !mandatory,
      builder: (ctx) => PopScope(
        canPop: !mandatory,
        child: const DataConsentDialog(),
      ),
    );

/// Спросить на первом запуске и сохранить ответ. Ничего не делает, если
/// уже спрашивали или сборка не из Play (решает [needsAsking]).
Future<void> askDataConsentIfNeeded(
  BuildContext context,
  SettingsController settings, {
  required bool Function() needsAsking,
}) async {
  await settings.whenLoaded;
  if (!context.mounted || !needsAsking()) return;
  final ok = await showDataConsentDialog(context, mandatory: true);
  if (ok == null) return;
  await settings.update((s) => s.copyWith(deviceInfoConsent: ok));
}

class DataConsentDialog extends StatelessWidget {
  const DataConsentDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget para(String text, {TextStyle? style}) => Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 10),
          child: Text(text, style: style ?? theme.textTheme.bodyMedium),
        );

    return AlertDialog(
      title: Text(l.consentTitle),
      content: adaptiveDialogBody(
        context,
        width: 460,
        height: 460,
        hugContent: true,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              para(l.consentIntro),
              // Ссылка на политику — сразу под первым абзацем: в конце
              // прокрутки на телефоне её не видно, пока не прокрутишь.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('consentPolicyButton'),
                  onPressed: () =>
                      unawaited(UrlOpener.open(AppStoreInfo.privacyPolicyUrl)),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l.consentPolicy),
                ),
              ),
              para(l.consentDeviceTitle, style: theme.textTheme.titleSmall),
              para(l.consentDeviceBody),
              para(l.consentDeclineNote, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('consentDecline'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.consentDecline),
        ),
        FilledButton(
          key: const Key('consentAccept'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.consentAccept),
        ),
      ],
    );
  }
}
