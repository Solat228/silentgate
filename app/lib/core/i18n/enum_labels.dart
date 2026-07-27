import '../../l10n/gen/app_localizations.dart';
import '../models/subscription_sync.dart';
import '../models/vpn_server.dart';
import '../models/vpn_status.dart';
import '../net/speed_test.dart';
import '../settings/app_settings.dart';
import '../settings/split_tunnel.dart';
import '../xray/outbound_variant.dart';
import '../../state/app_error.dart';

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

/// Сводка обновления подписки: «7 серверов · +2 · −1» либо «… · без изменений».
///
/// Плюрализация зависит от языка (в русском три формы, в арабском шесть),
/// поэтому строится здесь, а не в модели: `SubscriptionSyncResult.summary`
/// остаётся русским фолбэком для логов и отчёта поддержки.
String syncSummary(AppLocalizations l, SubscriptionSyncResult r) {
  final parts = <String>[l.syncServersCount(r.total)];
  if (r.added.isNotEmpty) parts.add('+${r.added.length}');
  if (r.removed.isNotEmpty) parts.add('−${r.removed.length}');
  if (!r.hasChanges) parts.add(l.syncNoChanges);
  return parts.join(' · ');
}

/// Подпись объёма спидтеста («20 МБ» / «5 МБ»).
String speedSizeLabel(AppLocalizations l, SpeedTestSize s) =>
    s == SpeedTestSize.full ? l.speedSizeFull : l.speedSizeLight;

/// Подпись результата замера скорости с локализованными единицами.
String speedResultLabel(AppLocalizations l, SpeedResult? r) {
  if (r == null || !r.ok) return '—';
  final mbs = r.bytesPerSecond / 1000000;
  if (mbs >= 1) return l.speedMbPerSec(mbs.toStringAsFixed(1));
  return l.speedKbPerSec((r.bytesPerSecond / 1000).toStringAsFixed(0));
}

/// Текст распознанной ошибки приложения.
String appErrorText(AppLocalizations l, AppErrorCode c) => switch (c) {
      AppErrorCode.invalidJson => l.errInvalidJson,
      AppErrorCode.pickServerFirst => l.errPickServerFirst,
      AppErrorCode.importSubscriptionFirst => l.errImportSubscriptionFirst,
    };

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
