import '../../core/models/vpn_status.dart';
import '../../l10n/gen/app_localizations.dart';

/// Текст статуса подключения на языке интерфейса (ANDROID.md п.19а).
///
/// Есть код ([VpnStatus.text]) — переводим его; нет — показываем
/// [VpnStatus.message] как есть: это сырой вывод ядра или исключение, и
/// переводить там нечего.
String? statusLine(AppLocalizations l, VpnStatus s) {
  final t = s.text;
  return t == null ? s.message : statusTextL10n(l, t);
}

String statusTextL10n(AppLocalizations l, StatusText t) => switch (t) {
      StatusReconnectBlocked(seconds: final sec, attempt: final a) =>
        l.statusReconnectBlocked(sec, a),
      StatusReconnectUnprotected(seconds: final sec, attempt: final a) =>
        l.statusReconnectUnprotected(sec, a),
      StatusTrafficNotFlowing() => l.statusTrafficNotFlowing,
      StatusNoInternet() => l.statusNoInternet,
      StatusVpnConsentDenied() => l.statusVpnConsentDenied,
      StatusMissingCore(file: final f) => l.statusMissingCore(f),
      StatusPortConflict(port: final p, holder: final h, ownCore: final own) =>
        h == null
            ? l.statusPortUnknown(p)
            : own
                ? l.statusPortOwnCore(p, h)
                : l.statusPortHolder(p, h),
      StatusTunCoreHung() => l.statusTunCoreHung,
      StatusNetworkChanged() => l.statusNetworkChanged,
      StatusRecoveryError() => l.statusRecoveryError,
      StatusGeoUnavailable() => l.statusGeoUnavailable,
      StatusNetworkBackChannelDead() => l.statusNetworkBackChannelDead,
      StatusConnectFailed(detail: final d) => l.statusConnectFailed(d),
      StatusCoreStopped(core: final c, code: final code, reason: final r) =>
        r == null
            ? l.statusCoreStopped(c, code)
            : l.statusCoreStoppedReason(c, code, _reason(l, r)),
    };

String _reason(AppLocalizations l, CoreStopReason r) => switch (r) {
      CoreStopPortBusy(port: final p) =>
        p == null ? l.statusReasonPortBusyAny : l.statusReasonPortBusy(p),
      CoreStopFailedToStart() => l.statusReasonFailedToStart,
      CoreStopRaw(line: final line) => line,
    };
