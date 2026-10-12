import 'package:intl/intl.dart';

import '../../core/update/download_progress.dart';
import '../../l10n/gen/app_localizations.dart';

/// Текст хода закачки обновления — две строки:
///
///     Загрузка 12,3 из 38,1 МБ
///     осталось 25,8 МБ · ~20 с
///
/// Без байтов (размер неизвестен) — прежний процент. Время появляется, когда
/// скорость уже понятна ([DownloadRateMeter.warmUp]).
String downloadProgressText(
  AppLocalizations l,
  String locale, {
  DownloadProgress? download,
  double? fraction,
}) {
  final d = download;
  if (d == null || d.total <= 0) {
    return l.updatesStatusDownloading(((fraction ?? 0) * 100).round());
  }
  final mb = NumberFormat('0.0', locale);
  String m(int bytes) => mb.format(bytes / (1024 * 1024));
  final head = l.updatesDownloadedOf(m(d.received), m(d.total));
  final tail = <String>[l.updatesDownloadLeft(m(d.remaining))];
  final eta = d.eta;
  if (eta != null) tail.add(etaText(l, eta));
  return '$head\n${tail.join(' · ')}';
}

/// «~20 с» до минуты, дальше «~3 мин». Округляем ВВЕРХ: «~0 с» при живой
/// закачке читается как зависание на последнем куске.
String etaText(AppLocalizations l, Duration eta) {
  final s = (eta.inMilliseconds / 1000).ceil();
  if (s < 60) return l.updatesDownloadEtaSec(s < 1 ? 1 : s);
  return l.updatesDownloadEtaMin((s / 60).ceil());
}
