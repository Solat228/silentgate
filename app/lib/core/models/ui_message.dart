/// Сообщение для человека — код и параметры, а не готовая строка.
///
/// ⚠️ ЗАЧЕМ (MS1 S13, 19.10.2026). Итоги пинга и автонастройки, плашки
/// «переподключитесь», ошибки импорта подписки рождаются в `state/` и `core/`,
/// где языка интерфейса нет. Раньше они уходили на экран готовой русской
/// строкой, и человек с английским интерфейсом видел русский текст: это нашли
/// и проверяющие Google Play, и прогон для Microsoft Store.
///
/// Тот же приём, что [StatusText] для строки статуса: источник кладёт сюда, ЧТО
/// случилось, а текст подбирает интерфейс (`ui/widgets/ui_message_l10n.dart`).
/// Русская строка рядом остаётся — для журнала и отчёта поддержки, они
/// принципиально не переводятся.
library;

import '../net/network_error_hint.dart';

sealed class UiMessage {
  const UiMessage();
}

/// Пинг закончен или отменён.
final class UiPingDone extends UiMessage {
  /// `true` — проба через сервер реально была («рабочих»), иначе только TCP
  /// («доступных»).
  final bool verified;
  final bool cancelled;
  final int ok;
  final int total;
  final int seconds;
  const UiPingDone({
    required this.verified,
    required this.cancelled,
    required this.ok,
    required this.total,
    required this.seconds,
  });
}

/// Прогон пинга оборвался исключением.
final class UiPingFailed extends UiMessage {
  const UiPingFailed();
}

/// Замер скорости закончен или отменён.
final class UiSpeedDone extends UiMessage {
  final bool cancelled;
  final int ok;
  final int total;
  final int seconds;
  const UiSpeedDone({
    required this.cancelled,
    required this.ok,
    required this.total,
    required this.seconds,
  });
}

/// Скорость этого сервера мерится только через живое подключение к нему.
final class UiSpeedNeedsLive extends UiMessage {
  const UiSpeedNeedsLive();
}

/// Итог автонастройки: сколько рабочих серверов найдено (0 — ни одного).
final class UiAutoConfigDone extends UiMessage {
  final int found;
  const UiAutoConfigDone(this.found);
}

/// Автонастройка на этой платформе невозможна.
///
/// [long] — полный текст с пояснением (экран автонастройки), иначе короткий
/// итог для карточки.
final class UiAutoConfigUnsupported extends UiMessage {
  final bool long;
  const UiAutoConfigUnsupported({this.long = false});
}

/// Вставленный ключ не разобрался.
final class UiAutoConfigBadKey extends UiMessage {
  const UiAutoConfigBadKey();
}

/// Прогон дошёл до конца, рабочих серверов нет (строка ошибки на экране).
final class UiAutoConfigNoneFound extends UiMessage {
  const UiAutoConfigNoneFound();
}

/// Автонастройка упала исключением; [detail] — его текст (не переводится).
final class UiAutoConfigError extends UiMessage {
  final String detail;
  const UiAutoConfigError(this.detail);
}

/// Выбран другой сервер при живом VPN.
final class UiRestartServerChanged extends UiMessage {
  const UiRestartServerChanged();
}

/// Переключена подписка при живом VPN.
final class UiRestartSubscriptionSwitched extends UiMessage {
  const UiRestartSubscriptionSwitched();
}

/// Url-команда назвала сервер, которого нет.
final class UiServerNotFound extends UiMessage {
  final String name;
  const UiServerNotFound(this.name);
}

/// Узнанная сетевая ошибка при импорте подписки.
final class UiNetworkHint extends UiMessage {
  final NetworkErrorKind kind;
  const UiNetworkHint(this.kind);
}

/// Панель отказала: исчерпан лимит устройств. [limit] — из заголовка, может
/// отсутствовать.
final class UiSubDeviceLimit extends UiMessage {
  final String? limit;
  const UiSubDeviceLimit(this.limit);
}

/// Панель требует идентификатор устройства, а его не прислали.
final class UiSubHwidRequired extends UiMessage {
  const UiSubHwidRequired();
}

/// Сервер подписки ответил кодом ошибки.
final class UiSubHttpCode extends UiMessage {
  final int code;
  const UiSubHttpCode(this.code);
}

/// В ответе подписки нет ни одного сервера.
final class UiSubNoServers extends UiMessage {
  const UiSubNoServers();
}

/// Подписка увела в петлю редиректов.
final class UiSubTooManyRedirects extends UiMessage {
  const UiSubTooManyRedirects();
}
