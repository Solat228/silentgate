import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/enum_labels.dart';
import '../../core/models/vpn_server.dart';
import '../../core/probe/auto_config_engine.dart';
import '../../core/settings/app_settings.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/auto_config_controller.dart';
import 'measured_at.dart';
import 'site_favicon.dart';

/// Что автонастройка узнала про ЭТОТ сервер — блок на экране «Информация о
/// сервере».
///
/// ⚠️ ЗАЧЕМ. Прогон автонастройки стоит времени и трафика подписки, а его итог
/// был виден только на экране автонастройки — общим списком, где про
/// конкретный сервер сказано «сервисов 3 из 4». Человек, открывший карточку
/// сервера, ответа на свой вопрос («что через него работает?») не получал
/// вовсе, хотя ответ уже был измерен и лежит на диске
/// (`ResultsStore.autoConfig`, переживает перезапуск).
///
/// ⚠️ ГЛАВНОЕ ЗДЕСЬ — ГЕОБЛОК, И ОН РИСУЕТСЯ ТРЕТЬИМ ЦВЕТОМ, А НЕ ЗЕЛЁНЫМ И НЕ
/// КРАСНЫМ. Сервис, помеченный `CandidateResult.geoBlocked`, ОТКРЫВАЕТСЯ через
/// сервер (канал жив, TLS цел), но отвечает «в вашей стране недоступно».
/// Зелёный тут был бы враньём ровно для того, кто искал именно ChatGPT;
/// красный — враньём про сервер, который полностью исправен и для остального
/// годится. Оба варианта одинаково уводят от единственного верного вывода:
/// нужен выход в другой стране.
///
/// ⚠️ Экран НИЧЕГО НЕ МЕРЯЕТ: показывается только сохранённое. Замер отсюда
/// означал бы второй прогон харнесса за спиной у пользователя.
class ServerAutoConfigCard extends StatelessWidget {
  const ServerAutoConfigCard({super.key, required this.server});

  final VpnServer server;

  /// Результат последнего прогона по [s] или null.
  ///
  /// ⚠️ Ищем ПО КЛЮЧУ, а не по имени: у владельца четыре подписки, и названия
  /// серверов в них повторяются — поиск по имени показал бы в карточке чужой
  /// замер. Первое совпадение и есть самое свежее: `AutoConfigController.start`
  /// кладёт итог прогона в НАЧАЛО списка, выбросив прежние записи по тем же
  /// ключам.
  ///
  /// Чистая функция ради теста: у виджета не спросишь, какую запись он выбрал.
  static AutoConfigResult? resultFor(
      List<AutoConfigResult> found, VpnServer s) {
    for (final r in found) {
      if (r.server.key == s.key) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = resultFor(context.watch<AutoConfigController>().found, server);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Оформление заголовка — как у соседних разделов экрана.
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            l.autoTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (result == null)
          // Пустой блок хуже отсутствующего: «ничего не показано» человек
          // читает как «сервер ничего не прошёл». Поэтому говорим прямо, что
          // прогона не было.
          Text(
            l.srvInfoAutoNever,
            key: const Key('srvInfoAutoNone'),
            style: theme.textTheme.bodySmall,
          )
        else ...[
          Text(l.srvInfoAutoHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          _meta(context, result),
          const SizedBox(height: 8),
          _services(context, result),
          if (result.detail.geoBlocked.isNotEmpty) ...[
            const SizedBox(height: 8),
            _geoNote(context, result),
          ],
          if (result.mbps != null) ...[
            const SizedBox(height: 8),
            _speed(context, result),
          ],
        ],
      ],
    );
  }

  /// Когда проверяли и какая вариация обхода победила.
  Widget _meta(BuildContext context, AutoConfigResult r) {
    final l = AppLocalizations.of(context);
    final at = r.measuredAt;
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        // Формат момента — общий на всё приложение (`measured_at.dart`): своя
        // копия разошлась бы с подсказками пинга и скорости на первой же
        // правке порога.
        if (at != null)
          Text(measuredAtLine(context, at),
              style: Theme.of(context).textTheme.bodySmall),
        Text(
          l.autoVariant(outboundVariantLabel(l, r.variant)),
          key: const Key('srvInfoAutoVariant'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Сервисы прогона: по одной плашке на мишень, порядок — как в перечислении
  /// (иначе он «дышал» бы от прогона к прогону, а глаз ищет знакомое место).
  Widget _services(BuildContext context, AutoConfigResult r) {
    final services = [
      for (final s in ProbeService.values)
        if (r.detail.passed.containsKey(s)) s,
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final s in services) _serviceChip(context, r, s)],
    );
  }

  Widget _serviceChip(
      BuildContext context, AutoConfigResult r, ProbeService service) {
    final l = AppLocalizations.of(context);
    final ok = r.detail.passed[service] == true;
    final geo = r.detail.geoBlocked.contains(service);

    // Три состояния, а не два. Цвета те же, что у сервис-чипов на главном
    // экране (`service_checks_row.dart`), — расхождение читалось бы как разные
    // величины.
    final Color color = geo
        ? Colors.orange
        : ok
            ? Colors.green
            : const Color(0xFFCC7777);
    final IconData icon = geo
        ? Icons.public_off
        : ok
            ? Icons.check_circle
            : Icons.cancel;
    final String word = geo
        ? l.serviceStatusGeo
        : ok
            ? l.serviceStatusOk
            : l.serviceStatusFail;

    return Tooltip(
      message: '${service.label}\n$word',
      child: Container(
        key: Key('srvInfoAcSvc-${service.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SiteFavicon(domain: service.domain, size: 16, builtIn: true),
            const SizedBox(width: 6),
            // Название сервиса — бренд, направление всегда слева направо
            // (в ar/fa зеркалить «ChatGPT» нечего).
            Text(service.label,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: 4),
            // Ключ на самом значке состояния: внутри плашки есть ещё и
            // бренд-иконка (у сервиса без фавикона она тоже `Icon`), и без
            // ключа состояние из теста не отличить от украшения.
            Icon(icon,
                key: Key('srvInfoAcState-${service.name}'),
                size: 14,
                color: color),
          ],
        ),
      ),
    );
  }

  /// Пояснение к геоблоку: в чём именно проблема этого сервера.
  ///
  /// Без него оранжевая плашка — просто «какой-то третий цвет»: человек видит,
  /// что что-то не так, но не понимает, менять сервер или сервис.
  Widget _geoNote(BuildContext context, AutoConfigResult r) {
    final l = AppLocalizations.of(context);
    final names = [
      for (final s in ProbeService.values)
        if (r.detail.geoBlocked.contains(s)) s.label,
    ].join(', ');
    return Container(
      key: const Key('srvInfoAutoGeo'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.public_off, size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l.srvInfoAutoGeoNote(names),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  /// Скорость, замеренная В ТОМ ЖЕ прогоне.
  ///
  /// Доля своего канала обязательна рядом с мегабитами: «60 Мбит/с» — отлично
  /// на канале 60 и скверно на канале 300.
  Widget _speed(BuildContext context, AutoConfigResult r) {
    final l = AppLocalizations.of(context);
    final mbps = r.mbps!;
    final share = r.sharePercent;
    final value = l.autoSpeedValue(mbps.toStringAsFixed(mbps >= 100 ? 0 : 1));
    return Row(children: [
      const Icon(Icons.speed, size: 16),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          share == null ? value : '$value · ${l.autoSpeedShare(share)}',
          key: const Key('srvInfoAutoSpeed'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ]);
  }
}
