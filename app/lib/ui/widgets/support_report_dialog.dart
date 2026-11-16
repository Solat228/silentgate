import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_server.dart';
import '../../core/platform/app_launcher.dart';
import '../../core/platform/device_id.dart';
import '../../core/platform/platform_services.dart';
import '../../core/probe/proxy_probe.dart';
import '../../core/settings/app_settings.dart';
import '../../core/support/dev_report_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import 'app_toast.dart';
import 'extended_clipboard.dart';
import 'flag_text.dart';
import 'subscription_avatar.dart';

const kDeveloperSupportTelegram = 'https://t.me/silentgate_vpn_help';

/// Результат генерации отчёта из встроенного чата поддержки.
class ChatGeneratedReport {
  final String filePath;
  final String reportCode;
  final String summaryLine;

  const ChatGeneratedReport({
    required this.filePath,
    required this.reportCode,
    required this.summaryLine,
  });
}

/// Открыть штатный диалог генерации и отправки отчёта поддержки (из Настроек).
Future<void> showSupportReportDialog(
  BuildContext context, {
  DevReportHttpSender? httpSenderOverride,
  SupportReporter? reporterOverride,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => SupportReportDialog(
      forInAppChat: false,
      httpSenderOverride: httpSenderOverride,
      reporterOverride: reporterOverride,
    ),
  );
}

/// Открыть компактный диалог прикрепления диагностического отчёта прямо во
/// встроенном чате поддержки (`SupportChatOverlay`).
Future<ChatGeneratedReport?> showSupportReportForChatDialog(
  BuildContext context, {
  DevReportHttpSender? httpSenderOverride,
  SupportReporter? reporterOverride,
}) async {
  return showDialog<ChatGeneratedReport>(
    context: context,
    builder: (_) => SupportReportDialog(
      forInAppChat: true,
      httpSenderOverride: httpSenderOverride,
      reporterOverride: reporterOverride,
    ),
  );
}

/// Единый диалог подготовки и отправки отчёта поддержки:
/// - необязательное текстовое описание на всех платформах (Android и Windows);
/// - быстрые чипы категорий в 1 нажатие без набора текста;
/// - галочка отправки обезличенной копии на сервер разработчика + предпросмотр «Что уйдёт?»;
/// - кнопка «Только разработчику» для тихой отправки в 1 клик без проводника/Telegram.
class SupportReportDialog extends StatefulWidget {
  final bool forInAppChat;
  final DevReportHttpSender? httpSenderOverride;
  final SupportReporter? reporterOverride;

  const SupportReportDialog({
    super.key,
    this.forInAppChat = false,
    this.httpSenderOverride,
    this.reporterOverride,
  });

  @override
  State<SupportReportDialog> createState() => _SupportReportDialogState();
}

class _SupportReportDialogState extends State<SupportReportDialog> {
  bool _busy = false;
  String? _path;
  String? _error;
  bool _devOnlyCompleted = false;
  DevReportUploadResult? _devUploadResult;

  late final String _reportCode = DevReportService.generateReportCode();
  final TextEditingController _description = TextEditingController();
  final Set<QuickReportTag> _selectedTags = <QuickReportTag>{};
  bool? _sendDevCopyLocal;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  String _tagLabel(AppLocalizations l, QuickReportTag tag) {
    switch (tag) {
      case QuickReportTag.cantConnect:
        return l.supportChipCantConnect;
      case QuickReportTag.siteOrYoutube:
        return l.supportChipSiteOrYoutube;
      case QuickReportTag.slowSpeed:
        return l.supportChipSlowSpeed;
      case QuickReportTag.connectionDrops:
        return l.supportChipConnectionDropsLabel;
    }
  }

  bool _effectiveSendDevCopy(AppSettings? settings) {
    if (_sendDevCopyLocal != null) return _sendDevCopyLocal!;
    return settings?.sendDevReportCopy ??
        DevReportService.defaultSendCopyEnabled;
  }

  void _toggleSendDevCopy(bool value) {
    setState(() => _sendDevCopyLocal = value);
    final ctrl = context.read<SettingsController?>();
    if (ctrl != null) {
      unawaited(ctrl.update((s) => s.copyWith(sendDevReportCopy: value)));
    }
  }

  String _buildHeader(AppLocalizations l) {
    final text = _description.text.trim();
    final tagLabels = _selectedTags.map((t) => _tagLabel(l, t)).toList();
    final hasAnyUserInput = text.isNotEmpty || tagLabels.isNotEmpty;

    final b = StringBuffer()
      ..writeln('==================================================')
      ..writeln('  ${l.reportTitle} ($_reportCode)')
      ..writeln('==================================================')
      ..writeln()
      ..writeln('[${l.supportDescriptionSection}]')
      ..writeln();

    if (tagLabels.isNotEmpty) {
      b.writeln('${l.supportCategoriesHeader}: ${tagLabels.join(', ')}');
    }
    if (text.isNotEmpty) {
      b.writeln(text);
    }
    if (!hasAnyUserInput) {
      b.writeln(l.supportNoTextProvided);
    }

    b
      ..writeln()
      ..writeln(l.supportNoScreenshots)
      ..writeln()
      ..writeln('--------------------------------------------------')
      ..writeln(l.reportTechNoticeLine1)
      ..writeln(l.reportTechNoticeLine2)
      ..writeln('--------------------------------------------------');
    return b.toString();
  }

  String _buildChatSummaryLine(AppLocalizations l) {
    final text = _description.text.trim();
    final tagLabels = _selectedTags.map((t) => _tagLabel(l, t)).toList();
    if (text.isNotEmpty && tagLabels.isNotEmpty) {
      return '[${tagLabels.join(', ')}] $text (отчёт $_reportCode)';
    }
    if (text.isNotEmpty) {
      return '$text (отчёт $_reportCode)';
    }
    if (tagLabels.isNotEmpty) {
      return '${l.supportAttachDiagButton} $_reportCode: ${tagLabels.join(', ')}';
    }
    return '${l.supportAttachDiagButton} $_reportCode';
  }

  SupportContext _buildSupportContext(AppLocalizations l, AppState? state) {
    final server = state?.selectedServer;
    return SupportContext(
      statusLine: state?.status.label ?? '-',
      subscriptionUrl: state?.subscriptionUrl,
      serverCount: state?.servers.length ?? 0,
      activeServer: server == null ? '(нет)' : server.displayName,
      activeCore: server == null
          ? '-'
          : (server.core == ProxyCore.singbox ? 'sing-box' : 'Xray'),
      header: _buildHeader(l),
    );
  }

  Future<(String path, String rawText, String anonymizedText, String? hwid)>
      _generateReportArtifacts() async {
    final l = AppLocalizations.of(context);
    final state = context.read<AppState?>();
    final settings =
        context.read<SettingsController?>()?.settings ?? const AppSettings();
    final ctx = _buildSupportContext(l, state);
    final reporter = widget.reporterOverride ?? platform.support;
    final path = await reporter.generate(settings: settings, ctx: ctx);
    final rawText = File(path).readAsStringSync();
    String? hwid;
    try {
      hwid = await Hwid.get();
    } catch (_) {}
    final anonymized = DevReportService.anonymizeReportText(
      rawText,
      rawHwid: hwid,
      rawSubscriptionUrl: state?.subscriptionUrl,
      reportCode: _reportCode,
    );
    return (path, rawText, anonymized, hwid);
  }

  Future<DevReportUploadResult> _uploadToDeveloper({
    required String anonymizedText,
    required String? rawHwid,
    required AppState? state,
  }) async {
    String osVer = Platform.operatingSystemVersion;
    String model = '';
    if (Platform.isAndroid) {
      try {
        osVer = 'Android ${await deviceIdProvider().osVersion()}';
        model = await deviceIdProvider().deviceModel();
      } catch (_) {}
    }
    final proxyPort = (state != null &&
            state.status.isConnected &&
            state.httpProxyPort > 0)
        ? state.httpProxyPort
        : null;
    final server = state?.selectedServer;
    return DevReportService.upload(
      anonymizedReport: anonymizedText,
      reportCode: _reportCode,
      rawHwid: rawHwid,
      rawSubscriptionUrl: state?.subscriptionUrl,
      tags: _selectedTags.toList(),
      hasUserDescription: _description.text.trim().isNotEmpty,
      activeServer: server?.displayName ?? '',
      activeCore: server == null
          ? '-'
          : (server.core == ProxyCore.singbox ? 'sing-box' : 'Xray'),
      osVersion: osVer,
      deviceModel: model,
      proxyPort: proxyPort,
      proxyUser: proxyPort != null ? ProxyProbe.user : '',
      proxyPassword: proxyPort != null ? ProxyProbe.password : '',
      httpSender: widget.httpSenderOverride,
    );
  }

  Future<void> _previewDevCopy() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (path, _, anonymized, _) = await _generateReportArtifacts();
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _busy = false);
      final l = AppLocalizations.of(context);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.supportPreviewDialogTitle),
          content: SizedBox(
            width: 560,
            height: 420,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  anonymized,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 17),
              label: Text(l.commonCopy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: anonymized));
                AppToast.copied(ctx);
              },
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.commonClose),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _generateAndOptionallyUpload({required bool devOnly}) async {
    final l = AppLocalizations.of(context);
    final state = context.read<AppState?>();
    final settings = context.read<SettingsController?>()?.settings;
    final sendCopy = devOnly || _effectiveSendDevCopy(settings);

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (path, _, anonymized, hwid) = await _generateReportArtifacts();

      DevReportUploadResult? uploadRes;
      if (sendCopy) {
        uploadRes = await _uploadToDeveloper(
          anonymizedText: anonymized,
          rawHwid: hwid,
          state: state,
        );
      }

      if (devOnly) {
        // В режиме «Только разработчику» локальный проводник/шторку НЕ дёргаем,
        // а временный файл убираем, если копия уже принята сервером.
        if (uploadRes != null && uploadRes.ok) {
          try {
            final f = File(path);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
          if (!mounted) return;
          setState(() {
            _busy = false;
            _devOnlyCompleted = true;
            _devUploadResult = uploadRes;
          });
          return;
        }
        if (!mounted) return;
        setState(() {
          _busy = false;
          _path = path;
          _devUploadResult = uploadRes;
        });
        return;
      }

      if (widget.forInAppChat) {
        if (!mounted) return;
        if (uploadRes != null && uploadRes.ok) {
          AppToast.show(context, l.supportDevCopySent(uploadRes.reportCode));
        }
        Navigator.of(context).pop(
          ChatGeneratedReport(
            filePath: path,
            reportCode: _reportCode,
            summaryLine: _buildChatSummaryLine(l),
          ),
        );
        return;
      }

      await (widget.reporterOverride ?? platform.support).reveal(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _devUploadResult = uploadRes;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState?>();
    final settings = context.watch<SettingsController?>()?.settings;
    final serviceName = (state?.info.title ?? '').trim();
    final vpnSupport = (state?.info.supportUrl ?? '').trim();
    final done = _path != null || _devOnlyCompleted;
    final sendDevCopy = _effectiveSendDevCopy(settings);

    return AlertDialog(
      scrollable: true,
      title: Text(done ? l.supportDialogTitleDone : l.supportDialogTitle),
      content: SizedBox(
        width: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!done) ...[
              if (!widget.forInAppChat) ...[
                Text(
                  l.supportWhatWillHappen,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(l.supportBullet1),
                const SizedBox(height: 4),
                Text(
                  Platform.isAndroid
                      ? l.supportBullet2Android
                      : l.supportBullet2,
                ),
                const SizedBox(height: 12),
              ],
              Text(
                l.supportChipsHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in QuickReportTag.values)
                    FilterChip(
                      key: Key('supportChip_${tag.wireKey}'),
                      visualDensity: VisualDensity.compact,
                      selected: _selectedTags.contains(tag),
                      label: Text(
                        _tagLabel(l, tag),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      onSelected: _busy
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedTags.add(tag);
                                } else {
                                  _selectedTags.remove(tag);
                                }
                              });
                            },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('supportDescriptionField'),
                controller: _description,
                contentInsertionConfiguration: buildExtendedContentInsertion(
                  _description,
                ),
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l.supportDescribeOptionalLabel,
                  hintText: l.supportDescribeHint,
                ),
              ),
              const SizedBox(height: 10),
              Material(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.5),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      key: const Key('supportSendDevCopyCheckbox'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding:
                          const EdgeInsets.fromLTRB(8, 2, 12, 0),
                      value: sendDevCopy,
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v != null) _toggleSendDevCopy(v);
                            },
                      title: Text(
                        l.supportSendDevCopyTitle,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        l.supportSendDevCopySub,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          key: const Key('supportPreviewDevCopyButton'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _busy ? null : _previewDevCopy,
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: Text(
                            l.supportPreviewDevCopy,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.supportNoScreenshots,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  l.supportError(_error!),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ] else if (_devOnlyCompleted && _devUploadResult != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      l.supportDevOnlyDoneText(_devUploadResult!.reportCode),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                Platform.isAndroid
                    ? l.supportDoneTextAndroid
                    : l.supportDoneText,
              ),
              const SizedBox(height: 8),
              SelectableText(
                _path!.split(RegExp(r'[\\/]')).last,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              if (_devUploadResult != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      _devUploadResult!.ok
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 17,
                      color: _devUploadResult!.ok
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _devUploadResult!.ok
                            ? l.supportDevCopySent(_devUploadResult!.reportCode)
                            : l.supportDevCopyFailed(
                                _devUploadResult!.reportCode,
                              ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Text(
                l.supportWhoTo,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              SupportRecipients(
                serviceName: serviceName,
                supportUrl: vpnSupport,
                logoPath: state?.logoPath,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (done && _devOnlyCompleted && _devUploadResult != null)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: _devUploadResult!.reportCode),
              );
              AppToast.copied(context);
            },
            label: Text(l.commonCopy),
          ),
        if (done && _path != null)
          TextButton.icon(
            icon: Icon(
              Platform.isAndroid ? Icons.copy_all : Icons.folder_open,
              size: 18,
            ),
            onPressed: () async {
              await platform.support.reveal(_path!);
              if (Platform.isAndroid && context.mounted) {
                AppToast.copied(context, message: l.supportReportCopied);
              }
            },
            label: Text(
              Platform.isAndroid ? l.supportCopyReport : l.supportShowOnPc,
            ),
          ),
        if (done && _path != null)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _path!));
              AppToast.copied(context, message: l.commonPathCopied);
            },
            label: Text(l.supportCopyPath),
          ),
        if (!done)
          FilledButton.tonalIcon(
            key: const Key('supportSendDevOnlyButton'),
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            onPressed: _busy
                ? null
                : () => _generateAndOptionallyUpload(devOnly: true),
            label: Text(l.supportSendDevOnlyButton),
          ),
        if (!done)
          FilledButton.icon(
            key: Key(
              widget.forInAppChat
                  ? 'supportAttachToChatConfirmButton'
                  : 'supportGenerateButton',
            ),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    widget.forInAppChat
                        ? Icons.attach_file
                        : Icons.description_outlined,
                    size: 18,
                  ),
            onPressed: _busy
                ? null
                : () => _generateAndOptionallyUpload(devOnly: false),
            label: Text(
              _busy
                  ? l.supportGenerating
                  : (widget.forInAppChat
                      ? l.supportSendToChatAndDev
                      : l.supportGenerateButton),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(done ? l.commonDone : l.commonCancel),
        ),
      ],
    );
  }
}

extension _SupportL10nCompat on AppLocalizations {
  String get supportChipConnectionDropsLabel => supportChipDrops;
}

/// «Кому отправить» — два РАЗНЫХ адресата.
///
/// ⚠️ ЗАЧЕМ ЗДЕСЬ АВАТАРКА ПОДПИСКИ. У обеих кнопок стояли безликие значки, и
/// первая («написать в Silentgate VPN») ничем не отличалась от второй, кроме
/// слова в скобках. Логотип подписки уже скачан и закэширован — это самый
/// быстрый способ узнать «свой» сервис, и человек не отправит лог не туда.
///
/// ⚠️ И РОВНО У ОДНОЙ КНОПКИ. У разработчика клиента аватарки подписки быть не
/// должно: это другой адресат, и чужой логотип рядом с ним прямо врал бы.
/// Стережёт тест.
class SupportRecipients extends StatelessWidget {
  const SupportRecipients({
    super.key,
    required this.serviceName,
    required this.supportUrl,
    required this.logoPath,
  });

  final String serviceName;
  final String supportUrl;
  final String? logoPath;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(spacing: 8, runSpacing: 6, children: [
      if (supportUrl.isNotEmpty)
        FilledButton.tonalIcon(
          icon: SubscriptionAvatar(
            path: logoPath,
            label: serviceName,
            size: 18,
          ),
          label: FlagText(
            serviceName.isNotEmpty
                ? l.supportContactNamed(serviceName)
                : l.supportContact,
          ),
          onPressed: () => UrlOpener.openTelegram(supportUrl),
        ),
      OutlinedButton.icon(
        icon: const Icon(Icons.developer_mode, size: 18),
        label: Text(l.supportContactNamed(l.supportDevServiceName)),
        onPressed: () => UrlOpener.openTelegram(kDeveloperSupportTelegram),
      ),
    ]);
  }
}
