import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/android/android_engine.dart';

/// МОЛЧАЩИЙ ГЛАВНЫЙ ПОТОК ANDROID НЕ ИМЕЕТ ПРАВА ОСТАНАВЛИВАТЬ ПРИЛОЖЕНИЕ.
///
/// ⚠️ ЧТО ЗДЕСЬ СТЕРЕЖЁТСЯ. Обработчики каналов `lol.silentgate/vpn` и
/// `lol.silentgate/device` исполняются на ГЛАВНОМ потоке Android. Пока он
/// занят — а до 1.5.1 он был занят подъёмом обоих ядер прямо в
/// `onStartCommand` — ответа не будет, и `await` без срока висит ровно столько
/// же. Цена у каждого места своя, и обе — «приложение зависло»:
///
///  * `AppState.init()` ПЕРВОЙ строкой ждёт `adoptRunningTunnel()`. Не ответил
///    канал — запуск приложения не сдвинулся ни на шаг, и в журнале при этом НИ
///    ОДНОЙ строки. Ровно так выглядел отчёт владельца 15.08.2026: сорок две
///    минуты пустоты при живом процессе;
///  * `_waitTunnelUp` обещает потолок 25 с, но сверяется с ним МЕЖДУ опросами —
///    а зависает ВНУТРИ опроса. Обещание не выполнялось ровно в том случае,
///    ради которого написано;
///  * `directDns` зовётся дважды за подъём. Зависший там `await` оставляет
///    состояние «Подключение…» навсегда, с заблокированным kill switch
///    трафиком.
///
/// Нативной стороны в тесте нет: канал подменён обработчиком, который НИКОГДА
/// не отвечает — это и есть занятый главный поток.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vpn = MethodChannel('lol.silentgate/vpn');
  const events = EventChannel('lol.silentgate/vpn_events');
  const device = MethodChannel('lol.silentgate/device');

  late Directory tmp;
  final never = Completer<Object?>();

  void mockSilent() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(vpn, (_) => never.future)
      ..setMockMethodCallHandler(device, (_) => never.future)
      ..setMockMethodCallHandler(
          MethodChannel(events.name), (_) async => null);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sg_chan_timeout_');
    AppPaths.overrideRoot(tmp);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(vpn, null)
      ..setMockMethodCallHandler(device, null)
      ..setMockMethodCallHandler(MethodChannel(events.name), null);
    // Журнал пишется фоновой цепочкой — дать ей закончиться ДО возврата
    // каталога данных к боевому.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('⚠️ ГЛАВНОЕ: adoptRunningTunnel возвращается, даже если канал молчит',
      () async {
    mockSilent();
    final engine = AndroidEngine()..channelTimeout = const Duration(milliseconds: 80);

    final before = AppLog.entries.length;
    // Без срока этот `await` не завершился бы НИКОГДА — а это первая строка
    // `AppState.init()`, то есть весь запуск приложения.
    await engine
        .adoptRunningTunnel()
        .timeout(const Duration(seconds: 5), onTimeout: () {
      fail('adoptRunningTunnel завис — запуск приложения остановлен');
    });

    expect(engine.status.isConnected, isFalse,
        reason: '«не ответили» — это «не знаю», а не «туннель поднят»');

    // ⚠️ И об этом ОБЯЗАНА быть строка. Молчаливое «не знаю» вернуло бы нас
    // ровно туда, откуда пришли: отчёт без ответа на главный вопрос.
    final written = AppLog.entries.skip(before).map((e) => e.message).toList();
    expect(written.any((m) => m.contains('Главный поток Android не ответил')),
        isTrue,
        reason: 'иначе в отчёте снова будет пустота вместо улики');
  });

  test('directDns при молчащем канале не подвешивает подключение', () async {
    mockSilent();
    final engine = AndroidEngine()..channelTimeout = const Duration(milliseconds: 80);

    // `startFallbackDns` первым делом спрашивает резолвер физической сети.
    // Ответа нет — обязан вернуться с честным «не подняли», а не ждать вечно.
    final port = await engine
        .startFallbackDns(_dnsAllSettings, viaXray: true, gen: 1,
            aborted: () => false)
        .timeout(const Duration(seconds: 5), onTimeout: () {
      fail('startFallbackDns завис на вопросе к главному потоку');
    });
    expect(port, 0);
  });

  test('ответ пришёл — обычный путь не сломан', () async {
    // Иначе «починка» свелась бы к тому, что нативную сторону перестали
    // слушать вовсе.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(vpn, (call) async {
        if (call.method == 'isRunning') return true;
        return null;
      })
      ..setMockMethodCallHandler(
          MethodChannel(events.name), (_) async => null);

    final engine = AndroidEngine();
    await engine.adoptRunningTunnel();
    expect(engine.status.isConnected, isTrue,
        reason: 'живой туннель прошлого запуска обязан подхватываться');
    await engine.cleanup();
  });
}

/// «Весь DNS через туннель» — только при нём и поднимается запасной форвардер,
/// а вместе с ним и вопрос о резолвере физической сети.
const _dnsAllSettings = AppSettings(tunnelDnsForAll: true);
