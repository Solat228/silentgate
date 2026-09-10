import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/app_log.dart';
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

  /// Базовый кегль подписи группы и его нижняя граница.
  static const double labelFontBase = 9;
  static const double labelFontMin = 6;

  /// Кегль, при котором САМАЯ ДЛИННАЯ подпись укладывается в ширину блока
  /// без разрыва слова — ОДИН на все группы экрана.
  ///
  /// ⚠️ ЗАЧЕМ СЧИТАТЬ, А НЕ ЗАДАТЬ ЧИСЛОМ. Я подбирал кегль на глаз дважды
  /// (9, потом 8) и оба раза получал на снимке из VM «Мессендже/ры»: слово
  /// не помещалось и рвалось по буквам. Ширина строки зависит от шрифта,
  /// языка и системных настроек — угадать её нельзя, а измерить можно.
  ///
  /// ⚠️ И кегль ОБЩИЙ намеренно. Сжимать каждую подпись отдельно
  /// (`FittedBox` на каждой) уже пробовали: «Мессенджеры» выходили мелкими,
  /// «ИИ» крупными, столбики значков вставали на разной высоте — жалоба
  /// владельца «а хули они у тебя вразброс».
  static double labelFontFor(List<GroupedRow> rows, AppLocalizations l,
      {required bool dense}) {
    final width = labelWidthFor(dense);
    var worst = 0.0;
    for (final r in rows) {
      // Меряем самое длинное СЛОВО, а не всю подпись: несколько слов
      // переносятся по пробелам («Видео и» / «музыка»), и уменьшать кегль
      // ради них не нужно.
      for (final word in r.group.label(l).split(' ')) {
        final tp = TextPainter(
          text: TextSpan(
            text: word,
            style: const TextStyle(fontSize: labelFontBase, height: 1.15),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        if (tp.width > worst) worst = tp.width;
      }
    }
    if (worst <= 0 || worst <= width) return labelFontBase;
    final fitted = labelFontBase * width / worst;
    return fitted < labelFontMin ? labelFontMin : fitted;
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

      final left = _SideColumn(
        rows: split.left,
        httpPort: httpPort,
        dense: dense,
        alignEnd: true,
        showGlyph: showGlyph,
      );
      final right = _SideColumn(
        rows: split.right,
        httpPort: httpPort,
        dense: dense,
        alignEnd: false,
        showGlyph: showGlyph,
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
            scaled(left, wL, hL, Alignment.centerRight),
            const SizedBox(width: _gap),
            buttonBox,
            const SizedBox(width: _gap),
            scaled(right, wR, hR, Alignment.centerLeft),
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
  static double sideWidthOf(List<GroupedRow> rows, {required bool dense}) {
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
    return labelWidthFor(dense) * inRow + _blockGap * (inRow - 1);
  }

  /// Размеры одной ячейки в режиме «сетка» — списаны с того, что реально
  /// рисует `_SideColumn` (зона 32 под кольцо 28, просвет `Wrap` 6).
  static const double _denseIcon = 32;
  static const double _denseGap = 6;

  /// Высота ОДНОГО блока-группы при масштабе 1.0 — то, что реально рисует
  /// `_SideColumn`: подпись 22 + 2 + линия 1, зазор 4, на сервис — бокс
  /// кольца плюс 8 px отступов (`_ServicePair`: 2 снаружи, 2 внутри, с двух
  /// сторон).
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
          r.services.length * (_StatusRing.boxSizeFor(_pairIconSize) + 8);

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
  });

  final List<GroupedRow> rows;
  final int httpPort;
  final bool dense;

  /// Рисовать ли глиф состояния в углу кольца — см.
  /// [ServiceChecksSides.glyphMinScale].
  final bool showGlyph;

  /// Левая сторона прижимает неполный ряд к кнопке (к правому краю), правая
  /// — наоборот. Порядок «до → после» внутри пары при этом ОДИНАКОВЫЙ с обеих
  /// сторон — см. предысторию в [_ServicePair].
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final ctrl = context.watch<ServiceCheckController>();
    final labelFont =
        ServiceChecksSides.labelFontFor(rows, l, dense: dense);
    final live = httpPort > 0;
    // Настройки — необязательно, см. `ServiceChecksRows`.
    final split = context.watch<SettingsController?>()?.settings.splitTunnel;

    SiteRule? bypassOf(ProbeService s) =>
        split == null ? null : ServiceChecks.bypassRuleFor(split, s);

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
                    _ServicePair(
                      key: ValueKey('svc:${s.name}'),
                      service: s,
                      before: ctrl.baselineFor(s),
                      after: ctrl.resultFor(s),
                      live: live,
                      alignEnd: false,
                      dense: true,
                      showGlyph: showGlyph,
                      groupLabel: rows[i].group.label(l),
                      bypass: bypassOf(s),
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
                maxWidth: ServiceChecksSides.labelWidthFor(dense),
                fontSize: labelFont,
              ),
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
                    // ⚠️ ВСЕГДА false, В ОБЕИХ СТОРОНАХ. Порядок
                    // «до → после» обязан совпадать слева и справа:
                    // зеркальный порядок меняет местами «до» и «после», и
                    // стрелка начинает показывать в обратную сторону.
                    alignEnd: false,
                    showGlyph: showGlyph,
                    bypass: bypassOf(s),
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

  static const double labelHeight = 22;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                  maxWidth: label.contains(' ') ? maxWidth : double.infinity,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: label.contains(' ') ? 2 : 1,
                  softWrap: label.contains(' '),
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

/// Размер значка сервиса в паре «до → после» (масштаб 1.0). Бокс кольца
/// вокруг него — [_StatusRing.boxSizeFor] = 34.
const double _pairIconSize = 26;

/// Место под стрелку перехода между значками пары.
///
/// ⚠️ ФИКСИРОВАННОЕ, А НЕ ПО ТЕКСТУ. Стрелка нарисована символом «→», и
/// ширина символа зависит от шрифта; ячейка же — константа. Растянись стрелка
/// шире отведённого, второй значок вылез бы за ячейку ровно на живом канале,
/// где на пару и смотрят. Внутри — `FittedBox`, который символ ужмёт, но не
/// даст ему занять больше.
const double _arrowWidth = 10;

/// Постоянная ширина ячейки сервиса на масштабе 1.0: два бокса кольца по 34
/// и стрелка [_arrowWidth] между ними — 78.
///
/// Резерв держится ВСЕГДА, даже когда VPN выключен: без него подключение
/// расширяло бы каждую ячейку, блоки разъезжались и масштаб пересчитывался —
/// экран дёргался на ровном месте. Пока второго значка нет, первый стоит по
/// центру ячейки.
const double cellWidth = 2 * (_pairIconSize + 2 * (_StatusRing.ringWidth +
        _StatusRing.gapWidth)) +
    _arrowWidth;

/// ЗНАЧОК СЕРВИСА В КОЛЬЦЕ СОСТОЯНИЯ — единственный источник для обоих видов:
/// пары «до → после» (`sides`, ряды) и плотной сетки (`grid`).
///
/// ⚠️ ДВОЙНОЙ КОНТУР, И ВОТ ПОЧЕМУ. Жалоба владельца (08.09.2026): «обводка
/// сливается с брендом» у зелёного Spotify и красного YouTube. Механика
/// найдена разведкой: прослойки между значком и кольцом не было ВООБЩЕ.
/// `DecoratedBox` не отступает под рамку (в отличие от `Container`), и кольцо
/// 2 px рисовалось ПОВЕРХ крайнего пикселя значка — зелёное на зелёном.
/// Теперь между ними прослойка [gapWidth] цвета ФОНА окна
/// (`scaffoldBackgroundColor`, а не `surface`: контраст нужен с тем, что
/// нарисовано вокруг значка, а вокруг него — фон). Кольцо видно на любом
/// бренде, потому что касается не бренда, а фона.
///
/// ⚠️ ДО 09.09.2026 ЛОГИКА ЦВЕТА ЖИЛА В ДВУХ КОПИЯХ (`iconBox` в паре и
/// `_buildDense` в сетке), и они уже разошлись на индикаторе «идёт проверка».
/// Здесь одна; страж на единый источник — `service_status_ring_test`
/// проверяет прослойку и глиф в ОБЕИХ раскладках.
///
/// Раскладка (снаружи внутрь): кольцо [ringWidth] цвета состояния →
/// прослойка [gapWidth] цвета фона → значок [iconSize]. Бокс =
/// `iconSize + 2·(ringWidth + gapWidth)`. Прямоугольник прослойки равен
/// прямоугольнику кольца, сжатому ровно на [ringWidth], — это и проверяется
/// геометрией.
class _StatusRing extends StatelessWidget {
  const _StatusRing({
    required this.domain,
    required this.outcome,
    required this.iconSize,
    required this.circle,
    required this.showGlyph,
    this.badge,
  });

  final String domain;
  final ServiceCheckOutcome outcome;
  final double iconSize;

  /// `true` — круг (плотная сетка), `false` — скруглённый квадрат (пара).
  final bool circle;

  /// Рисовать ли глиф состояния в правом нижнем углу — см.
  /// [ServiceChecksSides.glyphMinScale].
  final bool showGlyph;

  /// Правило обхода — бейдж слева сверху. `null` — бейджа нет.
  final SiteRule? badge;

  static const double ringWidth = 2;
  static const double gapWidth = 2;

  /// Кружок глифа состояния и знак внутри него.
  static const double glyphSize = 12;
  static const double glyphIconSize = 8;

  /// Насколько глиф и бейдж выступают за бокс. Не больше отступа ячейки
  /// (2 + 2 = 4), иначе соседние ячейки наезжали бы друг на друга.
  static const double _overhang = 3;

  static double boxSizeFor(double iconSize) =>
      iconSize + 2 * (ringWidth + gapWidth);

  /// Цвет состояния — им красится кольцо и глиф.
  static Color statusColor(BuildContext context, ServiceCheckOutcome o) =>
      switch (o.state) {
        ServiceCheckState.ok => Colors.green,
        ServiceCheckState.geoBlocked => Colors.orange,
        ServiceCheckState.fail => const Color(0xFFCC7777),
        _ => Theme.of(context).disabledColor,
      };

  /// Знак в углу: ✓ / ! / ✕. У «идёт проверка» и «не проверено» знака нет —
  /// там нечего утверждать.
  ///
  /// ⚠️ НЕ `Icons.block` для отказа: он занят бейджем правила «Блок», и
  /// `service_chips_test` требует его отсутствия там, где правила нет.
  static IconData? glyphFor(ServiceCheckOutcome o) => switch (o.state) {
        ServiceCheckState.ok => Icons.check,
        ServiceCheckState.geoBlocked => Icons.priority_high,
        ServiceCheckState.fail => Icons.close,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusColor(context, outcome);
    final gapColor = theme.scaffoldBackgroundColor;
    final box = boxSizeFor(iconSize);
    final busy = outcome.state == ServiceCheckState.checking;
    // Радиус кольца ~0.3 бокса (у 34 — 10); у прослойки — на толщину кольца
    // меньше, чтобы скругления шли параллельно.
    final outerRadius = circle ? null : BorderRadius.circular(box * 0.3);
    final innerRadius =
        circle ? null : BorderRadius.circular(box * 0.3 - ringWidth);
    final iconRadius = circle
        ? null
        : BorderRadius.circular(box * 0.3 - ringWidth - gapWidth);

    final ring = DecoratedBox(
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: outerRadius,
        border: Border.all(color: color, width: ringWidth),
      ),
      // ⚠️ Отступ под кольцо — ЯВНЫЙ `Padding`: `DecoratedBox` сам под
      // рамку не отступает, и без него прослойка легла бы под кольцо.
      child: Padding(
        padding: const EdgeInsets.all(ringWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: innerRadius,
            color: gapColor,
          ),
          child: Padding(
            padding: const EdgeInsets.all(gapWidth),
            child: SizedBox(
              width: iconSize,
              height: iconSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SiteFavicon(domain: domain, size: iconSize, builtIn: true),
                  // ⚠️ «ИДЁТ ПРОВЕРКА» ОБЯЗАНО БЫТЬ ВИДНО. Найдено ревью
                  // 05.09.2026: при переходе с кружков на обводку индикатор
                  // потерялся — `checking` красился тем же цветом, что и
                  // «не проверено». Обратной связи на нажатие не оставалось:
                  // человек тапал, ничего не менялось секунд шестнадцать, и
                  // кнопка выглядела неработающей.
                  if (busy)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: gapColor.withValues(alpha: 0.72),
                        shape: circle ? BoxShape.circle : BoxShape.rectangle,
                        borderRadius: iconRadius,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: iconSize * 0.55,
                          height: iconSize * 0.55,
                          child: CircularProgressIndicator(
                            strokeWidth: iconSize * 0.09,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final glyph = showGlyph ? glyphFor(outcome) : null;
    final rule = badge;
    if (glyph == null && rule == null) return ring;

    // Накладки — поверх, а не рядом: рядом они отняли бы ширину, а ширина
    // здесь единственное, что ограничивает размер значков. Бейдж обхода —
    // слева сверху, глиф состояния — справа снизу; углы разные, столкнуться
    // они не могут.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ring,
        if (rule != null)
          Positioned(
            left: -_overhang,
            top: -_overhang,
            child: DecoratedBox(
              decoration: BoxDecoration(color: gapColor, shape: BoxShape.circle),
              child: Icon(
                rule.action == AppAction.block
                    ? Icons.block
                    : Icons.lock_open_rounded,
                size: glyphSize,
                color: rule.action == AppAction.block
                    ? const Color(0xFFCC7777)
                    : Colors.orange,
              ),
            ),
          ),
        if (glyph != null)
          Positioned(
            right: -_overhang,
            bottom: -_overhang,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                // Рамка цвета прослойки отделяет кружок от кольца того же
                // цвета — иначе он сливался бы с ним в кляксу.
                border: Border.all(color: gapColor, width: 1),
              ),
              child: SizedBox(
                width: glyphSize,
                height: glyphSize,
                child: Icon(glyph, size: glyphIconSize, color: Colors.white),
              ),
            ),
          ),
      ],
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
    this.showGlyph = true,
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

  /// `true` — плотная сетка (`ServiceChecksLayout.grid`): одно кольцо поверх
  /// иконки вместо пары «до → после», подпись группы уходит целиком в
  /// `Tooltip`.
  final bool dense;

  /// Глиф состояния в углу кольца — см. [ServiceChecksSides.glyphMinScale].
  /// В рядах ([ServiceChecksRows]) масштаб всегда 1.0, и он рисуется всегда.
  final bool showGlyph;

  /// Название группы для подсказки — заполняется только в [dense]. В обычном
  /// виде группу уже называет подпись над сервисом.
  final String? groupLabel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (dense) return _buildDense(context, l);

    // ⚠️ СОСТОЯНИЕ — КОЛЬЦОМ ЗНАЧКА, А НЕ КРУЖКОМ РЯДОМ. Решение владельца
    // 04.09.2026 по разбору десяти раскладок в масштабе: кружок рядом стоил
    // дороже всего именно на ЖИВОМ канале — к нему добавлялась пара «до →
    // после», и ячейка росла с 43 до 71 px, то есть раскладка мельчала ровно
    // тогда, когда на неё и смотрят. Кольцо живёт НА значке.
    //
    // ⚠️ ДВА ЗНАЧКА ОДНОГО РАЗМЕРА, И СТРЕЛКА УКАЗЫВАЕТ НА ВТОРОЙ. Слева
    // сервис БЕЗ VPN, справа — ЧЕРЕЗ VPN, у каждого своё кольцо. Первый
    // сперва делали меньше, чтобы выгадать ширину, но так «до» читается как
    // сноска, а не как равноправный замер (решение владельца 05.09.2026:
    // «нужно знать, что было до включения»).
    final live0 = live && before.state != ServiceCheckState.idle;
    final arrow = live0
        ? SizedBox(
            width: _arrowWidth,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // ⚠️ СТРЕЛКА НЕ СЛУШАЕТ СИСТЕМНОЕ УКРУПНЕНИЕ ТЕКСТА. Найдено
                // ревью 05.09.2026: ячейка фиксирована, а стрелка нарисована
                // ТЕКСТОМ и росла вместе с системным масштабом — при 1.3
                // второй значок вылезал за отведённое место. Это графический
                // разделитель, а не текст для чтения.
                child: MediaQuery.withNoTextScaling(
                  child: Text('→',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                            fontWeight: FontWeight.w700,
                          )),
                ),
              ),
            ),
          )
        : null;

    final rule = bypass;
    Widget iconBox(ServiceCheckOutcome o, {bool badge = false}) => _StatusRing(
          domain: service.domain,
          outcome: o,
          iconSize: _pairIconSize,
          circle: false,
          showGlyph: showGlyph,
          badge: badge ? rule : null,
        );

    final items = <Widget>[
      if (live0) ...[
        iconBox(before),
        arrow!,
      ],
      iconBox(live ? after : before, badge: true),
    ];
    return Tooltip(
      message: _tip(l, rule),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          // ⚠️ Строка ужимается, а не обрезается: на узком телефоне правая
          // колонка не влезала и уезжала за край — кружок «через VPN»
          // оказывался за экраном, то есть пропадала ровно та половина
          // сравнения, ради которой всё и сделано.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignEnd
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: SizedBox(
              width: cellWidth,
              // ⚠️ ПАРА ВСЕГДА СЛЕВА НАПРАВО, ДАЖЕ В АРАБСКОМ И ФАРСИ.
              //
              // Найдено ревью 05.09.2026. `Row` без явного направления берёт
              // его у локали, поэтому в RTL дети зеркалились: значок «до»
              // уезжал ВПРАВО, «после» — влево. При этом символ «→» не входит
              // в таблицу зеркалящихся (U+2192 не имеет пары в BidiMirroring),
              // и глиф продолжал смотреть вправо — то есть от «после» к «до».
              // Подсказка «i» объясняет пару словами «слева/справа» на десяти
              // языках; здесь порядок — часть СМЫСЛА, а не оформления,
              // поэтому он закреплён кодом.
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  // Значок по центру, пока стрелки нет; со стрелкой — от
                  // начала, чтобы она встала в отведённое ей место.
                  mainAxisAlignment: arrow == null
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  // ⚠️ ПОРЯДОК ОДИНАКОВЫЙ В ОБЕИХ СТОРОНАХ, ЗЕРКАЛЕНИЯ НЕТ.
                  // Левая сторона раньше разворачивала строку, чтобы кружки
                  // смотрели на кнопку; выходило, что бренд-иконки у левой
                  // половины сервисов стоят справа, у правой — слева, и глазу
                  // не за что зацепиться. Требование владельца 18.08.2026 —
                  // «помести картинки сервисов у левой панели налево».
                  children: items,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Текст подсказки — общий для обычного вида и [dense]: набор фактов один и
  /// тот же, различается только то, КАК они нарисованы на экране.
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

  /// Плотный вид для `ServiceChecksLayout.grid`: одно кольцо поверх иконки
  /// вместо пары «до → после» — при 14 сервисах в узкой сетке места на целую
  /// пару нет, а какое-то состояние показать надо. Показываем «после» при
  /// живом VPN, иначе «до» — ровно то состояние, что интереснее человеку
  /// прямо сейчас.
  ///
  /// Кольцо — тот же [_StatusRing], что и в паре: значок 20, бокс 28, в зоне
  /// 32 (`ServiceChecksSides._denseIcon`), кругом.
  Widget _buildDense(BuildContext context, AppLocalizations l) {
    final rule = bypass;
    final outcome = live ? after : before;
    return Tooltip(
      message: _tip(l, rule),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: ServiceChecksSides._denseIcon,
          height: ServiceChecksSides._denseIcon,
          child: Center(
            child: _StatusRing(
              domain: service.domain,
              outcome: outcome,
              iconSize: 20,
              circle: true,
              showGlyph: showGlyph,
              badge: rule,
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
