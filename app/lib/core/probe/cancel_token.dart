import 'dart:async';

class CancelledException implements Exception {
  const CancelledException();
  @override
  String toString() => 'Отменено';
}

/// Простой флаг отмены для длинных операций (пинг/автонастройка).
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw const CancelledException();
  }
}

/// Ограничитель конкурентности (семафор). Без внешних зависимостей.
class Pool {
  final int max;
  int _active = 0;
  final _waiters = <Completer<void>>[];

  Pool(this.max);

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < max) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future; // слот передаётся нам из _release без изменения _active
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(); // передаём слот следующему
    } else {
      _active--;
    }
  }
}
