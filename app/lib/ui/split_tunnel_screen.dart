import '../core/models/vpn_server.dart';
import '../core/util/country_flag.dart';
import 'package:country_flags/country_flags.dart';
import '../state/app_state.dart';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'layout/adaptive.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/settings/app_settings.dart';
import '../core/singbox/exit_outbounds.dart';
import '../core/settings/split_tunnel.dart';
import '../core/platform/platform_services.dart';
import '../state/settings_controller.dart';
import '../core/util/server_search.dart';
import 'widgets/app_icon.dart';
import 'widgets/dead_path_badge.dart';
import 'widgets/server_search_field.dart';
import 'widgets/server_tile.dart';
import 'widgets/app_label.dart';
import 'widgets/route_diagram.dart';
import 'widgets/site_favicon.dart';
import 'widgets/info_tooltip.dart';
import 'widgets/sel_text.dart';
import 'widgets/app_toast.dart';
import '../core/i18n/enum_labels.dart';
import '../l10n/gen/app_localizations.dart';

/// Можно ли редактировать правила при таком способе захвата.
///
/// ⚠️ НЕ ТО ЖЕ САМОЕ, ЧТО «ПРАВИЛА ДЕЙСТВУЮТ ДЛЯ ВСЕЙ МАШИНЫ».
///
/// * `tun` — действуют полностью;
/// * `proxyOnly` — не действуют ни для одной программы машины (перехватывать
///   нечего), но список «Блок» применяется к локальным портам API при
///   включённом `AppSettings.applyRulesInProxyOnly`. Значит редактировать его
///   надо ЗДЕСЬ — а экран был заблокирован, и тумблер в настройках вёл в
///   никуда (находка финального ревью 8);
/// * `systemProxy` — не действуют вовсе: приложения сами решают, ходить ли
///   через прокси, и принудить их нечем.
bool splitRulesEditableIn(CaptureMode mode) => mode != CaptureMode.systemProxy;

class SplitTunnelScreen extends StatelessWidget {
  const SplitTunnelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    // Серверы и текущий выбор — из состояния приложения: правило указывает на
    // сервер напрямую, поэтому список нужен и строкам, и диалогам.
    final state = context.watch<AppState>();
    final st = controller.settings.splitTunnel;
    // #2 — при системном прокси раздельное туннелирование не работает
    // (приложения сами решают, ходить ли через прокси): контролы серые.
    final mode = controller.settings.captureMode;
    final tunActive = mode == CaptureMode.tun;
    // ⚠️ В «Только прокси» ЭКРАН РЕДАКТИРУЕМ, ХОТЬ TUN И НЕ ВКЛЮЧЁН —
    // см. [splitRulesEditableIn], там же почему.
    final editable = splitRulesEditableIn(mode);
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
                  child: SelText(mode == CaptureMode.proxyOnly
                      ? l.splitProxyOnlyBanner
                      : l.splitTunOnlyBanner),
                ),
                // Кнопка «Включить TUN» — только там, где менять режим и
                // правда нужно. В «Только прокси» её нет: режим выбран
                // осознанно (ради портов API), и предлагать выйти из него
                // ради правил, которые тут и так частично работают, — совет
                // против намерения пользователя.
                if (mode != CaptureMode.proxyOnly)
                  TextButton(
                    onPressed: () => controller.update(
                        (s) => s.copyWith(captureMode: CaptureMode.tun)),
                    child: Text(l.splitEnableTun),
                  ),
              ]),
            ),
          // #2 — при системном прокси всё серое и неактивное.
          IgnorePointer(
            ignoring: !editable,
            child: Opacity(
              opacity: editable ? 1 : 0.45,
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
                  const Divider(),
                  // ⚠️ ВЫШЕ блока «списки при не-all режиме» намеренно: выходы
                  // действуют и в режиме «Всё через VPN». Там нет ни «Прямо»,
                  // ни «Блока», но вопрос «в какой туннель» остаётся.
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
                          // Человеческое имя приложения, а не ключ правила. На
                          // Windows ключ и есть имя файла, на Android — имя
                          // пакета, и без этого в строке стояло
                          // «com.google.android.youtube» при верной иконке.
                          title: AppLabel(
                              path: rule.path, fallback: rule.name),
                          subtitle: _ruleSubtitle(
                            context,
                            rule.enabled
                                // На Android сопоставления «по имени/по пути»
                                // нет — там имя пакета, и подпись «По имени ·
                                // com.android.chrome» только путала.
                                // ⚠️ Показываем ТО, ПО ЧЕМУ РЕАЛЬНО СРАВНИВАЕМ.
                                // Раньше подпись гласила «По имени · <полный
                                // путь>» — то есть называла способ, а
                                // показывала поле, к сопоставлению отношения не
                                // имеющее. Четыре записи одной программы, все
                                // с разными путями, выглядели разными
                                // правилами, хотя правило было одно.
                                ? (Platform.isAndroid || Platform.isIOS
                                    ? rule.path
                                    : '${rule.byName ? l.splitByName : l.splitByPath}'
                                        ' · ${rule.byName ? rule.name : rule.path}')
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
                            // Правило по пути на исчезнувший файл: молчать о нём
                            // нельзя — оно выглядит здоровым и не совпадает ни с
                            // чем (воспроизведено опытом, см. DeadPathBadge).
                            DeadPathBadge(
                              rule: rule,
                              onSwitchToName: () =>
                                  _updateApp(controller, rule, byName: true),
                            ),
                            ServerBadge(
                                servers: state.servers,
                                serverKey: rule.serverKey,
                                action: rule.action),
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
                  ..._sortedSites(st.sites).expand((e) => [
                        // Разделитель между группами: без него соседние сайты
                        // читаются как один список, и поддомен одного домена
                        // выглядит принадлежащим предыдущему.
                        if (e.newGroup)
                          const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
                        _siteTile(context, controller, e.site, e.depth),
                      ]),
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
                  // Стоит здесь, а не в общих настройках: уведомление касается
                  // только правил «Блок», а их заводят именно на этом экране.
                  // Показываем, лишь когда блокировка реально есть, — иначе это
                  // настройка ни для чего.
                  //
                  // ⚠️ ЗДЕСЬ БЫЛА СТРАНИЦА-ЗАГЛУШКА. Она подменяла ответ по
                  // http и до пользователя почти никогда не доходила: браузеры
                  // идут в https сразу, HSTS переписывает адрес ДО отправки
                  // запроса, и человек видел `ERR_CONNECTION_RESET` вместо
                  // объяснения. Подменить https без своего корневого
                  // сертификата нельзя, а ставить такой сертификат — значит
                  // получить возможность читать весь TLS пользователя. Поэтому
                  // объяснение переехало туда, где оно работает всегда, —
                  // в само приложение.
                  if (st.sites.any((x) => x.action == AppAction.block)) ...[
                    const Divider(),
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_active_outlined),
                      value: controller.settings.blockNoticeEnabled,
                      onChanged: (v) => controller
                          .update((s) => s.copyWith(blockNoticeEnabled: v)),
                      title: Text(l.blockNoticeTitle),
                      subtitle: SelText(l.blockNoticeSub,
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
      for (final path in paths) {
        // ⚠️ Спрашиваем у правил, покрывают ли они эту программу, а НЕ сравниваем
        // пути. Правило «по имени» ловит процесс по имени файла, поэтому запись
        // с прежним путём (до обновления программы) — это та же самая запись.
        if (apps.any((a) => a.matches(path))) continue;
        apps.add(AppRule(path,
            byName: true, action: s.splitTunnel.defaultAction));
      }
      return s.copyWith(splitTunnel: s.splitTunnel.copyWith(apps: apps));
    });
  }

  /// `false` — правило на эту программу уже есть (вызывающий скажет об этом).
  bool _addApp(SettingsController c, String path) {
    if (c.settings.splitTunnel.containsApp(path)) return false;
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
    return true;
  }

  void _removeApp(SettingsController c, AppRule rule) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            apps: s.splitTunnel.apps
                // По ключу сопоставления, а не по пути: у правила «по имени»
                // путь — это лишь путь, по которому его когда-то завели, и он
                // устаревает при первом же обновлении программы.
                .where((a) => a.matchKey != rule.matchKey)
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
                // `rule` — состояние ДО правки, поэтому его ключ совпадает с
                // ключом искомого элемента даже когда правка меняет `byName`.
                .map((a) => a.matchKey == rule.matchKey
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

  /// Назначить сайту сервер. `null` — основной туннель.
  void _setSiteServer(SettingsController c, SiteRule site, String? key) {
    c.update((s) => s.copyWith(
          splitTunnel: s.splitTunnel.copyWith(
            sites: [
              for (final x in s.splitTunnel.sites)
                (x.domain == site.domain && x.port == site.port)
                    ? x.copyWith(serverKey: key, clearServer: key == null)
                    : x
            ],
          ),
        ));
  }

  /// Назначить приложению сервер. `null` — основной туннель.
  void _setAppServer(SettingsController c, AppRule rule, String? key) {
    c.update((s) => s.copyWith(
          splitTunnel: s.splitTunnel.copyWith(
            apps: [
              for (final a in s.splitTunnel.apps)
                // Тот же ключ сопоставления, что и в _updateApp/_removeApp:
                // четыре точки сравнения обязаны согласоваться, иначе выбор
                // сервера уедет не на то правило.
                a.matchKey == rule.matchKey
                    ? a.copyWith(serverKey: key, clearServer: key == null)
                    : a
            ],
          ),
        ));
  }

  void _setSiteAllowRealIp(SettingsController c, SiteRule site, bool value) {
    c.update((s) => s.copyWith(
        splitTunnel: s.splitTunnel.copyWith(
            sites: s.splitTunnel.sites
                .map((x) => _sameSite(x, site) ? x.copyWith(allowRealIp: value) : x)
                .toList())));
  }

  /// Упорядочивает сайты для показа деревом.
  ///
  /// Группируем по «корневому» домену (`example.com`), внутри группы корень
  /// идёт первым, поддомены — под ним с отступом. [newGroup] помечает первую
  /// строку каждой группы: по ней рисуется разделитель, иначе соседние группы
  /// сливаются в один список.
  ///
  /// ⚠️ ГЛУБИНА СЧИТАЕТСЯ ПО РЕАЛЬНО ПРИСУТСТВУЮЩИМ ПРЕДКАМ, А НЕ ПО
  /// ВЫЧИСЛЕННОМУ КОРНЮ. Раньше отступ брался как «число лишних уровней
  /// относительно `baseDomain`», и строка получала его даже тогда, когда
  /// родителя в списке НЕТ. У владельца это выглядело так: `xtls.github.com`
  /// стоял с отступом сразу под `dnsleaktest.com` — то есть читался как его
  /// поддомен, хотя не имеет к нему отношения вовсе. Ошибка чисто
  /// отображательная (маршруты строятся отдельно), но она заставляет искать
  /// поломку в конфиге, которой там нет.
  /// Раскладка дерева для теста: логика чистая, а поднимать ради неё виджеты
  /// значило бы проверять Flutter вместо своего кода.
  @visibleForTesting
  static List<({SiteRule site, int depth, bool newGroup})> debugSortedSites(
          List<SiteRule> sites) =>
      _sortedSites(sites);

  static List<({SiteRule site, int depth, bool newGroup})> _sortedSites(
      List<SiteRule> sites) {
    // ⚠️ СОРТИРУЕМ ПО ПЕРЕВЁРНУТЫМ МЕТКАМ, А НЕ ПО ПАРЕ «КОРЕНЬ + ЧИСЛО ТОЧЕК».
    //
    // `a.b.example.com` → `[com, example, b, a]`, дальше обычное лексикографи-
    // ческое сравнение. Это честный обход дерева сверху вниз: предок по
    // построению оказывается перед любым своим потомком, а ветви не
    // перемешиваются.
    //
    // Прежний порядок «сначала baseDomain, потом число меток» давал два
    // разных дефекта, и оба нашлись проверкой:
    //  1. голый публичный суффикс в списке (`co.uk` рядом с `bbc.co.uk`)
    //     уезжал ПОД своего потомка: у них разный `baseDomain`, и ключи
    //     сравнивались как чужие;
    //  2. внутри группы сортировка по ЧИСЛУ меток — это обход в ширину:
    //     `x.a.example.com` вставал после `b.example.com`, то есть прилипал
    //     отступом к чужому соседу. Ровно тот класс ошибки, ради которого
    //     правка и делалась.
    // Регистр учитываем ЗДЕСЬ ЖЕ: `depthOf` его нормализует, и компаратор
    // обязан вести себя так же, иначе `Example.COM` и `sub.example.com`
    // разъезжаются.
    List<String> key(SiteRule s) =>
        s.domain.toLowerCase().split('.').reversed.toList();
    final ordered = [...sites];
    ordered.sort((a, b) {
      final ka = key(a), kb = key(b);
      for (var i = 0; i < ka.length && i < kb.length; i++) {
        final c = ka[i].compareTo(kb[i]);
        if (c != 0) return c;
      }
      if (ka.length != kb.length) return ka.length.compareTo(kb.length);
      return (a.port ?? 0).compareTo(b.port ?? 0);
    });

    final present = ordered.map((s) => s.domain.toLowerCase()).toSet();
    // Сколько предков этого домена реально есть в списке: столько отступов и
    // рисуем. `a.b.example.com` при наличии только `example.com` получит 1, а
    // не 2 — промежуточного уровня в списке нет, и «ступенька» в пустоту
    // выглядела бы как пропущенная строка.
    int depthOf(String domain) {
      final d = domain.toLowerCase();
      var n = 0;
      final parts = d.split('.');
      for (var i = 1; i < parts.length; i++) {
        if (present.contains(parts.sublist(i).join('.'))) n++;
      }
      return n;
    }

    String? prevBase;
    final out = <({SiteRule site, int depth, bool newGroup})>[];
    for (final s in ordered) {
      final base = baseDomain(s.domain);
      out.add((
        site: s,
        depth: depthOf(s.domain),
        newGroup: prevBase != null && prevBase != base,
      ));
      prevBase = base;
    }
    return out;
  }

  Widget _siteTile(BuildContext context, SettingsController controller,
      SiteRule site, int depth) {
    final state = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final indent = 16.0 + depth * 22.0;
    return ListTile(
      key: ValueKey('site:${site.domain}|${site.port ?? ''}'),
      contentPadding: EdgeInsetsDirectional.only(start: indent, end: 16),
      leading: Row(mainAxisSize: MainAxisSize.min, children: [
        if (depth > 0)
          Icon(Icons.subdirectory_arrow_right,
              size: 18, color: Theme.of(context).disabledColor),
        // ⚠️ Открытый замок — ровно то же предупреждение, что показывает
        // браузер. `http://` означает, что провайдер видит соединение целиком:
        // и адрес страницы, и параметры запроса, и содержимое. Правило от
        // этого не спасает — оно решает, КУДА идёт трафик, а не шифрует его.
        // Показываем только когда схему написал сам пользователь: додумывать
        // за него, чего он не писал, нельзя.
        if (site.insecureScheme)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: Tooltip(
              message: l.siteInsecureScheme,
              child: Icon(Icons.no_encryption_gmailerrorred_outlined,
                  size: 18, color: Theme.of(context).colorScheme.error),
            ),
          ),
        SiteFavicon(domain: site.domain),
      ]),
      // ⚠️ У ПОДДОМЕНА ПОКАЗЫВАЕМ ТОЛЬКО ЕГО ЧАСТЬ, а общий хвост приглушаем.
      // Иначе в столбце стоят три почти одинаковые строки, отличающиеся первым
      // словом, и разница между `xtls.github.io` и `github.io` теряется — а от
      // неё зависит, какое правило сработает.
      title: depth > 0
          ? _SubdomainLabel(site: site)
          : Text(site.label,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: _ruleSubtitle(
          context,
          site.port != null ? l.splitOnlyPort(site.port!) : null,
          action: site.action,
          allowRealIp: site.allowRealIp,
          noRealIp: controller.settings.noRealIp),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ServerBadge(
            servers: state.servers,
            serverKey: site.serverKey,
            action: site.action),
        _ActionChip(action: site.action),
        // Показать заглушку вручную.
        //
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
    final state = context.read<AppState>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _RuleDialog(
        servers: state.servers,
        currentServer: state.selectedServer,
        serverKey: rule.serverKey,
        onServer: (key) => _setAppServer(c, rule, key),
        // Строка списка уже прогрела кэш меток — берём готовую.
        title: (hasPlatformServices
                ? platform.appCatalog.cachedLabel(rule.path)
                : null) ??
            rule.name,
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
    final state = context.read<AppState>();
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
        servers: state.servers,
        currentServer: state.selectedServer,
        serverKey: site.serverKey,
        onServer: (key) {
          _setSiteServer(c, current, key);
          current = current.copyWith(serverKey: key, clearServer: key == null);
        },
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
    if (file == null) return;
    // Молчаливое «ничего не произошло» читается как поломка: пользователь выбрал
    // файл, а список не изменился. Говорим, почему.
    final added = _addApp(c, file.path);
    if (!added && context.mounted) {
      AppToast.show(context, l.splitAppAlreadyAdded);
    }
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
                          // ⚠️ ИКОНКА В `title`, А НЕ В `secondary`. У
                          // CheckboxListTile `secondary` — это слот на
                          // ПРОТИВОПОЛОЖНОЙ от галочки стороне: с галочкой
                          // слева иконка уезжала к правому краю, отрываясь от
                          // имени, которому принадлежит. Порядок, который
                          // просил владелец: галочка, отступ, иконка, имя.
                          title: Row(children: [
                            AppIcon(
                                path: p.key, size: context.sg.listIconSize),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(p.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
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
/// Сервер, через который идёт правило, — плашкой рядом с чипом действия.
///
/// Ничего не рисует, когда сервер не задан или действие не «Туннель»: правило
/// без явного сервера идёт через основной, и плашка «как у всех» у каждой
/// строки только съедала бы ширину, которой на телефоне и так впритык.
///
/// ⚠️ ШИРИНА РЕШАЕТ, ЧТО ПОКАЗАТЬ. Просьба владельца — «старайся вписать полное
/// название сервера, или оставляй только флаг». Поэтому здесь не фиксированная
/// ширина, а [LayoutBuilder]: пока имя влезает — показываем имя целиком, стало
/// тесно — остаётся один флаг, а если флага у сервера нет, имя обрезается.
/// Числом это не задать: на телефоне и в широком окне «влезает» разное.
///
/// ⚠️ Класс публичный только ради стража (`test/rule_server_picker_test.dart`):
/// подсказка налезала на соседнюю строку, и проверять это надо на настоящей
/// плашке, а не на её копии в тесте.
class ServerBadge extends StatelessWidget {
  final List<VpnServer> servers;
  final String? serverKey;
  final AppAction action;

  const ServerBadge(
      {super.key,
      required this.servers,
      required this.serverKey,
      required this.action});

  @override
  Widget build(BuildContext context) {
    if (action != AppAction.tunnel || serverKey == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    VpnServer? server;
    for (final s in servers) {
      if (s.key == serverKey) {
        server = s;
        break;
      }
    }
    // Сервер исчез из подписки, пока правило лежало. Показываем это явно:
    // трафик пойдёт основным туннелем, а молчащая строка выглядела бы
    // настроенной — человек искал бы поломку не там.
    if (server == null) {
      return Tooltip(
        message: l.exitServerGone,
        child: Container(
          margin: const EdgeInsetsDirectional.only(end: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.link_off, size: 13, color: scheme.onErrorContainer),
        ),
      );
    }
    final name = server.displayName;
    final iso = FlagUtil.isoFromName(name);
    // ⚠️ СЕРВЕР МОЖЕТ БЫТЬ ВЫБРАН И ПРИ ЭТОМ НЕ РАБОТАТЬ ОТДЕЛЬНЫМ ВЫХОДОМ.
    //
    // Панельный профиль «Авто» — это готовый конфиг Xray целиком, а вторым
    // выходом трафик разводит sing-box: собрать из такого профиля outbound он
    // не может. Правило остаётся валидным и молча идёт основным туннелем —
    // ровно тот класс дефектов, за который в этом проекте платили дороже всего:
    // «настройка видна, выглядит рабочей и ничего не делает».
    // Владелец решил (07.08.2026) выбор разрешать, но предупреждать.
    //
    // ⚠️ И ДО ЭТОЙ ПРАВКИ КОММЕНТАРИЙ ВРАЛ. Спрашивали
    // `SingboxOutboundFactory.supports`, а он смотрит ТОЛЬКО на `protocol` —
    // у панельного профиля тот берётся с первого outbound'а конфига и равен
    // `vless`, то есть предупреждение про «Авто» не показывалось ни разу с
    // версии 1.2.0. Теперь вопрос задаётся единственному ответчику
    // (`canBeExitServer`), общему с `/v1/exits` и `ExitOutbounds.build`.
    final unsupported = !canBeExitServer(server);
    return LayoutBuilder(builder: (context, box) {
      final tight = box.maxWidth < 132;
      final flagOnly = tight && iso != null;
      final badge = Tooltip(
        // ⚠️ В ПОДСКАЗКЕ — ТОЛЬКО ИМЯ СЕРВЕРА, АБЗАЦ УЕХАЛ В «!».
        //
        // Здесь стоял `exitServerUnsupported(name)` — 230 символов одной
        // всплывающей подсказкой. Подсказка не ограничена по ширине и рисуется
        // ПОД плашкой (`preferBelow` по умолчанию `true`), поэтому накрывала
        // следующее правило списка: владелец прислал скриншот. Длинный текст
        // теперь показывает `InfoTooltip` диалогом (см. ниже), а ширина
        // подсказок вдобавок ограничена темой (`buildAppTheme` в `app.dart`).
        //
        // Имя оставляем: плашка на узком экране показывает один флаг, и без
        // подсказки не узнать, через какой сервер идёт правило.
        message: name,
        child: Container(
          margin: const EdgeInsetsDirectional.only(end: 6),
          padding: EdgeInsets.symmetric(
              horizontal: flagOnly ? 5 : 8, vertical: 3),
          decoration: BoxDecoration(
            // Непригодный сервер красим предупреждением, а не основным цветом:
            // одинаковая плашка означала бы «настроено и работает».
            color: unsupported
                ? scheme.tertiaryContainer
                : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (unsupported)
              Icon(Icons.warning_amber_rounded,
                  size: 13, color: scheme.onTertiaryContainer)
            else if (iso != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: CountryFlag.fromCountryCode(iso, width: 16, height: 12),
              )
            else
              Icon(Icons.alt_route, size: 13, color: scheme.onPrimaryContainer),
            // Тесно и флаг есть — он и опознаёт сервер, текст только мешает.
            if (!flagOnly) ...[
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: unsupported
                          ? scheme.onTertiaryContainer
                          : scheme.onPrimaryContainer),
                ),
              ),
            ],
          ]),
        ),
      );
      if (!unsupported) return badge;
      // «!» рядом с плашкой: абзац о том, почему сервер не поднимется
      // отдельным выходом, показывается ДИАЛОГОМ. Он же работает на тач-экране,
      // где наведения нет вовсе, — прежняя подсказка там была недостижима.
      return Row(mainAxisSize: MainAxisSize.min, children: [
        badge,
        InfoTooltip(l.exitServerUnsupportedInfo, title: name),
      ]);
    });
  }
}

/// Итог выбора сервера в пикере.
///
/// ⚠️ ОБЁРТКА, А НЕ ГОЛЫЙ `String?`, И ЭТО НЕ ФОРМАЛЬНОСТЬ. `showDialog`
/// возвращает `null` при ОТМЕНЕ (кнопка «Закрыть», Esc, тап мимо диалога), а
/// `null` внутри выбора — законное значение «как основной сервер». Без обёртки
/// закрытие пикера крестиком стирало бы уже выбранный сервер, и правило молча
/// уезжало бы в общий туннель — ровно тот класс дефектов, который в этом
/// проекте стоит дороже всего.
class RuleServerChoice {
  /// Ключ сервера; `null` — «как основной».
  final String? key;
  const RuleServerChoice(this.key);
}

/// Строка «через какой сервер идёт правило» + вход в пикер.
///
/// Текущий выбор показывается ТОЙ ЖЕ строкой [ServerTile], что и на главном
/// экране: флаг, имя, подписка, теги, пинг и скорость. Данные она берёт из тех
/// же провайдеров, поэтому разойтись с главным экраном физически не может —
/// в отличие от прежнего `Text(displayName)`, который показывал только имя.
class RuleServerField extends StatelessWidget {
  final List<VpnServer> servers;

  /// Сервер, выбранный на главном экране, — для подписи «Как основной (…)».
  final VpnServer? currentServer;
  final String? serverKey;
  final ValueChanged<String?> onChanged;

  const RuleServerField({
    super.key,
    required this.servers,
    required this.currentServer,
    required this.serverKey,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    final choice = await showDialog<RuleServerChoice>(
      context: context,
      builder: (_) => RuleServerPickerDialog(
        servers: servers,
        currentServer: currentServer,
        serverKey: serverKey,
      ),
    );
    // Отмена (`null`) выбор НЕ трогает — см. [RuleServerChoice].
    if (choice != null) onChanged(choice.key);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    VpnServer? picked;
    for (final s in servers) {
      if (s.key == serverKey) {
        picked = s;
        break;
      }
    }
    // ⚠️ Сервер мог пропасть из подписки, пока правило лежало. Прежний
    // `DropdownButtonFormField` в этом случае молча показывал «Как основной» —
    // то есть врал: правило по-прежнему ссылается на исчезнувший сервер.
    // Говорим прямо, той же строкой, что и плашка в списке правил.
    final gone = serverKey != null && picked == null;

    final Widget inner;
    if (picked != null) {
      inner = ServerTile(
        server: picked,
        selected: false,
        // Тап по строке открывает пикер: строка здесь — не выбор, а показ
        // текущего значения.
        onTap: () => _open(context),
        // Ни меню, ни правки: диалог правила поверх себя ничего не переживёт.
        showActions: false,
        unavailableNote:
            canBeExitServer(picked) ? null : l.exitServerUnsupportedInfo,
      );
    } else {
      inner = ListTile(
        dense: true,
        leading: Icon(gone ? Icons.link_off : Icons.hub_outlined,
            color: gone ? scheme.error : null),
        title: Text(
          gone
              ? l.exitServerGone
              // ⚠️ Умолчание — «тот, что включён сейчас», и оно НЕ фиксируется
              // ключом. Запиши мы сюда текущий сервер, правило застряло бы на
              // нём навсегда: пользователь сменил бы сервер на главном экране, а
              // правило продолжало ходить через прежнюю страну — молча, при том
              // что в строке написано «Туннель».
              : (currentServer == null
                  ? l.ruleServerCurrent
                  : l.ruleServerCurrentNamed(currentServer!.displayName)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _open(context),
      );
    }

    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(child: inner),
          // Стрелка вместо шеврона: поле должно читаться как выпадающий
          // список, которым оно и было, — иначе неочевидно, что по нему жмут.
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

/// Пикер сервера для правила — по образцу диалога выбора приложений.
///
/// ⚠️ ВНУТРИ — НАСТОЯЩИЙ [ServerTile], А НЕ ЕГО УПРОЩЁННАЯ КОПИЯ. Копия
/// разошлась бы с главным экраном на первой же правке (так уже было с плашкой
/// пригодности сервера, которая полтора релиза не показывалась), а здесь
/// строка сама берёт пинг и скорость из `ProbeController`.
///
/// ⚠️ Строки-уведомления подписки (`0.0.0.0:1` с текстом вместо имени) в список
/// не попадают: выход из них собирается синтаксически верным и ведёт в никуда —
/// так решает `exitServerRejection`, единственный ответчик на вопрос
/// пригодности. Предлагать заведомо нерабочий выбор нельзя.
class RuleServerPickerDialog extends StatefulWidget {
  final List<VpnServer> servers;
  final VpnServer? currentServer;
  final String? serverKey;

  const RuleServerPickerDialog({
    super.key,
    required this.servers,
    required this.currentServer,
    required this.serverKey,
  });

  @override
  State<RuleServerPickerDialog> createState() => _RuleServerPickerDialogState();
}

class _RuleServerPickerDialogState extends State<RuleServerPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final all = widget.servers.where((s) => !s.isNotice).toList();
    // Поиск — общий с главным экраном (`ServerSearch`): у владельца в подписке
    // больше сотни серверов, и без поиска список пришлось бы листать.
    // ⚠️ Он отдаёт ИСХОДНЫЕ индексы, поэтому берём сервер по ним, а не по
    // порядку в отфильтрованном списке.
    final found = ServerSearch.matchIndices(all, _q);

    return AlertDialog(
      title: Text(l.ruleServer),
      content: adaptiveDialogBody(
        context,
        width: 440,
        height: 480,
        child: Column(
          children: [
            ServerSearchField(
              value: _q,
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            // «Как основной» — ОТДЕЛЬНОЙ строкой над списком: у этого выбора
            // сервера нет, и строкой сервера его не изобразить.
            ListTile(
              dense: true,
              leading: const Icon(Icons.hub_outlined),
              selected: widget.serverKey == null,
              title: Text(
                widget.currentServer == null
                    ? l.ruleServerCurrent
                    : l.ruleServerCurrentNamed(
                        widget.currentServer!.displayName),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing:
                  widget.serverKey == null ? const Icon(Icons.check) : null,
              onTap: () =>
                  Navigator.of(context).pop(const RuleServerChoice(null)),
            ),
            const Divider(height: 1),
            Expanded(
              child: found.isEmpty
                  ? Center(child: Text(l.splitNothingFound))
                  : ListView.builder(
                      itemCount: found.length,
                      itemBuilder: (_, i) {
                        final s = all[found[i]];
                        return ServerTile(
                          server: s,
                          selected: s.key == widget.serverKey,
                          onTap: () => Navigator.of(context)
                              .pop(RuleServerChoice(s.key)),
                          // Меню строки уводит с диалога (информация,
                          // автонастройка) и умеет удалять сервер — в пикере
                          // это чужие действия.
                          showActions: false,
                          // Пригодность спрашиваем у единственного ответчика,
                          // общего с построителем конфига и `/v1/exits`:
                          // разойдись мы с ним — интерфейс пообещал бы то,
                          // чего конфиг не сделает.
                          unavailableNote: canBeExitServer(s)
                              ? null
                              : l.exitServerUnsupportedInfo,
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
          child: Text(l.splitClose),
        ),
      ],
    );
  }
}

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

  /// Серверы подписки и текущий выбор правила.
  ///
  /// ⚠️ Показываем ТОЛЬКО при действии «Туннель». «Прямо через Германию» —
  /// противоречие: прямое правило идёт мимо всех туннелей, и такой выбор был бы
  /// контролом, который видно и который ничего не делает.
  final List<VpnServer> servers;

  /// Сервер, выбранный на главном экране: он и стоит по умолчанию.
  final VpnServer? currentServer;
  final String? serverKey;
  final ValueChanged<String?>? onServer;

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
    this.servers = const [],
    this.currentServer,
    this.serverKey,
    this.onServer,
  });

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late AppAction _action = widget.action;
  late bool _byName = widget.byName ?? true;
  late bool _allowRealIp = widget.allowRealIp ?? true;

  late bool _overrideSites = widget.overrideSites ?? false;
  late String? _serverKey = widget.serverKey;
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
          // Сервер — только у «Туннеля»: см. оговорку у поля servers.
          if (widget.onServer != null &&
              widget.servers.isNotEmpty &&
              _action == AppAction.tunnel) ...[
            const Divider(),
            Text(l.ruleServer),
            const SizedBox(height: 6),
            // ⚠️ ЗДЕСЬ БЫЛ ВЫПАДАЮЩИЙ СПИСОК С ГОЛЫМ ИМЕНЕМ СЕРВЕРА: ни флага,
            // ни пинга, ни скорости, ни пометки «этот сервер отдельным выходом
            // не поднимается». Человек выбирал вслепую, хотя рядом, на главном
            // экране, всё это уже показано. Требование владельца (18.08.2026):
            // «в выборе сервера, через что пойдёт трафик, отображай инфу о
            // сервере как на главной».
            RuleServerField(
              servers: widget.servers,
              currentServer: widget.currentServer,
              serverKey: _serverKey,
              onChanged: (v) {
                setState(() => _serverKey = v);
                widget.onServer?.call(v);
              },
            ),
          ],
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
                SiteRule(domain,
                    port: port,
                    action: s.splitTunnel.defaultAction,
                    // Схему запоминаем ТОЛЬКО если пользователь написал её сам:
                    // `normalizeDomain` её срезает, и после этого отличить
                    // «http://site.com» от «site.com» уже нельзя.
                    insecureScheme: hasInsecureScheme(_controller.text))]));
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

/// Подпись поддомена: своя часть — обычным цветом, общий хвост — приглушённым.
///
/// ⚠️ Зачем не просто `Text(domain)`. В дереве подряд стоят `github.io` и
/// `xtls.github.io`; читаются они почти одинаково, а ведут себя по-разному —
/// от того, какой из них совпал, зависит и маршрут, и резолвер. Выделяя ту
/// часть, которой строки ОТЛИЧАЮТСЯ, мы делаем разницу видимой без лишних
/// пояснений.
class _SubdomainLabel extends StatelessWidget {
  final SiteRule site;

  const _SubdomainLabel({required this.site});

  @override
  Widget build(BuildContext context) {
    final base = baseDomain(site.domain);
    final d = site.domain;
    // Хвост совпал — значит есть своя часть; иначе рисуем как есть.
    final own = d.toLowerCase().endsWith('.${base.toLowerCase()}')
        ? d.substring(0, d.length - base.length - 1)
        : '';
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.55);
    final port = site.port == null ? '' : ':${site.port}';
    if (own.isEmpty) {
      return Text('$d$port', textDirection: TextDirection.ltr);
    }
    return RichText(
      textDirection: TextDirection.ltr,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: [
          TextSpan(
              text: own, style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: '.$base$port', style: TextStyle(color: muted)),
        ],
      ),
    );
  }
}
