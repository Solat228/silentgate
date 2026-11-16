import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/dpi/dpi_bypass_lists.dart';
import '../core/dpi/dpi_bypass_proxy.dart';
import '../core/dpi/dpi_probe_engine.dart';
import '../core/dpi/dpi_strategy.dart';
import '../core/dpi/physical_nic_socket_windows.dart';
import '../core/settings/app_settings.dart';
import '../core/settings/split_tunnel.dart';
import '../engine/windows/zapret_winws_runner.dart';
import '../state/settings_controller.dart';
import 'widgets/app_toast.dart';

/// Полноценный экран управления встроенным обходом DPI (`Zapret` / `ByeDPI`):
/// живая проверка потока `> 32 КБ`, автоподбор стратегий под провайдера/ТСПУ,
/// тонкие настройки десинхронизации и управление категориями/доменами.
class DpiBypassScreen extends StatefulWidget {
  const DpiBypassScreen({super.key});

  @override
  State<DpiBypassScreen> createState() => _DpiBypassScreenState();
}

class _DpiBypassScreenState extends State<DpiBypassScreen> {
  final TextEditingController _probeDomainCtrl = TextEditingController();
  final TextEditingController _addDomainCtrl = TextEditingController();

  bool _verifying = false;
  bool _autoTuning = false;
  bool _cancelTune = false;
  int _tuneStep = 0;
  int _tuneTotal = 0;
  DpiStrategyPreset? _currentTestingPreset;

  DpiStrategyReport? _lastReport;
  DpiAutoTuneSummary? _tuneSummary;

  PhysicalGatewayInfo? _gateway;
  String? _winwsPath;
  Timer? _statsRefreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshEnvInfo();
    _statsRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statsRefreshTimer?.cancel();
    _probeDomainCtrl.dispose();
    _addDomainCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshEnvInfo() async {
    if (Platform.isWindows) {
      final gw = PhysicalNicSocketManager.instance.currentGateway(
        forceRefresh: true,
      );
      final exe = await ZapretWinwsRunner.locateWinwsBinary();
      if (!mounted) return;
      setState(() {
        _gateway = gw;
        _winwsPath = exe?.path;
      });
    }
  }

  Future<void> _runVerify(AppSettings settings) async {
    if (_verifying || _autoTuning) return;
    setState(() {
      _verifying = true;
    });
    try {
      final cfg = DpiDesyncConfig.fromSettings(settings);
      final targets = DpiProbeEngine.buildTargets(
        customDomain: _probeDomainCtrl.text,
      );
      final report = await DpiProbeEngine.verifyStrategy(
        cfg,
        targets: targets,
      );
      if (!mounted) return;
      setState(() {
        _lastReport = report;
      });
    } finally {
      if (mounted) {
        setState(() {
          _verifying = false;
        });
      }
    }
  }

  Future<void> _runAutoTune(SettingsController controller) async {
    if (_verifying || _autoTuning) return;
    setState(() {
      _autoTuning = true;
      _cancelTune = false;
      _tuneStep = 0;
      _tuneTotal = DpiDesyncConfig.autoTuneOrder.length;
      _tuneSummary = null;
    });
    try {
      final targets = DpiProbeEngine.buildTargets(
        customDomain: _probeDomainCtrl.text,
      );
      final summary = await DpiProbeEngine.autoTune(
        targets: targets,
        isCancelled: () => _cancelTune,
        onProgress: (idx, total, preset, completed) {
          if (!mounted) return;
          setState(() {
            _tuneStep = idx;
            _tuneTotal = total;
            _currentTestingPreset = preset;
            if (completed != null) {
              _lastReport = completed;
            }
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _tuneSummary = summary;
        if (summary.best != null) {
          _lastReport = summary.best;
        }
      });
      final best = summary.best;
      if (best != null && !_cancelTune) {
        await controller.update(
          (s) => s.copyWith(dpiStrategy: best.strategy.preset),
        );
        DpiRuntimeRegistry.clearLearnedFallbacks();
        if (!mounted) return;
        AppToast.show(
          context,
          'Подобрана лучшая стратегия: ${best.strategy.titleRu} '
          '(${best.okCount}/${best.totalCount} напрямую)',
        );
      } else if (!_cancelTune && mounted) {
        AppToast.show(
          context,
          'Провайдер блокирует тестовые цели по IP — включите режим «Zapret → VPN»',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _autoTuning = false;
          _currentTestingPreset = null;
        });
      }
    }
  }

  void _addCustomDomain(SettingsController controller, AppSettings settings) {
    final raw = _addDomainCtrl.text.trim().toLowerCase();
    final d = normalizeDomain(raw);
    if (d.isEmpty || !d.contains('.') || d.contains(' ')) {
      AppToast.show(context, 'Введите корректный домен, например nnmclub.to');
      return;
    }
    if (settings.dpiCustomDomains.contains(d)) {
      _addDomainCtrl.clear();
      return;
    }
    controller.update(
      (s) => s.copyWith(dpiCustomDomains: [...s.dpiCustomDomains, d]),
    );
    _addDomainCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    final cs = Theme.of(context).colorScheme;
    final activeCfg = DpiDesyncConfig.fromSettings(s);
    final learned = DpiRuntimeRegistry.learnedFallbackHosts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zapret / Встроенный обход DPI'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // ── 1. Главный переключатель и живой статус ────────────────────
              Card(
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        key: const Key('dpiScreenEnabledSwitch'),
                        value: s.dpiBypassEnabled,
                        onChanged: (v) => controller.update(
                          (st) => st.copyWith(dpiBypassEnabled: v),
                        ),
                        title: const Text(
                          '⚡ Включить встроенный обход DPI (Zapret / ByeDPI)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Открывает YouTube, Discord и выбранные сайты с вашего домашнего IP '
                          'без расхода трафика VPN за счёт десинхронизации TLS ClientHello и MSG_OOB',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatusChip(
                              icon: Icons.tune,
                              label: 'Стратегия: ${activeCfg.titleRu}',
                              color: cs.primaryContainer,
                              onColor: cs.onPrimaryContainer,
                            ),
                            if (Platform.isWindows)
                              _StatusChip(
                                icon: Icons.settings_ethernet,
                                label: _gateway != null
                                    ? 'Физический адаптер: ${_gateway!.displayLabel}'
                                    : 'Адаптер: автовыбор ОС',
                                color: cs.secondaryContainer,
                                onColor: cs.onSecondaryContainer,
                              ),
                            _StatusChip(
                              icon: Icons.bolt,
                              label:
                                  'Прямых: ${DpiRuntimeRegistry.directSuccessCount} · В VPN: ${DpiRuntimeRegistry.fallbackCount}',
                              color: cs.surfaceContainerHighest,
                              onColor: cs.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                      if (learned.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Переведено в VPN в этой сессии (${learned.length}): '
                                  '${learned.take(5).join(", ")}${learned.length > 5 ? "…" : ""}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  DpiRuntimeRegistry.clearLearnedFallbacks();
                                  setState(() {});
                                  AppToast.show(
                                    context,
                                    'Кэш фоллбэков очищен — домены снова попробуют прямой Zapret',
                                  );
                                },
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Сбросить'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── 2. Живая проверка и автоподбор стратегии ──────────────────
              Card(
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.fact_check_outlined, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Проверка работы и автоподбор стратегии',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Проверяет реальное рукопожатие TLS 1.3 и скачивание потока > 32 КБ '
                        '(ловит блокировку ТСПУ на 16–20 КБ) напрямую через физический адаптер — '
                        'работает даже при включённом VPN.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _probeDomainCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          labelText: 'Дополнительный домен для теста (необязательно)',
                          hintText: 'например: nnmclub.to или 7tv.app',
                          prefixIcon: Icon(Icons.language, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.tonalIcon(
                            key: const Key('dpiVerifyButton'),
                            onPressed:
                                (_verifying || _autoTuning) ? null : () => _runVerify(s),
                            icon: _verifying
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(
                              _verifying
                                  ? 'Проверяю напрямую…'
                                  : 'Проверить текущую стратегию',
                            ),
                          ),
                          FilledButton.icon(
                            key: const Key('dpiAutoTuneButton'),
                            onPressed: (_verifying || _autoTuning)
                                ? null
                                : () => _runAutoTune(controller),
                            icon: _autoTuning
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.auto_fix_high),
                            label: Text(
                              _autoTuning
                                  ? 'Подбор ($_tuneStep/$_tuneTotal)…'
                                  : 'Автоподбор лучшей стратегии',
                            ),
                          ),
                          if (_autoTuning)
                            OutlinedButton.icon(
                              onPressed: () => setState(() => _cancelTune = true),
                              icon: const Icon(Icons.stop, size: 16),
                              label: const Text('Остановить'),
                            ),
                        ],
                      ),
                      if (_autoTuning) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _tuneTotal > 0 ? _tuneStep / _tuneTotal : null,
                        ),
                        if (_currentTestingPreset != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Тестируется: ${DpiDesyncConfig.presetTitleRu(_currentTestingPreset!)}…',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                      if (_lastReport != null) ...[
                        const Divider(height: 24),
                        Text(
                          'Результат: ${_lastReport!.strategy.titleRu} — '
                          'прошли напрямую ${_lastReport!.okCount} из ${_lastReport!.totalCount}',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        for (final r in _lastReport!.results)
                          _ProbeResultTile(result: r),
                      ],
                      if (_tuneSummary != null && _tuneSummary!.reports.isNotEmpty) ...[
                        const Divider(height: 24),
                        Text(
                          'Сравнение всех проверенных стратегий:',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        for (final rep in _tuneSummary!.reports)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              rep == _tuneSummary!.best
                                  ? Icons.emoji_events
                                  : Icons.check_circle_outline,
                              color: rep == _tuneSummary!.best
                                  ? Colors.amber
                                  : (rep.okCount > 0 ? Colors.green : cs.outline),
                            ),
                            title: Text(rep.strategy.titleRu),
                            subtitle: Text(
                              'Напрямую: ${rep.okCount}/${rep.totalCount}'
                              '${rep.freezeCount > 0 ? " · 16КБ ТСПУ: ${rep.freezeCount}" : ""}'
                              '${rep.okCount > 0 ? " · средн. ${rep.averageOkMs} мс" : ""}',
                            ),
                            trailing: s.dpiStrategy == rep.strategy.preset
                                ? const Chip(label: Text('Выбрана'))
                                : TextButton(
                                    onPressed: () {
                                      controller.update(
                                        (st) => st.copyWith(
                                          dpiStrategy: rep.strategy.preset,
                                        ),
                                      );
                                      DpiRuntimeRegistry.clearLearnedFallbacks();
                                    },
                                    child: const Text('Выбрать'),
                                  ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── 3. Выбор стратегии и тонкие параметры ──────────────────────
              Card(
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Стратегия десинхронизации DPI',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<DpiStrategyPreset>(
                        key: const Key('dpiStrategyDropdown'),
                        value: s.dpiStrategy,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Активный профиль Zapret / ByeDPI',
                        ),
                        items: [
                          for (final p in DpiStrategyPreset.values)
                            DropdownMenuItem(
                              value: p,
                              child: Text(
                                DpiDesyncConfig.presetTitleRu(p),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          controller.update((st) => st.copyWith(dpiStrategy: v));
                          DpiRuntimeRegistry.clearLearnedFallbacks();
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        activeCfg.subtitleRu,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (s.dpiStrategy == DpiStrategyPreset.custom) ...[
                        const Divider(height: 24),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: s.dpiUseOob,
                          onChanged: (v) =>
                              controller.update((st) => st.copyWith(dpiUseOob: v)),
                          title: const Text('Срочный байт TCP (MSG_OOB) внутри SNI'),
                          subtitle: const Text(
                            'Добавляет out-of-band байт 0x61 — ломает склейку SNI на ТСПУ, игнорируется сервером',
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: s.dpiTlsRecordSplit,
                          onChanged: (v) => controller.update(
                            (st) => st.copyWith(dpiTlsRecordSplit: v),
                          ),
                          title: const Text('Дробить на отдельные TLS-рекорды'),
                          subtitle: const Text(
                            'Выключено — сырая TCP-нарезка (raw multisplit)',
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: s.dpiHttpHostMixedCase,
                          onChanged: (v) => controller.update(
                            (st) => st.copyWith(dpiHttpHostMixedCase: v),
                          ),
                          title: const Text('Смешивать регистр HTTP Host (hOsT:)'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Позиция первого разреза: ${s.dpiFirstSplitPos.clamp(1, 16)} байт',
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Slider(
                                min: 1,
                                max: 16,
                                divisions: 15,
                                value: s.dpiFirstSplitPos.clamp(1, 16).toDouble(),
                                label: '${s.dpiFirstSplitPos.clamp(1, 16)}',
                                onChanged: (v) => controller.update(
                                  (st) => st.copyWith(dpiFirstSplitPos: v.round()),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── 4. Совместный режим с VPN и DNS ────────────────────────────
              Card(
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          'Совместная работа с VPN и защита DNS',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SwitchListTile(
                        value: s.dpiBypassAutoFallbackToVpn,
                        onChanged: (v) => controller.update(
                          (st) => st.copyWith(dpiBypassAutoFallbackToVpn: v),
                        ),
                        title: const Text('Совместный режим «Zapret → VPN»'),
                        subtitle: const Text(
                          'Сначала пробует прямой обход с домашнего IP; если домен заблокирован по IP '
                          'или заморожен ТСПУ на 16–20 КБ (например, Cloudflare у Discord), '
                          'мгновенно переводит его в активный VPN',
                        ),
                      ),
                      SwitchListTile(
                        value: s.dpiDnsViaVpn,
                        onChanged: (v) => controller.update(
                          (st) => st.copyWith(dpiDnsViaVpn: v),
                        ),
                        title: const Text('Резолвить DNS доменов Zapret через VPN'),
                        subtitle: const Text(
                          'Защищает от подмены DNS провайдером (рекомендуется). '
                          'Выключите, если хотите получать ближайшие российские кэш-серверы провайдера',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Таймаут прямого ответа до фоллбэка: '
                                '${s.dpiFallbackTimeoutMs.clamp(600, 5000)} мс',
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                min: 600,
                                max: 4000,
                                divisions: 17,
                                value: s.dpiFallbackTimeoutMs
                                    .clamp(600, 4000)
                                    .toDouble(),
                                onChanged: (v) => controller.update(
                                  (st) =>
                                      st.copyWith(dpiFallbackTimeoutMs: v.round()),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Порог детектора заморозки ТСПУ: '
                                '${s.dpiTspuThresholdKb.clamp(12, 64)} КБ',
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                min: 12,
                                max: 64,
                                divisions: 13,
                                value:
                                    s.dpiTspuThresholdKb.clamp(12, 64).toDouble(),
                                onChanged: (v) => controller.update(
                                  (st) =>
                                      st.copyWith(dpiTspuThresholdKb: v.round()),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (Platform.isWindows) ...[
                        const Divider(height: 12),
                        SwitchListTile(
                          value: s.dpiBypassDiscordUdpWinws,
                          onChanged: (v) => controller.update(
                            (st) => st.copyWith(dpiBypassDiscordUdpWinws: v),
                          ),
                          title: const Text(
                            'Discord UDP Voice и QUIC через внешний winws.exe (WinDivert)',
                          ),
                          subtitle: Text(
                            _winwsPath != null
                                ? 'Найден: $_winwsPath (все IP серверов VPN автоматически исключаются)'
                                : 'Необязательный модуль для голосовых каналов Discord мимо VPN '
                                    '(положите winws.exe в папку bin\\zapret\\winws.exe рядом с программой; '
                                    'TCP/HTTPS Zapret работает встроенно без него)',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── 5. Категории и пользовательские домены ─────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Списки и свои домены Zapret',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final count =
                                  await DpiBypassLists.refreshPublicLists();
                              if (!context.mounted) return;
                              setState(() {});
                              AppToast.show(
                                context,
                                count > 0
                                    ? 'Базы Flowseal обновлены ($count доменов)'
                                    : 'Не удалось скачать внешние базы — работают встроенные списки',
                              );
                            },
                            icon: const Icon(Icons.sync, size: 16),
                            label: const Text('Обновить Flowseal'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: s.dpiListsYoutube,
                        onChanged: (v) => controller.update(
                          (st) => st.copyWith(dpiListsYoutube: v ?? true),
                        ),
                        title: const Text('YouTube и Google Video'),
                        subtitle: const Text(
                          'youtube.com, googlevideo.com, ytimg.com, youtu.be, ggpht.com + list-google.txt',
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: s.dpiListsDiscord,
                        onChanged: (v) => controller.update(
                          (st) => st.copyWith(dpiListsDiscord: v ?? true),
                        ),
                        title: const Text('Discord (текст, картинки, шлюз)'),
                        subtitle: const Text(
                          'discord.com, discordapp.com, discordapp.net, discord.media, discordcdn.com',
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: s.dpiListsGeneral,
                        onChanged: (v) => controller.update(
                          (st) => st.copyWith(dpiListsGeneral: v ?? true),
                        ),
                        title: const Text('Общий список (RuTracker, 7TV, NTC и др.)'),
                        subtitle: const Text(
                          'rutracker.org, ntc.party, 7tv.app, betterttv.net + list-general.txt',
                        ),
                      ),
                      const Divider(height: 20),
                      Text(
                        'Свои домены для обхода через Zapret (${s.dpiCustomDomains.length}):',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _addDomainCtrl,
                              onSubmitted: (_) => _addCustomDomain(controller, s),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                hintText: 'Добавить домен (например: nnmclub.to)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            onPressed: () => _addCustomDomain(controller, s),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Добавить'),
                          ),
                        ],
                      ),
                      if (s.dpiCustomDomains.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final d in s.dpiCustomDomains)
                              InputChip(
                                label: Text(d),
                                onDeleted: () => controller.update(
                                  (st) => st.copyWith(
                                    dpiCustomDomains: st.dpiCustomDomains
                                        .where((x) => x != d)
                                        .toList(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color onColor;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: onColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: onColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProbeResultTile extends StatelessWidget {
  final DpiProbeTargetResult result;

  const _ProbeResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String badge) = switch (result.outcome) {
      DpiProbeOutcome.ok => (Icons.check_circle, Colors.green, 'Напрямую OK'),
      DpiProbeOutcome.tspuFreeze => (
          Icons.warning_amber_rounded,
          Colors.orange,
          'ТСПУ → VPN'
        ),
      DpiProbeOutcome.blocked => (Icons.cancel, Colors.redAccent, 'Блок'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.target.title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  result.detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
