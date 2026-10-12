import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:silentgate/core/update/download_progress.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/download_progress_text.dart';

/// Ход закачки обновления: «12,3 из 38,1 МБ, осталось 25,8 МБ, ~20 с».
///
/// Просьба владельца 12.10.2026: на телефоне один процент на медленной сети
/// стоял минутами, и было непонятно, идёт закачка или зависла.
void main() {
  setUpAll(() => initializeDateFormatting());
  const mb = 1024 * 1024;
  final ru = lookupAppLocalizations(const Locale('ru'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('DownloadRateMeter', () {
    test('первую секунду время не называется — скорость ещё не ясна', () {
      var now = DateTime(2026, 10, 12, 12);
      final m = DownloadRateMeter(clock: () => now);
      expect(m.update(0, 40 * mb).eta, isNull);
      now = now.add(const Duration(milliseconds: 500));
      final p = m.update(10 * mb, 40 * mb);
      expect(p.eta, isNull, reason: 'первые куски приходят из буфера');
      expect(p.remaining, 30 * mb);
    });

    test('оценка — по средней скорости от начала', () {
      var now = DateTime(2026, 10, 12, 12);
      final m = DownloadRateMeter(clock: () => now);
      m.update(0, 40 * mb);
      now = now.add(const Duration(seconds: 10));
      // 10 МБ за 10 с → оставшиеся 30 МБ за ~30 с.
      final p = m.update(10 * mb, 40 * mb);
      expect(p.eta!.inSeconds, 30);
      expect(p.fraction, 0.25);
    });

    test('докачано — времени нет, остаток ноль', () {
      var now = DateTime(2026, 10, 12, 12);
      final m = DownloadRateMeter(clock: () => now);
      m.update(0, 40 * mb);
      now = now.add(const Duration(seconds: 5));
      final p = m.update(40 * mb, 40 * mb);
      expect(p.eta, isNull);
      expect(p.remaining, 0);
    });
  });

  group('Текст', () {
    test('две строки: скачано из всего, остаток и время', () {
      final t = downloadProgressText(ru, 'ru',
          download: DownloadProgress(
              received: (12.3 * mb).round(),
              total: (38.1 * mb).round(),
              eta: const Duration(seconds: 20)));
      expect(t, 'Загрузка 12,3 из 38,1 МБ\nосталось 25,8 МБ · ~20 с');
    });

    test('без оценки времени — только остаток', () {
      final t = downloadProgressText(en, 'en',
          download: DownloadProgress(received: 1 * mb, total: 4 * mb));
      expect(t, 'Downloading 1.0 of 4.0 MB\n3.0 MB left');
    });

    test('размер неизвестен — прежний процент', () {
      expect(downloadProgressText(ru, 'ru', fraction: 0.42),
          ru.updatesStatusDownloading(42));
    });

    test('время: секунды вверх, минуты после минуты', () {
      expect(etaText(ru, const Duration(milliseconds: 300)), '~1 с');
      expect(etaText(ru, const Duration(seconds: 59)), '~59 с');
      expect(etaText(ru, const Duration(seconds: 61)), '~2 мин');
    });
  });
}
