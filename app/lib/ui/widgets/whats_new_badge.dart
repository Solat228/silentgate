import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../../core/app_info.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/settings_controller.dart';
import 'app_toast.dart';
import 'sel_text.dart';

/// Кликабельная плашка версии в шапке главного экрана (Android и Windows)
/// с мигающим колокольчиком после установки новой версии/сборки и авто-показом
/// окна «Что нового».
class HeaderVersionBadge extends StatefulWidget {
  const HeaderVersionBadge({super.key});

  /// В обычных виджет-тестах `HomeScreen` авто-всплытие окна отключено, чтобы
  /// не перекрывать тестируемые элементы главного экрана; в профильном тесте
  /// «Что нового» включается явно.
  static bool enableAutoPopupInTests = false;

  /// Уже проверяли авто-показ в текущем процессе приложения.
  static bool _autoPopupCheckedThisRun = false;

  /// Открыто ли сейчас окно «Что нового» (чтобы колокольчик в шапке не гас
  /// мгновенно в момент открытия диалога, а оставался виден, пока человек читает).
  static final ValueNotifier<bool> dialogOpen = ValueNotifier<bool>(false);

  @visibleForTesting
  static void resetAutoPopupStateForTest() {
    _autoPopupCheckedThisRun = false;
    dialogOpen.value = false;
  }

  /// Есть ли непрочитанное «Что нового» для текущей установленной версии/сборки.
  static bool hasUnseen(String? lastSeenVersion) =>
      (lastSeenVersion ?? '').trim() != AppInfo.fullVersion;

  @override
  State<HeaderVersionBadge> createState() => _HeaderVersionBadgeState();
}

class _HeaderVersionBadgeState extends State<HeaderVersionBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;
  Animation<double>? _pulseAnim;

  bool get _isFlutterTest =>
      Platform.environment.containsKey('FLUTTER_TEST') &&
      !HeaderVersionBadge.enableAutoPopupInTests;

  @override
  void initState() {
    super.initState();
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _pulseController = ctrl;
    _pulseAnim = CurvedAnimation(parent: ctrl, curve: Curves.easeInOut);

    if (!_isFlutterTest) {
      unawaited(ctrl.repeat(reverse: true));
    } else {
      ctrl.value = 1.0;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoShow());
  }

  Future<void> _maybeAutoShow() async {
    if (!mounted) return;
    if (HeaderVersionBadge._autoPopupCheckedThisRun) return;
    if (Platform.environment.containsKey('FLUTTER_TEST') &&
        !HeaderVersionBadge.enableAutoPopupInTests) {
      return;
    }

    SettingsController? settingsCtrl;
    try {
      settingsCtrl = context.read<SettingsController>();
    } catch (_) {
      return;
    }

    final s = settingsCtrl.settings;
    if (!s.showWhatsNewOnUpdate) return;
    if (!HeaderVersionBadge.hasUnseen(s.lastSeenWhatsNewVersion)) return;

    HeaderVersionBadge._autoPopupCheckedThisRun = true;

    if (!HeaderVersionBadge.enableAutoPopupInTests) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    await showWhatsNewDialog(context);
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isRu = Localizations.localeOf(context)
        .languageCode
        .toLowerCase()
        .startsWith('ru');

    String? lastSeen;
    try {
      lastSeen = context.select<SettingsController, String?>(
        (c) => c.settings.lastSeenWhatsNewVersion,
      );
    } catch (_) {
      lastSeen = AppInfo.fullVersion;
    }

    return ValueListenableBuilder<bool>(
      valueListenable: HeaderVersionBadge.dialogOpen,
      builder: (context, isDialogOpen, _) {
        final unseen = HeaderVersionBadge.hasUnseen(lastSeen) || isDialogOpen;
        final tooltipText = unseen
            ? (isRu
                ? 'Что нового в v${AppInfo.fullVersion} (нажмите, чтобы прочитать)'
                : "What's new in v${AppInfo.fullVersion} (tap to read)")
            : (isRu
                ? 'О версии и список изменений (v${AppInfo.fullVersion})'
                : 'Version info & changelog (v${AppInfo.fullVersion})');

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                AppInfo.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: tooltipText,
              child: InkWell(
                key: const Key('headerVersionBadgeButton'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => unawaited(showWhatsNewDialog(context)),
                child: AnimatedBuilder(
                  animation:
                      _pulseAnim ?? const AlwaysStoppedAnimation<double>(0),
                  builder: (context, _) {
                    final t = unseen ? (_pulseAnim?.value ?? 1.0) : 0.0;
                    final bgColor = unseen
                        ? Color.lerp(
                            cs.primaryContainer.withValues(alpha: 0.55),
                            cs.primaryContainer,
                            t,
                          )
                        : cs.surfaceContainerHighest.withValues(alpha: 0.55);
                    final borderColor = unseen
                        ? Color.lerp(
                            cs.primary.withValues(alpha: 0.35),
                            cs.primary,
                            t,
                          )!
                        : cs.outlineVariant.withValues(alpha: 0.45);
                    final textColor = unseen
                        ? Color.lerp(
                            cs.onPrimaryContainer.withValues(alpha: 0.78),
                            cs.onPrimaryContainer,
                            t,
                          )
                        : cs.onSurfaceVariant;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: borderColor, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unseen) ...[
                            Transform.rotate(
                              angle: (t - 0.5) * 0.28,
                              child: Icon(
                                Icons.notifications_active_rounded,
                                key: const Key('headerVersionBellIcon'),
                                size: 14,
                                color: Color.lerp(
                                  cs.primary.withValues(alpha: 0.65),
                                  cs.primary,
                                  t,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            'v${AppInfo.fullVersion}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight:
                                  unseen ? FontWeight.w600 : FontWeight.w400,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Открывает окно «Что нового» / истории изменений и отмечает текущую версию
/// прочитанной (гасит мигающий колокольчик в шапке после закрытия окна).
Future<void> showWhatsNewDialog(
  BuildContext context, {
  String? renderedVersion,
}) async {
  SettingsController? settingsCtrl;
  try {
    settingsCtrl = context.read<SettingsController>();
  } catch (_) {}

  final wasUnseen = settingsCtrl != null &&
      HeaderVersionBadge.hasUnseen(
          settingsCtrl.settings.lastSeenWhatsNewVersion);
  if (wasUnseen) {
    HeaderVersionBadge.dialogOpen.value = true;
    unawaited(settingsCtrl.update(
      (s) => s.copyWith(lastSeenWhatsNewVersion: AppInfo.fullVersion),
    ));
  }

  final l = AppLocalizations.of(context);
  final isRu = l.localeName.toLowerCase().startsWith('ru');
  final patches = AppInfo.patchEntriesForLocale(l.localeName);
  final channelLabel =
      AppInfo.isBeta ? l.updatesChannelBeta : l.updatesChannelStable;
  final displayVer = renderedVersion ?? AppInfo.formatAboutVersion();

  final lines = <String>[
    '${l.aboutVersion}: $displayVer',
    '${isRu ? "Номер сборки" : "Build"}: +${AppInfo.buildNumber}',
    '${isRu ? "Канал" : "Channel"}: $channelLabel',
    if (AppInfo.gitCommit.isNotEmpty)
      'Git: ${AppInfo.gitCommit}'
          '${AppInfo.gitBranch.isNotEmpty ? " (${AppInfo.gitBranch})" : ""}',
    '',
    isRu
        ? 'Что нового и история изменений:'
        : "What's new & version changelog:",
    for (final p in patches) '• $p',
  ];
  final reportText = lines.join('\n');
  final latestPatch = patches.isNotEmpty ? patches.first : null;
  final olderPatches =
      patches.length > 1 ? patches.sublist(1) : const <String>[];

  try {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final theme = Theme.of(ctx);
            final cs = theme.colorScheme;
            SettingsController? dlgSettingsCtrl;
            try {
              dlgSettingsCtrl = ctx.watch<SettingsController>();
            } catch (_) {
              dlgSettingsCtrl = settingsCtrl;
            }
            final autoShow =
                dlgSettingsCtrl?.settings.showWhatsNewOnUpdate ?? true;

            return AlertDialog(
              key: const Key('aboutVersionPatchesDialog'),
              title: Row(
                children: [
                  Icon(Icons.new_releases_outlined, color: cs.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isRu
                          ? 'Что нового в $displayVer'
                          : "What's new in $displayVer",
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 540, maxHeight: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (latestPatch != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer
                                      .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isRu
                                          ? 'Текущее обновление ($displayVer):'
                                          : 'Current update ($displayVer):',
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    SelText(
                                      latestPatch,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            SelText(
                              [
                                '${l.aboutVersion}: $displayVer',
                                '${isRu ? "Номер сборки" : "Build"}: +${AppInfo.buildNumber}',
                                '${isRu ? "Канал" : "Channel"}: $channelLabel',
                                if (AppInfo.gitCommit.isNotEmpty)
                                  'Git: ${AppInfo.gitCommit}'
                                      '${AppInfo.gitBranch.isNotEmpty ? " (${AppInfo.gitBranch})" : ""}',
                                if (olderPatches.isNotEmpty) ...[
                                  '',
                                  isRu
                                      ? 'Предыдущие обновления и патчи:'
                                      : 'Previous updates & patches:',
                                  for (final p in olderPatches) '• $p',
                                ],
                              ].join('\n'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (dlgSettingsCtrl != null) ...[
                      const Divider(height: 20),
                      CheckboxListTile(
                        key: const Key('whatsNewAutoShowCheckbox'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: !autoShow,
                        onChanged: (dontShow) {
                          if (dontShow == null) return;
                          unawaited(dlgSettingsCtrl!.update(
                            (s) => s.copyWith(showWhatsNewOnUpdate: !dontShow),
                          ));
                          setDialogState(() {});
                        },
                        title: Text(
                          isRu
                              ? 'Больше не показывать автоматически после обновления'
                              : "Don't show automatically after updates",
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  key: const Key('aboutVersionCopyButton'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: reportText));
                    if (ctx.mounted) {
                      AppToast.show(ctx, l.commonCopied);
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(l.srvTileCopy),
                ),
                FilledButton(
                  key: const Key('whatsNewCloseButton'),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l.commonClose),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    if (wasUnseen) {
      HeaderVersionBadge.dialogOpen.value = false;
    }
  }
}
