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
/// [build] отдельно обрабатывает случай «места с избытком по обеим осям»: без
/// FittedBox вовсе, с зазором у кнопки, растущим вместе с окном (в разумных,
/// капнутых пределах) — см. [_gapExtraShare], [_gapExtraCap]. Случай нехватки
/// места остался БЕЗ ИЗМЕНЕНИЙ — прежний проверенный `FittedBox` вокруг всего
/// блока, тот же уровень надёжности.
///
/// ⚠️ ГРУБАЯ ОЦЕНКА МАСШТАБА (`_estimateScale`) — ДРУГОЕ ЧИСЛО, И ОНО НЕ ОБЯЗАНО
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
  /// лезем в него, а просто отводим ему опорную ширину/высоту для измерения —
  /// `FittedBox` ниже досожмёт фактический размер вместе со всем остальным.
  static const double _naturalButton = 148.0;

  /// Минимальный просвет между колонкой и кнопкой — то, что остаётся, когда
  /// добавить нечего (места впритык) или расти некуда (см. [_gapExtraCap]).
  static const double _gap = 14.0;

  /// Просвет между блоками-группами внутри одной стороны — и по горизонтали,
  /// и между рядами блоков. Одно число на оба измерения намеренно: сетка
  /// читается как сетка, только когда её просветы одинаковы.
  static const double _blockGap = 10.0;

  /// Ширина одной колонки на масштабе 1.0. Разная для `sides` (нужно место под
  /// пару «до → после») и `grid` (только иконка с кружком статуса).
  /// Сколько блоков-групп ложится в один ряд с одной стороны от кнопки.
  ///
  /// Два — решение владельца: «слева и справа по 2 столбца, в высоту 3».
  ///
  /// ⚠️ ТРИ В РЯД СНАЧАЛА СДЕЛАЛИ ХУЖЕ, И ВОТ ПОЧЕМУ ЭТО НЕ ОТМЕНА ПРАВКИ.
  /// При потолке подписи 108 блок занимал 78 px, три блока — 254 при
  /// доступных 209, и сторона сжималась до 0,82: значки становились МЕЛЬЧЕ.
  /// После ужатия подписи до 60 блок стал 60 px, три блока — 200, и они
  /// помещаются. А главное — при пяти группах два в ряд дают ОДИН ряд слева
  /// и ДВА справа (замер: высоты сторон 138 и 276), то есть правая сторона
  /// сжимается вдвое сильнее левой, и это видно на глаз. Три в ряд кладут
  /// обе стороны в один ряд — высоты равны, масштаб общий.
  ///
  /// На тесном экране остаётся два: там 209 px на сторону нет вовсе.
  ///
  /// Параметром, а не константой, оставлено намеренно: число меряется от
  /// ширины, и если раскладка изменится, менять придётся ОДНО место.
  static int blocksPerRowFor(double paneWidth) => paneWidth >= 520 ? 3 : 2;

  static double _columnWidth(bool dense) => dense ? 84.0 : 108.0;

  /// Та же ширина, доступная подписи группы: она обязана считаться ОДНИМ
  /// числом с шириной стороны, иначе подпись снова начнёт раздувать блок.
  static double columnWidthFor(bool dense) => _columnWidth(dense);

  /// Потолок ширины ПОДПИСИ группы — заметно уже колонки.
  ///
  /// ⚠️ ЭТО ГЛАВНЫЙ РЫЧАГ РАЗМЕРА ЗНАЧКОВ, и он неочевиден. Ширину блока
  /// задаёт самый широкий его элемент, а это ПОДПИСЬ: «Видео и музыка»
  /// занимает около 78 px против 43 у самой ячейки. Чем шире подпись, тем
  /// шире сторона и тем сильнее `BoxFit.contain` жмёт ВЕСЬ блок — значки в
  /// том числе.
  ///
  /// Замер на живом окне (04.09.2026): при потолке 108 сторона занимала
  /// 166 px и масштаб выходил 1,26; при 60 — 130 px и масштаб 1,6. Подпись
  /// при этом не теряется: она рисуется в том же увеличенном масштабе, то
  /// есть занимает около 96 настоящих пикселей.
  /// Ширина ячейки сервиса на масштабе 1.0: стрелка перехода, отступ, значок
  /// с обводкой. По ней же меряется подпись — блок не должен быть шире
  /// своего содержимого.
  /// ⚠️ ЧУТЬ ШИРЕ ЯЧЕЙКИ, И ЭТО ИЗМЕРЕНО, А НЕ ПРИКИНУТО. «Мессенджеры»
  /// шрифтом 8 занимают около 50 px, и в ячейку 48 не помещаются — Flutter
  /// рвёт слово по буквам («Мессендже/ры» на снимке из VM, дважды). Четыре
  /// лишних пикселя стоят двух пикселей размера значка и оставляют название
  /// целым.
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
  /// Само сжатие структурно безопасно (см. шапку класса), порог — вопрос
  /// читаемости, не целостности.
  static const double _minReadableScale = 0.62;

  /// Во сколько раз блоку позволено вырасти сверх натурального размера.
  ///
  /// ⚠️ Требование владельца (05.09.2026): «пропорционально оставшемуся
  /// месту, но до определённого размера». Без потолка на широком мониторе
  /// значки раздувались бы вместе с окном — экран превратился бы в набор
  /// гигантских кружков вокруг кнопки.
  static const double _maxGrow = 1.6;

  @override
  Widget build(BuildContext context) {
    final rows = ServiceChecks.grouped(services);
    // Проверки выключены целиком — колонкам нечего показывать, но кнопка
    // остаётся: место у неё не отбираем.
    if (rows.isEmpty) return button;


    return LayoutBuilder(builder: (context, c) {
      final perRow = blocksPerRowFor(c.maxWidth);
      final split = _splitColumns(rows, dense: dense, perRow: perRow);
      final natural = _naturalSize(split, dense: dense, perRow: perRow);
      final scale = _estimateScale(c, natural);
      if (scale < _minReadableScale) {
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

      // ⚠️ ФИКСИРОВАННОЙ ШИРИНЫ У СТОРОНЫ БОЛЬШЕ НЕТ, И ЭТО НЕ ОТМЕНА
      // ПРЕЖНЕЙ ПРАВКИ, А ЕЁ ЗАМЕНА.
      //
      // Раньше обе стороны зажимались в одинаковый `SizedBox`, чтобы кнопка
      // не съезжала с центра (её сдвигало на половину разницы сторон). Теперь
      // симметрию держат равные `Expanded` по бокам — по построению, а не по
      // совпадению чисел.
      //
      // ⚠️ А ЗАЖИМАТЬ БЫЛО НЕЛЬЗЯ: ширина считалась по `_columnWidth` (108 на
      // блок), то есть 344 px на три блока при настоящем содержимом в 152.
      // `FittedBox` вписывал в место ЭТУ КОРОБКУ вместе с пустотой внутри —
      // и вместо роста давал сжатие до 0,6. Снимок 04.09.2026: обводки
      // появились, подписи ужались, а значки не подросли ни на пиксель.
      final left = _SideColumn(
        perRow: perRow,
        rows: split.left,
        httpPort: httpPort,
        dense: dense,
        alignEnd: true,
      );
      final right = _SideColumn(
        perRow: perRow,
        rows: split.right,
        httpPort: httpPort,
        dense: dense,
        alignEnd: false,
      );
      final buttonBox = SizedBox(
        width: _naturalButton,
        height: _naturalButton,
        child: Center(child: button),
      );

      // ⚠️ ОЦЕНКОЙ РАЗМЕР БОЛЬШЕ НЕ РЕШАЕТСЯ — ТОЛЬКО ФАКТОМ.
      //
      // Жалоба владельца 04.09.2026 со снимком, где свободное место обведено
      // красным: «есть же место, почему не используешь». Причина оказалась не
      // в потолке роста, а в самой оценке: `_columnWidth` отводит блоку 108 px
      // сверху, а настоящий блок занимает около 45 (иконка, отступ, точка).
      // Формула считала, что места НЕ ХВАТАЕТ, когда его было вдвое больше
      // нужного — и блок жался посреди пустого окна.
      //
      // Подпирать оценку бесполезно: она приблизительная по построению и
      // расходится с вёрсткой при каждой её правке (в этом файле так было уже
      // трижды). Поэтому сторонам отдаётся ВСЁ свободное место, а вписывает в
      // него содержимое `FittedBox` — он меряет ребёнка по-настоящему и
      // находит наибольший масштаб, при котором тот влезает. Это и есть
      // «жать или растить, пока не влезет», без единого предположения о
      // размерах.
      //
      // ⚠️ «БЕЗ ФАНАТИЗМА» обеспечивает ВЫСОТА: `BoxFit.contain` вписывает по
      // МЕНЬШЕЙ из осей, а высота ограничена потолком, который панель выдаёт
      // блоку. На широком мониторе рост упрётся в неё и остановится, а не
      // раздует значки вместе с окном.
      //
      // ⚠️ Кнопку не растим: её размер задаёт панель, он одинаков во всех
      // раскладках, и это стережёт `connect_button_content_test`.
      _logSides(c, split, dense: dense, perRow: perRow);
      // ⚠️ БЛОК ЗАНИМАЕТ СВОЮ ВЫСОТУ, А НЕ ВЕСЬ ВЫДАННЫЙ ПОТОЛОК.
      //
      // Найдено ревью 05.09.2026 и подтверждено замером: при потолке 486 px и
      // трёх сервисах блок занимал ровно 486 при содержимом 186 — между
      // последним значком и следующей строкой висело 190 px пустоты, а низ
      // панели выдавливался за её край.
      //
      // Причина в том, что потолок доводится сюда цепочкой `Flexible` с
      // нежёсткой посадкой, и `SizedBox(height: потолок)` заполнял его
      // целиком. Потолок — это ОГРАНИЧЕНИЕ («больше нельзя»), а не задание
      // («займи столько»); разница видна только когда содержимого мало, то
      // есть в самом частом случае.
      final wanted = math.max(
        _naturalButton,
        math.max(sideHeightOf(split.left, dense: dense, perRow: perRow),
            sideHeightOf(split.right, dense: dense, perRow: perRow)),
      );
      final boxHeight = c.hasBoundedHeight && wanted > c.maxHeight
          ? c.maxHeight
          : wanted;

      // ⚠️ МАСШТАБ ОДИН НА ОБЕ СТОРОНЫ.
      //
      // Раньше каждая сторона вписывалась в свою половину своим `FittedBox`.
      // Половины равны, а блоков в них разное число (пять групп делятся как
      // 2 и 3), поэтому три блока ужимались сильнее двух: на снимке из VM
      // правая половина значков выходила заметно мельче левой, хотя стоят
      // они в одной строке.
      //
      // Теперь коэффициент считается по ХУДШЕЙ стороне и применяется к обеим:
      // сторона с меньшим числом блоков просто не занимает свою половину
      // целиком, и пустое место остаётся у дальнего от кнопки края.
      final roomPerSide = (c.maxWidth - _naturalButton - _gap * 2) / 2;
      final wL = sideWidthOf(split.left, dense: dense, perRow: perRow);
      final wR = sideWidthOf(split.right, dense: dense, perRow: perRow);
      final hL = sideHeightOf(split.left, dense: dense, perRow: perRow);
      final hR = sideHeightOf(split.right, dense: dense, perRow: perRow);
      final widest = math.max(wL, wR);
      final tallest = math.max(hL, hR);
      var k = _maxGrow;
      if (widest > 0) k = math.min(k, roomPerSide / widest);
      if (tallest > 0 && c.hasBoundedHeight) {
        k = math.min(k, c.maxHeight / tallest);
      }
      if (k <= 0 || !k.isFinite) k = 1.0;

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
  /// Высота одной стороны при сетке блоков: сумма РЯДОВ, а в ряду берётся
  /// самый высокий блок. Отдельным помощником, потому что нужна и оценке
  /// размера, и расчёту роста в `build` — две копии этой формулы разошлись бы
  /// на первой же правке.
  /// Ширина одной стороны при масштабе 1.0.
  static double sideWidthOf(List<GroupedRow> rows,
      {required bool dense, required int perRow}) {
    if (rows.isEmpty) return 0;
    final inRow = rows.length < perRow ? rows.length : perRow;
    return labelWidthFor(dense) * inRow + _blockGap * (inRow - 1);
  }

  static double sideHeightOf(List<GroupedRow> rows,
      {required bool dense, required int perRow}) {
    if (rows.isEmpty) return 0;
    double blockHeight(GroupedRow r) => dense
        ? (r.services.length / 2).ceil() * 40.0
        : 26.0 + r.services.length * 34.0;
    if (dense) {
      var h = 0.0;
      for (final r in rows) {
        h += blockHeight(r) + 6;
      }
      return h;
    }
    var h = 0.0;
    for (var i = 0; i < rows.length; i += perRow) {
      var tallest = 0.0;
      for (var k = i;
          k < math.min(i + perRow, rows.length);
          k++) {
        tallest = math.max(tallest, blockHeight(rows[k]));
      }
      h += tallest + _blockGap;
    }
    return h;
  }

  Size _naturalSize(({List<GroupedRow> left, List<GroupedRow> right}) split,
      {required bool dense, required int perRow}) {
    // ⚠️ СЧИТАЕМ ПО СЕТКЕ БЛОКОВ, А НЕ ПО СТОЛБЦУ. Прежняя формула складывала
    // высоты всех групп подряд — она отвечала прежней раскладке, где группы
    // шли одна под другой. С сеткой «два в ширину» высота стороны это сумма
    // РЯДОВ, а в ряду берётся самый высокий блок. Оставь старую формулу — и
    // оценка завысит высоту вдвое, сжатие включится там, где не нужно, и
    // блок уедет в раскладку рядами на ровном месте.
    double blockHeight(GroupedRow r) => dense
        // Сетка: иконки по две в ряд, без подписи группы.
        ? (r.services.length / 2).ceil() * 40.0
        // Блок: строка подписи группы + по строке на сервис.
        : 26.0 + r.services.length * 34.0;

    double sideHeight(List<GroupedRow> rows) {
      if (rows.isEmpty) return 0;
      if (dense) {
        var h = 0.0;
        for (final r in rows) {
          h += blockHeight(r) + 6;
        }
        return h;
      }
      var h = 0.0;
      for (var i = 0; i < rows.length; i += perRow) {
        var tallest = 0.0;
        for (var k = i;
            k < math.min(i + perRow, rows.length);
            k++) {
          tallest = math.max(tallest, blockHeight(rows[k]));
        }
        h += tallest + 10; // просвет между рядами блоков
      }
      return h;
    }

    final height = math.max(
      _naturalButton,
      math.max(sideHeight(split.left), sideHeight(split.right)),
    );
    // Ширина стороны: столько блоков в ряд, сколько их реально есть, но не
    // больше [blocksPerRow] — при двух группах сторона занимает две ширины,
    // а не отведённые под сетку четыре.
    double sideWidth(List<GroupedRow> rows) {
      if (rows.isEmpty) return 0;
      final inRow = dense
          ? 1
          : math.min(rows.length, perRow);
      return _columnWidth(dense) * inRow + 10 * (inRow - 1);
    }

    final width = sideWidth(split.left) +
        sideWidth(split.right) +
        _naturalButton +
        _gap * 2;
    return Size(width, height);
  }

  /// Раскладывает ГРУППЫ (не отдельные сервисы — группа не разрывается между
  /// колонками, иначе смысл ряда потерялся бы, см. шапку файла) по двум
  /// колонкам, примерно поровну по числу строк.
  /// Тот же делёж, доступный стражу: равновесие сторон глазами видно, а
  /// тестом — только через эту точку (сам делёж приватен, а поднимать ради
  /// него всё дерево значит проверять вёрстку вместо арифметики).
  @visibleForTesting
  static ({List<GroupedRow> left, List<GroupedRow> right}) splitForTest(
          List<GroupedRow> rows,
          {required bool dense, int perRow = 2}) =>
      const ServiceChecksSides(services: [], httpPort: 0, button: SizedBox())
          ._splitColumns(rows, dense: dense, perRow: perRow);

  ({List<GroupedRow> left, List<GroupedRow> right}) _splitColumns(
      List<GroupedRow> rows,
      {required bool dense, required int perRow}) {
    // ⚠️ ДЕЛИМ ПОРОВНУ ПО ВЫСОТЕ, А НЕ ПО ЧИСЛУ СТРОК — решение владельца
    // (04.09.2026). С сеткой это разные вещи: два блока по три сервиса и
    // шесть блоков по одному дают одинаковое число строк и совершенно разную
    // высоту стороны.
    int linesOf(GroupedRow r) =>
        dense ? (r.services.length / 2).ceil() : 1 + r.services.length;

    // Высота стороны при данном наборе блоков: сумма рядов, в ряду —
    // самый высокий.
    int heightOf(List<GroupedRow> side) {
      if (dense) return side.fold<int>(0, (a, r) => a + linesOf(r));
      var h = 0;
      for (var i = 0; i < side.length; i += perRow) {
        var tallest = 0;
        for (var k = i;
            k < math.min(i + perRow, side.length);
            k++) {
          tallest = math.max(tallest, linesOf(side[k]));
        }
        h += tallest;
      }
      return h;
    }

    // Порядок групп сохраняем: перетасовать их значило бы, что привычное
    // место сервиса меняется от набора к набору. Ищем лучшую ТОЧКУ РАЗРЕЗА.
    // ⚠️ ПРИ РАВНОЙ ВЫСОТЕ РЕШАЕТ ЧИСЛО БЛОКОВ — БЕЗ ЭТОГО СТОРОНЫ ВЫХОДЯТ
    // 1 ПРОТИВ 4. Высота стороны считается по РЯДАМ, а в ряду берётся самый
    // высокий блок: сторона из одного блока и сторона из двух дают ОДНУ И ТУ
    // ЖЕ высоту. Значит по высоте все разрезы равны, и выигрывал просто
    // первый — левая сторона получала один блок, правая четыре.
    //
    // Поймано живым снимком из VM 04.09.2026: числа сходились, тесты были
    // зелёными, а экран выглядел перекошенным.
    var bestCut = (rows.length / 2).ceil();
    var bestDiff = -1;
    var bestCountDiff = -1;
    for (var cut = 1; cut < rows.length; cut++) {
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
    if (rows.length < 2) return (left: rows, right: const <GroupedRow>[]);
    return (left: rows.sublist(0, bestCut), right: rows.sublist(bestCut));
  }
}

/// Одна колонка внутри [ServiceChecksSides]: список групп сверху вниз.
class _SideColumn extends StatelessWidget {
  const _SideColumn({
    required this.perRow,
    required this.rows,
    required this.httpPort,
    required this.dense,
    required this.alignEnd,
  });

  final List<GroupedRow> rows;
  final int httpPort;

  /// Сколько блоков в одном ряду — см. [ServiceChecksSides.blocksPerRowFor].
  final int perRow;

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

    // ⚠️ БЛОКИ СЕТКОЙ: ДВА В ШИРИНУ, ДО ТРЁХ В ВЫСОТУ.
    //
    // Требование владельца 04.09.2026, и оно решает беду, из-за которой блок
    // не влезал в минимальное окно ВООБЩЕ. Раньше группы шли одна под другой
    // единым столбцом, и высота росла с КАЖДЫМ добавленным сервисом:
    // четырнадцать штук давали 366 px при доступных 237, и никакое сжатие
    // этого не лечило — жать пришлось бы до нечитаемого.
    //
    // Теперь блок это группа (подпись и сервисы друг под другом), а блоки
    // ложатся сеткой по два в ширину. Высота перестаёт зависеть от числа
    // сервисов линейно и растёт ступенями по рядам блоков, а рост идёт
    // ВШИРЬ — туда, где место есть.
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
                    // «иконка → точки» обязан совпадать слева и справа:
                    // зеркальный порядок меняет местами «до» и «после»,
                    // стрелка начинает показывать в обратную сторону, а
                    // подпись «слева без VPN, справа через VPN» становится
                    // ложью ровно для половины сервисов.
                    alignEnd: false,
                    bypass: bypassOf(s),
                    onTap: () => ctrl.check(s, httpPort),
                  ),
                ),
            ],
          ),
        ),
    ];

    final gridRows = <List<Widget>>[];
    for (var i = 0; i < blocks.length; i += perRow) {
      gridRows.add(blocks.sublist(i, math.min(i + perRow, blocks.length)));
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
            padding: EdgeInsets.only(bottom: r == gridRows.length - 1 ? 0 : 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < gridRows[r].length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
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
/// Постоянная ширина ячейки сервиса на масштабе 1.0.
///
/// Пара «без VPN → через VPN»: два значка по 26 (+обводка и отступ = 32
/// каждый) и стрелка 8 между ними. Резерв держится
/// ВСЕГДА: без него подключение расширяло бы каждую ячейку, блоки
/// разъезжались и масштаб пересчитывался — экран дёргался на ровном месте.
const double cellWidth = 72;

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
    // ⚠️ СОСТОЯНИЕ — ОБВОДКОЙ ЗНАЧКА, А НЕ КРУЖКОМ РЯДОМ. Решение владельца
    // 04.09.2026 по разбору десяти раскладок в масштабе.
    //
    // Кружок рядом стоил дороже всего именно на ЖИВОМ канале: там к нему
    // добавлялась пара «до → после» со стрелкой, и ячейка росла с 43 до 71 px.
    // Из-за этого раскладка, крупная в покое, на подключённом VPN сжималась —
    // то есть мельчала ровно тогда, когда на неё и смотрят. Обводка живёт НА
    // значке и ширины не занимает вовсе, поэтому размер стал одинаковым в
    // обоих состояниях.
    //
    // ⚠️ Стрелка УКАЗЫВАЕТ НА ВТОРОЙ ЗНАЧОК, а не висит в пустоте: слева
    // сервис без VPN, справа — он же через VPN. Цвет стрелки нейтральный,
    // состояния несут обводки самих значков.
    final live0 = live && before.state != ServiceCheckState.idle;
    final arrow = live0
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            // ⚠️ СТРЕЛКА НЕ СЛУШАЕТ СИСТЕМНОЕ УКРУПНЕНИЕ ТЕКСТА. Найдено ревью
            // 05.09.2026: ширина ячейки фиксирована (72 px под пару значков и
            // стрелку), а стрелка нарисована ТЕКСТОМ и потому росла вместе с
            // системным масштабом. При укрупнении 1.3 второй значок вылезал за
            // отведённое место, и на телефоне с крупным шрифтом — то есть
            // ровно у того, кому он нужен, — пара разъезжалась.
            //
            // Фиксируем осознанно: это графический разделитель, а не текст для
            // чтения. Крупнее он не станет понятнее, а подписи групп и слово в
            // кнопке укрупнение по-прежнему уважают.
            child: MediaQuery.withNoTextScaling(
              child: Text('→',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                        fontWeight: FontWeight.w700,
                      )),
            ),
          )
        : null;

    final rule = bypass;
    // ⚠️ ДВА ЗНАЧКА СЕРВИСА, И СТРЕЛКА УКАЗЫВАЕТ НА ВТОРОЙ.
    //
    // Владелец 04.09.2026: «и чё это за отсталая стрелочка? стрелка указывает
    // на то, что с сервисом, то есть на 2-й значок сервиса с альтернативной
    // обводкой». Верно: до этого стрелка показывала в пустоту, а состояние
    // «до» жило только в её цвете — догадаться об этом было нельзя.
    //
    // Теперь пара читается сама: слева сервис БЕЗ VPN, справа — ЧЕРЕЗ VPN,
    // у каждого своя обводка. Первый нарочно меньше: он справочный, а
    // отвечает на вопрос «работает ли сейчас» именно второй.
    //
    // ⚠️ ОБА ЗНАЧКА ОДНОГО РАЗМЕРА И ОБА С ОБВОДКОЙ — решение владельца
    // (05.09.2026): «нужно знать, что было до включения». Первый значок
    // сперва делали меньше, чтобы выгадать ширину, но так «до» читается как
    // сноска, а не как равноправный замер, и цвет его обводки теряется.
    //
    // ⚠️ ЦЕНА ИЗМЕРЕНА: пара равных занимает 72 px против 34 у одиночного
    // значка, поэтому масштаб блока падает примерно до 0,9 — значок выходит
    // около 23 px. Это осознанный размен: два состояния важнее размера.
    // ⚠️ Место под пару держится ВСЕГДА, даже когда VPN выключен: иначе
    // подключение расширяло бы каждую ячейку, блоки разъезжались, и экран
    // дёргался на ровном месте. Пока второго значка нет, первый стоит по
    // центру ячейки.
    Widget iconBox(ServiceCheckOutcome o, double size, {bool badge = false}) {
      final busy = o.state == ServiceCheckState.checking;
      final box = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: statusColor(context, o), width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SiteFavicon(domain: service.domain, size: size, builtIn: true),
                // ⚠️ «ИДЁТ ПРОВЕРКА» ОБЯЗАНО БЫТЬ ВИДНО. Найдено ревью
                // 05.09.2026: при переходе с кружков на обводку индикатор
                // потерялся — `checking` попал в общую ветку и красился тем же
                // цветом, что и «не проверено».
                //
                // Обратной связи на нажатие не осталось ни на ПК, ни на
                // телефоне: человек тапает, ничего не меняется секунд
                // шестнадцать, тапает второй раз — а контроллер молча выходит,
                // потому что проверка уже идёт. Выглядит как неработающая
                // кнопка.
                if (busy)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(size * 0.3),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: size * 0.55,
                        height: size * 0.55,
                        child: CircularProgressIndicator(
                          strokeWidth: size * 0.09,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      if (!badge || bypass == null) return box;
      // Пометка правила — накладкой: рядом она отняла бы ширину, а ширина
      // здесь единственное, что ограничивает размер значков.
      return Stack(
        clipBehavior: Clip.none,
        children: [
          box,
          Positioned(
            left: -3,
            top: -3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                bypass!.action == AppAction.block
                    ? Icons.block
                    : Icons.lock_open_rounded,
                size: 12,
                color: bypass!.action == AppAction.block
                    ? const Color(0xFFCC7777)
                    : Colors.orange,
              ),
            ),
          ),
        ],
      );
    }

    final items = <Widget>[
      if (live0) ...[
        iconBox(before, 26),
        arrow!,
      ],
      iconBox(live ? after : before, 26, badge: true),
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
            child: SizedBox(
              // Постоянная ширина: значок с обводкой (34) плюс место под
              // стрелку (14). Пусто при выключенном VPN, занято при
              // включённом — но ячейка одна и та же, поэтому раскладка
              // при подключении не дёргается.
              width: cellWidth,
              // ⚠️ ПАРА ВСЕГДА СЛЕВА НАПРАВО, ДАЖЕ В АРАБСКОМ И ФАРСИ.
              //
              // Найдено ревью 05.09.2026. `Row` без явного направления берёт
              // его у локали, поэтому в RTL дети зеркалились: значок «до»
              // уезжал ВПРАВО, «после» — влево. При этом символ «→» не входит
              // в таблицу зеркалящихся (U+2192 не имеет пары в BidiMirroring),
              // и глиф продолжал смотреть вправо — то есть от «после» к «до».
              //
              // Подпись под блоком переведена дословно: «چپ — بدون VPN» и
              // «يسارًا — دون VPN» значат «слева — без VPN». Иранский
              // пользователь — а это ядро аудитории VPN-клиента — читал бы
              // подпись, смотрел на левый значок и видел замер ЧЕРЕЗ VPN.
              // Сервис, который VPN починил, читался бы как им сломанный.
              //
              // Проще всего было бы перевести подписи на «справа/слева» для
              // RTL, но тогда правда зависела бы от аккуратности десяти
              // переводов. Здесь порядок — часть СМЫСЛА, а не оформления,
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

  /// Цвет состояния. Вынесен из [_dot], потому что теперь им красится не
  /// только кружок, но и обводка значка со стрелкой перехода.
  static Color statusColor(BuildContext context, ServiceCheckOutcome o) =>
      switch (o.state) {
        ServiceCheckState.ok => Colors.green,
        ServiceCheckState.geoBlocked => Colors.orange,
        ServiceCheckState.fail => const Color(0xFFCC7777),
        _ => Theme.of(context).disabledColor,
      };
}

/// Печатает НАСТОЯЩИЕ размеры, по одному разу на изменение.
///
/// ⚠️ Четыре захода подряд по этой вёрстке я правил вслепую и трижды сделал
/// хуже: то блок не рос, то жался сильнее прежнего. Все рассуждения строились
/// на ОЦЕНКЕ `_naturalSize`, которая по построению приблизительна. Здесь
/// печатаются факты — что реально выдал `LayoutBuilder` и сколько занимает
/// содержимое.
String? _lastSidesLog;
void _logSides(BoxConstraints c,
    ({List<GroupedRow> left, List<GroupedRow> right}) split,
    {required bool dense, required int perRow}) {
  final lh = ServiceChecksSides.sideHeightOf(split.left,
      dense: dense, perRow: perRow);
  final rh = ServiceChecksSides.sideHeightOf(split.right,
      dense: dense, perRow: perRow);
  final line = 'Проверки: место ${c.maxWidth.toStringAsFixed(0)}×'
      '${c.hasBoundedHeight ? c.maxHeight.toStringAsFixed(0) : "∞"}, '
      'блоков в ряду $perRow, групп ${split.left.length}/${split.right.length}, '
      'высота сторон ${lh.toStringAsFixed(0)}/${rh.toStringAsFixed(0)}';
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
