import '../../l10n/gen/app_localizations.dart';
import '../models/subscription_sync.dart';
import '../models/vpn_server.dart';
import '../models/vpn_status.dart';
import '../net/speed_test.dart';
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

/// Человекочитаемое имя поля сервера — для значка «обновлён» на карточке
/// (`ServerTile`, значок берёт список полей из `AppState.updatedFieldsOf`).
///
/// ⚠️ ТОЛЬКО ТЕ ПОЛЯ, У КОТОРЫХ ЕСТЬ ПОНЯТНОЕ ЧЕЛОВЕКУ НАЗВАНИЕ. Список сырых
/// имён общий с [SubscriptionSyncResult.changedFields] — это ЕДИНСТВЕННЫЙ
/// источник того, что вообще могло измениться, второй список заводить нельзя
/// (расхождение снова спрячет часть полей, как это уже было с журналом).
/// Для полей без интуитивного смысла конечному пользователю (`alterId`,
/// `flow`, `headerType`, `authority`, `xhttpMode`, `xPadding`, `spiderX`,
/// `allowInsecure`) возвращается сырое имя как есть: придуманный перевод хуже
/// технического названия, а показывать что-то надо — эти поля тоже входят в
/// список изменившихся.
String serverFieldLabel(AppLocalizations l, String field) {
  switch (field) {
    case 'address':
      return l.srvInfoParamAddress;
    case 'network':
      return l.srvInfoParamTransport;
    case 'fingerprint':
      return l.srvInfoParamTlsFingerprint;
    case 'id':
      return l.srvFieldId;
    case 'encryption':
      return l.srvFieldEncryption;
    case 'security':
      return l.srvFieldSecurity;
    case 'sni':
      return l.srvFieldSni;
    case 'host':
      return l.srvFieldHost;
    case 'path':
      return l.srvFieldPath;
    case 'publicKey':
      return l.srvFieldPublicKey;
    case 'shortId':
      return l.srvFieldShortId;
    case 'alpn':
      return l.srvFieldAlpn;
    case 'obfs':
      return l.srvFieldObfs;
    case 'obfsPassword':
      return l.srvFieldObfsPassword;
    case 'hopPorts':
      return l.srvFieldHopPorts;
    default:
      return field;
  }
}

/// Подсказка к значку «обновлён»: что именно изменилось при последней
/// синхронизации подписки. Пустой [fields] — сменилась только запись ссылки
/// (см. [ServerKeyChange.fields]), сами поля совпали.
String updatedServerTooltip(AppLocalizations l, List<String> fields) {
  if (fields.isEmpty) return l.srvTileUpdatedGeneric;
  return l.srvTileUpdatedFields(
      fields.map((f) => serverFieldLabel(l, f)).join(', '));
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
      AppErrorCode.serverUnsupported => l.errServerUnsupported,
    };

/// Текст «!»-подсказки у сервера, который клиент не умеет поднять
/// ([VpnServer.isUnsupported]). Код причины хранится в модели
/// машиночитаемым (не переводится) — единственное место перевода здесь.
String unsupportedServerNote(AppLocalizations l, VpnServer s) {
  final reason = s.unsupportedReason ?? '';
  if (reason.startsWith('hy2_mask:')) {
    return l.serverUnsupportedHy2Mask(reason.substring('hy2_mask:'.length));
  }
  return l.serverUnsupportedGeneric;
}

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
