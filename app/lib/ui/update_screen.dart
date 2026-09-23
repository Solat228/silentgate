import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/platform/app_launcher.dart';
import '../core/settings/app_settings.dart';
import '../core/update/app_update.dart';
import '../core/update/update_installer.dart';
import '../core/update/update_manifest.dart' show normalizeVersion;
import '../l10n/gen/app_localizations.dart';
import '../state/app_update_controller.dart';
import '../state/settings_controller.dart';
import 'settings_screen.dart' show kSettingsContentMaxWidth;
import 'widgets/info_tooltip.dart';
import 'widgets/update_dialog.dart';

/// Источник списка «Прежних версий» — подменяется тестом.
typedef ReleaseHistoryLoader = Future<List<AppRelease>> Function();

/// ЭКРАН «ОБНОВЛЕНИЯ» (Настройки → Обновления).
///
/// Всё про обновление самого приложения в одном месте: какая версия стоит,
/// что с проверкой сейчас, как обновляться, бета-канал и откат. До 1.14.0 это
/// был блок в «О программе», который умел только открыть ссылку; теперь
/// экран — лицо [AppUpdateController] и своего потока не заводит.
///
/// ⚠️ НИКАКИХ КОНТРОЛОВ-ОБМАНОК.
///  * «Скачать» показывается только там, где установка сработает
///    ([AppUpdateController.installCapability] == ready и у релиза есть
///    подписанный манифест). Иначе — причина и «Открыть страницу»: кнопка,
///    которая после закачки выяснила бы, что ставить нельзя, — обманка с
///    задержкой.
///  * Режимы обновления — только на Windows и Android: на прочих платформах
///    установщика нет, и выбор «автоматически» ничего бы не значил.
///  * «Установить» в «Прежних версиях» — только у установленной копии
///    Windows. Android откатиться поверх более новой версии не даёт.
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key, this.releaseHistory});

  /// `null` — настоящий список релизов GitHub.
  final ReleaseHistoryLoader? releaseHistory;

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  /// Может ли эта копия ставить сама; `null` — ещё не узнали.
  InstallCapability? _cap;

  @override
  void initState() {
    super.initState();
    unawaited(context
        .read<AppUpdateController>()
        .installCapability()
        .then((c) => mounted ? setState(() => _cap = c) : null)
        .catchError((Object _) {}));
  }

  /// Самообновление возможно на этой платформе в принципе.
  static bool get _platformSupported => Platform.isWindows || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.watch<AppUpdateController>();
    final settingsCtrl = context.watch<SettingsController>();
    final s = settingsCtrl.settings;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.updatesTitle)),
      body: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSettingsContentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // ⚠️ Подменённый источник — первым и красным: на стенде это
              // нормально, у обычного человека такого не бывает никогда.
              if (c.overridden)
                const Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                  child: _OverrideBanner(),
                ),
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: Text(l.updatesCurrentVersion(AppInfo.version)),
                subtitle: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(AppInfo.isBeta
                        ? l.updatesChannelBeta
                        : l.updatesChannelStable),
                    if (AppInfo.isBeta) const UpdateBetaBadge(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                child: _StatusCard(controller: c, capability: _cap),
              ),
              const Divider(),
              if (_platformSupported) ...[
                ListTile(
                  title: Row(children: [
                    Flexible(
                      child: Text(l.updatesModeTitle,
                          style: theme.textTheme.titleSmall),
                    ),
                    InfoTooltip(l.updatesInfo),
                  ]),
                ),
                RadioGroup<AppUpdateMode>(
                  groupValue: s.appUpdateMode,
                  onChanged: (m) {
                    if (m == null) return;
                    unawaited(settingsCtrl
                        .update((x) => x.copyWith(appUpdateMode: m)));
                  },
                  child: Column(children: [
                    _modeTile(AppUpdateMode.ask, l.updatesModeAsk,
                        l.updatesModeAskHint),
                    _modeTile(AppUpdateMode.auto, l.updatesModeAuto,
                        l.updatesModeAutoHint),
                    _modeTile(AppUpdateMode.notifyOnly, l.updatesModeNotify,
                        l.updatesModeNotifyHint),
                  ]),
                ),
              ],
              SwitchListTile(
                key: const Key('updatesAutoCheckSwitch'),
                value: s.appUpdateCheck,
                onChanged: (v) => unawaited(
                    settingsCtrl.update((x) => x.copyWith(appUpdateCheck: v))),
                title: Text(l.updatesAutoCheck),
              ),
              SwitchListTile(
                key: const Key('updatesBetaSwitch'),
                value: s.betaChannel,
                onChanged: (v) => unawaited(
                    settingsCtrl.update((x) => x.copyWith(betaChannel: v))),
                title: Row(children: [
                  Flexible(child: Text(l.updatesBeta)),
                  const SizedBox(width: 6),
                  const UpdateBetaBadge(),
                  InfoTooltip(l.infoAppUpdateBeta),
                ]),
              ),
              ListTile(
                key: const Key('updatesPreviousVersionsTile'),
                leading: const Icon(Icons.history),
                title: Text(l.updatesPreviousVersions),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showPreviousVersions(context),
              ),
              const Divider(),
              _Note(icon: Icons.verified_user_outlined, text: l.updatesSignatureNote),
              if (Platform.isAndroid)
                _Note(icon: Icons.info_outline, text: l.updatesAndroidNoSilent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeTile(AppUpdateMode m, String title, String hint) =>
      RadioListTile<AppUpdateMode>(
        key: ValueKey('updatesMode-${m.name}'),
        value: m,
        title: Text(title),
        subtitle: Text(hint),
      );

  /// Можно ли откатиться на [r] ЗДЕСЬ: установленная копия Windows и релиз
  /// с подписанным манифестом. На Android система не ставит более старую
  /// версию поверх новой, а портативной копии нечем.
  bool _canInstall(AppRelease r) =>
      Platform.isWindows && _cap == InstallCapability.ready && r.canSelfUpdate;

  /// «Прежние версии» — список последних релизов GitHub. Сеть — только по
  /// нажатию: список не нужен, пока человек явно не попросил откатиться.
  Future<void> _showPreviousVersions(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final c = context.read<AppUpdateController>();
    final load = widget.releaseHistory ?? AppUpdate.fetchReleaseHistory;
    final picked = await showDialog<AppRelease>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.updatesPreviousVersions),
        content: SizedBox(
          width: 420,
          child: FutureBuilder<List<AppRelease>>(
            future: load(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  height: 96,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final list = snap.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⚠️ ЧЕСТНОСТЬ СПИСКА — ПРЯМО В ДИАЛОГЕ: это ровно то, что
                  // лежит в GitHub Releases, и каких-то версий там может не быть.
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 8),
                    child: Text(l.appUpdatePreviousVersionsHint,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(l.appUpdatePreviousVersionsEmpty),
                    )
                  else
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) =>
                              _releaseTile(context, ctx, list[i], c),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.commonClose)),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    await _rollbackTo(context, c, picked);
  }

  Widget _releaseTile(BuildContext context, BuildContext dialogCtx,
      AppRelease r, AppUpdateController c) {
    final l = AppLocalizations.of(context);
    final d = r.publishedAt;
    final dateStr = d == null
        ? ''
        : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
    final installable = _canInstall(r) && !c.busy;
    return ListTile(
      dense: true,
      title: Row(children: [
        Text('v${normalizeVersion(r.version)}',
            textDirection: TextDirection.ltr),
        if (r.isBeta) ...[
          const SizedBox(width: 6),
          const UpdateBetaBadge(),
        ],
      ]),
      subtitle: dateStr.isEmpty
          ? null
          : Text(dateStr, textDirection: TextDirection.ltr),
      trailing: installable
          ? TextButton(
              key: Key('updatesInstallOlder-${normalizeVersion(r.version)}'),
              onPressed: () => Navigator.of(dialogCtx).pop(r),
              child: Text(l.updatesInstallOlder),
            )
          : IconButton(
              key: Key('updatesOpenRelease-${normalizeVersion(r.version)}'),
              tooltip: l.appUpdateOpenRelease,
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => UrlOpener.open(
                (r.downloadUrl ?? '').isNotEmpty
                    ? r.downloadUrl!
                    : (r.pageUrl ?? AppUpdate.releasesPage),
              ),
            ),
    );
  }

  /// Откат (или переход на выбранную версию): подтверждение → закачка с
  /// проверкой подписи → установка с `allowDowngrade`. Без подтверждения
  /// откат не начинается: контроллер отказывает ставить не-новую версию
  /// именно потому, что это должно быть решением человека.
  Future<void> _rollbackTo(
      BuildContext context, AppUpdateController c, AppRelease r) async {
    final l = AppLocalizations.of(context);
    final older = !AppUpdate.isNewer(r.version, c.currentVersion);
    final vpn = c.vpnActive;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('v${normalizeVersion(r.version)}',
            textDirection: TextDirection.ltr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (older) Text(l.updatesDowngradeWarning),
            if (vpn) ...[
              if (older) const SizedBox(height: 8),
              UpdateNoticeBox(
                key: const Key('updatesRollbackVpnWarning'),
                icon: Icons.vpn_lock,
                error: true,
                title: l.updatesVpnWarning,
                body: l.updatesVpnWarningBody,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const Key('updatesRollbackCancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            key: const Key('updatesRollbackConfirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.updatesInstallOlder),
          ),
        ],
      ),
    );
    if (ok != true) return;
    c.offerRelease(r);
    await startUpdate(c, forceQuit: vpn, allowDowngrade: true);
  }
}

/// Карточка состояния: что происходит сейчас и что с этим можно сделать.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller, required this.capability});

  final AppUpdateController controller;
  final InstallCapability? capability;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = controller;
    final theme = Theme.of(context);
    final offer = c.offer;

    String? status;
    String? detail;
    double? progress;
    var showProgress = false;
    final actions = <Widget>[];

    // Ставить самим нельзя — причина известна ДО закачки.
    LinkOnlyReason? earlyReason;
    if (offer != null && c.phase == UpdatePhase.available) {
      if (capability != null && capability != InstallCapability.ready) {
        earlyReason = AppUpdateController.linkOnlyReasonFor(capability!);
      } else if (!offer.canSelfUpdate) {
        earlyReason = LinkOnlyReason.noSelfUpdate;
      }
    }

    Widget openPage() => OutlinedButton.icon(
          key: const Key('updatesOpenPageButton'),
          onPressed: () => unawaited(openUpdatePage(offer)),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(l.updatesOpenPage),
        );

    switch (c.phase) {
      case UpdatePhase.idle:
        if (c.offerIsSkipped && offer != null) {
          status = l.updatesSkippedNote(offer.version);
        }
      case UpdatePhase.checking:
        status = l.updatesStatusChecking;
        showProgress = true;
      case UpdatePhase.upToDate:
        status = l.updatesStatusUpToDate;
      case UpdatePhase.available:
        status = l.updatesStatusAvailable(offer?.version ?? '');
        if (earlyReason != null) {
          detail = linkOnlyReasonText(l, earlyReason);
          actions.add(openPage());
        } else if (capability != null) {
          actions.add(FilledButton.icon(
            key: const Key('updatesDownloadButton'),
            onPressed: () => unawaited(c.download()),
            icon: const Icon(Icons.download, size: 18),
            label: Text(l.updatesDownload),
          ));
        }
      case UpdatePhase.downloading:
        final p = c.progress;
        status = l.updatesStatusDownloading(((p ?? 0) * 100).round());
        progress = p;
        showProgress = true;
        actions.add(_cancelButton(l));
      case UpdatePhase.verifying:
        status = l.updatesStatusVerifying;
        showProgress = true;
        actions.add(_cancelButton(l));
      case UpdatePhase.ready:
        if (c.waitingForVpnOff) {
          status = l.updatesWaitingVpn;
          actions.add(FilledButton(
            key: const Key('updatesInstallNowButton'),
            onPressed: () => _install(context, confirm: true),
            child: Text(l.updatesInstallNow),
          ));
        } else {
          status = l.updatesStatusReady;
          actions.add(FilledButton(
            key: const Key('updatesInstallButton'),
            onPressed: () => _install(context, confirm: c.vpnActive),
            child: Text(l.updatesInstall),
          ));
        }
      case UpdatePhase.installing:
        status = l.updatesStatusInstalling;
        showProgress = true;
        if (Platform.isAndroid) detail = l.updatesAndroidNoSilent;
      case UpdatePhase.failed:
        final e = c.error;
        status = l.updatesStatusFailed(
            e == null ? l.updatesErrCheck : updateErrorText(l, e));
        // Повтор закачки — если отказ случился на ней, а не на проверке.
        if (offer != null && e != null && e.kind != UpdateErrorKind.checkFailed) {
          actions.add(OutlinedButton(
            key: const Key('updatesRetryButton'),
            onPressed: () => unawaited(c.download()),
            child: Text(l.updatesDownload),
          ));
        }
      case UpdatePhase.needsPermission:
        status = l.updatesStatusNeedsPermission;
        detail = l.updatesAndroidUnknownSources;
        actions.add(FilledButton(
          key: const Key('updatesOpenPermissionButton'),
          onPressed: () => unawaited(c.openInstallPermission()),
          child: Text(l.updatesAndroidOpenSettings),
        ));
      case UpdatePhase.linkOnly:
        status = offer == null
            ? l.updatesStatusLinkOnly
            : l.updatesStatusAvailable(offer.version);
        final reason = c.linkOnlyReason;
        detail = reason == null
            ? l.updatesStatusLinkOnly
            : linkOnlyReasonText(l, reason);
        actions.add(openPage());
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (status != null)
              Row(children: [
                Flexible(
                  child: Text(status,
                      key: const Key('updatesStatusText'),
                      style: theme.textTheme.titleSmall),
                ),
                if (offer != null && offer.isBeta &&
                    c.phase != UpdatePhase.upToDate &&
                    c.phase != UpdatePhase.checking) ...[
                  const SizedBox(width: 6),
                  const UpdateBetaBadge(),
                ],
              ]),
            if (detail != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 4),
                child: Text(detail,
                    key: const Key('updatesStatusDetail'),
                    style: theme.textTheme.bodySmall),
              ),
            if (showProgress)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 8),
                child: LinearProgressIndicator(value: progress),
              ),
            if (status != null || detail != null || showProgress)
              const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonal(
                key: const Key('updatesCheckButton'),
                onPressed: c.busy || c.phase == UpdatePhase.installing
                    ? null
                    : () => unawaited(c.checkNow()),
                child: Text(l.updatesCheckNow),
              ),
              ...actions,
            ]),
          ],
        ),
      ),
    );
  }

  Widget _cancelButton(AppLocalizations l) => OutlinedButton(
        key: const Key('updatesCancelButton'),
        onPressed: controller.cancel,
        child: Text(l.commonCancel),
      );

  /// «Установить»: при живом VPN — только после предупреждения, и тогда с
  /// `forceQuit`; без согласия ничего не происходит.
  Future<void> _install(BuildContext context, {required bool confirm}) async {
    if (confirm) {
      if (!await confirmVpnBreak(context)) return;
    }
    await controller.install(forceQuit: confirm);
  }
}

class _OverrideBanner extends StatelessWidget {
  const _OverrideBanner();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return UpdateNoticeBox(
      key: const Key('updatesOverrideBanner'),
      icon: Icons.science_outlined,
      error: true,
      body: l.updatesOverrideBadge,
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
