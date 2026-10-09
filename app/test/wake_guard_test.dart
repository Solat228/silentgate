import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/wake_guard.dart';

/// Удержание процессора на время пинга и замера скорости (Android): без него
/// при погасшем экране пробы истекают, и живые серверы метятся мёртвыми.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lol.silentgate/device');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    WakeGuard.resetForTests();
    WakeGuard.debugEnabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
  });

  tearDown(() {
    WakeGuard.debugEnabled = null;
    WakeGuard.resetForTests();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('одно удержание: hold, затем release', () async {
    final h = WakeGuard.acquire('пинг');
    await flush();
    expect(calls, ['wakeHold']);
    h.release();
    await flush();
    expect(calls, ['wakeHold', 'wakeRelease']);
    expect(WakeGuard.holders, 0);
  });

  test('⚠️ пинг и замер внахлёст: замок снимается после последнего', () async {
    final ping = WakeGuard.acquire('пинг');
    final speed = WakeGuard.acquire('замер скорости');
    ping.release();
    await flush();
    expect(calls, ['wakeHold'], reason: 'замер ещё идёт');
    speed.release();
    await flush();
    expect(calls, ['wakeHold', 'wakeRelease']);
  });

  test('повторный release не уводит счётчик в минус', () async {
    final a = WakeGuard.acquire('a');
    a.release();
    a.release();
    final b = WakeGuard.acquire('b');
    await flush();
    expect(WakeGuard.holders, 1);
    expect(calls, ['wakeHold', 'wakeRelease', 'wakeHold']);
    b.release();
  });

  test('ошибка канала не роняет вызывающего', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'x');
    });
    final h = WakeGuard.acquire('пинг');
    await flush();
    h.release();
    await flush();
    expect(WakeGuard.holders, 0);
  });

  test('не Android — канал не трогается', () async {
    WakeGuard.debugEnabled = false;
    WakeGuard.acquire('пинг').release();
    await flush();
    expect(calls, isEmpty);
  });

  test('проводка: разрешение, Kotlin и оба прогона', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.WAKE_LOCK'));
    final kt = File(
            'android/app/src/main/kotlin/lol/silentgate/platform/PlatformChannels.kt')
        .readAsStringSync();
    expect(kt, contains('"wakeHold"'));
    expect(kt, contains('"wakeRelease"'));
    expect(kt, contains('PARTIAL_WAKE_LOCK'));
    expect(kt, contains('setReferenceCounted(false)'));
    // Замок без таймаута посадил бы батарею при зависшем прогоне.
    expect(kt, contains('acquire(WAKE_TIMEOUT_MS)'));
    final probe = File('lib/state/probe_controller.dart').readAsStringSync();
    expect(RegExp(r"WakeGuard\.acquire\('пинг'\)").hasMatch(probe), isTrue);
    expect(RegExp(r"WakeGuard\.acquire\('замер скорости'\)").hasMatch(probe),
        isTrue);
    expect('wake.release()'.allMatches(probe).length, 2);
  });
}
