import '../../l10n/gen/app_localizations.dart';
import '../models/vpn_server.dart';
import '../models/vpn_status.dart';
import '../settings/split_tunnel.dart';
import '../xray/outbound_variant.dart';

/// Локализованные подписи enum-моделей. Сами модели держат русский фолбэк в
/// `.label` (для не-UI мест и диагностики); в интерфейсе используем эти хелперы
/// с `AppLocalizations`, чтобы подписи переводились.

String splitModeLabel(AppLocalizations l, SplitMode m) {
  switch (m) {
    case SplitMode.all:
      return l.enumSplitAll;
    case SplitMode.onlySelected:
      return l.enumSplitOnly;
    case SplitMode.exceptSelected:
      return l.enumSplitExcept;
  }
}

String appActionLabel(AppLocalizations l, AppAction a) {
  switch (a) {
    case AppAction.tunnel:
      return l.enumActionTunnel;
    case AppAction.direct:
      return l.enumActionDirect;
    case AppAction.block:
      return l.enumActionBlock;
  }
}

/// Подпись состояния подключения. Модель (`VpnStatus.label`) держит русский
/// фолбэк для логов и отчёта поддержки — в UI звать только это.
String vpnStatusLabel(AppLocalizations l, VpnConnectionState s) {
  switch (s) {
    case VpnConnectionState.disconnected:
      return l.enumStatusDisconnected;
    case VpnConnectionState.connecting:
      return l.enumStatusConnecting;
    case VpnConnectionState.connected:
      return l.enumStatusConnected;
    case VpnConnectionState.disconnecting:
      return l.enumStatusDisconnecting;
    case VpnConnectionState.error:
      return l.enumStatusError;
  }
}

/// Подпись вариации обхода: «обычный» переводится, `fragment`/`fp:chrome` —
/// технические имена, они одинаковы во всех языках.
String outboundVariantLabel(AppLocalizations l, OutboundVariant v) =>
    v.isNone ? l.enumVariantPlain : v.label;

/// Подписи тегов сервера: переводимые маркеры ([VpnServerTags]) заменяются на
/// локализованные, технические (VLESS/TCP/REALITY…) остаются как есть.
List<String> configTagLabels(AppLocalizations l, List<String> raw) => raw
    .map((t) => switch (t) {
          VpnServerTags.autoSelect => l.tagAutoSelect,
          VpnServerTags.panel => l.tagPanel,
          VpnServerTags.portHopping => l.tagPortHopping,
          _ => t,
        })
    .toList(growable: false);
