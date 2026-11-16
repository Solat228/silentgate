import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_store.dart';
import '../core/models/vpn_server.dart';
import '../core/net/api_ports.dart';
import '../core/net/ip_info.dart';
import '../core/settings/app_settings.dart';
import '../core/singbox/exit_outbounds.dart';
import '../engine/engine_base.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/app_state.dart';
import '../state/probe_controller.dart';
import '../state/settings_controller.dart';
import 'widgets/app_toast.dart';
import 'widgets/flag_text.dart';
import 'widgets/info_tooltip.dart';
import 'widgets/sel_text.dart';

/// Экран «API для автоматизации».
class ApiScreen extends StatelessWidget {
  const ApiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.watch<SettingsController>();
    return Scaffold(
      appBar: AppBar(title: Text(l.apiSectionTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _ApiBody(settings: controller.settings, controller: controller),
        ],
      ),
    );
  }
}

enum _ServerFilter { all, checked, autoOnly }

class _PortProbeState {
  final bool loading;
  final bool? ok;
  final int? latencyMs;
  final String? summary;

  const _PortProbeState({
    this.loading = false,
    this.ok,
    this.latencyMs,
    this.summary,
  });
}

class _ApiBody extends StatefulWidget {
  final AppSettings settings;
  final SettingsController controller;
  const _ApiBody({required this.settings, required this.controller});

  @override
  State<_ApiBody> createState() => _ApiBodyState();
}

class _ApiBodyState extends State<_ApiBody> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  _ServerFilter _filter = _ServerFilter.all;
  final Map<int, _PortProbeState> _portProbes = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isRu(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase() != 'en';

  String _proxyUrlFor(AppSettings s, int port, {required bool socks}) {
    final scheme = socks ? 'socks5' : 'http';
    final auth = switch (s.apiProxyAuthMode) {
      ApiProxyAuthMode.none => '',
      ApiProxyAuthMode.apiToken =>
        s.apiToken.isEmpty ? 'sg:<TOKEN>@' : 'sg:${Uri.encodeComponent(s.apiToken)}@',
      ApiProxyAuthMode.custom => s.apiProxyCustomUser.trim().isEmpty
          ? ''
          : '${Uri.encodeComponent(s.apiProxyCustomUser.trim())}:${Uri.encodeComponent(s.apiProxyCustomPassword)}@',
    };
    return '$scheme://${auth}127.0.0.1:$port';
  }

  void _copyProxyUrl(BuildContext context, int port, {required bool socks}) {
    final url = _proxyUrlFor(widget.settings, port, socks: socks);
    Clipboard.setData(ClipboardData(text: url));
    AppToast.copied(context);
  }

  Future<void> _testPort(int port) async {
    final s = widget.settings;
    setState(() {
      _portProbes[port] = const _PortProbeState(loading: true);
    });
    final creds = switch (s.apiProxyAuthMode) {
      ApiProxyAuthMode.apiToken => (user: 'sg', pass: s.apiToken),
      ApiProxyAuthMode.none => (user: '', pass: ''),
      ApiProxyAuthMode.custom => (
          user: s.apiProxyCustomUser.trim(),
          pass: s.apiProxyCustomPassword,
        ),
    };
    final sw = Stopwatch()..start();
    try {
      final info = await IpInfoService.lookup(
        proxyPort: port,
        proxyUser: creds.user,
        proxyPassword: creds.pass,
        timeout: const Duration(seconds: 8),
      );
      sw.stop();
      if (!mounted) return;
      if (info == null) {
        setState(() {
          _portProbes[port] = _PortProbeState(
            loading: false,
            ok: false,
            latencyMs: sw.elapsedMilliseconds,
            summary: _isRu(context)
                ? 'Порт не отвечает (включите VPN или фоновый режим API)'
                : 'Port unreachable (connect VPN or enable background API ports)',
          );
        });
        return;
      }
      final loc = [info.countryCode ?? info.country, info.city]
          .whereType<String>()
          .where((e) => e.trim().isNotEmpty)
          .join(', ');
      setState(() {
        _portProbes[port] = _PortProbeState(
          loading: false,
          ok: true,
          latencyMs: sw.elapsedMilliseconds,
          summary: '${info.ip}${loc.isNotEmpty ? " ($loc)" : ""} · ${sw.elapsedMilliseconds} ms',
        );
      });
    } catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _portProbes[port] = _PortProbeState(
          loading: false,
          ok: false,
          latencyMs: sw.elapsedMilliseconds,
          summary: '$e',
        );
      });
    }
  }

  void _toggleServer(VpnServer srv, bool enabled, List<VpnServer> allCatalog) {
    widget.controller.update((s) {
      final nextKeys = enabled
          ? <String>{...s.apiExitServerKeys, srv.key}.toList()
          : s.apiExitServerKeys.where((k) => k != srv.key).toList();
      final effective = ApiPorts.effectiveServerKeys(
        s.copyWith(apiExitServerKeys: nextKeys),
        allCatalog,
      );
      final sticky = ApiPorts.assignStickyPorts(
        effective,
        s.apiAssignedPorts,
        controlPort: s.apiControlPort,
        autoPort: s.apiAutoPort,
        directPort: s.apiDirectPort,
      );
      return s.copyWith(
        apiExitServerKeys: nextKeys,
        apiAssignedPorts: sticky,
      );
    });
  }

  void _enableAllAuto(List<VpnServer> allCatalog) {
    widget.controller.update((s) {
      final set = <String>{...s.apiExitServerKeys};
      for (final srv in allCatalog) {
        if (srv.isPanelProfile && canBeExitServer(srv)) {
          set.add(srv.key);
        }
      }
      final nextKeys = set.toList();
      final sticky = ApiPorts.assignStickyPorts(
        nextKeys,
        s.apiAssignedPorts,
        controlPort: s.apiControlPort,
        autoPort: s.apiAutoPort,
        directPort: s.apiDirectPort,
      );
      return s.copyWith(
        apiExitServerKeys: nextKeys,
        apiAssignedPorts: sticky,
      );
    });
  }

  void _enableAllServers(List<VpnServer> allCatalog) {
    widget.controller.update((s) {
      final set = <String>{...s.apiExitServerKeys};
      for (final srv in allCatalog) {
        if (set.length >= ApiPorts.maxServers) break;
        if (canBeExitServer(srv)) {
          set.add(srv.key);
        }
      }
      final nextKeys = set.toList();
      final sticky = ApiPorts.assignStickyPorts(
        nextKeys,
        s.apiAssignedPorts,
        controlPort: s.apiControlPort,
        autoPort: s.apiAutoPort,
        directPort: s.apiDirectPort,
      );
      return s.copyWith(
        apiExitServerKeys: nextKeys,
        apiAssignedPorts: sticky,
      );
    });
  }

  void _clearServers() {
    widget.controller.update((s) => s.copyWith(
          apiExitServerKeys: const [],
          apiAutoIncludeAutoProfiles: false,
        ));
  }

  Future<void> _editServerPortDialog(
    BuildContext context,
    VpnServer srv,
    int currentPort,
  ) async {
    final ru = _isRu(context);
    final ctrl = TextEditingController(text: '$currentPort');
    String? errorText;
    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(ru ? 'Порт для «${srv.displayName}»' : 'Port for "${srv.displayName}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ru
                    ? 'Задайте фиксированный локальный порт (1025–65535, кроме служебных 10808–10813, 10855, 10870 и 10910–11199):'
                    : 'Set a fixed local port (1025–65535, excluding reserved internal ports):',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: ru ? 'Номер порта' : 'Port number',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ru ? 'Отмена' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = int.tryParse(ctrl.text.trim());
                final s = widget.settings;
                if (v == null ||
                    ApiPorts.isReservedSystemPort(
                      v,
                      controlPort: s.apiControlPort,
                      autoPort: s.apiAutoPort,
                      directPort: s.apiDirectPort,
                    )) {
                  setLocal(() {
                    errorText = ru
                        ? 'Недопустимый или служебный порт'
                        : 'Invalid or reserved port';
                  });
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: Text(ru ? 'Сохранить' : 'Save'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (chosen == null) return;
    await widget.controller.update((s) {
      final assigned = Map<String, int>.from(s.apiAssignedPorts)
        ..removeWhere((_, p) => p == chosen);
      assigned[srv.key] = chosen;
      final nextKeys = s.apiExitServerKeys.contains(srv.key)
          ? s.apiExitServerKeys
          : [...s.apiExitServerKeys, srv.key];
      return s.copyWith(
        apiExitServerKeys: nextKeys,
        apiAssignedPorts: assigned,
      );
    });
  }

  Future<void> _editCustomCredentialsDialog(BuildContext context) async {
    final ru = _isRu(context);
    final userCtrl =
        TextEditingController(text: widget.settings.apiProxyCustomUser);
    final passCtrl =
        TextEditingController(text: widget.settings.apiProxyCustomPassword);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ru ? 'Свой логин и пароль прокси' : 'Custom proxy credentials'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userCtrl,
              decoration: InputDecoration(
                labelText: ru ? 'Логин' : 'Username',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: ru ? 'Пароль' : 'Password',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ru ? 'Сохранить' : 'Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final u = userCtrl.text.trim();
      final p = passCtrl.text;
      await widget.controller.update((s) => s.copyWith(
            apiProxyAuthMode: ApiProxyAuthMode.custom,
            apiProxyCustomUser: u,
            apiProxyCustomPassword: p,
          ));
    }
    userCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _editBasePortsDialog(BuildContext context) async {
    final ru = _isRu(context);
    final s0 = widget.settings;
    final ctrlPort = TextEditingController(text: '${s0.apiControlPort}');
    final autoPort = TextEditingController(text: '${s0.apiAutoPort}');
    final directPort = TextEditingController(text: '${s0.apiDirectPort}');
    final intervalCtrl =
        TextEditingController(text: '${s0.apiUrltestIntervalSec}');
    String? err;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(ru ? 'Настройка базовых портов API' : 'Configure API base ports'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrlPort,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: ru
                        ? 'Управляющий HTTP-порт (по умолч. 10870)'
                        : 'Control HTTP port (default 10870)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: autoPort,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: ru
                        ? 'Порт «Умный Автовыбор» (по умолч. 10818)'
                        : 'Smart Auto port (default 10818)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: directPort,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: ru
                        ? 'Порт «Прямо» (по умолч. 10819)'
                        : 'Direct port (default 10819)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: intervalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: ru
                        ? 'Интервал проверки Автовыбора, сек (по умолч. 120)'
                        : 'Smart Auto urltest interval, sec (default 120)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    err!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ctrlPort.text = '${ApiPorts.control}';
                autoPort.text = '${ApiPorts.auto}';
                directPort.text = '${ApiPorts.direct}';
                intervalCtrl.text = '120';
              },
              child: Text(ru ? 'По умолчанию' : 'Reset defaults'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ru ? 'Отмена' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final c = int.tryParse(ctrlPort.text.trim());
                final a = int.tryParse(autoPort.text.trim());
                final d = int.tryParse(directPort.text.trim());
                final iv = int.tryParse(intervalCtrl.text.trim());
                if (c == null ||
                    a == null ||
                    d == null ||
                    iv == null ||
                    c <= 1024 ||
                    a <= 1024 ||
                    d <= 1024 ||
                    c > 65535 ||
                    a > 65535 ||
                    d > 65535 ||
                    {c, a, d}.length < 3 ||
                    iv < 15) {
                  setLocal(() {
                    err = ru
                        ? 'Порты должны быть разными (1025–65535), интервал ≥ 15 сек'
                        : 'Ports must be distinct (1025–65535), interval ≥ 15s';
                  });
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(ru ? 'Сохранить' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final c = int.parse(ctrlPort.text.trim());
      final a = int.parse(autoPort.text.trim());
      final d = int.parse(directPort.text.trim());
      final iv = int.parse(intervalCtrl.text.trim());
      await widget.controller.update((s) => s.copyWith(
            apiControlPort: c,
            apiAutoPort: a,
            apiDirectPort: d,
            apiUrltestIntervalSec: iv,
          ));
    }
    ctrlPort.dispose();
    autoPort.dispose();
    directPort.dispose();
    intervalCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ru = _isRu(context);
    final settings = widget.settings;
    final controller = widget.controller;
    final state = context.watch<AppState>();
    final probe = Provider.of<ProbeController?>(context);
    final scheme = Theme.of(context).colorScheme;

    final groups = state.allSubscriptionsGrouped();
    final allCatalog = state.allSubscriptionServers();
    final effectiveKeys = ApiPorts.effectiveServerKeys(settings, allCatalog);
    final effectiveSet = effectiveKeys.toSet();
    final portMap = ApiPorts.resolvePortMap(
      effectiveKeys,
      assignedPorts: settings.apiAssignedPorts,
      controlPort: settings.apiControlPort,
      autoPort: settings.apiAutoPort,
      directPort: settings.apiDirectPort,
    );
    final autoPoolKeys = ApiPorts.autoPoolServerKeys(
      settings,
      activeServers: state.servers,
      allServers: allCatalog,
    );

    final exitPortsExist = ApiPorts.exitPortsExistIn(settings.captureMode);
    final conflict = state.apiPortConflict;
    final portsLiveNow =
        ApiPorts.exitPortsActive(settings) &&
        (state.status.isConnected || state.standaloneApiPortsRunning);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l.apiSectionTitle),
        SwitchListTile(
          value: settings.apiEnabled,
          onChanged: (v) => controller.update((s) => s.copyWith(
                apiEnabled: v,
                apiToken: (v && s.apiToken.isEmpty)
                    ? VpnEngineBase.randomSecret()
                    : s.apiToken,
              )),
          title: Text(l.apiEnableTitle),
          subtitle: Text(l.apiEnableSub(settings.apiControlPort)),
        ),
        if (settings.apiEnabled) ...[
          if (conflict != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline,
                      size: 18, color: scheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.apiPortBusyTitle,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: scheme.onErrorContainer)),
                        const SizedBox(height: 2),
                        SelText(
                          conflict.holder == null
                              ? l.apiPortBusyUnknown(conflict.port)
                              : l.apiPortBusy(conflict.port, conflict.holder!),
                          style: TextStyle(
                              fontSize: 12, color: scheme.onErrorContainer),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),

          _ApiTokenTile(settings: settings, controller: controller),

          if (AppStoreInfo.tunAvailable && settings.apiToken.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: portsLiveNow
                      ? scheme.primaryContainer.withValues(alpha: 0.45)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      portsLiveNow ? Icons.check_circle : Icons.pause_circle_outline,
                      size: 18,
                      color: portsLiveNow ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        portsLiveNow
                            ? (state.standaloneApiPortsRunning
                                ? (ru
                                    ? 'Локальные прокси-порты активны в фоне (VPN выключен) · серверов с портом: ${portMap.length}'
                                    : 'Local proxy ports active in background (VPN off) · server ports: ${portMap.length}')
                                : (ru
                                    ? 'Локальные прокси-порты активны вместе с VPN · серверов с портом: ${portMap.length}'
                                    : 'Local proxy ports active with VPN · server ports: ${portMap.length}'))
                            : (ru
                                ? 'Прокси-порты ждут подключения VPN (или включите «Работать при выключенном VPN» ниже)'
                                : 'Proxy ports wait for VPN connection (or enable background mode below)'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Специальные фиксированные порты (Автовыбор 10818 + Прямо 10819) ──
          if (AppStoreInfo.tunAvailable && settings.apiToken.isNotEmpty) ...[
            _sectionHeader(
              context,
              ru ? 'Фиксированные умные порты' : 'Smart fixed ports',
              trailing: IconButton(
                tooltip: ru ? 'Настроить номера портов' : 'Configure base ports',
                icon: const Icon(Icons.tune, size: 18),
                onPressed: () => _editBasePortsDialog(context),
              ),
            ),
            _FixedPortCard(
              icon: Icons.auto_awesome,
              title: ru
                  ? 'Умный Автовыбор (:${settings.apiAutoPort})'
                  : 'Smart Auto-Select (:${settings.apiAutoPort})',
              subtitle: ru
                  ? 'Автоматически балансирует и выбирает самый быстрый рабочий сервер (узлов в пуле: ${autoPoolKeys.length})'
                  : 'Automatically balances across fastest healthy nodes (pool size: ${autoPoolKeys.length})',
              enabled: settings.apiAutoPortEnabled,
              onToggle: (v) =>
                  controller.update((s) => s.copyWith(apiAutoPortEnabled: v)),
              probeState: _portProbes[settings.apiAutoPort],
              onCopyHttp: () =>
                  _copyProxyUrl(context, settings.apiAutoPort, socks: false),
              onCopySocks: () =>
                  _copyProxyUrl(context, settings.apiAutoPort, socks: true),
              onTest: () => _testPort(settings.apiAutoPort),
              extraBottom: settings.apiAutoPortEnabled
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            ru ? 'Пул Автовыбора:' : 'Auto pool:',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          ChoiceChip(
                            label: Text(ru ? 'Все подписки' : 'All subscriptions'),
                            selected: settings.apiAutoPoolScope ==
                                ApiAutoPoolScope.allSubscriptions,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => controller.update((s) => s.copyWith(
                                apiAutoPoolScope:
                                    ApiAutoPoolScope.allSubscriptions)),
                          ),
                          ChoiceChip(
                            label: Text(ru ? 'Активная' : 'Active sub'),
                            selected: settings.apiAutoPoolScope ==
                                ApiAutoPoolScope.activeSubscription,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => controller.update((s) => s.copyWith(
                                apiAutoPoolScope:
                                    ApiAutoPoolScope.activeSubscription)),
                          ),
                          ChoiceChip(
                            label: Text(ru ? 'Только отмеченные' : 'Checked only'),
                            selected: settings.apiAutoPoolScope ==
                                ApiAutoPoolScope.checkedOnly,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => controller.update((s) => s.copyWith(
                                apiAutoPoolScope: ApiAutoPoolScope.checkedOnly)),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
            _FixedPortCard(
              icon: Icons.public,
              title: ru
                  ? 'Прямо — мимо VPN (:${settings.apiDirectPort})'
                  : 'Direct — bypass VPN (:${settings.apiDirectPort})',
              subtitle: ru
                  ? 'Реальный IP провайдера в один порт для сравнения и локальных сервисов'
                  : 'Real ISP IP through a local proxy port without disconnecting VPN',
              enabled: true,
              onToggle: null,
              probeState: _portProbes[settings.apiDirectPort],
              onCopyHttp: () =>
                  _copyProxyUrl(context, settings.apiDirectPort, socks: false),
              onCopySocks: () =>
                  _copyProxyUrl(context, settings.apiDirectPort, socks: true),
              onTest: () => _testPort(settings.apiDirectPort),
            ),

            // ── Режим работы и авторизация прокси-портов ───────────────────────
            _sectionHeader(
              context,
              ru ? 'Режим работы и безопасность портов' : 'Port behavior & auth',
            ),
            SwitchListTile(
              dense: true,
              value: settings.apiKeepAliveWhenDisconnected,
              onChanged: (v) => controller.update(
                (s) => s.copyWith(apiKeepAliveWhenDisconnected: v),
              ),
              title: Text(
                ru
                    ? 'Держать порты API активными при выключенном VPN'
                    : 'Keep API proxy ports active when VPN is disconnected',
              ),
              subtitle: Text(
                ru
                    ? 'Поднимает фоновый маршрутизатор портов без TUN и без вмешательства в трафик системы'
                    : 'Runs standalone local proxy ports in background without capturing OS traffic',
              ),
            ),
            SwitchListTile(
              dense: true,
              value: settings.apiAutoIncludeAutoProfiles,
              onChanged: (v) => controller.update((s) {
                final next = s.copyWith(apiAutoIncludeAutoProfiles: v);
                final eff = ApiPorts.effectiveServerKeys(next, allCatalog);
                final sticky = ApiPorts.assignStickyPorts(
                  eff,
                  s.apiAssignedPorts,
                  controlPort: s.apiControlPort,
                  autoPort: s.apiAutoPort,
                  directPort: s.apiDirectPort,
                );
                return next.copyWith(apiAssignedPorts: sticky);
              }),
              title: Text(
                ru
                    ? 'Автоматически выдавать порты всем профилям «Авто»'
                    : 'Automatically assign ports to all "Auto" profiles',
              ),
              subtitle: Text(
                ru
                    ? 'Все текущие и новые балансировочные профили Авто из подписок сразу получают свои порты (общие узлы дедуплицируются)'
                    : 'All panel Auto balancer profiles automatically get dedicated ports with shared node deduplication',
              ),
            ),
            SwitchListTile(
              dense: true,
              value: settings.apiDnsViaExit,
              onChanged: (v) =>
                  controller.update((s) => s.copyWith(apiDnsViaExit: v)),
              title: Text(
                ru
                    ? 'Изолировать DNS каждого порта через его сервер'
                    : 'Isolate DNS per exit port',
              ),
              subtitle: Text(
                ru
                    ? 'Запросы к немецкому порту резолвят домены через Германию, исключая утечку гео-DNS'
                    : 'Resolves domains through the target port exit to prevent geo-DNS mismatch',
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.lock_outline),
              title: Text(
                ru
                    ? 'Авторизация на локальных прокси-портах (10818, 10819, 10820+)'
                    : 'Authentication on local proxy ports',
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(ru ? 'По токену (sg:<токен>)' : 'API token (sg:<token>)'),
                      selected:
                          settings.apiProxyAuthMode == ApiProxyAuthMode.apiToken,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => controller.update((s) =>
                          s.copyWith(apiProxyAuthMode: ApiProxyAuthMode.apiToken)),
                    ),
                    ChoiceChip(
                      label: Text(ru ? 'Без пароля (127.0.0.1)' : 'No password (127.0.0.1)'),
                      selected:
                          settings.apiProxyAuthMode == ApiProxyAuthMode.none,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => controller.update((s) =>
                          s.copyWith(apiProxyAuthMode: ApiProxyAuthMode.none)),
                    ),
                    ChoiceChip(
                      label: Text(
                        settings.apiProxyAuthMode == ApiProxyAuthMode.custom &&
                                settings.apiProxyCustomUser.trim().isNotEmpty
                            ? (ru ? 'Свой логин/пароль ✓' : 'Custom login ✓')
                            : (ru ? 'Свой логин/пароль…' : 'Custom login…'),
                      ),
                      selected:
                          settings.apiProxyAuthMode == ApiProxyAuthMode.custom,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _editCustomCredentialsDialog(context),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (!exitPortsExist && AppStoreInfo.tunAvailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelText(l.apiCaptureModeWarning(settings.apiControlPort),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ]),
              ),
            ),

          // ── Серверы с отдельным портом (все подписки, липкие порты, до 250) ──
          if (allCatalog.isNotEmpty && AppStoreInfo.tunAvailable) ...[
            ListTile(
              dense: true,
              title: Text(l.apiExitsTitle),
              subtitle: Text(
                '${l.apiExitsSub} (${portMap.length} / ${ApiPorts.maxServers})',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome, size: 16),
                    label: Text(ru ? 'Все Авто' : 'All Auto'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _enableAllAuto(allCatalog),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.done_all, size: 16),
                    label: Text(ru ? 'Все серверы' : 'All servers'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _enableAllServers(allCatalog),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.clear_all, size: 16),
                    label: Text(ru ? 'Сбросить' : 'Clear'),
                    visualDensity: VisualDensity.compact,
                    onPressed: effectiveSet.isEmpty ? null : _clearServers,
                  ),
                ],
              ),
            ),
            if (allCatalog.length > 6)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        hintText: ru
                            ? 'Поиск по названию, стране или подписке…'
                            : 'Search by name, country or subscription…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        FilterChip(
                          label: Text(ru ? 'Все (${allCatalog.length})' : 'All (${allCatalog.length})'),
                          selected: _filter == _ServerFilter.all,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _filter = _ServerFilter.all),
                        ),
                        FilterChip(
                          label: Text(
                            ru
                                ? 'С портом (${portMap.length})'
                                : 'Assigned (${portMap.length})',
                          ),
                          selected: _filter == _ServerFilter.checked,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _filter = _ServerFilter.checked),
                        ),
                        FilterChip(
                          label: Text(ru ? 'Профили Авто' : 'Auto profiles'),
                          selected: _filter == _ServerFilter.autoOnly,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _filter = _ServerFilter.autoOnly),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ..._buildGroupedServers(
              context,
              groups: groups,
              effectiveSet: effectiveSet,
              portMap: portMap,
              allCatalog: allCatalog,
              probe: probe,
            ),
          ],

          if (AppStoreInfo.tunAvailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                l.apiPortsHint(
                  settings.apiControlPort,
                  settings.apiDirectPort,
                  ApiPorts.firstServer,
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),

          _ApiCheatSheet(settings: settings, servers: allCatalog),

          ListTile(
            dense: true,
            leading: const Icon(Icons.terminal),
            title: Text(l.apiCopyCurlExample),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: _curlExample(settings)),
              );
              AppToast.copied(context);
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.code),
            title: Text(l.apiCopyPythonExample),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: _pythonExample(settings)),
              );
              AppToast.copied(context);
            },
          ),
        ],
      ],
    );
  }

  List<Widget> _buildGroupedServers(
    BuildContext context, {
    required List<({dynamic profile, bool active, List<VpnServer> servers})>
        groups,
    required Set<String> effectiveSet,
    required Map<String, int> portMap,
    required List<VpnServer> allCatalog,
    required ProbeController? probe,
  }) {
    final ru = _isRu(context);
    final scheme = Theme.of(context).colorScheme;
    final q = _query.toLowerCase();
    final showGroupHeaders = groups.length > 1;
    final seen = <String>{};
    final widgets = <Widget>[];

    for (final g in groups) {
      final subTitle = g.profile?.safeTitle as String? ??
          (ru ? 'Локальные / закреплённые' : 'Local / pinned');
      final filtered = <VpnServer>[];
      for (final srv in g.servers) {
        if (!seen.add(srv.key)) continue;
        final isChecked = effectiveSet.contains(srv.key);
        if (_filter == _ServerFilter.checked && !isChecked) continue;
        if (_filter == _ServerFilter.autoOnly && !srv.isPanelProfile) continue;
        if (q.isNotEmpty) {
          final hay =
              '${srv.displayName} ${srv.protocol} $subTitle ${portMap[srv.key] ?? ''}'
                  .toLowerCase();
          if (!hay.contains(q)) continue;
        }
        filtered.add(srv);
      }
      if (filtered.isEmpty) continue;

      if (showGroupHeaders) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Row(
              children: [
                Icon(
                  g.active ? Icons.folder_special : Icons.folder_outlined,
                  size: 15,
                  color: g.active ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    subTitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: g.active ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (g.active)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ru ? 'активная' : 'active',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      for (final srv in filtered) {
        final isChecked = effectiveSet.contains(srv.key);
        final autoLocked =
            widget.settings.apiAutoIncludeAutoProfiles && srv.isPanelProfile && canBeExitServer(srv);
        final port = portMap[srv.key];
        final pingMs = probe?.resultFor(srv).latencyMs;
        widgets.add(
          _ApiExitCheckbox(
            server: srv,
            checked: isChecked,
            autoIncluded: autoLocked && !widget.settings.apiExitServerKeys.contains(srv.key),
            assignedPort: port,
            pingMs: pingMs,
            probeState: port != null ? _portProbes[port] : null,
            onChanged: autoLocked && !widget.settings.apiExitServerKeys.contains(srv.key)
                ? null
                : (v) => _toggleServer(srv, v == true, allCatalog),
            onEditPort: port != null
                ? () => _editServerPortDialog(context, srv, port)
                : null,
            onCopyHttp: port != null
                ? () => _copyProxyUrl(context, port, socks: false)
                : null,
            onCopySocks: port != null
                ? () => _copyProxyUrl(context, port, socks: true)
                : null,
            onTestPort: port != null ? () => _testPort(port) : null,
          ),
        );
      }
    }
    return widgets;
  }

  static String _curlExample(AppSettings s) {
    final token = s.apiToken.isEmpty ? '<токен>' : s.apiToken;
    final base = 'http://127.0.0.1:${s.apiControlPort}';
    return '# Состояние движка\n'
        'curl -s $base/v1/status -H "Authorization: Bearer $token"\n'
        '\n'
        '# Активные порты выходов (Умный Автовыбор :${s.apiAutoPort}, серверы, Прямо :${s.apiDirectPort})\n'
        'curl -s $base/v1/exits -H "Authorization: Bearer $token"\n'
        '\n'
        '# Запрос через порт «Умный Автовыбор»\n'
        'curl -s -x http://sg:$token@127.0.0.1:${s.apiAutoPort} https://ipwho.is/\n'
        '\n'
        '# Подключиться «Авто» (на живом канале - сменить сервер)\n'
        'curl -s -X POST $base/v1/connect '
        '-H "Authorization: Bearer $token" '
        '-H "Content-Type: application/json" '
        "-d '{\"auto\": true}'\n";
  }

  static String _pythonExample(AppSettings s) {
    final token = s.apiToken.isEmpty ? '<токен>' : s.apiToken;
    return 'import requests\n'
        '\n'
        'BASE = "http://127.0.0.1:${s.apiControlPort}"\n'
        'HEADERS = {"Authorization": "Bearer $token"}\n'
        'AUTO_PROXY = "http://sg:$token@127.0.0.1:${s.apiAutoPort}"\n'
        '\n'
        'status = requests.get(f"{BASE}/v1/status", headers=HEADERS).json()\n'
        'print("Status:", status)\n'
        '\n'
        '# Запрос сразу через балансируемый порт «Умный Автовыбор»\n'
        'ip = requests.get("https://ipwho.is/", proxies={"http": AUTO_PROXY, "https": AUTO_PROXY}).json()\n'
        'print("Exit IP:", ip.get("ip"), ip.get("country"))\n';
  }
}

class _FixedPortCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool>? onToggle;
  final _PortProbeState? probeState;
  final VoidCallback onCopyHttp;
  final VoidCallback onCopySocks;
  final VoidCallback onTest;
  final Widget? extraBottom;

  const _FixedPortCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onToggle,
    required this.probeState,
    required this.onCopyHttp,
    required this.onCopySocks,
    required this.onTest,
    this.extraBottom,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ru = Localizations.localeOf(context).languageCode.toLowerCase() != 'en';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: enabled ? scheme.primary : scheme.outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (onToggle != null)
                  Switch(value: enabled, onChanged: onToggle),
              ],
            ),
            if (enabled) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onCopyHttp,
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('HTTP'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onCopySocks,
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('SOCKS5'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: (probeState?.loading ?? false) ? null : onTest,
                    icon: (probeState?.loading ?? false)
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 15),
                    label: Text(ru ? 'Проверить порт' : 'Test port'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              if (probeState?.summary != null) ...[
                const SizedBox(height: 6),
                SelText(
                  probeState!.summary!,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: probeState!.ok == true ? scheme.primary : scheme.error,
                  ),
                ),
              ],
              if (extraBottom != null) extraBottom!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Строка токена: показать/скрыть, скопировать, перевыпустить.
class _ApiTokenTile extends StatefulWidget {
  final AppSettings settings;
  final SettingsController controller;
  const _ApiTokenTile({required this.settings, required this.controller});

  @override
  State<_ApiTokenTile> createState() => _ApiTokenTileState();
}

class _ApiTokenTileState extends State<_ApiTokenTile> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = widget.settings;
    final empty = settings.apiToken.isEmpty;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.vpn_key_outlined),
      title: Row(children: [
        Expanded(child: Text(l.apiTokenTitle)),
        InfoTooltip(l.apiTokenWarning, title: l.apiTokenTitle),
      ]),
      subtitle: empty
          ? Text(l.apiTokenUnset)
          : (_shown
              ? SelectableText(settings.apiToken,
                  textDirection: TextDirection.ltr,
                  style:
                      const TextStyle(fontSize: 12, fontFamily: 'monospace'))
              : Text('${'•' * 12}  ${l.apiTokenHidden}',
                  style: const TextStyle(fontSize: 12))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!empty)
            IconButton(
              key: const Key('apiTokenReveal'),
              tooltip: _shown ? l.apiTokenHide : l.apiTokenShow,
              icon: Icon(
                  _shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18),
              onPressed: () => setState(() => _shown = !_shown),
            ),
          if (!empty)
            IconButton(
              tooltip: l.commonCopy,
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: settings.apiToken));
                AppToast.copied(context);
              },
            ),
          IconButton(
            tooltip: l.apiTokenRegenerate,
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () {
              setState(() => _shown = false);
              widget.controller.update(
                  (s) => s.copyWith(apiToken: VpnEngineBase.randomSecret()));
            },
          ),
        ],
      ),
    );
  }
}

/// Памятка по API с ЖИВЫМИ значениями.
class _ApiCheatSheet extends StatelessWidget {
  final AppSettings settings;
  final List<VpnServer> servers;
  const _ApiCheatSheet({required this.settings, required this.servers});

  static const _endpoints = <(String, String)>[
    ('GET', '/v1/status'),
    ('GET', '/v1/servers'),
    ('GET', '/v1/exits'),
    ('GET', '/v1/traffic'),
    ('GET', '/v1/subscription'),
    ('GET', '/v1/subscriptions'),
    ('POST', '/v1/connect'),
    ('POST', '/v1/disconnect'),
    ('POST', '/v1/ping'),
    ('POST', '/v1/subscriptions/select'),
    ('POST', '/v1/subscriptions/refresh'),
    ('POST', '/v1/exits/configure'),
    ('POST', '/v1/exits/test'),
  ];

  String _describe(BuildContext context, AppLocalizations l, String path) {
    final ru = Localizations.localeOf(context).languageCode.toLowerCase() != 'en';
    return switch (path) {
      '/v1/status' => l.apiEpStatus,
      '/v1/servers' => l.apiEpServers,
      '/v1/exits' => l.apiEpExits,
      '/v1/traffic' => l.apiEpTraffic,
      '/v1/subscription' => l.apiEpSubscription,
      '/v1/subscriptions' =>
        ru ? 'Список всех подписок (без секретных URL)' : 'List all subscriptions (redacted)',
      '/v1/connect' => l.apiEpConnect,
      '/v1/disconnect' => l.apiEpDisconnect,
      '/v1/ping' => l.apiEpPing,
      '/v1/subscriptions/select' =>
        ru ? 'Переключить активную подписку по id/title' : 'Switch active subscription',
      '/v1/subscriptions/refresh' =>
        ru ? 'Обновить активную или все подписки' : 'Refresh subscription(s)',
      '/v1/exits/configure' =>
        ru ? 'Настроить порты выходов (Все Авто / липкий порт / режим)' : 'Configure exit ports & modes',
      '/v1/exits/test' =>
        ru ? 'Проверить задержку и внешний IP конкретного порта' : 'Probe port latency & egress IP',
      _ => l.apiEpPing,
    };
  }

  List<({int port, String name})> _serverPorts() {
    final keys = ApiPorts.effectiveServerKeys(settings, servers);
    final map = ApiPorts.resolvePortMap(
      keys,
      assignedPorts: settings.apiAssignedPorts,
      controlPort: settings.apiControlPort,
      autoPort: settings.apiAutoPort,
      directPort: settings.apiDirectPort,
    );
    final sortedKeys = map.keys.toList()
      ..sort((a, b) => map[a]!.compareTo(map[b]!));
    final out = <({int port, String name})>[];
    for (final key in sortedKeys) {
      final port = map[key];
      if (port == null) continue;
      final srv = servers.where((s) => s.key == key).firstOrNull;
      if (srv == null || !canBeExitServer(srv)) continue;
      out.add((port: port, name: srv.displayName));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ru = Localizations.localeOf(context).languageCode.toLowerCase() != 'en';
    final scheme = Theme.of(context).colorScheme;
    const mono = TextStyle(fontSize: 12, fontFamily: 'monospace');
    final small = Theme.of(context).textTheme.bodySmall;
    final tokenEmpty = settings.apiToken.isEmpty;
    final exitPortsExist = ApiPorts.exitPortsExistIn(settings.captureMode);
    final ports = _serverPorts();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.apiCheatSheetTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(l.apiCheatSheetBase, style: small),
            SelText('http://127.0.0.1:${settings.apiControlPort}',
                textDirection: TextDirection.ltr, style: mono),
            if (!AppStoreInfo.tunAvailable)
              const SizedBox.shrink()
            else ...[
              const SizedBox(height: 8),
              Text(l.apiCheatSheetExitPorts, style: small),
              if (!exitPortsExist)
                SelText(l.apiCheatSheetPortsSystemProxy(settings.apiControlPort),
                    style: mono)
              else if (tokenEmpty)
                SelText(l.apiCheatSheetTokenOff, style: mono)
              else ...[
                if (settings.apiAutoPortEnabled)
                  SelText(
                    ru
                        ? '127.0.0.1:${settings.apiAutoPort} — Умный Автовыбор (балансировщик)'
                        : '127.0.0.1:${settings.apiAutoPort} — Smart Auto-Select (balancer)',
                    textDirection: TextDirection.ltr,
                    style: mono,
                  ),
                SelText(l.apiCheatSheetPortDirect(settings.apiDirectPort),
                    textDirection: TextDirection.ltr, style: mono),
                if (ports.isEmpty)
                  SelText(l.apiCheatSheetNoExitServers, style: mono)
                else
                  for (final p in ports)
                    SelText(l.apiCheatSheetPortServer(p.port, p.name),
                        textDirection: TextDirection.ltr, style: mono),
                const SizedBox(height: 4),
                Text(l.apiCheatSheetPortsWhenConnected, style: small),
              ],
            ],
            const SizedBox(height: 8),
            Text(l.apiCheatSheetEndpoints, style: small),
            for (final e in _endpoints)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 215,
                      child: SelText('${e.$1} ${e.$2}',
                          textDirection: TextDirection.ltr, style: mono),
                    ),
                    Expanded(child: Text(_describe(context, l, e.$2), style: small)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ApiExitCheckbox extends StatelessWidget {
  final VpnServer server;
  final bool checked;
  final bool autoIncluded;
  final int? assignedPort;
  final int? pingMs;
  final _PortProbeState? probeState;
  final ValueChanged<bool?>? onChanged;
  final VoidCallback? onEditPort;
  final VoidCallback? onCopyHttp;
  final VoidCallback? onCopySocks;
  final VoidCallback? onTestPort;

  const _ApiExitCheckbox({
    required this.server,
    required this.checked,
    this.autoIncluded = false,
    this.assignedPort,
    this.pingMs,
    this.probeState,
    required this.onChanged,
    this.onEditPort,
    this.onCopyHttp,
    this.onCopySocks,
    this.onTestPort,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ru = Localizations.localeOf(context).languageCode.toLowerCase() != 'en';
    final scheme = Theme.of(context).colorScheme;
    final unsupported = !canBeExitServer(server);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: checked,
          onChanged: onChanged,
          title: Row(
            children: [
              Expanded(
                child: FlagText(
                  server.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: unsupported
                      ? TextStyle(color: Theme.of(context).disabledColor)
                      : null,
                ),
              ),
              if (server.isPanelProfile) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    autoIncluded ? (ru ? 'Авто · автопорт' : 'Auto · auto-port') : (ru ? 'Авто' : 'Auto'),
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
              if (pingMs != null) ...[
                const SizedBox(width: 6),
                Text(
                  '${pingMs}ms',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: scheme.primary,
                  ),
                ),
              ],
            ],
          ),
          subtitle: probeState?.summary != null
              ? Text(
                  probeState!.summary!,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: probeState!.ok == true ? scheme.primary : scheme.error,
                  ),
                )
              : null,
          secondary: unsupported
              ? InfoTooltip(l.exitServerUnsupported(server.displayName))
              : (checked && assignedPort != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: onEditPort,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              ':$assignedPort',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                        if (onCopyHttp != null)
                          IconButton(
                            tooltip: ru ? 'Скопировать HTTP прокси' : 'Copy HTTP proxy',
                            icon: const Icon(Icons.http, size: 17),
                            visualDensity: VisualDensity.compact,
                            onPressed: onCopyHttp,
                          ),
                        if (onCopySocks != null)
                          IconButton(
                            tooltip: ru ? 'Скопировать SOCKS5 прокси' : 'Copy SOCKS5 proxy',
                            icon: const Icon(Icons.hub_outlined, size: 16),
                            visualDensity: VisualDensity.compact,
                            onPressed: onCopySocks,
                          ),
                        if (onTestPort != null)
                          IconButton(
                            tooltip: ru ? 'Проверить выход порта' : 'Test port egress',
                            icon: (probeState?.loading ?? false)
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.network_check, size: 16),
                            visualDensity: VisualDensity.compact,
                            onPressed: (probeState?.loading ?? false) ? null : onTestPort,
                          ),
                      ],
                    )
                  : null),
        ),
      ],
    );
  }
}

Widget _sectionHeader(BuildContext context, String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Row(
      children: [
        Expanded(
          child: SelText(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );
}
