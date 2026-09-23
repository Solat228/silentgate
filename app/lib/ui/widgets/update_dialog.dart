import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/platform/app_launcher.dart';
import '../../core/update/app_update.dart';
import '../../core/update/update_installer.dart';
import '../../core/update/update_manifest.dart' show normalizeVersion;
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_update_controller.dart';
import '../layout/adaptive.dart';
import 'sel_text.dart';

/// ОКНО «ДОСТУПНО ОБНОВЛЕНИЕ» — и общие для интерфейса самообновления тексты
/// и действия (экран «Обновления», главный экран, этот диалог).
///
/// Заменило `UpdateNotesDialog` (до 1.14.0 окно только открывало ссылку).
/// Теперь «Обновить» качает установщик, проверяет подпись и ставит — всё через
/// [AppUpdateController], интерфейс своего потока не заводит.
///
/// ⚠️ ЧТО ЗДЕСЬ СТЕРЕЖЁТСЯ (`test/update_dialog_test.dart`):
///  * окно читается и закрывается на любом телефоне — описание релиза бывает
///    на десятки строк, и без ограничения высоты кнопки уезжали за край
///    (жалоба владельца 19.08.2026 — ради неё прежнее окно и появилось);
///  * **живой VPN рвётся только после предупреждения.** Установщик закрывает
///    приложение вместе с ядрами; при активном VPN окно показывает это прямо
///    над кнопками, и только тогда «Обновить» передаёт `forceQuit: true`;
///  * «Позже» и «Пропустить» — разные вещи: первое молчит до следующего
///    запуска, второе — до следующей, более новой версии.

/// Показать окно обновления для текущего предложения контроллера.
///
/// [linkReason] — ставить самим нельзя (решено заранее по
/// [AppUpdateController.installCapability]): вместо «Обновить» — «Открыть
/// страницу» и объяснение. Кнопка, которая после нажатия выяснила бы, что
/// ничего не может, — та же обманка, только с задержкой.
Future<void> showUpdateDialog(
  BuildContext context,
  AppUpdateController controller, {
  LinkOnlyReason? linkReason,
}) async {
  final offer = controller.offer;
  if (offer == null) return;
  await showDialog<void>(
    context: context,
    builder: (_) => UpdateDialog(
      controller: controller,
      offer: offer,
      linkReason: linkReason,
    ),
  );
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.controller,
    required this.offer,
    this.linkReason,
  });

  final AppUpdateController controller;

  /// Предложение на момент открытия: после «Пропустить» контроллер его не
  /// забывает, но окно не должно зависеть от того, что с ним случится дальше.
  final UpdateOffer offer;
  final LinkOnlyReason? linkReason;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lines = formatNotes(offer.notes ?? '');
    final canInstall = linkReason == null;
    // Спрашиваем в момент сборки: окно живёт секунды, а предупреждение обязано
    // совпадать с тем, что увидит установщик при нажатии.
    final vpn = canInstall && controller.vpnActive;
    final size = offer.assetSize;

    final header = <Widget>[
      if (offer.isBeta)
        const Padding(
          padding: EdgeInsetsDirectional.only(bottom: 6),
          child: UpdateBetaBadge(),
        ),
      if (canInstall && size != null && size > 0)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 6),
          child: Text(l.updatesSizeMb(formatMegabytes(size)),
              style: theme.textTheme.bodySmall),
        ),
      if (vpn)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: UpdateNoticeBox(
            key: const Key('updateDialogVpnWarning'),
            icon: Icons.vpn_lock,
            error: true,
            title: l.updatesVpnWarning,
            body: l.updatesVpnWarningBody,
          ),
        ),
      if (!canInstall)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: UpdateNoticeBox(
            key: const Key('updateDialogLinkReason'),
            icon: Icons.info_outline,
            body: linkOnlyReasonText(l, linkReason!),
          ),
        ),
      if (canInstall && Platform.isAndroid)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: Text(l.updatesAndroidNoSilent,
              style: theme.textTheme.bodySmall),
        ),
    ];

    final skip = TextButton(
      key: const Key('updateDialogSkip'),
      onPressed: () {
        unawaited(controller.skipVersion());
        Navigator.of(context).pop();
      },
      child: Text(l.updatesSkipVersion),
    );
    final later = TextButton(
      key: const Key('updateDialogLater'),
      onPressed: () {
        controller.postpone();
        Navigator.of(context).pop();
      },
      child: Text(l.updatesLater),
    );
    final primary = canInstall
        ? FilledButton(
            key: const Key('updateDialogInstall'),
            onPressed: () {
              Navigator.of(context).pop();
              // Согласие на разрыв VPN дано ровно тогда, когда предупреждение
              // было на экране. Если VPN поднимут уже во время закачки,
              // контроллер без forceQuit отложит установку до отключения.
              unawaited(startUpdate(controller, forceQuit: vpn));
            },
            child: Text(l.updatesInstall),
          )
        : FilledButton(
            key: const Key('updateDialogOpenPage'),
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(openUpdatePage(offer));
            },
            child: Text(l.updatesOpenPage),
          );

    // ⚠️ КНОПКИ НА ТЕЛЕФОНЕ — ДВА РЯДА, А НЕ ТРИ СТРОКИ. Три кнопки в один ряд
    // на телефоне не влезают, и `AlertDialog` ставит их столбиком по правому
    // краю: главная оказывается третьей строкой, а «Пропустить» — самой
    // заметной (живой прогон 24.09.2026). Здесь главная — во всю ширину
    // сверху, второстепенные — рядом под ней.
    final compact = MediaQuery.sizeOf(context).width < 600;

    return AlertDialog(
      title: Text(l.updatesDialogTitle(offer.version)),
      // ⚠️ ВЫСОТА — ПОТОЛОК, А НЕ РАЗМЕР: окно облегает содержимое и
      // прокручивается, только упершись в потолок. Ширину и потолок считает
      // общий помощник: на телефоне 460×420 недостижимы, и настаивать на них —
      // это и есть окно, у которого кнопки уезжают за край экрана.
      content: adaptiveDialogBody(
        context,
        width: 460,
        height: 420,
        hugContent: true,
        extraChrome: compact ? 48 : 0,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...header,
              if (lines.isEmpty)
                Text(l.updateNotesEmpty)
              else
                for (final line in lines)
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: line.bullet ? 12 : 0,
                      top: line.heading ? 10 : 2,
                      bottom: 2,
                    ),
                    child: SelText(
                      line.bullet ? '•  ${line.text}' : line.text,
                      style: line.heading
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.bodyMedium,
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: compact
          ? [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  primary,
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: skip),
                      Flexible(child: later),
                    ],
                  ),
                ],
              ),
            ]
          : [
              skip,
              later,
              // ⚠️ ГЛАВНАЯ КНОПКА ПОСЛЕДНЯЯ — ближайшая к большому пальцу.
              primary,
            ],
    );
  }

  /// Разобрать markdown в простые читаемые строки.
  ///
  /// ⚠️ ЭТО НАМЕРЕННО НЕ ПОЛНОЦЕННЫЙ ОТРИСОВЩИК MARKDOWN. Тянуть библиотеку
  /// ради описания релиза — лишняя зависимость и лишний вес; а показывать сырой
  /// текст, как было до 19.08.2026, нельзя. Нужен минимум: убрать разметку,
  /// которая мешает читать, и сохранить структуру — заголовки и списки.
  ///
  /// Публичная нарочно: её проверяют тестом отдельно от вёрстки.
  static List<NoteLine> formatNotes(String raw) {
    final out = <NoteLine>[];
    for (final rawLine in raw.split('\n')) {
      var t = rawLine.trim();
      if (t.isEmpty) continue;
      // Горизонтальные линейки в тексте только мешают.
      if (RegExp(r'^-{3,}$').hasMatch(t)) continue;

      final heading = t.startsWith('#');
      if (heading) t = t.replaceFirst(RegExp(r'^#+\s*'), '');

      final bullet = t.startsWith('- ') || t.startsWith('* ');
      if (bullet) t = t.substring(2);

      // Жирный, курсив, code и ссылки — снимаем разметку, оставляем текст.
      t = t
          .replaceAll(RegExp(r'\*\*'), '')
          .replaceAll(RegExp(r'`'), '')
          .replaceAllMapped(
              RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!);

      if (t.isEmpty) continue;
      out.add(NoteLine(text: t, bullet: bullet, heading: heading));
    }
    return out;
  }
}

/// Строка описания релиза после разбора разметки.
class NoteLine {
  final String text;
  final bool bullet;
  final bool heading;
  const NoteLine({
    required this.text,
    this.bullet = false,
    this.heading = false,
  });
}

// ── Общие действия ───────────────────────────────────────────────────────────

/// Согласие получено: скачать (если ещё не скачано) и поставить.
///
/// Одна функция на диалог, экран и «Прежние версии» — иначе три копии
/// порядка «скачать → проверить фазу → установить» разошлись бы на первой
/// правке. [forceQuit] — человек видел предупреждение о разрыве VPN;
/// [allowDowngrade] — осознанный откат из «Прежних версий».
Future<void> startUpdate(
  AppUpdateController c, {
  bool forceQuit = false,
  bool allowDowngrade = false,
}) =>
    // Порядок живёт в контроллере: там же он запоминается на случай, если
    // Android попросит разрешение и убьёт процесс (см. `ConsentMarker`).
    c.downloadAndInstall(forceQuit: forceQuit, allowDowngrade: allowDowngrade);

/// Открыть страницу релиза (или общую страницу загрузок, если у релиза её нет).
Future<void> openUpdatePage(UpdateOffer? offer) {
  final page = offer?.pageUrl;
  return UrlOpener.open(
      page != null && page.isNotEmpty ? page : AppUpdate.releasesPage);
}

/// «Установка разорвёт VPN» — подтверждение перед `forceQuit: true`.
/// `true` — человек согласился.
Future<bool> confirmVpnBreak(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.updatesVpnWarning),
      content: Text(l.updatesVpnWarningBody),
      actions: [
        TextButton(
          key: const Key('updateVpnConfirmCancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          key: const Key('updateVpnConfirmOk'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.updatesInstall),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Журнал неудачной установки — хвост, который собрал `reconcileAfterStart`.
Future<void> showInstallLog(BuildContext context, PendingResult result) {
  final l = AppLocalizations.of(context);
  final tail = result.logTail ?? '';
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.updatesInstallFailedTitle),
      content: adaptiveDialogBody(
        ctx,
        width: 560,
        height: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.updatesInstallFailedBody(
                  normalizeVersion(result.pending.version))),
              const SizedBox(height: 8),
              // Журнал — технический текст: слева направо в любой локали,
              // моноширинный, выделяемый (его пересылают в поддержку).
              SelText(
                tail,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.commonClose),
        ),
      ],
    ),
  );
}

// ── Тексты ───────────────────────────────────────────────────────────────────

/// Размер в мегабайтах с одним знаком — для «{mb} МБ».
String formatMegabytes(int bytes) =>
    (bytes / (1024 * 1024)).toStringAsFixed(1);

/// Почему вместо установки — ссылка. Каждая причина — своё объяснение: у них
/// разное лечение, и «установите вручную» без причины звучит как поломка.
String linkOnlyReasonText(AppLocalizations l, LinkOnlyReason reason) =>
    switch (reason) {
      LinkOnlyReason.notifyOnly => l.updatesLinkNotify,
      LinkOnlyReason.noSelfUpdate => l.updatesLinkNoSelfUpdate,
      LinkOnlyReason.portable => l.updatesPortableFallback,
      LinkOnlyReason.notInstalled => l.updatesPortableFallback,
      LinkOnlyReason.isolated => l.updatesLinkIsolated,
      LinkOnlyReason.locationMismatch => l.updatesLinkLocation,
      LinkOnlyReason.elevated => l.updatesLinkElevated,
      LinkOnlyReason.unsupported => l.updatesLinkUnsupported,
    };

/// Причина отказа — по ТИПУ ошибки, а не текстом исключения: тот уходит только
/// в журнал (и без адресов, см. `scrubUrls`).
String updateErrorText(AppLocalizations l, UpdateError e) => switch (e.kind) {
      UpdateErrorKind.checkFailed => l.updatesErrCheck,
      UpdateErrorKind.insecureUrl => l.updatesErrInsecure,
      UpdateErrorKind.unsafeAssetName => l.updatesErrAssetName,
      UpdateErrorKind.manifestUnavailable => l.updatesErrManifest,
      UpdateErrorKind.badSignature => l.updatesErrSignature,
      UpdateErrorKind.manifestRejected => l.updatesErrManifestRejected,
      UpdateErrorKind.downloadFailed => l.updatesErrDownload,
      UpdateErrorKind.installFailed => l.updatesErrInstall,
      UpdateErrorKind.notNewer => l.updatesErrNotNewer,
    };

// ── Общие виджеты ────────────────────────────────────────────────────────────

/// Плашка «БЕТА» — одна на диалог, экран «Обновления» и «Прежние версии»,
/// чтобы пре-релиз выглядел одинаково узнаваемо везде.
class UpdateBetaBadge extends StatelessWidget {
  const UpdateBetaBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          l.appUpdateBetaBadge,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: scheme.onTertiaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Плашка-пояснение: значок + (заголовок) + текст. [error] — красная.
class UpdateNoticeBox extends StatelessWidget {
  const UpdateNoticeBox({
    super.key,
    required this.icon,
    required this.body,
    this.title,
    this.error = false,
  });

  final IconData icon;
  final String? title;
  final String body;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final bg = error ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final fg = error ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Text(title!,
                        style: text.titleSmall?.copyWith(color: fg)),
                  Text(body, style: text.bodySmall?.copyWith(color: fg)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
