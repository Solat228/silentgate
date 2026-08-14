import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/android/android_engine.dart';

/// ⚠️ КАТАЛОГ ГЕО-БАЗ ПЕРЕДАЁТСЯ ЯДРУ В САМОМ КОНФИГЕ, А НЕ ЧЕРЕЗ ОКРУЖЕНИЕ.
///
/// Разбор живого отчёта владельца (15.08.2026) и воспроизведение на эмуляторе
/// `sg-test`: базы лежат на месте, а VPN не поднимается вовсе —
///
/// ```
/// common/geodata: illegal ip rule: geoip:private
///   > failed to open geoip.dat
///   > stat /system/bin/geoip.dat: no such file or directory
/// ```
///
/// `/system/bin` — путь ПО УМОЛЧАНИЮ, куда Go идёт, когда переменной
/// `XRAY_LOCATION_ASSET` для него не существует. Мы её ставили — из Kotlin,
/// через `android.system.Os.setenv`, ещё в `Application.onCreate`.
///
/// ⚠️ И ЭТО НЕ РАБОТАЕТ В ПРИНЦИПЕ, СКОЛЬКО БЫ РАНО МЫ ЕЁ НИ СТАВИЛИ.
/// `Os.setenv` правит окружение **libc**, а рантайм Go держит свою копию,
/// снятую при собственной инициализации, и в libc больше не заглядывает.
/// Прежний комментарий в коде объяснял отказ ПОРЯДКОМ загрузки библиотеки —
/// вывод «переносить обратно нельзя» был верен, причина названа неверно.
/// Проверено опытом: принудительная загрузка ядра сразу после `setenv` отказ
/// НЕ вылечила.
///
/// Работает другое: у Xray есть блок `env` ВНУТРИ конфига, который ядро
/// применяет своим `os.Setenv` — уже внутри Go. Это зафиксировано тестами
/// самого libXray: `TestInvokeRunXrayAppliesConfigEnv` (применяется) и
/// `TestInvokeIgnoresTopLevelEnv` (на верхнем уровне запроса игнорируется —
/// поэтому кладём именно в конфиг, а не рядом с ним).
void main() {
  const dir = '/data/user/0/lol.silentgate/files/SilentGate/geo';

  Map<String, dynamic> decode(String s) =>
      jsonDecode(s) as Map<String, dynamic>;

  group('Каталог гео-баз в конфиге', () {
    test('⚠️ ГЛАВНОЕ: путь попадает в env конфига', () {
      final out = decode(AndroidEngine.withAssetEnv('{"outbounds":[]}', dir));
      expect(out['env'], isA<Map>());
      expect((out['env'] as Map)['XRAY_LOCATION_ASSET'], dir,
          reason: 'без этого ядро ищет базы в /system/bin и падает целиком');
    });

    test('остальной конфиг не тронут', () {
      const src = '{"outbounds":[{"tag":"proxy"}],"routing":{"rules":[]}}';
      final out = decode(AndroidEngine.withAssetEnv(src, dir));
      expect(out['outbounds'], [
        {'tag': 'proxy'}
      ]);
      expect(out['routing'], {'rules': []});
    });

    test('⚠️ значение ПАНЕЛИ сильнее нашего', () {
      // Панель вправе прислать свой каталог; перетереть его значило бы решать
      // за неё. Наш путь — умолчание, а не приказ.
      final out = decode(AndroidEngine.withAssetEnv(
          '{"env":{"XRAY_LOCATION_ASSET":"/своё/место"}}', dir));
      expect((out['env'] as Map)['XRAY_LOCATION_ASSET'], '/своё/место');
    });

    test('соседние переменные панели сохраняются', () {
      final out = decode(
          AndroidEngine.withAssetEnv('{"env":{"XRAY_OTHER":"1"}}', dir));
      final env = out['env'] as Map;
      expect(env['XRAY_OTHER'], '1');
      expect(env['XRAY_LOCATION_ASSET'], dir);
    });

    test('битый конфиг возвращается как есть, без исключения', () {
      // Дальше по цепочке сработает страховка с чисткой гео-правил — уронить
      // подключение здесь было бы хуже, чем не помочь.
      const junk = 'не json вовсе';
      expect(AndroidEngine.withAssetEnv(junk, dir), junk);
    });

    test('конфиг-массив (не объект) тоже не ломается', () {
      const arr = '[1,2,3]';
      expect(AndroidEngine.withAssetEnv(arr, dir), arr);
    });
  });
}
