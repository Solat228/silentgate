import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/platform/url_scheme_windows.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/settings_controller.dart';
import 'widgets/app_toast.dart';
import 'widgets/info_tooltip.dart';

/// Экран «URL-схемы» (по образцу Happ/v2raytun): что приложение понимает при
/// импорте и какими ссылками им можно управлять (подключить/переключить/обновить).
/// Строки копируются; управляющие схемы реально работают (см. AppState.handleIncomingUrl).
class UrlSchemesScreen extends StatefulWidget {
  const UrlSchemesScreen({super.key});

  @override
  State<UrlSchemesScreen> createState() => _UrlSchemesScreenState();
}

class _UrlSchemesScreenState extends State<UrlSchemesScreen> {
  bool? _registered; // silentgate:// (всегда должна быть включена)
  bool? _serverLinks; // перехват vless:// и т.п.

  @override
  void initState() {
    super.initState();
    UrlSchemeWindows.isRegistered()
        .then((v) => mounted ? setState(() => _registered = v) : null);
    UrlSchemeWindows.areServerSchemesRegistered()
        .then((v) => mounted ? setState(() => _serverLinks = v) : null);
  }

  Future<bool> _confirm(String title, String body, String okLabel) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true), child: Text(okLabel)),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.watch<SettingsController>();
    return Scaffold(
      appBar: AppBar(title: Text(l.urlSchemesTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ⚠️ ОБА тумблера — только Windows, и это не косметика.
          //
          // Регистрацию схем на Windows ведёт реестр, и `UrlSchemeWindows` на
          // других платформах возвращает false и не делает ничего. На Android
          // схемы объявлены в манифесте: `silentgate://` работает всегда, а
          // тумблер показывал её ВЫКЛЮЧЕННОЙ; выключение проводило пользователя
          // через грозное предупреждение, гасило тумблер — и ссылки продолжали
          // работать. Перехват `vless://…` там переключается через
          // `PackageManager` (alias в манифесте объявлен `enabled=false`), и это
          // ещё не сделано — тумблер вставал в «вкл», не меняя ничего.
          //
          // Сами схемы ниже по экрану остаются: они рабочие и на Android.
          if (!Platform.isAndroid && !Platform.isIOS) ...[
          // silentgate:// — включена всегда; выключение только с предупреждением.
          SwitchListTile(
            value: _registered ?? true,
            onChanged: _registered == null
                ? null
                : (v) async {
                    if (!v) {
                      final ok = await _confirm(
                        l.urlSchemeDisableTitle,
                        l.urlSchemeDisableBody,
                        l.urlSchemeDisableOk,
                      );
                      if (!ok) return;
                      await UrlSchemeWindows.unregister();
                    } else {
                      await UrlSchemeWindows.register();
                    }
                    if (mounted) setState(() => _registered = v);
                  },
            title: Row(children: [
              Expanded(child: Text(l.urlSchemeSilentgateTitle)),
              InfoTooltip(l.infoScheme),
            ]),
            subtitle: Text(l.urlSchemeSilentgateSub),
          ),
          // Перехват ссылок серверов — с предупреждением при включении.
          SwitchListTile(
            dense: true,
            value: _serverLinks ?? false,
            onChanged: _serverLinks == null
                ? null
                : (v) async {
                    if (v) {
                      final schemes = UrlSchemeWindows.serverSchemes
                          .map((s) => "$s://")
                          .join(", ");
                      final ok = await _confirm(
                        l.urlSchemeServerConfirmTitle,
                        l.urlSchemeServerConfirmBody(schemes),
                        l.urlSchemeServerConfirmOk,
                      );
                      if (!ok) return;
                      await UrlSchemeWindows.registerServerSchemes();
                    } else {
                      await UrlSchemeWindows.unregisterServerSchemes();
                    }
                    if (mounted) setState(() => _serverLinks = v);
                  },
            title: Text(l.urlSchemeServerTitle),
            subtitle: Text(l.urlSchemeServerSub),
          ),
          ],
          // Автоподключение после импорта — наша собственная настройка, платформы
          // не касается.
          SwitchListTile(
            dense: true,
            value: controller.settings.autoConnectAfterImport,
            onChanged: (v) => controller
                .update((s) => s.copyWith(autoConnectAfterImport: v)),
            title: Text(l.urlSchemeAutoConnect),
          ),

          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(l.urlSupportedImport,
                style: const TextStyle(fontSize: 12)),
          ),

          for (final group in _schemeGroups(l).entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(group.key.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  )),
            ),
            for (final e in group.value.entries) _SchemeRow(uri: e.key, desc: e.value),
          ],

          // Сноска для владельца панели — в самом низу экрана URL-схем.
          const Divider(),
          const _PanelResponseRuleNote(),
          const _Hysteria2Note(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Локализованные группы URL-схем: технические URI + переведённые описания.
Map<String, Map<String, String>> _schemeGroups(AppLocalizations l) => {
      l.urlGroupImport: {
        'silentgate://import?url=<${l.urlHintSubUrl}>': l.urlDescImportSub,
        'silentgate://import?config=<${l.urlHintServerLink}>':
            l.urlDescImportServer,
      },
      l.urlGroupControl: {
        'silentgate://connect': l.urlDescConnect,
        // Выбор конкретного сервера — единственный способ переключить его
        // снаружи, поэтому строка стоит сразу за обычным connect.
        l.urlSchemeConnectServer: l.urlDescConnectServer,
        'silentgate://disconnect': l.urlDescDisconnect,
        'silentgate://toggle': l.urlDescToggle,
        'silentgate://update': l.urlDescUpdate,
      },
    };

/// Сноска для ВЛАДЕЛЬЦА панели: чтобы приложение получало подписку в формате
/// XRAY_JSON (готовые конфиги), в Remnawave нужно добавить правило ответа,
/// сопоставляющее наш User-Agent. Обычному пользователю это не нужно —
/// об этом прямо и написано. Переехала сюда из «Представления панели».
class _PanelResponseRuleNote extends StatelessWidget {
  const _PanelResponseRuleNote();

  static const _rule = '''{
  "name": "SilentGate",
  "enabled": true,
  "operator": "AND",
  "conditions": [
    {
      "headerName": "user-agent",
      "operator": "CONTAINS",
      "value": "SilentGate",
      "caseSensitive": false
    }
  ],
  "responseType": "XRAY_JSON"
},''';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.admin_panel_settings_outlined,
                  size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.panelOwnerTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              l.panelOwnerBody,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: SelectableText(
                _rule,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12, height: 1.35),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: Text(l.panelOwnerCopy),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: _rule));
                  AppToast.copied(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Сноска про Hysteria2 — для пользователя И для владельца панели. Hysteria2
/// приходит ТОЛЬКО в формате XRAY_JSON (Remnawave <2.8.0 выкидывает его из
/// base64/CLASH/SINGBOX); именно поэтому важно правило Response Rules → XRAY_JSON.
class _Hysteria2Note extends StatelessWidget {
  const _Hysteria2Note();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.bolt_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.hy2NoteTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(l.hy2NoteBody,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Одна строка URL-схемы: моноширинный URI + описание + кнопка «копировать».
class _SchemeRow extends StatelessWidget {
  final String uri;
  final String desc;
  const _SchemeRow({required this.uri, required this.desc});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 3, 8, 3),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(uri,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 2),
                child: Text(desc, style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Копировать',
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: uri));
            AppToast.copied(context);
          },
        ),
      ]),
    );
  }
}
