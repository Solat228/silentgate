import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/app_log.dart';
import '../../core/platform/desktop_notice.dart';
import '../../core/settings/app_settings.dart';
import '../../core/update/app_update.dart';
import '../../core/update/update_installer.dart';
import '../../core/update/update_manifest.dart' show normalizeVersion;
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_update_controller.dart';
import '../update_screen.dart';
import 'app_toast.dart';
import 'update_dialog.dart';

/// ГОЛОС САМООБНОВЛЕНИЯ НА ГЛАВНОМ ЭКРАНЕ.
///
/// [AppUpdateController] решает, что делать; этот класс только ГОВОРИТ об этом
/// человеку, и ровно один раз на событие:
///  * итог установки прошлой жизни процесса — «Обновлено до X» или карточка
///    «Установка не завершилась» с журналом;
///  * найденная на старте версия (режим «спрашивать») — окно [UpdateDialog],
///    не больше одного за запуск;
///  * ход закачки — карточка слева снизу (`AppToast.progress`, id [toastId]);
///  * «только ссылка» — короткое сообщение с причиной и кнопкой страницы;
///  * Android: нет разрешения ставить — сообщение с кнопкой настроек, а по
///    возвращении в приложение установка повторяется сама.
///  * режим «авто» при свёрнутом окне Windows — системное уведомление ПЕРЕД
///    установкой: иначе приложение молча исчезло бы из трея.
///
/// ⚠️ ОТДЕЛЬНЫЙ КЛАСС, А НЕ МЕТОДЫ `HomeScreen`. Главный экран и так огромен,
/// а здесь нужна своя память («что уже показали») — размазанная по его
/// состоянию, она потерялась бы при первой же правке.
class AppUpdatePresenter with WidgetsBindingObserver {
  AppUpdatePresenter({
    required this.controller,
    required this.contextOf,
    required this.modeOf,
  });

  /// Ключ карточки хода закачки.
  static const toastId = 'app-update';

  final AppUpdateController controller;

  /// Живой контекст главного экрана; `null` — экран ушёл.
  final BuildContext? Function() contextOf;

  /// Текущий режим обновления из настроек.
  final AppUpdateMode Function() modeOf;

  bool _attached = false;
  bool _outcomeShown = false;
  bool _dialogShown = false;
  bool _dialogPending = false;
  String? _linkShownFor;
  bool _permissionShown = false;
  UpdatePhase? _lastPhase;

  /// Подписаться. Зовётся один раз, когда главный экран готов показывать
  /// окна (после проверки помех — два окна подряд друг друга перекрыли бы).
  void attach() {
    if (_attached) return;
    _attached = true;
    controller.addListener(_onChange);
    controller.beforeUnattendedInstall = _beforeUnattendedInstall;
    WidgetsBinding.instance.addObserver(this);
    // Контроллер мог отработать старт раньше, чем мы подписались.
    _onChange();
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    controller.removeListener(_onChange);
    if (controller.beforeUnattendedInstall == _beforeUnattendedInstall) {
      controller.beforeUnattendedInstall = null;
    }
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android: человек вернулся с экрана «устанавливать из этого приложения»
    // — повторяем установку сами. Согласие на неё уже дано: до экрана
    // разрешения установка доходит только после него (или без живого VPN).
    if (state == AppLifecycleState.resumed &&
        controller.phase == UpdatePhase.needsPermission) {
      _permissionShown = false;
      unawaited(controller.install(forceQuit: true));
    }
  }

  void _onChange() {
    final context = contextOf();
    if (context == null || !context.mounted) return;
    _showOutcome(context);
    _showProgress(context);
    _maybeDialog();
    _maybeLinkOnly(context);
    _maybePermission(context);
    _lastPhase = controller.phase;
  }

  // ── Итог прошлой установки ────────────────────────────────────────────────

  void _showOutcome(BuildContext context) {
    if (_outcomeShown) return;
    final r = controller.lastOutcome;
    if (r == null) return;
    _outcomeShown = true;
    final l = AppLocalizations.of(context);
    final v = normalizeVersion(r.pending.version);
    switch (r.outcome) {
      case PendingOutcome.updated:
        AppToast.show(context, l.updatesInstalledToast(v),
            kind: ToastKind.success);
      case PendingOutcome.failed:
        final hasLog = (r.logTail ?? '').isNotEmpty;
        AppToast.show(
          context,
          l.updatesInstallFailedTitle,
          kind: ToastKind.error,
          duration: const Duration(seconds: 30),
          actionLabel: hasLog ? l.updatesShowLog : null,
          onAction: hasLog
              ? () {
                  final c = contextOf();
                  if (c != null && c.mounted) {
                    unawaited(showInstallLog(c, r));
                  }
                }
              : null,
        );
      case PendingOutcome.stale:
        // Слишком старая запись: чем кончилось, уже не разобрать — молчим.
        break;
    }
  }

  // ── Ход закачки ───────────────────────────────────────────────────────────

  void _showProgress(BuildContext context) {
    final l = AppLocalizations.of(context);
    final phase = controller.phase;
    final was = _lastPhase;
    final wasActive =
        was == UpdatePhase.downloading || was == UpdatePhase.verifying;
    void open() {
      final c = contextOf();
      if (c == null || !c.mounted) return;
      unawaited(AppToast.openOnce(c,
          key: 'update-screen', builder: (_) => const UpdateScreen()));
    }

    switch (phase) {
      case UpdatePhase.downloading:
        final p = controller.progress;
        AppToast.progress(context,
            id: toastId,
            message: l.updatesStatusDownloading(((p ?? 0) * 100).round()),
            value: p,
            onTap: open,
            tapTooltip: l.updatesTitle);
      case UpdatePhase.verifying:
        AppToast.progress(context,
            id: toastId,
            message: l.updatesStatusVerifying,
            onTap: open,
            tapTooltip: l.updatesTitle);
      case UpdatePhase.ready || UpdatePhase.installing when wasActive:
        AppToast.progress(context,
            id: toastId,
            message: controller.waitingForVpnOff
                ? l.updatesWaitingVpn
                : l.updatesStatusReady,
            finished: true,
            kind: ToastKind.success,
            onTap: open,
            tapTooltip: l.updatesTitle);
      case UpdatePhase.failed when wasActive:
        final e = controller.error;
        AppToast.progress(context,
            id: toastId,
            message: l.updatesStatusFailed(
                e == null ? l.updatesErrDownload : updateErrorText(l, e)),
            finished: true,
            kind: ToastKind.error,
            onTap: open,
            tapTooltip: l.updatesTitle);
      default:
        // Отмена, «только ссылка», новая проверка — карточка без итога.
        if (wasActive) AppToast.dismissProgress(toastId);
    }
  }

  // ── Окно «Доступна новая версия» ──────────────────────────────────────────

  bool _dialogWanted() {
    final c = controller;
    final offer = c.offer;
    return c.phase == UpdatePhase.available &&
        offer != null &&
        !c.lastCheckManual &&
        !c.postponed &&
        !c.offerIsSkipped &&
        modeOf() == AppUpdateMode.ask &&
        // Предложение «Прежних версий» (откат) — не повод для окна.
        AppUpdate.isNewer(offer.version, c.currentVersion);
  }

  void _maybeDialog() {
    if (_dialogShown || _dialogPending || !_dialogWanted()) return;
    _dialogPending = true;
    unawaited(_showDialog());
  }

  Future<void> _showDialog() async {
    try {
      // Причину «ставить самим нельзя» узнаём ДО окна: кнопка «Обновить»,
      // которая после закачки выяснит, что ставить нечем, — обманка.
      InstallCapability cap;
      try {
        cap = await controller.installCapability();
      } catch (e) {
        AppLog.w('Обновление: возможность установки не узнана: $e');
        cap = InstallCapability.unsupported;
      }
      // За время ожидания всё могло измениться (ручная проверка, закачка).
      if (!_attached || !_dialogWanted() || controller.busy) return;
      final context = contextOf();
      if (context == null || !context.mounted) return;
      final offer = controller.offer!;
      final LinkOnlyReason? reason = cap != InstallCapability.ready
          ? AppUpdateController.linkOnlyReasonFor(cap)
          : (!offer.canSelfUpdate ? LinkOnlyReason.noSelfUpdate : null);
      _dialogShown = true;
      await showUpdateDialog(context, controller, linkReason: reason);
    } finally {
      _dialogPending = false;
    }
  }

  // ── «Только ссылка» и разрешение Android ──────────────────────────────────

  void _maybeLinkOnly(BuildContext context) {
    final c = controller;
    final offer = c.offer;
    final reason = c.linkOnlyReason;
    if (c.phase != UpdatePhase.linkOnly || offer == null || reason == null) {
      return;
    }
    // Ручную проверку показывает экран «Обновления», где её и нажали.
    if (c.lastCheckManual) return;
    if (!AppUpdate.isNewer(offer.version, c.currentVersion)) return;
    final v = normalizeVersion(offer.version);
    if (_linkShownFor == v) return;
    _linkShownFor = v;
    final l = AppLocalizations.of(context);
    AppToast.show(
      context,
      '${l.updatesStatusAvailable(v)}. ${linkOnlyReasonText(l, reason)}',
      kind: ToastKind.info,
      duration: const Duration(seconds: 15),
      actionLabel: l.updatesOpenPage,
      onAction: () => unawaited(openUpdatePage(offer)),
    );
  }

  void _maybePermission(BuildContext context) {
    if (controller.phase != UpdatePhase.needsPermission) return;
    if (_permissionShown) return;
    _permissionShown = true;
    final l = AppLocalizations.of(context);
    AppToast.show(
      context,
      l.updatesAndroidUnknownSources,
      kind: ToastKind.warning,
      duration: const Duration(seconds: 20),
      actionLabel: l.updatesAndroidOpenSettings,
      onAction: () => unawaited(controller.openInstallPermission()),
    );
  }

  // ── Перед установкой без нажатия ──────────────────────────────────────────

  Future<void> _beforeUnattendedInstall(UpdateOffer offer) async {
    if (!Platform.isWindows) return;
    var hidden = false;
    try {
      hidden = !await windowManager.isVisible() ||
          await windowManager.isMinimized();
    } catch (_) {
      // Окно не опросить (тест, окна нет) — считаем свёрнутым: лишнее
      // уведомление лучше, чем молча исчезнувшее приложение.
      hidden = true;
    }
    if (!hidden) return;
    final context = contextOf();
    if (context == null || !context.mounted) return;
    final l = AppLocalizations.of(context);
    await DesktopNotice.show(l.updatesAutoNoticeTitle,
        l.updatesAutoNoticeBody(normalizeVersion(offer.version)));
  }
}
