import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/probe/auto_config_engine.dart';
import '../../core/probe/service_check.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/split_tunnel.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/service_check_controller.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../layout/adaptive.dart';
import 'site_favicon.dart';

/// Смысловая группа сервисов — один ряд проверок у кнопки Connect.
///
/// ⚠️ ГРУППА — ЭТО КЛАСС БЛОКИРОВКИ, А НЕ ПОЛКА ДЛЯ КРАСОТЫ. Четырнадцать
/// одинаковых кружков в две колонки читаются как один список, и человек не
/// видит главного: «мессенджеры живы, ИИ мёртв» — это разные диагнозы, а
/// «Telegram зелёный, ChatGPT красный» вперемешку выглядит как случайность.
///
/// Порядок значений — порядок рядов на экране.
enum ServiceGroup { messengers, ai, media, social, other }

/// Одна смысловая группа с выбранными сервисами внутри неё — то, что отдаёт
/// [ServiceChecks.grouped]. Алиас заведён ради читаемости сигнатур новых
/// раскладок (боковых колонок): без него каждая сигнатура повторяла бы
/// анонимный тип записи целиком.
typedef GroupedRow = ({ServiceGroup group, List<ProbeService> services});

extension ServiceGroupLabel on ServiceGroup {
  /// Подпись ряда. Переводится (в отличие от названий самих сервисов — те
  /// бренды и остаются как есть).
  String label(AppLocalizations l) => switch (this) {
        ServiceGroup.messengers => l.serviceGroupMessengers,
        ServiceGroup.ai => l.serviceGroupAi,
        ServiceGroup.media => l.serviceGroupMedia,
        ServiceGroup.social => l.serviceGroupSocial,
        ServiceGroup.other => l.serviceGroupOther,
      };
}

/// Набор сервисов «живой» проверки у кнопки Connect (#6).
///
/// ⚠️ Прежний одноимённый ВИДЖЕТ-ряд (`ServiceChecksRow`) удалён: он давно не
/// стоял ни в одном дереве, но нёс собственную копию правил автопрогона со
/// сбросом результатов по ключу выбранного сервера. Мёртвый код, описывающий
/// поведение, которого нет, хуже отсутствующего: следующий читатель чинил бы
/// его вместо настоящего пути. Пришедший ему на смену [ServiceChecksRows]
/// (ряды по смыслу) автопрогон НЕ запускает — по той же причине.
///
/// ⚠️ РАСКЛАДКА ОДНА — [ServiceChecksRows], ряды по смысловым группам. Прежние
/// две колонки по бокам кнопки (`ServiceChecksColumn`) удалены 19.08.2026, и не
/// за красоту: при четырнадцати сервисах столбцы по семь строк лезли за край
/// экрана телефона. Но главное — ряды были написаны и покрыты тестами ещё
/// тогда, когда набор расширяли, а на месте вызова подмену забыли сделать:
/// группировка полгода существовала в коде, была зелёной в тестах и не доходила
/// до человека. Владелец сказал прямо: «в интерфейсе я этого не заметил».
/// Держать обе раскладки, когда рисуется одна, — тот же мёртвый код, что описан
/// абзацем выше.
abstract final class ServiceChecks {
  /// Смысловые группы — ряды проверок у кнопки Connect (сверху вниз).
  ///
  /// ⚠️ ЛЕЖИТ ВПЛОТНУЮ К [catalog] НАМЕРЕННО. Это два взгляда на один набор:
  /// каталог задаёт порядок в подменю и в настройках (менять его нельзя без
  /// нужды — по нему уже написаны стражи, которые тапают по строкам меню),
  /// группы задают раскладку рядами. Разъехаться им не дают тесты
  /// `test/service_rows_api_test.dart`: каждый сервис лежит ровно в одной
  /// группе, а объединение групп совпадает с каталогом ПОСОСТАВНО. Новый
  /// сервис, забытый здесь, тест валит сразу — молча выпасть из рядов он не
  /// может.
  ///
  /// Литерал `Map` в Dart сохраняет порядок вставки — на нём и держится
  /// порядок рядов.
  static const groups = <ServiceGroup, List<ProbeService>>{
    ServiceGroup.messengers: [
      ProbeService.telegram,
      ProbeService.whatsapp,
      ProbeService.discord,
    ],
    ServiceGroup.ai: [
      ProbeService.chatgpt,
      ProbeService.claude,
      ProbeService.gemini,
    ],
    ServiceGroup.media: [
      ProbeService.youtube,
      ProbeService.twitch,
      ProbeService.spotify,
    ],
    ServiceGroup.social: [
      ProbeService.instagram,
      ProbeService.x,
    ],
    // «Прочее» — не свалка: Google здесь эталон доступности (отвечает почти
    // всегда, поэтому его отказ означает беду с каналом, а не с сервисом),
    // Steam — игры, GitHub — разработка.
    ServiceGroup.other: [
      ProbeService.google,
      ProbeService.steam,
      ProbeService.github,
    ],
  };

  /// ВЕСЬ каталог, из которого пользователь собирает свой набор (подменю у
  /// проверок и раздел настроек).
  ///
  /// Порядок здесь — порядок показа В СПИСКЕ (подменю, настройки), а не в
  /// рядах: рядами командует [groups]. Порядок сохранён прежним сознательно —
  /// по нему написаны стражи, которые нажимают на строки подменю, и
  /// перетасовка увела бы Instagram под нижний край окна 800×600, где нажатие
  /// промахивается (проверено: тест краснеет ровно так).
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
    // не было вовсе.
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

  /// Раскладка набора по смысловым рядам ([groups]).
  ///
  /// Пустая группа не возвращается вовсе, а не возвращается пустой: подпись
  /// «Соцсети» над пустым местом занимала бы высоту у кнопки Connect и врала бы
  /// — проверок в этой группе человек не выбирал.
  ///
  /// Порядок внутри ряда — порядок [groups], а не порядок [selected]: набор
  /// приходит множеством, и у множества порядка нет вовсе (чипы перескакивали
  /// бы после каждой правки набора).
  static List<GroupedRow> grouped(List<ProbeService> selected) {
    final want = selected.toSet();
    final out = <GroupedRow>[];
    for (final e in groups.entries) {
      final row = [
        for (final s in e.value)
          if (want.contains(s)) s,
      ];
      if (row.isNotEmpty) out.add((group: e.key, services: row));
    }
    return out;
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


/// Проверки сервисов РЯДАМИ ПО СМЫСЛУ — мессенджеры, ИИ, видео, соцсети,
/// прочее (решение владельца от 18.08.2026).
///
/// ⚠️ ЗАЧЕМ ВМЕСТО ДВУХ КОЛОНОК. Четырнадцать одинаковых кружков в два
/// столбика по бокам кнопки читаются как один сплошной список: «Telegram
/// зелёный, ChatGPT красный, Instagram зелёный» вперемешку выглядит
/// случайностью. Ряд с подписью отвечает на вопрос, который человек на самом
/// деле задаёт: «мессенджеры живы, а ИИ нет» — это диагноз, а не набор точек.
///
/// ⚠️ АВТОПРОГОН ОТСЮДА НЕ ЗАПУСКАЕТСЯ — ровно по той же причине, по которой
/// его убрали из прежнего одноимённого виджета (см. шапку файла): прогон живёт
/// в `home_screen` и привязан к подъёму туннеля
/// (`ServiceCheckController.setTunnelUp`). Своя копия правил тут означала бы
/// два расходящихся описания одного поведения.
///
/// ⚠️ РЯД НЕ ИМЕЕТ ПРАВА РАСПЕРЕТЬ ОКНО: пары лежат в `Wrap`, поэтому на узком
/// экране они переносятся на вторую строку, а не уезжают за край. Ширину
/// виджет берёт ту, что дал родитель, и своей не просит.
class ServiceChecksRows extends StatelessWidget {
  const ServiceChecksRows({
    super.key,
    required this.services,
    required this.httpPort,
  });

  /// Состав из настроек (`ServiceChecks.selected`). Пусто — виджета нет вовсе
  /// и места он не занимает.
  final List<ProbeService> services;

  /// http-порт живого ядра; 0 — VPN выключен (показывается только замер «до»).
  final int httpPort;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ctrl = context.watch<ServiceCheckController>();
    final live = httpPort > 0;
    // Настройки читаются как НЕОБЯЗАТЕЛЬНЫЕ — см. `ServiceChecksColumn`:
    // стражи вёрстки поднимают виджет без провайдера настроек, и строгое
    // чтение уронило бы их `ProviderNotFoundException`.
    final split = context.watch<SettingsController?>()?.settings.splitTunnel;
    final rows = ServiceChecks.grouped(services);
    if (rows.isEmpty) return const SizedBox.shrink();
    // На узком экране просвет между рядами меньше: у кнопки Connect и без того
    // мало места по высоте, а рядов теперь до пяти.
    final compact = context.sg.isCompact;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) ...[
          _GroupDivider(group: row.group, label: row.group.label(l)),
          Padding(
            padding: EdgeInsets.only(top: compact ? 2 : 4),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: compact ? 6 : 12,
              runSpacing: 2,
              children: [
                for (final s in row.services)
                  _ServicePair(
                    // Ключ по имени сервиса — см. `ServiceChecksColumn`.
                    key: ValueKey('svc:${s.name}'),
                    service: s,
                    before: ctrl.baselineFor(s),
                    after: ctrl.resultFor(s),
                    live: live,
                    alignEnd: false,
                    bypass: split == null
                        ? null
                        : ServiceChecks.bypassRuleFor(split, s),
                    onTap: () => ctrl.check(s, httpPort),
                  ),
              ],
            ),
          ),
          SizedBox(height: compact ? 4 : 8),
        ],
      ],
    );
  }
}

/// Проверки сервисов КОЛОНКАМИ ПО БОКАМ кнопки Connect (решение владельца от
/// 27.08.2026) — режимы настройки `sides` и `grid`, и широкое окно в `adaptive`.
///
/// ⚠️ ПОЧЕМУ ЭТО НЕ ПРОСТО ВОЗВРАЩЕНИЕ УДАЛЁННОГО 19.08.2026 `ServiceChecksColumn`.
/// Тот виджет резервировал под колонку фиксированную высоту (семь строк) и на
/// каталоге в 14 сервисов вылезал за нижний край телефона — см. шапку файла и
/// [ServiceChecksLayout] в `app_settings.dart`. Здесь высота, наоборот, НИКОГДА
/// не фиксирована: `FittedBox` в конце [build] измеряет настоящий размер
/// содержимого при реальных ограничениях родителя и уменьшает ВЕСЬ блок (обе
/// колонки и кнопку — ОДНИМ множителем) ровно настолько, чтобы он влез. Это не
/// эвристика «подобрали число и надеемся» — `RenderFittedBox` физически не
/// может отрисовать ребёнка крупнее выделенного места, поэтому переполнение
/// (`RenderFlex overflowed`) здесь структурно невозможно ни при каком экране.
///
/// ⚠️ ГРУБАЯ ОЦЕНКА МАСШТАБА (`_estimateScale`) — ДРУГОЕ ЧИСЛО, И ОНО НЕ ОБЯЗАНО
/// БЫТЬ ТОЧНЫМ. От него зависит только порог, ниже которого колонки уступают
/// место привычным рядам под кнопкой, потому что мелкий текст и микроскопические
/// значки читать нельзя, даже если формально они поместились. Ошибка в этой
/// оценке — вопрос красоты (колонки чуть мельче или крупнее, чем могли бы), а не
/// целостности вёрстки: та гарантирована `FittedBox` выше независимо от неё.
class ServiceChecksSides extends StatelessWidget {
  const ServiceChecksSides({
    super.key,
    required this.services,
    required this.httpPort,
    required this.button,
    this.dense = false,
  });

  /// Состав из настроек (`ServiceChecks.selected`).
  final List<ProbeService> services;

  /// http-порт живого ядра; 0 — VPN выключен.
  final int httpPort;

  /// Кнопка Connect, приходит готовым виджетом — см. `ConnectCenterpiece`.
  final Widget button;

  /// `true` — режим настройки `grid`: плотная сетка иконок без подписи группы
  /// (имя группы уходит в `Tooltip`). `false` — режим `sides`: вертикальный
  /// список с подписями групп, как в [ServiceChecksRows], только колонкой.
  final bool dense;

  /// Диаметр кнопки на масштабе 1.0 — базовая величина, от которой считается
  /// коэффициент сжатия. Кнопка приходит готовым виджетом с уже своим
  /// размером (148 или 116 на коротком экране, см. `_ConnectButton`); мы не
  /// лезем в него, а просто отводим ему опорную ширину/высоту для измерения —
  /// `FittedBox` ниже досожмёт фактический размер вместе со всем остальным.
  static const double _naturalButton = 148.0;

  /// Просвет между колонкой и кнопкой на масштабе 1.0.
  static const double _gap = 14.0;

  /// Ширина одной колонки на масштабе 1.0. Разная для `sides` (нужно место под
  /// пару «до → после») и `grid` (только иконка с кружком статуса).
  static double _columnWidth(bool dense) => dense ? 84.0 : 108.0;

  /// Ниже этого множителя иконки и подписи превращаются в нечитаемую пыль —
  /// правильнее показать привычные ряды под кнопкой, чем ужимать до предела.
  /// Само сжатие структурно безопасно (см. шапку класса), порог — вопрос
  /// читаемости, не целостности.
  static const double _minReadableScale = 0.62;

  @override
  Widget build(BuildContext context) {
    final rows = ServiceChecks.grouped(services);
    // Проверки выключены целиком — колонкам нечего показывать, но кнопка
    // остаётся: место у неё не отбираем.
    if (rows.isEmpty) return button;

    final split = _splitColumns(rows, dense: dense);
    final natural = _naturalSize(split, dense: dense);

    return LayoutBuilder(builder: (context, c) {
      if (_estimateScale(c, natural) < _minReadableScale) {
        // Места категорически мало — те же ряды, что и на узком телефоне,
        // вместо нечитаемой мелочи по бокам.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            button,
            ServiceChecksRows(services: services, httpPort: httpPort),
          ],
        );
      }
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _columnWidth(dense),
              child: _SideColumn(
                rows: split.left,
                httpPort: httpPort,
                dense: dense,
                alignEnd: true,
              ),
            ),
            const SizedBox(width: _gap),
            SizedBox(
              width: _naturalButton,
              height: _naturalButton,
              child: Center(child: button),
            ),
            const SizedBox(width: _gap),
            SizedBox(
              width: _columnWidth(dense),
              child: _SideColumn(
                rows: split.right,
                httpPort: httpPort,
                dense: dense,
                alignEnd: false,
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Насколько пришлось бы сжать блок, чтобы он влез в `c` — ОЦЕНКА для
  /// решения «показывать колонки или ряды», не фактический рендер (тот считает
  /// `FittedBox` сам, по-настоящему).
  double _estimateScale(BoxConstraints c, Size natural) {
    final wRatio =
        natural.width <= 0 ? 1.0 : c.maxWidth / natural.width;
    // Высота часто НЕ ограничена (узкий телефон целиком прокручивается, см.
    // `_MaybeScroll` в `home_screen.dart`) — там сжимать по высоте не от чего,
    // и `BoxConstraints.hasBoundedHeight` отличает этот случай от настоящего
    // тесного окна (минимум Windows), где ограничение есть.
    final hRatio = !c.hasBoundedHeight || natural.height <= 0
        ? 1.0
        : c.maxHeight / natural.height;
    return math.min(1.0, math.min(wRatio, hRatio));
  }

  /// Требуемый размер блока (обе колонки + кнопка) на масштабе 1.0.
  Size _naturalSize(({List<GroupedRow> left, List<GroupedRow> right}) split,
      {required bool dense}) {
    double columnHeight(List<GroupedRow> rows) {
      var h = 0.0;
      for (final r in rows) {
        h += dense
            // Сетка: иконки по две в ряд, без подписи группы.
            ? (r.services.length / 2).ceil() * 40.0
            // Список: строка подписи группы + по строке на сервис.
            : 26.0 + r.services.length * 34.0;
        h += 6; // просвет после группы
      }
      return h;
    }

    final height = math.max(
      _naturalButton,
      math.max(columnHeight(split.left), columnHeight(split.right)),
    );
    final width = _columnWidth(dense) * 2 + _naturalButton + _gap * 2;
    return Size(width, height);
  }

  /// Раскладывает ГРУППЫ (не отдельные сервисы — группа не разрывается между
  /// колонками, иначе смысл ряда потерялся бы, см. шапку файла) по двум
  /// колонкам, примерно поровну по числу строк.
  ({List<GroupedRow> left, List<GroupedRow> right}) _splitColumns(
      List<GroupedRow> rows,
      {required bool dense}) {
    int linesOf(GroupedRow r) =>
        dense ? (r.services.length / 2).ceil() : 1 + r.services.length;
    final total = rows.fold<int>(0, (a, r) => a + linesOf(r));
    final left = <GroupedRow>[];
    final right = <GroupedRow>[];
    var acc = 0;
    for (final r in rows) {
      if (acc < total / 2) {
        left.add(r);
      } else {
        right.add(r);
      }
      acc += linesOf(r);
    }
    return (left: left, right: right);
  }
}

/// Одна колонка внутри [ServiceChecksSides]: список групп сверху вниз.
class _SideColumn extends StatelessWidget {
  const _SideColumn({
    required this.rows,
    required this.httpPort,
    required this.dense,
    required this.alignEnd,
  });

  final List<GroupedRow> rows;
  final int httpPort;
  final bool dense;

  /// Левая колонка прижимает пары «до → после» к кнопке (к правому краю своей
  /// колонки), правая — наоборот. Порядок иконка→точки при этом ОДИНАКОВЫЙ в
  /// обеих колонках — см. предысторию в [_ServicePair].
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final ctrl = context.watch<ServiceCheckController>();
    final live = httpPort > 0;
    // Настройки — необязательно, см. `ServiceChecksRows`.
    final split = context.watch<SettingsController?>()?.settings.splitTunnel;

    SiteRule? bypassOf(ProbeService s) =>
        split == null ? null : ServiceChecks.bypassRuleFor(split, s);

    if (dense) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in row.services)
                    _ServicePair(
                      key: ValueKey('svc:${s.name}'),
                      service: s,
                      before: ctrl.baselineFor(s),
                      after: ctrl.resultFor(s),
                      live: live,
                      alignEnd: false,
                      dense: true,
                      groupLabel: row.group.label(l),
                      bypass: bypassOf(s),
                      onTap: () => ctrl.check(s, httpPort),
                    ),
                ],
              ),
            ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) ...[
          _SideGroupLabel(group: row.group, label: row.group.label(l)),
          const SizedBox(height: 4),
          for (final s in row.services)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _ServicePair(
                key: ValueKey('svc:${s.name}'),
                service: s,
                before: ctrl.baselineFor(s),
                after: ctrl.resultFor(s),
                live: live,
                alignEnd: alignEnd,
                bypass: bypassOf(s),
                onTap: () => ctrl.check(s, httpPort),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

/// Разделитель ряда: подпись группы посреди тонкой линии.
///
/// ⚠️ Именно линия, а не один отступ. Владелец просил «явное разграничение»:
/// проверки стоят вплотную к кнопке Connect, и пустой промежуток между рядами
/// на глаз неотличим от промежутка между строками внутри ряда.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider({required this.group, required this.label});

  final ServiceGroup group;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      // Ключ ставится на строку целиком: по нему страж вёрстки считает ряды.
      key: ValueKey('serviceGroup:${group.name}'),
      children: [
        const Expanded(child: Divider(height: 1, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
          ),
        ),
        const Expanded(child: Divider(height: 1, thickness: 1)),
      ],
    );
  }
}

/// Подпись группы для УЗКОЙ колонки ([_SideColumn]) — БЕЗ линий по бокам.
///
/// ⚠️ ЭТО НЕ [_GroupDivider], И ВОТ ПОЧЕМУ. Та строка держит подпись между
/// двумя `Expanded(Divider)`, а `Expanded` требует от родительского `Row`
/// КОНЕЧНУЮ ширину — здесь она есть (колонка получает точную ширину), но сама
/// подпись («Мессенджеры», «Медиа») на этой ширине шире, чем остаётся ПОСЛЕ
/// того, как обеим линиям отдали хотя бы 0 px: `Row` не ужимает несгибаемый
/// текст, и получается `RenderFlex overflowed` ДО того, как до содержимого
/// вообще доберётся внешний `FittedBox` — тот умеет сжимать уже готовый
/// макет, а не чинить макет, упавший при построении. Здесь линия ОДНА, под
/// подписью, а не по бокам от нeё, и подпись сама умеет ужаться (`FittedBox`)
/// или обрезаться многоточием, если совсем не влезает.
class _SideGroupLabel extends StatelessWidget {
  const _SideGroupLabel({required this.group, required this.label});

  final ServiceGroup group;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      // Ключ — на весь блок подписи, как у `_GroupDivider`: по нему страж
      // вёрстки находит группу независимо от того, какая раскладка активна.
      key: ValueKey('serviceGroup:${group.name}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
          ),
        ),
        const SizedBox(height: 2),
        const Divider(height: 1, thickness: 1),
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
      // ⚠️ ВТОРОЙ ПРИЗНАК ЖИВОГО КАНАЛА ОБЯЗАТЕЛЕН, И ВОТ ПОЧЕМУ.
      //
      // Замер «до» идёт МИМО VPN и осмыслен только при выключенном туннеле.
      // Контроллер знает об этом из `_tunnelUp`, но тот выставляется из
      // колбэка главного экрана — то есть с задержкой в кадр. Нажатие «Все» в
      // подменю успевает попасть в это окно, и тогда прямые пробы уходят через
      // уже поднятый туннель, а их результат ложится в графу «без VPN». Колонка
      // «до» после этого врёт, и заметить это нечем — цифры правдоподобные.
      //
      // Параметр существовал с самого начала и был описан в контроллере, но его
      // не передавал НИ ОДИН боевой вызов: предохранитель был, защиты не было.
      final connected =
          context.read<AppState?>()?.status.isConnected ?? false;
      unawaited(ctrl.ensureBaseline(selected, vpnActive: connected));
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
    // Ключ по имени сервиса ставят оба места вызова — см. комментарии там:
    // без него Flutter сопоставляет пары позиционно и путает их состояние.
    super.key,
    required this.service,
    required this.before,
    required this.after,
    required this.live,
    required this.alignEnd,
    required this.onTap,
    this.bypass,
    this.dense = false,
    this.groupLabel,
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

  /// `true` — плотная сетка (`ServiceChecksLayout.grid`): один кружок статуса
  /// поверх иконки вместо пары «до → после», подпись группы уходит целиком в
  /// `Tooltip` — там её видно долгим нажатием, а строка над колонкой ей больше
  /// не нужна.
  final bool dense;

  /// Название группы для подсказки — заполняется только в [dense]. В обычном
  /// виде группу уже называет строка-разделитель над сервисом, дублировать её
  /// в каждой подсказке незачем.
  final String? groupLabel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (dense) return _buildDense(context, l);
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
      // Значок стоит ВПЛОТНУЮ к бренд-иконке, а не с краю строки: так он
      // читается как пометка НА СЕРВИСЕ, а не как ещё один кружок состояния
      // рядом с парой «до → после».
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
    return Tooltip(
      message: _tip(l, rule),
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
              // ⚠️ ПОРЯДОК ОДИНАКОВЫЙ В ОБЕИХ КОЛОНКАХ, ЗЕРКАЛЕНИЯ БОЛЬШЕ НЕТ.
              //
              // Левая колонка раньше разворачивала строку (`items.reversed`),
              // чтобы кружки смотрели на кнопку. Выходило, что бренд-иконки у
              // левой половины сервисов стоят справа, у правой — слева, и глазу
              // не за что зацепиться: чтобы найти нужный сервис, приходилось
              // читать обе колонки по-разному. Требование владельца 18.08.2026 —
              // «помести картинки сервисов у левой панели налево».
              //
              // Выравнивание БЛОКА (`alignment` выше) при этом осталось
              // зеркальным: колонки по-прежнему прижаты к кнопке, разъезжается
              // только внутренний порядок.
              children: items,
            ),
          ),
        ),
      ),
    );
  }

  /// Текст подсказки — общий для обычного вида и [dense]: набор фактов один и
  /// тот же, различается только то, КАК они нарисованы кружками на экране.
  String _tip(AppLocalizations l, SiteRule? rule) {
    // В сетке подписи группы над сервисом нет вовсе (см. [dense]) — имя
    // группы называет только подсказка, иначе оно терялось бы бесследно.
    final head =
        groupLabel == null ? service.label : '$groupLabel · ${service.label}';
    final tip = StringBuffer('$head\n')
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
    return tip.toString();
  }

  /// Плотный вид для `ServiceChecksLayout.grid`: один кружок статуса поверх
  /// иконки вместо пары «до → после» — при 14 сервисах в узкой сетке места на
  /// целую пару нет, а какое-то состояние показать надо. Показываем «после»
  /// при живом VPN, иначе «до» — ровно то состояние, что интереснее человеку
  /// прямо сейчас (см. `_dot` в обычном виде — та же логика).
  Widget _buildDense(BuildContext context, AppLocalizations l) {
    final rule = bypass;
    final outcome = live ? after : before;
    final checking = outcome.state == ServiceCheckState.checking;
    final ringColor = checking
        ? Theme.of(context).disabledColor
        : switch (outcome.state) {
            ServiceCheckState.ok => Colors.green,
            ServiceCheckState.geoBlocked => Colors.orange,
            ServiceCheckState.fail => const Color(0xFFCC7777),
            _ => Theme.of(context).disabledColor,
          };
    return Tooltip(
      message: _tip(l, rule),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 2),
                ),
                child: const SizedBox(width: 28, height: 28),
              ),
              SiteFavicon(domain: service.domain, size: 20, builtIn: true),
              if (checking)
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              // Замок/запрет — тем же значком, что и в обычном виде, только
              // мельче и в углу: сетка тесная, полноразмерный значок рядом с
              // 20-пиксельной иконкой перетянул бы на себя весь кружок.
              if (rule != null)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Icon(
                    rule.action == AppAction.block
                        ? Icons.block
                        : Icons.lock_open_rounded,
                    size: 12,
                    color: rule.action == AppAction.block
                        ? const Color(0xFFCC7777)
                        : Colors.orange,
                  ),
                ),
            ],
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

