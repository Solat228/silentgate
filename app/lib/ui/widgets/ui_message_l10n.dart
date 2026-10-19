import 'package:flutter/widgets.dart';

import '../../app_nav.dart';
import '../../core/models/engine_notice.dart';
import '../../core/models/ui_message.dart';
import '../../core/net/network_error_hint.dart';
import '../../l10n/gen/app_localizations.dart';
import 'status_text_l10n.dart';

/// Текст [UiMessage] на языке интерфейса (MS1 S13).
String uiMessageL10n(AppLocalizations l, UiMessage m) => switch (m) {
      UiPingDone(
        verified: final v,
        cancelled: final c,
        ok: final ok,
        total: final t,
        seconds: final s
      ) =>
        c
            ? (v ? l.pingCancelledWorking(ok, t) : l.pingCancelledReachable(ok, t))
            : (v ? l.pingDoneWorking(ok, t, s) : l.pingDoneReachable(ok, t, s)),
      UiPingFailed() => l.pingFailed,
      UiSpeedDone(cancelled: final c, ok: final ok, total: final t, seconds: final s) =>
        c ? l.speedCancelled(ok, t) : l.speedDone(ok, t, s),
      UiSpeedNeedsLive() => l.speedNeedsLive,
      UiAutoConfigDone(found: final n) =>
        n > 0 ? l.autoConfigDoneFound(n) : l.autoConfigDoneNone,
      UiAutoConfigUnsupported(long: final long) =>
        long ? l.autoConfigUnsupportedLong : l.autoConfigUnsupportedShort,
      UiAutoConfigBadKey() => l.autoConfigBadKey,
      UiAutoConfigNoneFound() => l.autoConfigNoneFound,
      UiAutoConfigError(detail: final d) => l.autoConfigError(d),
      UiRestartServerChanged() => l.restartServerChanged,
      UiRestartSubscriptionSwitched() => l.restartSubscriptionSwitched,
      UiServerNotFound(name: final n) => l.errorServerNotFound(n),
      UiNetworkHint(kind: final k) => networkHintL10n(l, k),
      UiSubDeviceLimit(limit: final lim) =>
        lim == null || lim.isEmpty ? l.subDeviceLimitAny : l.subDeviceLimit(lim),
      UiSubHwidRequired() => l.subHwidRequired,
      UiSubHttpCode(code: final c) => l.subHttpCode(c),
      UiSubNoServers() => l.subNoServers,
      UiSubTooManyRedirects() => l.subTooManyRedirects,
    };

/// Подсказка к узнанной сетевой ошибке.
String networkHintL10n(AppLocalizations l, NetworkErrorKind k) => switch (k) {
      NetworkErrorKind.clockBehind => l.hintClockBehind,
      NetworkErrorKind.certExpired => l.hintCertExpired,
      NetworkErrorKind.hostnameMismatch => l.hintHostnameMismatch,
      NetworkErrorKind.noNetwork => l.hintNoNetwork,
    };

/// Заголовок и пояснение заметки движка на языке интерфейса.
///
/// ⚠️ [EngineNotice.text] и [EngineNotice.detail] — русские, для журнала.
/// Причину без кода ([EngineNotice.reason] == null) показываем сырой строкой
/// только при русском интерфейсе: в других языках русская фраза посреди
/// перевода — ровно то, что чинит MS1 S13. Такая причина — сырой текст ядра
/// или исключения; он остаётся в журнале и отчёте поддержки.
({String title, String? detail}) engineNoticeL10n(
    AppLocalizations l, EngineNotice n) {
  final ru = l.localeName.startsWith('ru');
  final rawDetail = (n.detail ?? '').trim();
  final reason = n.reason != null
      ? statusTextL10n(l, n.reason!)
      : (ru && rawDetail.isNotEmpty ? rawDetail : null);
  return switch (n.kind) {
    EngineNoticeKind.reconnecting => (title: l.noticeReconnecting, detail: reason),
    EngineNoticeKind.recovered => (title: l.noticeRecovered, detail: null),
    EngineNoticeKind.failed => (
        title: n.stillTrying ? l.noticeStillDown : l.noticeRecoverFailed,
        detail: n.attempts == null
            ? reason
            : n.reason != null
                ? l.noticeAttempts(n.attempts!, reason!)
                : l.noticeAttemptsOnly(n.attempts!),
      ),
    EngineNoticeKind.blocked => (title: l.noticeBlocked, detail: n.subject),
    EngineNoticeKind.geoAssetsMissing => (title: l.noticeGeoMissing, detail: null),
    EngineNoticeKind.geoAssetsUnusable => (title: l.noticeGeoUnusable, detail: null),
    EngineNoticeKind.staleScheduledTask => (title: l.tunAutoFixNoticeText, detail: null),
    EngineNoticeKind.systemProxyFailed => (
        title: l.noticeSystemProxyFailed,
        detail: l.noticeSystemProxyFailedDetail,
      ),
    EngineNoticeKind.exitDown => (
        title: l.noticeExitDown(n.subject ?? ''),
        detail: n.switched ? l.noticeExitDownSwitched : l.noticeExitDownStopped,
      ),
    EngineNoticeKind.noInternet => (
        title: l.noticeNoInternet,
        detail: l.noticeNoInternetDetail,
      ),
    EngineNoticeKind.internetRestored => (
        title: l.noticeInternetRestored,
        detail: null,
      ),
    // Эти два вида показываются своими ветками; запасной текст на случай,
    // если ветку уберут.
    EngineNoticeKind.deadAppRule => (title: n.text, detail: null),
    EngineNoticeKind.geoAssetsBundled => (title: n.text, detail: null),
  };
}

/// Заметка движка для системного уведомления — на языке интерфейса.
///
/// Контекст берётся из навигатора приложения: состояние, которое шлёт
/// уведомление, живёт вне дерева виджетов. Окна ещё нет — `null`, и
/// вызывающий покажет русский текст движка.
({String title, String body})? systemNoticeL10n(EngineNotice n) {
  // ⚠️ `currentContext` бросает, пока привязка виджетов не поднята (ранний
  // старт, юнит-тесты без дерева) — та же ловушка, что в `TrayWindow._ctx`.
  BuildContext? ctx;
  try {
    ctx = navigatorKey.currentContext;
  } catch (_) {
    return null;
  }
  if (ctx == null) return null;
  final l = Localizations.of<AppLocalizations>(ctx, AppLocalizations);
  if (l == null) return null;
  final t = engineNoticeL10n(l, n);
  return (title: t.title, body: t.detail ?? 'SilentGate');
}
