import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/settings/app_settings.dart';
import '../core/settings/split_tunnel.dart';
import '../core/platform/platform_services.dart';
import '../state/settings_controller.dart';
import 'widgets/app_icon.dart';
import 'widgets/route_diagram.dart';
import 'widgets/site_favicon.dart';
import 'widgets/info_tooltip.dart';
import 'widgets/sel_text.dart';
import 'widgets/app_toast.dart';
import '../core/i18n/enum_labels.dart';
import '../l10n/gen/app_localizations.dart';

class SplitTunnelScreen extends StatelessWidget {
  const SplitTunnelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final st = controller.settings.splitTunnel;
    // #2 — при системном прокси раздельное туннелирование не работает
    // (приложения сами решают, ходить ли через прокси): контролы серые.
    final tunActive = controller.settings.captureMode == CaptureMode.tun;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.splitTitle)),
      body: ListView(
        children: [
          if (!tunActive)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: SelText(l.splitTunOnlyBanner),
                ),
                TextButton(
                  onPressed: () => controller
                      .update((s) => s.copyWith(captureMode: CaptureMode.tun)),
                  child: Text(l.splitEnableTun),
                ),
              ]),
            ),
          // #2 — при системном прокси всё серое и неактивное.
          IgnorePointer(
            ignoring: !tunActive,
            child: Opacity(
              opacity: tunActive ? 1 : 0.45,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, l.splitModeHeader, l.infoSplitMode),
                  ...SplitMode.values.map((m) => RadioListTile<SplitMode>(
                        value: m,
                        groupValue: st.mode,
                        onChanged: (v) => controller.update((s) => s.copyWith(
                            splitTunnel: s.splitTunnel.copyWith(mode: v))),
                        title: Text(splitModeLabel(l, m)),
                      )),
                  // #14.2 — наглядно, как пойдёт трафик при текущем режиме.
                  RouteDiagram(split: st),
                  // «Все через VPN» — исключений нет, списки приложений/сайтов не
                  // показываем: и так понятно, что весь трафик идёт через VPN.
                  if (st.mode != SplitMode.all) ...[
                  const Divider(),
                  _header(context, l.splitAppsHeader, l.infoSplitApps),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SelText(
                      l.splitAppsHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  ...st.apps.map((rule) => Opacity(
                        opacity: rule.enabled ? 1 : 0.45,
                        child: ListTile(
                          key: ValueKey('app:${rule.path}'),
                          leading: Row(mainAxisSize: MainAxisSize.min, children: [
                            Checkbox(
                              value: rule.enabled,
                              onChanged: (v) => _updateApp(controller, rule,
                                  enabled: v ?? true),
                            ),
                            AppIcon(path: rule.path), // #1 — реальная иконка exe
                          ]),
                          title: Text(rule.name, textDirection: TextDirection.ltr),
                          subtitle: _ruleSubtitle(
                            context,
                            rule.enabled
                                ? '${rule.byName ? l.splitByName : l.splitByPath} · ${rule.path}'
                                : l.splitRuleDisabled,
                            action: rule.action,
                            allowRealIp: rule.allowRealIp,
                            noRealIp: rule.enabled && controller.settings.noRealIp,
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            _ActionChip(action: rule.action),
                            IconButton(
                              tooltip: l.splitRemove,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _removeApp(controller, rule),
                            ),
                          ]),
                          onTap: () => _appDialog(context, controller, rule),
                        ),
                      )),
                  OverflowBar(
                    alignment: MainAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.list),
                        // Формулировка зависит от платформы: на Windows каталог
                        // строится из ЗАПУЩЕННЫХ процессов, на Android система
                        // отдаёт список УСТАНОВЛЕННЫХ приложений. Назвать их
                        // «запущенными» значило бы обмануть — пользователь стал
                        // бы искать в списке то, что сейчас открыто.
                        label: Text(platform.appCatalog.supportsManualPick
                            ? l.splitFromRunning
                            : l.splitPickInstalled),
                        onPressed: () => _pickRunning(context, controller),
                      ),
                      // Выбор файла вручную осмыслен там, где правило адресует
                      // исполняемый файл (Windows). На Android правило — это
                      // packageName, и весь список даёт сама система.
                      if (platform.appCatalog.supportsManualPick)
                        TextButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: Text(l.splitPickExe),
                          onPressed: () => _pickExe(context, controller),
                        ),
                    ],
                  ),
                  const Divider(),
                  _header(context, l.splitSitesHeader, l.infoSplitDomains),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SelText(
                      l.splitSitesHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  ..._sortedSites(st.sites).map((e) => _siteTile(
                        context, controller, e.site, e.depth)),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _AddSiteField(controller: controller),
                  ),
                  ], // конец блока «списки при не-all режиме»
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String title, String info) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(children: [
          SelText(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )),
          InfoTooltip(info, title: title),
        ]),
      );

  void _addApp(SettingsController c, String path) {
    c.update((s) {
      if (s.splitTunnel.containsApp(path)) return s;
      // #3 — по умолчанию сопоставляем ПО ИМЕНИ: sing-box сравнивает process_path
      // побайтово (регистр/короткие пути Windows), из-за чего правило «по пути»
      // может молча не срабатывать. По имени — надёжно; меняется в диалоге.
      // Действие — «то, что выделено» текущим режимом (см. defaultAction).
      final rule = AppRule(path,
          byName: true, action: s.splitTunnel.defaultAction);
      return s.copyWith(
          splitTunnel: s.splitTunnel
              .copyWith(apps: [...s.splitTunnel.apps, rule]));
    });
  }

  void _removeApp(SettingsController c, AppRule rule) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            apps: s.splitTunnel.apps
                .where((a) => a.path != rule.path)
                .toList())));
  }

  void _updateApp(SettingsController c, AppRule rule,
      {AppAction? action, bool? byName, bool? enabled, bool? allowRealIp}) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            apps: s.splitTunnel.apps
                .map((a) => a.path == rule.path
                    ? a.copyWith(
                        action: action,
                        byName: byName,
                        enabled: enabled,
                        allowRealIp: allowRealIp)
                    : a)
                .toList())));
  }

  // ── Сайты ────────────────────────────────────────────────────────────────
  // Запись уникальна по паре (домен, порт): один домен может быть добавлен
  // и без порта, и с портом — это разные правила.
  static bool _sameSite(SiteRule a, SiteRule b) =>
      a.domain == b.domain && a.port == b.port;

  void _removeSite(SettingsController c, SiteRule site) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            sites: s.splitTunnel.sites
                .where((x) => !_sameSite(x, site))
                .toList())));
  }

  void _updateSite(SettingsController c, SiteRule site, AppAction action) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            sites: s.splitTunnel.sites
                .map((x) => _sameSite(x, site) ? x.copyWith(action: action) : x)
                .toList())));
  }

  void _setSitePort(SettingsController c, SiteRule site, int? port) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            sites: s.splitTunnel.sites
                // copyWith, а не новый SiteRule: пересборка теряла бы галочку
                // «разрешить реальный IP» при каждой правке порта.
                .map((x) => _sameSite(x, site)
                    ? x.copyWith(port: port, clearPort: port == null)
                    : x)
                .toList())));
  }

  void _setSiteAllowRealIp(SettingsController c, SiteRule site, bool value) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            sites: s.splitTunnel.sites
                .map((x) => _sameSite(x, site) ? x.copyWith(allowRealIp: value) : x)
                .toList())));
  }

  /// Упорядочивает сайты для показа деревом: группируем по «корневому» домену
  /// (`example.com`), внутри группы корень идёт первым, поддомены — под ним с
  /// отступом (глубина = число «лишних» уровней относительно корня).
  static List<({SiteRule site, int depth})> _sortedSites(List<SiteRule> sites) {
    final ordered = [...sites];
    ordered.sort((a, b) {
      final ba = baseDomain(a.domain), bb = baseDomain(b.domain);
      if (ba != bb) return ba.compareTo(bb);
      final la = a.domain.split('.').length, lb = b.domain.split('.').length;
      if (la != lb) return la.compareTo(lb); // корень (короче) — выше
      final d = a.domain.compareTo(b.domain);
      return d != 0 ? d : (a.port ?? 0).compareTo(b.port ?? 0);
    });
    return ordered.map((s) {
      final base = baseDomain(s.domain);
      final depth = s.domain == base
          ? 0
          : s.domain.split('.').length - base.split('.').length;
      return (site: s, depth: depth);
    }).toList();
  }

  Widget _siteTile(BuildContext context, SettingsController controller,
      SiteRule site, int depth) {
    final l = AppLocalizations.of(context);
    final indent = 16.0 + depth * 22.0;
    return ListTile(
      key: ValueKey('site:${site.domain}|${site.port ?? ''}'),
      contentPadding: EdgeInsetsDirectional.only(start: indent, end: 16),
      leading: Row(mainAxisSize: MainAxisSize.min, children: [
        if (depth > 0)
          Icon(Icons.subdirectory_arrow_right,
              size: 18, color: Theme.of(context).disabledColor),
        SiteFavicon(domain: site.domain),
      ]),
      title: Text(site.label, textDirection: TextDirection.ltr),
      subtitle: _ruleSubtitle(
          context,
          site.port != null ? l.splitOnlyPort(site.port!) : null,
          action: site.action,
          allowRealIp: site.allowRealIp,
          noRealIp: controller.settings.noRealIp),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _ActionChip(action: site.action),
        IconButton(
          tooltip: l.splitRemove,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _removeSite(controller, site),
        ),
      ]),
      onTap: () => _siteDialog(context, controller, site),
    );
  }

  /// Подпись правила. При включённом «Не выходить под реальным IP» правило
  /// «Прямо» обязано честно сообщать, куда оно на самом деле пойдёт: раньше чип
  /// показывал «Прямо», а трафик молча уходил в туннель.
  Widget? _ruleSubtitle(BuildContext context, String? base,
      {required AppAction action,
      required bool allowRealIp,
      required bool noRealIp}) {
    final l = AppLocalizations.of(context);
    // Длинный путь к exe обязан обрезаться, а не ломать вёрстку строки.
    Widget baseText() =>
        Text(base!, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (!noRealIp || action != AppAction.direct) {
      return base == null ? null : baseText();
    }
    final scheme = Theme.of(context).colorScheme;
    final warn = allowRealIp;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (base != null) ...[Flexible(child: baseText()), const SizedBox(width: 8)],
      Icon(warn ? Icons.warning_amber_rounded : Icons.shield_outlined,
          size: 14, color: warn ? Colors.orange : scheme.primary),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          warn ? l.splitRealIpExposed : l.splitRealIpProtected,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: warn ? Colors.orange : scheme.primary),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }

  /// Диалог настройки приложения: действие + способ сопоставления.
  Future<void> _appDialog(
      BuildContext context, SettingsController c, AppRule rule) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _RuleDialog(
        title: rule.name,
        copySource: rule.path,
        action: rule.action,
        byName: rule.byName,
        allowRealIp: c.settings.noRealIp ? rule.allowRealIp : null,
        onAction: (a) => _updateApp(c, rule, action: a),
        onByName: (b) => _updateApp(c, rule, byName: b),
        onAllowRealIp: (v) => _updateApp(c, rule, allowRealIp: v),
      ),
    );
  }

  /// Диалог настройки сайта: действие + необязательный порт.
  Future<void> _siteDialog(
      BuildContext context, SettingsController c, SiteRule site) async {
    // Порт правится «на месте»: находим актуальную запись после смены порта,
    // чтобы последующие изменения действия попадали в неё же.
    var current = site;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _RuleDialog(
        title: site.domain,
        copySource: site.label,
        action: site.action,
        initialPort: site.port,
        allowRealIp: c.settings.noRealIp ? site.allowRealIp : null,
        onAction: (a) => _updateSite(c, current, a),
        onAllowRealIp: (v) => _setSiteAllowRealIp(c, current, v),
        onPort: (p) {
          _setSitePort(c, current, p);
          current = current.copyWith(port: p, clearPort: p == null);
        },
      ),
    );
  }

  Future<void> _pickExe(BuildContext context, SettingsController c) async {
    final l = AppLocalizations.of(context);
    final group = XTypeGroup(label: l.splitProgramsFileType, extensions: const ['exe']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file != null) _addApp(c, file.path);
  }

  Future<void> _pickRunning(BuildContext context, SettingsController c) async {
    final all = await platform.appCatalog.list();
    final added = c.settings.splitTunnel;
    // #6.3 — исключаем уже добавленные
    final procs = all.where((p) => !added.containsApp(p.key)).toList();
    if (!context.mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => _RunningPickerDialog(procs: procs),
    );
    if (selected != null) _addApp(c, selected);
  }
}

/// Диалог выбора из запущенных с поиском (#6.1).
class _RunningPickerDialog extends StatefulWidget {
  final List<CatalogApp> procs;
  const _RunningPickerDialog({required this.procs});
  @override
  State<_RunningPickerDialog> createState() => _RunningPickerDialogState();
}

class _RunningPickerDialogState extends State<_RunningPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final filtered = _q.isEmpty
        ? widget.procs
        : widget.procs
            .where((p) => p.label.toLowerCase().contains(_q.toLowerCase()))
            .toList();
    return AlertDialog(
      // См. кнопку открытия: на Android это установленные приложения.
      title: Text(platform.appCatalog.supportsManualPick
          ? l.splitRunningApps
          : l.splitInstalledApps),
      content: SizedBox(
        width: 440,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.splitSearchByName,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(l.splitNothingFound))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        return ListTile(
                          dense: true,
                          leading: AppIcon(path: p.key), // #1 — реальная иконка
                          title: Text(p.label),
                          subtitle: Text(p.key,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(context).pop(p.key),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.splitClose)),
      ],
    );
  }
}

/// Метка действия приложения (Туннель / Прямо / Блок) — цвет + иконка + текст.
class _ActionChip extends StatelessWidget {
  final AppAction action;
  const _ActionChip({required this.action});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (action) {
      AppAction.tunnel => (Icons.vpn_lock, scheme.primary),
      AppAction.direct => (Icons.arrow_outward, Colors.blueGrey),
      AppAction.block => (Icons.block, scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(appActionLabel(l, action),
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Диалог настройки записи (приложения или сайта): действие + (для приложений)
/// способ сопоставления. Изменения применяются сразу через колбэки.
class _RuleDialog extends StatefulWidget {
  final String title;

  /// Что кладём в буфер: у приложения — полный путь, а не короткое имя из
  /// заголовка; у сайта — адрес с портом.
  final String? copySource;
  String get copyText => copySource ?? title;

  final AppAction action;
  final bool? byName; // null = запись без сопоставления (сайт)
  final ValueChanged<AppAction> onAction;
  final ValueChanged<bool>? onByName;
  final int? initialPort; // задан для сайтов (может быть null = любой порт)
  final ValueChanged<int?>? onPort; // задан для сайтов

  /// Галочка «разрешить реальный IP». null = не показывать (настройка
  /// «Не выходить под реальным IP» выключена — тогда «Прямо» и так прямое).
  final bool? allowRealIp;
  final ValueChanged<bool>? onAllowRealIp;

  const _RuleDialog({
    required this.title,
    required this.action,
    this.copySource,
    required this.onAction,
    this.byName,
    this.onByName,
    this.initialPort,
    this.onPort,
    this.allowRealIp,
    this.onAllowRealIp,
  });

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late AppAction _action = widget.action;
  late bool _byName = widget.byName ?? true;
  late bool _allowRealIp = widget.allowRealIp ?? true;
  late final TextEditingController _port =
      TextEditingController(text: widget.initialPort?.toString() ?? '');
  String? _portError;

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  void _applyPort() {
    final l = AppLocalizations.of(context);
    final raw = _port.text.trim();
    if (raw.isEmpty) {
      setState(() => _portError = null);
      widget.onPort?.call(null);
      return;
    }
    final p = int.tryParse(raw);
    if (p == null || p < 1 || p > 65535) {
      setState(() => _portError = l.splitPortRange);
      return;
    }
    setState(() => _portError = null);
    widget.onPort?.call(p);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      // Заголовок — сам адрес сайта (или имя exe): делаем его выделяемым и
      // даём кнопку копирования. Раньше адрес нельзя было ни выделить, ни
      // скопировать: нажатие по строке лишь открывало этот диалог.
      title: Row(children: [
        Expanded(
          child: SelText.technical(widget.title,
              maxLines: 1, style: Theme.of(context).textTheme.titleLarge),
        ),
        IconButton(
          tooltip: widget.onPort != null ? l.splitCopyDomain : l.splitCopyPath,
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.copyText));
            if (context.mounted) AppToast.copied(context);
          },
        ),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.splitAction),
          for (final a in AppAction.values)
            RadioListTile<AppAction>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: a,
              groupValue: _action,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _action = v);
                widget.onAction(v);
              },
              title: Text(appActionLabel(l, a)),
              secondary: _actionIcon(context, a),
            ),
          // Видно только у «Прямо» и только когда включено «Не выходить под
          // реальным IP»: в остальных случаях выбора нет — прямое правило и так
          // идёт мимо VPN.
          if (widget.allowRealIp != null && _action == AppAction.direct) ...[
            const Divider(),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _allowRealIp,
              onChanged: (v) {
                setState(() => _allowRealIp = v);
                widget.onAllowRealIp?.call(v);
              },
              title: Text(l.splitAllowRealIp),
              subtitle: Text(_allowRealIp
                  ? l.splitAllowRealIpOn
                  : l.splitAllowRealIpOff),
            ),
          ],
          if (widget.onPort != null) ...[
            const Divider(),
            Text(l.splitPortOptional),
            const SizedBox(height: 6),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: l.splitAnyPort,
                errorText: _portError,
                helperText: l.splitPortHelper,
              ),
              onChanged: (_) => _applyPort(),
            ),
          ],
          if (widget.byName != null) ...[
            const Divider(),
            Text(l.splitMatching),
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: true,
              groupValue: _byName,
              onChanged: (v) {
                setState(() => _byName = v!);
                widget.onByName?.call(v!);
              },
              title: Text(l.splitByName),
              subtitle: Text(l.splitByNameSubtitle),
            ),
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: false,
              groupValue: _byName,
              onChanged: (v) {
                setState(() => _byName = v!);
                widget.onByName?.call(v!);
              },
              title: Text(l.splitByPath),
              subtitle: Text(l.splitByPathSubtitle),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.splitDone)),
      ],
    );
  }

  Widget _actionIcon(BuildContext context, AppAction a) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (a) {
      AppAction.tunnel => (Icons.vpn_lock, scheme.primary),
      AppAction.direct => (Icons.arrow_outward, Colors.blueGrey),
      AppAction.block => (Icons.block, scheme.error),
    };
    return Icon(icon, color: color, size: 20);
  }
}

class _AddSiteField extends StatefulWidget {
  final SettingsController controller;
  const _AddSiteField({required this.controller});
  @override
  State<_AddSiteField> createState() => _AddSiteFieldState();
}

class _AddSiteFieldState extends State<_AddSiteField> {
  final _controller = TextEditingController();
  final _portController = TextEditingController();
  String? _error;

  void _add() {
    final l = AppLocalizations.of(context);
    // https://www.EXAMPLE.com:8443/lk → домен example.com, порт 8443.
    final domain = normalizeDomain(_controller.text);
    if (domain.isEmpty) {
      setState(() => _error = l.splitEnterDomain);
      return;
    }
    // Порт: приоритет у отдельного поля, иначе — из самой строки домена.
    int? port;
    final rawPort = _portController.text.trim();
    if (rawPort.isNotEmpty) {
      port = int.tryParse(rawPort);
      if (port == null || port < 1 || port > 65535) {
        setState(() => _error = l.splitPortRange);
        return;
      }
    } else {
      port = extractPort(_controller.text);
    }
    widget.controller.update((s) {
      if (s.splitTunnel.containsSite(domain, port: port)) return s;
      return s.copyWith(
          splitTunnel: s.splitTunnel.copyWith(
              sites: [...s.splitTunnel.sites,
                SiteRule(domain, port: port, action: s.splitTunnel.defaultAction)]));
    });
    _controller.clear();
    _portController.clear();
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        flex: 3,
        child: TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'youtube.com',
            labelText: l.splitAddSite,
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _error,
          ),
          onSubmitted: (_) => _add(),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 92,
        child: TextField(
          controller: _portController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: l.splitAnyPort,
            labelText: l.splitPort,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) => _add(),
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: FilledButton(onPressed: _add, child: Text(l.splitAdd)),
      ),
    ]);
  }
}
