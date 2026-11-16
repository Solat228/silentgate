import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/net/ip_info.dart';
import 'package:silentgate/core/net/socks5_http_bridge.dart';
import 'package:silentgate/core/net/speed_test.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/proxy_probe.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/whitelist_bypass/whitelist_relay_probe.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/auto_config_controller.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/settings_controller.dart';
import 'package:silentgate/ui/server_info_screen.dart';
import 'package:silentgate/ui/widgets/app_toast.dart';

/// Минимальный локальный SOCKS5-сервер на `127.0.0.1`, пробрасывающий TCP
/// на локальный тестовый HTTP-сервер (имитирует `whitelist-bypass` внутри звонка).
class _MockSocks5Server {
  final ServerSocket _server;
  final Set<Socket> _sockets = <Socket>{};
  int connectCount = 0;

  _MockSocks5Server._(this._server) {
    _server.listen(_onClient, onError: (_) {});
  }

  int get port => _server.port;

  static Future<_MockSocks5Server> start() async {
    final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return _MockSocks5Server._(srv);
  }

  Future<void> stop() async {
    await _server.close();
    for (final s in _sockets.toList()) {
      s.destroy();
    }
    _sockets.clear();
  }

  Future<void> _onClient(Socket client) async {
    _sockets.add(client);
    final buf = <int>[];
    Completer<void>? waiter;
    var closed = false;
    Socket? upstream;
    var piping = false;

    final sub = client.listen(
      (Uint8List chunk) {
        if (piping) {
          upstream?.add(chunk);
          return;
        }
        buf.addAll(chunk);
        final w = waiter;
        if (w != null && !w.isCompleted) {
          waiter = null;
          w.complete();
        }
      },
      onDone: () {
        closed = true;
        final w = waiter;
        if (w != null && !w.isCompleted) w.complete();
        upstream?.destroy();
      },
      onError: (_) {
        closed = true;
        final w = waiter;
        if (w != null && !w.isCompleted) w.complete();
        upstream?.destroy();
      },
    );

    Future<Uint8List?> readExact(int n) async {
      while (buf.length < n) {
        if (closed) return null;
        final w = Completer<void>();
        waiter = w;
        await w.future;
      }
      final out = Uint8List.fromList(buf.sublist(0, n));
      buf.removeRange(0, n);
      return out;
    }

    try {
      final g = await readExact(2);
      if (g == null || g[0] != 0x05) return;
      final methods = await readExact(g[1]);
      if (methods == null) return;
      client.add(const [0x05, 0x00]);
      await client.flush();

      final head = await readExact(4);
      if (head == null || head[0] != 0x05 || head[1] != 0x01) return;
      String host;
      switch (head[3]) {
        case 0x01:
          final raw = await readExact(4);
          if (raw == null) return;
          host = InternetAddress.fromRawAddress(raw).address;
        case 0x03:
          final len = await readExact(1);
          if (len == null) return;
          final raw = await readExact(len[0]);
          if (raw == null) return;
          host = utf8.decode(raw);
        default:
          return;
      }
      final pRaw = await readExact(2);
      if (pRaw == null) return;
      final targetPort = (pRaw[0] << 8) | pRaw[1];

      connectCount++;
      upstream = await Socket.connect(host, targetPort);
      _sockets.add(upstream);

      client.add(const [0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0]);
      await client.flush();

      piping = true;
      if (buf.isNotEmpty) {
        upstream.add(Uint8List.fromList(buf));
        buf.clear();
      }
      upstream.listen(
        (chunk) => client.add(chunk),
        onDone: () => client.destroy(),
        onError: (_) => client.destroy(),
      );
    } catch (_) {
      await sub.cancel();
      client.destroy();
      upstream?.destroy();
    }
  }
}

void main() {
  setUp(() {
    // Разрешаем локальные loopback HTTP-запросы к 127.0.0.1 в модульных тестах,
    // чтобы TestWidgetsFlutterBinding не подменял их заглушкой HTTP 400.
    HttpOverrides.global = null;
    WhitelistExitIpCache.clear();
    AppToast.resetProgressForTest();
    AppToast.dismiss();
  });

  tearDown(() {
    WhitelistExitIpCache.clear();
  });

  group('LocalHttpToSocksBridge + IpInfoService + ProxyProbe', () {
    test('пропускает авторизованные запросы через SOCKS5 и режет без пароля (407)',
        () async {
      final targetHttp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      targetHttp.listen((req) async {
        if (req.uri.path == '/generate_204') {
          req.response.statusCode = 204;
          await req.response.close();
          return;
        }
        if (req.uri.path == '/geo') {
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'ip': '203.0.113.230',
            'country': 'Italy',
            'country_code': 'IT',
            'region': 'Lombardy',
            'city': 'Milan',
            'connection': {'isp': 'Google LLC'},
          }));
          await req.response.close();
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      });

      final mockSocks = await _MockSocks5Server.start();
      final bridge = await LocalHttpToSocksBridge.start(
        socksPort: mockSocks.port,
      );

      try {
        // 1. Без кредов мост обязан отказать 407, не открывая SOCKS5-соединений.
        final unauth = await ProxyProbe.check(
          bridge.port,
          'http://127.0.0.1:${targetHttp.port}/generate_204',
          head: false,
          proxyUser: '',
          proxyPassword: '',
        );
        expect(unauth.ok, isFalse);
        expect(mockSocks.connectCount, 0);

        // 2. С кредами проба проходит через SOCKS5 и возвращает RTT в мс.
        final okProbe = await ProxyProbe.check(
          bridge.port,
          'http://127.0.0.1:${targetHttp.port}/generate_204',
          head: false,
          proxyUser: bridge.user,
          proxyPassword: bridge.password,
        );
        expect(okProbe.ok, isTrue);
        expect(okProbe.rttMs, isNotNull);
        expect(mockSocks.connectCount, greaterThanOrEqualTo(1));

        // 3. IpInfoService.lookup с кредами определяет реальный выходной IP узла БС.
        final info = await IpInfoService.lookup(
          proxyPort: bridge.port,
          proxyUser: bridge.user,
          proxyPassword: bridge.password,
          endpoints: ['http://127.0.0.1:${targetHttp.port}/geo'],
        );
        expect(info, isNotNull);
        expect(info!.ip, '203.0.113.230');
        expect(info.location, 'Milan, Lombardy, Italy');
        expect(info.isp, 'Google LLC');
      } finally {
        await bridge.stop();
        await mockSocks.stop();
        await targetHttp.close(force: true);
      }
    });
  });

  group('ProbeController: сервер БС пингуется и меряет скорость ЧЕРЕЗ звонок', () {
    final vkServer = ShareLinkParser.tryParse(
      'whitelist://vk/https://vk.ru/call/join/TestRoom123#VK%20%D0%97%D0%B2%D0%BE%D0%BD%D0%BA%D0%B8',
    )!;

    test('холодный пинг БС входит в звонок, выдаёт мс + passed и открывает замер скорости',
        () async {
      final targetHttp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      targetHttp.listen((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        req.response.statusCode = 204;
        await req.response.close();
      });
      final mockSocks = await _MockSocks5Server.start();
      var stopCalls = 0;
      var speedCalledPort = 0;

      final probe = ProbeController(
        whitelistProbeStarter: (
          server, {
          required variant,
          required realism,
          required cancel,
        }) async {
          final bridge = await LocalHttpToSocksBridge.start(
            socksPort: mockSocks.port,
          );
          return WhitelistRelayProbeHandle.forTest(
            httpPort: bridge.port,
            user: bridge.user,
            password: bridge.password,
            onStop: () async {
              stopCalls++;
              await bridge.stop();
            },
          );
        },
      );
      probe.speedDownload = ({
        required SpeedTestSize size,
        int? proxyPort,
        String proxyUser = '',
        String proxyPassword = '',
      }) async {
        speedCalledPort = proxyPort ?? 0;
        expect(proxyUser, isNotEmpty);
        expect(proxyPassword, isNotEmpty);
        return SpeedResult(
          bitsPerSecond: 48 * 1000 * 1000,
          bytes: size.bytes,
          elapsed: const Duration(seconds: 1),
        );
      };

      final settings = const AppSettings().copyWith(
        testUrl: 'http://127.0.0.1:${targetHttp.port}/generate_204',
        pingTimeoutMs: 3000,
      );

      try {
        await probe.pingOne(vkServer, settings);
        final res = probe.resultFor(vkServer);

        expect(res.outcome, PingOutcome.ok);
        expect(res.verification, PingVerification.passed,
            reason: 'сервер БС обязан проходить реальную проверку канала, а не висеть в ok/notRun');
        expect(res.latencyMs, isNotNull);
        expect(res.latencyMs, greaterThan(0));
        expect(res.speedMeasurable, isTrue);
        expect(probe.lastSummary, contains('рабочих 1 из 1'));
        expect(stopCalls, 1, reason: 'временный звонок обязан закрываться после пробы');

        // Замер скорости холодного сервера БС тоже поднимает звонок и сохраняет Мбит/с.
        expect(probe.canMeasureSpeed(vkServer), isTrue);
        await probe.measureSpeedOne(vkServer, settings);
        expect(speedCalledPort, greaterThan(0));
        expect(probe.speedFor(vkServer)?.mbps, closeTo(48.0, 0.01));
        expect(stopCalls, 2);
      } finally {
        probe.dispose();
        await mockSocks.stop();
        await targetHttp.close(force: true);
      }
    });

    test('недоступная комната БС помечается failed, не роняя прогон', () async {
      final probe = ProbeController(
        whitelistProbeStarter: (
          server, {
          required variant,
          required realism,
          required cancel,
        }) async =>
            WhitelistRelayProbeHandle.failed(),
      );
      try {
        await probe.pingOne(vkServer, const AppSettings());
        final res = probe.resultFor(vkServer);
        expect(res.outcome, PingOutcome.failed);
        expect(res.verification, PingVerification.failed);
        expect(res.speedMeasurable, isFalse);
      } finally {
        probe.dispose();
      }
    });
  });

  group('ServerInfoScreen: сервер БС не показывает 127.0.0.1:10855 и LLC VK', () {
    testWidgets('показывает реальный выходной IP звонка вместо локального порта',
        (t) async {
      final vkServer = ShareLinkParser.tryParse(
        'whitelist://vk/https://vk.ru/call/join/TestRoom123#VK%20%D0%97%D0%B2%D0%BE%D0%BD%D0%BA%D0%B8',
      )!;

      final probeCtrl = ProbeController();
      final settingsCtrl = SettingsController();
      final autoCtrl = AutoConfigController();

      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProbeController>.value(value: probeCtrl),
            ChangeNotifierProvider<SettingsController>.value(value: settingsCtrl),
            ChangeNotifierProvider<AutoConfigController>.value(value: autoCtrl),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ServerInfoScreen(
              server: vkServer,
              probeStarter: (_) async => WhitelistRelayProbeHandle.forTest(
                httpPort: 31234,
                user: 'u',
                password: 'p',
              ),
              ipViaProxyLookup: (port, user, password) async {
                expect(port, 31234);
                expect(user, 'u');
                expect(password, 'p');
                return const IpInfo(
                  ip: '203.0.113.230',
                  city: 'Milan',
                  region: 'Lombardy',
                  country: 'Italy',
                  countryCode: 'IT',
                  isp: 'Google LLC',
                );
              },
            ),
          ),
        ),
      );

      await t.pumpAndSettle();

      expect(find.text('127.0.0.1:10855'), findsNothing,
          reason: 'внутренний локальный порт релея не должен светиться как адрес сервера');
      expect(find.textContaining('203.0.113.230'), findsWidgets);
      expect(find.text('Milan, Lombardy, Italy'), findsOneWidget);
      expect(find.text('Google LLC'), findsOneWidget);

      probeCtrl.dispose();
      settingsCtrl.dispose();
      autoCtrl.dispose();
    });
  });

  group('AppToast: крестик закрытия есть на ЛЮБОМ уведомлении прогресса', () {
    Future<void> settle(WidgetTester t) async {
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('крестик закрывает активный прогресс и не пускает такты того же прогона',
        (t) async {
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: Text('главный'));
        }),
      ));
      await t.pump();

      AppToast.progress(ctx, id: 'ping', message: 'Пинг 1 из 10', value: 0.1);
      await settle(t);
      expect(find.text('Пинг 1 из 10'), findsOneWidget);
      expect(find.byKey(const ValueKey('progressToastClose_ping')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('progressToastClose_ping')));
      await settle(t);
      expect(find.text('Пинг 1 из 10'), findsNothing);

      // Следующие такты того же прогона подавлены и не всплывают обратно.
      AppToast.progress(ctx, id: 'ping', message: 'Пинг 5 из 10', value: 0.5);
      await settle(t);
      expect(find.text('Пинг 5 из 10'), findsNothing);

      // Финальный итог имеет свой крестик и тоже закрывается по нажатию.
      AppToast.progress(
        ctx,
        id: 'ping',
        message: 'Пинг завершён: рабочих 10 из 10 (2 с)',
        finished: true,
        kind: ToastKind.success,
      );
      await settle(t);
      expect(find.text('Пинг завершён: рабочих 10 из 10 (2 с)'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('progressToastClose_ping')));
      await settle(t);
      expect(find.text('Пинг завершён: рабочих 10 из 10 (2 с)'), findsNothing);
    });

    testWidgets('закреплённая карточка автонастройки тоже имеет крестик закрытия',
        (t) async {
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: Text('главный'));
        }),
      ));
      await t.pump();

      AppToast.progress(
        ctx,
        id: 'autoconfig',
        message: 'Подбор 1 из 20',
        value: 0.05,
        pinned: true,
      );
      await settle(t);

      expect(find.byIcon(Icons.unfold_less), findsOneWidget);
      expect(
        find.byKey(const ValueKey('progressToastClose_autoconfig')),
        findsOneWidget,
      );

      await t.tap(find.byKey(const ValueKey('progressToastClose_autoconfig')));
      await settle(t);
      expect(find.text('Подбор 1 из 20'), findsNothing);
    });
  });
}
