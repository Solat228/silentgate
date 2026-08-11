import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_env.dart';
import 'app_log.dart';

/// Single-instance через локальный сокет. Первый экземпляр слушает порт на 127.0.0.1;
/// последующие (например, запущенные браузером по deep link) пересылают ему URL и завершаются.
class SingleInstance {
  static const int _basePort = 47654;

  /// Изолированная копия (SILENTGATE_PORT_OFFSET) слушает свой порт и не конфликтует
  /// с установленной версией.
  static int get _port => _basePort + AppEnv.portOffset;

  /// Пытается стать первичным экземпляром: вернёт сервер-сокет, либо null если уже запущен.
  static Future<ServerSocket?> tryBecomePrimary() async {
    try {
      return await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
    } catch (_) {
      return null;
    }
  }

  /// Разобрать сообщение сокета: `<токен>\n<ссылка>` либо просто `<ссылка>`.
  static ({String? token, String url}) splitMessage(String raw) {
    final i = raw.indexOf('\n');
    if (i < 0) return (token: null, url: raw.trim());
    return (token: raw.substring(0, i).trim(), url: raw.substring(i + 1).trim());
  }

  /// Требует ли эта ссылка токена.
  ///
  /// ⚠️ Управляющие команды — да, импорт — НЕТ. Импортную ссылку передаёт
  /// второй экземпляр приложения, запущенный человеком двойным кликом; требовать
  /// у него токен значило бы сломать штатный путь ради защиты от самого
  /// пользователя.
  static bool needsToken(String url) {
    final u = url.trim().toLowerCase();
    if (!u.startsWith('silentgate://')) return false;
    final rest = u.substring('silentgate://'.length);
    for (final a in ['connect', 'disconnect', 'toggle', 'update']) {
      if (rest == a || rest.startsWith('$a?') || rest.startsWith('$a/')) {
        return true;
      }
    }
    return false;
  }

  /// Первичный экземпляр: принимать входящие URL.
  ///
  /// [token] — токен API. Управляющие команды без него отбрасываются.
  static void listen(ServerSocket server, void Function(String url) onUrl,
      {required String Function() token}) {
    server.listen((socket) {
      final buf = <int>[];
      socket.listen(
        buf.addAll,
        onDone: () {
          final raw = utf8.decode(buf, allowMalformed: true).trim();
          socket.destroy();
          if (raw.isEmpty) return;
          final m = splitMessage(raw);
          if (needsToken(m.url)) {
            final want = token();
            if (want.isEmpty || m.token != want) {
              // ⚠️ Молчать нельзя: «команда отвергнута» и «команда выполнена»
              // снаружи неотличимы, и разбор жалобы начинался бы с нуля.
              AppLog.w('Команда через локальный сокет отвергнута: '
                  'неверный или отсутствующий токен');
              return;
            }
          }
          onUrl(m.url);
        },
        onError: (_) => socket.destroy(),
      );
    });
  }

  /// Вторичный экземпляр: переслать URL первичному.
  static Future<void> forward(String url) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(seconds: 2),
      );
      socket.add(utf8.encode(url));
      await socket.flush();
      await socket.close();
    } catch (_) {}
  }
}
