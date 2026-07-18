import 'package:flutter/material.dart';
import 'widgets/app_toast.dart';
import 'package:flutter/services.dart';

import '../core/models/vpn_server.dart';
import '../core/singbox/singbox_proxy_config_builder.dart';
import '../core/xray/xray_config_builder.dart';
import '../l10n/gen/app_localizations.dart';

/// Редактор сервера в стиле NekoBox: правка ключевых полей VLESS/Reality и др.
/// Возвращает изменённый [VpnServer] (с пересобранной share-ссылкой) или null.
class ServerEditorDialog extends StatefulWidget {
  final VpnServer server;
  const ServerEditorDialog({super.key, required this.server});

  @override
  State<ServerEditorDialog> createState() => _ServerEditorDialogState();
}

class _ServerEditorDialogState extends State<ServerEditorDialog> {
  late final _name = TextEditingController(text: widget.server.remark);
  late final _address = TextEditingController(text: widget.server.address);
  late final _port = TextEditingController(text: '${widget.server.port}');
  late final _id = TextEditingController(text: widget.server.id);
  late final _sni = TextEditingController(text: widget.server.sni ?? '');
  late final _alpn = TextEditingController(text: widget.server.alpn ?? '');
  late final _pbk = TextEditingController(text: widget.server.publicKey ?? '');
  late final _sid = TextEditingController(text: widget.server.shortId ?? '');
  late final _host = TextEditingController(text: widget.server.host ?? '');
  late final _path = TextEditingController(text: widget.server.path ?? '');

  // Поля hysteria2: у него свой набор — обфускация и порт-хоппинг.
  late final _obfs = TextEditingController(text: widget.server.obfs ?? '');
  late final _obfsPassword =
      TextEditingController(text: widget.server.obfsPassword ?? '');
  late final _mport = TextEditingController(text: widget.server.hopPorts ?? '');
  late bool _insecure = widget.server.allowInsecure;

  /// hysteria2 работает поверх QUIC: транспорт и «безопасность» у него не
  /// выбираются, а Xray-приёмы (flow, reality, ws/grpc) неприменимы. Показывать
  /// их нельзя не только для красоты: `quic` нет в списке транспортов, и
  /// выпадающий список с чужим значением просто падает.
  bool get _isHysteria2 => widget.server.protocol == 'hysteria2';

  late String _network = widget.server.network;
  late String _security = widget.server.security;
  late String _flow = widget.server.flow ?? '';
  late String _fp = widget.server.fingerprint ?? 'chrome';

  static const _networks = ['tcp', 'ws', 'grpc', 'http'];
  static const _securities = ['none', 'tls', 'reality'];
  static const _flows = ['', 'xtls-rprx-vision'];
  static const _fps = [
    'chrome', 'firefox', 'safari', 'edge', 'ios', 'android', 'randomized'
  ];

  @override
  void dispose() {
    for (final c in [
      _name, _address, _port, _id, _sni, _alpn, _pbk, _sid, _host, _path,
      _obfs, _obfsPassword, _mport,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Пустое поле — это «нет значения», а не пустая строка: иначе в конфиг
  /// уходит `alpn: [""]`, и Go отвергает рукопожатие («invalid NextProtos»).
  static String? _nz(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  VpnServer _buildEdited() {
    // Раз пользователь правит поля руками, готовый outbound/профиль от панели
    // больше не авторитетен: иначе правка молча не применялась бы (фабрика
    // предпочитает конфиг панели), и это выглядело как «работает через раз».
    if (_isHysteria2) {
      final edited = widget.server.copyWith(
        remark: _name.text.trim(),
        address: _address.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? widget.server.port,
        id: _id.text.trim(),
        sni: _nz(_sni),
        alpn: _nz(_alpn),
        obfs: _nz(_obfs),
        obfsPassword: _nz(_obfsPassword),
        hopPorts: _nz(_mport),
        allowInsecure: _insecure,
        clearPanelConfigs: true,
      );
      return edited.copyWith(rawLink: edited.buildShareLink());
    }

    final edited = widget.server.copyWith(
      remark: _name.text.trim(),
      address: _address.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? widget.server.port,
      id: _id.text.trim(),
      network: _network,
      security: _security,
      flow: _flow,
      sni: _nz(_sni),
      alpn: _nz(_alpn),
      fingerprint: _fp,
      publicKey: _nz(_pbk),
      shortId: _nz(_sid),
      host: _nz(_host),
      path: _nz(_path),
      clearPanelConfigs: true,
    );
    return edited.copyWith(rawLink: edited.buildShareLink());
  }

  void _save() => Navigator.of(context).pop(_buildEdited());

  void _showJson() {
    final l = AppLocalizations.of(context);
    final edited = _buildEdited();
    // Показываем конфиг ТОГО ядра, которое реально поднимет этот сервер.
    final json = _isHysteria2
        ? const SingboxProxyConfigBuilder().buildJson([edited])
        : const XrayConfigBuilder().buildJson(edited);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.editorJsonTitle),
        content: SizedBox(
          width: 560,
          height: 460,
          child: SingleChildScrollView(
            child: SelectableText(json,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              AppToast.copied(context);
            },
            child: Text(l.editorCopy),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.editorClose)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.editorTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(l.editorFieldName, _name),
              _field(l.editorFieldAddress, _address),
              _field(l.editorFieldPort, _port),
              _field(l.editorFieldUuidPassword, _id),
              if (_isHysteria2) ...[
                _field('SNI', _sni),
                _field('ALPN', _alpn),
                _field(l.editorFieldObfs, _obfs),
                _field(l.editorFieldObfsPassword, _obfsPassword),
                _field(l.editorFieldPortHopping, _mport),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.editorAllowSelfSigned),
                  subtitle: Text(l.editorAllowSelfSignedSub),
                  value: _insecure,
                  onChanged: (v) => setState(() => _insecure = v),
                ),
              ] else ...[
              _dropdown(l.editorTransport, _network, _networks, (v) => setState(() => _network = v)),
              _dropdown(l.editorSecurity, _security, _securities, (v) => setState(() => _security = v)),
              _dropdown('Flow', _flow, _flows, (v) => setState(() => _flow = v),
                  labels: {'': l.editorNone}),
              _dropdown('Fingerprint', _fp, _fps, (v) => setState(() => _fp = v)),
              _field('SNI', _sni),
              _field('ALPN', _alpn),
              if (_security == 'reality') ...[
                _field('Reality Pbk', _pbk),
                _field('Reality Sid', _sid),
              ],
              if (_network == 'ws' || _network == 'http' || _network == 'grpc') ...[
                _field('Host', _host),
                _field('Path / serviceName', _path),
              ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _showJson,
            child: const Text('JSON')), // #5 — из редактора открыть JSON
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.editorCancel)),
        FilledButton(onPressed: _save, child: Text(l.editorSave)),
      ],
    );
  }

  Widget _field(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        ),
      );

  Widget _dropdown(String label, String value, List<String> options,
      ValueChanged<String> onChanged,
      {Map<String, String> labels = const {}}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: options.contains(value) ? value : options.first,
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(labels[o] ?? o)))
                .toList(),
            onChanged: (v) => onChanged(v ?? options.first),
          ),
        ),
      ),
    );
  }
}
