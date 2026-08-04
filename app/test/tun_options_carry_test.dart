import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';

/// Страж класса багов «копия опций молча потеряла поле».
///
/// [TunOptions.copyWith] вызывается автоподбором стека/MTU — а это ДЕФОЛТ
/// (`tunStack: auto`), то есть путь большинства пользователей. [TunOptions
/// .asBlackhole] строит заглушку kill switch. Обе копии перечисляют поля
/// РУКАМИ, и забытое поле не ловит ни компилятор, ни `sing-box check`: конфиг
/// остаётся валидным, просто настройка перестаёт действовать.
///
/// Так уже терялись `platformTun` и `selfPackage` (ломался весь туннель на
/// Android), а следом — `ipv6Upstream`, `tunnelDnsForAll`, `blockQuic`,
/// `blockEncryptedDns` и `blockPagePort`.
///
/// Проверка не перечисляет поля: сравнивается ГОТОВЫЙ конфиг. Любое поле,
/// которое хоть как-то влияет на вывод, обязано пережить копию.
void main() {
  // Всё, что можно, отклонено от умолчания — иначе потерянное поле совпало бы
  // с дефолтом и тест бы этого не заметил.
  const opts = TunOptions(
    stack: 'gvisor',
    mtu: 1400,
    strictRoute: false,
    ipv6: false,
    ipv6Upstream: false,
    endpointIndependentNat: false,
    bypassLan: false,
    excludeCidrs: ['10.8.0.0/24'],
    routeOnlyCidrs: ['104.16.0.0/12'],
    dnsMode: DnsMode.custom,
    dnsServer: '9.9.9.9',
    dnsHijack: false,
    dnsStrategy: DnsStrategy.preferIpv6,
    logLevel: 'debug',
    serverIps: ['203.0.113.10'],
    serverDomains: ['node.example'],
    autotune: true,
    noRealIp: true,
    platformTun: true,
    selfPackage: 'lol.silentgate.test',
    directDnsUpstream: '192.168.1.1',
    logOutput: 'C:/tmp/singbox.log',
    tunnelDnsForAll: true,
    blockPagePort: 18080,
    clashApiPort: 10812,
    clashApiSecret: 'secret',
    blockQuic: true,
    blockEncryptedDns: true,
  );

  const split = SplitTunnelConfig(
    mode: SplitMode.onlySelected,
    apps: [
      AppRule('chrome.exe', byName: true, action: AppAction.tunnel),
      AppRule('bank.exe', byName: true, action: AppAction.direct, allowRealIp: true),
      AppRule('evil.exe', byName: true, action: AppAction.block),
    ],
    sites: [
      SiteRule('example.net', action: AppAction.tunnel),
      SiteRule('bank.ru', action: AppAction.direct, allowRealIp: true),
      SiteRule('ads.example', action: AppAction.block),
    ],
  );

  Map<String, dynamic> build(TunOptions o) =>
      SingboxConfigBuilder(options: o).buildMap(split);

  test('copyWith без аргументов даёт ПОБАЙТОВО тот же конфиг', () {
    expect(build(opts.copyWith()), build(opts),
        reason: 'автоподбор пересоздаёт опции на каждой комбинации стек×MTU — '
            'потерянное здесь поле исчезает у всех, у кого стек «Авто»');
  });

  test('copyWith меняет ровно стек и MTU и ничего больше', () {
    // На Android стек ФОРСИТСЯ в gvisor (system/mixed там не форвардят TCP),
    // поэтому перебор проверяем на настольных опциях — иначе тест мерил бы
    // не копирование полей, а этот форс.
    const desktop = TunOptions(
      stack: 'gvisor',
      mtu: 1400,
      strictRoute: false,
      ipv6: false,
      ipv6Upstream: false,
      bypassLan: false,
      excludeCidrs: ['10.8.0.0/24'],
      routeOnlyCidrs: ['104.16.0.0/12'],
      dnsMode: DnsMode.custom,
      dnsServer: '9.9.9.9',
      serverIps: ['203.0.113.10'],
      autotune: true,
      noRealIp: true,
      directDnsUpstream: '192.168.1.1',
      tunnelDnsForAll: true,
      blockPagePort: 18080,
      blockQuic: true,
      blockEncryptedDns: true,
    );

    final changed = build(desktop.copyWith(stack: 'system', mtu: 1280));
    final tun = (changed['inbounds'] as List).first as Map;
    expect(tun['stack'], 'system');
    expect(tun['mtu'], 1280);

    // Остальное — сверяем целиком, вырезав то, что и должно было измениться.
    final base = build(desktop);
    (((base['inbounds'] as List).first) as Map).remove('stack');
    (((base['inbounds'] as List).first) as Map).remove('mtu');
    tun.remove('stack');
    tun.remove('mtu');
    expect(changed, base);
  });

  test('заглушка kill switch объявляет ТОТ ЖЕ интерфейс', () {
    // Совпасть обязан именно `inbounds`: разойдись адреса или MTU — система
    // пересоздаст адаптер, а на этот миг трафик пойдёт мимо VPN. Ради закрытия
    // этого мига заглушка и существует.
    expect((build(opts.asBlackhole())['inbounds'] as List),
        (build(opts)['inbounds'] as List),
        reason: 'разный интерфейс у живого туннеля и заглушки = окно утечки');
  });

  test('из заглушки нет ни одного выхода наружу', () {
    final dead = build(opts.asBlackhole());

    // Правило ровно одно и это отказ: пользовательское «Прямо» выпустило бы
    // трафик мимо VPN — ровно то, что kill switch обязан запретить.
    expect((dead['route'] as Map)['rules'], [
      {'action': 'reject'}
    ]);
    // DNS-секции нет вовсе: резолвер — тоже канал наружу.
    expect(dead.containsKey('dns'), isFalse);
    expect((dead['outbounds'] as List).length, 1,
        reason: 'единственный outbound, и до него не доходит ни один пакет');
  });

  test('fromSettings доносит ipv6Available до обоих полей', () {
    final s = AppSettings(tunIpv6: true);

    final withV6 = TunOptions.fromSettings(s, ipv6Available: true);
    expect(withV6.ipv6, isTrue);
    expect(withV6.ipv6Upstream, isTrue);

    final noV6 = TunOptions.fromSettings(s, ipv6Available: false);
    expect(noV6.ipv6, isFalse);
    expect(noV6.ipv6Upstream, isFalse,
        reason: 'нет IPv6 наружу — адрес не объявляем и резать нечего');

    // Обратный случай: IPv6 наружу ЕСТЬ, но пользователь его выключил. Тогда
    // адрес объявить ОБЯЗАНЫ, иначе IPv6 уйдёт мимо туннеля под реальным IP.
    final refused = TunOptions.fromSettings(
        AppSettings(tunIpv6: false), ipv6Available: true);
    expect(refused.ipv6, isFalse);
    expect(refused.ipv6Upstream, isTrue);
  });
}
