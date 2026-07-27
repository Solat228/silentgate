import 'package:flutter/material.dart';
import 'widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/vpn_server.dart';
import '../core/net/ip_info.dart';
import '../core/net/speed_test.dart';
import '../core/probe/probe_harness.dart';
import '../core/util/country_flag.dart';
import '../core/i18n/enum_labels.dart';
import '../core/i18n/text_direction.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/app_state.dart';
import '../engine/probe_factory.dart';
import '../state/probe_controller.dart';
import '../state/settings_controller.dart';
import 'widgets/flag_cell.dart';
import 'widgets/ping_chip.dart';

/// Информация о сервере: куда вы выходите через него (IP, страна, провайдер),
/// какая задержка и какая реальная скорость.
///
/// Всё меряется через **проброс-харнесс** — отдельный Xray с локальным прокси.
/// Системный прокси и TUN не трогаются, поэтому проверка не требует включать VPN.
class ServerInfoScreen extends StatefulWidget {
  final VpnServer server;
  const ServerInfoScreen({super.key, required this.server});

  @override
  State<ServerInfoScreen> createState() => _ServerInfoScreenState();
}

class _ServerInfoScreenState extends State<ServerInfoScreen> {
  IpInfo? _viaServer; // адрес и гео самого сервера
  SpeedResult? _speedDirect;
  SpeedResult? _speedServer;

  bool _loadingIp = false;
  bool _testingSpeed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadIps();
  }

  /// Поднять харнесс для этого сервера и выполнить [action] с его портом.
  Future<T?> _withHarness<T>(Future<T> Function(int port) action) async {
    final l = AppLocalizations.of(context);
    HarnessHandle? handle;
    try {
      // Вариация (fragment/fingerprint) обязательна: без неё сервер, который
      // работает только с обходом, покажет «не удалось» вместо скорости —
      // ровно как это было до автонастройки.
      final variant = context.read<AppState>().variantFor(widget.server);
      handle = await createProbeHarness().start([
        HarnessEntry(key: widget.server.key, server: widget.server, variant: variant),
      ]);
      return await action(handle.proxyPortFor(0));
    } catch (e) {
      if (mounted) setState(() => _error = l.srvInfoProbeFailed('$e'));
      return null;
    } finally {
      await handle?.stop();
    }
  }

  /// Локация сервера определяется по ЕГО адресу (резолв + гео по этому IP).
  /// Мы намеренно не выходим ни через сервер, ни напрямую: туннель для справки
  /// поднимать незачем, а лишний прямой запрос раскрывал бы ваш реальный адрес.
  /// Прямой замер остаётся только в тесте скорости — там он нужен для сравнения.
  Future<void> _loadIps() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _loadingIp = true;
      _error = null;
    });
    final info = await IpInfoService.lookupHost(widget.server.address);
    if (!mounted) return;
    setState(() {
      _viaServer = info;
      _loadingIp = false;
      if (info == null) _error = l.srvInfoServerAddressFailed;
    });
  }

  Future<void> _runSpeed() async {
    final size = context.read<SettingsController>().settings.speedTestSize;
    setState(() {
      _testingSpeed = true;
      _error = null;
    });
    final direct = await SpeedTest.download(size: size);
    final viaServer =
        await _withHarness((port) => SpeedTest.download(size: size, proxyPort: port));
    if (!mounted) return;
    setState(() {
      _speedDirect = direct;
      _speedServer = viaServer;
      _testingSpeed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = widget.server;
    final size = context.watch<SettingsController>().settings.speedTestSize;
    final ping = context.watch<ProbeController>().resultFor(s);

    return Scaffold(
      appBar: AppBar(title: Text(l.srvInfoTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            FlagCell(s.remark, width: 34, height: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(FlagUtil.strip(s.displayName),
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            PingChip(result: ping),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            // Переводимые теги («АВТОВЫБОР»/«ПАНЕЛЬ»/«ПОРТ-ХОППИНГ») в ar/fa
            // пишутся справа налево, поэтому направление — по содержимому,
            // а не форсированный LTR (технические VLESS/TCP/REALITY он и так даёт).
            for (final t in configTagLabels(l, s.configTags))
              Chip(
                  label: Text(t, textDirection: autoTextDirection(t)),
                  visualDensity: VisualDensity.compact),
          ]),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],

          const SizedBox(height: 16),
          _section(context, l.srvInfoSectionExit),
          Text(
            l.srvInfoExitHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_loadingIp)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            )
          else ...[
            _ipCard(context, l.srvInfoAddressLocation, _viaServer, primary: true),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l.srvInfoCheckAgain),
              onPressed: _loadingIp ? null : _loadIps,
            ),
          ),

          const SizedBox(height: 16),
          _section(context, l.srvInfoSectionSpeed),
          Text(
            l.srvInfoSpeedHint(speedSizeLabel(l, size)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_testingSpeed)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            )
          else ...[
            _speedRow(context, l.srvInfoViaServer, _speedServer, primary: true),
            _speedRow(context, l.srvInfoWithoutVpn, _speedDirect),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.speed, size: 18),
              label: Text(_testingSpeed ? l.srvInfoMeasuring : l.srvInfoMeasureSpeed),
              onPressed: _testingSpeed ? null : _runSpeed,
            ),
          ),

          const SizedBox(height: 16),
          _section(context, l.srvInfoSectionParams),
          _kv(context, l.srvInfoParamAddress, '${s.address}:${s.port}'),
          _kv(context, l.srvInfoParamProtocol, s.protocolLabel),
          _kv(context, l.srvInfoParamTransport, s.network),
          if ((s.sni ?? '').isNotEmpty) _kv(context, 'SNI', s.sni!),
          if ((s.fingerprint ?? '').isNotEmpty)
            _kv(context, l.srvInfoParamTlsFingerprint, s.fingerprint!),
          if (s.isPanelProfile)
            _kv(context, l.srvInfoParamType, l.srvInfoPanelAutoProfile),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                )),
      );

  Widget _ipCard(BuildContext context, String title, IpInfo? info,
      {bool primary = false}) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (primary ? scheme.primary : scheme.outline).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        if (info == null)
          Text(l.srvInfoCouldNotDetermine)
        else ...[
          Row(children: [
            Expanded(
              child: SelectableText(info.ip,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: l.srvInfoCopy,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: info.ip));
                AppToast.copied(context);
              },
            ),
          ]),
          Text(info.location,
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.bodySmall),
          if ((info.isp ?? '').isNotEmpty)
            Text(info.isp!,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }

  Widget _speedRow(BuildContext context, String title, SpeedResult? r,
      {bool primary = false}) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(title)),
        Text(
          r == null ? '—' : (r.ok ? speedResultLabel(l, r) : (r.error ?? '—')),
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
            color: r != null && !r.ok
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ),
      ]),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 140, child: Text(k, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: SelectableText(v, textDirection: TextDirection.ltr)),
        ]),
      );
}
