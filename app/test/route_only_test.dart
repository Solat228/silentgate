import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Режим «в туннель ТОЛЬКО эти подсети».
///
/// Ради чего он вообще есть: обычно туннель забирает маршрут по умолчанию, и в
/// него заходит весь трафик машины — «Прямо» разбирается уже ВНУТРИ ядра. Такой
/// трафик зависает вместе с ядром. С непустым `route_address` маршрута по
/// умолчанию туннель не получает, и остальное идёт мимо него физически.
void main() {
  const split = SplitTunnelConfig(
    mode: SplitMode.onlySelected,
    sites: [SiteRule('example.net', action: AppAction.tunnel)],
  );

  Map<String, dynamic> tunOf(TunOptions o) =>
      ((SingboxConfigBuilder(options: o).buildMap(split)['inbounds'] as List)
          .first) as Map<String, dynamic>;

  test('пустой список = обычный туннель, поля route_address нет', () {
    final tun = tunOf(const TunOptions(serverIps: ['203.0.113.10']));
    expect(tun.containsKey('route_address'), isFalse,
        reason: 'пустой route_address означал бы «не захватывать ничего» — '
            'туннель бы поднялся и не работал');
    expect(tun['auto_route'], isTrue);
  });

  test('непустой список попадает в route_address', () {
    final tun = tunOf(const TunOptions(
      serverIps: ['203.0.113.10'],
      routeOnlyCidrs: ['104.16.0.0/12', '2606:4700::/32'],
    ));
    expect(tun['route_address'], ['104.16.0.0/12', '2606:4700::/32']);
    // auto_route обязан остаться: без него маршруты не ставятся вообще, и
    // указанные подсети в туннель тоже не попадут.
    expect(tun['auto_route'], isTrue);
  });

  test('битые записи отбрасываются, целые остаются', () {
    final tun = tunOf(const TunOptions(
      serverIps: ['203.0.113.10'],
      routeOnlyCidrs: [
        '104.16.0.0/12',
        'мусор',
        '10.0.0.1', // без префикса
        '10.0.0.0/33', // префикс вне диапазона
        '2606:4700::/32',
      ],
    ));
    expect(tun['route_address'], ['104.16.0.0/12', '2606:4700::/32'],
        reason: 'ядро отвергает конфиг ЦЕЛИКОМ из-за одной битой записи');
  });

  test('режим и исключения сосуществуют', () {
    final tun = tunOf(const TunOptions(
      serverIps: ['203.0.113.10'],
      routeOnlyCidrs: ['104.16.0.0/12'],
      excludeCidrs: ['104.16.5.0/24'],
    ));
    expect(tun['route_address'], ['104.16.0.0/12']);
    expect(tun['route_exclude_address'], ['104.16.5.0/24']);
  });

  test('настройка доезжает от AppSettings до конфига', () {
    final o = TunOptions.fromSettings(
      const AppSettings(tunRouteOnlyCidrs: ['198.51.100.0/24']),
      serverIps: const ['203.0.113.10'],
    );
    expect(o.routeOnlyCidrs, ['198.51.100.0/24']);
    expect(tunOf(o)['route_address'], ['198.51.100.0/24']);
  });

  test('НАСТОЯЩЕЕ ядро принимает конфиг с route_address', () {
    final exe = File('../engine/windows/bin/sing-box.exe');
    if (!exe.existsSync()) {
      markTestSkipped('sing-box.exe не найден');
      return;
    }
    final json = SingboxConfigBuilder(
      options: const TunOptions(
        serverIps: ['203.0.113.10'],
        routeOnlyCidrs: ['104.16.0.0/12', '2606:4700::/32'],
        excludeCidrs: ['104.16.5.0/24'],
      ),
    ).buildJson(split);
    final dir = Directory('build/route-only')..createSync(recursive: true);
    final f = File('${dir.path}/route_only.json')..writeAsStringSync(json);
    final r = Process.runSync(exe.path, ['check', '-c', f.absolute.path]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(jsonDecode(json), isA<Map<String, dynamic>>());
  });

  group('Гибрид: системный прокси вместе с туннелем', () {
    test('по умолчанию выключен', () {
      expect(const AppSettings().alsoSetSystemProxy, isFalse,
          reason: 'смешанный режим ломает правила по приложениям — '
              'включать его молча нельзя');
    });

    test('переживает сохранение и требует переподключения', () {
      const before = AppSettings();
      final after = before.copyWith(alsoSetSystemProxy: true);
      expect(AppSettings.fromJson(after.toJson()).alsoSetSystemProxy, isTrue);
      expect(before.reconnectReasons(after), isNotEmpty,
          reason: 'захват ставится один раз при подъёме — правка «на живую» '
              'не применилась бы, и об этом надо сказать');
    });
  });

  group('Сторож зависшего ядра', () {
    test('по умолчанию включён и не слишком чуткий', () {
      const s = AppSettings();
      expect(s.tunWatchdogSeconds, greaterThanOrEqualTo(10),
          reason: 'меньше 10 с — ложные срабатывания на медленном старте');
    });

    test('переживает сохранение, ноль сохраняется как ноль', () {
      final off = const AppSettings().copyWith(tunWatchdogSeconds: 0);
      expect(AppSettings.fromJson(off.toJson()).tunWatchdogSeconds, 0,
          reason: '0 = «не следить», и он не должен подменяться дефолтом');
    });
  });
}
