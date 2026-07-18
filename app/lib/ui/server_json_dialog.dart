import 'dart:convert';
import 'widgets/app_toast.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/vpn_server.dart';
import '../core/singbox/singbox_proxy_config_builder.dart';
import '../core/xray/xray_config_builder.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/app_state.dart';

/// Редактируемый JSON-конфиг сервера. «Сохранить» применяет его как override при подключении
/// (сессионно, перезаписывается при обновлении подписки). «Редактор полей» — pop('edit').
class ServerJsonDialog extends StatefulWidget {
  final VpnServer server;
  const ServerJsonDialog({super.key, required this.server});

  @override
  State<ServerJsonDialog> createState() => _ServerJsonDialogState();
}

class _ServerJsonDialogState extends State<ServerJsonDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ov = context.read<AppState>().overrideFor(widget.server);
    // Для профиля «Авто …» показываем ПОЛНЫЙ конфиг панели (десятки серверов +
    // балансировщик), а не пересобранный из одного outbound.
    final panel = widget.server.rawPanelConfig;
    _controller = TextEditingController(text: ov?.rawJson ?? _baseJson(panel));
  }

  /// Конфиг ТОГО ядра, которое реально поднимет сервер.
  ///
  /// Раньше здесь всегда звался Xray-строитель, и на hysteria2 он бросал
  /// `UnsupportedError` прямо в initState — пункт меню «JSON конфиг» ронял
  /// диалог красным экраном.
  String _baseJson(String? panel) {
    if (panel != null && panel.isNotEmpty) {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(panel));
    }
    try {
      if (widget.server.core == ProxyCore.singbox) {
        return const SingboxProxyConfigBuilder().buildJson([widget.server]);
      }
      return const XrayConfigBuilder().buildJson(widget.server);
    } catch (e) {
      return '// Не удалось собрать конфиг для этого сервера:\n// $e';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Состав профиля автовыбора: сколько серверов и есть ли burstObservatory.
  String _profileSummary(AppLocalizations l) {
    try {
      final cfg = jsonDecode(widget.server.rawPanelConfig!) as Map;
      final outs = (cfg['outbounds'] as List?) ?? const [];
      final proxies = outs.where((o) {
        final p = '${(o as Map)['protocol']}';
        return p != 'freedom' && p != 'blackhole' && p != 'dns';
      }).length;
      final burst = cfg.containsKey('burstObservatory') ? ', burstObservatory' : '';
      return l.jsonProfileServers(proxies, burst);
    } catch (_) {
      return l.jsonCompositionUnknown;
    }
  }

  /// Откуда взят конфиг: outbound от панели (XRAY_JSON) или пересобран из share-ссылки.
  /// Пересборка теряет часть streamSettings — из-за неё ломался автовыбор.
  Widget _sourceBadge(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fromPanel = (widget.server.rawOutboundJson ?? '').isNotEmpty;
    final overridden =
        context.read<AppState>().overrideFor(widget.server)?.rawJson != null;

    final (icon, text, color) = overridden
        ? (Icons.edit_note, l.jsonYourSavedOverride, scheme.tertiary)
        : widget.server.isPanelProfile
            ? (
                Icons.hub,
                l.jsonPanelProfileApplied(_profileSummary(l)),
                scheme.primary
              )
            : fromPanel
                ? (Icons.verified, l.jsonPanelConfig, scheme.primary)
                : (
                Icons.warning_amber,
                l.jsonBuiltFromShareLink,
                scheme.error
              );

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 12)),
        ),
      ]),
    );
  }

  void _save() {
    final l = AppLocalizations.of(context);
    final text = _controller.text.trim();
    try {
      jsonDecode(text);
    } catch (_) {
      setState(() => _error = l.jsonInvalidJson);
      return;
    }
    context.read<AppState>().setJsonOverride(widget.server, text);
    AppToast.show(context, l.jsonSaved, kind: ToastKind.success);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.jsonTitle),
      content: SizedBox(
        width: 600,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sourceBadge(context),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('edit'),
          child: Text(l.jsonFieldEditor),
        ),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _controller.text));
            AppToast.copied(context);
          },
          child: Text(l.jsonCopy),
        ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.jsonClose)),
        FilledButton(onPressed: _save, child: Text(l.jsonSave)),
      ],
    );
  }
}
