import 'dart:async';

/// Шина входящих ссылок silentgate:// (из deep link'а браузера).
/// Первичный экземпляр приложения кладёт сюда полученные URL; [AppState] их слушает.
class IncomingLinks {
  static final StreamController<String> _controller =
      StreamController<String>.broadcast();

  static Stream<String> get stream => _controller.stream;

  static void add(String url) {
    if (url.trim().isNotEmpty) _controller.add(url.trim());
  }
}
