
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/vpn_server.dart';
import '../core/singbox/exit_outbounds.dart';
import '../engine/engine_base.dart';
import '../core/net/api_ports.dart';
import '../core/settings/app_settings.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/app_state.dart';
import '../state/settings_controller.dart';
import 'widgets/app_toast.dart';
import 'widgets/sel_text.dart';
import 'widgets/info_tooltip.dart';

/// Экран «API для автоматизации».
///
/// ⚠️ ВЫНЕСЕН ИЗ НАСТРОЕК ОТДЕЛЬНЫМ ЭКРАНОМ по просьбе владельца: «для API
/// сделай отдельное меню, чтобы не мешало настройкам». Раздел занимал экран
/// целиком — тумблер, поле токена, таблица портов и список серверов с
/// чекбоксами, — и на широком окне вытеснял всё остальное. Образец ровно тот
/// же, что у URL-схем: в настройках остаётся строка со стрелкой.
///
/// ⚠️ Только Windows: сам сервер на Android не поднимается вовсе (см.
/// `AppState.applyApiSettings`), а видимый тумблер, который ничего не делает,
/// был бы обманом.
class ApiScreen extends StatelessWidget {
  const ApiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.watch<SettingsController>();
    return Scaffold(
      appBar: AppBar(title: Text(l.apiSectionTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _ApiBody(settings: controller.settings, controller: controller),
        ],
      ),
    );
  }
}

// ── API для автоматизации ────────────────────────────────────────────────────
/// Локальный HTTP-API (`core/net/api_server.dart`) для внешних скриптов —
/// например, Python-скрипта, который гоняет трафик через клиент и управляет
/// им. Раздел показывается ТОЛЬКО на Windows: сам сервер на Android не
/// поднимается вовсе (см. `AppState.applyApiSettings`), а видимый тумблер,
/// который ничего не делает, был бы обманом.
class _ApiBody extends StatelessWidget {
  final AppSettings settings;
  final SettingsController controller;
  const _ApiBody({required this.settings, required this.controller});

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
    // Тот же предикат, что решает это физически (`ExitOutbounds.build`), что
    // спрашивает `/v1/exits` и что красит плашку выхода в правиле
    // (`split_tunnel_screen`). Четыре места — один вопрос и один ответчик.
    //
    // ⚠️ РАНЬШЕ ЗДЕСЬ СПРАШИВАЛИ `SingboxOutboundFactory.supports`, и
    // панельный профиль «Авто» его ПРОХОДИЛ (его `protocol` — это протокол
    // первого outbound'а конфига, обычно `vless`). Чекбокс выглядел обычным,
    // порт публиковался, а выход собирался из одного узла профиля.
    final unsupported = !canBeExitServer(server);
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

/// Заголовок группы внутри экрана. Копия помощника из настроек: он там
/// приватный, а делать его общим ради одного вызова — лишняя связанность
/// между экраном и настройками.
Widget _sectionHeader(BuildContext context, String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Row(
      children: [
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
