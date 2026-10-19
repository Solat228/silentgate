import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/backup/settings_bundle.dart';
import '../../core/models/vpn_status.dart';
import '../../core/platform/app_log.dart';
import '../../core/platform/app_restart.dart';
import '../../core/platform/text_file_picker_android.dart';
import '../../data/settings_backup.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import 'app_toast.dart';

/// Экспорт и импорт настроек файлом (P11). Строки раздела «Резервная копия»
/// собираются в `settings_screen.dart`, здесь — окна и работа с файлом.

/// Контекст, который переживает системное окно выбора файла.
///
/// ⚠️ КОНТЕКСТ СТРОКИ НАСТРОЕК ДЛЯ ЭТОГО НЕ ГОДИТСЯ. Строка — элемент
/// ленивого списка: пока поверх приложения открыто системное окно, экран
/// настроек пересобирается, и элемент строки создаётся заново. Прежний
/// `context.mounted` становится `false`, и импорт молча обрывался сразу
/// после выбора файла — ни окна, ни ошибки (найдено живьём в эмуляторе).
/// Контекст маршрута живёт, пока открыт сам экран.
@visibleForTesting
BuildContext backupActionHost(BuildContext context) =>
    ModalRoute.of(context)?.subtreeContext ?? context;

/// Экспорт: спросить про подписки, собрать файл и отдать его человеку
/// (Windows — окно «Сохранить как», Android — системное «Поделиться»).
Future<void> exportSettings(BuildContext context) async {
  final host = backupActionHost(context);
  final l = AppLocalizations.of(host);
  final withSubs = await showDialog<bool>(
    context: host,
    builder: (_) => const ExportSettingsDialog(),
  );
  if (withSubs == null || !host.mounted) return;
  try {
    final text = await SettingsBackup.exportText(includeSubscriptions: withSubs);
    if (Platform.isAndroid) {
      final f = await SettingsBackup.writeAndroidExport(text);
      final ok = await const MethodChannel('lol.silentgate/launcher')
          .invokeMethod<bool>('shareFile', {'url': f.path});
      if (ok != true) throw StateError('shareFile отказал');
      return;
    }
    final name = SettingsBackup.exportFileName(DateTime.now());
    final loc = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'SilentGate', extensions: [SettingsBundle.extension]),
      ],
    );
    if (loc == null) return;
    var path = loc.path;
    if (!path.toLowerCase().endsWith('.${SettingsBundle.extension}')) {
      path = '$path.${SettingsBundle.extension}';
    }
    await File(path).writeAsString(text, flush: true);
    if (host.mounted) {
      AppToast.show(host, l.backupExportDone(path), kind: ToastKind.success);
    }
  } catch (e) {
    AppLog.w('Экспорт настроек не удался: $e');
    if (host.mounted) {
      AppToast.show(host, l.backupExportFailed, kind: ToastKind.error);
    }
  }
}

/// Импорт: выбрать файл, показать, что в нём, подготовить и перезапуститься.
Future<void> importSettings(BuildContext context) async {
  final host = backupActionHost(context);
  final l = AppLocalizations.of(host);
  // VPN обязан быть выключен: перезапуск снял бы живой туннель на полуслове,
  // а с kill switch оставил бы машину без сети до следующего подключения.
  final state = host.read<AppState>().status.state;
  if (state != VpnConnectionState.disconnected &&
      state != VpnConnectionState.error) {
    AppToast.show(host, l.backupImportDisconnectFirst);
    return;
  }
  // Отказ окна выбора (поставщик не отдал файл, файл слишком большой)
  // приходит исключением — без перехвата нажатие «Импорт» молча ничего не
  // делало бы.
  PickedTextFile? file;
  try {
    file = await _pickBundleFile();
  } catch (e) {
    AppLog.w('Импорт настроек: окно выбора файла вернуло ошибку ($e)');
    if (host.mounted) {
      AppToast.show(host, l.backupImportBadFile, kind: ToastKind.error);
    }
    return;
  }
  if (file == null) {
    AppLog.i('Импорт настроек: файл не выбран');
    return;
  }
  AppLog.i('Импорт настроек: выбран файл ${file.name}');
  if (!host.mounted) {
    AppLog.w('Импорт настроек: экран настроек закрыт — импорт отменён');
    return;
  }
  final bundle = SettingsBundle.parse(file.text);
  if (bundle == null || (!bundle.hasSettings && !bundle.hasSubscriptions)) {
    AppLog.w('Импорт настроек: ${file.name} — не файл экспорта SilentGate');
    AppToast.show(host, l.backupImportBadFile, kind: ToastKind.error);
    return;
  }
  final replaceSubs = await showDialog<bool>(
    context: host,
    builder: (_) => ImportSettingsDialog(bundle: bundle),
  );
  if (replaceSubs == null || !host.mounted) return;
  final staged = await SettingsBackup.stageImport(bundle,
      includeSubscriptions: replaceSubs);
  if (!host.mounted) return;
  if (!staged) {
    AppToast.show(host, l.backupImportBadFile, kind: ToastKind.error);
    return;
  }
  final restarted = await AppRestart.restart();
  if (!restarted && host.mounted) {
    AppToast.show(host, l.backupImportRestartManually,
        duration: const Duration(seconds: 15));
  }
}

/// Выбрать файл экспорта и прочитать его.
///
/// ⚠️ На Android — своё окно выбора, а не `file_selector`: ответ плагина
/// терялся, если система пересоздавала Activity, пока открыто окно (см.
/// `platform/TextFilePicker.kt`). И без фильтра типов: расширения
/// `.sgsettings` система не знает, с фильтром файл просто не показался бы.
Future<PickedTextFile?> _pickBundleFile() async {
  if (Platform.isAndroid) return TextFilePickerAndroid().pickText();
  final x = await openFile(acceptedTypeGroups: const [
    XTypeGroup(label: 'SilentGate', extensions: [SettingsBundle.extension]),
  ]);
  if (x == null) return null;
  return PickedTextFile(name: x.name, text: await x.readAsString());
}

class ExportSettingsDialog extends StatefulWidget {
  const ExportSettingsDialog({super.key});

  @override
  State<ExportSettingsDialog> createState() => ExportSettingsDialogState();
}

class ExportSettingsDialogState extends State<ExportSettingsDialog> {
  // По умолчанию с подписками: экспорт почти всегда нужен, чтобы перенести
  // приложение целиком на другое устройство. Предупреждение видно сразу.
  bool _withSubs = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.backupExportTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                key: const ValueKey('backup-export-subs'),
                contentPadding: EdgeInsets.zero,
                value: _withSubs,
                onChanged: (v) => setState(() => _withSubs = v ?? false),
                title: Text(l.backupExportWithSubs),
              ),
              const SizedBox(height: 4),
              if (_withSubs)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 20, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.backupExportSubsWarning)),
                  ],
                )
              else
                Text(l.backupExportNoSubsNote),
              const SizedBox(height: 12),
              Text(l.backupExportDeviceNote, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_withSubs),
          child: Text(l.backupExportAction),
        ),
      ],
    );
  }
}

class ImportSettingsDialog extends StatefulWidget {
  const ImportSettingsDialog({super.key, required this.bundle});

  final BundleContents bundle;

  @override
  State<ImportSettingsDialog> createState() => ImportSettingsDialogState();
}

class ImportSettingsDialogState extends State<ImportSettingsDialog> {
  late bool _replaceSubs = widget.bundle.hasSubscriptions;

  static String _platformName(String p) => switch (p) {
        'android' => 'Android',
        'windows' => 'Windows',
        _ => p,
      };

  static String _date(DateTime? d) {
    if (d == null) return '—';
    final t = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final b = widget.bundle;
    final theme = Theme.of(context);
    final otherPlatform = b.platform != SettingsBackup.platform;
    return AlertDialog(
      title: Text(l.backupImportConfirmTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.backupImportFrom(
                    _platformName(b.platform), b.appVersion, _date(b.createdAt)),
                style: theme.textTheme.bodySmall,
              ),
              if (b.hasSubscriptions) ...[
                const SizedBox(height: 8),
                Text(l.backupImportSubsCount(b.subscriptionCount)),
                CheckboxListTile(
                  key: const ValueKey('backup-import-subs'),
                  contentPadding: EdgeInsets.zero,
                  value: _replaceSubs,
                  onChanged: (v) => setState(() => _replaceSubs = v ?? false),
                  title: Text(l.backupImportReplaceSubs),
                ),
              ],
              const SizedBox(height: 8),
              Text(l.backupImportBody),
              if (otherPlatform) ...[
                const SizedBox(height: 8),
                Text(l.backupImportOtherPlatform,
                    style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_replaceSubs),
          child: Text(l.backupImportAction),
        ),
      ],
    );
  }
}
