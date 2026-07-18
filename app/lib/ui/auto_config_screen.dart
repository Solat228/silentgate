import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/probe/auto_config_engine.dart';
import '../core/settings/app_settings.dart';
import '../core/util/country_flag.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/app_state.dart';
import '../state/auto_config_controller.dart';
import '../state/probe_controller.dart';
import '../state/settings_controller.dart';
import 'widgets/flag_cell.dart';
import 'widgets/info_tooltip.dart';
import 'widgets/ping_chip.dart';
import 'widgets/site_favicon.dart';

class AutoConfigScreen extends StatelessWidget {
  const AutoConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AutoConfigController>();
    final appState = context.watch<AppState>();
    final hasServers = appState.hasServers;
    // Найденные закрепляются сверху списка — если включена соответствующая настройка.
    final autoPin = context.watch<SettingsController>().settings.autoPinFound;
    ctrl.onPinFound = autoPin ? appState.pinWithVariant : null;
    // #3.2 — измеренная задержка сразу подменяет пинг на главной.
    ctrl.onPingMeasured = context.read<ProbeController>().setResult;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.autoTitle),
        actions: [
          if (ctrl.found.isNotEmpty && !ctrl.running)
            IconButton(
              tooltip: l.autoClearResults,
              icon: const Icon(Icons.delete_outline),
              onPressed: ctrl.clear,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!ctrl.running) ...[
                  const _ConfigControls(),
                  const Divider(height: 32),
                  if (hasServers) const _BatchTune() else const _KeyInput(),
                ],
                if (ctrl.running && ctrl.progress != null)
                  _ProgressView(progress: ctrl.progress!),
                if (ctrl.error != null && ctrl.found.isEmpty && !ctrl.running)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(ctrl.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                if (ctrl.found.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${l.autoFoundWorking(ctrl.found.length)}'
                      '${autoPin ? l.autoPinnedTop : ''}'
                      '${ctrl.running ? l.autoSearchContinues : ''}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  ...ctrl.found.map((r) => _FoundCard(result: r)),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _BottomAction(ctrl: ctrl, hasServers: hasServers),
          ),
        ],
      ),
    );
  }
}

/// Настройки перебора (сервисы + fragment) — перенесены сюда из общих настроек (#1.1).
class _ConfigControls extends StatelessWidget {
  const _ConfigControls();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(l.autoCheckServices,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              InfoTooltip(l.infoAutoConfigServices),
            ]),
          ),
          // #6.3 — выбрать/снять все сервисы.
          TextButton(
            onPressed: () => controller.update((st) =>
                st.copyWith(autoConfigServices: ProbeService.values.toSet())),
            child: Text(l.autoSelectAll),
          ),
          TextButton(
            onPressed: () => controller.update(
                (st) => st.copyWith(autoConfigServices: const {})),
            child: Text(l.autoDeselectAll),
          ),
        ]),
        Wrap(
          spacing: 8,
          children: ProbeService.values.map((service) {
            final on = s.autoConfigServices.contains(service);
            return FilterChip(
              // #6.3.1 — бренд-иконка сервиса.
              avatar: SiteFavicon(domain: service.domain, size: 18),
              label: Text(service.label),
              selected: on,
              onSelected: (v) => controller.update((st) {
                final set = {...st.autoConfigServices};
                v ? set.add(service) : set.remove(service);
                return st.copyWith(autoConfigServices: set);
              }),
            );
          }).toList(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.autoPinFound,
          onChanged: (v) =>
              controller.update((st) => st.copyWith(autoPinFound: v)),
          title: Row(children: [
            Expanded(child: Text(l.autoPinFoundOnTop)),
            InfoTooltip(l.infoAutoPinFound),
          ]),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.tryFragment,
          onChanged: (v) => controller.update((st) => st.copyWith(tryFragment: v)),
          title: Row(children: [
            Expanded(child: Text(l.autoTryFragment)),
            InfoTooltip(l.infoTryFragment),
          ]),
        ),
      ],
    );
  }
}

/// Поле для одиночного ключа, когда подписки нет (#1.2).
class _KeyInput extends StatefulWidget {
  const _KeyInput();
  @override
  State<_KeyInput> createState() => _KeyInputState();
}

class _KeyInputState extends State<_KeyInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.autoNoSubscriptionPasteKey),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'vless://…',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.auto_fix_high),
          label: Text(l.autoTuneByKey),
          onPressed: () {
            final settings = context.read<SettingsController>().settings;
            context.read<AutoConfigController>().startForKey(_controller.text, settings);
          },
        ),
      ],
    );
  }
}

class _ProgressView extends StatelessWidget {
  final AutoConfigProgress progress;
  const _ProgressView({required this.progress});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: progress.total > 0 ? (progress.index + 1) / progress.total : null,
        ),
        const SizedBox(height: 12),
        // #1 — флаг картинкой: эмодзи-флаги на Windows не рендерятся.
        Row(children: [
          Text(l.autoTesting(progress.index + 1, progress.total)),
          FlagCell(progress.candidateName, width: 26, height: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(FlagUtil.strip(progress.candidateName),
                textDirection: TextDirection.ltr,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        Text(l.autoVariant(progress.variantLabel),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: progress.services.entries
              .map((e) => Chip(avatar: _stateIcon(e.value), label: Text(e.key.label)))
              .toList(),
        ),
        const Divider(height: 32),
      ],
    );
  }

  Widget _stateIcon(ProbeState state) {
    switch (state) {
      case ProbeState.pending:
        return const Icon(Icons.radio_button_unchecked, size: 16, color: Colors.grey);
      case ProbeState.testing:
        return const SizedBox(
            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2));
      case ProbeState.ok:
        return const Icon(Icons.check_circle, size: 16, color: Colors.green);
      case ProbeState.fail:
        return const Icon(Icons.cancel, size: 16, color: Colors.red);
    }
  }
}

class _FoundCard extends StatelessWidget {
  final AutoConfigResult result;
  const _FoundCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = result.detail;
    // Компактная строка: флаг, имя, вариация, пройденные сервисы, пинг и кнопка —
    // всё в одну строку, чтобы список найденных не занимал по экрану на сервер.
    final okCount = d.passed.values.where((v) => v).length;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(children: [
          FlagCell(result.server.remark, width: 24, height: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(FlagUtil.strip(result.server.displayName),
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${result.variant.label} · ${l.autoServicesPassed(okCount, d.passed.length)}',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PingChip(result: context.watch<ProbeController>().resultFor(result.server)),
          const SizedBox(width: 4),
          IconButton(
            tooltip: l.autoConnect,
            icon: const Icon(Icons.power_settings_new, size: 20),
            onPressed: () {
              final state = context.read<AppState>();
              state.applyAutoConfigResult(result.server, result.variant);
              state.toggleConnection(
                  context.read<SettingsController>().settings);
              Navigator.of(context).pop();
            },
          ),
        ]),
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  final AutoConfigController ctrl;
  final bool hasServers;
  const _BottomAction({required this.ctrl, required this.hasServers});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (ctrl.running) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.stop),
        label: Text(l.autoStopSearch),
        onPressed: ctrl.cancel,
      );
    }
    // #1 — по завершении: вернуться на главный, обновить пинг найденных, сообщить.
    if (ctrl.found.isNotEmpty) {
      return FilledButton.icon(
        icon: const Icon(Icons.check),
        label: Text(l.autoDoneRefreshPing),
        onPressed: () {
          final state = context.read<AppState>();
          final probe = context.read<ProbeController>();
          final settings = context.read<SettingsController>().settings;
          final messenger = ScaffoldMessenger.of(context);
          final found = [
            for (final r in ctrl.found)
              state.servers.firstWhere((s) => s.key == r.server.key,
                  orElse: () => r.server),
          ];
          Navigator.of(context).pop();
          messenger.showSnackBar(SnackBar(
            content: Text(l.autoFoundPinnedRefreshing(found.length)),
          ));
          probe.pingAll(found, settings);
        },
      );
    }
    // Запуск — в блоке выбора серверов (_BatchTune) или по ключу (_KeyInput).
    return const SizedBox.shrink();
  }
}

/// #8.1 — пакетный подбор по выбранным серверам (чекбоксы + выбрать/снять все).
class _BatchTune extends StatefulWidget {
  const _BatchTune();
  @override
  State<_BatchTune> createState() => _BatchTuneState();
}

class _BatchTuneState extends State<_BatchTune> {
  final Set<String> _sel = {};
  bool _init = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final servers = state.servers;
    // Уже найденные связки — чтобы отметить их прямо в списке перебора.
    final found_ = context.watch<AutoConfigController>().found;
    if (!_init) {
      _sel.addAll(servers.map((s) => s.key));
      _init = true;
    }
    final selected = servers.where((s) => _sel.contains(s.key)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(l.autoServersForTuning(selected.length, servers.length),
                style: Theme.of(context).textTheme.titleSmall),
          ),
          TextButton(
            onPressed: () => setState(
                () => _sel..clear()..addAll(servers.map((s) => s.key))),
            child: Text(l.autoSelectAll),
          ),
          TextButton(
            onPressed: () => setState(() => _sel.clear()),
            child: Text(l.autoDeselectAll),
          ),
        ]),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: Text(l.autoTuneSelected),
          onPressed: selected.isEmpty
              ? null
              : () => context.read<AutoConfigController>().start(
                  selected, context.read<SettingsController>().settings),
        ),
        const SizedBox(height: 8),
        // #5.1 — сервер, уже прошедший подбор, показывается результатом прямо здесь,
        // а не только отдельной карточкой ниже: иначе один сервер виден дважды.
        ...servers.map((s) {
          final name = FlagUtil.strip(s.remark);
          final found = found_.where((r) => r.server.key == s.key).firstOrNull;
          return CheckboxListTile(
            dense: true,
            value: _sel.contains(s.key),
            onChanged: (v) => setState(() {
              if (v == true) {
                _sel.add(s.key);
              } else {
                _sel.remove(s.key);
              }
            }),
            secondary: FlagCell(s.remark, width: 26, height: 18),
            title: Row(children: [
              Expanded(child: Text(name.isEmpty ? s.address : name,
                  textDirection: TextDirection.ltr)),
              if (found != null) ...[
                Icon(Icons.check_circle,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                PingChip(
                    result: context.watch<ProbeController>().resultFor(s)),
              ],
            ]),
            subtitle: Text(found != null
                ? l.autoTuned(found.variant.label)
                : s.configTags.join(' / ')),
          );
        }),
      ],
    );
  }
}
