import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/engine/windows/singbox_stats.dart';

/// Страж рассинхрона между построителем конфига и счётчиком трафика.
///
/// Счётчик отделяет прямой трафик от проксированного ПО ТЕГАМ, которые задаём
/// мы сами в конфиге. Переименование тега в построителе молча превратит прямой
/// трафик в «проксированный» — компилятор такое не ловит, а на экране это
/// выглядит правдоподобно. Ровно класс багов «поле пишется, но не читается».
void main() {
  test('все не-VPN теги построителя известны счётчику', () {
    final cfg = SingboxConfigBuilder(
      options: const TunOptions(serverIps: ['203.0.113.10']),
    ).buildMap(const SplitTunnelConfig());
    final tags = (cfg['outbounds'] as List)
        .cast<Map<String, dynamic>>()
        .map((o) => (o['tag'] ?? '').toString())
        .where((t) => t.isNotEmpty && t != 'proxy')
        .toSet();
    expect(tags, isNotEmpty, reason: 'иначе тест ничего не проверяет');
    for (final t in tags) {
      expect(SingboxStats.directTags, contains(t),
          reason: 'тег "' + t + '" есть в конфиге, но счётчик про него не знает — '
              'его трафик засчитается как ушедший через VPN');
    }
  });

  test('тег proxy счётчик НЕ считает прямым', () {
    expect(SingboxStats.directTags, isNot(contains('proxy')));
  });

  group('Разделение прямого и проксированного', () {
    // Данные ровно той формы, что отдаёт Clash API: у соединения есть цепочка
    // outbound'ов, и наличие в ней нашего direct-тега означает «ушло мимо VPN».
    final payload = {
      'uploadTotal': 1000,
      'downloadTotal': 2000,
      'connections': [
        {'chains': ['proxy'], 'upload': 10, 'download': 20},
        {'chains': ['direct'], 'upload': 700, 'download': 900},
        {'chains': ['urltest', 'proxy'], 'upload': 5, 'download': 7},
        {'chains': ['dns-out'], 'upload': 1, 'download': 1},
      ],
    };

    test('считается только то, что ушло через VPN', () {
      final snap = SingboxStats.sumProxiedForTest(payload['connections']);
      expect(snap.uplink, 15, reason: '10 + 5, прямое и DNS не в счёт');
      expect(snap.downlink, 27);
    });

    test('глобальные итоги включали бы прямой трафик', () {
      // Ради этого разделение и заводилось: 1000/2000 против 15/27.
      expect(payload['uploadTotal'], isNot(15));
    });

    test('мусор вместо списка не роняет счётчик', () {
      final snap = SingboxStats.sumProxiedForTest('не список');
      expect(snap.uplink, 0);
      expect(snap.downlink, 0);
    });
  });
}
