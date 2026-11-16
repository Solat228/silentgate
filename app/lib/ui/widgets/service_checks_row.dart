import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/app_log.dart';
import '../../core/probe/auto_config_engine.dart';
import '../../core/probe/service_check.dart';
import '../../core/settings/app_settings.dart';
import '../../core/singbox/exit_outbounds.dart';
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
    final best = _mostSpecific(split, s, (_) => true);
    if (best == null || best.action == AppAction.tunnel) return null;
    return best;
  }

  /// Правило «Туннель» с выбранным сервером (выход), по которому сервис идёт
  /// через ДРУГОЙ сервер, либо `null`.
  ///
  /// ⚠️ В РЕЖИМЕ «ВСЁ ЧЕРЕЗ VPN» ВЫХОДЫ ДЕЙСТВУЮТ, а прочие правила нет
  /// (`SingboxConfigBuilder._addExitOnlyRules`): там выбирается самое
  /// конкретное среди правил с выходом. В остальных режимах выход показан,
  /// только если самое конкретное правило вообще — это он: «google.com →
  /// Германия» + «gemini.google.com → Прямо» уводит Gemini мимо VPN, а не в
  /// Германию.
  ///
  /// Жив ли сервер выхода, здесь не проверяется — это знает ячейка
  /// (сервер мог пропасть из подписки, и трафик идёт основным туннелем).
  static SiteRule? exitRuleFor(SplitTunnelConfig split, ProbeService s) {
    if (split.mode == SplitMode.all) {
      return _mostSpecific(split, s, _isExit);
    }
    final best = _mostSpecific(split, s, (_) => true);
    return best != null && _isExit(best) ? best : null;
  }

  /// Правило, которое ячейка отмечает значком: мимо VPN, блок или выход.
  static SiteRule? markRuleFor(SplitTunnelConfig split, ProbeService s) =>
      bypassRuleFor(split, s) ?? exitRuleFor(split, s);

  static bool _isExit(SiteRule r) =>
      r.action == AppAction.tunnel && r.serverKey != null;

  /// Самое конкретное (длиннейший домен) правило сайта, покрывающее пробу
  /// сервиса, среди тех, что пропускает [use].
  static SiteRule? _mostSpecific(SplitTunnelConfig split, ProbeService s,
      bool Function(SiteRule) use) {
    final targets = domainsOf(s);
    if (targets.isEmpty) return null;
    final port = probePortOf(s);
    SiteRule? best;
    var bestLen = -1;
    for (final r in split.sites) {
      if (!use(r)) continue;
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
///
/// ⚠️ И НЕ ИМЕЕТ ПРАВА ПРОБИТЬ ВЫДАННЫЙ ПОТОЛОК ВЫСОТЫ. Замер 10.09.2026:
/// четырнадцать сервисов рядами на широком окне переполняли панель на 97 px
/// (1024×781) и 117 px (964×761) — причём и в отключённом состоянии, с пустым
/// контроллером проверок. Потолок рядам выдавался (`checksHeightBudget`), а
/// сжатия у них не было вовсе: они просто рисовались ниже кромки. В release
/// полосок переполнения нет — низ экрана молча уезжает за край.
///
/// ⚠️ СЖИМАЕТСЯ ТОЛЬКО СВОЁ СОДЕРЖИМОЕ, КНОПКА CONNECT — НИКОГДА. Простое
/// решение «обернуть весь блок в `FittedBox`» уже пробовали, и это был провал
/// коммита `36229ab`: `FittedBox` жмёт блок ЦЕЛИКОМ, кнопка становилась
/// крошечной, и владелец это забраковал. Поэтому `FittedBox` живёт ЗДЕСЬ,
/// внутри рядов, — тем же приёмом, что и у `ServiceChecksSides` (общий
/// коэффициент на всё содержимое стороны), а кнопка остаётся снаружи и своего
/// диаметра (`connect_button_content_test`).
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
    final content = Column(
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
                  _ServiceCell(
                    // Ключ по имени сервиса — см. `ServiceChecksColumn`.
                    key: ValueKey('svc:${s.name}'),
                    service: s,
                    before: ctrl.baselineFor(s),
                    after: ctrl.resultFor(s),
                    live: live,
                    rule: split == null
                        ? null
                        : ServiceChecks.markRuleFor(split, s),
                    onTap: () => ctrl.check(s, httpPort),
                  ),
              ],
            ),
          ),
          SizedBox(height: compact ? 4 : 8),
        ],
      ],
    );

    return LayoutBuilder(builder: (_, box) {
      // ⚠️ ПОТОЛКА НЕТ — СЖИМАТЬ НЕ ОТ ЧЕГО. Так рядам достаётся телефон
      // (панель целиком в прокрутке) и запасная ветка `ServiceChecksSides`,
      // которая уже меряет их своим `FittedBox`-ом. Лишний `FittedBox` там
      // только смазал бы текст, а на бесконечной высоте коэффициент был бы
      // равен нулю.
      if (!box.hasBoundedHeight) return content;
      return FittedBox(
        // ⚠️ `scaleDown`, А НЕ `contain`: ряды имеют право УМЕНЬШИТЬСЯ, но не
        // раздуться. `contain` растянул бы три сервиса по умолчанию на весь
        // выданный потолок — значки размером с кнопку Connect.
        fit: BoxFit.scaleDown,
        // ⚠️ ШИРИНУ ЗАДАЁМ ЯВНО. `FittedBox` меряет ребёнка в НЕОГРАНИЧЕННОЙ
        // коробке, а внутри рядов `Wrap`: на бесконечной ширине он падает с
        // «BoxConstraints forces an infinite width». Та же грабля уже поймана
        // в `ServiceChecksSides.rowsFallback`.
        child: SizedBox(
          width: box.hasBoundedWidth ? box.maxWidth : null,
          child: content,
        ),
      );
    });
  }
}

/// Проверки сервисов КОЛОНКАМИ ПО БОКАМ кнопки Connect (решение владельца от
/// 27.08.2026) — режимы настройки `sides` и `grid`, и широкое окно в `adaptive`.
///
/// ⚠️ ПОЧЕМУ ЭТО НЕ ПРОСТО ВОЗВРАЩЕНИЕ УДАЛЁННОГО 19.08.2026 `ServiceChecksColumn`.
/// Тот виджет резервировал под колонку фиксированную высоту (семь строк) и на
/// каталоге в 14 сервисов вылезал за нижний край телефона — см. шапку файла и
/// [ServiceChecksLayout] в `app_settings.dart`. Здесь высота, наоборот, НИКОГДА
/// не фиксирована — переполнение (`RenderFlex overflowed`) структурно
/// невозможно ни при каком экране, см. [build].
///
/// ⚠️ БЫЛ БАГ: ОДИН `FittedBox` НА ВЕСЬ БЛОК ТЕРЯЛ ШИРИНУ НА ШИРОКОМ ОКНЕ.
/// До 29.08.2026 колонки и кнопка лежали в одном `Row` фиксированного размера
/// (`natural.width` — константа, не зависящая от окна), и этот `Row` целиком
/// заворачивался в `FittedBox(fit: scaleDown)`. `BoxFit.scaleDown` умеет только
/// СЖИМАТЬ — если натуральный размер блока и без того меньше окна, множитель
/// остаётся 1.0, `FittedBox` рисует блок 1:1 и берёт себе ровно его размер, а
/// не размер, который дал родитель. На растянутом окне это давало крошечный
/// (392 px) остров с кнопкой и двумя колонками, центрированный посреди
/// огромного пустого поля, — ровно то, на что пожаловался владелец. Сейчас
/// [build] отдаёт сторонам всё свободное место и вписывает содержимое
/// `FittedBox`-ом по вычисленному коэффициенту `k` — с ростом до [_maxGrow].
///
/// ⚠️ РОСТ НЕ РАБОТАЛ НИ РАЗУ ДО 09.09.2026. Высота блока (`boxHeight`)
/// считалась по НЕМАСШТАБИРОВАННОЙ высоте стороны ДО вычисления `k`, и
/// `SizedBox(h·k)` внутри зажимался строкой этой высоты: фактический потолок
/// роста был `max(148, tallest) / tallest`, то есть ровно 1,0 при любой
/// стороне выше кнопки — а это все раскладки с пятью группами. `_maxGrow`
/// существовал в коде и не делал ничего. Порядок теперь обратный: сначала
/// `k`, потом высота блока по нему. Страж —
/// `centerpiece_reports_its_height_test` («рост до потолка 1,6»).
///
/// ⚠️ ГРУБАЯ ОЦЕНКА ПО ШИРИНЕ (`_widthFit`) — ДРУГОЕ ЧИСЛО, И ОНО НЕ ОБЯЗАНО
/// БЫТЬ ТОЧНЫМ. От него зависит только порог, ниже которого колонки уступают
/// место привычным рядам под кнопкой, потому что мелкий текст и микроскопические
/// значки читать нельзя, даже если формально они поместились. Ошибка в этой
/// оценке — вопрос красоты (колонки чуть мельче или крупнее, чем могли бы), а не
/// целостности вёрстки: та гарантирована по-прежнему [build] независимо от неё.
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
  /// лезем в него, а просто отводим ему опорную ширину/высоту для измерения.
  static const double _naturalButton = 148.0;

  /// Минимальный просвет между колонкой и кнопкой.
  static const double _gap = 14.0;

  /// Просвет между блоками-группами внутри одной стороны — и по горизонтали,
  /// и между рядами блоков. Одно число на оба измерения намеренно: сетка
  /// читается как сетка, только когда её просветы одинаковы.
  static const double _blockGap = 10.0;

  /// Сколько блоков-групп ложится в один ряд с одной стороны от кнопки —
  /// и сколько рядов сторона может занять.
  ///
  /// ⚠️ КОНСТАНТЫ, А НЕ ФУНКЦИЯ ОТ ШИРИНЫ — ПРЯМОЕ ТРЕБОВАНИЕ ВЛАДЕЛЬЦА
  /// (08.09.2026): «Колонки могут быть в ширину только 2 колонки. В высоту
  /// строки могут быть до 3-ёх штук». До этого число блоков в ряду зависело
  /// от ширины панели (`paneWidth >= 520 ? 3 : 2`), и ровно это условие
  /// рождало жалобу «слева пустует место»: справа три блока в ряд, слева два,
  /// а общий масштаб считался по широкой стороне — левая жалась вслед за
  /// правой и оставляла пустоту у края окна. При двух в ряд пять групп
  /// делятся 2/3, ширины сторон равны (174 = 174), и общий коэффициент
  /// перестаёт обкрадывать левую сторону по построению.
  ///
  /// ⚠️ Потолок в три ряда держит [_splitColumns]: сторона не получает больше
  /// [perRow] × [maxRows] блоков. Групп в приложении пять при потолке
  /// двенадцати; тринадцатая молча уводила бы раскладку в ряды под кнопкой
  /// (см. [build]) — стережёт `side_split_balance_test`.
  static const int perRow = 2;
  static const int maxRows = 3;

  /// Ширина, доступная подписи группы, — ЧУТЬ ШИРЕ ячейки сервиса.
  ///
  /// ⚠️ ЭТО ГЛАВНЫЙ РЫЧАГ РАЗМЕРА ЗНАЧКОВ, и он неочевиден. Ширину блока
  /// задаёт самый широкий его элемент, а это ПОДПИСЬ: чем шире подпись, тем
  /// шире сторона и тем сильнее `BoxFit.contain` жмёт ВЕСЬ блок — значки в
  /// том числе. Поэтому подпись меряется ОДНИМ числом с ячейкой, а не
  /// собственной колонкой.
  ///
  /// ⚠️ ЧЕТЫРЕ ЛИШНИХ ПИКСЕЛЯ ИЗМЕРЕНЫ, А НЕ ПРИКИНУТЫ. «Мессенджеры» шрифтом
  /// 8 занимают около 50 px, и в ячейку 48 не помещались — Flutter рвал слово
  /// по буквам («Мессендже/ры» на снимке из VM, дважды). Запас стоит двух
  /// пикселей размера значка и оставляет название целым.
  static double labelWidthFor(bool dense) => dense ? 34.0 : cellWidth + 4;

  /// Насколько подпись группы может стать шире ячейки, когда по ширине
  /// место есть.
  ///
  /// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА 24.09.2026: «имена и сами сервисы СЛИШКОМ маленькие,
  /// хотя места полно». Замер из его журнала: место 535×225, стороны 155/320
  /// по высоте, масштаб 0,70 — упирается ВЫСОТА (у стороны с тремя группами
  /// два ряда блоков), а по ширине с каждой стороны пустовало около 57 px.
  /// Подпись при этом была зажата в ширину ячейки (82) и рисовалась кеглем
  /// 9 × 0,70 ≈ 6 px. Теперь пустующая ширина отдаётся подписям: масштаб
  /// значков это не трогает (он уже посчитан по высоте), а текст растёт.
  static const double _labelGrowMax = 48;

  /// Потолки кегля подписи: для ОДНОЙ строки и для ДВУХ. Область подписи
  /// ([_SideGroupLabel.labelHeight] = 22) вмещает две строки кеглем 9,5, а
  /// одну — кеглем до 19; одна строка выше 14 уже спорит со значками.
  static const double labelFontMax = 14;
  static const double labelFontTwoLines = 9;
  static const double labelFontMin = 6;

  /// Кегль подписей — ОДИН на все группы экрана — и число строк.
  ///
  /// Сперва пробуем ОДНУ строку: самая длинная подпись целиком в [width].
  /// Если одной строкой выходит мельче, чем двумя, — переносим по словам
  /// («Видео и» / «музыка»), и тогда в ширину обязано влезть самое длинное
  /// СЛОВО.
  ///
  /// ⚠️ ЗАЧЕМ СЧИТАТЬ, А НЕ ЗАДАТЬ ЧИСЛОМ. Я подбирал кегль на глаз дважды
  /// (9, потом 8) и оба раза получал на снимке из VM «Мессендже/ры»: слово
  /// не помещалось и рвалось по буквам. Ширина строки зависит от шрифта,
  /// языка и системных настроек — угадать её нельзя, а измерить можно.
  /// Меряем ТЕМ ЖЕ стилем и с тем же системным масштабом, что рисуем:
  /// расхождение стилей уже давало разрыв слова.
  ///
  /// ⚠️ И кегль ОБЩИЙ намеренно. Сжимать каждую подпись отдельно
  /// (`FittedBox` на каждой) уже пробовали: «Мессенджеры» выходили мелкими,
  /// «ИИ» крупными, столбики значков вставали на разной высоте — жалоба
  /// владельца «а хули они у тебя вразброс».
  /// Заглушка кегля для плотной раскладки, где подписи групп не рисуются.
  /// Нулевой размер выбран нарочно: если такой кегль куда-то утечёт, подпись
  /// пропадёт на виду, а не ужмётся незаметно на пару пикселей.
  static const _unusedLabelFont = (size: 0.0, oneLine: true);

  static ({double size, bool oneLine}) labelFontFor(
      List<GroupedRow> rows, AppLocalizations l,
      {required double width,
      TextStyle? style,
      TextScaler textScaler = TextScaler.noScaling}) {
    // Ширина текста на 1 px кегля: меряем на кегле 10 и делим — текст
    // масштабируется линейно.
    double widthPerPx(String text) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: (style ?? const TextStyle())
              .copyWith(fontSize: 10, height: 1.15, letterSpacing: 0.1),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      return tp.width / 10;
    }

    var wholeWorst = 0.0, wordWorst = 0.0;
    for (final r in rows) {
      final label = r.group.label(l);
      wholeWorst = math.max(wholeWorst, widthPerPx(label));
      for (final word in label.split(' ')) {
        wordWorst = math.max(wordWorst, widthPerPx(word));
      }
    }
    if (wholeWorst <= 0) return (size: labelFontTwoLines, oneLine: false);
    final one = math.min(labelFontMax, width / wholeWorst);
    final two = wordWorst <= 0
        ? labelFontTwoLines
        : math.min(labelFontTwoLines, width / wordWorst);
    if (one >= two) return (size: one, oneLine: true);
    return (size: math.max(labelFontMin, two), oneLine: false);
  }

  /// Ниже этого множителя иконки и подписи превращаются в нечитаемую пыль —
  /// правильнее показать привычные ряды под кнопкой, чем ужимать до предела.
  ///
  /// ⚠️ ПРИМЕНЯЕТСЯ ТОЛЬКО К ШИРИНЕ. При ограниченной ВЫСОТЕ бока остаются
  /// на любом масштабе: `FittedBox` переполнения не даст, а ряды под потолком
  /// сжимают вместе с кнопкой — это был провал коммита 36229ab, откаченного
  /// по снимку из VM («Отключено», «Информация о сервере» и ряды сложились
  /// друг на друга).
  static const double _minReadableScale = 0.62;

  /// Во сколько раз блоку позволено вырасти сверх натурального размера.
  ///
  /// ⚠️ Требование владельца (05.09.2026): «пропорционально оставшемуся
  /// месту, но до определённого размера». Без потолка на широком мониторе
  /// значки раздувались бы вместе с окном — экран превратился бы в набор
  /// гигантских кружков вокруг кнопки.
  static const double _maxGrow = 1.6;

  /// Ниже этого масштаба глиф состояния в углу кольца (12 px) — пятно, а не
  /// знак: при 0,75 кружок 9 px ещё читается, при 0,6 — уже нет. Там кольцо
  /// несёт состояние одно, как и раньше.
  static const double glyphMinScale = 0.75;

  @override
  Widget build(BuildContext context) {
    final rows = ServiceChecks.grouped(services);
    // Проверки выключены целиком — колонкам нечего показывать, но кнопка
    // остаётся: место у неё не отбираем.
    if (rows.isEmpty) return button;

    return LayoutBuilder(builder: (context, c) {
      // Ряды под кнопкой — те же, что на узком телефоне. Включаются в двух
      // случаях: (1) групп больше, чем помещается в сетку 2 × 3 на две
      // стороны, — такого сегодня нет, страж не даст появиться молча;
      // (2) упирается ШИРИНА, и бока вышли бы нечитаемо мелкими.
      //
      // ⚠️ И ЭТА ВЕТКА ТОЖЕ ОБЯЗАНА ВЛЕЗАТЬ. Найдено ревью 05.09.2026:
      // здесь возвращался голый `Column` — ни сжатия, ни прокрутки, и замер
      // показал «RenderFlex overflowed by 277 pixels» при месте 500×171.
      // В release полосок переполнения нет: подписи просто лягут поверх
      // кнопки — ровно та жалоба, из-за которой всю эту вёрстку и
      // переделывали.
      Widget rowsFallback() {
        final fallback = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            button,
            ServiceChecksRows(services: services, httpPort: httpPort),
          ],
        );
        // Высота не ограничена (телефон целиком в прокрутке) — сжимать не от
        // чего, и лишний `FittedBox` только смазал бы текст.
        if (!c.hasBoundedHeight) return fallback;
        return SizedBox(
          height: c.maxHeight,
          child: FittedBox(
            fit: BoxFit.contain,
            // ⚠️ ШИРИНУ ЗАДАЁМ ЯВНО. `FittedBox` меряет ребёнка в
            // НЕОГРАНИЧЕННОЙ коробке, а рядам нужна конечная ширина: внутри
            // есть `Wrap`, и на бесконечности он падает с «BoxConstraints
            // forces an infinite width». Поймано этим же стражем при первой
            // попытке починки — то есть лечение само едва не стало новым
            // дефектом.
            child: SizedBox(
              width: c.hasBoundedWidth ? c.maxWidth : _naturalButton * 2,
              child: fallback,
            ),
          ),
        );
      }

      if (rows.length > perRow * maxRows * 2) return rowsFallback();
      final split = _splitColumns(rows, dense: dense);
      if (_widthFit(c, split) < _minReadableScale) return rowsFallback();

      // ⚠️ ФИКСИРОВАННОЙ ШИРИНЫ У СТОРОНЫ НЕТ: симметрию держат равные
      // `Expanded` по бокам — по построению, а не по совпадению чисел.
      // Зажимать стороны в одинаковый `SizedBox` было нельзя: коробка
      // считалась по колонке 108 px на блок при настоящем содержимом в 82,
      // и `FittedBox` вписывал в место ЭТУ КОРОБКУ вместе с пустотой внутри
      // — вместо роста давал сжатие (снимок 04.09.2026).
      final wL = sideWidthOf(split.left, dense: dense);
      final wR = sideWidthOf(split.right, dense: dense);
      final hL = sideHeightOf(split.left, dense: dense);
      final hR = sideHeightOf(split.right, dense: dense);
      final widest = math.max(wL, wR);
      final tallest = math.max(hL, hR);

      // ⚠️ МАСШТАБ ОДИН НА ОБЕ СТОРОНЫ И СЧИТАЕТСЯ ПЕРВЫМ.
      //
      // Раньше каждая сторона вписывалась в свою половину своим `FittedBox`;
      // блоков в половинах разное число, и три блока ужимались сильнее двух
      // — на снимке из VM правая половина значков выходила заметно мельче
      // левой, хотя стоят они в одной строке. Теперь коэффициент считается
      // по ХУДШЕЙ стороне и применяется к обеим; сторона с меньшим числом
      // блоков просто не занимает свою половину целиком.
      //
      // ⚠️ «БЕЗ ФАНАТИЗМА» обеспечивают ВЫСОТА и [_maxGrow]: рост упирается
      // в потолок, который панель выдаёт блоку, либо в 1,6 — а не раздувает
      // значки вместе с окном. Кнопку не растим: её размер задаёт панель, он
      // одинаков во всех раскладках (`connect_button_content_test`).
      final roomPerSide = (c.maxWidth - _naturalButton - _gap * 2) / 2;
      var k = _maxGrow;
      if (widest > 0) k = math.min(k, roomPerSide / widest);
      if (tallest > 0 && c.hasBoundedHeight) {
        k = math.min(k, c.maxHeight / tallest);
      }
      if (k <= 0 || !k.isFinite) k = 1.0;

      // ⚠️ ВЫСОТА БЛОКА — ПОСЛЕ `k`, А НЕ ДО. Считать её по немасштабированной
      // стороне значило зажать `SizedBox(h·k)` ниже строкой ровно на рост —
      // см. шапку класса. И блок занимает СВОЮ высоту, а не весь выданный
      // потолок: потолок — ограничение («больше нельзя»), а не задание
      // («займи столько»); разница видна, когда сервисов мало (замер
      // 05.09.2026: 190 px пустоты под тремя значками, низ панели за краем).
      final wanted = math.max(_naturalButton, tallest * k);
      final boxHeight =
          c.hasBoundedHeight ? math.min(c.maxHeight, wanted) : wanted;
      final showGlyph = k >= glyphMinScale;

      // Пустующая по ширине часть стороны — подписям (см. [_labelGrowMax]).
      // Масштаб уже посчитан, и расширение его не меняет: сторона растёт
      // ровно до места, которое у неё и так было.
      var labelWidth = labelWidthFor(dense);
      if (!dense && k > 0) {
        final inRow = math.min(
            perRow, math.max(split.left.length, split.right.length));
        final slack = roomPerSide / k - widest - 0.5;
        if (inRow > 0 && slack > 0) {
          labelWidth += math.min(slack / inRow, _labelGrowMax);
        }
      }
      final wL2 = sideWidthOf(split.left, dense: dense, labelWidth: labelWidth);
      final wR2 =
          sideWidthOf(split.right, dense: dense, labelWidth: labelWidth);
      // ⚠️ КЕГЛЬ СЧИТАЕТСЯ ПО ВСЕМ ГРУППАМ ЭКРАНА, А НЕ ПО СТОРОНЕ. Раньше
      // каждая сторона подбирала свой: слева «Мессенджеры» выходили одним
      // кеглем, справа «Видео и музыка» — другим, и подписи в одной строке
      // вокруг кнопки были разного размера (поймано стражем 24.09.2026).
      // ⚠️ В плотной раскладке подписей групп нет вовсе — название уходит в
      // подсказку, и `labelFont` не читает никто. Считать его там незачем:
      // `labelFontFor` раскладывает `TextPainter` по каждому слову каждой
      // группы, а эта сборка идёт на КАЖДЫЙ тик проверки сервисов.
      final labelFont = dense
          ? _unusedLabelFont
          : labelFontFor(rows, AppLocalizations.of(context),
              width: labelWidth,
              style: Theme.of(context).textTheme.labelSmall,
              textScaler: MediaQuery.textScalerOf(context));

      final left = _SideColumn(
        rows: split.left,
        httpPort: httpPort,
        dense: dense,
        alignEnd: true,
        showGlyph: showGlyph,
        labelWidth: labelWidth,
        labelFont: labelFont,
      );
      final right = _SideColumn(
        rows: split.right,
        httpPort: httpPort,
        dense: dense,
        alignEnd: false,
        showGlyph: showGlyph,
        labelWidth: labelWidth,
        labelFont: labelFont,
      );
      final buttonBox = SizedBox(
        width: _naturalButton,
        height: _naturalButton,
        child: Center(child: button),
      );

      _logSides(c, split, k: k, dense: dense);

      // ⚠️ `SizedBox` с ЯВНЫМ размером обязателен: `FittedBox` растягивает
      // содержимое, только когда ему самому задан размер. Со свободными
      // ограничениями он принимает размер ребёнка, и `BoxFit.contain` не
      // делает ничего — блок остаётся натуральным посреди пустого места.
      Widget scaled(Widget side, double w, double h, Alignment toButton) =>
          Expanded(
            child: Align(
              // Прижим к кнопке: пустое место уходит к краю окна, а не в
              // промежуток между блоками и кнопкой.
              alignment: toButton,
              child: SizedBox(
                width: w * k,
                height: h * k,
                child: FittedBox(fit: BoxFit.contain, child: side),
              ),
            ),
          );

      return SizedBox(
        height: boxHeight,
        child: Row(
          key: const ValueKey('serviceChecksSidesRow'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            scaled(left, wL2, hL, Alignment.centerRight),
            const SizedBox(width: _gap),
            buttonBox,
            const SizedBox(width: _gap),
            scaled(right, wR2, hR, Alignment.centerLeft),
          ],
        ),
      );
    });
  }

  /// Насколько пришлось бы сжать блок ПО ШИРИНЕ, чтобы он влез в `c` —
  /// ОЦЕНКА для решения «показывать колонки или ряды», не фактический
  /// рендер (тот считает `FittedBox` сам, по-настоящему).
  ///
  /// Высота здесь не участвует намеренно — см. [_minReadableScale].
  double _widthFit(
      BoxConstraints c, ({List<GroupedRow> left, List<GroupedRow> right}) split) {
    final natural = sideWidthOf(split.left, dense: dense) +
        sideWidthOf(split.right, dense: dense) +
        _naturalButton +
        _gap * 2;
    if (natural <= 0) return 1.0;
    return math.min(1.0, c.maxWidth / natural);
  }

  /// Ширина одной стороны при масштабе 1.0.
  ///
  /// [labelWidth] — ширина подписи, если она расширена под свободное место
  /// (см. [_labelGrowMax]); по умолчанию — [labelWidthFor].
  static double sideWidthOf(List<GroupedRow> rows,
      {required bool dense, double? labelWidth}) {
    if (rows.isEmpty) return 0;
    if (dense) {
      // ⚠️ СЕТКА РИСУЕТСЯ ИНАЧЕ, ЧЕМ БЛОКИ. Найдено ревью 05.09.2026 замером:
      // `_SideColumn` в этом режиме строит колонку из `Wrap`-ов — КАЖДАЯ
      // ГРУППА своей строкой, и внутри строки иконки идут в одну линию
      // (ширина у `FittedBox` не ограничена). Формула, считавшая блоки бок
      // о бок, давала коробки не по содержимому, общий коэффициент
      // переставал быть общим: значки 25 px слева против 39 справа.
      // Считаем то, что рисуется: самая длинная группа задаёт ширину.
      var widest = 0.0;
      for (final r in rows) {
        final n = r.services.length;
        final w = _denseIcon * n + _denseGap * (n - 1);
        if (w > widest) widest = w;
      }
      return widest;
    }
    final inRow = rows.length < perRow ? rows.length : perRow;
    return (labelWidth ?? labelWidthFor(dense)) * inRow +
        _blockGap * (inRow - 1);
  }

  /// Размеры одной ячейки в режиме «сетка» — списаны с того, что реально
  /// рисует `_SideColumn`: ячейка 40 (рамка 30 и поле 5 под значки по углам),
  /// просвет `Wrap` 4.
  static const double _denseIcon = 40;
  static const double _denseGap = 4;

  /// Высота ОДНОГО блока-группы при масштабе 1.0 — то, что реально рисует
  /// `_SideColumn`: подпись 22 + 2 + линия 1, зазор 4, на сервис — ячейка
  /// [cellWidth] (квадратная, поле под значки по углам уже внутри).
  ///
  /// ⚠️ ОДНА ФОРМУЛА НА ВСЁ. До 09.09.2026 их было ДВЕ (`sideHeightOf` и
  /// `_naturalSize`), и они уже расходились с вёрсткой и друг с другом
  /// (34 на сервис при настоящих 36; просвет ряда прибавлялся и после
  /// последнего). По этой высоте считаются и масштаб, и делёж сторон — ошибка
  /// в ней это сжатие там, где место есть, или перекос сторон.
  static double blockHeightOf(GroupedRow r, {required bool dense}) => dense
      ? _denseIcon
      : _SideGroupLabel.labelHeight +
          2 +
          1 +
          4 +
          r.services.length * cellWidth;

  /// Высота одной стороны при масштабе 1.0: сумма РЯДОВ (в ряду — самый
  /// высокий блок) и просвет [_blockGap] ТОЛЬКО МЕЖДУ рядами.
  static double sideHeightOf(List<GroupedRow> rows, {required bool dense}) {
    if (rows.isEmpty) return 0;
    if (dense) {
      // Каждая группа — своей строкой (см. [sideWidthOf]), просвет между
      // строками — и только между.
      return _denseIcon * rows.length + _denseGap * (rows.length - 1);
    }
    var h = 0.0;
    var rowCount = 0;
    for (var i = 0; i < rows.length; i += perRow) {
      var tallest = 0.0;
      for (var j = i; j < math.min(i + perRow, rows.length); j++) {
        tallest = math.max(tallest, blockHeightOf(rows[j], dense: dense));
      }
      h += tallest;
      rowCount++;
    }
    return h + _blockGap * (rowCount - 1);
  }

  /// Тот же делёж, доступный стражу: равновесие сторон глазами видно, а
  /// тестом — только через эту точку (сам делёж приватен, а поднимать ради
  /// него всё дерево значит проверять вёрстку вместо арифметики).
  @visibleForTesting
  static ({List<GroupedRow> left, List<GroupedRow> right}) splitForTest(
          List<GroupedRow> rows,
          {required bool dense}) =>
      const ServiceChecksSides(services: [], httpPort: 0, button: SizedBox())
          ._splitColumns(rows, dense: dense);

  /// Раскладывает ГРУППЫ (не отдельные сервисы — группа не разрывается между
  /// сторонами, иначе смысл ряда потерялся бы, см. шапку файла) по двум
  /// сторонам, примерно поровну по высоте.
  ({List<GroupedRow> left, List<GroupedRow> right}) _splitColumns(
      List<GroupedRow> rows,
      {required bool dense}) {
    if (rows.length < 2) return (left: rows, right: const <GroupedRow>[]);

    // ⚠️ ДЕЛИМ ПОРОВНУ ПО ВЫСОТЕ, А НЕ ПО ЧИСЛУ БЛОКОВ — решение владельца
    // (04.09.2026). С сеткой это разные вещи: два блока по три сервиса и
    // шесть блоков по одному дают одинаковое число строк и совершенно разную
    // высоту стороны. Высота — ТА ЖЕ формула, что и у рендера
    // ([sideHeightOf]): второй копии, которая могла бы разойтись, нет.
    double heightOf(List<GroupedRow> side) => sideHeightOf(side, dense: dense);

    // Порядок групп сохраняем: перетасовать их значило бы, что привычное
    // место сервиса меняется от набора к набору. Ищем лучшую ТОЧКУ РАЗРЕЗА.
    //
    // ⚠️ ПРИ РАВНОЙ ВЫСОТЕ РЕШАЕТ ЧИСЛО БЛОКОВ — БЕЗ ЭТОГО СТОРОНЫ ВЫХОДЯТ
    // 1 ПРОТИВ 4. Высота стороны считается по РЯДАМ, а в ряду берётся самый
    // высокий блок: сторона из одного блока и сторона из двух дают ОДНУ И ТУ
    // ЖЕ высоту. По высоте все разрезы равны, и выигрывал просто первый.
    // Поймано живым снимком из VM 04.09.2026: числа сходились, тесты были
    // зелёными, а экран выглядел перекошенным.
    //
    // ⚠️ ПОТОЛОК В ТРИ РЯДА: разрез, отдающий стороне больше [perRow] ×
    // [maxRows] блоков, не рассматривается вовсе. Число групп сверх удвоенного
    // потолка сюда не доходит — [build] уводит такое в ряды.
    const maxPerSide = perRow * maxRows;
    final lo = math.max(1, rows.length - maxPerSide);
    final hi = math.min(rows.length - 1, maxPerSide);
    var bestCut = (rows.length / 2).ceil();
    var bestDiff = -1.0;
    var bestCountDiff = -1;
    for (var cut = lo; cut <= hi; cut++) {
      final diff =
          (heightOf(rows.sublist(0, cut)) - heightOf(rows.sublist(cut))).abs();
      final countDiff = (cut - (rows.length - cut)).abs();
      final better = bestDiff < 0 ||
          diff < bestDiff ||
          (diff == bestDiff && countDiff < bestCountDiff);
      if (better) {
        bestDiff = diff;
        bestCountDiff = countDiff;
        bestCut = cut;
      }
    }
    return (left: rows.sublist(0, bestCut), right: rows.sublist(bestCut));
  }
}

/// Одна сторона внутри [ServiceChecksSides]: сетка блоков-групп.
class _SideColumn extends StatelessWidget {
  const _SideColumn({
    required this.rows,
    required this.httpPort,
    required this.dense,
    required this.alignEnd,
    required this.showGlyph,
    required this.labelWidth,
    required this.labelFont,
  });

  final List<GroupedRow> rows;
  final int httpPort;

  /// Ширина подписи группы — см. `ServiceChecksSides._labelGrowMax`.
  final double labelWidth;

  /// Кегль подписей — общий на обе стороны, см. `labelFontFor`.
  final ({double size, bool oneLine}) labelFont;
  final bool dense;

  /// Рисовать ли глиф состояния в углу кольца — см.
  /// [ServiceChecksSides.glyphMinScale].
  final bool showGlyph;

  /// Левая сторона прижимает неполный ряд к кнопке (к правому краю), правая
  /// — наоборот. Половины рамки внутри ячейки при этом одинаковые с обеих
  /// сторон — см. [_ServiceCell].
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final ctrl = context.watch<ServiceCheckController>();
    final live = httpPort > 0;
    // Настройки — необязательно, см. `ServiceChecksRows`.
    final split = context.watch<SettingsController?>()?.settings.splitTunnel;

    SiteRule? markOf(ProbeService s) =>
        split == null ? null : ServiceChecks.markRuleFor(split, s);

    if (dense) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              // Просвет — только МЕЖДУ строками, как и считает
              // `sideHeightOf`: после последней его нет.
              padding: EdgeInsets.only(
                  bottom: i == rows.length - 1
                      ? 0
                      : ServiceChecksSides._denseGap),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: ServiceChecksSides._denseGap,
                runSpacing: ServiceChecksSides._denseGap,
                children: [
                  for (final s in rows[i].services)
                    _ServiceCell(
                      key: ValueKey('svc:${s.name}'),
                      service: s,
                      before: ctrl.baselineFor(s),
                      after: ctrl.resultFor(s),
                      live: live,
                      dense: true,
                      showGlyph: showGlyph,
                      groupLabel: rows[i].group.label(l),
                      rule: markOf(s),
                      onTap: () => ctrl.check(s, httpPort),
                    ),
                ],
              ),
            ),
        ],
      );
    }

    // ⚠️ БЛОКИ СЕТКОЙ: ДВА В ШИРИНУ, ДО ТРЁХ В ВЫСОТУ.
    //
    // Требование владельца 04.09.2026, и оно решает беду, из-за которой блок
    // не влезал в минимальное окно ВООБЩЕ. Раньше группы шли одна под другой
    // единым столбцом, и высота росла с КАЖДЫМ добавленным сервисом:
    // четырнадцать штук давали 366 px при доступных 237, и никакое сжатие
    // этого не лечило — жать пришлось бы до нечитаемого.
    //
    // ⚠️ Ширина каждого блока — ПО СОДЕРЖИМОМУ (`IntrinsicWidth`), а не по
    // общей колонке. Прежняя жалоба («линия отчёркивания слишком длинная»)
    // была ровно об этом: линия под подписью шла во всю ширину колонки
    // независимо от того, сколько под ней иконок.
    final blocks = <Widget>[
      for (final row in rows)
        IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SideGroupLabel(
                group: row.group,
                label: row.group.label(l),
                maxWidth: labelWidth,
                fontSize: labelFont.size,
                oneLine: labelFont.oneLine,
              ),
              const SizedBox(height: 4),
              for (final s in row.services)
                // По центру блока: подпись бывает шире ячейки (см.
                // `_labelGrowMax`), и без этого значки прижимались бы к
                // левому краю под центрованной подписью. Просвета между
                // ячейками нет: поле вокруг рамки уже есть в самой ячейке.
                Center(
                  child: _ServiceCell(
                    key: ValueKey('svc:${s.name}'),
                    service: s,
                    before: ctrl.baselineFor(s),
                    after: ctrl.resultFor(s),
                    live: live,
                    showGlyph: showGlyph,
                    rule: markOf(s),
                    onTap: () => ctrl.check(s, httpPort),
                  ),
                ),
            ],
          ),
        ),
    ];

    final gridRows = <List<Widget>>[];
    for (var i = 0; i < blocks.length; i += ServiceChecksSides.perRow) {
      gridRows.add(blocks.sublist(
          i, math.min(i + ServiceChecksSides.perRow, blocks.length)));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      // Неполный последний ряд прижимается к кнопке, а не повисает у края
      // окна: так обе стороны читаются как одно целое вокруг кнопки.
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        for (var r = 0; r < gridRows.length; r++)
          Padding(
            padding: EdgeInsets.only(
                bottom: r == gridRows.length - 1
                    ? 0
                    : ServiceChecksSides._blockGap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < gridRows[r].length; i++) ...[
                  if (i > 0)
                    const SizedBox(width: ServiceChecksSides._blockGap),
                  gridRows[r][i],
                ],
              ],
            ),
          ),
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
  const _SideGroupLabel({
    required this.group,
    required this.label,
    required this.maxWidth,
    required this.fontSize,
    required this.oneLine,
  });

  final ServiceGroup group;
  final String label;

  /// Ширина, в которую подпись обязана уложиться.
  ///
  /// ⚠️ ЭТО ГЛАВНЫЙ РЫЧАГ РАЗМЕРА ЗНАЧКОВ, и он совершенно неочевиден. Ширину
  /// блока задаёт самый широкий его элемент, а это ПОДПИСЬ: «Видео и музыка»
  /// в одну строку занимает около 78 px против 41 у самой ячейки. Пока подпись
  /// шире содержимого, увеличивать значки бесполезно — сторона упирается в неё.
  ///
  /// Поэтому подпись переносится на ВТОРУЮ СТРОКУ, а не обрезается: требование
  /// владельца — «текст не обрезай». Перенос стоит ~14 px высоты, а даёт около
  /// 35 px ширины на каждый блок, то есть примерно полтора размера значка.
  final double maxWidth;

  /// Высота области подписи — ровно две строки шрифтом 9 с интерлиньяжем
  /// 1.15. Фиксирована намеренно: у всех групп она обязана быть одинаковой,
  /// иначе столбики значков под подписями встают на разной высоте.
  /// Кегль, общий на все группы экрана (см. `labelFontFor`).
  final double fontSize;

  /// Подпись целиком в одну строку (место позволило) — иначе перенос по
  /// словам. Решается сразу для всех групп, см. `labelFontFor`.
  final bool oneLine;

  static const double labelHeight = 22;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wraps = !oneLine && label.contains(' ');
    return Column(
      // Ключ — на весь блок подписи, как у `_GroupDivider`: по нему страж
      // вёрстки находит группу независимо от того, какая раскладка активна.
      key: ValueKey('serviceGroup:${group.name}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // ⚠️ ВЫСОТА ОБЛАСТИ ПОДПИСИ ОДНА У ВСЕХ ГРУПП — ЭТО И ДЕРЖИТ
        // ЗНАЧКИ В ЛИНИЮ.
        //
        // Жалоба владельца 04.09.2026: «а хули они у тебя вразброс». Причина
        // была не в кегле, а в РАЗНОЙ ВЫСОТЕ подписей: однословная занимала
        // строку, двухсловная — две, и столбик значков под ней уезжал вниз.
        // Теперь область фиксирована [labelHeight], и сколько бы строк ни
        // заняла подпись, значки начинаются с одной высоты.
        //
        // ⚠️ КЕГЛЬ ПОДБИРАЕТ САМ `FittedBox`, И ЭТО ПОСЛЕ ДВУХ НЕУДАЧ.
        // Задавать его числом я пробовал дважды (9, потом 8) — оба раза на
        // снимке из VM выходило «Мессендже/ры»: слово не влезало и рвалось по
        // буквам. Вычислять кегль `TextPainter`-ом тоже не помогло: меряется
        // один стиль, а рисуется другой (тема добавляет своё), и расхождения
        // хватает, чтобы слово не поместилось. `FittedBox` меряет то самое,
        // что рисует.
        //
        // Многословные названия переносятся ПО СЛОВАМ («Видео и» / «музыка» —
        // как просил владелец), однословные ужимаются в строку целиком.
        SizedBox(
          width: maxWidth,
          height: labelHeight,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wraps ? maxWidth : double.infinity,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: wraps ? 2 : 1,
                  softWrap: wraps,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: fontSize,
                        height: 1.15,
                        letterSpacing: 0.1,
                      ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(width: maxWidth, child: const Divider(height: 1, thickness: 1)),
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
    // ⚠️ ТУГАЯ КОРОБКА [size], И `SizedBox` СНАРУЖИ ОБЯЗАТЕЛЕН. Кнопка стоит
    // в полосе плашки активного сервера (`ActiveServerBanner.trailing`) и не
    // имеет права её растить: область нажатия Material (`tapTargetSize:
    // padded`) тянет `IconButton` до 40 px по высоте, если родитель не зажал,
    // — полоса поднялась бы на 12 px и съела треть выигрыша от убранной
    // легенды. Тот же размер у соседней «i» (`InfoTooltip.compactSize`).
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        icon: const Icon(Icons.tune, size: 18),
        tooltip: l.serviceChecksMenuTooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: size, height: size),
        onPressed: () => _open(context),
      ),
    );
  }

  /// Сторона кнопки — см. [build].
  static const double size = 28;

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

/// Размеры ячейки сервиса: значок, рамка, просвет до значка, разрез рамки и
/// значки по углам.
///
/// ⚠️ ЧИСЛА ИЗ МАКЕТА, УТВЕРЖДЁННОГО ВЛАДЕЛЬЦЕМ 28.10.2026 (вариант 4): значок
/// 28, рамка 4, просвет 3, разрез 6, значки 16; в плотной сетке 20/3/2/5/12.
/// Ячейка — бокс рамки плюс поле [pad] с каждой стороны: значки по углам
/// выступают за бокс на треть своего размера, и поле не даёт им лечь на
/// соседнюю ячейку.
class _CellMetrics {
  const _CellMetrics({
    required this.icon,
    required this.stroke,
    required this.inner,
    required this.split,
    required this.badge,
    required this.pad,
  });

  final double icon, stroke, inner, split, badge;

  /// Поле вокруг бокса, не меньше выступа значков ([overhang]).
  final double pad;

  double get box => icon + 2 * (stroke + inner);
  double get overhang => badge * 0.35;
  double get slot => box + 2 * pad;
  double get radius => box * 0.3;

  static const normal =
      _CellMetrics(icon: 28, stroke: 4, inner: 3, split: 6, badge: 16, pad: 6);
  static const dense =
      _CellMetrics(icon: 20, stroke: 3, inner: 2, split: 5, badge: 12, pad: 5);
}

/// Сторона ячейки сервиса на масштабе 1.0: бокс 28 + 2·(4 + 3) = 42 и поле 6
/// с каждой стороны — 54. Совпадает с `_CellMetrics.normal.slot` (страж —
/// `service_status_ring_test`); константой, а не геттером, потому что от неё
/// считается вёрстка сторон и её читают тесты.
///
/// Ширина постоянная: замер «через VPN» живёт в правой половине той же рамки,
/// поэтому подключение ячейку не расширяет и экран не дёргается.
const double cellWidth = 54;

/// Что правило раздельного туннелирования делает с сервисом — от этого
/// зависят форма рамки и значки по углам.
enum _RuleMark { none, direct, block, exit }

/// Красный отказа и запрета. Ярче прежнего `0xFFCC7777`: владелец просил
/// «красный поярче» на макете 27.10.2026.
const _failRed = Color(0xFFE35D5D);

/// Синий замка «через другой сервер».
const _exitBlue = Color(0xFF5B9BF0);

/// Рамка ячейки: две половины (без VPN / через VPN) либо цельный круг —
/// сервис идёт мимо VPN, и замер «через VPN» не имеет смысла.
///
/// ⚠️ ПОЛОВИНЫ НЕ СОПРИКАСАЮТСЯ: сверху и снизу разрез [split] цвета фона.
/// Слитая рамка двух цветов читалась как одна «пёстрая», а не как два замера.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.left,
    required this.right,
    required this.stroke,
    required this.split,
    required this.radius,
    required this.circle,
  });

  final Color left, right;
  final double stroke, split, radius;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (circle) {
      canvas.drawCircle(size.center(Offset.zero), size.width / 2 - stroke / 2,
          paint..color = left);
      return;
    }
    final rr = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(stroke / 2), Radius.circular(radius));
    final half = size.width / 2;
    for (final (rect, color) in [
      (Rect.fromLTRB(0, 0, half - split / 2, size.height), left),
      (Rect.fromLTRB(half + split / 2, 0, size.width, size.height), right),
    ]) {
      canvas.save();
      canvas.clipRect(rect);
      canvas.drawRRect(rr, paint..color = color);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) =>
      o.left != left ||
      o.right != right ||
      o.stroke != stroke ||
      o.split != split ||
      o.radius != radius ||
      o.circle != circle;
}

/// Замок, нарисованный своим путём, а не глифом Material.
///
/// ⚠️ У глифа `lock_open` дужка отходит от корпуса на 1 px и в размере 12–16
/// выглядит закрытой. Здесь у открытого замка дужка поднята и сдвинута ВПРАВО
/// за край корпуса (просьба владельца). Вся геометрия — по пиксельной сетке:
/// дробные координаты размывали ногу дужки на два пикселя, и она выглядела
/// наклонённой («дужка кривая» — замечание владельца, 27.10.2026).
class _LockPainter extends CustomPainter {
  _LockPainter({required this.open, required this.color, required this.bg});

  final bool open;
  final Color color, bg;

  @override
  void paint(Canvas canvas, Size sz) {
    final s = sz.width;
    final w = math.max(1.5, (.14 * s).roundToDouble());
    final half = w.round().isOdd ? .5 : 0.0;
    double x(double v) => (v * s).roundToDouble() + half;
    double y(double v) => (v * s).roundToDouble();
    final body = RRect.fromRectAndRadius(
        Rect.fromLTRB(y(.08), y(.46), y(.74), y(.96)),
        Radius.circular(.12 * s));
    final double l, r, top;
    if (open) {
      l = x(.52);
      r = x(.88);
      top = y(.28);
    } else {
      l = x(.24);
      r = x(.58);
      top = y(.34);
    }
    final rad = (r - l) / 2;
    final shackle = Path()
      ..moveTo(l, y(.5))
      ..lineTo(l, top)
      ..arcTo(Rect.fromLTRB(l, top - rad, r, top + rad), math.pi, math.pi,
          false)
      ..lineTo(r, open ? y(.40) : y(.5));
    // Сперва контур цвета фона (тот же путь толще), потом сам замок: так
    // он читается поверх рамки любого цвета.
    for (final (c, extra) in [(bg, 2.0), (color, 0.0)]) {
      canvas.drawPath(
          shackle,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = w + extra
            ..color = c);
      canvas.drawRRect(body.inflate(extra / 2), Paint()..color = c);
    }
    // Скважина — цветом фона.
    canvas.drawCircle(
        Offset(body.center.dx, .69 * s), .07 * s, Paint()..color = bg);
  }

  @override
  bool shouldRepaint(covariant _LockPainter o) =>
      o.open != open || o.color != color || o.bg != bg;
}

/// Значок Material с контуром цвета фона в 1 px — иначе он сливается с
/// рамкой того же цвета.
Widget _outlinedIcon(IconData icon, double size, Color color, Color bg) => Icon(
      icon,
      size: size,
      color: color,
      shadows: [
        for (final o in const [
          Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1), //
          Offset(1, 1), Offset(-1, -1), Offset(1, -1), Offset(-1, 1),
        ])
          Shadow(color: bg, offset: o),
      ],
    );

/// ЗНАЧОК СЕРВИСА В РАЗРЕЗАННОЙ РАМКЕ — одна ячейка вместо пары «до → после».
///
/// ⚠️ ДИЗАЙН УТВЕРЖДЁН ВЛАДЕЛЬЦЕМ 27–28.10.2026 по макету (вариант 4):
/// - левая половина рамки — замер БЕЗ VPN, правая — ЧЕРЕЗ VPN; половины не
///   касаются;
/// - слева сверху открытый замок, справа сверху закрытый: какая половина что
///   значит, видно без легенды;
/// - справа снизу кружок со знаком ✓ / ! / ✕ — как сейчас (через VPN при
///   живом канале, иначе без VPN);
/// - правило «Прямо»: рамка круглая и одноцветная (замер «через VPN» идёт тем
///   же прямым путём), слева сверху развилка, справа значка нет;
/// - правило «Блок»: справа сверху красный запрет;
/// - правило через другой сервер: справа сверху синий замок со стрелкой;
/// - у каждого элемента своя подсказка.
///
/// Прежняя пара с двумя значками и стрелкой занимала 78 px в ширину и делила
/// одно сравнение на два значка; рамка несёт оба замера на одном значке.
///
/// ⚠️ ПОРЯДОК ПОЛОВИН ЗАКРЕПЛЁН (`Directionality.ltr`), В ФАРСИ ТОЖЕ. Подсказка
/// «i» на десяти языках говорит «левая половина — без VPN»; зеркальная рамка в
/// RTL сделала бы эту фразу ложью — ровно то, что ревью 05.09.2026 нашло у
/// прежней пары.
class _ServiceCell extends StatelessWidget {
  const _ServiceCell({
    // Ключ по имени сервиса ставят все места вызова: без него Flutter
    // сопоставляет ячейки позиционно и путает их состояние.
    super.key,
    required this.service,
    required this.before,
    required this.after,
    required this.live,
    required this.onTap,
    this.rule,
    this.dense = false,
    this.showGlyph = true,
    this.groupLabel,
  });

  final ProbeService service;
  final ServiceCheckOutcome before;
  final ServiceCheckOutcome after;
  final bool live;
  final VoidCallback onTap;

  /// Правило из [ServiceChecks.markRuleFor]: «Прямо», «Блок» или туннель через
  /// другой сервер. `null` — сервис идёт как весь остальной трафик.
  final SiteRule? rule;

  /// Плотная сетка (`ServiceChecksLayout.grid`): ячейка меньше, подпись группы
  /// уходит в подсказку значка.
  final bool dense;

  /// Знак состояния справа снизу — см. [ServiceChecksSides.glyphMinScale].
  final bool showGlyph;

  /// Название группы для подсказки — только в [dense].
  final String? groupLabel;

  /// Цвет состояния — им красятся половины рамки и кружок знака.
  static Color statusColor(BuildContext context, ServiceCheckOutcome o) =>
      switch (o.state) {
        ServiceCheckState.ok => Colors.green,
        ServiceCheckState.geoBlocked => Colors.orange,
        ServiceCheckState.fail => _failRed,
        _ => Theme.of(context).disabledColor,
      };

  /// Знак справа снизу: ✓ / ! / ✕. У «идёт проверка» и «не проверено» знака
  /// нет — там нечего утверждать.
  ///
  /// ⚠️ НЕ `Icons.block` для отказа: запрет — значок правила «Блок».
  static IconData? glyphFor(ServiceCheckOutcome o) => switch (o.state) {
        ServiceCheckState.ok => Icons.check,
        ServiceCheckState.geoBlocked => Icons.priority_high,
        ServiceCheckState.fail => Icons.close,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context);
    final bg = t.scaffoldBackgroundColor;
    final m = dense ? _CellMetrics.dense : _CellMetrics.normal;
    final rule = this.rule;

    // Имя сервера выхода. ⚠️ `select`, а не `watch`: состояние приложения
    // уведомляет на каждый тик счётчиков трафика, а здесь нужна одна строка.
    // Сервер исчез из подписки или не годится в выход — трафик правила идёт
    // основным туннелем (`ExitOutbounds.build`), и синий замок соврал бы.
    final exitKey = rule != null &&
            rule.action == AppAction.tunnel &&
            rule.serverKey != null
        ? rule.serverKey
        : null;
    final exitServer = exitKey == null
        ? null
        : context.select<AppState?, String?>((s) {
            if (s == null) return null;
            for (final v in s.servers) {
              if (v.key == exitKey) {
                return canBeExitServer(v) ? v.displayName : null;
              }
            }
            return null;
          });

    final mark = switch (rule?.action) {
      AppAction.direct => _RuleMark.direct,
      AppAction.block => _RuleMark.block,
      AppAction.tunnel when exitServer != null => _RuleMark.exit,
      _ => _RuleMark.none,
    };
    final direct = mark == _RuleMark.direct;
    final now = live ? after : before;
    final left = direct ? now : before;
    final glyph = showGlyph ? glyphFor(now) : null;
    final ink = t.colorScheme.onSurface;
    final o = m.overhang;

    String word(ServiceCheckOutcome x) => switch (x.state) {
          ServiceCheckState.ok => l.serviceStatusOk,
          ServiceCheckState.geoBlocked => l.serviceStatusGeo,
          ServiceCheckState.fail => l.serviceStatusFail,
          ServiceCheckState.checking => l.serviceStatusChecking,
          ServiceCheckState.idle => l.serviceStatusTap,
        };
    final beforeTip = before.state == ServiceCheckState.idle
        ? l.serviceChecksNoBaseline
        : '${l.serviceChecksBefore}: ${word(before)}';
    final afterTip = '${l.serviceChecksAfter}: '
        '${live ? word(after) : l.serviceChecksAfterOff}';
    final ruleTip = rule == null
        ? null
        : switch (mark) {
            _RuleMark.direct => l.serviceChecksBypassDirect(rule.label),
            _RuleMark.block => l.serviceChecksBypassBlock(rule.label),
            _RuleMark.exit =>
              l.serviceChecksExitServer(rule.label, exitServer!),
            _RuleMark.none => null,
          };

    // Подсказка значка: имя (с группой в сетке, где подписи над ним нет) и
    // что будет по нажатию. У YouTube — оговорка про замедление: зелёная рамка
    // рядом с не грузящимся видео выглядит враньём.
    final head =
        groupLabel == null ? service.label : '$groupLabel · ${service.label}';
    final iconTip = StringBuffer('$head\n${l.serviceStatusTap}');
    if (service == ProbeService.youtube) {
      iconTip.write('\n\n${l.serviceYoutubeThrottleNote}');
    }

    // Невидимая зона под подсказкой половины рамки: `ColoredBox` принимает
    // наведение и долгое нажатие, пустой `SizedBox` — нет.
    Widget zone(String tip) => Tooltip(
        message: tip,
        child: const ColoredBox(color: Colors.transparent));

    final iconInset = m.stroke + m.inner;
    Widget icon = SiteFavicon(domain: service.domain, size: m.icon, builtIn: true);
    icon = direct
        ? ClipOval(child: icon)
        : ClipRRect(
            borderRadius: BorderRadius.circular(m.radius - iconInset),
            child: icon);

    final Widget? rightBadge = switch (mark) {
      _RuleMark.none => Tooltip(
          message: afterTip,
          child: _lock(false, m.badge, ink, bg),
        ),
      _RuleMark.exit => Tooltip(
          message: ruleTip!,
          child: Stack(clipBehavior: Clip.none, children: [
            _lock(false, m.badge, _exitBlue, bg),
            Positioned(
              right: -m.badge * .5,
              bottom: -m.badge * .15,
              child: _outlinedIcon(
                  Icons.arrow_forward_rounded, m.badge * .62, _exitBlue, bg),
            ),
          ]),
        ),
      _RuleMark.block => Tooltip(
          message: ruleTip!,
          child: _outlinedIcon(Icons.block_rounded, m.badge, _failRed, bg),
        ),
      _RuleMark.direct => null,
    };

    final cell = SizedBox(
      width: m.box,
      height: m.box,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: CustomPaint(
            key: const ValueKey('serviceRing'),
            painter: _RingPainter(
              left: statusColor(context, left),
              right: live
                  ? statusColor(context, after)
                  : t.disabledColor,
              stroke: m.stroke,
              split: m.split,
              radius: m.radius,
              circle: direct,
            ),
          ),
        ),
        // Подсказки половин рамки — под значком: наведение на сам значок
        // отдаёт его подсказку, на рамку — подсказку половины.
        Positioned.fill(
          child: direct
              ? zone('${l.serviceChecksBefore}: ${word(now)}')
              : Row(children: [
                  Expanded(child: zone(beforeTip)),
                  Expanded(child: zone(afterTip)),
                ]),
        ),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(iconInset),
            child: Tooltip(message: iconTip.toString(), child: icon),
          ),
        ),
        // ⚠️ «ИДЁТ ПРОВЕРКА» ОБЯЗАНО БЫТЬ ВИДНО: иначе после нажатия ничего
        // не меняется секунд шестнадцать, и значок выглядит неработающим
        // (найдено ревью 05.09.2026).
        if (now.state == ServiceCheckState.checking)
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: EdgeInsets.all(iconInset),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bg.withValues(alpha: 0.72),
                    shape: direct ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: direct
                        ? null
                        : BorderRadius.circular(m.radius - iconInset),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: m.icon * .55,
                      height: m.icon * .55,
                      child: CircularProgressIndicator(
                          strokeWidth: m.icon * .09),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: -o,
          top: -o,
          child: direct
              ? Tooltip(
                  message: ruleTip!,
                  child: _outlinedIcon(
                      Icons.alt_route_rounded, m.badge, Colors.orange, bg),
                )
              : Tooltip(
                  message: beforeTip,
                  child: _lock(true, m.badge, ink, bg),
                ),
        ),
        if (rightBadge != null) Positioned(right: -o, top: -o, child: rightBadge),
        if (glyph != null)
          Positioned(
            right: -o - 1,
            bottom: -o - 1,
            child: Tooltip(
              message: '${l.serviceChecksNow}: ${word(now)}',
              child: Container(
                width: m.badge * .9,
                height: m.badge * .9,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor(context, now),
                  shape: BoxShape.circle,
                  // Рамка цвета фона отделяет кружок от рамки того же цвета.
                  border: Border.all(color: bg, width: 1),
                ),
                child: Icon(glyph, size: m.badge * .62, color: Colors.white),
              ),
            ),
          ),
      ]),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: m.slot,
        height: m.slot,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: cell),
        ),
      ),
    );
  }

  static Widget _lock(bool open, double size, Color color, Color bg) =>
      CustomPaint(
        key: ValueKey(open ? 'lockOpen' : 'lockClosed'),
        size: Size.square(size),
        painter: _LockPainter(open: open, color: color, bg: bg),
      );
}

/// Печатает НАСТОЯЩИЕ размеры, по одному разу на изменение.
///
/// ⚠️ Четыре захода подряд по этой вёрстке я правил вслепую и трижды сделал
/// хуже: то блок не рос, то жался сильнее прежнего. Все рассуждения строились
/// на ОЦЕНКЕ, которая по построению приблизительна. Здесь печатаются факты —
/// что реально выдал `LayoutBuilder` и какой коэффициент из этого вышел.
String? _lastSidesLog;
void _logSides(BoxConstraints c,
    ({List<GroupedRow> left, List<GroupedRow> right}) split,
    {required double k, required bool dense}) {
  final lh = ServiceChecksSides.sideHeightOf(split.left, dense: dense);
  final rh = ServiceChecksSides.sideHeightOf(split.right, dense: dense);
  final line = 'Проверки: место ${c.maxWidth.toStringAsFixed(0)}×'
      '${c.hasBoundedHeight ? c.maxHeight.toStringAsFixed(0) : "∞"}, '
      'групп ${split.left.length}/${split.right.length}, '
      'высота сторон ${lh.toStringAsFixed(0)}/${rh.toStringAsFixed(0)}, '
      'масштаб ${k.toStringAsFixed(2)}';
  if (line == _lastSidesLog) return;
  _lastSidesLog = line;
  // ⚠️ ОТЛАДОЧНЫЙ УРОВЕНЬ, А НЕ БОЕВОЙ. Найдено ревью 05.09.2026.
  //
  // Строка пишется из `build`, то есть на КАЖДОЙ перекладке блока, а в неё
  // входят ширина и высота места, округлённые до пикселя — при перетаскивании
  // угла окна они меняются каждый кадр. Дедупликация по строке от этого не
  // спасает: за пять секунд жеста в журнал уходило около трёхсот разных
  // строк — процентов шесть всего файла (потолок 512 КБ).
  //
  // То есть диагностика вёрстки вымывала из журнала настоящую историю обрыва
  // — ровно то, ради чего журнал и ведут, и что уже приходилось чинить
  // отдельной правкой в 1.11.0.
  AppLog.d(line);
}
