import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/subscription_info.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/device_id.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/subscription/subscription_service.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

/// Движок-пустышка: VPN к обновлению подписки отношения не имеет.
class _FakeEngine extends VpnEngine {
  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}

  @override
  Stream<VpnStatus> get statusStream => const Stream.empty();

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
  Future<void> dispose() async {}
}

/// Панель, которая считает обращения. Сети нет — проверяется ФАКТ ЗАПРОСА.
class _FakePanel extends SubscriptionService {
  _FakePanel({this.throwOnFetch = false, this.logoUrl});

  final bool throwOnFetch;
  final String? logoUrl;
  final List<String> urls = [];

  int get calls => urls.length;

  @override
  Future<SubscriptionResult> fetch(String url,
      {Map<String, String> deviceHeaders = const {}}) async {
    urls.add(url);
    if (throwOnFetch) throw SubscriptionException('панель недоступна');
    return SubscriptionResult(const [], SubscriptionInfo(logoUrl: logoUrl));
  }
}

/// Настоящий провайдер на Windows лезет в реестр — тесту это ни к чему.
class _FakeDeviceId implements DeviceIdProvider {
  @override
  Future<String> hwid() async => 'test-hwid';
  @override
  String osName() => 'Test';
  @override
  Future<String> osVersion() async => '1.0';
  @override
  Future<String> deviceModel() async => 'TestModel';
}

/// Обновление подписки при запуске приложения.
///
/// ⚠️ ЗАЧЕМ ОТДЕЛЬНАЯ НАСТРОЙКА, ЕСЛИ ЕСТЬ АВТООБНОВЛЕНИЕ. Автообновление
/// работает по ТАЙМЕРУ (по умолчанию 12 часов) и между запусками ничего не
/// гарантирует: открыл приложение через сутки — список серверов и остаток
/// трафика показывались прошлые, пока не подойдёт срок или пока не нажмёшь
/// «Обновить» руками. Владелец попросил тянуть подписку на каждом запуске.
void main() {
  group('Умолчание', () {
    test('включено — прямое решение владельца', () {
      expect(const AppSettings().updateSubscriptionOnStart, isTrue);
    });
  });

  group('Переживает диск', () {
    test('выключенная настройка не включается сама при чтении', () {
      const s = AppSettings(updateSubscriptionOnStart: false);
      expect(AppSettings.fromJson(s.toJson()).updateSubscriptionOnStart, isFalse,
          reason: 'класс багов: поле пишется в toJson, но не читается обратно');
    });

    test('старый файл без поля читается умолчанием', () {
      expect(
          AppSettings.fromJson({'captureMode': 'tun'})
              .updateSubscriptionOnStart,
          isTrue);
    });
  });

  group('copyWith не теряет поле', () {
    test('правка соседней настройки не сбрасывает эту', () {
      const s = AppSettings(updateSubscriptionOnStart: false);
      expect(s.copyWith(killSwitch: true).updateSubscriptionOnStart, isFalse);
    });

    test('поле переключается через copyWith', () {
      const s = AppSettings();
      expect(s.copyWith(updateSubscriptionOnStart: false)
          .updateSubscriptionOnStart, isFalse);
    });
  });

  group('Переподключение не требуется', () {
    test('настройка НЕ названа причиной переподключения', () {
      // Обновление подписки конфиг ядра не трогает. Попади оно в список причин
      // — пользователь получал бы плашку «переподключитесь» на ровном месте,
      // а при живом канале это ещё и предложение оборвать себе VPN.
      const a = AppSettings();
      expect(a.reconnectReasons(a.copyWith(updateSubscriptionOnStart: false)),
          isEmpty);
    });
  });

  // ── Сам запуск ──────────────────────────────────────────────────────────────

  /// ⚠️ ЧЕГО ЗДЕСЬ НЕ ХВАТАЛО. Всё выше проверяло НАСТРОЙКУ: умолчание, запись
  /// на диск, copyWith. Сам вызов `_maybeRefreshOnStart()` в `AppState.init()`
  /// не был покрыт ничем — его можно было удалить, и вся сюита оставалась
  /// зелёной. Настройка при этом включена по умолчанию у всех, кто обновится:
  /// молча отвалившись, она никак себя не проявляет, пока пользователь не
  /// заметит, что список серверов и остаток трафика после запуска старые.
  ///
  /// В сеть тесты не ходят: панель подменена (`_FakePanel`), а запрет
  /// `AppState._underTest` снимается только вместе с этой подменой
  /// (`debugAllowRefreshOnStart`).
  group('Запуск приложения: подписка обновляется', () {
    const url = 'https://panel.example/sub/token';
    const logoUrl = 'https://panel.example/logo.png';
    final id = SubscriptionProfile.idFor(url);
    Directory? tmp;

    setUp(() {
      setDeviceIdProviderForTests(_FakeDeviceId());
      AppState.debugAllowRefreshOnStart = true;
    });

    /// Живое состояние текущего теста — чтобы прибрать за ним централизованно.
    AppState? live;

    /// ⚠️ СНАЧАЛА ДОЖДАТЬСЯ ФОНОВОЙ ЦЕПОЧКИ, ПОТОМ СНИМАТЬ ПОДМЕНУ КАТАЛОГА.
    /// Обновление при запуске уходит в `unawaited` (старт не должен ждать
    /// сеть), и `panel.calls > 0` наступает на ПЕРВОМ шаге цепочки — импорт,
    /// запись профиля и логотип идут дальше уже после конца теста. Раньше
    /// `resetForTests()` успевал сработать первым, цепочка резолвила путь
    /// заново и писала в `%APPDATA%\SilentGate`: так был переписан боевой
    /// `subscriptions.json` владельца (14.08.2026). Теперь то же самое поймает
    /// предохранитель в `AppPaths`, но правильный порядок здесь всё равно
    /// нужен — иначе тесты будут падать не по своей вине.
    tearDown(() async {
      final st = live;
      if (st != null) {
        for (var i = 0; i < 200 && st.refreshing; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        // Иначе между тестами копятся четыре подписки на потоки, таймер
        // автообновления и наблюдатель сети — и фейковая панель прошлого теста
        // продолжает отвечать следующему.
        st.dispose();
        live = null;
      }
      AppState.debugAllowRefreshOnStart = false;
      setDeviceIdProviderForTests(null);
      AppPaths.resetForTests();
      try {
        tmp?.deleteSync(recursive: true);
      } catch (_) {}
      tmp = null;
    });

    /// Ждать СОБЫТИЯ, а не «сколько-нибудь миллисекунд»: обновление уходит
    /// без `await` (запуск не должен ждать сеть), и момент его завершения
    /// не задан ничем.
    Future<void> waitFor(bool Function() ready,
        {String what = 'ожидаемое состояние', int maxTicks = 400}) async {
      for (var i = 0; i < maxTicks; i++) {
        if (ready()) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(ready(), isTrue, reason: 'не дождались: $what');
    }

    /// Дать фоновой цепочке отработать, когда проверяем, что она НЕ сходила.
    /// Отрицательное утверждение ждать по событию нечем — здесь потолок честен.
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    /// Поднять `AppState` так, как он поднимается после перезапуска.
    AppState boot({
      bool updateOnStart = true,
      bool withSubscription = true,
      _FakePanel? panel,
    }) {
      tmp = Directory.systemTemp.createTempSync('sg_update_start_');
      AppPaths.overrideRoot(tmp!);
      final sep = Platform.pathSeparator;
      // ⚠️ Логотип кладём готовым, с тем же адресом, что вернёт панель:
      // `importSource` тянет аватарку, и без этого тест ушёл бы в сеть.
      final logo = File('${tmp!.path}${sep}logo.png')
        ..writeAsBytesSync(const [0x89, 0x50, 0x4e, 0x47]);
      File('${tmp!.path}${sep}silentgate_settings.json').writeAsStringSync(
          jsonEncode({
        'updateSubscriptionOnStart': updateOnStart,
        // Автообновление по таймеру — другая подсистема; здесь оно только
        // мешало бы отличить, кто именно сходил на панель.
        'autoUpdateEnabled': false,
      }));
      if (withSubscription) {
        File('${tmp!.path}${sep}subscriptions.json')
            .writeAsStringSync(jsonEncode({
          'activeId': id,
          'items': [
            {
              'id': id,
              'url': url,
              'servers': const <String>[],
              'logoUrl': logoUrl,
              'logoPath': logo.path,
            },
          ],
        }));
      }
      return live = AppState(
        engine: _FakeEngine(),
        subscription: panel ?? _FakePanel(logoUrl: logoUrl),
      );
    }

    test('⚠️ ГЛАВНОЕ: при запуске подписка ЗАПРАШИВАЕТСЯ', () async {
      final panel = _FakePanel(logoUrl: logoUrl);
      final state = boot(panel: panel);

      await state.init();
      await waitFor(() => panel.calls > 0, what: 'запрос подписки на запуске');
      expect(panel.urls.single, url, reason: 'запрошена активная подписка');

      // «Ровно один» проверяем ПОСЛЕ того, как цепочка досчитала: сразу после
      // первого запроса второму физически неоткуда взяться, и утверждение было
      // бы пустым.
      await waitFor(() => !state.refreshing, what: 'завершение обновления');
      await settle();
      expect(panel.calls, 1, reason: 'ровно один запрос, а не цикл');
    });

    test('настройка выключена — на панель не ходим', () async {
      final panel = _FakePanel(logoUrl: logoUrl);
      final state = boot(updateOnStart: false, panel: panel);

      await state.init();
      await settle();

      expect(panel.calls, 0,
          reason: 'человек снял галочку — обновления на запуске быть не должно');
    });

    test('подписки нет — обновлять нечего', () async {
      final panel = _FakePanel(logoUrl: logoUrl);
      final state = boot(withSubscription: false, panel: panel);

      await state.init();
      await settle();

      expect(panel.calls, 0);
    });

    test('⚠️ ОТКАЗ ПАНЕЛИ НЕ ПОКАЗЫВАЕТСЯ КРАСНЫМ БАННЕРОМ', () async {
      // Пользователь этого обновления не просил — он просто открыл приложение.
      // Без сети (самолёт, панель прилегла) баннер с текстом сетевого
      // исключения вылезал бы при КАЖДОМ холодном старте.
      final panel = _FakePanel(throwOnFetch: true, logoUrl: logoUrl);
      final state = boot(panel: panel);

      await state.init();
      await waitFor(() => panel.calls > 0, what: 'запрос подписки на запуске');
      await waitFor(() => !state.refreshing, what: 'завершение обновления');

      expect(state.error, isNull,
          reason: 'ошибка незапрошенного обновления остаётся в журнале');
    });
  });
}
