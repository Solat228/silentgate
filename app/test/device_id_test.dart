import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/device_id.dart';

/// Заголовки устройства уходят панели Remnawave и участвуют в её device-limit.
/// Битое значение роняет ВЕСЬ запрос подписки (FormatException), поэтому
/// санитайзер и состав заголовков закреплены тестом.
class _FakeDeviceId implements DeviceIdProvider {
  final String id;
  final String os;
  final String version;
  final String model;
  _FakeDeviceId({
    this.id = 'test-hwid',
    this.os = 'TestOS',
    this.version = '1.0',
    this.model = 'TestModel',
  });

  @override
  Future<String> hwid() async => id;
  @override
  String osName() => os;
  @override
  Future<String> osVersion() async => version;
  @override
  Future<String> deviceModel() async => model;
}

void main() {
  tearDown(() => setDeviceIdProviderForTests(null));

  group('DeviceHeaders.headerSafe', () {
    test('кириллица и кавычки вычищаются, ASCII остаётся', () {
      // Реальная строка с локализованной Windows, из-за которой падал импорт.
      // Не-ASCII заменяется пробелами, пробелы схлопываются — осмысленная
      // ASCII-часть («Windows 11 …») сохраняется, и заголовок остаётся полезным.
      expect(
        DeviceHeaders.headerSafe(
            '"Майкрософт Windows 11 Корпоративная" 10.0 (Build 26100)'),
        'Windows 11 10.0 (Build 26100)',
      );
    });

    test('строка без ASCII превращается в unknown', () {
      expect(DeviceHeaders.headerSafe('Только кириллица'), 'unknown');
      // Модели Android у части производителей содержат не-ASCII.
      expect(DeviceHeaders.headerSafe('小米 手机'), 'unknown');
    });

    test('обычное значение проходит без изменений', () {
      expect(DeviceHeaders.headerSafe('10.0 (Build 26100)'), '10.0 (Build 26100)');
      expect(DeviceHeaders.headerSafe('Pixel 8 Pro'), 'Pixel 8 Pro');
    });

    test('пустое значение и пробелы дают unknown', () {
      expect(DeviceHeaders.headerSafe(''), 'unknown');
      expect(DeviceHeaders.headerSafe('   '), 'unknown');
    });

    test('длина ограничена 200 символами', () {
      expect(DeviceHeaders.headerSafe('a' * 500).length, 200);
    });
  });

  group('DeviceHeaders.build', () {
    test('состав заголовков соответствует контракту панели', () async {
      setDeviceIdProviderForTests(_FakeDeviceId());

      final h = await DeviceHeaders.build();

      expect(h.keys.toSet(),
          {'X-HWID', 'X-Device-OS', 'X-Ver-OS', 'X-Device-Model'});
      expect(h['X-HWID'], 'test-hwid');
      expect(h['X-Device-OS'], 'TestOS');
      expect(h['X-Ver-OS'], '1.0');
      expect(h['X-Device-Model'], 'TestModel');
    });

    test('каждое значение прогоняется через headerSafe', () async {
      // Ни одно поле не должно уехать в заголовок как есть: не-ASCII в любом
      // из них роняет запрос целиком.
      setDeviceIdProviderForTests(_FakeDeviceId(
        id: 'идентификатор',
        os: 'Android',
        version: '"14" (сборка)',
        model: '小米',
      ));

      final h = await DeviceHeaders.build();

      expect(h['X-HWID'], 'unknown');
      expect(h['X-Device-Model'], 'unknown');
      // Кавычки ломают кавычкование значения заголовка — их быть не должно.
      expect(h['X-Ver-OS'], isNot(contains('"')));
      for (final v in h.values) {
        expect(v.codeUnits.every((u) => u >= 0x20 && u <= 0x7E && u != 0x22),
            isTrue,
            reason: 'значение «$v» не безопасно для HTTP-заголовка');
      }
    });
  });
}
