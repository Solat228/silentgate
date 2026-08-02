import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'layout/adaptive.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/settings/app_settings.dart';
import '../core/platform/app_launcher.dart';
import '../core/net/block_page_server.dart';
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
                  // ⚠️ Пока «Не выходить под реальным IP» включено, часть
                  // правил «Прямо» работает не так, как написано в строке.
                  // Молчать об этом нельзя: человек видит «Прямо» и считает,
                  // что трафик идёт прямо.
                  if (controller.settings.noRealIp)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .tertiaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        const Icon(Icons.shield_outlined, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SelText(l.splitNoRealIpBanner,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ]),
                    ),
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
                          dense: context.sg.isCompact,
                          title: Text(rule.name,
                              textDirection: TextDirection.ltr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: _ruleSubtitle(
                            context,
                            rule.enabled
                                // На Android сопоставления «по имени/по пути»
                                // нет — там имя пакета, и подпись «По имени ·
                                // com.android.chrome» только путала.
                                ? (Platform.isAndroid || Platform.isIOS
                                    ? rule.path
                                    : '${rule.byName ? l.splitByName : l.splitByPath}'
                                        ' · ${rule.path}')
                                : l.splitRuleDisabled,
                            action: rule.action,
                            allowRealIp: rule.allowRealIp,
                            noRealIp: rule.enabled && controller.settings.noRealIp,
                          ),
                          // ⚠️ НА ТЕЛЕФОНЕ КНОПКИ УДАЛЕНИЯ ЗДЕСЬ НЕТ, И ЭТО НЕ ПОТЕРЯ.
                          //
                          // Считано на 360 dp: слева 104 dp занимают отступ,
                          // галочка и иконка, справа чип с кнопкой — ещё 120.
                          // Названию приложения оставалось около 120 dp, то
                          // есть примерно двенадцать символов. Удаление и так
                          // доступно в диалоге, который открывается по тапу на
                          // строку, поэтому на компактном экране кнопка уходит
                          // и освобождает 48 dp. На десктопе она остаётся: там
                          // мышь, hover и подсказка работают, а места хватает.
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            _ActionChip(action: rule.action),
                            if (!context.sg.isCompact)
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
                  // ⚠️ Побочный эффект правил по сайтам, о котором нельзя
                  // молчать: приложение глушит HTTP/3 для ВСЕГО трафика, а не
                  // только для перечисленных доменов. Иначе правило по сайту
                  // молча не срабатывает — браузер на HTTP/3 имени не
                  // оставляет. Пользователь имеет право знать, почему у него
                  // пропал HTTP/3, хотя он такого не просил.
                  if (st.sites.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16,
                              color: Theme.of(context).hintColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelText(
                              l.splitQuicNote,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context).hintColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Стоит здесь, а не в общих настройках: заглушка касается
                  // только правил «Блок», а их заводят именно на этом экране.
                  // Показываем, лишь когда блокировка реально есть, — иначе это
                  // настройка ни для чего.
                  if (st.sites.any((x) => x.action == AppAction.block)) ...[
                    const Divider(),
                    SwitchListTile(
                      secondary: const Icon(Icons.report_outlined),
                      value: controller.settings.blockPageEnabled,
                      onChanged: (v) => controller
                          .update((s) => s.copyWith(blockPageEnabled: v)),
                      title: Text(l.settingsBlockPage),
                      subtitle: SelText(l.settingsBlockPageSub,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
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

  /// Добавить СРАЗУ НЕСКОЛЬКО приложений одним изменением настроек.
  ///
  /// ⚠️ Не циклом по [_addApp]: каждый вызов пишет настройки на диск и дёргает
  /// перерисовку, а при выборе десятка приложений это десяток сохранений
  /// подряд. Плюс промежуточные состояния успевают уехать в конфиг.
  void _addApps(SettingsController c, List<String> paths) {
    if (paths.isEmpty) return;
    c.update((s) {
      final apps = [...s.splitTunnel.apps];
      final have = {for (final a in apps) a.path.toLowerCase()};
      for (final path in paths) {
        if (have.contains(path.toLowerCase())) continue;
        have.add(path.toLowerCase());
        apps.add(AppRule(path,
            byName: true, action: s.splitTunnel.defaultAction));
      }
      return s.copyWith(splitTunnel: s.splitTunnel.copyWith(apps: apps));
    });
  }

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
      {AppAction? action,
      bool? byName,
      bool? enabled,
      bool? allowRealIp,
      bool? overrideSites}) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            apps: s.splitTunnel.apps
                .map((a) => a.path == rule.path
                    ? a.copyWith(
                        action: action,
                        byName: byName,
                        enabled: enabled,
                        allowRealIp: allowRealIp,
                        overrideSites: overrideSites)
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
        // Показать заглушку вручную.
        //
        // ⚠️ Иначе увидеть её почти невозможно: перехватывается только plain
        // HTTP, а браузеры повышают http до https сами (HSTS, HTTPS-First).
        // Пользователь набирает адрес — браузер молча уходит на 443, где его
        // ждёт reject, и вместо объяснения человек видит обычную ошибку
        // соединения. Ссылка на петлю таким повышением не затрагивается.
        if (site.action == AppAction.block &&
            controller.settings.blockPageEnabled)
          IconButton(
            tooltip: l.splitShowBlockPage,
            icon: const Icon(Icons.open_in_new),
            onPressed: () {
              final url = BlockPageServer.urlFor(site.domain);
              if (url == null) {
                // Сервер заглушки живёт только при поднятом туннеле.
                AppToast.show(context, l.splitBlockPageNeedsVpn,
                    kind: ToastKind.info);
                return;
              }
              UrlOpener.open(url);
            },
          ),
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
        // Только у приложений: у сайта переопределять нечего.
        overrideSites: rule.overrideSites,
        onAction: (a) => _updateApp(c, rule, action: a),
        onByName: (b) => _updateApp(c, rule, byName: b),
        onAllowRealIp: (v) => _updateApp(c, rule, allowRealIp: v),
        onOverrideSites: (v) => _updateApp(c, rule, overrideSites: v),
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
    // ⚠️ Диалог отдаёт СПИСОК. Раньше он возвращал одну строку и закрывался на
    // первом же тапе: пользователь отмечал несколько приложений, а добавлялось
    // одно. Из-за этого в правилах владельца не оказалось браузера — и в режиме
    // «только отмеченные» весь веб уходил мимо VPN, что выглядело как «ничего
    // не работает».
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _RunningPickerDialog(procs: procs),
    );
    if (selected != null) _addApps(c, selected);
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

  /// Отмеченные приложения. Раньше диалог закрывался на первом тапе и отдавал
  /// ровно одно — отсюда и жалоба «правила не работают при мультивыделении».
  final Set<String> _picked = {};

  /// Имя → сколько приложений его носят (для подписи у тёзок).
  final Map<String, int> _dupes = {};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Сколько приложений носят каждое имя: подпись нужна только тёзкам.
    if (_dupes.isEmpty) {
      for (final p in widget.procs) {
        _dupes[p.label] = (_dupes[p.label] ?? 0) + 1;
      }
    }
    final filtered = _q.isEmpty
        ? widget.procs
        : widget.procs
            .where((p) => p.label.toLowerCase().contains(_q.toLowerCase()))
            .toList();
    return AlertDialog(
      // См. кнопку открытия: на Android это установленные приложения.
      title: Row(children: [
        Expanded(
          child: Text(platform.appCatalog.supportsManualPick
              ? l.splitRunningApps
              : l.splitInstalledApps),
        ),
        // На компактном экране третья кнопка живёт здесь — см. комментарий у
        // `actions`.
        if (filtered.isNotEmpty && context.sg.isCompact)
          IconButton(
            tooltip: l.splitSelectAllFound,
            icon: const Icon(Icons.done_all),
            onPressed: () => setState(() {
              final keys = filtered.map((p) => p.key);
              if (keys.every(_picked.contains)) {
                _picked.removeAll(keys);
              } else {
                _picked.addAll(keys);
              }
            }),
          ),
      ]),
      content: adaptiveDialogBody(
        context,
        width: 440,
        height: 480,
        child: Column(
          children: [
            TextField(
              // ⚠️ НЕ автофокус на телефоне: клавиатура поднимается В МОМЕНТ
                // открытия и съедает ~280 dp — человек видит список из одной
                // строки раньше, чем успевает что-то выбрать.
                autofocus: !context.sg.isCompact,
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
                        final on = _picked.contains(p.key);
                        // ⚠️ Подпись показываем ТОЛЬКО у тёзок. Она и есть та
                        // вторая строка, из-за которой каждая позиция занимала
                        // 64 dp вместо 56: на десяти видимых строках это целая
                        // потерянная позиция. А смысл у неё ровно один —
                        // различить два приложения с одинаковым названием; в
                        // остальных случаях на Android там просто имя пакета,
                        // которое ничего не добавляет.
                        final ambiguous = (_dupes[p.label] ?? 0) > 1;
                        return CheckboxListTile(
                          dense: true,
                          value: on,
                          controlAffinity: ListTileControlAffinity.leading,
                          // Иконка рядом с галочкой: без неё в длинном списке
                          // одинаковых имён не разобраться, что именно отмечено.
                          secondary: AppIcon(
                              path: p.key, size: context.sg.listIconSize),
                          title: Text(p.label,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: ambiguous
                              ? Text(p.key,
                                  maxLines: 1, overflow: TextOverflow.ellipsis)
                              : null,
                          onChanged: (v) => setState(() =>
                              v == true ? _picked.add(p.key) : _picked.remove(p.key)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      // ⚠️ ТРИ КНОПКИ НА ТЕЛЕФОНЕ НЕ ВЛЕЗАЮТ В СТРОКУ.
      //
      // Диалог на экране 360 dp получает 280 dp ширины, а «Отметить всё
      // найденное» + «Закрыть» + «Добавить (N)» требуют заметно больше.
      // `OverflowBar` в этом случае раскладывает их СТОЛБИКОМ и съедает ~170 dp
      // высоты — при 300 dp, уже отданных клавиатуре, списку не оставалось
      // ничего. Поэтому на компактном экране «Отметить всё найденное»
      // переезжает из ряда кнопок в шапку диалога, где место есть.
      actions: [
        // «Отметить всё найденное» — по отфильтрованному списку, а не по всему:
        // иначе поиск теряет смысл, а случайное нажатие добавляет сотню правил.
        if (filtered.isNotEmpty && !context.sg.isCompact)
          TextButton(
            onPressed: () => setState(() {
              final keys = filtered.map((p) => p.key);
              if (keys.every(_picked.contains)) {
                _picked.removeAll(keys);
              } else {
                _picked.addAll(keys);
              }
            }),
            child: Text(l.splitSelectAllFound),
          ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.splitClose)),
        // Счётчик прямо на кнопке: видно, сколько уйдёт в правила, и заметно,
        // если отметилось не то.
        FilledButton(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.of(context).pop(_picked.toList()),
          child: Text(l.splitAddSelected(_picked.length)),
        ),
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

  /// Приложение важнее правил по сайтам. null — запись без этой опции (сайт).
  final bool? overrideSites;
  final ValueChanged<bool>? onOverrideSites;

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
    this.overrideSites,
    this.onOverrideSites,
  });

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late AppAction _action = widget.action;
  late bool _byName = widget.byName ?? true;
  late bool _allowRealIp = widget.allowRealIp ?? true;

  late bool _overrideSites = widget.overrideSites ?? false;
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
      // ⚠️ Внутри поле «Порт»: без прокрутки диалог рвётся при клавиатуре.
      // У пикера выше scrollable НЕ ставим — там свой ListView в Expanded,
      // и внешняя прокрутка отняла бы у него высоту.
      scrollable: true,
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
          // Переопределение приоритета: по умолчанию правило сайта конкретнее и
          // потому сильнее. Здесь это можно перевернуть для конкретного
          // приложения — когда оно обязано ходить одним путём целиком.
          if (widget.overrideSites != null) ...[
            const Divider(),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _overrideSites,
              onChanged: (v) {
                setState(() => _overrideSites = v);
                widget.onOverrideSites?.call(v);
              },
              title: Text(l.splitAppOverrideSites),
              subtitle: Text(l.splitAppOverrideSitesSub),
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
          // Способ сопоставления — понятие Windows: там правило матчится либо по
          // имени exe, либо по полному пути. На Android ядро получает от
          // VpnService только uid и знает приложение по ИМЕНИ ПАКЕТА — выбор
          // ничего не менял, но правил настройки и звал переподключиться зря.
          if (widget.byName != null && !Platform.isAndroid && !Platform.isIOS) ...[
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
