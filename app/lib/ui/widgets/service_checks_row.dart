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

  /// Сервисы у кнопки: компактный дефолтный набор (YouTube/ChatGPT/Telegram).
  static const services = <ProbeService>[
    ProbeService.youtube,
    ProbeService.chatgpt,
    ProbeService.telegram,
  ];

  @override
  State<ServiceChecksRow> createState() => _ServiceChecksRowState();
}

class _ServiceChecksRowState extends State<ServiceChecksRow> {
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
    final ctrl = context.read<ServiceCheckController>();
    ctrl.bind(widget.epoch);
    unawaited(ctrl.autoCheckAll(widget.httpPort, ServiceChecksRow.services));
  }

  @override
  void dispose() {
    // Отключились / ушли с экрана — результаты старого соединения больше не валидны
    // (иначе переподключение к ТОМУ ЖЕ серверу или второй сеанс «Авто» показал бы
    // прежние чипы: epoch совпал бы). Контроллер корневой — живёт всё время; reset
    // откладываем на пост-кадр, чтобы не дёргать notifyListeners во время teardown.
    final ctrl = context.read<ServiceCheckController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.reset());
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
        avatar: SiteFavicon(domain: service.domain, size: 18),
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
