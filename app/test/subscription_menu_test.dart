import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/l10n/gen/app_localizations_ru.dart';
import 'package:silentgate/state/app_state.dart';
import 'package:silentgate/ui/widgets/subscription_bar.dart';

/// Меню ⋮ у карточки подписки.
///
/// ⚠️ ЗАМЕЧАНИЕ ВЛАДЕЛЬЦА (1.4.3, скриншот 2): «в меню трёх точек у подписки
/// лишний пункт „Добавить подписку“ — убрать». Меню карточки — про ЭТУ
/// подписку (обновить её, скопировать её ссылку, удалить её), и заведение
/// новой в нём чужое.
///
/// ⚠️ И ВТОРАЯ ПОЛОВИНА ТОГО ЖЕ ТРЕБОВАНИЯ: убрать пункт нельзя, если он был
/// единственным входом. Поэтому здесь же стережётся, что добавление подписки
/// остаётся достижимым из другого места (кнопка «Импорт» в шапке главного
/// экрана).
void main() {
  final l = AppLocalizationsRu();

  group('Пункты меню карточки подписки', () {
    Directory? tmp;
    late AppState state;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('sg_sub_menu_');
      AppPaths.overrideRoot(tmp!);
      final sep = Platform.pathSeparator;
      // Автообновление выключено: тест не должен ходить в сеть.
      File('${tmp!.path}${sep}silentgate_settings.json')
          .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
      File('${tmp!.path}${sep}subscriptions.json')
          .writeAsStringSync(jsonEncode({
        'activeId': _id,
        'items': [
          {'id': _id, 'url': _url, 'servers': [_link]},
        ],
      }));
      state = AppState(engine: _FakeEngine());
      await state.init();
    });

    tearDown(() async {
      state.dispose();
      // Фоновые цепочки состояния успевают дописать файлы уже после dispose —
      // сперва даём им кадр, и только потом снимаем подмену каталога.
      await Future<void>.delayed(Duration.zero);
      AppPaths.resetForTests();
      try {
        tmp?.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> openMenu(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          locale: Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SubscriptionBar()),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }

    testWidgets('«Добавить подписку» в меню НЕТ', (tester) async {
      await openMenu(tester);
      // Меню действительно открылось — иначе «пункта нет» было бы правдой
      // просто потому, что нет и меню.
      expect(find.text(l.subBarCopyLink), findsOneWidget);
      expect(find.text(l.subBarAddSubscription), findsNothing,
          reason: 'ЗДЕСЬ БЫЛ ЛИШНИЙ ПУНКТ: меню карточки — про эту подписку');
    });

    testWidgets('остальные пункты на месте — убрали ровно один',
        (tester) async {
      await openMenu(tester);
      expect(find.text(l.subBarRefresh), findsOneWidget);
      expect(find.text(l.subBarCopyLink), findsOneWidget);
      expect(find.text(l.subBarDeleteSubscription), findsOneWidget);
      // «Поддержка» есть и в меню, и кнопкой в самой карточке.
      expect(find.text(l.subBarSupport), findsWidgets);
    });
  });

  group('Добавить подписку по-прежнему есть где', () {
    test('⚠️ экран импорта открывается НЕ ТОЛЬКО из карточки подписки', () {
      // Тест читает исходники, и это осознанно: проверяется не вёрстка, а
      // ДОСТИЖИМОСТЬ возможности. Поднять для этого главный экран целиком
      // нельзя — он тянет полдюжины провайдеров и стартовые цепочки; а без
      // проверки удаление пункта из меню однажды окажется удалением
      // последнего входа, и добавить подписку станет нечем.
      final callers = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('subscription_bar.dart')) continue;
        if (f.readAsStringSync().contains('ImportScreen(')) {
          callers.add(f.path);
        }
      }
      expect(callers, isNotEmpty,
          reason: 'после удаления пункта из меню единственным входом осталась '
              'кнопка «Импорт» в шапке главного экрана — если исчезнет и она, '
              'подписку будет не добавить вовсе');
      expect(callers.any((p) => p.endsWith('home_screen.dart')), isTrue,
          reason: 'вход обязан быть на видном месте, а не в дальнем экране');
    });
  });
}

const _url = 'https://panel.example/sub/aaaaaaaa';
final _id = SubscriptionProfile.idFor(_url);
const _link = 'vless://11111111-1111-1111-1111-111111111111@a1.example:443'
    '?type=tcp&security=none#Alpha-1';

/// Движок-пустышка: `AppState` подписывается на его потоки в конструкторе,
/// самому тесту движок не нужен — ни одного подключения здесь нет.
class _FakeEngine extends VpnEngine {
  final _statusCtrl = StreamController<VpnStatus>.broadcast();

  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}

  @override
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<TrafficStats> get statsStream => const Stream.empty();

  @override
  Stream<String> get blockedHostEvents => const Stream.empty();

  @override
  Stream<EngineNotice> get notices => const Stream.empty();

  @override
  VpnStatus get status => const VpnStatus.disconnected();

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}
