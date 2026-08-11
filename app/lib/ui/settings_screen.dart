import 'dart:io';

import '../engine/probe_factory.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/i18n/enum_labels.dart';
import '../l10n/gen/app_localizations.dart';
import '../core/net/api_ports.dart';
import '../core/platform/device_id.dart';
import '../core/platform/interference_scanner.dart';
import '../core/platform/network_recovery.dart';
import '../core/platform/app_launcher.dart';
import '../core/platform/vpn_lockdown.dart';
import '../core/net/speed_test.dart';
import '../core/update/app_update.dart';
import '../core/models/vpn_server.dart';
import '../core/settings/app_settings.dart';
import '../core/settings/split_tunnel.dart';
import '../core/singbox/singbox_outbound_factory.dart';
import '../core/subscription/subscription_service.dart';
import '../core/platform/platform_services.dart';
import '../engine/engine_base.dart';
import '../state/app_state.dart';
import '../state/settings_controller.dart';
import 'logs_screen.dart';
import 'split_tunnel_screen.dart';
import 'tun_settings_screen.dart';
import 'url_schemes_screen.dart';
import 'widgets/app_toast.dart';
import 'widgets/geo_assets_tile.dart';
import 'widgets/info_tooltip.dart';
import 'widgets/sel_text.dart';
import 'widgets/language_button.dart';

/// Глобальный ключ раздела «Поддержка» — чтобы «перекинуть» сюда по кнопке
/// «Поддержка» из любого места (карточка подписки и т.п.) и прокрутить.
final GlobalKey supportSectionKey = GlobalKey();

/// Якорь строки гео-баз: на неё ведёт плашка с главного экрана.
final GlobalKey geoAssetsKey = GlobalKey();

class SettingsScreen extends StatefulWidget {
  /// Открыть настройки и сразу прокрутить к разделу «Поддержка».
  final bool scrollToSupport;

  /// Открыть настройки и подвести к строке гео-баз. Нужно плашке с главного
  /// экрана: сказать «скачайте в настройках» и бросить искать самому — то же
  /// самое, что промолчать.
  final bool scrollToGeo;
  const SettingsScreen(
      {super.key, this.scrollToSupport = false, this.scrollToGeo = false});

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
    if (widget.scrollToGeo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = geoAssetsKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              alignment: 0.3);
        }
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
          // «Восстановление сети» и «проверка помех» — про netsh, чужие
          // TUN-адаптеры и системный прокси Windows. На Android ни одного из
          // этих понятий нет: туннель рвётся системой сам, а перечислять чужие
          // процессы приложение не может.
          if (!Platform.isAndroid) ...[
            const Divider(),
            const _NetworkSection(),
          ],
          // Локальный API для скриптов (Python и т.п.). Работает ТОЛЬКО на
          // Windows — на Android слушатель не поднимается (см.
          // `AppState.applyApiSettings`), и видимый раздел, который ничего
          // не делает, был бы обманом.
          if (Platform.isWindows) ...[
            const Divider(),
            _ApiSection(settings: s, controller: controller),
          ],
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
                // заблокированным навсегда — гасим вместе. Вместе с ним гасим и
                // зависимый noRealIp: иначе он оставался включённым, продолжал
                // действовать и при этом ИСЧЕЗАЛ из настроек — снять его было
                // нечем.
                killSwitch: v ? s.killSwitch : false,
                noRealIp: v ? s.noRealIp : false,
              )),
          title: Row(children: [
            Expanded(child: Text(l.autoReconnectTitle)),
            InfoTooltip(l.infoAutoReconnect, title: l.autoReconnectTitle),
          ]),
          subtitle: Text(l.autoReconnectSub),
        ),
        // ⚠️ В режиме «Только прокси» kill switch смысла не имеет
        // (`AppSettings.killSwitchApplies`): удерживать он может только
        // трафик МАШИНЫ, а в этом режиме машина и так ходит мимо туннеля.
        // Тумблер, который виден и ничего не делает, хуже отсутствующего.
        if (settings.killSwitchApplies)
          SwitchListTile(
            value: settings.killSwitch,
            // Без автопереподключения восстанавливать нечего — переключатель неактивен.
            onChanged: settings.autoReconnect
                ? (v) {
                    controller.update((s) =>
                        s.copyWith(killSwitch: v, noRealIp: v ? s.noRealIp : false));
                    // ⚠️ Системный always-on НАДЁЖНЕЕ нашего kill switch и об этом
                    // надо сказать в момент, когда человек о защите и думает.
                    // Наш работает, только пока живо приложение; системный держит
                    // блокировку и когда оно убито, и при обновлении, и до первого
                    // запуска после перезагрузки. Предлагаем один раз, при
                    // включении, и не навязываем — просто открываем нужный экран.
                    if (v && Platform.isAndroid) _offerAlwaysOn(context);
                  }
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
        // Системный Always-on — надёжнее любого нашего kill switch: он держит
        // блокировку и когда приложение убито, и во время обновления, и до
        // первого запуска после перезагрузки. Наш собственный закрывает только
        // окно между попытками переподключения, поэтому они дополняют друг
        // друга, а не заменяют.
        // Раскладка уведомления. Переключатель заводился временным — на время
        // сравнения двух вариантов на живом телефоне; выбор сделан, и он стал
        // постоянной настройкой.
        if (Platform.isAndroid)
          SwitchListTile(
            value: settings.compactNotification,
            onChanged: (v) async {
              final state = context.read<AppState>();
              // Ждём запись: без await следующая строка читала бы прежнее
              // значение, и раскладка не менялась бы вовсе.
              await controller.update((s) => s.copyWith(compactNotification: v));
              await state.publishNotificationLayout(
                  settings: controller.settings);
            },
            title: Text(l.notifCompactTitle),
            subtitle: Text(l.notifCompactSub),
          ),
        // ⚠️ СИСТЕМНАЯ ЗАЩИТА — НЕ ТО ЖЕ САМОЕ, ЧТО НАШ KILL SWITCH.
        //
        // Наш держит трафик, пока жив наш сервис. Система убила процесс —
        // туннель снялся вместе с ним, и трафик пошёл открыто. Этот случай
        // закрывает только «Блокировать соединения без VPN» в настройках
        // Android, а включить её из приложения платформа запрещает.
        //
        // Поэтому здесь не просто ссылка, а СОСТОЯНИЕ: пользователь имеет право
        // видеть, защищён он на самом деле или только думает, что защищён.
        if (Platform.isAndroid) const _LockdownTile(),
        // Пароль на локальные прокси ядра. Общий для платформ.
        //
        // ⚠️ ПОЧЕМУ ЭТО ВООБЩЕ ВИДНО ПОЛЬЗОВАТЕЛЮ. Умолчание (пароль включён)
        // верное для всех, и трогать его не нужно. Но локальный прокси —
        // законный способ пустить в VPN стороннюю программу, и тому, кто так
        // делает, нужны предсказуемые логин с паролем вместо случайных.
        // Прятать такую возможность значит вынуждать выключать защиту целиком.
        SwitchListTile(
          value: settings.localProxyAuth,
          onChanged: (v) =>
              controller.update((s) => s.copyWith(localProxyAuth: v)),
          title: Row(children: [
            Expanded(child: Text(l.localProxyAuthTitle)),
            InfoTooltip(l.localProxyAuthInfo, title: l.localProxyAuthTitle),
          ]),
          subtitle: Text(!settings.localProxyAuth
              ? l.localProxyAuthOff
              : settings.captureMode == CaptureMode.systemProxy &&
                      !Platform.isAndroid
                  // ⚠️ Честно говорим, что настройка сейчас не действует.
                  // Молчание здесь означало бы «защита включена», хотя её нет.
                  ? l.localProxyAuthSystemProxy
                  : (settings.localProxyUser.trim().isEmpty ||
                          settings.localProxyPassword.isEmpty)
                      ? l.localProxyAuthRandom
                      : l.localProxyAuthCustom),
        ),
        if (settings.localProxyAuth)
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(l.localProxyCredsTitle),
            subtitle: Text(settings.localProxyUser.trim().isEmpty ||
                    settings.localProxyPassword.isEmpty
                ? l.localProxyCredsUnset
                : l.localProxyCredsUser(settings.localProxyUser)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editLocalProxyCreds(context, controller, settings),
          ),
        // «Не выходить под реальным IP» — только при включённом kill switch,
        // и только там, где kill switch вообще имеет смысл (не «Только прокси»).
        if (settings.killSwitch && settings.killSwitchApplies)
          SwitchListTile(
            value: settings.noRealIp,
            onChanged: (v) =>
                controller.update((s) => s.copyWith(noRealIp: v)),
            title: Text(l.noRealIpTitle),
            subtitle: Text(l.noRealIpSub),
          ),
        // ⚠️ ЭТОГО ПЕРЕКЛЮЧАТЕЛЯ ЗДЕСЬ НЕ БЫЛО, И ЭТО МЕНЯЛО МАРШРУТЫ ВСЕМ.
        //
        // Поле `myRulesOverridePanel` завели вместе с переведёнными на десять
        // языков подписями, движок его читает — а контрол забыли. Умолчание
        // `true`, изменить нечем, значит условие реврайта панельных правил
        // (`engine_base`: mode == all || noRealIp || myRulesOverridePanel) было
        // истинным ВСЕГДА: у каждого пользователя панельного профиля российские
        // сайты уходили кругом через зарубежный сервер, и объяснения этому в
        // настройках не находилось. Заодно два первых слагаемых условия были
        // мертвы — любой их разбор вводил бы в заблуждение.
        SwitchListTile(
          value: settings.myRulesOverridePanel,
          onChanged: (v) =>
              controller.update((s) => s.copyWith(myRulesOverridePanel: v)),
          title: Text(l.settingsMyRulesOverridePanel),
          subtitle: Text(l.settingsMyRulesOverridePanelSub),
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
                          // Первой строкой — ПРОГРАММА, если опознана: имя
                          // адаптера («happ-tun») пользователю ничего не
                          // говорит, а закрывать он будет именно программу.
                          title: Text(i.appName ?? i.name,
                              textDirection: TextDirection.ltr),
                          subtitle: Text(
                              i.appName == null
                                  ? i.detail
                                  : [i.name, i.appPath ?? '']
                                      .where((e) => e.isNotEmpty)
                                      .join(' · '),
                              textDirection: TextDirection.ltr,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: i.closable
                              ? TextButton(
                                  onPressed: () async {
                                    await InterferenceScanner.kill(i.pid!);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                  child: Text(l.errorCloseApp(i.appName!)),
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
    final effective = SubscriptionService.defaultUserAgent;
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
          subtitle: SelectableText(effective, textDirection: TextDirection.ltr),
          trailing: IconButton(
            tooltip: l.commonCopy,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: effective)),
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
    final xray = await platform.coreVersions.xray();
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
                  // На Android ядра ВСТРОЕНЫ в APK — прежний текст про
                  // «отдельные процессы» там просто неверен.
                  subtitle: Text(Platform.isAndroid
                      ? l.aboutThirdPartySubEmbedded
                      : l.aboutThirdPartySub),
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

  /// Описание проблемы словами пользователя.
  ///
  /// На Windows его вписывают прямо в открывшийся txt — там файл виден в
  /// Проводнике. На Android открывать нечего: отчёт уезжает в буфер обмена
  /// целиком, поэтому описание собираем ДО генерации, иначе в поддержку
  /// приходит один голый лог без единого слова о проблеме.
  final _description = TextEditingController();
  bool _descriptionMissing = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final l = AppLocalizations.of(context);
    // Пустое описание пропускаем только там, где его можно вписать в сам файл.
    final described = _description.text.trim().isNotEmpty;
    if (!described && _descriptionRequired) {
      setState(() => _descriptionMissing = true);
      return;
    }
    final state = context.read<AppState>();
    final settings = context.read<SettingsController>().settings;
    final server = state.selectedServer;
    // Локализованная шапка отчёта (только её и переводим — техчасть ниже как есть).
    final header = (StringBuffer()
          ..writeln('==================================================')
          ..writeln('  ${l.reportTitle}')
          ..writeln('==================================================')
          ..writeln()
          // Описание, введённое в приложении, идёт первым — читающему
          // обращение не нужно искать его среди сотен строк лога. Если поля не
          // было (десктоп), остаётся прежняя болванка для заполнения в файле.
          ..writeln(described ? '[${l.supportDescriptionSection}]' : l.reportDescribeHere)
          ..writeln()
          ..writeln(described
              ? _description.text.trim()
              : '  ${l.reportWhatDid}\n'
                  '  ${l.reportWhatExpected}\n'
                  '  ${l.reportWhatHappened}\n'
                  '  ${l.reportWhenStarted}')
          ..writeln()
          ..writeln(l.supportNoScreenshots)
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
      final path = await platform.support.generate(settings: settings, ctx: ctx);
      // Строгий порядок: сперва открыть папку, затем сам txt-файл (см. reveal).
      await platform.support.reveal(path);
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

  /// Поле описания ОБЯЗАТЕЛЬНО там, где готовый отчёт нельзя дописать руками:
  /// он уходит файлом через «Поделиться» как есть.
  bool get _descriptionRequired => Platform.isAndroid;

  /// А ПОКАЗЫВАЕМ его везде.
  ///
  /// ⚠️ На Windows поля не было вовсе: считалось, что человек допишет описание
  /// прямо в открытом txt. На деле файл открывается уже после генерации, и
  /// владелец присылал отчёты с нетронутой болванкой «Что делали: / Что
  /// ожидали:». Спрашивать надо ТАМ, ГДЕ ЧЕЛОВЕК ЕЩЁ В КОНТЕКСТЕ, — то есть в
  /// диалоге, до генерации. Обязательным на десктопе не делаем: дописать файл
  /// руками там всё ещё можно, и запрет мешал бы быстрой отправке лога.
  bool get _descriptionShown => true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    // Имя сервиса VPN (владельца подписки) — для подписи «кому отправить».
    final serviceName = (state.info.title ?? '').trim();
    final vpnSupport = (state.info.supportUrl ?? '').trim();
    final done = _path != null;

    return AlertDialog(
      // ⚠️ Без этого диалог с полем ввода рвётся при клавиатуре: Dialog
      // ужимается, а Column внутри — нет. Именно так ломался отчёт поддержки.
      scrollable: true,
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
              // На Android отчёт уходит файлом через системное «Поделиться»,
              // на Windows открывается папка и сам файл. Инструкция, зовущая
              // искать папку на телефоне, отправляет человека в никуда.
              Text(Platform.isAndroid ? l.supportBullet2Android : l.supportBullet2),
              // Поле описания — там, где готовый отчёт нельзя дописать руками
              // (Android: он копируется в буфер целиком и уходит как есть).
              // Без него в поддержку приезжает голый лог без слова о проблеме.
              if (_descriptionShown) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) {
                    if (_descriptionMissing) {
                      setState(() => _descriptionMissing = false);
                    }
                  },
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l.supportDescribeLabel,
                    hintText: l.supportDescribeHint,
                    errorText:
                        _descriptionMissing ? l.supportDescribeRequired : null,
                  ),
                ),
                const SizedBox(height: 8),
                // Скриншоты в текстовый отчёт не вставить — говорим об этом
                // сразу, а не после того, как пользователь попробует.
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l.supportNoScreenshots,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ]),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(l.supportError(_error!),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12)),
              ],
            ] else ...[
              Text(Platform.isAndroid ? l.supportDoneTextAndroid : l.supportDoneText),
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
          // На Windows отчёт «показывается» — открывается папка с выделенным
          // файлом. На Android показывать нечего: приватный каталог приложения
          // недоступен файловым менеджерам, поэтому текст отчёта копируется в
          // буфер обмена и сразу вставляется в чат поддержки.
          TextButton.icon(
            icon: Icon(
                Platform.isAndroid ? Icons.copy_all : Icons.folder_open,
                size: 18),
            onPressed: () async {
              await platform.support.reveal(_path!);
              if (Platform.isAndroid && context.mounted) {
                AppToast.copied(context, message: l.supportReportCopied);
              }
            },
            label: Text(
                Platform.isAndroid ? l.supportCopyReport : l.supportShowOnPc),
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

/// Список стороннего кода в поставке.
///
/// ⚠️ Тексты лицензий ЕДУТ В САМОМ ПРИЛОЖЕНИИ (`assets/licenses/`), а не
/// «лежат рядом в папке licenses»: у APK такой папки нет. На Android ядра
/// встроены внутрь (`libcores.so`), и sing-box под GPL-3.0 — передавать текст
/// лицензии вместе с бинарником обязательно. Поэтому диалог показывает не
/// только перечисление, но и сами тексты.
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
                Platform.isAndroid ? l.thirdPartyBodyEmbedded : l.thirdPartyBody,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final e in const {
                'NOTICE': 'assets/licenses/NOTICE.txt',
                'GPL-3.0': 'assets/licenses/GPL-3.0.txt',
                'MPL-2.0': 'assets/licenses/MPL-2.0.txt',
              }.entries)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: Text(e.key),
                    onPressed: () => _showLicenseText(context, e.key, e.value),
                  ),
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

/// Полный текст лицензии из ассетов. Читается по требованию: GPL-3.0 — 34 КБ,
/// держать это в памяти постоянно незачем.
void _showLicenseText(BuildContext context, String title, String asset) {
  final l = AppLocalizations.of(context);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        height: 420,
        child: FutureBuilder<String>(
          future: rootBundle.loadString(asset),
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              child: SelectableText(
                snap.data ?? '',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(l.commonClose)),
      ],
    ),
  );
}


/// Открыть системный раздел VPN — там включается Always-on и «блокировать
/// соединения без VPN». Прямого экрана «Always-on для приложения X» в Android
/// нет, поэтому ведём в общий раздел.
Future<void> _openVpnSettings(BuildContext context) async {
  final l = AppLocalizations.of(context);
  var ok = false;
  try {
    ok = await const MethodChannel('lol.silentgate/device')
            .invokeMethod<bool>('openVpnSettings') ??
        false;
  } catch (_) {}
  if (!ok && context.mounted) {
    AppToast.show(context, l.alwaysOnSub, kind: ToastKind.info);
  }
}

Widget _sectionHeader(BuildContext context, String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Row(
      children: [
        // Заголовок не лежит в кликабельной строке, поэтому его безопасно
        // делать выделяемым: тапы у соседних настроек не пострадают.
        SelText(title,
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
        // Трея на Android нет: приложение сворачивается системой, а VPN
        // продолжает жить в foreground-сервисе с постоянной нотификацией —
        // она и играет роль значка в трее.
        if (!Platform.isAndroid)
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
  if (await platform.privileges.isConfigured()) return;
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

  final ok = await platform.privileges.configure();
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
        // Выбора режима на Android нет: глобального системного прокси там не
        // существует, весь трафик идёт через VpnService. Показывать
        // переключатель с единственным вариантом незачем.
        if (!Platform.isAndroid) ...[
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
        ],
        // Задача 3b/7: режим для локального API — ядро поднято, порты
        // серверов слушают, но ни системный прокси, ни TUN не ставятся.
        // Не нужен UAC (в отличие от TUN выше), поэтому смена режима — сразу.
        //
        // ⚠️ ГЕЙТ БУКВАЛЬНО `Platform.isWindows`, А НЕ УНАСЛЕДОВАННЫЙ
        // `!Platform.isAndroid` соседних пунктов выше. Оба сегодня совпадают
        // (кроме Windows/Android в дереве никого нет), но соседний гейт
        // кодирует чужое допущение «не Android = Windows» — оно перестанет
        // быть верным в день, когда появится iOS-движок (заглушки
        // `Platform.isIOS` уже встречаются рядом, см. `tunRoutingSub` ниже).
        // Наш контрол работает ТОЛЬКО там, где поднимается локальный API
        // (`AppState.applyApiSettings`, тоже `Platform.isWindows`), поэтому
        // берём тот же буквальный гейт, а не молчаливо наследуем чужой.
        // Секцию «Захват» в остальном не трогаем — это не наша зона.
        if (Platform.isWindows)
          RadioListTile<CaptureMode>(
            value: CaptureMode.proxyOnly,
            groupValue: settings.captureMode,
            onChanged: (v) => controller.update((s) => s.copyWith(captureMode: v)),
            title: Text(l.captureProxyOnly),
            subtitle: Text(l.captureProxyOnlySub),
          ),
        // #14 — всё, что относится к TUN, показываем ТОЛЬКО когда он выбран:
        // в режиме системного прокси эти настройки ни на что не влияют.
        // На Android туннель — единственный режим, поэтому показываем всегда.
        if (Platform.isAndroid || settings.captureMode == CaptureMode.tun) ...[
          // Драйвер туннеля — понятие Windows (wintun). На Android туннель даёт
          // сама система через VpnService, выбирать нечего.
          if (!Platform.isAndroid)
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
            // ⚠️ Стек на Android не выбирается: он форсится в gvisor
            // (SingboxConfigBuilder), а переключатель с экрана TUN убран —
            // system/mixed там не форвардят TCP без прав, и получалось
            // «Подключено» с мёртвым интернетом. Показывать здесь «auto» из
            // настроек значило сообщать пользователю неверный факт о его же
            // туннеле и посылать искать переключатель, которого нет.
            subtitle: Text(l.tunRoutingSub(
                (Platform.isAndroid || Platform.isIOS)
                    ? 'gvisor'
                    : settings.tunStack.name,
                settings.tunMtu,
                _dnsShort(l, settings.dnsMode))),
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
          // Гео-базы нужны только там, где их нет в поставке. На Windows они
          // приезжают вместе с ядром, и кнопка была бы обманкой.
          if (Platform.isAndroid) GeoAssetsTile(key: geoAssetsKey),
        ] else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              l.captureTunHint,
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ),
          // Задача 3b: в «Только прокси» раздельное туннелирование не
          // действует ни для одной программы машины (ничего не
          // перехватывается), поэтому тумблер виден ТОЛЬКО в этом режиме —
          // иначе он был бы виден и ничего не делал бы.
          // ⚠️ `Platform.isWindows` буквально, как и у пункта режима выше —
          // тот же довод: это НАШ контрол, а не унаследованный `else`
          // соседней секции.
          if (Platform.isWindows &&
              settings.captureMode == CaptureMode.proxyOnly) ...[
            SwitchListTile(
              value: settings.applyRulesInProxyOnly,
              onChanged: (v) => controller
                  .update((s) => s.copyWith(applyRulesInProxyOnly: v)),
              title: Text(l.apiRulesInProxyOnly),
              subtitle: Text(l.apiRulesInProxyOnlySub),
            ),
            // ⚠️ БЕЗ ЭТОЙ СТРОКИ ТУМБЛЕР ВЁЛ В НИКУДА. Он оперирует списком
            // «Блок», а список редактируется на экране раздельного
            // туннелирования — который в этом режиме из настроек НЕ ОТКРЫТЬ:
            // пункт «Раздельное туннелирование» живёт в ветке `captureMode ==
            // tun` выше. Человек включал галочку и не мог завести ни одного
            // правила. (Сам экран в этом режиме больше не заблокирован — см.
            // `split_tunnel_screen.dart`.)
            ListTile(
              dense: true,
              leading: const Icon(Icons.alt_route),
              title: Text(l.splitTunnelTitle),
              subtitle: Text(l.apiRulesInProxyOnlyEdit),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SplitTunnelScreen()),
              ),
            ),
          ],
        ],
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

// ── API для автоматизации ────────────────────────────────────────────────────
/// Локальный HTTP-API (`core/net/api_server.dart`) для внешних скриптов —
/// например, Python-скрипта, который гоняет трафик через клиент и управляет
/// им. Раздел показывается ТОЛЬКО на Windows: сам сервер на Android не
/// поднимается вовсе (см. `AppState.applyApiSettings`), а видимый тумблер,
/// который ничего не делает, был бы обманом.
class _ApiSection extends StatelessWidget {
  final AppSettings settings;
  final SettingsController controller;
  const _ApiSection({required this.settings, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Список серверов подписки — источник для чекбоксов «выдать порт». Как и
    // выбор сервера для правила раздельного туннелирования (split_tunnel_screen),
    // берём его нефильтрованным: тот же список видит пользователь на главном.
    final state = context.watch<AppState>();
    final servers = state.servers;
    final scheme = Theme.of(context).colorScheme;
    // ⚠️ ПОРТОВ ВЫХОДОВ В ЭТОМ РЕЖИМЕ НЕ СУЩЕСТВУЕТ, А РАЗДЕЛ ИХ ПРЕДЛАГАЛ.
    // Инбаунды живут в TUN-конфиге либо в маршрутизаторе выходов «Только
    // прокси»; при системном прокси (умолчание на Windows!) нет ни того, ни
    // другого. Раздел при этом давал включить API, отметить серверы, а
    // `/v1/exits` называл номера портов — и все соединения получали отказ.
    // `docs/API.md` это описывал честно, интерфейс — ни словом.
    final exitPortsExist = ApiPorts.exitPortsExistIn(settings.captureMode);
    // Отказ подъёма управляющего порта. Показывается только при заданном
    // токене: пустой токен — это «канал выключен», и у него своя строка.
    final conflict = state.apiPortConflict;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l.apiSectionTitle),
        SwitchListTile(
          value: settings.apiEnabled,
          onChanged: (v) => controller.update((s) => s.copyWith(apiEnabled: v)),
          title: Text(l.apiEnableTitle),
          subtitle: Text(l.apiEnableSub(ApiPorts.control)),
        ),
        if (settings.apiEnabled) ...[
          // Порт занят — тумблер включён, а слушателя нет. Раньше это жило
          // ТОЛЬКО в журнале: раздел выглядел рабочим, токен показан, кнопка
          // «Скопировать пример» на месте, а скрипт получал отказ соединения
          // и не мог понять почему.
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
          // Токен — он же пароль локальных портов API. Пустой токен означает
          // «канал не поднимается» (см. `LocalApiServer.start`), поэтому даём
          // сразу и увидеть его, и сгенерировать заново.
          ListTile(
            dense: true,
            leading: const Icon(Icons.vpn_key_outlined),
            title: Row(children: [
              Expanded(child: Text(l.apiTokenTitle)),
              InfoTooltip(l.apiTokenWarning, title: l.apiTokenTitle),
            ]),
            subtitle: settings.apiToken.isEmpty
                ? Text(l.apiTokenUnset)
                : SelectableText(settings.apiToken,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settings.apiToken.isNotEmpty)
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
                  // Тот же генератор, что и у паролей локальных прокси/Clash
                  // API — общая точка правды, а не свой велосипед.
                  onPressed: () => controller.update((s) =>
                      s.copyWith(apiToken: VpnEngineBase.randomSecret())),
                ),
              ],
            ),
          ),
          // Режим захвата, в котором портов выходов физически нет. Плашка
          // стоит НАД списком серверов: она объясняет, почему галочки ниже
          // сейчас ни к чему не приведут.
          if (!exitPortsExist)
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
                    child: SelText(l.apiCaptureModeWarning(ApiPorts.control),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ]),
              ),
            ),
          // Серверы с отдельным портом — только если подписка вообще что-то
          // дала: пустой список чекбоксов под заголовком выглядел бы поломкой.
          if (servers.isNotEmpty) ...[
            ListTile(
              dense: true,
              title: Text(l.apiExitsTitle),
              subtitle: Text(l.apiExitsSub),
            ),
            for (final srv in servers)
              // ⚠️ СЕРВЕР, ИЗ КОТОРОГО ВЫХОД НЕ СОБИРАЕТСЯ, ОТМЕЧАЛСЯ БЕЗ
              // ЕДИНОГО СЛОВА. Панельный профиль «Авто» — готовый конфиг Xray
              // целиком, а порты выходов разводит sing-box; его же фабрика не
              // умеет часть протоколов. Такой сервер порта не получит
              // (`ExitOutbounds.build` его пропускает, `/v1/exits` его теперь
              // и не публикует).
              //
              // ⚠️ ДЕЛАЕМ ТАК ЖЕ, КАК В СОСЕДНЕЙ ПОДСИСТЕМЕ, А НЕ ТРЕТЬИМ
              // СПОСОБОМ: серый + тултип с той же строкой, что у выбора
              // сервера для правила (`split_tunnel_screen._ServerBadge`,
              // ключ `exitServerUnsupported`). Выбор при этом НЕ запрещаем —
              // решение владельца от 07.08.2026: разрешать, но предупреждать.
              _ApiExitCheckbox(
                server: srv,
                checked: settings.apiExitServerKeys.contains(srv.key),
                onChanged: (v) => controller.update((s) => s.copyWith(
                    apiExitServerKeys: v == true
                        ? [...s.apiExitServerKeys, srv.key]
                        : s.apiExitServerKeys
                            .where((k) => k != srv.key)
                            .toList())),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              l.apiPortsHint(
                  ApiPorts.control, ApiPorts.direct, ApiPorts.firstServer),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.code),
            title: Text(l.apiCopyPythonExample),
            onTap: () {
              Clipboard.setData(ClipboardData(text: _pythonExample(settings)));
              AppToast.copied(context);
            },
          ),
        ],
      ],
    );
  }

  /// Готовый фрагмент для Python — с уже подставленными портом и токеном,
  /// чтобы скрипт заработал сразу после вставки, без правки руками.
  static String _pythonExample(AppSettings s) {
    final token = s.apiToken.isEmpty ? '<токен>' : s.apiToken;
    return 'import requests\n'
        '\n'
        'BASE = "http://127.0.0.1:${ApiPorts.control}"\n'
        'HEADERS = {"Authorization": "Bearer $token"}\n'
        '\n'
        'status = requests.get(f"{BASE}/v1/status", headers=HEADERS).json()\n'
        'print(status)\n'
        '\n'
        'requests.post(f"{BASE}/v1/connect", headers=HEADERS, json={"auto": True})\n';
  }
}

/// Чекбокс «выдать порт» одному серверу.
///
/// Отдельным виджетом — ради тултипа: `CheckboxListTile` не умеет объяснять
/// сам себя, а объяснение здесь обязательно (см. комментарий у места вызова).
class _ApiExitCheckbox extends StatelessWidget {
  final VpnServer server;
  final bool checked;
  final ValueChanged<bool?> onChanged;

  const _ApiExitCheckbox({
    required this.server,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Тот же предикат, что решает это физически (`ExitOutbounds.build`) и что
    // спрашивает `/v1/exits`. Три места — один вопрос и один ответчик.
    final unsupported = !SingboxOutboundFactory.supports(server);
    final tile = CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: checked,
      title: Text(
        server.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unsupported
            ? TextStyle(color: Theme.of(context).disabledColor)
            : null,
      ),
      secondary: unsupported
          ? Icon(Icons.help_outline,
              size: 16, color: Theme.of(context).disabledColor)
          : null,
      onChanged: onChanged,
    );
    if (!unsupported) return tile;
    return Tooltip(
      message: l.exitServerUnsupported(server.displayName),
      child: tile,
    );
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
          // ICMP требует сырых сокетов (нет без root), GET/HEAD — проброс-харнесс
          // (второй экземпляр ядра рядом с живым туннелем не поднять). Показывать
          // методы, которые заведомо не отработают, нечестно.
          _choice<PingMethod>(
            context,
            current: settings.pingPrimary,
            options: {
              PingMethod.tcp: 'TCP',
              if (icmpSupported) PingMethod.icmp: 'ICMP',
              if (proxyProbeSupported) ...{
                PingMethod.proxyGet: 'GET',
                PingMethod.proxyHead: 'HEAD',
              },
            },
            onChanged: (m) => controller.update((s) => s.copyWith(pingPrimary: m)),
          ),
          _methodLegend({
            'TCP': l.pingInfoTcp,
            if (icmpSupported) 'ICMP': l.pingInfoIcmp,
            if (proxyProbeSupported) ...{
              'GET': l.pingInfoProxyGet,
              'HEAD': l.pingInfoProxyHead,
            },
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
    final release = await AppUpdate.check(endpoint: settings.effectiveAppUpdateUrl);
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

/// Разовое предложение включить системный always-on VPN (Android).
///
/// Показывается при включении kill switch: именно тогда человек думает о том,
/// чтобы трафик не утёк, и именно тогда уместно сказать, что у системы есть
/// более сильный механизм. Отказ ничего не ломает — наш kill switch работает.
Future<void> _offerAlwaysOn(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.alwaysOnTitle),
      content: Text(l.alwaysOnSub),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonCancel)),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.commonOpen)),
      ],
    ),
  );
  if (go == true && context.mounted) await _openVpnSettings(context);
}

/// Диалог «свои логин и пароль локального прокси».
///
/// ⚠️ Пустые поля — это НЕ ошибка, а осознанный выбор «пусть будет случайный».
/// Поэтому кнопка сохранения активна всегда, а очистка полей возвращает режим
/// посессионного пароля. Требовать заполнения значило бы навязывать худший
/// вариант: заданный вручную пароль ложится на диск и переживает перезапуск.
Future<void> _editLocalProxyCreds(BuildContext context,
    SettingsController controller, AppSettings settings) async {
  final user = TextEditingController(text: settings.localProxyUser);
  final pass = TextEditingController(text: settings.localProxyPassword);
  var obscure = true;
  // Локализация берётся ОДИН раз здесь: внутри builder контекст другой,
  // а строка нужна и заголовку, и полям.
  final l = AppLocalizations.of(context);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(l.localProxyDialogTitle),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SelText(l.localProxyDialogBody),
          const SizedBox(height: 12),
          TextField(
            controller: user,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
                labelText: l.localProxyFieldUser,
                hintText: l.localProxyFieldHint),
          ),
          TextField(
            controller: pass,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.localProxyFieldPassword,
              hintText: l.localProxyFieldHint,
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setLocal(() => obscure = !obscure),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx).commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(ctx).commonDone)),
        ],
      ),
    ),
  );
  if (saved != true) return;
  await controller.update((s) => s.copyWith(
        localProxyUser: user.text.trim(),
        localProxyPassword: pass.text,
      ));
}

/// Строка «Системная защита»: показывает РЕАЛЬНОЕ состояние, а не ссылку.
///
/// ⚠️ ЗАЧЕМ СОСТОЯНИЕ, А НЕ ПРОСТО КНОПКА «ОТКРЫТЬ НАСТРОЙКИ».
///
/// Наш kill switch на Android настоящий: ядро перезагружается конфигом-
/// заглушкой, и трафик умирает в `reject`. Но живёт это ровно столько, сколько
/// живёт наш сервис. Система убила процесс — туннель снялся вместе с ним, и
/// трафик пошёл открыто. Закрывает такой случай только сама Android, а включить
/// её настройку из приложения платформа запрещает намеренно.
///
/// Владелец сформулировал проблему точно: «неизвестно, работает или нет, без
/// настроек в самом телефоне». Значит показывать надо факт, а не намёк.
class _LockdownTile extends StatefulWidget {
  const _LockdownTile();

  @override
  State<_LockdownTile> createState() => _LockdownTileState();
}

class _LockdownTileState extends State<_LockdownTile> with WidgetsBindingObserver {
  VpnLockdown _state = VpnLockdown.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Пользователь уходил в системные настройки и вернулся — перечитываем.
    // Без этого строка показывала бы старое состояние до перезапуска, и
    // человек, только что включивший защиту, видел бы «выключена».
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final st = await VpnLockdown.query();
    if (mounted) setState(() => _state = st);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final st = _state;
    final l = AppLocalizations.of(context);

    final (IconData icon, Color color, String title, String sub) = switch (st) {
      // Полная защита: и постоянная VPN, и блокировка без неё.
      _ when st.fullyProtected => (
          Icons.verified_user,
          scheme.primary,
          l.lockdownOnTitle,
          l.lockdownOnSub
        ),
      // Назначены постоянной VPN, но блокировки нет — половина дела.
      _ when st.supported && st.alwaysOn => (
          Icons.gpp_maybe,
          scheme.tertiary,
          l.lockdownHalfTitle,
          l.lockdownHalfSub
        ),
      // Знаем точно, что защиты нет.
      _ when st.supported => (
          Icons.gpp_bad,
          scheme.error,
          l.lockdownOffTitle,
          l.lockdownOffSub
        ),
      // ⚠️ Не знаем — так и говорим. Зелёная птица здесь была бы враньём.
      _ => (
          Icons.help_outline,
          scheme.outline,
          l.lockdownUnknownTitle,
          l.lockdownUnknownSub
        ),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(sub),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () async {
        final ok = await VpnLockdown.openSettings();
        if (!context.mounted) return;
        if (!ok) {
          // Экрана нет — бывает на прошивках. Молча ничего не делать хуже:
          // пользователь решит, что сломалась кнопка.
          AppToast.show(
            context,
            AppLocalizations.of(context).lockdownOpenFailed,
            kind: ToastKind.error,
          );
        }
      },
    );
  }
}
