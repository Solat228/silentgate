import 'dart:async';
import 'dart:io';

import 'app_log.dart';

/// Следит за сменой сетевого окружения: Wi-Fi ↔ кабель, выход из сна, смена IP,
/// подъём/падение адаптера.
///
/// **Почему так осторожно.** Наивная версия (отпечаток всех интерфейсов + исключение
/// своего адаптера ПО ИМЕНИ) давала самоподдерживающийся цикл: `NetworkInterface.list()`
/// на Windows возвращает не то имя, что показывает система, поэтому подъём собственного
/// TUN считался «сменой сети» → переподключение → туннель поднимался заново → снова
/// «смена сети». В логе это выглядело как ровный цикл раз в ~20 секунд, а трафик
/// пользователя всё это время падал в мёртвый прокси.
///
/// Поэтому здесь три независимых предохранителя:
///  1. в отпечаток идут только «настоящие» адреса — наши TUN-подсети, link-local и
///     APIPA отбрасываются (адрес надёжнее имени: он задан нами в конфиге sing-box);
///  2. изменение принимается, только если продержалось два опроса подряд (дебаунс);
///  3. на время собственных операций (подключение/переподключение) watcher ставится
///     на паузу через [suspend]/[resume].
class NetworkWatcher {
  /// Наши TUN-адреса (см. SingboxConfigBuilder): их появление — не смена сети.
  static const _ownPrefixes = ['172.19.0.', 'fdfe:dcba:9876:'];

  /// Link-local/APIPA: приходят и уходят сами по себе, к смене сети отношения не имеют.
  static const _ignoredPrefixes = ['169.254.', 'fe80:'];

  final Duration interval;

  /// Сколько игнорировать изменения после возобновления работы (подъём туннеля
  /// перестраивает маршруты — это наши же действия, а не смена сети).
  final Duration grace;

  final _controller = StreamController<String>.broadcast();
  Timer? _timer;
  String? _lastSignature;
  String? _pendingSignature; // кандидат на изменение (ждём подтверждения)
  bool _suspended = false;
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  NetworkWatcher({
    this.interval = const Duration(seconds: 5),
    this.grace = const Duration(seconds: 15),
  });

  /// Событие на подтверждённое изменение; значение — описание «было → стало».
  Stream<String> get changes => _controller.stream;

  Future<void> start() async {
    _lastSignature = await signature() ?? '';
    _pendingSignature = null;
    _suspended = false;
    _quietUntil = DateTime.now().add(grace);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  /// Пауза на время собственных операций (подключение, переподключение, подъём TUN).
  void suspend() => _suspended = true;

  /// Возобновить наблюдение: текущее состояние принимается за эталон, плюс grace.
  Future<void> resume() async {
    _lastSignature = await signature() ?? '';
    _pendingSignature = null;
    _quietUntil = DateTime.now().add(grace);
    _suspended = false;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _suspended = false;
    _pendingSignature = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  Future<void> _tick() async {
    if (_suspended || DateTime.now().isBefore(_quietUntil)) return;
    final now = await signature();
    // Не смогли прочитать список интерфейсов (разовый сбой) — НЕ считаем это
    // сменой сети: иначе пустой отпечаток отличается от прошлого и после дебаунса
    // выстреливает ложное «сеть изменилась».
    if (now == null) {
      _pendingSignature = null;
      return;
    }
    if (now == _lastSignature) {
      _pendingSignature = null; // дребезг закончился сам
      return;
    }
    // Дебаунс: реагируем только на изменение, продержавшееся два опроса подряд.
    if (_pendingSignature != now) {
      _pendingSignature = now;
      return;
    }
    final was = _lastSignature ?? '';
    _lastSignature = now;
    _pendingSignature = null;
    AppLog.w('Сеть изменилась: [$was] → [$now]');
    if (!_controller.isClosed) _controller.add(now);
  }

  /// Отпечаток из готового списка адресов (чистая функция — тестируется без сети).
  ///
  /// Отбрасываются: наши TUN-подсети, link-local/APIPA и нестабильные IPv6
  /// (временные, Teredo, 6to4, ULA) — см. [_isStableIpv6].
  static String fingerprintOf(Iterable<String> addresses) {
    final addrs = <String>{};
    for (final raw in addresses) {
      final ip = raw.toLowerCase();
      if (_ownPrefixes.any(ip.startsWith)) continue; // наш туннель
      if (_ignoredPrefixes.any(ip.startsWith)) continue; // link-local/APIPA
      if (!ip.contains(':') && _isVirtualClassB(ip)) continue; // #10 Docker/WSL/Hyper-V
      if (ip.contains(':')) {
        if (!_isStableIpv6(ip)) continue; // временный/Teredo/6to4/ULA IPv6
        // Только /64-префикс сети, а не полный адрес: privacy-расширения (RFC 4941)
        // крутят младшие 64 бита у того же префикса — это НЕ смена сети. Раньше
        // такие ротации меняли отпечаток и давали ложные переподключения.
        addrs.add(_ipv6Prefix64(ip));
      } else {
        addrs.add(ip);
      }
    }
    final sorted = addrs.toList()..sort();
    return sorted.join(',');
  }

  /// /64-префикс IPv6 (первые 8 байт), нормализованный через InternetAddress —
  /// корректно разворачивает сжатую запись `::`. При сбое возвращает исходное.
  static String _ipv6Prefix64(String ip) {
    final a = InternetAddress.tryParse(ip);
    if (a == null || a.type != InternetAddressType.IPv6) return ip;
    final b = a.rawAddress; // 16 байт
    if (b.length != 16) return ip;
    final groups = <String>[
      for (var i = 0; i < 8; i += 2)
        (((b[i] << 8) | b[i + 1]).toRadixString(16)),
    ];
    return '${groups.join(':')}::/64';
  }

  /// Адрес виртуального адаптера из 172.16.0.0/12? Сюда попадают Docker
  /// (172.17.x), WSL2 и Hyper-V (172.x): их старт/стоп давал ложную «смену сети»
  /// и цикл переподключений. Реальные LAN почти всегда 192.168.x / 10.x, поэтому
  /// исключение этого диапазона из отпечатка безопаснее ложных срабатываний.
  /// (Наш собственный TUN 172.19.0.x и так исключён по [_ownPrefixes].)
  static bool _isVirtualClassB(String ip) {
    final m = RegExp(r'^172\.(\d{1,3})\.').firstMatch(ip);
    if (m == null) return false;
    final second = int.tryParse(m.group(1)!) ?? -1;
    return second >= 16 && second <= 31;
  }

  /// Стабилен ли IPv6-адрес, то есть говорит ли его изменение о смене сети.
  ///
  /// Windows сама постоянно перегенерирует временные адреса (privacy extensions,
  /// RFC 4941) и поднимает/опускает Teredo. В логе пользователя это давало до 20
  /// ложных «смен сети» за сессию: менялись только адреса вида
  /// `fd6e:e701:c863:0:XXXX:…` и `2001:0:4625:…`, а сама сеть не менялась.
  ///
  /// Поэтому в отпечаток идут только **глобальные unicast** адреса (2000::/3),
  /// кроме туннельных Teredo (2001:0::/32) и 6to4 (2002::/16). Уникальные локальные
  /// (fc00::/7) отбрасываются: они локальные и у Windows как раз временные.
  static bool _isStableIpv6(String ip) {
    if (ip.startsWith('2001:0:') || ip.startsWith('2002:')) return false; // Teredo/6to4
    final head = int.tryParse(ip.split(':').first, radix: 16);
    if (head == null) return false;
    return head >= 0x2000 && head <= 0x3fff; // глобальный unicast
  }

  /// Отпечаток сетевого окружения: только маршрутизируемые адреса чужих адаптеров.
  ///
  /// Имена интерфейсов НЕ используются: на Windows Dart отдаёт не то имя, что видно
  /// в системе, и опираться на него нельзя (см. историю бага в шапке класса).
  static Future<String?> signature() async {
    try {
      final list = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
      return fingerprintOf(
        [for (final ni in list) ...ni.addresses.map((a) => a.address)],
      );
    } catch (_) {
      // null (а не '') — «не удалось прочитать», чтобы _tick не принял это за
      // смену сети (см. _tick).
      return null;
    }
  }
}
