import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/vpn_server.dart';
import '../core/probe/auto_config_engine.dart';
import '../core/settings/app_settings.dart';
import '../core/settings/split_tunnel.dart';
import '../core/util/country_flag.dart';
import '../core/i18n/enum_labels.dart';
import '../l10n/gen/app_localizations.dart';
import '../engine/probe_factory.dart';
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
    final servers = appState.servers;
    final hasServers = appState.hasServers;
    // Найденные закрепляются сверху списка — если включена соответствующая настройка.
    final autoPin = context.watch<SettingsController>().settings.autoPinFound;
    ctrl.onPinFound = autoPin ? appState.pinWithVariant : null;
    // #3.2 — измеренная задержка сразу подменяет пинг на главной.
    ctrl.onPingMeasured = context.read<ProbeController>().setResult;
    // Выбор живёт в контроллере и переживает уход с экрана; первый заход
    // отмечает все серверы. Уведомлять слушателей отсюда нельзя — идёт сборка.
    ctrl.ensureSelection(servers.map((s) => s.key));
    final selected =
        servers.where((s) => ctrl.selection.contains(s.key)).toList();
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
          // ⚠️ ОТКАЗ ПОКАЗЫВАЕМ СРАЗУ, А НЕ ПО ФАКТУ НАЖАТИЯ.
          //
          // На Android харнесс не умеет пропускать запросы через кандидата
          // (`ProbeHarnessAndroid.supportsProxyRequests == false`), поэтому
          // подбор не начнётся никогда. Раньше экран честно предлагал крутить
          // стратегию, бюджет и набор сервисов — и отказывал только когда
          // человек нажимал «Начать». Настроил, нажал, получил отказ: время
          // потрачено на решение, которое ничего не значило.
          if (!autoConfigSupported)
            MaterialBanner(
              content: Text(AutoConfigController.unsupportedMessage),
              leading: const Icon(Icons.info_outline),
              actions: const [SizedBox.shrink()],
            ),
          const _SettingsWarning(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (ctrl.running && ctrl.progress != null)
                  AutoConfigProgressView(progress: ctrl.progress!),
                // Настройки перебора при живом прогоне приглушены: менять их на
                // ходу нельзя — они запекаются в конфиг кандидата на старте.
                IgnorePointer(
                  ignoring: ctrl.running,
                  child: Opacity(
                    opacity: ctrl.running ? 0.45 : 1,
                    child: const _ConfigControls(),
                  ),
                ),
                const Divider(height: 32),
                // ⚠️ СПИСОК ВИДЕН ВСЕГДА, В ТОМ ЧИСЛЕ ВО ВРЕМЯ ПРОГОНА.
                //
                // Раньше он стоял под гейтом `if (!ctrl.running)` и на время
                // подбора пропадал с экрана целиком. Владелец: «если выйти и
                // зайти заново — не показывает список серверов». Прогон идёт
                // минутами; человек возвращался на экран и видел пустоту вместо
                // своей подписки — то есть решал, что подписка потерялась.
                if (hasServers) const _ServerPicker() else const _KeyInput(),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ctrl.running) ...[
                  _RunTimer(ctrl: ctrl),
                  const SizedBox(height: 8),
                ],
                _BottomAction(
                    ctrl: ctrl, hasServers: hasServers, selected: selected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Плашка про настройки, влияющие на маршрутизацию.
///
/// ⚠️ ЗАЧЕМ ОНА ЗДЕСЬ. Экран автонастройки ничего не знал ни о VPN, ни о
/// галочках, а результаты подбора владелец сверяет с тем, как ведёт себя
/// браузер. Когда «Не выходить под реальным IP» переписывает «Прямо» в «через
/// VPN», картинка на экране и картинка в жизни расходятся — и объяснения этому
/// в приложении не было нигде.
///
/// ⚠️ ТЕКСТ ОБЯЗАН ГОВОРИТЬ ПРАВДУ. Пробы идут мимо VPN-выхода при любых
/// настройках, но в режиме TUN они всё равно проходят через процесс ядра:
/// зависшее ядро сделает ВСЕ результаты ложно-отрицательными. Бодрое «всё идёт
/// мимо VPN, не волнуйтесь» было бы враньём ровно в том случае, когда человек
/// пришёл разбираться, почему подбор ничего не находит.
class _SettingsWarning extends StatelessWidget {
  const _SettingsWarning();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Порядок — по важности: первым идёт то, что вообще умеет переписывать
    // пользовательское «Прямо» в «через VPN».
    final items = <_WarnItem>[
      if (s.noRealIp)
        _WarnItem(
          id: 'noRealIp',
          text: l.autoWarnNoRealIp,
          off: () => controller.update((st) => st.copyWith(noRealIp: false)),
        ),
      if (s.splitTunnel.mode == SplitMode.all)
        _WarnItem(
          id: 'allVpn',
          text: l.autoWarnAllVpn,
          // ⚠️ Уходим в `exceptSelected`, а не в `onlySelected`: трафик по
          // умолчанию остаётся в туннеле (как и был), но пользовательские
          // правила начинают действовать. `onlySelected` выкинул бы наружу всё,
          // что человек не отметил, — это не «отключить галочку», а другой
          // способ пользоваться VPN.
          off: () => controller.update((st) => st.copyWith(
              splitTunnel:
                  st.splitTunnel.copyWith(mode: SplitMode.exceptSelected))),
        ),
      if (s.myRulesOverridePanel)
        _WarnItem(
          id: 'panelOverride',
          text: l.autoWarnPanelOverride,
          off: () => controller
              .update((st) => st.copyWith(myRulesOverridePanel: false)),
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Row(key: Key('autoWarn-${item.id}'), children: [
              const Icon(Icons.shield_outlined, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(item.text,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              TextButton(
                key: Key('autoWarnOff-${item.id}'),
                onPressed: item.off,
                child: Text(l.autoWarnTurnOff),
              ),
            ]),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l.autoWarnProbesDirect,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _WarnItem {
  const _WarnItem({required this.id, required this.text, required this.off});
  final String id;
  final String text;
  final VoidCallback off;
}

/// «Прошло M:SS · осталось примерно M:SS».
///
/// ⚠️ ОТДЕЛЬНЫЙ ВИДЖЕТ СО СВОИМ ТАЙМЕРОМ — И ЭТО НЕ УКРАШАТЕЛЬСТВО. Тикая раз в
/// секунду через общий контроллер, мы перерисовывали бы весь экран вместе со
/// списком серверов и всеми найденными карточками. Здесь `setState` помечает
/// грязным ровно одну строку.
class _RunTimer extends StatefulWidget {
  const _RunTimer({required this.ctrl});
  final AutoConfigController ctrl;

  @override
  State<_RunTimer> createState() => _RunTimerState();
}

class _RunTimerState extends State<_RunTimer> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// M:SS. Часы не показываем: прогон таких размеров не бывает, а «0:00:42»
  /// читается хуже, чем «0:42».
  static String fmt(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final elapsed = widget.ctrl.elapsed();
    if (elapsed == null) return const SizedBox.shrink();
    final left = widget.ctrl.remainingEstimate();
    return Text(
      left == null
          ? l.autoTimerNoEstimate(fmt(elapsed))
          : l.autoTimer(fmt(elapsed), fmt(left)),
      style: Theme.of(context).textTheme.bodySmall,
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
              avatar: SiteFavicon(domain: service.domain, size: 18, builtIn: true),
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
          value: s.speedInAutoSelect,
          onChanged: (v) =>
              controller.update((st) => st.copyWith(speedInAutoSelect: v)),
          title: Row(children: [
            Expanded(child: Text(l.autoUseSpeed)),
            InfoTooltip(l.infoAutoUseSpeed),
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
    final running = context.watch<AutoConfigController>().running;
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
        // Кнопка живёт рядом с полем — иначе она относилась бы к пустому вводу.
        // Пока идёт прогон, её нет: остановка — единственное действие, и она в
        // нижней панели.
        if (!running)
          FilledButton.icon(
            key: const Key('autoAction'),
            icon: const Icon(Icons.auto_fix_high),
            label: Text(l.autoTuneByKey),
            onPressed: () {
              final settings = context.read<SettingsController>().settings;
              context
                  .read<AutoConfigController>()
                  .startForKey(_controller.text, settings);
            },
          ),
      ],
    );
  }
}

/// Ход текущего прогона.
///
/// Публичный намеренно: страж `test/auto_config_ui_test.dart` рисует его с
/// фазой замера скорости напрямую. Иначе проверить, что эта фаза больше не
/// притворяется перебором кандидатов, можно было бы только живым прогоном с
/// сетью — то есть никак.
class AutoConfigProgressView extends StatelessWidget {
  final AutoConfigProgress progress;
  const AutoConfigProgressView({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Фаза замера скорости рассказывает о себе САМА. Пока она этого не делала,
    // прогресс замирал на последнем кандидате перебора и десятки секунд
    // показывал «Тестируется 97/97: …», хотя перебор давно кончился.
    final speed = progress.phase == AutoConfigPhase.speed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: progress.total > 0 ? (progress.index + 1) / progress.total : null,
        ),
        const SizedBox(height: 12),
        if (speed)
          Text(
            // Пустое имя — замер СВОЕГО канала: он идёт мимо VPN и ни к какому
            // серверу не относится.
            progress.candidateName.isEmpty
                ? l.autoSpeedOwn
                : l.autoSpeedRanking(FlagUtil.strip(progress.candidateName)),
          )
        else ...[
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
          Text(l.autoVariant(outboundVariantLabel(l, progress.variant)),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: progress.services.entries
                .map((e) => Chip(avatar: _stateIcon(e.value), label: Text(e.key.label)))
                .toList(),
          ),
        ],
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

/// Плашка со скоростью — рядом с пингом.
///
/// Показывает и абсолютную величину, и долю СВОЕГО канала: «60 Мбит/с» само по
/// себе ничего не значит — это отлично на канале 60 и скверно на канале 300.
/// Долю считаем от замера собственного канала, снятого в том же прогоне.
class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.mbps, this.sharePercent});

  final double mbps;
  final int? sharePercent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Цвет — по доле канала, а не по абсолютной скорости: узкое место важнее
    // мегабит. Доли нет (свой канал не замерился) — нейтральный вид.
    final share = sharePercent;
    final color = share == null
        ? scheme.outline
        : share >= 80
            ? Colors.green
            : share >= 40
                ? Colors.orange
                : const Color(0xFFCC7777);
    return Tooltip(
      message: share == null
          ? l.autoSpeedValue(mbps.toStringAsFixed(1))
          : '${l.autoSpeedValue(mbps.toStringAsFixed(1))} · '
              '${l.autoSpeedShare(share)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          l.autoSpeedValue(mbps.toStringAsFixed(mbps >= 100 ? 0 : 1)),
          textDirection: TextDirection.ltr,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
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
                  '${outboundVariantLabel(l, result.variant)} · ${l.autoServicesPassed(okCount, d.passed.length)}',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Замеренная скорость — рядом с пингом, иначе включённая галочка
          // «Учитывать скорость» тратит трафик подписки, меняет порядок списка,
          // а показать результат замера негде: пользователь видит только новый
          // порядок и не понимает, откуда он взялся.
          if (result.mbps != null) ...[
            _SpeedChip(mbps: result.mbps!, sharePercent: result.sharePercent),
            const SizedBox(width: 4),
          ],
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

/// ЕДИНСТВЕННАЯ кнопка действия на экране.
///
/// ⚠️ БЫЛО ДВЕ, И ВЕРХНЯЯ МОЛЧА УНИЧТОЖАЛА ДАННЫЕ НИЖНЕЙ. «Подобрать для
/// выбранных» жила посреди прокручиваемого списка, «Готово — обновить пинг
/// найденных» — внизу; запуск первой делал `_found.clear()`, то есть стирал
/// ровно то, на чём держалась вторая. Владелец: «нахуя в автонастройке 2
/// кнопки? сделай 1».
class _BottomAction extends StatelessWidget {
  final AutoConfigController ctrl;
  final bool hasServers;
  final List<VpnServer> selected;
  const _BottomAction(
      {required this.ctrl, required this.hasServers, required this.selected});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (ctrl.running) {
      return OutlinedButton.icon(
        key: const Key('autoAction'),
        icon: const Icon(Icons.stop),
        label: Text(l.autoStopSearch),
        onPressed: ctrl.cancel,
      );
    }
    // Подписки нет — запуск идёт от поля ввода ключа (`_KeyInput`), там же и
    // единственная кнопка. Дублировать её здесь значило бы вернуть ту же пару.
    if (!hasServers) return const SizedBox.shrink();
    return FilledButton.icon(
      key: const Key('autoAction'),
      icon: const Icon(Icons.play_arrow),
      label: Text('${l.autoTuneSelected} (${selected.length})'),
      onPressed: selected.isEmpty ? null : () => _startWithConsent(context),
    );
  }

  /// Спросить про расход трафика ПЕРЕД прогоном — и только если он вправду будет.
  ///
  /// ⚠️ ЗАЧЕМ СПРАШИВАТЬ, ЕСЛИ ГАЛОЧКА УЖЕ ВКЛЮЧЕНА. Замер скорости включают
  /// один раз в настройках, а прогон запускают потом — днями позже и не всегда
  /// тот же человек, который включал. Платит при этом ПОДПИСКА: по
  /// [SpeedTestSize] на каждый из [AppSettings.speedTopN] серверов плюс столько
  /// же на собственный канал. При умолчании это 55 МБ за нажатие, и узнавать о
  /// них постфактум — по счётчику остатка — худший из возможных способов.
  ///
  /// ⚠️ Число берётся ТОЛЬКО из [AppSettings.speedTestTrafficMb]: оно считается
  /// в одном месте нарочно, потому что показывается в трёх (галочка, подсказка,
  /// это окно). Разъехавшиеся цифры в предупреждении о расходе — худший вид
  /// неправды: после него человек перестаёт верить всем трём.
  Future<void> _startWithConsent(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final settings = context.read<SettingsController>().settings;
    if (settings.speedInAutoSelect) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l.autoSpeedTrafficTitle),
          // Порядок аргументов задан порядком плейсхолдеров в самой строке
          // ({servers} раньше {mb}) — так его объявляет ARB и так генерирует
          // gen_l10n. Страж l10n_test сверяет одно с другим.
          content: Text(l.autoSpeedTrafficBody(
              settings.effectiveSpeedTopN, settings.speedTestTrafficMb)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false), child: Text(l.commonCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(l.autoSpeedTrafficGo)),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    await ctrl.start(selected, settings);
  }
}

/// #8.1 — какие серверы участвуют в подборе (чекбоксы + выбрать/снять все).
///
/// ⚠️ БЕЗ СВОЕГО `State`: выбор хранит контроллер. Прежний `_BatchTuneState`
/// держал галочки у себя и заполнял их «всеми» при каждом построении экрана —
/// то есть выбор существовал ровно до первого ухода с экрана.
class _ServerPicker extends StatelessWidget {
  const _ServerPicker();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final ctrl = context.watch<AutoConfigController>();
    final servers = state.servers;
    final sel = ctrl.selection;
    final running = ctrl.running;
    // Уже найденные связки — чтобы отметить их прямо в списке перебора.
    final found = ctrl.found;
    // Подсвечиваем ВСЕХ, кто проверяется прямо сейчас: при
    // `autoConfigConcurrency > 1` их несколько, и один «текущий» был бы враньём.
    // Запасной вариант — ключ из прогресса: он есть и когда множество пусто
    // (например, в самом начале фазы).
    final activeKeys = ctrl.activeKeys;
    final currentKey = ctrl.progress?.candidateKey;
    final scheme = Theme.of(context).colorScheme;
    final selectedCount = servers.where((s) => sel.contains(s.key)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(l.autoServersForTuning(selectedCount, servers.length),
                style: Theme.of(context).textTheme.titleSmall),
          ),
          TextButton(
            onPressed: running
                ? null
                : () => ctrl.selectAll(servers.map((s) => s.key)),
            child: Text(l.autoSelectAll),
          ),
          TextButton(
            onPressed: running ? null : ctrl.clearSelection,
            child: Text(l.autoDeselectAll),
          ),
        ]),
        const SizedBox(height: 8),
        // #5.1 — сервер, уже прошедший подбор, показывается результатом прямо здесь,
        // а не только отдельной карточкой ниже: иначе один сервер виден дважды.
        ...servers.map((s) {
          final name = FlagUtil.strip(s.remark);
          final hit = found.where((r) => r.server.key == s.key).firstOrNull;
          final current = running &&
              (activeKeys.contains(s.key) ||
                  (activeKeys.isEmpty && currentKey == s.key));
          return CheckboxListTile(
            key: Key('autoSrv-${s.key}'),
            dense: true,
            // Текущий кандидат подсвечен: во время прогона список остаётся на
            // экране, и без подсветки непонятно, где сейчас идёт проверка.
            tileColor:
                current ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
            value: sel.contains(s.key),
            // Во время прогона состав менять нельзя: список кандидатов уже
            // построен движком, и галочка ни на что не повлияла бы — то есть
            // была бы контролом-обманкой.
            onChanged: running
                ? null
                : (v) => ctrl.setSelected(s.key, v == true),
            secondary: FlagCell(s.remark, width: 26, height: 18),
            title: Row(children: [
              Expanded(child: Text(name.isEmpty ? s.address : name,
                  textDirection: TextDirection.ltr)),
              if (hit != null) ...[
                Icon(Icons.check_circle, size: 16, color: scheme.primary),
                const SizedBox(width: 4),
                PingChip(
                    result: context.watch<ProbeController>().resultFor(s)),
              ],
            ]),
            subtitle: Text(hit != null
                ? l.autoTuned(outboundVariantLabel(l, hit.variant))
                : configTagLabels(l, s.configTags).join(' / ')),
          );
        }),
      ],
    );
  }
}
