import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/probe/tunnel_health.dart';
import 'package:silentgate/engine/engine_base.dart';

/// Сторож признал канал мёртвым, а разбор причины (ещё две пробы) показал,
/// что ответило ВСЁ. Аудит 25.10.2026, G: раньше канал рвался и в этом
/// случае, и счётчик переподключений рос впустую.
class _Health extends TunnelHealth {
  _Health(this.diagByIp, this.diagByName)
      : super(
          proxyPort: 1,
          interval: const Duration(milliseconds: 5),
          failuresToDeclareDown: 1,
        );

  final bool diagByIp;
  final bool diagByName;
  int calls = 0;

  @override
  Future<bool> probeOnce() async {
    calls++;
    // 1 — промах (канал «умер»), 2 — подтверждающая проба тоже промах,
    // 3 — проба разбора причины.
    if (calls <= 2) return false;
    if (calls == 3) return diagByIp;
    return true;
  }

  @override
  Future<bool> nameResolutionWorks() async => diagByName;
}

class _Engine extends VpnEngineBase {
  _Engine(this.make);
  final TunnelHealth Function() make;
  final made = <TunnelHealth>[];
  int teardowns = 0;

  @override
  Future<bool?> directInternetAvailable() async => true;

  @override
  TunnelHealth createHealthProbe({
    required int proxyPort,
    required String proxyUser,
    required String proxyPassword,
  }) {
    final h = made.isEmpty ? make() : _Alive();
    made.add(h);
    return h;
  }

  @override
  Future<void> startSession() async {}

  @override
  Future<void> teardownCore({bool keepCapture = false}) async => teardowns++;

  @override
  Future<void> platformCleanup() async {}
}

class _Alive extends TunnelHealth {
  _Alive()
      : super(
          proxyPort: 2,
          interval: const Duration(seconds: 30),
          failuresToDeclareDown: 1,
        );
  @override
  Future<bool> probeOnce() async => true;
}

Future<_Engine> _run(bool byIp, bool byName) async {
  final e = _Engine(() => _Health(byIp, byName));
  addTearDown(e.stopHealthWatch);
  e.setStatus(VpnConnectionState.connected);
  e.startHealthWatch(() => false);
  for (var i = 0; i < 50 && e.made.length < 2 && e.teardowns == 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return e;
}

void main() {
  test('на повторе ответило всё — канал не рвём, сторож встаёт заново',
      () async {
    final e = await _run(true, true);
    expect(e.teardowns, 0, reason: 'исправный канал порван впустую');
    expect(e.made, hasLength(2), reason: 'сторож обязан встать заново');
    expect(e.status.isConnected, isTrue);
  });

  test('транспорт мёртв — переподключение, как и раньше', () async {
    final e = await _run(false, false);
    expect(e.teardowns, 1);
  });

  test('сломан только DNS в туннеле — переподключение', () async {
    final e = await _run(true, false);
    expect(e.teardowns, 1);
  });
}
