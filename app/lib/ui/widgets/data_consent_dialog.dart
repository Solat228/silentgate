import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_store.dart';
import '../../core/platform/app_launcher.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/settings_controller.dart';
import '../layout/adaptive.dart';

/// Окно раскрытия данных и согласия (сборки Google Play и Microsoft Store).
///
/// [noticeOnly] — сборка GitHub: то же раскрытие, но без выбора, одна кнопка
/// «Понятно» (решение владельца 19.10.2026: согласие спрашивают магазины,
/// GitHub только сообщает).
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
  bool noticeOnly = false,
}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: !mandatory,
      builder: (ctx) => PopScope(
        canPop: !mandatory,
        child: DataConsentDialog(noticeOnly: noticeOnly),
      ),
    );

/// Спросить на первом запуске и сохранить ответ. Ничего не делает, если
/// уже спрашивали или сборка не из магазина (решает [needsAsking]).
///
/// [needsNotice] — сборка GitHub: показать раскрытие без выбора один раз.
Future<void> askDataConsentIfNeeded(
  BuildContext context,
  SettingsController settings, {
  required bool Function() needsAsking,
  bool Function()? needsNotice,
}) async {
  await settings.whenLoaded;
  if (!context.mounted) return;
  if (needsAsking()) {
    final ok = await showDataConsentDialog(context, mandatory: true);
    if (ok == null) return;
    await settings.update((s) => s.copyWith(deviceInfoConsent: ok));
  } else if (needsNotice != null && needsNotice()) {
    await showDataConsentDialog(context, mandatory: true, noticeOnly: true);
    await settings.update((s) => s.copyWith(deviceInfoNoticeShown: true));
  }
}

class DataConsentDialog extends StatelessWidget {
  const DataConsentDialog({super.key, this.noticeOnly = false, this.windows});

  /// Только раскрытие, без выбора (сборка GitHub).
  final bool noticeOnly;

  /// Текст про Windows (HWID компьютера) или Android (Android ID). `null` —
  /// по платформе.
  final bool? windows;

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
              para((windows ?? Platform.isWindows)
                  ? l.consentDeviceBodyWindows
                  : l.consentDeviceBody),
              para(noticeOnly ? l.consentNoticeNote : l.consentDeclineNote,
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: noticeOnly
          ? [
              FilledButton(
                key: const Key('consentNoticeOk'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l.consentNoticeOk),
              ),
            ]
          : [
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
