import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/net/api_ports.dart';
import 'package:silentgate/core/settings/split_tunnel.dart';
import 'package:silentgate/core/singbox/exit_tags.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/engine/windows/tun/singbox_router_windows.dart';

/// Раунд исправлений 1, находка 1: `SingboxRouterWindows` — ЕДИНСТВЕННОЕ
/// место на Windows, где `SingboxConfigBuilder` реально вызывается
/// (`_startOnce`). Построитель умел `apiExitServerKeys`/`apiToken` сам по
/// себе, но роутер их никуда не передавал — порты API не создавались
/// НИКОГДА при живом подключении, хотя `test/api_ports_test.dart` был
/// зелёным: он зовёт построитель мимо роутера и этого не видит.
///
/// ⚠️ `start()` здесь НЕ вызывается — он запрашивает права администратора и
/// стартует процесс (`Elevation.runElevatedAsync`, `TunScheduledTask.run`).
/// `primeSessionForTest`/`configJsonFor` — тестовый шов: `primeSessionForTest`
/// заполняет ТЕ ЖЕ поля, что и `start()` (через общий приватный `_prime`, а
/// не отдельную копипасту), `configJsonFor` строит РЕАЛЬНО ЗАПИСЫВАЕМЫЙ в
/// файл конфиг — тот же вызов, что использует `_startOnce`.
void main() {
  group('SingboxRouterWindows: конфиг, который реально пишет роутер', () {
    test('apiExitServerKeys/apiToken доходят до конфига', () {
      const keyA = 'vless://a';
      final router = SingboxRouterWindows();
      router.primeSessionForTest(
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
        apiExitServerKeys: const [keyA],
        apiToken: 'secret',
      );
      final json =
          router.configJsonFor(const SplitTunnelConfig(), 10808, const TunOptions());
      final cfg = jsonDecode(json) as Map<String, dynamic>;

      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins.any((i) => i['tag'] == apiExitInboundTag(keyA)), isTrue,
          reason: 'роутер не передал apiExitServerKeys/apiToken в '
              'SingboxConfigBuilder — именно так фича не работала вовсе');

      final rules = (cfg['route']['rules'] as List).cast<Map<String, dynamic>>();
      expect(
          rules.any((r) =>
              (r['inbound'] as List?)?.contains(apiExitInboundTag(keyA)) == true &&
              r['outbound'] == exitTagFor(keyA)),
          isTrue,
          reason: 'нет правила inboundTag -> outboundTag в конфиге роутера');
    });

    test('контрольный кейс: без прайминга порта нет (тест не ложноположительный)', () {
      final router = SingboxRouterWindows();
      final json =
          router.configJsonFor(const SplitTunnelConfig(), 10808, const TunOptions());
      final cfg = jsonDecode(json) as Map<String, dynamic>;
      final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(ins.any((i) => '${i['tag']}'.startsWith('api-exit-')), isFalse);
    });

    test('exitOutbounds и креды локального SOCKS тоже доходят', () {
      // Не только новые поля: старые (`exitOutbounds`/`xraySocksUser`/
      // `xraySocksPassword`) обязаны продолжать доходить тем же путём — иначе
      // рефакторинг ради API сломал бы мульти-VPN, который был здесь раньше.
      const keyB = 'vless://b';
      final router = SingboxRouterWindows();
      router.primeSessionForTest(
        exitOutbounds: [
          {'tag': exitTagFor(keyB), 'type': 'vless'},
        ],
        xraySocksUser: 'sg',
        xraySocksPassword: 'pw',
      );
      final json =
          router.configJsonFor(const SplitTunnelConfig(), 10808, const TunOptions());
      final cfg = jsonDecode(json) as Map<String, dynamic>;

      final outbounds = (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['username'], 'sg');
      expect(proxy['password'], 'pw');
      expect(outbounds.any((o) => o['tag'] == exitTagFor(keyB)), isTrue);
    });

    /// ⚠️ ТОТ ЖЕ УРОК, ЧТО И У `apiExitServerKeys`: поле, которое построитель
    /// умеет, но роутер не передаёт, не работает НИКОГДА — а прямые тесты
    /// построителя этого не видят, потому что зовут его мимо роутера.
    test('apiOnlyExitKeys доходят: правило активного сервера идёт в proxy', () {
      const keyA = 'vless://a';
      final router = SingboxRouterWindows();
      router.primeSessionForTest(
        exitOutbounds: [
          {'tag': exitTagFor(keyA), 'type': 'vless'},
        ],
        apiExitServerKeys: const [keyA],
        // Активный сервер: outbound ему собран ради порта, но правилам он не
        // адресат — иначе к одному узлу пошло бы второе соединение.
        apiOnlyExitKeys: const [keyA],
        apiToken: 'secret',
      );
      const split = SplitTunnelConfig(
        mode: SplitMode.onlySelected,
        sites: [SiteRule('2ip.ru', action: AppAction.tunnel, serverKey: keyA)],
      );
      final cfg = jsonDecode(router.configJsonFor(split, 10808, const TunOptions()))
          as Map<String, dynamic>;
      final rules = (cfg['route']['rules'] as List).cast<Map<String, dynamic>>();

      final site = rules.firstWhere((r) =>
          (r['domain_suffix'] as List?)?.contains('2ip.ru') == true &&
          r['outbound'] != null);
      expect(site['outbound'], 'proxy');
      // И при этом порт живой — ради него всё и затевалось.
      expect(
          rules.any((r) =>
              (r['inbound'] as List?)?.contains(apiExitInboundTag(keyA)) ==
                  true &&
              r['outbound'] == exitTagFor(keyA)),
          isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('⚠️ Отмена подключения не ждёт конца подбора параметров', () {
    /// Просьба владельца 20.08.2026: «сделай возможность отключения VPN до
    /// того, как он автоматически подключится, чтобы юзер мог не ждать, пока
    /// подберутся параметры».
    ///
    /// ⚠️ ПОЧЕМУ СТРАЖ ПО ИСХОДНИКУ. Настоящую отмену не проверить тестом:
    /// `start()` запрашивает права администратора и поднимает процесс ядра, а
    /// ожидание адаптера спрашивает систему. Единственное, что можно
    /// удержать, — что признак отмены ЧИТАЕТСЯ ВНУТРИ цикла ожидания, а не
    /// только между комбинациями подбора.
    late String source;

    setUp(() {
      source = File('lib/engine/windows/tun/singbox_router_windows.dart')
          .readAsLinesSync()
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join(String.fromCharCode(10));
    });

    test('признак отмены доходит до ожидания адаптера', () {
      expect(source, contains('Future<void> _waitUp({bool Function()? abort})'),
          reason: 'без параметра ожидание не знает об отмене вовсе');
      expect(source, contains('_waitUp(abort: abort)'),
          reason: 'признак обязан передаваться, а не просто быть объявленным');
    });

    test('⚠️ отмена проверяется В ЦИКЛЕ, а не один раз до него', () {
      // До 20.08.2026 отмена читалась только между комбинациями подбора, а
      // самое долгое ожидание — здесь: до 12 секунд на каждую из девяти.
      // Нажав «Отключить» на первой же, человек ждал конца текущей попытки.
      final wait = source.substring(source.indexOf('Future<void> _waitUp('));
      final loopAt = wait.indexOf('while (');
      final checkAt = wait.indexOf('abort?.call()');
      expect(loopAt, greaterThan(0));
      expect(checkAt, greaterThan(loopAt),
          reason: 'проверка обязана стоять ВНУТРИ цикла: снаружи она сработает '
              'только через двенадцать секунд');
    });

    test('оба вызова подъёма передают отмену', () {
      // Их два: обычный путь и путь автоподбора. Забыть один — значит оставить
      // половину случаев неотменяемой.
      expect(RegExp(r'_startOnce\([^)]*abort: abort').allMatches(source).length,
          2);
    });
  });
}
