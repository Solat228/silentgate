import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/probe/service_check.dart';
import '../../core/settings/app_settings.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/service_check_controller.dart';
import 'info_tooltip.dart';
import 'site_favicon.dart';

/// Ряд «живой» проверки сервисов рядом с кнопкой Connect (#6). Показывается
/// только при активном VPN и идёт через уже поднятое соединение. Один раз при
/// подъёме туннеля сервисы проверяются автоматически, дальше — только по тапу
/// пользователя.
class ServiceChecksRow extends StatefulWidget {
  /// http-порт активного ядра, через который проверяем.
  final int httpPort;

  /// Сигнатура текущего соединения — её смена сбрасывает прежние результаты.
  final String epoch;

  const ServiceChecksRow({
    super.key,
    required this.httpPort,
    required this.epoch,
  });

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

  @override
  State<ServiceChecksRow> createState() => _ServiceChecksRowState();
}

class _ServiceChecksRowState extends State<ServiceChecksRow> {
  /// Контроллер запоминаем заранее: в [dispose] обращаться к `context.read`
  /// уже НЕЛЬЗЯ — дерево разбирается, и поиск провайдера кидает исключение
  /// (падало на каждое «Отключить», а сброс результатов не отрабатывал).
  ServiceCheckController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl = context.read<ServiceCheckController>();
  }

  @override
  void initState() {
    super.initState();
    // Привязываем результаты к текущему соединению после кадра (без setState в build).
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindAndAutoCheck());
  }

  @override
  void didUpdateWidget(ServiceChecksRow old) {
    super.didUpdateWidget(old);
    if (old.epoch != widget.epoch) {
      // Смена сервера при живом подключении приходит во время build родителя
      // (_ConnectPane слушает AppState). bind() зовёт notifyListeners корневого
      // контроллера — синхронный вызов здесь = markNeedsBuild во время build.
      // Откладываем на пост-кадр (как в initState).
      WidgetsBinding.instance.addPostFrameCallback((_) => _bindAndAutoCheck());
    }
  }

  /// Ряд появляется только на живом соединении, поэтому его привязка — и есть
  /// момент «туннель поднялся»: здесь же запускаем единственный автопрогон.
  /// Повторные вызовы (перестроение виджета) контроллер отсекает сам.
  void _bindAndAutoCheck() {
    if (!mounted) return;
    final ctrl = _ctrl ?? context.read<ServiceCheckController>();
    ctrl.bind(widget.epoch);
    // ⚠️ Автопрогон — ТОЛЬКО по живому соединению. Без него проба ушла бы
    // напрямую и показала доступность канала пользователя, выдав её за
    // результат VPN. Замер «до» снимается отдельной кнопкой.
    if (widget.httpPort > 0) {
      // Прогон по живому туннелю запускает ЭКРАН (home_screen), а не ряд:
      // колонок две, и каждая знает лишь свою половину сервисов.
      unawaited(ctrl.autoCheckAll(widget.httpPort, ServiceChecksRow.services));
    }
  }

  @override
  void dispose() {
    // Отключились / ушли с экрана — результаты старого соединения больше не валидны
    // (иначе переподключение к ТОМУ ЖЕ серверу или второй сеанс «Авто» показал бы
    // прежние чипы: epoch совпал бы). Контроллер корневой — живёт всё время; reset
    // откладываем на пост-кадр, чтобы не дёргать notifyListeners во время teardown.
    final ctrl = _ctrl;
    if (ctrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.reset());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ctrl = context.watch<ServiceCheckController>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.serviceChecksTitle,
                style: Theme.of(context).textTheme.labelMedium),
            InfoTooltip(l.serviceChecksInfo),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final s in ServiceChecksRow.services)
              _ServiceChip(
                service: s,
                outcome: ctrl.resultFor(s),
                onTap: () => ctrl.check(s, widget.httpPort),
              ),
          ],
        ),
      ],
    );
  }
}

class _ServiceChip extends StatelessWidget {
  final ProbeService service;
  final ServiceCheckOutcome outcome;
  final VoidCallback onTap;
  const _ServiceChip({
    required this.service,
    required this.outcome,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final checking = outcome.state == ServiceCheckState.checking;
    final (color, statusIcon, statusText) = _visuals(context, l);
    final ms = outcome.latencyMs;
    final tip = ms != null && outcome.isTerminal
        ? '$statusText · ${l.serviceLatencyMs(ms)}'
        : statusText;

    return Tooltip(
      message: tip,
      child: ActionChip(
        avatar: SiteFavicon(domain: service.domain, size: 18, builtIn: true),
        // Имя + значок статуса справа (галочка/крест/замок/спиннер).
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(service.label),
          const SizedBox(width: 6),
          statusIcon,
        ]),
        onPressed: checking ? null : onTap,
        side: color == null ? null : BorderSide(color: color),
        backgroundColor: color?.withValues(alpha: 0.10),
      ),
    );
  }

  /// (цвет рамки/фона, значок статуса, текст статуса) по состоянию.
  (Color?, Widget, String) _visuals(BuildContext context, AppLocalizations l) {
    switch (outcome.state) {
      case ServiceCheckState.idle:
        return (
          null,
          const Icon(Icons.radio_button_unchecked, size: 16, color: Colors.grey),
          l.serviceStatusTap,
        );
      case ServiceCheckState.checking:
        return (
          null,
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          l.serviceStatusChecking,
        );
      case ServiceCheckState.ok:
        return (
          Colors.green,
          const Icon(Icons.check_circle, size: 16, color: Colors.green),
          l.serviceStatusOk,
        );
      case ServiceCheckState.geoBlocked:
        return (
          Colors.orange,
          const Icon(Icons.public_off, size: 16, color: Colors.orange),
          l.serviceStatusGeo,
        );
      case ServiceCheckState.fail:
        return (
          Colors.red,
          const Icon(Icons.cancel, size: 16, color: Colors.red),
          l.serviceStatusFail,
        );
    }
  }
}

/// Колонка проверок сбоку от кнопки Connect.
///
/// Показывается ВСЕГДА — и до подключения, и после: смысл в сравнении. У
/// каждого сервиса два состояния рядом: слева замер «до» (напрямую, мимо VPN),
/// справа — через туннель. Так видно, что именно изменил VPN, а не просто
/// «сейчас зелёное».
///
/// ⚠️ Автопрогон запускается ТОЛЬКО при живом соединении ([httpPort] > 0).
/// До подключения проба ушла бы напрямую и показала доступность канала
/// пользователя, выдав её за результат VPN.
class ServiceChecksColumn extends StatelessWidget {
  const ServiceChecksColumn({
    super.key,
    required this.services,
    required this.httpPort,
    required this.epoch,
    required this.alignEnd,
  });

  final List<ProbeService> services;
  final int httpPort;
  final String epoch;

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
