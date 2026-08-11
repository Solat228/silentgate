import 'dart:async';
import 'dart:convert';
import 'dart:io';


/// Замечает, что трафик ушёл в блокировку по НАШЕМУ правилу, и называет домен.
///
/// ## Зачем это заменило страницу-заглушку
///
/// Заглушка подменяла ответ по plain http. До пользователя она почти никогда не
/// доходила: браузеры идут в `https` сразу, а HSTS переписывает адрес ДО
/// отправки запроса — человек видел `ERR_CONNECTION_RESET` и шёл искать
/// поломку. Подменить `https` без своего корневого сертификата невозможно, а
/// ставить такой сертификат нельзя: он даёт читать весь TLS пользователя.
///
/// Уведомление ничего не подменяет и работает на любом протоколе и порту.
/// Оно отвечает на единственный важный вопрос: «сайт сломался или это я его
/// закрыл?»
///
/// ## Откуда берутся события
///
/// Из Clash API ядра (`GET /connections`) — того же, из которого читаются
/// счётчики. Соединение, отправленное в `reject`, появляется там с нашим
/// blackhole-тегом в `chains`, а имя хоста — в `metadata`.
///
/// ⚠️ ЭТО НАБЛЮДЕНИЕ, А НЕ ПЕРЕХВАТ, И У НЕГО ЕСТЬ ПРЕДЕЛ. Снимок отдаёт
/// ЖИВЫЕ соединения; отвергнутое живёт мгновения, и между тактами опроса часть
/// попыток проходит незамеченной. Поэтому уведомление — подсказка, а не
/// счётчик: пропуск здесь не дефект, а свойство способа. Обещать «покажем
/// каждую попытку» нельзя.
class BlockNoticeWatcher {
  BlockNoticeWatcher({
    required this.apiPort,
    required this.secret,
    this.period = const Duration(seconds: 2),
    this.repeatAfter = const Duration(minutes: 5),
  });

  final int apiPort;
  final String secret;
  final Duration period;

  /// Как скоро можно повторить уведомление о ТОМ ЖЕ домене.
  ///
  /// ⚠️ Без этого одна открытая вкладка давала бы уведомление каждые две
  /// секунды: браузер переспрашивает сам. Повторяющееся сообщение перестают
  /// читать, и вместе с ним перестают читать все остальные.
  final Duration repeatAfter;

  /// Теги outbound-ов, означающих блокировку. Задаются нами же в построителе
  /// конфига — переименование там обязано отражаться здесь.
  static const blockTags = {'block', 'blocked', 'reject'};

  Timer? _timer;
  final _controller = StreamController<String>.broadcast();
  final _lastSeen = <String, DateTime>{};

  /// Домены, о которых стоит сообщать. Пусто — сторож молчит.
  Set<String> blocked = const {};

  /// Имена заблокированных доменов, замеченные в трафике.
  Stream<String> get events => _controller.stream;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(period, (_) => unawaited(_tick()));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _lastSeen.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  Future<void> _tick() async {
    if (blocked.isEmpty || _controller.isClosed) return;
    final conns = await _connections();
    if (conns == null) return;
    final now = DateTime.now();
    for (final host in _blockedHosts(conns, blocked)) {
      final seen = _lastSeen[host];
      if (seen != null && now.difference(seen) < repeatAfter) continue;
      _lastSeen[host] = now;
      if (!_controller.isClosed) _controller.add(host);
    }
  }

  /// Разбор снимка соединений. Вынесен отдельно и статичен — чтобы его можно
  /// было проверить тестом без сети и без ядра.
  ///
  /// Возвращает домены из [blocked], чей трафик ушёл в блокировку.
  static Set<String> blockedHostsIn(Object? raw, Set<String> blocked) =>
      _blockedHosts(raw is Map ? raw['connections'] : raw, blocked);

  static Set<String> _blockedHosts(Object? raw, Set<String> blocked) {
    if (raw is! List || blocked.isEmpty) return const {};
    final out = <String>{};
    for (final c in raw) {
      if (c is! Map) continue;
      final meta = c['metadata'];
      if (meta is! Map) continue;
      // `host` — имя из сниффинга; при соединении по адресу его может не быть.
      final host = (meta['host'] ?? '').toString().trim().toLowerCase();
      if (host.isEmpty) continue;
      // ⚠️ СОВПАДЕНИЯ ПО ИМЕНИ ДОСТАТОЧНО, ЦЕПОЧКУ НЕ ТРЕБУЕМ.
      //
      // Блокируем мы действием `reject` на ПРАВИЛЕ, а не отдельным
      // outbound-ом, поэтому в `chains` блок-тега может не оказаться вовсе:
      // ядру некуда его записать. Требовать тег значило бы не заметить ни
      // одной блокировки — то есть сделать уведомление, которое молчит всегда.
      // Ложные срабатывания при этом исключены по построению: правила «Блок»
      // стоят ВЫШЕ всех прочих, и раз хост есть в списке, его судьба решена.
      final match = matchBlocked(host, blocked);
      if (match != null) out.add(match);
    }
    return out;
  }

  /// Какое из правил закрыло этот хост. `null` — ни одно.
  ///
  /// ⚠️ Совпадение СУФФИКСНОЕ, как у самого ядра (`domain_suffix`): правило
  /// `example.com` закрывает и `cdn.example.com`. Сообщаем при этом ИМЯ
  /// ПРАВИЛА, а не хоста: человек ищет в списке то, что он туда вписывал.
  /// Показать `cdn.example.com` там, где в списке `example.com`, значит
  /// отправить его искать несуществующую строку.
  static String? matchBlocked(String host, Set<String> blocked) {
    final h = host.toLowerCase();
    String? best;
    for (final b in blocked) {
      final rule = b.toLowerCase().trim();
      if (rule.isEmpty) continue;
      if (h == rule || h.endsWith('.$rule')) {
        // Самое КОНКРЕТНОЕ правило: при `example.com` и `cdn.example.com`
        // в списке победить должно второе — оно и сработало в ядре первым.
        if (best == null || rule.length > best.length) best = rule;
      }
    }
    return best;
  }

  Future<Object?> _connections() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$apiPort/connections'));
      if (secret.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      }
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final j = jsonDecode(body);
      return j is Map ? j['connections'] : null;
    } catch (_) {
      // Ядро могло уйти между тактами — это штатно, молчим.
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
