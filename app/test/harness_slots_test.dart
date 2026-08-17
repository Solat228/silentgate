import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/probe/singbox_harness_windows.dart';
import 'package:silentgate/engine/windows/probe/xray_harness_windows.dart';

/// ОДНОВРЕМЕННЫЕ ХАРНЕССЫ НЕ ИМЕЮТ ПРАВА ДРАТЬСЯ ЗА ОДИН ПОРТ.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. Параллельная автонастройка (`autoConfigConcurrency`,
/// умолчание 3) поднимает по отдельному харнессу на кандидата, а база портов
/// была КОНСТАНТОЙ — все просили 21000 и писали один `harness_config.json`.
///
/// Отказ был молчаливым и потому особенно скверным: два `xray.exe` падали на
/// «address already in use», но `_waitReady(21000)` проходил у всех троих —
/// порт-то слушает выживший. Дальше пробы уходили на ЧУЖОЕ ядро: у кого пароль
/// не совпал, тот получал 407 и объявлял исправный сервер нерабочим; у кого
/// совпал — мерил чужой сервер и записывал результат своему кандидату. То есть
/// список «лучших серверов» собирался из перепутанных замеров.
///
/// Тот же баг уже был оплачен на Android (`withPortBase`), но Windows его не
/// звал нигде — платформы разъехались молча.
void main() {
  group('У каждого харнесса свой диапазон портов', () {
    test('⚠️ ГЛАВНОЕ: три подряд созданных Xray-харнесса не совпадают портами',
        () {
      final ports = [
        for (var i = 0; i < 3; i++) XrayHarnessWindows().builder.ports.base,
      ];
      expect(ports.toSet().length, 3,
          reason: 'ЗДЕСЬ БЫЛА ДРАКА ЗА ПОРТ: все три просили 21000');
    });

    test('диапазоны не налезают друг на друга', () {
      final a = XrayHarnessWindows().builder.ports.base;
      final b = XrayHarnessWindows().builder.ports.base;
      expect((a - b).abs(), greaterThanOrEqualTo(16),
          reason: 'у харнесса по два порта на запись, записей бывает несколько');
    });

    test('sing-box-харнесс разведён так же и не пересекается с Xray', () {
      final xray = [
        for (var i = 0; i < 3; i++) XrayHarnessWindows().builder.ports.base,
      ];
      final sing = [
        for (var i = 0; i < 3; i++) SingboxHarnessWindows().builder.ports.base,
      ];
      expect(sing.toSet().length, 3);
      expect(xray.toSet().intersection(sing.toSet()), isEmpty,
          reason: 'ядра разные, а порт один — уже наступали (10085, 10809)');
    });
  });
}
