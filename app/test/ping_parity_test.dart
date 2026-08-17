import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/probe/ping_result.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/state/probe_controller.dart';

/// ОДНА КОЛОНКА — ОДНА ВЕЛИЧИНА.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ (п.8 владельца: «перепроверь, что подобные
/// оптимизации используются и для обычного пинга»). Сверка обычного пинга с
/// перестроенной автонастройкой вскрыла расхождение, которое видно только при
/// сравнении ДВУХ платформ.
///
/// Там, где замер делает сама платформа (Android: `LibXray.ping` поднимает ядро
/// внутри вызова и возвращает готовые миллисекунды), в `latencyMs` безусловно
/// клали RTT прокси-запроса — затирая уже намеренный TCP, — а в `latencyMethod`
/// при этом клали `settings.pingPrimary`, который по умолчанию `tcp`. То есть
/// плашка подписывалась «TCP», показывая величину другой природы.
///
/// Симптом: один и тот же сервер одной подписки показывает на Windows 45 мс, а
/// на телефоне 380 — и обе цифры подписаны одинаково. По этой колонке человек
/// выбирает сервер, то есть выбирает по неправде.
///
/// Правило, общее с автонастройкой: **показываем TCP или НИЧЕГО**; прокси-RTT
/// живёт в отдельном поле `proxyRttMs` и в колонку задержки не подставляется.
class _SelfMeasuringHarness implements ProbeHarness {
  _SelfMeasuringHarness(this.rtt);

  /// Что «намерила» платформа. Именно это значение раньше уезжало в колонку
  /// задержки, вытесняя намеренный TCP.
  final int rtt;

  /// Порта наружу нет — ровно как на Android: послать свой запрос некуда,
  /// доступна только готовая цифра от платформы.
  @override
  bool get supportsProxyRequests => false;

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async =>
      _SelfMeasuringHandle(rtt);
}

class _SelfMeasuringHandle implements HarnessHandle {
  _SelfMeasuringHandle(this.rtt);
  final int rtt;

  @override
  String get proxyUser => '';
  @override
  String get proxyPassword => '';
  @override
  int proxyPortFor(int index) => -1;
  @override
  Future<int?> delayMs(int index) async => rtt;
  @override
  Future<void> stop() async {}
}

void main() {
  late Directory tmp;

  /// ⚠️ НАСТОЯЩИЙ слушающий сокет на loopback, а не выдуманный адрес.
  /// Фаза 1 обычного пинга — это TCP-коннект, и сервер, не ответивший на него,
  /// до фазы 2 не доходит вовсе (это правильно и проверяется отдельно ниже).
  /// Чтобы добраться до ветки «замер сделала платформа», TCP обязан пройти.
  /// Наружу тест при этом не ходит: всё на 127.0.0.1.
  late ServerSocket listener;

  setUp(() async {
    // Пинг пишет результаты на диск. Боевой %APPDATA% тесты не трогают никогда —
    // предохранитель живёт в AppPaths, обходить его нельзя.
    tmp = Directory.systemTemp.createTempSync('sg_ping_parity_');
    AppPaths.overrideRoot(tmp);
    listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    listener.listen((s) => s.destroy());
  });

  tearDown(() async {
    await listener.close();
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  VpnServer alive() => ShareLinkParser.tryParse(
      'vless://00000000-0000-0000-0000-000000000000@127.0.0.1:${listener.port}'
      '?type=tcp&security=none#alive')!;

  /// Порт 9 (discard) на loopback закрыт — TCP до него не пройдёт.
  VpnServer dead() => ShareLinkParser.tryParse(
      'vless://00000000-0000-0000-0000-000000000000@127.0.0.1:9'
      '?type=tcp&security=none#dead')!;

  const settings = AppSettings(pingTimeoutMs: 700, pingConcurrency: 4);

  group('Замер платформы не вытесняет TCP из колонки задержки', () {
    test('⚠️ ГЛАВНОЕ: в колонке остаётся TCP, а не RTT прокси', () async {
      // 380 — заведомо больше любого loopback-коннекта, поэтому подмену видно
      // без сравнения с точным числом.
      final ctrl =
          ProbeController(harnessFactory: () => _SelfMeasuringHarness(380));
      await ctrl.pingAll([alive()], settings);

      final r = ctrl.resultFor(alive());
      expect(r.latencyMs, isNotNull);
      expect(r.latencyMs, lessThan(380),
          reason: 'ЗДЕСЬ БЫЛА ПОДМЕНА: latencyMs безусловно перезаписывался '
              'значением от платформы, и Windows против телефона показывали '
              'разные цифры под одной и той же подписью');
      expect(r.latencyMethod, PingMethod.tcp,
          reason: 'подпись обязана совпадать с тем, что реально в колонке');
    });

    test('прокси-RTT не теряется — он уходит в своё поле', () async {
      final ctrl =
          ProbeController(harnessFactory: () => _SelfMeasuringHarness(380));
      await ctrl.pingAll([alive()], settings);
      expect(ctrl.resultFor(alive()).proxyRttMs, 380,
          reason: 'величина полезная, её место — proxyRttMs, а не колонка');
    });

    test('⚠️ проверка через сервер РЕАЛЬНО была — вердикт заслуженный', () async {
      // Отличать от простого TCP-ответа: там порт лишь открылся и ничего не
      // проксировал. Здесь ядро поднималось внутри платформенного вызова.
      final ctrl =
          ProbeController(harnessFactory: () => _SelfMeasuringHarness(120));
      await ctrl.pingAll([alive()], settings);
      final r = ctrl.resultFor(alive());
      expect(r.reachableViaProxy, isTrue);
      expect(r.outcome, PingOutcome.ok);
    });
  });

  group('Порядок фаз тот же, что у перестроенной автонастройки', () {
    test('⚠️ молчащий по TCP до дорогой фазы не доходит', () async {
      // Дешёвое раньше дорогого — тот же принцип, ради которого перестроена
      // автонастройка. Признак: платформенный замер к мёртвому не применился,
      // и его RTT в результат не попал.
      final ctrl =
          ProbeController(harnessFactory: () => _SelfMeasuringHarness(999));
      await ctrl.pingAll([dead()], settings);
      final r = ctrl.resultFor(dead());
      expect(r.outcome, isNot(PingOutcome.ok));
      expect(r.proxyRttMs, isNull,
          reason: 'иначе фаза 2 отработала бы по заведомо мёртвому серверу');
    });

    test('прогон заканчивается и досчитывает прогресс', () async {
      final ctrl =
          ProbeController(harnessFactory: () => _SelfMeasuringHarness(60));
      await ctrl.pingAll([alive(), dead()], settings);
      expect(ctrl.running, isFalse);
      expect(ctrl.done, ctrl.total,
          reason: 'иначе полоска висит недосчитанной до конца прогона');
    });
  });
}
