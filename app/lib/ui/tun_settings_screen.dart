import 'package:flutter/material.dart';
import 'widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/settings/app_settings.dart';
import '../core/settings/split_tunnel.dart';
import '../core/platform/platform_services.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/settings_controller.dart';
import 'widgets/info_tooltip.dart';

/// Экран «TUN и маршрутизация»: права без UAC, стек/MTU, маршрутизация, DNS, диагностика.
class TunSettingsScreen extends StatefulWidget {
  const TunSettingsScreen({super.key});

  @override
  State<TunSettingsScreen> createState() => _TunSettingsScreenState();
}

class _TunSettingsScreenState extends State<TunSettingsScreen> {
  bool? _taskInstalled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshTask();
  }

  Future<void> _refreshTask() async {
    final ok = await platform.privileges.isConfigured();
    if (mounted) setState(() => _taskInstalled = ok);
  }

  Future<void> _installTask() async {
    setState(() => _busy = true);
    final ok = await platform.privileges.configure();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refreshTask();
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? l.tunTaskDone : l.tunTaskFailed),
    ));
  }

  Future<void> _removeTask() async {
    setState(() => _busy = true);
    await platform.privileges.remove();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refreshTask();
  }

  Future<void> _showLog() async {
    final log = await platform.tunLog.tail(lines: 200);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.tunLogTitle),
        content: SizedBox(
          width: 640,
          height: 420,
          child: log.isEmpty
              ? Center(child: Text(l.tunLogEmpty))
              : SingleChildScrollView(
                  child: SelectableText(log,
                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 12)),
                ),
        ),
        actions: [
          TextButton(
            onPressed: log.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: log));
                    AppToast.copied(context);
                  },
            child: Text(l.tunCopy),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.tunClose)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.tunTitle)),
      body: ListView(
        children: [
          _header(context, l.tunSectionPrivilege, l.infoTunPrivilege),
          ListTile(
            leading: Icon(
              _taskInstalled == true ? Icons.verified_user : Icons.shield_outlined,
              color: _taskInstalled == true ? Colors.green : null,
            ),
            title: Text(_taskInstalled == null
                ? l.tunChecking
                : _taskInstalled!
                    ? l.tunNoUacConfigured
                    : l.tunUacEachConnect),
            subtitle: Text(l.tunTaskSubtitle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OverflowBar(spacing: 8, children: [
              FilledButton.icon(
                icon: const Icon(Icons.admin_panel_settings),
                label: Text(_taskInstalled == true
                    ? l.tunRecreateTask
                    : l.tunSetupOneUac),
                onPressed: _busy ? null : _installTask,
              ),
              if (_taskInstalled == true)
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l.tunRemoveTask),
                  onPressed: _busy ? null : _removeTask,
                ),
            ]),
          ),
          const Divider(),

          _header(context, l.tunSectionAdapter, l.infoTunStack),
          ListTile(
            title: Row(children: [
              Text(l.tunStack),
              InfoTooltip(l.infoTunStack),
            ]),
            trailing: SegmentedButton<TunStack>(
              segments: TunStack.values
                  .map((v) => ButtonSegment(value: v, label: Text(v.name)))
                  .toList(),
              selected: {s.tunStack},
              showSelectedIcon: false,
              onSelectionChanged: (v) =>
                  controller.update((st) => st.copyWith(tunStack: v.first)),
            ),
          ),
          ListTile(
            title: Row(children: [
              const Text('MTU'),
              InfoTooltip(l.infoTunMtu),
            ]),
            trailing: SizedBox(
              width: 90,
              child: TextFormField(
                initialValue: '${s.tunMtu}',
                textAlign: TextAlign.end,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true),
                onChanged: (v) {
                  final mtu = int.tryParse(v);
                  if (mtu != null && mtu >= 576 && mtu <= 9000) {
                    controller.update((st) => st.copyWith(tunMtu: mtu));
                  }
                },
              ),
            ),
          ),
          const Divider(),

          _header(context, l.tunSectionRouting, l.infoTunStrictRoute),
          _switch(context, controller,
              value: s.tunStrictRoute,
              title: l.tunStrictRoute,
              info: l.infoTunStrictRoute,
              apply: (st, v) => st.copyWith(tunStrictRoute: v)),
          _switch(context, controller,
              value: s.tunIpv6,
              title: l.tunIpv6,
              info: l.infoTunIpv6,
              apply: (st, v) => st.copyWith(tunIpv6: v)),
          _switch(context, controller,
              value: s.tunEndpointIndependentNat,
              title: l.tunEndpointNat,
              info: l.infoTunEndpointIndependentNat,
              apply: (st, v) => st.copyWith(tunEndpointIndependentNat: v)),
          _switch(context, controller,
              value: s.tunBypassLan,
              title: l.tunLanBypass,
              info: l.infoTunBypassLan,
              apply: (st, v) => st.copyWith(tunBypassLan: v)),
          _CidrEditor(controller: controller),
          const Divider(),

          _header(context, 'DNS', l.infoDnsMode),
          ...DnsMode.values.map((m) => RadioListTile<DnsMode>(
                value: m,
                groupValue: s.dnsMode,
                onChanged: (v) => controller.update((st) => st.copyWith(dnsMode: v)),
                title: Text(_dnsLabel(l, m)),
                subtitle: Text(_dnsHint(l, m)),
              )),
          if (s.dnsMode == DnsMode.custom)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextFormField(
                initialValue: s.dnsCustomServer,
                decoration: InputDecoration(
                  labelText: l.tunDnsServer,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => controller
                    .update((st) => st.copyWith(dnsCustomServer: v.trim())),
              ),
            ),
          if (s.dnsMode != DnsMode.system)
            _switch(context, controller,
                value: s.dnsHijack,
                title: l.tunDnsHijack,
                info: l.infoDnsHijack,
                apply: (st, v) => st.copyWith(dnsHijack: v)),
          // Виден только там, где имеет смысл: в остальных режимах весь трафик
          // и так в туннеле, и вопроса «куда девать DNS остальных» не стоит.
          if (s.dnsMode != DnsMode.system &&
              s.splitTunnel.mode == SplitMode.onlySelected)
            _switch(context, controller,
                value: s.tunnelDnsForAll,
                title: l.tunDnsForAll,
                info: l.infoDnsForAll,
                apply: (st, v) => st.copyWith(tunnelDnsForAll: v)),
          ListTile(
            title: Row(children: [
              Text(l.tunResolveStrategy),
              InfoTooltip(l.infoDnsStrategy),
            ]),
            trailing: DropdownButton<DnsStrategy>(
              value: s.dnsStrategy,
              onChanged: (v) =>
                  controller.update((st) => st.copyWith(dnsStrategy: v)),
              items: DnsStrategy.values
                  .map((v) => DropdownMenuItem(
                      value: v, child: Text(v.singboxValue)))
                  .toList(),
            ),
          ),
          const Divider(),

          _header(context, l.tunSectionDiagnostics, l.infoSingboxLogLevel),
          ListTile(
            title: Row(children: [
              Text(l.tunSingboxLogLevel),
              InfoTooltip(l.infoSingboxLogLevel),
            ]),
            trailing: SegmentedButton<SingboxLogLevel>(
              segments: SingboxLogLevel.values
                  .map((v) => ButtonSegment(value: v, label: Text(v.name)))
                  .toList(),
              selected: {s.singboxLogLevel},
              showSelectedIcon: false,
              onSelectionChanged: (v) =>
                  controller.update((st) => st.copyWith(singboxLogLevel: v.first)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.article_outlined),
              label: Text(l.tunShowLog),
              onPressed: _showLog,
            ),
          ),
        ],
      ),
    );
  }

  static String _dnsLabel(AppLocalizations l, DnsMode m) {
    switch (m) {
      case DnsMode.vpn:
        return l.tunDnsVpn;
      case DnsMode.system:
        return l.tunDnsSystem;
      case DnsMode.custom:
        return l.tunDnsCustom;
    }
  }

  static String _dnsHint(AppLocalizations l, DnsMode m) {
    switch (m) {
      case DnsMode.vpn:
        return l.tunDnsVpnHint;
      case DnsMode.system:
        return l.tunDnsSystemHint;
      case DnsMode.custom:
        return l.tunDnsCustomHint;
    }
  }

  Widget _header(BuildContext context, String title, String info) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(children: [
          Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )),
          InfoTooltip(info, title: title),
        ]),
      );

  Widget _switch(
    BuildContext context,
    SettingsController controller, {
    required bool value,
    required String title,
    required String info,
    required AppSettings Function(AppSettings, bool) apply,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: (v) => controller.update((st) => apply(st, v)),
      title: Row(children: [
        Expanded(child: Text(title)),
        InfoTooltip(info, title: title),
      ]),
    );
  }
}

/// Список подсетей-исключений (CIDR).
class _CidrEditor extends StatefulWidget {
  final SettingsController controller;
  const _CidrEditor({required this.controller});
  @override
  State<_CidrEditor> createState() => _CidrEditorState();
}

class _CidrEditorState extends State<_CidrEditor> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final v = _input.text.trim();
    if (v.isEmpty || !v.contains('/')) return;
    widget.controller.update((st) {
      if (st.tunExcludeCidrs.contains(v)) return st;
      return st.copyWith(tunExcludeCidrs: [...st.tunExcludeCidrs, v]);
    });
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final list = widget.controller.settings.tunExcludeCidrs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Text(l.tunExcludeSubnets),
            InfoTooltip(l.infoTunExcludeCidrs),
          ]),
        ),
        ...list.map((c) => ListTile(
              dense: true,
              leading: const Icon(Icons.alt_route, size: 20),
              title: Text(c),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => widget.controller.update((st) => st.copyWith(
                    tunExcludeCidrs:
                        st.tunExcludeCidrs.where((x) => x != c).toList())),
              ),
            )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                decoration: const InputDecoration(
                  hintText: '10.8.0.0/24',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _add, child: Text(l.tunAdd)),
          ]),
        ),
      ],
    );
  }
}
