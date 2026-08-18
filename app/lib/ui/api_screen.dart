
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
          _ApiTokenTile(settings: settings, controller: controller),
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
          // Памятка с ЖИВЫМИ значениями — см. `_ApiCheatSheet`.
          _ApiCheatSheet(settings: settings, servers: servers),
          ListTile(
            dense: true,
            leading: const Icon(Icons.terminal),
            title: Text(l.apiCopyCurlExample),
            onTap: () {
              Clipboard.setData(ClipboardData(text: _curlExample(settings)));
              AppToast.copied(context);
            },
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

  /// Пример на curl — с уже подставленными портом и токеном.
  ///
  /// ⚠️ ТОКЕН В БУФЕР — ЭТО НЕ ТО ЖЕ, ЧТО ТОКЕН НА ЭКРАНЕ. На экране он спрятан
  /// за кнопкой «показать» (плечо через чужой взгляд и скриншот), а копирование
  /// — осознанное действие самого человека, и пример без токена пришлось бы
  /// править руками, то есть он не пример.
  ///
  /// Кавычки одинарные — как в `docs/API.md`: пример писан под bash/Git Bash. В
  /// `cmd.exe` их придётся заменить на двойные с экранированием, и врать про
  /// это незачем.
  static String _curlExample(AppSettings s) {
    final token = s.apiToken.isEmpty ? '<токен>' : s.apiToken;
    const base = 'http://127.0.0.1:${ApiPorts.control}';
    return '# Состояние движка\n'
        'curl -s $base/v1/status -H "Authorization: Bearer $token"\n'
        '\n'
        '# Какие порты выходов раскладка обещает\n'
        'curl -s $base/v1/exits -H "Authorization: Bearer $token"\n'
        '\n'
        '# Подключиться «Авто» (на живом канале — сменить сервер)\n'
        'curl -s -X POST $base/v1/connect '
        '-H "Authorization: Bearer $token" '
        '-H "Content-Type: application/json" '
        "-d '{\"auto\": true}'\n";
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

/// Строка токена: показать/скрыть, скопировать, перевыпустить.
///
/// ⚠️ ТОКЕН НЕ ПОКАЗЫВАЕТСЯ САМ ПО СЕБЕ. Раньше он лежал на экране открытым
/// текстом: экран API открывают, чтобы посмотреть порты и скопировать пример, —
/// и вместе с ними в кадр попадал пароль ко ВСЕМУ каналу (он же пароль каждого
/// порта выхода). Скриншот в поддержку, демонстрация экрана, чужой взгляд
/// через плечо — три обычных способа отдать его даром. Копирование при этом
/// работает и со скрытым токеном: чтобы вставить его в скрипт, видеть его
/// глазами не нужно.
class _ApiTokenTile extends StatefulWidget {
  final AppSettings settings;
  final SettingsController controller;
  const _ApiTokenTile({required this.settings, required this.controller});

  @override
  State<_ApiTokenTile> createState() => _ApiTokenTileState();
}

class _ApiTokenTileState extends State<_ApiTokenTile> {
  /// Показ живёт в состоянии ЭКРАНА, а не в настройках: уход с экрана прячет
  /// токен обратно. Настройка «показывать всегда» означала бы, что однажды
  /// нажатая кнопка светит паролем во всех будущих сессиях.
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = widget.settings;
    final empty = settings.apiToken.isEmpty;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.vpn_key_outlined),
      title: Row(children: [
        Expanded(child: Text(l.apiTokenTitle)),
        InfoTooltip(l.apiTokenWarning, title: l.apiTokenTitle),
      ]),
      subtitle: empty
          ? Text(l.apiTokenUnset)
          : (_shown
              ? SelectableText(settings.apiToken,
                  textDirection: TextDirection.ltr,
                  style:
                      const TextStyle(fontSize: 12, fontFamily: 'monospace'))
              // Длина точек НЕ равна длине токена: маска, выдающая длину
              // секрета, — это подсказка тому, кто его подбирает.
              : Text('${'•' * 12}  ${l.apiTokenHidden}',
                  style: const TextStyle(fontSize: 12))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!empty)
            IconButton(
              key: const Key('apiTokenReveal'),
              tooltip: _shown ? l.apiTokenHide : l.apiTokenShow,
              icon: Icon(
                  _shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18),
              onPressed: () => setState(() => _shown = !_shown),
            ),
          if (!empty)
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
            onPressed: () {
              // Новый токен прячем обратно: перевыпуск — не просьба показать.
              setState(() => _shown = false);
              widget.controller.update(
                  (s) => s.copyWith(apiToken: VpnEngineBase.randomSecret()));
            },
          ),
        ],
      ),
    );
  }
}

/// Памятка по API с ЖИВЫМИ значениями: настоящий адрес, настоящие порты
/// текущего режима захвата и список эндпоинтов.
///
/// ⚠️ ПАМЯТКА ОБЯЗАНА ГОВОРИТЬ ПРО РЕЖИМ ЗАХВАТА. В системном прокси (умолчание
/// на Windows) портов выходов НЕ СУЩЕСТВУЕТ вовсе — ни одного инбаунда не
/// создаётся. Памятка, перечисляющая номера портов молча, повторила бы уже
/// оплаченный дефект: в 1.4.0 таблица портов в документации описала порт
/// «Прямо» раньше, чем его реализовали, и соединение получало отказ, а человек
/// искал причину у себя.
///
/// ⚠️ ЭНДПОИНТЫ БЕРУТСЯ ИЗ КОДА, А НЕ ИЗ ГОЛОВЫ: `core/net/api_server.dart`
/// (`_route`) — единственное место, где путь превращается в вызов. Строки ниже
/// сверены с ним и с `state/api_handlers.dart`; выдуманный путь дал бы
/// `404 not_found` и ту же охоту за несуществующей причиной.
class _ApiCheatSheet extends StatelessWidget {
  final AppSettings settings;
  final List<VpnServer> servers;
  const _ApiCheatSheet({required this.settings, required this.servers});

  /// Эндпоинты в порядке `LocalApiServer._route`: сперва GET, потом POST.
  static const _endpoints = <(String, String)>[
    ('GET', '/v1/status'),
    ('GET', '/v1/servers'),
    ('GET', '/v1/exits'),
    ('GET', '/v1/traffic'),
    ('GET', '/v1/subscription'),
    ('POST', '/v1/connect'),
    ('POST', '/v1/disconnect'),
    ('POST', '/v1/ping'),
  ];

  String _describe(AppLocalizations l, String path) => switch (path) {
        '/v1/status' => l.apiEpStatus,
        '/v1/servers' => l.apiEpServers,
        '/v1/exits' => l.apiEpExits,
        '/v1/traffic' => l.apiEpTraffic,
        '/v1/subscription' => l.apiEpSubscription,
        '/v1/connect' => l.apiEpConnect,
        '/v1/disconnect' => l.apiEpDisconnect,
        _ => l.apiEpPing,
      };

  /// Порты выходов, которые РЕАЛЬНО достанутся отмеченным серверам.
  ///
  /// ⚠️ Тот же ответчик, что решает это физически: позиция считается по полному
  /// списку ключей (`ApiPorts.forServer`), а непригодный сервер порта не
  /// получает вовсе (`canBeExitServer`) — ровно как в `/v1/exits`. Считай мы
  /// «по порядку галочек», памятка называла бы порт, на котором никто не
  /// слушает, а соседний сервер получил бы чужой номер.
  List<({int port, String name})> _serverPorts() {
    final keys = settings.apiExitServerKeys;
    final out = <({int port, String name})>[];
    for (final key in ApiPorts.withinRange(keys)) {
      final port = ApiPorts.forServer(keys, key);
      if (port == null) continue;
      final srv = servers.where((s) => s.key == key).firstOrNull;
      // Сервер, которого нет в списке (подписка сменилась), пропускаем: имени
      // у него нет, а пригодность спросить не у кого.
      if (srv == null || !canBeExitServer(srv)) continue;
      out.add((port: port, name: srv.displayName));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    const mono = TextStyle(fontSize: 12, fontFamily: 'monospace');
    final small = Theme.of(context).textTheme.bodySmall;
    final tokenEmpty = settings.apiToken.isEmpty;
    final exitPortsExist = ApiPorts.exitPortsExistIn(settings.captureMode);
    final ports = _serverPorts();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.apiCheatSheetTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(l.apiCheatSheetBase, style: small),
            const SelText('http://127.0.0.1:${ApiPorts.control}',
                textDirection: TextDirection.ltr, style: mono),
            const SizedBox(height: 8),
            Text(l.apiCheatSheetExitPorts, style: small),
            // Три взаимоисключающих ответа, и ни один нельзя пропустить: режим
            // без портов, выключенный канал и рабочая раскладка — разные вещи.
            if (!exitPortsExist)
              SelText(l.apiCheatSheetPortsSystemProxy(ApiPorts.control),
                  style: mono)
            else if (tokenEmpty)
              SelText(l.apiCheatSheetTokenOff, style: mono)
            else ...[
              SelText(l.apiCheatSheetPortDirect(ApiPorts.direct),
                  textDirection: TextDirection.ltr, style: mono),
              if (ports.isEmpty)
                SelText(l.apiCheatSheetNoExitServers, style: mono)
              else
                for (final p in ports)
                  SelText(l.apiCheatSheetPortServer(p.port, p.name),
                      textDirection: TextDirection.ltr, style: mono),
              const SizedBox(height: 4),
              Text(l.apiCheatSheetPortsWhenConnected, style: small),
            ],
            const SizedBox(height: 8),
            Text(l.apiCheatSheetEndpoints, style: small),
            for (final e in _endpoints)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Метод и путь — не перевод, а буквальная строка протокола:
                    // её вставляют в скрипт как есть.
                    SizedBox(
                      width: 152,
                      child: SelText('${e.$1} ${e.$2}',
                          textDirection: TextDirection.ltr, style: mono),
                    ),
                    Expanded(child: Text(_describe(l, e.$2), style: small)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
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
    return CheckboxListTile(
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
      // ⚠️ АБЗАЦ ПОКАЗЫВАЕТ «!», А НЕ ГОЛАЯ ПОДСКАЗКА НАД СТРОКОЙ.
      //
      // Здесь `Tooltip` оборачивал строку ЦЕЛИКОМ и нёс 230 символов: подсказка
      // не ограничена по ширине и рисуется под целью (`preferBelow` по
      // умолчанию), поэтому растягивалась на всю ширину и накрывала соседние
      // строки списка — тот же дефект, что владелец прислал скриншотом по
      // раздельному туннелированию. И на тач-экране наведения нет вовсе, то
      // есть объяснение было недостижимо ровно там, где список длиннее.
      // Лечение — образец проекта: `InfoTooltip` (диалог по нажатию).
      secondary: unsupported
          ? InfoTooltip(l.exitServerUnsupported(server.displayName))
          : null,
      onChanged: onChanged,
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
