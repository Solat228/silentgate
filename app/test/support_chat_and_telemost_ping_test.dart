import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/cancel_token.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/support/dev_report_service.dart';
import 'package:silentgate/core/whitelist_bypass/whitelist_relay_probe.dart';
import 'package:silentgate/core/xray/harness_config_builder.dart';
import 'package:silentgate/engine/android/probe_harness_android.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/support_chat_controller.dart';
import 'package:silentgate/ui/widgets/support_chat_overlay.dart';

class _SpySupportChatController extends SupportChatController {
  final List<int> closedTicketIds = <int>[];

  @override
  Future<bool> closeTicket(int ticketId) async {
    closedTicketIds.add(ticketId);
    injectTicketsForTest(const [
      SupportTicketItem(id: 42, no: '5', status: 'closed'),
    ]);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  HttpOverrides? prevHttpOverrides;

  setUp(() {
    prevHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    tmp = Directory.systemTemp.createTempSync('sg_support_telemost_test_');
    AppPaths.overrideRoot(tmp);
    SupportChatController.clearMemoryStoreForTests();
  });

  tearDown(() {
    HttpOverrides.global = prevHttpOverrides;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('lol.silentgate/probe'),
      null,
    );
    SupportChatController.clearMemoryStoreForTests();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('SupportChatOverlay close-ticket confirmation & duplicate report check',
      () {
    test(
        'computeReportContentFingerprint matches 1-in-1 reports despite new SG code and inventory count',
        () {
      const r1 = '''
==================================================
  Отчёт для техподдержки (SG-234567)
==================================================
[Описание проблемы]
Не открывается YouTube
[Логи на диске]
app.log: 12 KB, строк 40
Отчёты поддержки: 1 шт., 15 KB
==================================================
[app.log]
==================================================
17.11.2026 04:00:01 [INFO] Подключение по команде пользователя
''';
      const r2Same = '''
==================================================
  Отчёт для техподдержки (SG-9KLMNP)
==================================================
[Описание проблемы]
Не открывается YouTube
[Логи на диске]
app.log: 12 KB, строк 40
Отчёты поддержки: 2 шт., 30 KB
==================================================
[app.log]
==================================================
17.11.2026 04:00:01 [INFO] Подключение по команде пользователя
''';
      const r3NewLogLine = '''
==================================================
  Отчёт для техподдержки (SG-9KLMNP)
==================================================
[Описание проблемы]
Не открывается YouTube
[Логи на диске]
app.log: 13 KB, строк 41
Отчёты поддержки: 2 шт., 30 KB
==================================================
[app.log]
==================================================
17.11.2026 04:00:01 [INFO] Подключение по команде пользователя
17.11.2026 04:00:15 [WARN] Таймаут рукопожатия TLS
''';

      final fp1 = DevReportService.computeReportContentFingerprint(r1);
      final fp2 = DevReportService.computeReportContentFingerprint(r2Same);
      final fp3 = DevReportService.computeReportContentFingerprint(r3NewLogLine);

      expect(fp1, fp2);
      expect(fp3, isNot(fp1));
    });

    test(
        'SupportChatController persists sent report fingerprint after sendMessage and detects 1-in-1 duplicate',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final closeBodies = <Map<String, dynamic>>[];
      server.listen((HttpRequest req) async {
        final rawBody = await utf8.decoder.bind(req).join();
        if (req.uri.path.endsWith('/support/close')) {
          closeBodies.add(jsonDecode(rawBody) as Map<String, dynamic>);
        }
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'ok': true,
          'tickets': [
            {
              'id': 1001,
              'no': '7',
              'status': req.uri.path.endsWith('/support/close') ? 'closed' : 'open',
              'messages': [
                {'id': 501, 'dir': 'in', 'text': 'Лог'},
              ],
            }
          ],
        }));
        await req.response.close();
      });

      final subUrl =
          'http://127.0.0.1:${server.port}/sub/TEST_TOKEN_123456';
      final ctrl = SupportChatController();
      addTearDown(ctrl.dispose);

      await ctrl.bindSubscriptionUrl(subUrl);

      final rep1 = File('${tmp.path}/silentgate-report-1.txt')
        ..writeAsStringSync(
          'Отчёт для техподдержки (SG-234567)\n'
          'Отчёты поддержки: 1 шт., 10 KB\n'
          '[app.log]\n'
          '17.11.2026 04:10:00 [INFO] Старт\n',
        );
      final rep2Identical = File('${tmp.path}/silentgate-report-2.txt')
        ..writeAsStringSync(
          'Отчёт для техподдержки (SG-ABCDEF)\n'
          'Отчёты поддержки: 2 шт., 20 KB\n'
          '[app.log]\n'
          '17.11.2026 04:10:00 [INFO] Старт\n',
        );
      final rep3Different = File('${tmp.path}/silentgate-report-3.txt')
        ..writeAsStringSync(
          'Отчёт для техподдержки (SG-ABCDEF)\n'
          'Отчёты поддержки: 3 шт., 30 KB\n'
          '[app.log]\n'
          '17.11.2026 04:10:00 [INFO] Старт\n'
          '17.11.2026 04:11:00 [ERROR] Отказ узла\n',
        );

      expect(ctrl.isDuplicateReportFile(rep1.path), isFalse);
      ctrl.addPendingFiles([rep1.path]);
      ctrl.updateDraftText('Первый отчёт');
      final sent = await ctrl.sendMessage();
      expect(sent, isTrue);

      expect(ctrl.isDuplicateReportFile(rep2Identical.path), isTrue);
      expect(ctrl.isDuplicateReportFile(rep3Different.path), isFalse);

      // Also verify closeTicket sends client_app + initiator_token over wire
      final closed = await ctrl.closeTicket(1001);
      expect(closed, isTrue);
      expect(closeBodies.single['client_app'], isNotEmpty);
      expect(closeBodies.single['initiator_token'], isNotEmpty);
    });

    testWidgets(
        'Вопрос решён has visible OutlinedButton border and asks confirmation before closing ticket',
        (tester) async {
      final ctrl = _SpySupportChatController();
      addTearDown(ctrl.dispose);
      await ctrl.bindSubscriptionUrl(
        'https://sub.silentgate.lol/sub/EXAMPLE_TOKEN_01',
      );
      ctrl.injectTicketsForTest(const [
        SupportTicketItem(
          id: 42,
          no: '5',
          status: 'open',
          messages: [
            SupportMessageItem(id: 10, dir: 'in', text: 'Проверка'),
          ],
        ),
      ]);
      await ctrl.open();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(
              children: [
                SupportChatOverlay(controller: ctrl),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final closeBtnFinder = find.byKey(const Key('supportCloseTicketButton'));
      expect(closeBtnFinder, findsOneWidget);
      expect(tester.widget(closeBtnFinder), isA<OutlinedButton>());

      // Tap 1: opens confirmation dialog, does NOT close ticket yet
      await tester.tap(closeBtnFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('supportConfirmCloseDialog')), findsOneWidget);
      expect(find.textContaining('Вы точно уверены'), findsOneWidget);
      expect(ctrl.closedTicketIds, isEmpty);

      // Tap Cancel -> dialog dismisses, ticket stays open
      await tester.tap(find.byKey(const Key('supportCancelCloseTicketButton')));
      await tester.pumpAndSettle();
      expect(ctrl.closedTicketIds, isEmpty);
      expect(ctrl.openTicket, isNotNull);

      // Tap again + Confirm -> closes ticket!
      await tester.tap(closeBtnFinder);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('supportConfirmCloseTicketButton')));
      await tester.pumpAndSettle();
      expect(ctrl.closedTicketIds, [42]);
      expect(ctrl.openTicket, isNull);
    });
  });

  group('Telemost /sgbs & standalone Telemost ping (Windows & Android)', () {
    final telemostPanelServer = VpnServer(
      protocol: 'vless',
      remark: 'Yandex Telemost IT1',
      address: '198.51.100.10',
      port: 443,
      id: '11111111-2222-4333-8444-555555555555',
      network: 'ws',
      security: 'none',
      path: '/sgbs?p=telemost&r=https%3A%2F%2Ftelemost.yandex.ru%2Fj%2F12345678901234',
      whitelistPlatform: 'telemost',
      whitelistRoom: 'https://telemost.yandex.ru/j/12345678901234',
      rawLink:
          'vless://11111111-2222-4333-8444-555555555555@198.51.100.10:443?type=ws&path=%2Fsgbs%3Fp%3Dtelemost#Yandex%20Telemost%20IT1',
      rawPanelConfig: jsonEncode({
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': '127.0.0.1',
                  'port': 10855,
                  'users': [
                    {
                      'id': '11111111-2222-4333-8444-555555555555',
                      'encryption': 'none',
                    }
                  ],
                }
              ],
            },
          }
        ],
        'routing': {'rules': []},
      }),
    );

    test(
        'HarnessConfigBuilder chains VLESS over dynamic whitelistRelayPort instead of static rawPanelConfig',
        () {
      expect(telemostPanelServer.usesWhitelistRelay, isTrue);
      expect(telemostPanelServer.isWhitelistBypass, isFalse);

      final builder = const HarnessConfigBuilder(
        ports: HarnessPorts(base: 22100),
      ).withAuth('u', 'p');

      final cfg = builder.buildMap([
        HarnessEntry(
          key: telemostPanelServer.key,
          server: telemostPanelServer,
          whitelistRelayPort: 38185,
        ),
      ]);

      final outbounds = (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
      final relaySocks = outbounds.firstWhere(
        (o) => o['tag'] == 'wb-relay-out-0',
        orElse: () => <String, dynamic>{},
      );
      expect(relaySocks['protocol'], 'socks');
      final servers =
          ((relaySocks['settings'] as Map)['servers'] as List).single as Map;
      expect(servers['port'], 38185);

      final vlessOut = outbounds.firstWhere((o) => o['tag'] == 'out-0');
      final sockopt =
          ((vlessOut['streamSettings'] as Map)['sockopt'] as Map);
      expect(sockopt['dialerProxy'], 'wb-relay-out-0');
    });

    test(
        'ProbeHarnessAndroid writes probe config for /sgbs server with whitelistRelayPort and retries cold wake-up',
        () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('lol.silentgate/probe'),
        (call) async {
          if (call.method == 'ping') {
            calls++;
            final args = (call.arguments as Map).cast<String, dynamic>();
            final cfgFile = File('${args['configPath']}');
            expect(cfgFile.existsSync(), isTrue);
            expect(cfgFile.readAsStringSync(), contains('38185'));
            if (calls == 1) return 0;
            if (calls == 2) return 260;
            return 145;
          }
          return null;
        },
      );

      final harness = ProbeHarnessAndroid();
      final handle = await harness.start([
        HarnessEntry(
          key: telemostPanelServer.key,
          server: telemostPanelServer,
          whitelistRelayPort: 38185,
        ),
      ]);
      addTearDown(handle.stop);

      final rtt = await handle.delayMs(0);
      expect(rtt, 145);
      expect(calls, 3);
    });

    test(
        'Standalone Telemost whitelist_bypass ping recovers when first 2 cold SFU frames fail',
        () async {
      var proxyHits = 0;
      final httpProxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => httpProxy.close(force: true));
      httpProxy.listen((req) async {
        proxyHits++;
        if (proxyHits <= 2) {
          req.response.statusCode = 502;
          await req.response.close();
          return;
        }
        req.response.statusCode = 204;
        await req.response.close();
      });

      const standaloneTelemost = VpnServer(
        protocol: 'whitelist_bypass',
        remark: 'Yandex Telemost IT1',
        address: 'telemost.yandex.ru',
        port: 0,
        id: '',
        whitelistPlatform: 'telemost',
        whitelistRoom: 'https://telemost.yandex.ru/j/9999999999',
        whitelistMode: 'video',
        rawLink: 'telemost://9999999999#Yandex%20Telemost%20IT1',
      );

      final probeCtrl = ProbeController(
        whitelistProbeStarter: (
          srv, {
          required variant,
          required realism,
          required CancelToken cancel,
        }) async =>
            WhitelistRelayProbeHandle.forTest(
          httpPort: httpProxy.port,
          user: '',
          password: '',
        ),
      );
      addTearDown(probeCtrl.dispose);

      await probeCtrl.pingOne(
        standaloneTelemost,
        const AppSettings().copyWith(
          testUrl: 'http://example.com/generate_204',
          pingTimeoutMs: 1200,
        ),
      );

      final res = probeCtrl.resultFor(standaloneTelemost);
      expect(res.isWorking, isTrue);
      expect(res.latencyMs, isNotNull);
      expect(proxyHits, greaterThanOrEqualTo(3));
    });
  });
}
