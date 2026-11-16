import 'dart:async';
import 'dart:io';

import 'tunnel_health.dart';

/// Есть ли у машины интернет МИМО туннеля.
///
/// ## Зачем
///
/// Сторож канала видит одно: через туннель трафик не идёт. Причин две, и
/// лечатся они противоположно. Умер сервер — надо переподключаться, может
/// помочь другой сервер. Пропал сам интернет (кабель, роутер, мобильная сеть)
/// — переподключение бесполезно: оно рвёт то, что ещё держится, гоняет ядро
/// впустую и шлёт человеку «Связь оборвалась, восстанавливаю», когда
/// восстанавливать нечего. Владелец 13.10.2026: при выдернутом из роутера
/// кабеле трей не покраснел, а приложение молча крутило попытки.
///
/// Эта проба отвечает на вопрос «жив ли интернет вообще», и только в момент,
/// когда канал уже признан мёртвым.
///
/// ## Как запрос обходит туннель
///
/// - Windows, системный прокси: `HttpClient` настройки WinINET не читает,
///   `DIRECT` идёт мимо прокси сам.
/// - Windows, TUN: пакеты приложения заходят в адаптер, но правило
///   «процессы SilentGate → direct» выводит их наружу через ядро TUN. Kill
///   switch свой исполняемый файл пропускает (`wfp_rules.dart`, «свой …»).
///   Имена в этом режиме резолвит туннельный DNS, он вместе с каналом мёртв,
///   поэтому среди мишеней есть адреса без имени.
/// - Android: пакет приложения исключён из `VpnService`, сокет идёт в
///   обычную сеть. Исключение — блокировка без VPN (lockdown): она режет и
///   исключённые приложения, поэтому Android-движок в этом режиме пробу не
///   зовёт вовсе (ответ «не знаю»).
class DirectInternetProbe {
  DirectInternetProbe({
    this.timeout = const Duration(seconds: 4),
    this.targets = const [
      // По адресу — работают и тогда, когда туннельный DNS мёртв (TUN).
      'http://1.1.1.1/generate_204',
      'http://1.0.0.1/generate_204',
      // По имени — на случай, когда у провайдера закрыт Cloudflare.
      'http://connectivitycheck.gstatic.com/generate_204',
      'http://www.msftconnecttest.com/connecttest.txt',
      // ⚠️ И ОТЕЧЕСТВЕННЫЙ АДРЕС. В режиме белых списков мобильный оператор
      // пускает только разрешённые сайты: зарубежные мишени молчат, хотя
      // интернет есть. Ответ «интернета нет» там был бы ложью и остановил бы
      // переподключения — а сервер на разрешённом адресе может и подняться.
      'http://ya.ru/',
    ],
  });

  final Duration timeout;
  final List<String> targets;

  /// `true` — хоть одна мишень ответила напрямую.
  Future<bool> check() async =>
      await TunnelHealth.firstSuccess(targets, _get) != null;

  Future<bool> _get(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = timeout
        ..findProxy = ((_) => 'DIRECT')
        ..userAgent = null;
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      req.followRedirects = false;
      final res = await req.close().timeout(timeout);
      await res.drain<void>().timeout(timeout);
      // Любой ответ сервера — это уже интернет: важен факт, а не код.
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }
}
