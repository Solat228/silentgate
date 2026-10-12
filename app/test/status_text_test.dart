import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/i18n/app_locales.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/l10n/gen/app_localizations.dart';
import 'package:silentgate/ui/widgets/status_text_l10n.dart';

/// Статус подключения на языке интерфейса (ANDROID.md п.19а): движок кладёт
/// код, UI переводит. Раньше в девяти языках из десяти человек видел русский
/// текст ровно в момент обрыва.
void main() {
  const samples = <StatusText>[
    StatusReconnectBlocked(seconds: 5, attempt: 3),
    StatusTrafficNotFlowing(),
    StatusVpnConsentDenied(),
    StatusMissingCore('xray.exe'),
    StatusPortConflict(port: 10808, holder: 'xray.exe', ownCore: true),
    StatusPortConflict(port: 10808),
    StatusPortConflict(port: 10808, holder: 'other.exe'),
    StatusTunCoreHung(),
    StatusConnectFailed('SocketException: refused'),
    StatusCoreStopped(core: 'Xray', code: 1),
    StatusCoreStopped(core: 'Xray', code: 1, reason: CoreStopPortBusy(10809)),
    StatusCoreStopped(core: 'Xray', code: 1, reason: CoreStopPortBusy(null)),
    StatusCoreStopped(core: 'sing-box', code: 2, reason: CoreStopFailedToStart()),
    StatusCoreStopped(core: 'Xray', code: 1, reason: CoreStopRaw('panic: x')),
  ];

  final cyrillic = RegExp('[А-Яа-яЁё]');

  for (final lang in supportedLanguages) {
    test('${lang.code}: каждый код даёт текст с параметрами', () async {
      final l = await AppLocalizations.delegate.load(Locale(lang.code));
      for (final t in samples) {
        final s = statusTextL10n(l, t);
        expect(s.trim(), isNotEmpty, reason: '$t');
        if (lang.code != 'ru') {
          expect(cyrillic.hasMatch(s), isFalse,
              reason: '${lang.code}: русский текст в «$s»');
        }
      }
      expect(statusTextL10n(l, samples.first), contains('5'));
      expect(statusTextL10n(l, samples.first), contains('3'));
      expect(statusTextL10n(l, samples[4]), contains('10808'));
      expect(statusTextL10n(l, samples[4]), contains('xray.exe'));
      expect(statusTextL10n(l, samples[10]), contains('10809'));
      // Сырые строки ядра и исключения не переводятся — уходят как есть.
      expect(statusTextL10n(l, samples[8]), contains('SocketException: refused'));
      expect(statusTextL10n(l, samples.last), contains('panic: x'));
    });
  }

  test('без кода — сырое сообщение, с кодом — перевод', () async {
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
        statusLine(
            l, const VpnStatus(VpnConnectionState.error, message: 'raw core')),
        'raw core');
    expect(
        statusLine(
            l,
            const VpnStatus(VpnConnectionState.error,
                message: 'Туннельное ядро зависло, туннель снят',
                text: StatusTunCoreHung())),
        l.statusTunCoreHung);
    expect(statusLine(l, const VpnStatus.disconnected()), isNull);
  });

  group('причина остановки ядра — один разбор на журнал и экран', () {
    test('порт занят', () {
      final r = VpnEngineBase.coreStopReasonFromTail(
          'listen tcp 127.0.0.1:10808: bind: address already in use');
      expect(r, isA<CoreStopPortBusy>());
      expect((r as CoreStopPortBusy).port, 10808);
      expect(VpnEngineBase.coreStopReasonRu(r), 'локальный порт 10808 уже занят');
    });
    test('не стартовало', () {
      final r = VpnEngineBase.coreStopReasonFromTail('Failed to start: x');
      expect(r, isA<CoreStopFailedToStart>());
      expect(VpnEngineBase.coreStopReasonRu(r), 'ядро не смогло запуститься');
    });
    test('прочее — первая строка, обрезанная', () {
      final r = VpnEngineBase.coreStopReasonFromTail('\n  ${'a' * 200}\nвторая');
      expect(r, isA<CoreStopRaw>());
      expect((r as CoreStopRaw).line.length, 161);
    });
    test('пусто — причины нет', () {
      expect(VpnEngineBase.coreStopReasonFromTail('  \n '), isNull);
      expect(VpnEngineBase.coreStopReasonRu(null), '');
    });
  });

  test('главный экран берёт текст через statusLine, а не message', () {
    final src = File('lib/ui/home_screen.dart').readAsStringSync();
    expect(src, contains('statusLine(l, status)'));
    expect(src, isNot(contains('status.message')));
  });

  test('движок кладёт код во все показываемые ошибки', () {
    final base = File('lib/engine/engine_base.dart').readAsStringSync();
    expect(base, contains('StatusReconnectBlocked('));
    expect(base, contains('StatusTrafficNotFlowing()'));
    expect(base, contains('StatusCoreStopped('));
    final win = File('lib/engine/windows/windows_engine.dart').readAsStringSync();
    for (final c in ['StatusMissingCore(', 'StatusPortConflict(', 'StatusConnectFailed(', 'StatusTunCoreHung()']) {
      expect(win, contains(c), reason: c);
    }
    final and = File('lib/engine/android/android_engine.dart').readAsStringSync();
    expect(and, contains('StatusVpnConsentDenied()'));
  });
}
