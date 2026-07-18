import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/i18n/enum_labels.dart';
import '../l10n/gen/app_localizations.dart';
import '../core/platform/hwid_windows.dart';
import '../core/platform/interference_scanner.dart';
import '../core/platform/network_recovery.dart';
import '../core/platform/url_opener.dart';
import '../core/net/speed_test.dart';
import '../core/update/app_update.dart';
import '../core/models/vpn_server.dart';
import '../core/settings/app_settings.dart';
import '../core/settings/split_tunnel.dart';
import '../core/subscription/subscription_service.dart';
import '../engine/windows/support_report.dart';
import '../engine/windows/tun/tun_scheduled_task.dart';
import '../engine/windows/xray_version.dart';
import '../state/app_state.dart';
import '../state/settings_controller.dart';
import 'logs_screen.dart';
import 'split_tunnel_screen.dart';
import 'tun_settings_screen.dart';
import 'url_schemes_screen.dart';
import 'widgets/app_toast.dart';
import 'widgets/info_tooltip.dart';
import 'widgets/language_button.dart';

/// Глобальный ключ раздела «Поддержка» — чтобы «перекинуть» сюда по кнопке
/// «Поддержка» из любого места (карточка подписки и т.п.) и прокрутить.
final GlobalKey supportSectionKey = GlobalKey();

class SettingsScreen extends StatefulWidget {
  /// Открыть настройки и сразу прокрутить к разделу «Поддержка».
  final bool scrollToSupport;
  const SettingsScreen({super.key, this.scrollToSupport = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.scrollToSupport) {
      // Раздел «Поддержка» — внизу: мотаем страницу вниз и сразу показываем
      // всплывающее окно поддержки (как будто пользователь сам нажал кнопку).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_scroll.hasClients) {
          await _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
        }
        if (mounted) await _support(context);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsTitle),
        // Переключатель языка — отдельно в шапке (флаг + значок перевода).
        actions: const [LanguageButton()],
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _AppearanceSection(settings: s, controller: controller),
          const Divider(),
          _CaptureSection(settings: s, controller: controller),
          const Divider(),
          _ReliabilitySection(settings: s, controller: controller),
          const Divider(),
          _PingSection(settings: s, controller: controller),
          const Divider(),
          _IdentitySection(settings: s, controller: controller),
          const Divider(),
          const _NetworkSection(),
          const Divider(),
          // «URL-схемы» переехали в раздел «Представление панели» (как приложение
          // общается с панелью), «Логи» — к «Поддержке» (внутри «О программе»).
          const _AboutSection(),
        ],
      ),
    );
  }
}

// ── Надёжность соединения ────────────────────────────────────────────────────
class _ReliabilitySection extends StatelessWidget {
  final AppSettings settings;
  final SettingsController controller;
  const _ReliabilitySection({required this.settings, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l.sectionReliability),
        SwitchListTile(
          value: settings.autoReconnect,
          onChanged: (v) => controller.update((s) => s.copyWith(
                autoReconnect: v,
                // Kill switch без автопереподключения оставил бы трафик
                // заблокированным навсегда — гасим вместе.
                killSwitch: v ? s.killSwitch : false,
              )),
          title: Row(children: [
            Expanded(child: Text(l.autoReconnectTitle)),
            InfoTooltip(l.infoAutoReconnect, title: l.autoReconnectTitle),
          ]),
          subtitle: Text(l.autoReconnectSub),
        ),
        SwitchListTile(
          value: settings.killSwitch,
          // Без автопереподключения восстанавливать нечего — переключатель неактивен.
          onChanged: settings.autoReconnect
              ? (v) => controller.update((s) => s.copyWith(killSwitch: v))
              : null,
          title: Row(children: [
            Expanded(child: Text(l.killSwitchTitle)),
            InfoTooltip(l.infoKillSwitch, title: l.killSwitchTitle),
          ]),
          subtitle: Text(
            settings.autoReconnect
                ? (settings.captureMode == CaptureMode.tun
                    ? l.killSwitchSubTun
                    : l.killSwitchSubProxy)
                : l.killSwitchSubOff,
          ),
        ),
        // «Не выходить под реальным IP» — только при включённом kill switch.
        if (settings.killSwitch)
          SwitchListTile(
            value: settings.noRealIp,
            onChanged: (v) =>
                controller.update((s) => s.copyWith(noRealIp: v)),
            title: Text(l.noRealIpTitle),
            subtitle: Text(l.noRealIpSub),
          ),
      ],
    );
  }
}


// ── Сеть / помехи ────────────────────────────────────────────────────────────
class _NetworkSection extends StatelessWidget {
  const _NetworkSection();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l.sectionNetwork),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: Row(children: [
            Expanded(child: Text(l.networkRecoverTitle)),
            InfoTooltip(l.infoNetworkRecover, title: l.networkRecoverTitle),
          ]),
          subtitle: Text(l.networkRecoverSub),
          onTap: () => _recover(context),
        ),
        ListTile(
          leading: const Icon(Icons.travel_explore),
          title: Row(children: [
            Expanded(child: Text(l.interferenceTitle)),
            InfoTooltip(l.infoInterference),
          ]),
          onTap: () => scanInterferenceDialog(context),
        ),
      ],
    );
  }

  Future<void> _recover(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.networkRecoverConfirmTitle),
        content: Text(l.networkRecoverConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.networkRecoverConfirmOk)),
        ],
      ),
    );
    if (ok == true) await NetworkRecovery.run();
  }
}

/// Диалог сканирования помех (используется и из настроек, и со старта).
Future<void> scanInterferenceDialog(BuildContext context) async {
  final found = await InterferenceScanner.scan();
  if (!context.mounted) return;
  final l = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.interferenceDialogTitle),
      content: SizedBox(
        width: 460,
        child: found.isEmpty
            ? Text(l.interferenceNoneFound)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: found
                    .map((i) => ListTile(
                          dense: true,
                          leading: Icon(i.kind == 'adapter'
                              ? Icons.settings_ethernet
                              : Icons.warning_amber),
                          title: Text(i.name, textDirection: TextDirection.ltr),
                          subtitle: Text(i.detail,
                              textDirection: TextDirection.ltr,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: i.pid != null
                              ? TextButton(
                                  onPressed: () async {
                                    await InterferenceScanner.kill(i.pid!);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                  child: Text(l.commonClose),
                                )
                              : null,
                        ))
                    .toList(),
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(l.interferenceIgnore)),
      ],
    ),
  );
}

/// Как приложение представляется панели. От User-Agent зависит ФОРМАТ подписки:
/// известным клиентам Remnawave отдаёт XRAY_JSON с готовыми конфигами.
class _IdentitySection extends StatelessWidget {
  final AppSettings settings;
  final SettingsController controller;
  const _IdentitySection({required this.settings, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // UA собирается из имени и версии приложения и НЕ редактируется: раньше здесь
    // было поле переопределения, и сохранённое в нём значение «замораживало» версию
    // (у пользователя UA застрял на 0.8.0 после обновлений).
    const effective = SubscriptionService.defaultUserAgent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _sectionHeader(context, l.sectionIdentity)),
          InfoTooltip(l.infoUserAgent),
        ]),
        ListTile(
          dense: true,
          leading: const Icon(Icons.badge_outlined),
          title: Text(l.identityUserAgent),
          subtitle: const SelectableText(effective, textDirection: TextDirection.ltr),
          trailing: IconButton(
            tooltip: l.commonCopy,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () =>
                Clipboard.setData(const ClipboardData(text: effective)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SelectableText(
            l.identityUaAutoNote(AppInfo.version),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        // URL-схемы — тоже про то, как приложение общается со «внешним миром».
        // Сноска «Для владельца панели» переехала ВНУТРЬ экрана URL-схем (внизу).
        ListTile(
          leading: const Icon(Icons.link),
          title: Text(l.urlSchemesTitle),
          subtitle: Text(l.urlSchemesSub),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UrlSchemesScreen()),
          ),
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  Future<({String app, String xray, String hwid})> _load() async {
    final info = await PackageInfo.fromPlatform();
    final xray = await XrayVersion.get();
    final hwid = await Hwid.get();
    return (app: info.version, xray: xray, hwid: hwid);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l.sectionAbout),
        FutureBuilder<({String app, String xray, String hwid})>(
          future: _load(),
          builder: (context, snap) {
            final app = snap.data?.app ?? '…';
            final xray = snap.data?.xray ?? '…';
            final hwid = snap.data?.hwid ?? '…';
            return Column(
              children: [
                ListTile(
                  dense: true,
                  title: Text(l.aboutVersion),
                  trailing: Text('v$app', textDirection: TextDirection.ltr),
                ),
                ListTile(
                  dense: true,
                  title: Text(l.aboutXrayCore),
                  trailing: Text(xray, textDirection: TextDirection.ltr),
                ),
                // Обновление приложения: только проверка и открытие ссылки —
                // ставит пользователь сам (установщик не подписан).
                const _AppUpdateTile(),
                ListTile(
                  title: Text(l.aboutHwid),
                  subtitle: SelectableText(hwid,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  trailing: IconButton(
                    tooltip: l.commonCopy,
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: hwid));
                      AppToast.copied(context);
                    },
                  ),
                ),
                // Обязательное раскрытие: вместе с приложением поставляются
                // xray.exe (MPL-2.0), sing-box.exe (GPL-3.0) и wintun.dll —
                // их лицензии требуют передавать текст и указывать исходники.
                ListTile(
                  leading: const Icon(Icons.workspaces_outline),
                  title: Text(l.aboutThirdPartyTitle),
                  subtitle: Text(l.aboutThirdPartySub),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showThirdParty(context),
                ),
                // Логи — рядом с поддержкой: при обращении в поддержку сюда же
                // заглядывают (формат подписки, пинг, ошибки).
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(l.logsTitle),
                  subtitle: Text(l.logsSub),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LogsScreen()),
                  ),
                ),
                _SupportSection(key: supportSectionKey),
              ],
            );
          },
        ),
      ],
    );
  }
}

const _supportChat = 'https://t.me/silentgate_vpn_help';

/// Поддержка. НИЧЕГО не генерируем и не открываем сразу — открываем диалог, где
/// пользователь СНАЧАЛА жмёт «Сгенерировать лог», и ТОЛЬКО ПОСЛЕ этого видит,
/// куда отправить. Так юзер не пугается, что у него «сама пооткрывалась хрень».
Future<void> _support(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _SupportDialog(),
  );
}

/// Диалог поддержки со строгой последовательностью:
/// 1) объяснение + кнопка «Сгенерировать лог для поддержки»;
/// 2) по нажатию — сборка отчёта и показ (СНАЧАЛА папка, ПОТОМ сам файл);
/// 3) только теперь — меню «кому отправить» (с именем сервиса в скобках).
class _SupportDialog extends StatefulWidget {
  const _SupportDialog();

  @override
  State<_SupportDialog> createState() => _SupportDialogState();
}

class _SupportDialogState extends State<_SupportDialog> {
  bool _busy = false;
  String? _path; // путь к готовому отчёту (null, пока не сгенерирован)
  String? _error;

  Future<void> _generate() async {
    final l = AppLocalizations.of(context);
    final state = context.read<AppState>();
    final settings = context.read<SettingsController>().settings;
    final server = state.selectedServer;
    // Локализованная шапка отчёта (только её и переводим — техчасть ниже как есть).
    final header = (StringBuffer()
          ..writeln('==================================================')
          ..writeln('  ${l.reportTitle}')
          ..writeln('==================================================')
          ..writeln()
          ..writeln(l.reportDescribeHere)
          ..writeln()
          ..writeln('  ${l.reportWhatDid}')
          ..writeln('  ${l.reportWhatExpected}')
          ..writeln('  ${l.reportWhatHappened}')
          ..writeln('  ${l.reportWhenStarted}')
          ..writeln()
          ..writeln('--------------------------------------------------')
          ..writeln(l.reportTechNoticeLine1)
          ..writeln(l.reportTechNoticeLine2)
          ..writeln('--------------------------------------------------'))
        .toString();
    final ctx = SupportContext(
      statusLine: state.status.label,
      subscriptionUrl: state.subscriptionUrl,
      serverCount: state.servers.length,
      activeServer: server == null ? '(нет)' : server.displayName,
      activeCore: server == null
          ? '—'
          : (server.core == ProxyCore.singbox ? 'sing-box' : 'Xray'),
      header: header,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await SupportReport.generate(settings: settings, ctx: ctx);
      // Строгий порядок: сперва открыть папку, затем сам txt-файл (см. reveal).
      await SupportReport.reveal(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    // Имя сервиса VPN (владельца подписки) — для подписи «кому отправить».
    final serviceName = (state.info.title ?? '').trim();
    final vpnSupport = (state.info.supportUrl ?? '').trim();
    final done = _path != null;

    return AlertDialog(
      title: Text(done ? l.supportDialogTitleDone : l.supportDialogTitle),
      content: SizedBox(
        width: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!done) ...[
              Text(l.supportWhatWillHappen,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(l.supportBullet1),
              const SizedBox(height: 4),
              Text(l.supportBullet2),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(l.supportError(_error!),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12)),
              ],
            ] else ...[
              Text(l.supportDoneText),
              const SizedBox(height: 8),
              SelectableText(_path!.split(RegExp(r'[\\/]')).last,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 14),
              Text(l.supportWhoTo,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (vpnSupport.isNotEmpty)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.support_agent, size: 18),
                    // В скобках — НАЗВАНИЕ СЕРВИСА, а не «владельцу».
                    label: Text(serviceName.isNotEmpty
                        ? l.supportContactNamed(serviceName)
                        : l.supportContact),
                    onPressed: () => UrlOpener.openTelegram(vpnSupport),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.developer_mode, size: 18),
                  label: Text(l.supportContactNamed(l.supportDevServiceName)),
                  onPressed: () => UrlOpener.openTelegram(_supportChat),
                ),
              ]),
            ],
          ],
        ),
      ),
      actions: [
        if (done)
          TextButton.icon(
            icon: const Icon(Icons.folder_open, size: 18),
            onPressed: () => SupportReport.reveal(_path!),
            label: Text(l.supportShowOnPc),
          ),
        if (done)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _path!));
              AppToast.copied(context, message: l.commonPathCopied);
            },
            label: Text(l.supportCopyPath),
          ),
        if (!done)
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.description_outlined, size: 18),
            onPressed: _busy ? null : _generate,
            label: Text(_busy ? l.supportGenerating : l.supportGenerateButton),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(done ? l.commonDone : l.commonCancel),
        ),
      ],
    );
  }
}

/// Раздел «Поддержка». Никакой ПРЯМОЙ ссылки здесь нет: единственная кнопка
/// запускает флоу выше — юзер сам генерирует лог, и уже там появляется редирект
/// в поддержку. Сюда же «перекидывает» кнопка «Поддержка» из карточки подписки.
class _SupportSection extends StatelessWidget {
  const _SupportSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l.sectionSupport),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l.supportSectionNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        ListTile(
          leading: Icon(Icons.support_agent, color: scheme.primary),
          title: Text(l.supportButtonTitle),
          subtitle: Text(l.supportButtonSub),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => _support(context),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Список стороннего кода в поставке. Тексты лицензий кладутся рядом с
/// приложением в папку `licenses` (см. build-exe.bat и THIRD-PARTY.md).
void _showThirdParty(BuildContext context) {
  final l = AppLocalizations.of(context);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.thirdPartyTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                l.thirdPartyBody,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(l.commonClose)),
      ],
    ),
  );
}

Widget _sectionHeader(BuildContext context, String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Row(
      children: [
        Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                )),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );
}

Widget _badge(BuildContext context, String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text,
        style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSecondaryContainer)),
  );
}

// ── Оформление и поведение ───────────────────────────────────────────────────
class _AppearanceSection extends StatelessWidget {
  final AppSettings settings;
  final SettingsController controller;
  const _AppearanceSection({required this.settings, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l.sectionAppearance),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Text(l.appearanceTheme),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<AppThemeMode>(
            segments: [
              ButtonSegment(
                  value: AppThemeMode.system, label: Text(l.themeSystem)),
              ButtonSegment(value: AppThemeMode.light, label: Text(l.themeLight)),
              ButtonSegment(value: AppThemeMode.dark, label: Text(l.themeDark)),
            ],
            selected: {settings.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                controller.update((st) => st.copyWith(themeMode: s.first)),
          ),
        ),
        SwitchListTile(
          value: settings.closeToTray,
          onChanged: (v) => controller.update((s) => s.copyWith(closeToTray: v)),
          title: Text(l.closeToTrayTitle),
          subtitle: Text(l.closeToTraySubtitle),
        ),
        SwitchListTile(
          value: settings.autoUpdateEnabled,
          onChanged: (v) =>
              controller.update((s) => s.copyWith(autoUpdateEnabled: v)),
          title: Text(l.autoUpdateSubTitle),
          subtitle: Text(l.autoUpdateSubText),
        ),
        // #10 — интервал автообновления: поле (наше значение, приоритет выше
        // подписки) + галочка «брать из подписки».
        if (settings.autoUpdateEnabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Expanded(child: Text(l.autoUpdateIntervalLabel)),
              SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: '${settings.autoUpdateIntervalHours}',
                  enabled: !settings.autoUpdatePreferSubscription,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                      isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) {
                    final h = int.tryParse(v.trim());
                    if (h != null && h > 0) {
                      controller.update(
                          (s) => s.copyWith(autoUpdateIntervalHours: h));
                    }
                  },
                ),
              ),
            ]),
          ),
          SwitchListTile(
            dense: true,
            value: settings.autoUpdatePreferSubscription,
            onChanged: (v) => controller
                .update((s) => s.copyWith(autoUpdatePreferSubscription: v)),
            title: Text(l.autoUpdatePreferSub),
          ),
        ],
      ],
    );
  }
}

/// Включение TUN: сразу предлагаем настроить запуск без UAC (один раз),
/// иначе Windows будет спрашивать права при КАЖДОМ подключении.
Future<void> _enableTun(BuildContext context, SettingsController controller) async {
  final l = AppLocalizations.of(context);
  controller.update((s) => s.copyWith(captureMode: CaptureMode.tun));
  if (await TunScheduledTask.exists()) return;
  if (!context.mounted) return;

  final setup = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.tunUacTitle),
      content: Text(l.tunUacBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.tunUacLater),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.tunUacSetup),
        ),
      ],
    ),
  );
  if (setup != true) return;

  final ok = await TunScheduledTask.install();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(ok ? l.tunUacDone : l.tunUacFail),
  ));
}

// ── Захват трафика ───────────────────────────────────────────────────────────
class _CaptureSection extends StatelessWidget {
  final AppSettings settings;
  final SettingsController controller;
  const _CaptureSection({required this.settings, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l.sectionCapture),
        RadioListTile<CaptureMode>(
          value: CaptureMode.systemProxy,
          groupValue: settings.captureMode,
          onChanged: (v) => controller.update((s) => s.copyWith(captureMode: v)),
          title: Text(l.captureSystemProxy),
          subtitle: Text(l.captureSystemProxySub),
        ),
        RadioListTile<CaptureMode>(
          value: CaptureMode.tun,
          groupValue: settings.captureMode,
          onChanged: (v) => _enableTun(context, controller),
          title: Row(children: [
            Text(l.captureTun),
            const SizedBox(width: 8),
            _badge(context, l.captureTunBadgeUac),
            InfoTooltip(l.pingInfoTunStage),
          ]),
          subtitle: Text(l.captureTunSub),
        ),
        // #14 — всё, что относится к TUN, показываем ТОЛЬКО когда он выбран:
        // в режиме системного прокси эти настройки ни на что не влияют.
        if (settings.captureMode == CaptureMode.tun) ...[
          ListTile(
            dense: true,
            title: Text(l.tunProvider),
            trailing: const Text('wintun', textDirection: TextDirection.ltr),
          ),
          // Все параметры TUN/DNS/прав — на отдельном экране (их стало много).
          ListTile(
            dense: true,
            leading: const Icon(Icons.settings_ethernet),
            title: Text(l.tunRoutingTitle),
            subtitle: Text(l.tunRoutingSub(
                settings.tunStack.name, settings.tunMtu, _dnsShort(l, settings.dnsMode))),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TunSettingsScreen()),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.alt_route),
            title: Text(l.splitTunnelTitle),
            subtitle: Text(_splitLabel(l, settings)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SplitTunnelScreen()),
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              l.captureTunHint,
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ),
      ],
    );
  }

  static String _dnsShort(AppLocalizations l, DnsMode m) {
    switch (m) {
      case DnsMode.vpn:
        return l.dnsShortVpn;
      case DnsMode.system:
        return l.dnsShortSystem;
      case DnsMode.custom:
        return l.dnsShortCustom;
    }
  }

  String _splitLabel(AppLocalizations l, AppSettings settings) {
    final st = settings.splitTunnel;
    final modeLabel = splitModeLabel(l, st.mode);
    // «Все через VPN» — правила не применяются, счётчики не показываем.
    if (st.mode == SplitMode.all) return modeLabel;
    final a = st.apps.length, s = st.sites.length;
    final n = a + s;
    return '$modeLabel${n > 0 ? ' · ${l.splitRulesCount(n, a, s)}' : ''}';
  }
}

// ── Пинг ─────────────────────────────────────────────────────────────────────
/// Все четыре метода доступны для обеих фаз (#4.1).
class _PingSection extends StatelessWidget {
  final AppSettings settings;
  final SettingsController controller;
  const _PingSection({required this.settings, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l.sectionPing),
        SwitchListTile(
          dense: true,
          value: settings.pingTwoPhase,
          onChanged: (v) => controller.update((s) => s.copyWith(pingTwoPhase: v)),
          title: Row(children: [
            Expanded(child: Text(l.pingTwoPhaseTitle)),
            InfoTooltip(l.pingInfoTwoPhase),
          ]),
          subtitle: Text(settings.pingTwoPhase
              ? l.pingTwoPhaseSubOn
              : l.pingTwoPhaseSubOff),
        ),
        if (settings.pingTwoPhase) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(l.pingMethodCheck),
          ),
          _choice<bool>(
            context,
            current: settings.pingFallback == PingMethod.proxyHead ||
                settings.pingPrimary == PingMethod.proxyHead,
            options: const {false: 'GET', true: 'HEAD'},
            // TCP — первая фаза, фиксирована; выбор влияет только на метод проверки.
            onChanged: (head) => controller.update((s) => s.copyWith(
                  pingPrimary: PingMethod.tcp,
                  pingFallback:
                      head ? PingMethod.proxyHead : PingMethod.proxyGet,
                )),
          ),
          // «!» и для TCP (первая фаза), и для метода проверки — что проверяется.
          _methodLegend({
            'TCP': l.pingInfoTcp,
            'GET': l.pingInfoProxyGet,
            'HEAD': l.pingInfoProxyHead,
          }),
        ] else ...[
          // Галочка отжата — один метод на выбор (TCP/ICMP/GET/HEAD), как раньше.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(l.pingMethodPing),
          ),
          _choice<PingMethod>(
            context,
            current: settings.pingPrimary,
            options: const {
              PingMethod.tcp: 'TCP',
              PingMethod.icmp: 'ICMP',
              PingMethod.proxyGet: 'GET',
              PingMethod.proxyHead: 'HEAD',
            },
            onChanged: (m) => controller.update((s) => s.copyWith(pingPrimary: m)),
          ),
          _methodLegend({
            'TCP': l.pingInfoTcp,
            'ICMP': l.pingInfoIcmp,
            'GET': l.pingInfoProxyGet,
            'HEAD': l.pingInfoProxyHead,
          }),
        ],
        // #11 — объём пробы теста скорости (ПКМ по серверу → «Информация о сервере»).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Text(l.speedTestProbe),
            InfoTooltip(l.infoSpeedTest),
          ]),
        ),
        _choice<SpeedTestSize>(
          context,
          current: settings.speedTestSize,
          options: {
            SpeedTestSize.full: l.speedTestFull,
            SpeedTestSize.light: l.speedTestLight,
          },
          onChanged: (v) => controller.update((s) => s.copyWith(speedTestSize: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextFormField(
            initialValue: settings.testUrl,
            decoration: InputDecoration(
              labelText: l.testUrlLabel,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => controller.update((s) => s.copyWith(testUrl: v)),
          ),
        ),
      ],
    );
  }
}

/// Легенда методов: у каждого имени — своя «! info» рядом (#4/#4.1).
Widget _methodLegend(Map<String, String> methods) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    child: Wrap(
      spacing: 12,
      children: methods.entries
          .map((e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e.key, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
                  InfoTooltip(e.value, title: e.key),
                ],
              ))
          .toList(),
    ),
  );
}

Widget _choice<T>(
  BuildContext context, {
  required T current,
  required Map<T, String> options,
  required ValueChanged<T> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SegmentedButton<T>(
      segments: options.entries
          .map((e) => ButtonSegment<T>(value: e.key, label: Text(e.value)))
          .toList(),
      selected: {current},
      showSelectedIcon: false,
      onSelectionChanged: (sel) => onChanged(sel.first),
    ),
  );
}

/// Проверка обновлений приложения: статус + ручная проверка + переключатель.
class _AppUpdateTile extends StatefulWidget {
  const _AppUpdateTile();

  @override
  State<_AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends State<_AppUpdateTile> {
  bool _checking = false;
  String? _status;

  Future<void> _check() async {
    final l = AppLocalizations.of(context);
    final settings = context.read<SettingsController>().settings;
    setState(() {
      _checking = true;
      _status = null;
    });
    final release = await AppUpdate.check(endpoint: settings.appUpdateUrl);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (release == null) {
        _status = l.appUpdateServerUnavailable;
      } else if (release.isNewer) {
        _status = l.appUpdateAvailable(release.version);
      } else {
        _status = l.appUpdateLatest;
      }
    });
    if (release != null && release.isNewer && (release.downloadUrl ?? '').isNotEmpty) {
      if (!mounted) return;
      AppToast.show(
        context,
        l.appUpdateAvailable(release.version),
        actionLabel: l.appUpdateDownload,
        onAction: () => UrlOpener.open(release.downloadUrl!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    return Column(children: [
      SwitchListTile(
        dense: true,
        value: settings.appUpdateCheck,
        onChanged: (v) => controller.update((s) => s.copyWith(appUpdateCheck: v)),
        title: Row(children: [
          Expanded(child: Text(l.appUpdateCheckTitle)),
          InfoTooltip(l.infoAppUpdate),
        ]),
        subtitle: Text(_status ?? l.appUpdateManual),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextFormField(
              initialValue: settings.appUpdateUrl,
              decoration: InputDecoration(
                labelText: l.appUpdateEndpointLabel,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  controller.update((s) => s.copyWith(appUpdateUrl: v.trim())),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _checking ? null : _check,
            child: Text(_checking ? '…' : l.commonCheck),
          ),
        ]),
      ),
    ]);
  }
}
