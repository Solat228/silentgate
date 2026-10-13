import 'dart:async';

import 'direct_internet.dart';

/// Частая проверка прямого интернета, пока канал считается живым.
///
/// ## Зачем
///
/// Сторож канала на живом туннеле щупает его раз в 45 секунд, и обрыв сети
/// на ПК замечался за 45–55 секунд. Владелец 13.10.2026 выбрал «около 15
/// секунд». Частить сквозной пробой нельзя: каждая проба через туннель — это
/// новое соединение с сервером и TLS-рукопожатие, десятки мегабайт в сутки.
///
/// Прямой запрос к `1.1.1.1` стоит сотни байт и в туннель не заходит. Он
/// идёт раз в 5 секунд, и два промаха подряд — повод проверить канал сразу,
/// не дожидаясь очередной пробы. Решает по-прежнему сторож канала: эта
/// проверка только будит его.
///
/// ## Почему только после первого успеха
///
/// У части провайдеров `1.1.1.1` закрыт, а в режиме белых списков закрыто всё
/// зарубежное. Там прямая проверка не проходит никогда, и каждый её промах
/// будил бы сторожа впустую. Поэтому сигнал даёт только ПЕРЕХОД: интернет
/// отвечал и перестал. Не отвечал ни разу — проверка молчит.
///
/// ## Почему не на Android
///
/// Запрос раз в 5 секунд будит радио телефона и сажает батарею. Там смену
/// сети и так сообщает система.
class NetworkLossWatch {
  NetworkLossWatch({
    Future<bool> Function()? check,
    this.every = const Duration(seconds: 5),
    this.missesToAct = 2,
  }) : check = check ?? _defaultCheck;

  /// Есть ли интернет напрямую. Дешёвая проверка: только адреса без имени и
  /// короткий таймаут.
  final Future<bool> Function() check;
  final Duration every;

  /// Сколько промахов подряд нужно для сигнала. Один промах бывает у любой
  /// сети, и будить сторожа на каждом незачем.
  final int missesToAct;

  static Future<bool> _defaultCheck() => DirectInternetProbe(
        timeout: const Duration(seconds: 3),
        targets: const [
          'http://1.1.1.1/generate_204',
          'http://1.0.0.1/generate_204',
        ],
      ).check();

  Timer? _timer;
  bool _busy = false;
  bool _seenUp = false;
  bool _fired = false;
  int _misses = 0;
  Object? _owner;

  bool get isRunning => _timer != null;

  /// Был ли хоть один успех с запуска. Для тестов и журнала.
  bool get seenUp => _seenUp;

  /// Запустить. [onLoss] зовётся один раз на эпизод: следующий сигнал
  /// возможен только после того, как интернет снова ответит.
  void start({required void Function() onLoss}) {
    stop();
    _seenUp = false;
    _fired = false;
    _misses = 0;
    final owner = Object();
    _owner = owner;
    _timer = Timer.periodic(every, (_) async {
      if (_busy || !identical(_owner, owner)) return;
      _busy = true;
      try {
        final ok = await check();
        if (!identical(_owner, owner)) return;
        if (ok) {
          _seenUp = true;
          _misses = 0;
          _fired = false;
          return;
        }
        if (!_seenUp || _fired) return;
        _misses++;
        if (_misses >= missesToAct) {
          _fired = true;
          onLoss();
        }
      } finally {
        _busy = false;
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _owner = null;
  }
}
