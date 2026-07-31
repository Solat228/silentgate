import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/probe/auto_config_engine.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Проверка должна отвечать на вопрос «работает ли СЕРВИС», а не «открывается
/// ли его сайт». Владелец поймал разницу живьём: страница YouTube открывается,
/// а видео не грузятся; web.telegram.org открывается, а приложение — нет.
void main() {
  test('YouTube проверяется по видео-CDN, а не по сайту', () {
    final ep = AutoConfigCatalog.endpointFor(ProbeService.youtube)!;
    expect(ep.url, contains('googlevideo.com'),
        reason: 'режут именно CDN видео, сайт открывается и при блокировке');
    expect(ep.url, isNot(contains('www.youtube.com')));
  });

  test('404 от видео-CDN считается живым ответом', () {
    final ep = AutoConfigCatalog.endpointFor(ProbeService.youtube)!;
    // /videoplayback без параметров — 404, и это ответ ПО СУЩЕСТВУ.
    expect(ep.validator(404, ''), isTrue);
    // Заглушка провайдера — 200 с большой HTML-страницей.
    expect(ep.validator(200, 'x' * 5000), isFalse);
  });

  test('Telegram проверяется дозвоном до дата-центра', () {
    final ep = AutoConfigCatalog.endpointFor(ProbeService.telegram)!;
    expect(ep.url, startsWith('tcp://'),
        reason: 'MTProto не HTTP: запрос провалится на сертификате');
    expect(ep.url, isNot(contains('web.telegram.org')));
    // Порт обязателен — иначе проба не соберётся.
    expect(ep.url.split(':').last, '443');
  });

  test('у всех сервисов из набора у кнопки есть адрес проверки', () {
    for (final s in ProbeService.values) {
      final ep = AutoConfigCatalog.endpointFor(s);
      expect(ep, isNotNull, reason: 'сервис $s без проверки');
      expect(ep!.url, isNotEmpty);
    }
  });
}
