import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/traffic_stats.dart';
import '../core/models/vpn_status.dart';
import '../core/platform/interference_scanner.dart';
import '../core/app_info.dart';
import '../core/platform/app_log.dart';
import '../core/platform/app_launcher.dart';
import '../core/update/app_update.dart';
import '../core/settings/app_settings.dart';
import '../core/util/country_flag.dart';
import '../core/util/server_search.dart';
import '../core/i18n/enum_labels.dart';
import '../core/i18n/text_direction.dart';
import '../l10n/gen/app_localizations.dart';
import 'widgets/info_tooltip.dart';
import '../state/app_state.dart';
import '../state/auto_config_controller.dart';
import '../state/probe_controller.dart';
import '../state/settings_controller.dart';
import 'auto_config_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';
import 'widgets/app_toast.dart';
import 'widgets/flag_cell.dart';
import 'widgets/server_search_field.dart';
import 'widgets/server_tile.dart';
import 'widgets/service_checks_row.dart';
import 'widgets/subscription_bar.dart';
import 'widgets/ping_chip.dart';
import 'servers_screen.dart';
import '../engine/probe_factory.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // #5 — проверка активных помех на старте (один раз).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final found = await InterferenceScanner.scan();
      if (found.isNotEmpty && mounted) {
        await scanInterferenceDialog(context);
      }
      await _checkAppUpdate();
    });
  }

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  /// Обновление приложения: только сообщаем и открываем страницу загрузки.
  /// Молча ничего не качаем и не запускаем — см. комментарий в [AppUpdate].
  Future<void> _checkAppUpdate() async {
    final settings = context.read<SettingsController>().settings;
    if (!settings.appUpdateCheck) return;
    final release = await AppUpdate.check(endpoint: settings.effectiveAppUpdateUrl);
    if (release == null || !release.isNewer || !mounted) return;
    AppLog.i('Доступна версия ${release.version} (у вас ${AppInfo.version})');
    final l = AppLocalizations.of(context);
    final notes = release.notes ?? '';
    AppToast.show(
      context,
      l.homeUpdateAvailable(release.version) +
          (notes.isEmpty ? '' : ' — $notes'),
      kind: ToastKind.info,
      actionLabel: (release.downloadUrl ?? '').isEmpty ? null : l.homeDownload,
      onAction: (release.downloadUrl ?? '').isEmpty
          ? null
          : () => UrlOpener.open(release.downloadUrl!),
    );
  }

  // Что уже показали, чтобы один и тот же тост не всплывал на каждой перерисовке.
  String? _shownError;
  DateTime? _shownSyncAt;
  String? _shownRestart;

  /// Временные сообщения — тостами поверх интерфейса (#2.2).
  void _showTransientMessages(
      BuildContext context, AppState state, AppSettings settings) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);

      // Распознанные ошибки переводятся по коду; динамические (текст
      // исключения от сети или ядра) показываются как есть.
      final code = state.errorCode;
      final err = code != null ? appErrorText(l, code) : state.error;
      if (err != null && err != _shownError) {
        _shownError = err;
        AppToast.show(context, err, kind: ToastKind.error);
        state.clearError();
        return;
      }
      if (err == null) _shownError = null;

      final sync = state.lastSync;
      if (sync != null && sync.at != _shownSyncAt) {
        _shownSyncAt = sync.at;
        // Состав изменений раскрывается по клику — с флагами стран.
        AppToast.show(
          context,
          l.homeSubscriptionUpdated(syncSummary(l, sync)),
          kind: sync.hasChanges ? ToastKind.success : ToastKind.info,
          details: [
            for (final name in sync.added)
              ToastDetail(FlagUtil.strip(name),
                  added: true, leading: FlagCell(name, width: 20, height: 14)),
            for (final name in sync.removed)
              ToastDetail(FlagUtil.strip(name),
                  added: false, leading: FlagCell(name, width: 20, height: 14)),
          ],
        );
        return;
      }

      // #13 — смена сервера/настройки при живом VPN применится только после
      // переподключения: предлагаем сделать это одной кнопкой.
      final restart = state.pendingRestart;
      if (restart != null && restart != _shownRestart) {
        _shownRestart = restart;
        AppToast.show(
          context,
          restart,
          kind: ToastKind.warning,
          actionLabel: l.homeReconnect,
          onAction: () => state.reconnect(settings),
        );
      }
      if (restart == null) _shownRestart = null;
    });
  }

  // Завершения, о которых уже отчитались (иначе итог всплывал бы каждую перерисовку).
  DateTime? _shownPingDone;
  DateTime? _shownAutoDone;
  DateTime? _shownTunDone;

  /// Ход пинга и автонастройки — карточками слева снизу: пока идёт, карточка
  /// висит и показывает прогресс; после завершения ещё 10 секунд показывает итог
  /// с убывающей полоской и уезжает вниз.
  void _showProgressToasts(BuildContext context) {
    final probe = context.watch<ProbeController>();
    final auto = context.watch<AutoConfigController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);

      if (probe.running) {
        _shownPingDone = null;
        final total = probe.total;
        AppToast.progress(
          context,
          id: 'ping',
          message: l.homePingProgress(probe.done, total),
          value: total > 0 ? probe.done / total : null,
        );
      } else if (probe.finishedAt != null &&
          probe.finishedAt != _shownPingDone &&
          probe.lastSummary != null) {
        _shownPingDone = probe.finishedAt;
        AppToast.progress(context,
            id: 'ping',
            message: probe.lastSummary!,
            finished: true,
            kind: ToastKind.success);
      }

      final p = auto.progress;
      if (auto.running) {
        _shownAutoDone = null;
        final total = p?.total ?? 0;
        AppToast.progress(
          context,
          id: 'autoconfig',
          message: p == null
              ? l.homeAutoConfigStarting
              : '${l.homeAutoConfigProgress(p.index + 1, total, p.candidateName)}'
                  ' · ${outboundVariantLabel(l, p.variant)}',
          value: total > 0 ? (p!.index + 1) / total : null,
        );
      } else if (auto.finishedAt != null &&
          auto.finishedAt != _shownAutoDone &&
          auto.lastSummary != null) {
        _shownAutoDone = auto.finishedAt;
        AppToast.progress(context,
            id: 'autoconfig',
            message: auto.lastSummary!,
            finished: true,
            kind: auto.found.isEmpty ? ToastKind.warning : ToastKind.success);
      }

      // #8 — перебор стека/MTU TUN: пока идёт — прогресс-тост, по завершении —
      // итог (успех/неудача), а не только строка статуса под кнопкой.
      final state = context.read<AppState>();
      if (state.tunAutotuning) {
        _shownTunDone = null;
        AppToast.progress(
          context,
          id: 'tun-autotune',
          message: state.tunAutotuneMessage ?? l.homeTunAutotuneProgress,
        );
      } else if (state.tunAutotuneFinishedAt != null &&
          state.tunAutotuneFinishedAt != _shownTunDone) {
        _shownTunDone = state.tunAutotuneFinishedAt;
        AppToast.progress(context,
            id: 'tun-autotune',
            message: state.tunAutotuneSucceeded
                ? l.homeTunAutotuneDone
                : l.homeTunAutotuneFailed,
            finished: true,
            kind: state.tunAutotuneSucceeded
                ? ToastKind.success
                : ToastKind.warning);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final status = state.status;
    final settings = context.watch<SettingsController>().settings;
    // #6 — пинг применяет сохранённую вариацию сервера (fragment/fingerprint),
    // иначе серверы, работающие только с обходом, показывают «n/a».
    final probe = context.read<ProbeController>();
    probe.variantFor = state.variantFor;
    // Там, где отдельный харнесс не поднять (Android — VpnService один),
    // проверить hysteria2 и профили «Авто» можно только по ЖИВОМУ каналу:
    // у них нет осмысленного TCP-адреса, а без второй фазы они оставались
    // непроверенными навсегда. Честно это работает ровно для подключённого
    // сервера — его и отдаём.
    probe.liveProxyPort =
        () => state.status.isConnected ? state.httpProxyPort : 0;
    probe.activeServerKey = () => state.selectedServer?.key;
    // #2.2 — всё временное показываем ПОВЕРХ интерфейса: раньше эти сообщения
    // жили в компоновке и сдвигали большую кнопку Connect.
    _showTransientMessages(context, state, settings);
    _showProgressToasts(context);

    // #1.2 — первый запуск: пока нет ни подписки, ни серверов, показываем экран
    // импорта целиком. Возвращаться некуда, поэтому и кнопки «назад» у него нет.
    if (!state.hasServers && state.subscriptionUrl == null) {
      return const ImportScreen(initialSetup: true);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('SilentGate'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add, size: 20),
            label: Text(l.homeImport),
            onPressed: () => _open(context, const ImportScreen()),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: l.homeSettings,
            icon: const Icon(Icons.settings),
            onPressed: () => _open(context, const SettingsScreen()),
          ),
        ],
      ),
      // Ход пинга/автонастройки показывается ТОЛЬКО карточкой слева снизу
      // (AppToast.progress). Верхней плашки больше нет: она двигала интерфейс.
      //
      // Компоновка выбирается по ШИРИНЕ, а не по платформе: узкое окно на
      // Windows получает ту же одноколоночную раскладку, что и телефон, и это
      // правильно — две панели по 380 px там просто не помещаются.
      body: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < _twoPaneMinWidth) {
            return _ConnectPane(
              status: status,
              settings: settings,
              onOpen: (w) => _open(context, w),
              compact: true,
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ConnectPane(
                  status: status,
                  settings: settings,
                  onOpen: (w) => _open(context, w),
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                  width: 380, child: _ServerPane(onOpen: (w) => _open(context, w))),
            ],
          );
        },
      ),
    );
  }
}

/// Ниже этой ширины список серверов уезжает на отдельный экран: панель в 380 px
/// плюс осмысленная колонка подключения рядом уже не помещаются.
const double _twoPaneMinWidth = 760;

class _ConnectPane extends StatelessWidget {
  final VpnStatus status;
  final AppSettings settings;
  final void Function(Widget screen) onOpen;

  /// Узкий экран: список серверов уехал на отдельный маршрут, поэтому здесь
  /// появляется строка выбранного сервера, а содержимое становится
  /// прокручиваемым — гарантии минимального размера окна на телефоне нет.
  final bool compact;

  const _ConnectPane({
    required this.status,
    required this.settings,
    required this.onOpen,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    return Column(
      children: [
        // Карточка подписки показывается целиком: место под неё даёт увеличенная
        // минимальная высота окна и компактная кнопка Connect (скролл тут мешал).
        const SubscriptionBar(),
        if (compact) _SelectedServerBar(onOpen: onOpen),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            // На широком окне раскладка держится распорками и не прокручивается
            // (минимальный размер окна это гарантирует). На узком гарантии нет:
            // при крупном системном шрифте, в ландшафте или в разделённом
            // экране жёсткая колонка даёт overflow, поэтому там — прокрутка.
            child: _MaybeScroll(
              enabled: compact,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  if (!compact) const Spacer(),
                _ConnectButton(
                    status: status, onTap: () => state.toggleConnection(settings)),
                const SizedBox(height: 16),
                Text(vpnStatusLabel(l, status.state),
                    style: Theme.of(context).textTheme.titleMedium),
                // #6 — живая проверка сервисов у кнопки: только при активном VPN,
                // запускается вручную (тап по сервису), идёт через это соединение.
                if (status.isConnected) ...[
                  const SizedBox(height: 12),
                  ServiceChecksRow(
                    httpPort: state.httpProxyPort,
                    epoch: state.selectedServer?.key ?? 'auto',
                  ),
                ],
                if (status.state == VpnConnectionState.error &&
                    status.message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(status.message!,
                        textAlign: TextAlign.center,
                        // Статус/ошибка: направление по содержимому — локализованный
                        // текст читается верно, вложенные технические фрагменты (имена
                        // exe/серверов) — по bidi.
                        textDirection: autoTextDirection(status.message),
                        style:
                            TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 20),
                if (state.hasServers)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.bolt),
                    label: Text(l.homeAutoBest),
                    onPressed: () => state
                        .connectAuto(context.read<SettingsController>().settings),
                  ),
                // Автонастройка целиком стоит на проброс-харнессе: она поднимает
                // рядом второй экземпляр ядра и гоняет через него пробы. На
                // Android этого нельзя — VpnService в приложении один, и
                // `createProbeHarness()` честно бросает UnsupportedError.
                // Кнопка при этом была на месте, и нажатие показывало сырое
                // «Ошибка: Unsupported operation…». Лучше не показывать вовсе,
                // чем обещать несуществующее.
                if (proxyProbeSupported) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(l.homeAutoConfig),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AutoConfigScreen())),
                  ),
                ],
                  if (!compact) const Spacer() else const SizedBox(height: 24),
                  // Всегда на месте: при отключённом VPN — нули (иначе блок появлялся
                  // рывком и двигал кнопки, а цифры не помещались).
                  _TrafficRow(
                    stats: status.isConnected ? state.stats : TrafficStats.zero,
                    sessionUp: state.sessionUplinkBytes,
                    sessionDown: state.sessionDownlinkBytes,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Оборачивает содержимое в прокрутку только когда это нужно.
///
/// На широком окне колонка держится `Spacer`-ами и обязана занимать всю высоту;
/// обернув её в скролл безусловно, мы сломали бы эту раскладку.
class _MaybeScroll extends StatelessWidget {
  final bool enabled;
  final Widget child;
  const _MaybeScroll({required this.enabled, required this.child});

  @override
  Widget build(BuildContext context) => enabled
      ? SingleChildScrollView(child: child)
      : child;
}

/// Строка выбранного сервера — вход в список на узком экране.
///
/// На широком окне список всегда виден справа, здесь его нет, и без этой
/// строки сменить сервер было бы негде.
class _SelectedServerBar extends StatelessWidget {
  final void Function(Widget screen) onOpen;
  const _SelectedServerBar({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final server = state.selectedServer;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onOpen(const ServersScreen()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              if (server != null)
                FlagCell(server.remark, auto: server.isPanelProfile, width: 28, height: 20)
              else
                const Icon(Icons.dns_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      server == null
                          ? l.homeServersCount(state.servers.length)
                          : FlagUtil.strip(server.displayName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Имя сервера — технический текст: в ar/fa не зеркалим.
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(l.homeServersCount(state.servers.length),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (server != null)
                PingChip(result: context.watch<ProbeController>().resultFor(server)),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ServerPane extends StatefulWidget {
  final void Function(Widget screen) onOpen;
  const _ServerPane({required this.onOpen});

  @override
  State<_ServerPane> createState() => _ServerPaneState();
}

class _ServerPaneState extends State<_ServerPane> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final probe = context.watch<ProbeController>();
    final settings = context.read<SettingsController>().settings;
    final servers = state.servers;
    // Индексы исходного списка: выбор сервера идёт по индексу в AppState.servers.
    final shown = ServerSearch.matchIndices(servers, _query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (servers.isEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _Onboarding(onOpen: widget.onOpen),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(children: [
              Expanded(
                child: Text(
                    _query.isEmpty
                        ? l.homeServersCount(servers.length)
                        : l.homeFoundCount(shown.length, servers.length),
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              TextButton.icon(
                icon: probe.running
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check, size: 18),
                // Пингуем то, что видно: при активном поиске — только найденное.
                label: Text(_query.isEmpty ? l.homePingServers : l.homePingFound),
                onPressed: probe.running || shown.isEmpty
                    ? null
                    : () => probe.pingAll(
                        [for (final i in shown) servers[i]], settings),
              ),
              // #4 — видимая «!»: понятно, что у пинга есть подсказка (что значат
              // цвета плашек). Текст выделяемый (см. InfoTooltip).
              InfoTooltip(l.pingLegendInfo, title: l.sectionPing),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            child: ServerSearchField(
              value: _query,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(child: Text(l.homeNothingFound))
                : ListView.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final idx = shown[i];
                      return ServerTile(
                        server: servers[idx],
                        selected: idx == state.selectedIndex,
                        onTap: () => state.selectServer(idx),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }
}

/// #8 — индикатор идущих проверок; тап → на соответствующий экран.
class _Onboarding extends StatelessWidget {
  final void Function(Widget screen) onOpen;
  const _Onboarding({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_download_outlined,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(l.homeOnboardingTitle, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(l.homeOnboardingSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l.homeImportSubscription),
              onPressed: () => onOpen(const ImportScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  final VpnStatus status;
  final VoidCallback onTap;
  const _ConnectButton({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = status.isConnected;
    final busy = status.isBusy;
    final color = connected ? scheme.primary : scheme.surfaceContainerHighest;

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 148,
        height: 148,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: connected
              ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: 4)]
              : null,
        ),
        child: Center(
          child: busy
              ? const CircularProgressIndicator()
              : Icon(Icons.power_settings_new,
                  size: 68, color: connected ? scheme.onPrimary : scheme.onSurface),
        ),
      ),
    );
  }
}

/// Трафик: скорость и объём текущего подключения + итог за сессию приложения.
/// Показывается ВСЕГДА (нулями при отключённом VPN), чтобы блок не появлялся
/// рывком и не сдвигал кнопки.
class _TrafficRow extends StatelessWidget {
  final TrafficStats stats;
  final int sessionUp;
  final int sessionDown;
  const _TrafficRow({
    required this.stats,
    required this.sessionUp,
    required this.sessionDown,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _metric(context, Icons.arrow_downward,
                TrafficStats.formatSpeed(stats.downlinkSpeed),
                TrafficStats.formatBytes(stats.downlinkBytes)),
            _metric(context, Icons.arrow_upward,
                TrafficStats.formatSpeed(stats.uplinkSpeed),
                TrafficStats.formatBytes(stats.uplinkBytes)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l.homeSessionTraffic(
            TrafficStats.formatBytes(sessionDown),
            TrafficStats.formatBytes(sessionUp),
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _metric(BuildContext context, IconData icon, String speed, String total) {
    return Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(speed,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.titleSmall),
      ]),
      Text(total,
          textDirection: TextDirection.ltr,
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

