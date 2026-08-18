import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/probe/auto_config_engine.dart';
import '../../core/probe/service_check.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/split_tunnel.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/service_check_controller.dart';
import '../../state/settings_controller.dart';
import 'site_favicon.dart';

/// Набор сервисов «живой» проверки у кнопки Connect (#6).
///
/// ⚠️ Прежний одноимённый ВИДЖЕТ-ряд (`ServiceChecksRow`) удалён: он давно не
/// стоял ни в одном дереве — проверки рисуются двумя колонками по бокам кнопки
/// (`ServiceChecksColumn`), — но нёс собственную копию правил автопрогона со
/// сбросом результатов по ключу выбранного сервера. Мёртвый код, описывающий
/// поведение, которого нет, хуже отсутствующего: следующий читатель чинил бы
/// его вместо настоящего пути.
abstract final class ServiceChecks {
  /// ВЕСЬ каталог, из которого пользователь собирает свой набор (подменю у
  /// колонок проверок).
  ///
  /// Порядок здесь — порядок показа на экране: сперва прежняя зашитая шестёрка
  /// (её раскладку владелец уже видит), затем остальные.
  ///
  /// ⚠️ Список ЯВНЫЙ, а не `ProbeService.values`, ровно ради этого порядка — и
  /// поэтому новый сервис, забытый здесь, стал бы невыбираемым: настройка его
  /// хранить умеет, а показать было бы негде. Стережёт
  /// `test/connect_checks_test.dart`.
  static const catalog = <ProbeService>[
    ProbeService.youtube,
    ProbeService.chatgpt,
    ProbeService.telegram,
    ProbeService.instagram,
    ProbeService.discord,
    ProbeService.google,
    ProbeService.claude,
    ProbeService.gemini,
    ProbeService.x,
    // Пятёрка, добавленная по просьбе владельца: мессенджер, стриминг видео,
    // музыка, игры и разработка — классы блокировок, которых в прежней девятке
    // не было вовсе. Четырнадцать сервисов раскладываются ровно по семь в
    // колонку ([columns]), то есть кнопка Connect остаётся посередине.
    ProbeService.whatsapp,
    ProbeService.twitch,
    ProbeService.spotify,
    ProbeService.steam,
    ProbeService.github,
  ];

  /// Прежний зашитый набор — по три в колонке слева и справа.
  ///
  /// Шесть, а не три: набор должен покрывать разные классы блокировок —
  /// видео, ИИ, мессенджер, соцсеть и «эталон доступности» (Google отвечает
  /// почти всегда, поэтому его отказ означает, что дело не в конкретном
  /// сервисе, а в канале).
  ///
  /// ⚠️ БОЛЬШЕ НЕ ИСТОЧНИК ПРАВДЫ О ТОМ, ЧТО ПРОВЕРЯЕТСЯ. Состав ряда и
  /// автопрогона берётся из настроек ([selected]) — владелец попросил выбирать
  /// сервисы сам. Константа осталась запасной раскладкой для вёрстки (у
  /// `ConnectCenterpiece` нет доступа к настройкам в стражах вёрстки) и опорным
  /// набором тестов.
  static const services = <ProbeService>[
    ProbeService.youtube,
    ProbeService.chatgpt,
    ProbeService.telegram,
    ProbeService.instagram,
    ProbeService.discord,
    ProbeService.google,
  ];

  /// Что проверять при подключении — по настройкам пользователя.
  ///
  /// Пустой список означает «не проверять вовсе»: ни ряда чипов на главном, ни
  /// автопрогона при подъёме туннеля. Два способа получить пусто равноправны —
  /// снятая галочка [AppSettings.connectChecksEnabled] и пустой набор сервисов.
  ///
  /// Порядок берётся из [catalog], а не из множества: у `Set` порядка нет
  /// вовсе, и чипы перескакивали бы с места на место после каждой правки
  /// набора.
  static List<ProbeService> selected(AppSettings s) {
    if (!s.connectChecksEnabled) return const [];
    return [
      for (final svc in catalog)
        if (s.connectCheckServices.contains(svc)) svc,
    ];
  }

  /// Раскладка набора по двум колонкам вокруг кнопки Connect.
  ///
  /// Нечётное число уходит влево: правая колонка ближе к краю экрана, и на
  /// телефоне ей теснее (см. `FittedBox` в паре ниже).
  static ({List<ProbeService> left, List<ProbeService> right}) columns(
      List<ProbeService> all) {
    final half = (all.length + 1) ~/ 2;
    return (left: all.sublist(0, half), right: all.sublist(half));
  }

  /// Домены, по которым сервис узнаётся в правилах раздельного туннелирования.
  ///
  /// Это НЕ только бренд-домен из [ProbeServiceLabel.domain]. Проба ходит туда,
  /// где живёт сам сервис, а не на его витрину: у YouTube это сеть доставки
  /// видео, у WhatsApp — чат-сервер, у Steam — Web API. Человек, уводящий
  /// сервис мимо VPN, пишет в правило именно такой адрес не реже, чем бренд
  /// («googlevideo.com → Прямо» — обычный приём против замедления). Возьми мы
  /// один бренд-домен — пометка молчала бы ровно там, где она нужнее всего,
  /// а кружок «через VPN» показывал бы замер, который через VPN не шёл.
  static List<String> domainsOf(ProbeService s) {
    final out = <String>{};
    void add(String? host) {
      if (host == null) return;
      final d = normalizeDomain(host);
      // IP-литерал (мишень Telegram — адрес дата-центра) в доменные правила не
      // попадает по построению, а суффиксное сравнение на нём даёт чепуху:
      // правило «51» совпало бы с «149.154.167.51».
      if (d.isEmpty || _isIpv4(d)) return;
      out.add(d);
    }

    add(s.domain);
    add(_hostOf(AutoConfigCatalog.endpointFor(s)?.url));
    add(_hostOf(AutoConfigCatalog.geoEndpointFor(s)?.url));
    return out.toList();
  }

  static String? _hostOf(String? url) {
    if (url == null || url.isEmpty) return null;
    // `tcp://host:443` разбирается тем же `Uri`, что и https-адреса.
    final h = Uri.tryParse(url)?.host;
    return (h == null || h.isEmpty) ? null : h;
  }

  // Регулярка собирается ОДИН раз: [bypassRuleFor] зовётся на каждый сервис при
  // каждой перерисовке главного экрана, а он перерисовывается раз в секунду
  // (тик счётчиков трафика).
  static final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  static bool _isIpv4(String d) => _ipv4.hasMatch(d);

  /// Порт, на который реально идёт проба сервиса (у всех сегодня 443).
  ///
  /// Нужен, чтобы правило с ЯВНЫМ портом («example.com:8443 → Прямо») не
  /// подписывалось под чужой трафик: оно меняет маршрут только своему порту, а
  /// проверка сервиса идёт мимо него.
  static int probePortOf(ProbeService s) {
    final url = AutoConfigCatalog.endpointFor(s)?.url;
    if (url == null) return 443;
    final u = Uri.tryParse(url);
    if (u == null || u.port == 0) return 443;
    return u.port;
  }

  /// Правило раздельного туннелирования, из-за которого сервис НЕ пойдёт через
  /// VPN, либо `null`.
  ///
  /// Решение владельца: пометка показывается ТОЛЬКО по ЯВНОМУ правилу «Прямо»
  /// или «Блок». Умолчания режима не считаются — в «Только отмеченные» мимо
  /// туннеля идёт вообще всё неотмеченное, и замок на всех четырнадцати чипах
  /// сразу не сообщал бы ничего. В режиме «Всё через VPN» пользовательские
  /// правила не применяются вовсе, поэтому там ответ всегда `null`.
  ///
  /// ⚠️ ДОМЕННОЕ ПРАВИЛО СУФФИКСНОЕ: `example.com` покрывает и
  /// `sub.example.com`. Считать иначе — значит врать: правило «google.com →
  /// Прямо» уводит мимо VPN и `gemini.google.com`. Поэтому побеждает САМОЕ
  /// КОНКРЕТНОЕ совпадение (длиннейший домен) — ровно как в конфиге ядра, где
  /// конфликтующий поддомен поднимается выше общего правила
  /// (`_addSitePriorityRules`). Иначе пара «google.com → Прямо» +
  /// «gemini.google.com → Туннель» дала бы замок сервису, который на самом
  /// деле идёт через VPN.
  static SiteRule? bypassRuleFor(SplitTunnelConfig split, ProbeService s) {
    if (split.mode == SplitMode.all) return null;
    final targets = domainsOf(s);
    if (targets.isEmpty) return null;
    final port = probePortOf(s);
    SiteRule? best;
    var bestLen = -1;
    for (final r in split.sites) {
      if (r.port != null && r.port != port) continue;
      final d = normalizeDomain(r.domain);
      if (d.isEmpty) continue;
      if (!targets.any((t) => t == d || t.endsWith('.$d'))) continue;
      // При равной конкретности сильнее «Блок»: он строится в конфиге выше
      // прочих, и ошибиться в сторону запрета честнее, чем промолчать о нём.
      final stronger = d.length > bestLen ||
          (d.length == bestLen && r.action == AppAction.block);
      if (stronger) {
        best = r;
        bestLen = d.length;
      }
    }
    if (best == null || best.action == AppAction.tunnel) return null;
    return best;
  }
}

/// Колонка проверок сбоку от кнопки Connect.
///
/// Показывается ВСЕГДА — и до подключения, и после: смысл в сравнении. У
/// каждого сервиса два состояния рядом: слева замер «до» (напрямую, мимо VPN),
/// справа — через туннель. Так видно, что именно изменил VPN, а не просто
/// «сейчас зелёное».
///
/// ⚠️ Автопрогон колонка НЕ запускает: он живёт в `home_screen` и привязан к
/// подъёму туннеля (`ServiceCheckController.setTunnelUp`). Колонок две, и
/// каждая знает лишь свою половину сервисов — запуск изнутри означал бы, что
/// первая занимает эпоху, а вторая молча пропускает свои три сервиса.
class ServiceChecksColumn extends StatelessWidget {
  const ServiceChecksColumn({
    super.key,
    required this.services,
    required this.httpPort,
    required this.alignEnd,
  });

  final List<ProbeService> services;
  final int httpPort;

  /// Колонка слева прижимается к кнопке справа, и наоборот.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ServiceCheckController>();
    final live = httpPort > 0;
    // ⚠️ НАСТРОЙКИ ЧИТАЮТСЯ КАК НЕОБЯЗАТЕЛЬНЫЕ. Колонку поднимают стражи
    // вёрстки (`ConnectCenterpiece`), которым настройки не нужны и которые
    // провайдер не заводят: строгое чтение уронило бы их
    // `ProviderNotFoundException`. Нет настроек — нет и пометок, всё остальное
    // на месте.
    final split = context.watch<SettingsController?>()?.settings.splitTunnel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        for (final s in services)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
            child: _ServicePair(
              service: s,
              before: ctrl.baselineFor(s),
              after: ctrl.resultFor(s),
              live: live,
              alignEnd: alignEnd,
              bypass:
                  split == null ? null : ServiceChecks.bypassRuleFor(split, s),
              // Тап меряет то, что сейчас доступно: с VPN — через туннель,
              // без него — напрямую (это и есть замер «до»).
              onTap: () => ctrl.check(s, httpPort),
            ),
          ),
      ],
    );
  }
}

/// Кнопка подменю «что проверять при подключении» — рядом с самими проверками.
///
/// ⚠️ ЖИВЁТ ЗДЕСЬ, А НЕ В НАСТРОЙКАХ. Требование владельца: «сама настройка
/// спрятана под подменю» у ряда проверок. Смысл практический — набор правят,
/// глядя на кружки, а не открывая отдельный экран; и когда проверки выключены
/// целиком, ряда на главном нет, так что включить их обратно можно только
/// отсюда. Поэтому кнопка показывается ВСЕГДА, независимо от настроек.
class ServiceChecksMenuButton extends StatefulWidget {
  const ServiceChecksMenuButton({super.key});

  @override
  State<ServiceChecksMenuButton> createState() =>
      _ServiceChecksMenuButtonState();
}

class _ServiceChecksMenuButtonState extends State<ServiceChecksMenuButton> {
  /// Набор, для которого замер «до» уже заказан.
  List<ProbeService>? _lastWanted;

  /// Догнать замер «до» для сервисов, добавленных после запуска.
  ///
  /// ⚠️ ЭТО ЛЕЧЕНИЕ ЖАЛОБЫ ВЛАДЕЛЬЦА: «пара точек со стрелкой есть только у
  /// трёх сервисов по умолчанию, а у добавленных позже — одна точка». Замер
  /// «до» снимался ровно один раз за запуск и ровно по тому набору, который
  /// был выбран в ту секунду (`ServiceCheckController.autoBaseline` из
  /// `home_screen`), а подписки на изменение набора не было вовсе.
  ///
  /// ⚠️ ПОЧЕМУ ИМЕННО ЗДЕСЬ, А НЕ В КОЛОНКЕ ПРОВЕРОК. Колонок две, каждая знает
  /// лишь свою половину сервисов, и при выключенных проверках их нет ни одной —
  /// то есть включить проверки обратно и не получить замера было бы легче
  /// всего. Кнопка подменю, наоборот, стоит на главном ВСЕГДА и видит набор
  /// целиком, откуда бы его ни правили: из этого подменю, из настроек или
  /// url-командой.
  ///
  /// Сам замер идёт мимо VPN и осмыслен только при выключенном туннеле —
  /// решение «сейчас или потом» принимает контроллер
  /// (`ServiceCheckController.ensureBaseline`): при живом канале просьба
  /// запоминается и выполняется, когда VPN выключат.
  void _topUpBaseline(List<ProbeService> selected) {
    if (_lastWanted != null && listEquals(_lastWanted, selected)) return;
    _lastWanted = selected;
    if (selected.isEmpty) return;
    // Побочное действие — после кадра: `ensureBaseline` уведомляет слушателей,
    // а менять состояние во время сборки дерева нельзя.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Контроллер необязателен: кнопку поднимает и страж самого подменю, где
      // проверок нет вовсе.
      final ctrl = context.read<ServiceCheckController?>();
      if (ctrl == null) return;
      unawaited(ctrl.ensureBaseline(selected));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Настройки читаются как необязательные — см. `ServiceChecksColumn`.
    final settings = context.watch<SettingsController?>()?.settings;
    if (settings != null) _topUpBaseline(ServiceChecks.selected(settings));
    return IconButton(
      icon: const Icon(Icons.tune, size: 18),
      tooltip: l.serviceChecksMenuTooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    // Контроллер берём ДО показа меню: внутри пункта контекст принадлежит
    // маршруту меню, и после его закрытия обращаться к нему нельзя.
    // Необязательный — по той же причине, что и в `build`: без настроек в меню
    // нечего показывать, но и падать незачем.
    final settings = context.read<SettingsController?>();
    if (settings == null) return;
    final box = context.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    await showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy + 28, pos.dx, pos.dy),
      items: [
        PopupMenuItem<void>(
          // Пункт-контейнер: нажатия обрабатывают строки внутри, а сам пункт
          // закрывать меню не должен — иначе после каждой галочки его пришлось
          // бы открывать заново.
          enabled: false,
          padding: EdgeInsets.zero,
          child: _ServiceChecksMenuBody(settings: settings),
        ),
      ],
    );
  }
}

/// Содержимое подменю: галочки сервисов плюс «не проверять при подключении».
class _ServiceChecksMenuBody extends StatefulWidget {
  final SettingsController settings;
  const _ServiceChecksMenuBody({required this.settings});

  @override
  State<_ServiceChecksMenuBody> createState() => _ServiceChecksMenuBodyState();
}

class _ServiceChecksMenuBodyState extends State<_ServiceChecksMenuBody> {
  @override
  void initState() {
    super.initState();
    // Меню живёт в СВОЁМ маршруте и на `notifyListeners` не перестраивается —
    // подписываемся сами. Без этого галочка не отзывалась бы на нажатие:
    // настройка менялась бы, а нарисованный флажок оставался прежним до
    // закрытия меню.
    widget.settings.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _toggleService(ProbeService s, bool on) {
    final next = {...widget.settings.settings.connectCheckServices};
    if (on) {
      next.add(s);
    } else {
      next.remove(s);
    }
    // Настройка применяется НЕМЕДЛЕННО (требование владельца), кнопки
    // «Сохранить» нет. Запись на диск идёт своим чередом — ждать её незачем.
    unawaited(widget.settings
        .update((c) => c.copyWith(connectCheckServices: next)));
  }

  /// «Все» / «Снять» — те же кнопки, что в настройках у этой же настройки.
  ///
  /// ⚠️ ИСТОЧНИК «ВСЕХ» — `ServiceChecks.catalog`, А НЕ `ProbeService.values`.
  /// Сервис, забытый в каталоге, кнопка «Все» иначе записала бы в настройку, а
  /// показать его было бы негде: в подменю его нет, на главном чипа нет — зато
  /// проба при подключении шла бы. Невидимая работа и невидимый трафик.
  void _setAll(bool on) {
    unawaited(widget.settings.update((c) => c.copyWith(
        connectCheckServices:
            on ? ServiceChecks.catalog.toSet() : const <ProbeService>{})));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final s = widget.settings.settings;
    final on = s.connectChecksEnabled;
    return SizedBox(
      // ⚠️ ТОЧНАЯ ШИРИНА, А НЕ `ConstrainedBox(minWidth/maxWidth)`.
      //
      // `showMenu` оборачивает содержимое в `IntrinsicWidth`, а тот спрашивает у
      // потомков внутренние размеры — на такой вопрос прокручиваемые области
      // бросают исключение. Диапазонные ограничения не спасают: короткое
      // замыкание в `RenderConstrainedBox` срабатывает только на ТУГОЙ ширине.
      // В release проверки вырезаны, поэтому дефект виден лишь в debug — то
      // есть дожил бы до чужого `flutter run`. 280 — штатный потолок ширины
      // меню (`_kMenuMaxWidth`), просить больше бессмысленно.
      width: 280,
      child: ConstrainedBox(
        // Потолок высоты: без него `Flexible` не от чего отталкивать прокрутку —
        // колонка в меню получает неограниченную высоту и растёт как раньше.
        // 420 подобрано так, чтобы меню помещалось и на невысоком окне, и на
        // телефоне в альбомной ориентации.
        constraints: const BoxConstraints(maxHeight: 420),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.serviceChecksMenuTitle,
                    // Цвет задан явно: пункт меню отключён (см. выше), а
                    // отключённый пункт красит весь свой текст в серый —
                    // заголовок выглядел бы недоступным.
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: scheme.onSurface),
                  ),
                ),
                // Четырнадцать сервисов руками отмечать долго — те же две
                // кнопки, что уже стоят у этой настройки в настройках.
                TextButton(
                  key: const Key('connectChecksMenuAll'),
                  onPressed: on ? () => _setAll(true) : null,
                  child: Text(l.autoSelectAll),
                ),
                TextButton(
                  key: const Key('connectChecksMenuNone'),
                  onPressed: on ? () => _setAll(false) : null,
                  child: Text(l.autoDeselectAll),
                ),
              ],
            ),
          ),
          // ⚠️ СПИСОК ПРОКРУЧИВАЕТСЯ, И ЭТО НЕ УКРАШЕНИЕ.
          //
          // Сервисов стало четырнадцать, и простая колонка перестала помещаться
          // на экран: нижний пункт «не проверять при подключении» уезжал за
          // границу и переставал нажиматься вовсе. Поймано тестом сразу после
          // добавления пятёрки — на окне 800×600 пункт оказался на y=772.
          // На телефоне было бы то же самое, только молча.
          //
          // ⚠️ Прокрутка внутри `showMenu` безопасна ИМЕННО ЗДЕСЬ, потому что
          // ширина выше задана ТУГО (`SizedBox(width: 280)`): короткое замыкание
          // в `RenderConstrainedBox` не пускает запрос внутренней ширины к
          // прокручиваемой области. Тот же приём уже работает в переключателе
          // подписок. Развяжешь ширину — вернётся исключение `IntrinsicWidth`.
          //
          // Заголовок с кнопками «Все»/«Снять» и нижняя галочка НАМЕРЕННО
          // оставлены вне прокрутки: ими пользуются чаще всего, и уводить их
          // под скролл значило бы менять одну беду на другую.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          for (final svc in ServiceChecks.catalog)
            _MenuCheckRow(
              enabled: on,
              value: s.connectCheckServices.contains(svc),
              onChanged: (v) => _toggleService(svc, v),
              label: svc.label,
              // ⚠️ Невыбранный сервис ЗАТЕМНЯЕТСЯ И ПЕРЕЧЁРКИВАЕТСЯ. Жалоба
              // владельца: «галочку просто не видно из-за значков приложений» —
              // четырнадцать ярких бренд-иконок в столбик перетягивают взгляд, и
              // маленький квадратик рядом с ними теряется. Состояние теперь
              // видно по самой строке целиком, а не по одному квадратику.
              struck: !s.connectCheckServices.contains(svc),
              leading: SiteFavicon(domain: svc.domain, size: 20, builtIn: true),
            ),
                ],
              ),
            ),
          ),
          const Divider(height: 8),
          _MenuCheckRow(
            // Эта галочка доступна ВСЕГДА — ею проверки и возвращают.
            enabled: true,
            value: !on,
            onChanged: (v) => unawaited(widget.settings
                .update((c) => c.copyWith(connectChecksEnabled: !v))),
            label: l.serviceChecksMenuOff,
          ),
          const SizedBox(height: 4),
        ],
        ),
      ),
    );
  }
}

/// Строка подменю с галочкой.
class _MenuCheckRow extends StatelessWidget {
  const _MenuCheckRow({
    required this.enabled,
    required this.value,
    required this.onChanged,
    required this.label,
    this.leading,
    this.struck = false,
  });

  final bool enabled;
  final bool value;
  final void Function(bool value) onChanged;
  final String label;
  final Widget? leading;

  /// Строка «выключена по смыслу»: гасим значок и перечёркиваем подпись.
  final bool struck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      // Нажатие по всей строке, а не только по квадратику: попасть в чекбокс
      // пальцем на телефоне — отдельное упражнение.
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              visualDensity: VisualDensity.compact,
              onChanged: enabled ? (v) => onChanged(v ?? false) : null,
            ),
            if (leading != null) ...[
              // Значок гасится вместе с подписью: он и был причиной жалобы —
              // яркая иконка выглядела как «включено» независимо от галочки.
              Opacity(opacity: struck ? 0.35 : 1, child: leading!),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: !enabled || struck
                      ? Theme.of(context).disabledColor
                      : scheme.onSurface,
                  decoration: struck ? TextDecoration.lineThrough : null,
                  decorationColor: Theme.of(context).disabledColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пара «до / после» для одного сервиса.
class _ServicePair extends StatelessWidget {
  const _ServicePair({
    required this.service,
    required this.before,
    required this.after,
    required this.live,
    required this.alignEnd,
    required this.onTap,
    this.bypass,
  });

  final ProbeService service;
  final ServiceCheckOutcome before;
  final ServiceCheckOutcome after;
  final bool live;
  final bool alignEnd;
  final VoidCallback onTap;

  /// Правило раздельного туннелирования, уводящее сервис мимо VPN (или
  /// запрещающее его). `null` — сервис идёт как весь остальной трафик.
  final SiteRule? bypass;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // ⚠️ Кружки собраны в ОТДЕЛЬНУЮ строку, и переворачивается только пара
    // «значок + кружки». Если перевернуть всё подряд, в левой колонке
    // поменяются местами «до» и «после»: стрелка станет показывать в обратную
    // сторону, а подпись «слева — без VPN, справа — через VPN» превратится в
    // ложь ровно для половины сервисов.
    final dots = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Пара «до → после» рисуется ТОЛЬКО когда есть что с чем сравнивать, то
        // есть при живом VPN. Иначе один и тот же замер показывался дважды со
        // стрелкой между ними — читалось как «проверено до и после», хотя
        // подключения ещё не было.
        if (live && before.state != ServiceCheckState.idle) ...[
          _dot(context, before, dim: true),
          const SizedBox(width: 4),
          Text('→', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(width: 4),
        ],
        _dot(context, live ? after : before, dim: false),
      ],
    );
    final rule = bypass;
    final items = <Widget>[
      SiteFavicon(domain: service.domain, size: 26, builtIn: true),
      // Значок стоит ВПЛОТНУЮ к бренд-иконке, а не с краю строки: строка
      // зеркалится в правой колонке (`items.reversed`), и значок, приклеенный
      // к кружкам, у половины сервисов оказался бы по другую сторону от них.
      if (rule != null) ...[
        const SizedBox(width: 2),
        Icon(
          // Перечёркнутый замок читается как «этот сервис вне защиты», знак
          // запрета — как «сюда вообще нельзя». Разные вещи, разные значки.
          rule.action == AppAction.block
              ? Icons.block
              : Icons.lock_open_rounded,
          size: 14,
          color: rule.action == AppAction.block
              ? const Color(0xFFCC7777)
              : Colors.orange,
        ),
      ],
      const SizedBox(width: 8),
      dots,
    ];
    // Подпись «до» и «после» словами: два кружка сами по себе не объясняют,
    // который из них какой, а порядок в правой колонке ещё и зеркалится.
    final tip = StringBuffer('${service.label}\n')
      ..write(before.state == ServiceCheckState.idle
          ? l.serviceChecksNoBaseline
          : '${l.serviceChecksBefore}: ${_word(l, before)}');
    if (live) {
      tip.write('\n${l.serviceChecksAfter}: ${_word(l, after)}');
    }
    // У YouTube отдельная оговорка: провайдер его чаще не блокирует, а
    // замедляет, и лёгкая проба этого не видит. Молчать нельзя — зелёный чип
    // рядом с не грузящимся видео выглядит как враньё.
    if (service == ProbeService.youtube) {
      tip.write('\n\n${l.serviceYoutubeThrottleNote}');
    }
    // Пометка объясняет ПРИЧИНУ и НАЗЫВАЕТ ПРАВИЛО. Без имени правила человек
    // видит замок и не знает, где его снять: правил у него десятки, а
    // совпадение может прийти от родительского домена, которого в списке
    // сервисов нет вовсе.
    if (rule != null) {
      tip.write('\n\n');
      tip.write(rule.action == AppAction.block
          ? l.serviceChecksBypassBlock(rule.label)
          : l.serviceChecksBypassDirect(rule.label));
    }
    return Tooltip(
      message: tip.toString(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          // ⚠️ Строка ужимается, а не обрезается.
          //
          // На узком телефоне правая колонка не влезала и уезжала за край:
          // кружок «через VPN» оказывался за экраном, то есть пропадала ровно
          // та половина сравнения, ради которой всё и сделано. Ширина здесь
          // фиксированная по содержимому (значок + два кружка + стрелка), и
          // растянуть её нечем — поэтому масштабируем целиком: на большом
          // экране размер прежний, на маленьком всё то же, только мельче.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignEnd
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: alignEnd ? items.reversed.toList() : items,
            ),
          ),
        ),
      ),
    );
  }

  String _word(AppLocalizations l, ServiceCheckOutcome o) => switch (o.state) {
        ServiceCheckState.ok => l.serviceStatusOk,
        ServiceCheckState.geoBlocked => l.serviceStatusGeo,
        ServiceCheckState.fail => l.serviceStatusFail,
        ServiceCheckState.checking => l.serviceStatusChecking,
        ServiceCheckState.idle => l.serviceStatusTap,
      };

  Widget _dot(BuildContext context, ServiceCheckOutcome o, {required bool dim}) {
    if (o.state == ServiceCheckState.checking) {
      return const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    }
    final color = switch (o.state) {
      ServiceCheckState.ok => Colors.green,
      ServiceCheckState.geoBlocked => Colors.orange,
      ServiceCheckState.fail => const Color(0xFFCC7777),
      _ => Theme.of(context).disabledColor,
    };
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: dim ? color.withValues(alpha: 0.45) : color,
        shape: BoxShape.circle,
      ),
    );
  }
}

