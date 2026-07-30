// Юнит-тесты по большому фидбэк-батчу v0.12.0–0.13.0: разбор панельной
// маршрутизации (#3.2), фавиконки корневого домена (#3.4), агрегация трафика
// панельных профилей (#5), приоритет интервала автообновления (#10), машина
// состояний тоста автоподбора TUN (#8), контроллер живой проверки сервисов (#6),
// персист новых настроек (#10/#6.1).
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/net/site_favicon.dart';
import 'package:silentgate/core/probe/service_check.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/xray/panel_routing_summary.dart';
import 'package:silentgate/engine/windows/xray_stats.dart';
import 'package:silentgate/state/service_check_controller.dart';

void main() {
  group('analyzePanelRouting (#3.2)', () {
    const panel = '''{
      "outbounds":[
        {"protocol":"vless","tag":"srv1"},
        {"protocol":"vless","tag":"srv2"},
        {"protocol":"vless","tag":"srv3"},
        {"protocol":"freedom","tag":"direct"},
        {"protocol":"blackhole","tag":"block"},
        {"protocol":"dns","tag":"dns-out"},
        {"protocol":"freedom","tag":"api"}
      ],
      "routing":{"rules":[
        {"type":"field","domain":["geosite:category-ru"],"outboundTag":"direct"},
        {"type":"field","protocol":["bittorrent"],"outboundTag":"block"},
        {"type":"field","network":"tcp,udp","balancerTag":"bal"}
      ]}
    }''';

    test('считает только прокси-серверы (freedom/blackhole/dns/api — не в счёт)', () {
      final info = analyzePanelRouting(panel);
      expect(info.serverCount, 3);
      expect(info.routesSomeDirect, isTrue);
      expect(info.routesSomeBlock, isTrue);
    });

    test('профиль без direct/block правил — флаги false', () {
      const simple = '''{
        "outbounds":[{"protocol":"vless","tag":"s1"}],
        "routing":{"rules":[{"type":"field","network":"tcp","balancerTag":"bal"}]}
      }''';
      final info = analyzePanelRouting(simple);
      expect(info.serverCount, 1);
      expect(info.routesSomeDirect, isFalse);
      expect(info.routesSomeBlock, isFalse);
    });

    test('битый JSON → пустая сводка, без исключения', () {
      expect(analyzePanelRouting('not json'), PanelRoutingInfo.empty);
      expect(analyzePanelRouting('{}').serverCount, 0);
    });
  });

  group('SiteFaviconService.rootDomain (#3.4)', () {
    test('простой домен возвращается как есть', () {
      expect(SiteFaviconService.rootDomain('example.com'), 'example.com');
      expect(SiteFaviconService.rootDomain('steam.com'), 'steam.com');
    });

    test('поддомен сводится к корню', () {
      expect(SiteFaviconService.rootDomain('www.example.com'), 'example.com');
      expect(SiteFaviconService.rootDomain('a.b.example.com'), 'example.com');
    });

    test('двухуровневый суффикс (co.uk) сохраняет три метки', () {
      expect(SiteFaviconService.rootDomain('example.co.uk'), 'example.co.uk');
      expect(SiteFaviconService.rootDomain('www.shop.example.co.uk'),
          'example.co.uk');
      expect(SiteFaviconService.rootDomain('a.example.com.br'), 'example.com.br');
    });
  });

  group('XrayStats.sumStatsQuery (#5)', () {
    test('суммирует все прокси-outbound, исключая direct/block/dns/api', () {
      const stdout = '''{"stat":[
        {"name":"outbound>>>srv1>>>traffic>>>uplink","value":"100"},
        {"name":"outbound>>>srv1>>>traffic>>>downlink","value":"1000"},
        {"name":"outbound>>>srv2>>>traffic>>>uplink","value":"50"},
        {"name":"outbound>>>srv2>>>traffic>>>downlink","value":"500"},
        {"name":"outbound>>>direct>>>traffic>>>uplink","value":"9999"},
        {"name":"outbound>>>block>>>traffic>>>downlink","value":"9999"},
        {"name":"outbound>>>api>>>traffic>>>uplink","value":"9999"},
        {"name":"inbound>>>socks>>>traffic>>>uplink","value":"7"}
      ]}''';
      final snap = XrayStats.sumStatsQuery(stdout);
      expect(snap.uplink, 150); // srv1 + srv2, без direct/api/inbound
      expect(snap.downlink, 1500); // srv1 + srv2, без block
    });

    test('тег `proxy` (обычный сервер) тоже считается', () {
      const stdout = '''{"stat":[
        {"name":"outbound>>>proxy>>>traffic>>>uplink","value":"42"},
        {"name":"outbound>>>proxy>>>traffic>>>downlink","value":"84"}
      ]}''';
      final snap = XrayStats.sumStatsQuery(stdout);
      expect(snap.uplink, 42);
      expect(snap.downlink, 84);
    });

    test('битый/пустой ввод → нули', () {
      expect(XrayStats.sumStatsQuery('not json').uplink, 0);
      expect(XrayStats.sumStatsQuery('{}').downlink, 0);
      expect(XrayStats.sumStatsQuery('{"stat":[]}').uplink, 0);
    });
  });

  group('resolveAutoUpdateIntervalHours (#10)', () {
    test('по умолчанию приоритет у поля приложения', () {
      expect(
        resolveAutoUpdateIntervalHours(
            preferSubscription: false, subscriptionHours: 6, fieldHours: 12),
        12,
      );
    });

    test('галочка «из подписки» → интервал панели', () {
      expect(
        resolveAutoUpdateIntervalHours(
            preferSubscription: true, subscriptionHours: 6, fieldHours: 12),
        6,
      );
    });

    test('подписка молчит → фолбэк на поле даже при галочке', () {
      expect(
        resolveAutoUpdateIntervalHours(
            preferSubscription: true, subscriptionHours: null, fieldHours: 12),
        12,
      );
    });
  });

  group('TunAutotuneTracking (#8)', () {
    VpnStatus tuning(String msg) => VpnStatus(VpnConnectionState.connecting,
        message: msg, phase: VpnPhase.tunAutotune);
    final t0 = DateTime(2026, 1, 1, 12);
    final t1 = DateTime(2026, 1, 1, 12, 1);

    test('обычное подключение (фаза normal) подбор НЕ запускает', () {
      final s = const TunAutotuneTracking()
          .next(const VpnStatus(VpnConnectionState.connecting), t0);
      expect(s.running, isFalse);
      expect(s.finishedAt, isNull);
    });

    test('статусы фазы tunAutotune → running с последним сообщением', () {
      var s = const TunAutotuneTracking().next(tuning('system, MTU 1500'), t0);
      expect(s.running, isTrue);
      expect(s.message, 'system, MTU 1500');
      expect(s.finishedAt, isNull);
      s = s.next(tuning('gvisor, MTU 1400'), t0);
      expect(s.message, 'gvisor, MTU 1400');
    });

    test('успех: первый connected фиксирует finishedAt и succeeded', () {
      var s = const TunAutotuneTracking().next(tuning('system, MTU 1500'), t0);
      s = s.next(const VpnStatus(VpnConnectionState.connected), t1);
      expect(s.running, isFalse);
      expect(s.finishedAt, t1);
      expect(s.succeeded, isTrue);
      // Последующий нефазовый статус состояние НЕ меняет (finishedAt стабилен).
      final s2 = s.next(const VpnStatus(VpnConnectionState.disconnected), t1);
      expect(identical(s, s2), isTrue);
    });

    test('неудача: error → finishedAt есть, succeeded false', () {
      var s = const TunAutotuneTracking().next(tuning('mixed, MTU 1280'), t0);
      s = s.next(
          const VpnStatus(VpnConnectionState.error, message: 'нет TUN'), t1);
      expect(s.running, isFalse);
      expect(s.succeeded, isFalse);
      expect(s.finishedAt, t1);
    });
  });

  group('VpnStatus.phase (#8)', () {
    test('по умолчанию normal', () {
      expect(const VpnStatus(VpnConnectionState.connected).phase,
          VpnPhase.normal);
      expect(const VpnStatus.disconnected().phase, VpnPhase.normal);
    });

    test('фаза переносится', () {
      const s = VpnStatus(VpnConnectionState.connecting,
          phase: VpnPhase.tunAutotune);
      expect(s.phase, VpnPhase.tunAutotune);
    });
  });

  group('ServiceCheckController (#6)', () {
    // На закрытом порту ждать готовности канала нечего — иначе каждый тест
    // простаивал бы штатные полминуты запаса, которые в бою отличают
    // «через VPN ничего не работает» от «прокси-ядро ещё не встало».
    setUp(() {
      ServiceCheckController.readinessAttempts = 1;
      ServiceCheckController.readinessDelay = Duration.zero;
    });

    test('по умолчанию все сервисы idle, никто не проверяется', () {
      final c = ServiceCheckController();
      expect(c.resultFor(ProbeService.youtube).state, ServiceCheckState.idle);
      expect(c.anyChecking, isFalse);
    });

    test('check по закрытому порту → fail (без интернета, локальный refuse)', () async {
      final c = ServiceCheckController();
      c.bind('srv1');
      // Порт 1 закрыт → прокси-соединение отклоняется сразу → недоступно.
      await c.check(ProbeService.youtube, 1);
      expect(c.resultFor(ProbeService.youtube).state, ServiceCheckState.fail);
      expect(c.anyChecking, isFalse);
    });

    test('bind другой сигнатурой сбрасывает прежние результаты', () async {
      final c = ServiceCheckController();
      c.bind('srv1');
      await c.check(ProbeService.youtube, 1);
      expect(c.resultFor(ProbeService.youtube).isTerminal, isTrue);
      c.bind('srv2'); // сменили сервер → результаты старого выхода не годятся
      expect(c.resultFor(ProbeService.youtube).state, ServiceCheckState.idle);
    });

    test('bind той же сигнатурой результаты сохраняет', () async {
      final c = ServiceCheckController();
      c.bind('srv1');
      await c.check(ProbeService.youtube, 1);
      c.bind('srv1');
      expect(c.resultFor(ProbeService.youtube).isTerminal, isTrue);
    });

    test('reset очищает и сбрасывает привязку', () async {
      final c = ServiceCheckController();
      c.bind('srv1');
      await c.check(ProbeService.youtube, 1);
      c.reset();
      expect(c.resultFor(ProbeService.youtube).state, ServiceCheckState.idle);
    });

    // Автопроверка при подъёме туннеля: ровно один прогон на соединение.
    test('autoCheckAll проверяет все сервисы разом', () async {
      final c = ServiceCheckController();
      c.bind('srv1');
      await c.autoCheckAll(1, const [ProbeService.youtube, ProbeService.telegram]);
      expect(c.resultFor(ProbeService.youtube).isTerminal, isTrue);
      expect(c.resultFor(ProbeService.telegram).isTerminal, isTrue);
    });

    test('autoCheckAll не повторяется для того же соединения', () async {
      final c = ServiceCheckController();
      c.bind('srv1');
      await c.autoCheckAll(1, const [ProbeService.youtube]);
      // Ручной сброс результата: если бы автопрогон повторился при следующем
      // перестроении интерфейса, сервис снова стал бы проверяться.
      c.bind('srv1');
      var notified = 0;
      c.addListener(() => notified++);
      await c.autoCheckAll(1, const [ProbeService.youtube]);
      expect(notified, 0, reason: 'второй автопрогон для того же соединения запрещён');
    });

    test('autoCheckAll повторяется на новом соединении', () async {
      final c = ServiceCheckController();
      c.bind('srv1');
      await c.autoCheckAll(1, const [ProbeService.youtube]);
      c.bind('srv2'); // переподключились/сменили сервер
      expect(c.resultFor(ProbeService.youtube).state, ServiceCheckState.idle);
      await c.autoCheckAll(1, const [ProbeService.youtube]);
      expect(c.resultFor(ProbeService.youtube).isTerminal, isTrue);
    });

    test('autoCheckAll без привязки не запускается', () async {
      final c = ServiceCheckController();
      await c.autoCheckAll(1, const [ProbeService.youtube]);
      expect(c.resultFor(ProbeService.youtube).state, ServiceCheckState.idle);
    });
  });

  group('Галочка «разрешить реальный IP» в правиле', () {
    test('переживает сохранение', () {
      final st = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        apps: const [
          AppRule(r'C:\a.exe', action: AppAction.direct, allowRealIp: false),
        ],
        sites: const [
          SiteRule('example.org', action: AppAction.direct),
          SiteRule('bank.ru', action: AppAction.direct, allowRealIp: false),
        ],
      );
      final back = SplitTunnelConfig.fromJson(st.toJson());
      expect(back.apps.single.allowRealIp, isFalse);
      expect(back.sites.first.allowRealIp, isTrue);
      expect(back.sites.last.allowRealIp, isFalse);
    });

    // Правила, заведённые до появления галочки, обязаны начать работать как
    // «Прямо»: раньше noRealIp молча уводил их в туннель.
    test('старые правила без поля получают разрешение', () {
      final st = SplitTunnelConfig.fromJson({
        'mode': 'onlySelected',
        'apps': [
          {'path': r'C:\a.exe', 'action': 'direct'}
        ],
        'sites': [
          {'domain': 'example.org', 'action': 'direct'}
        ],
      });
      expect(st.apps.single.allowRealIp, isTrue);
      expect(st.sites.single.allowRealIp, isTrue);
    });

    test('правка порта не сбрасывает галочку', () {
      const site = SiteRule('bank.ru', action: AppAction.direct, allowRealIp: false);
      expect(site.copyWith(port: 8443).allowRealIp, isFalse);
      expect(site.copyWith(clearPort: true).port, isNull);
    });
  });

  group('Персист новых настроек (#10/#6.1)', () {
    test('noRealIp / интервал автообновления / набор сервисов переживают JSON', () {
      final s = AppSettings.defaults.copyWith(
        noRealIp: true,
        autoUpdateIntervalHours: 48,
        autoUpdatePreferSubscription: true,
        autoConfigServices: {
          ProbeService.claude,
          ProbeService.gemini,
          ProbeService.x,
        },
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.noRealIp, isTrue);
      expect(back.autoUpdateIntervalHours, 48);
      expect(back.autoUpdatePreferSubscription, isTrue);
      expect(back.autoConfigServices, {
        ProbeService.claude,
        ProbeService.gemini,
        ProbeService.x,
      });
    });

    test('дефолты новых полей', () {
      const d = AppSettings.defaults;
      expect(d.noRealIp, isFalse);
      expect(d.autoUpdateIntervalHours, 12);
      expect(d.autoUpdatePreferSubscription, isFalse);
    });
  });
}
