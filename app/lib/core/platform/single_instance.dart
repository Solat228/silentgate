import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../url_scheme.dart';
import 'app_env.dart';
import 'app_log.dart';

/// Сравнение токена в ПОСТОЯННОЕ время (без раннего выхода на первом
/// несовпадающем байте и без утечки через сравнение длин).
///
/// ⚠️ ДУБЛИКАТ `_constantTimeEquals` из `core/net/api_server.dart` — и это
/// осознанный выбор, не забывчивость. Та функция приватна (ведущее `_`) в
/// чужом файле, который параллельно правит другая задача; тащить её в общий
/// модуль означало бы редактировать активно меняющийся файл ради источника
/// правды у примитива, который в принципе не может разойтись в толковании —
/// в отличие от разбора `needsToken` выше (там «что считать командой» было
/// вопросом ИНТЕРПРЕТАЦИИ, и два разных ответа на него — баг; здесь же
/// «побайтовое сравнение без утечки по времени» имеет одно определение, и
/// вторая копия того же алгоритма ничем не хуже первой). Модель угрозы тоже
/// слабее, чем у HTTP-токена: это сырой TCP-порт без keep-alive, каждая
/// попытка — новое соединение, и точность измерения тайминга поверх этого
/// джиттера ниже, чем у постоянно живущего HTTP-сервера.
bool _constantTimeEquals(String a, String b) {
  final ab = utf8.encode(a);
  final bb = utf8.encode(b);
  final maxLen = ab.length > bb.length ? ab.length : bb.length;
  var diff = ab.length ^ bb.length;
  for (var i = 0; i < maxLen; i++) {
    final x = i < ab.length ? ab[i] : 0;
    final y = i < bb.length ? bb[i] : 0;
    diff |= x ^ y;
  }
  return diff == 0;
}

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
  ///
  /// ⚠️ РАУНД РЕВЬЮ 1: раньше здесь был СВОЙ разбор строки (`rest == a ||
  /// startsWith('$a?') || startsWith('$a/')`), отдельный от того, что реально
  /// исполняет команду — `AppUrlScheme.controlAction` (парсит через `Uri`,
  /// берёт `uri.host` с фолбэком на первый сегмент пути). Они расходились:
  /// `silentgate://connect#x` и `silentgate:///connect` свой разбор не узнавал
  /// (`needsToken` → false), а `controlAction` эти же строки распознавал как
  /// `connect` и исполнял БЕЗ токена. Урок общий: два разбора одной строки —
  /// это всегда дыра, разрешение и исполнение обязаны спрашивать один и тот же
  /// код. Поэтому здесь больше нет parsing-логики вообще.
  static bool needsToken(String url) => AppUrlScheme.controlAction(url) != null;

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
            if (want.isEmpty || !_constantTimeEquals(m.token ?? '', want)) {
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
