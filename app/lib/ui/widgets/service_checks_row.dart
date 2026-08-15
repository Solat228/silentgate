import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/probe/service_check.dart';
import '../../core/settings/app_settings.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/service_check_controller.dart';
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
  /// Сервисы у кнопки — по три в колонке слева и справа.
  ///
  /// Шесть, а не три: набор должен покрывать разные классы блокировок —
  /// видео, ИИ, мессенджер, соцсеть и «эталон доступности» (Google отвечает
  /// почти всегда, поэтому его отказ означает, что дело не в конкретном
  /// сервисе, а в канале).
  static const services = <ProbeService>[
    ProbeService.youtube,
    ProbeService.chatgpt,
    ProbeService.telegram,
    ProbeService.instagram,
    ProbeService.discord,
    ProbeService.google,
  ];

  /// Левая и правая колонки — по три сервиса.
  static List<ProbeService> get leftColumn => services.sublist(0, 3);
  static List<ProbeService> get rightColumn => services.sublist(3);
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
