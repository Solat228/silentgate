import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/probe/service_check.dart';
import '../../core/settings/app_settings.dart';
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
class ServiceChecksMenuButton extends StatelessWidget {
  const ServiceChecksMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
    final settings = context.read<SettingsController>();
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              l.serviceChecksMenuTitle,
              // Цвет задан явно: пункт меню отключён (см. выше), а отключённый
              // пункт красит весь свой текст в серый — заголовок выглядел бы
              // недоступным.
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: scheme.onSurface),
            ),
          ),
          for (final svc in ServiceChecks.catalog)
            _MenuCheckRow(
              enabled: on,
              value: s.connectCheckServices.contains(svc),
              onChanged: (v) => _toggleService(svc, v),
              label: svc.label,
              leading: SiteFavicon(domain: svc.domain, size: 20, builtIn: true),
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
  });

  final bool enabled;
  final bool value;
  final void Function(bool value) onChanged;
  final String label;
  final Widget? leading;

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
              leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled
                      ? scheme.onSurface
                      : Theme.of(context).disabledColor,
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
  });

  final ProbeService service;
  final ServiceCheckOutcome before;
  final ServiceCheckOutcome after;
  final bool live;
  final bool alignEnd;
  final VoidCallback onTap;

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
    final items = <Widget>[
      SiteFavicon(domain: service.domain, size: 26, builtIn: true),
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

// TEMP_L10N_SHIM_START — временная заглушка ключей на время параллельной работы
extension TmpConnectChecksKeys on AppLocalizations {
  String get serviceChecksMenuTitle => 'Проверять при подключении';
  String get serviceChecksMenuOff => 'Не проверять при подключении';
  String get serviceChecksMenuTooltip => 'Какие сервисы проверять';
  String get serviceChecksLegendOff => 'Проверка сервисов выключена';
}
// TEMP_L10N_SHIM_END
