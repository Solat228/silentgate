import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'geo_bases.dart';
import 'geo_bases_store.dart';

/// Что предлагает кнопка прямо сейчас.
///
/// ⚠️ КНОПКА ОБЯЗАНА БЫТЬ ЧЕСТНОЙ. Жалоба владельца дословно: «кнопка
/// "обновить" должна быть "обновить" только если есть что обновлять, иначе она
/// должна быть кнопкой "проверить обновление"». Пока мы не спросили релиз, мы
/// НЕ ЗНАЕМ, есть ли новее, — и подпись «Обновить» в этот момент обещает
/// знание, которого нет. Отсюда четыре состояния, а не два.
enum GeoAction {
  /// Файлов нет или они испорчены — предлагаем скачать.
  download,

  /// Файлы на месте, про релиз ничего не известно — «Проверить обновление».
  check,

  /// Спросили релиз: там новее — «Обновить», и видно, что именно.
  update,

  /// Спросили релиз: обновлять нечего. Так и говорим, ничего не изображая.
  upToDate,
}

/// Что поедет по сети — показывается пользователю ДО закачки.
class GeoDownloadPlan {
  final List<GeoBase> files;

  /// Сколько байт. `null` — сервер размера не сказал, обещать цифру нельзя.
  final int? bytes;

  /// Обновление имеющихся (иначе — первая закачка).
  final bool isUpdate;

  const GeoDownloadPlan({
    required this.files,
    required this.bytes,
    required this.isUpdate,
  });
}

/// Итог последнего действия — для подписи под строкой.
enum GeoOutcome { none, downloaded, upToDate, declined, failed, restored }

/// Состояние гео-баз для интерфейса: файлы, проверка, закачка.
///
/// ⚠️ ВСЯ ЛОГИКА КНОПКИ ЖИВЁТ ЗДЕСЬ, А НЕ В ВИДЖЕТЕ. Виджет только рисует
/// [action] и подписи. Иначе проверить «кнопка во всех трёх видах» можно было
/// бы только виджет-тестом, а состояний тут больше, чем видов.
class GeoBasesController extends ChangeNotifier {
  GeoBasesController({http.Client? client}) : _client = client;

  /// Клиент, отданный снаружи (тест). Его закрывает тот, кто отдал.
  final http.Client? _client;

  /// Клиент, созданный нами. ⚠️ Владение закодировано в самом поле, отдельного
  /// флага не нужно: непустым оно бывает ровно тогда, когда своего клиента нам
  /// не дали, — поэтому [dispose] закрывает именно его и никогда чужой.
  http.Client? _lazyClient;

  http.Client get _http => _client ?? (_lazyClient ??= http.Client());

  GeoBasesStatus? _status;
  GeoBasesStatus? get status => _status;

  List<GeoBackup> _backups = const [];

  /// Прежние версии баз, которые можно вернуть одним нажатием.
  ///
  /// ⚠️ Пусто — значит откат ПРЕДЛАГАТЬ НЕЛЬЗЯ. Кнопка «вернуть прежние», за
  /// которой ничего нет, — обещание, что поломку легко отменить, а на деле
  /// человек нажмёт её и останется с тем же сломанным списком.
  List<GeoBackup> get backups => _backups;
  bool get canRestore => _backups.isNotEmpty;

  GeoCheckResult? _lastCheck;
  GeoCheckResult? get lastCheck => _lastCheck;

  DateTime? _lastCheckAt;

  /// Когда обновления проверяли последний раз (в том числе в прошлом запуске).
  DateTime? get lastCheckAt => _lastCheck?.at ?? _lastCheckAt;

  bool _busy = false;
  bool get busy => _busy;

  /// Идёт проверка (а не закачка) — подписи разные.
  bool _checking = false;
  bool get checking => _checking;

  GeoProgress? _progress;
  GeoProgress? get progress => _progress;

  String? _error;
  String? get error => _error;

  GeoOutcome _outcome = GeoOutcome.none;
  GeoOutcome get outcome => _outcome;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _lazyClient?.close();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Вид кнопки.
  ///
  /// ⚠️ Состояние файлов ВАЖНЕЕ прошлой проверки: пользователь мог удалить
  /// базы после неё, и «Обновлений нет» на пустом каталоге было бы враньём.
  GeoAction get action {
    final s = _status;
    if (s == null) return GeoAction.check;
    if (!s.ready) return GeoAction.download;
    final c = _lastCheck;
    if (c == null || c.failed) return GeoAction.check;
    if (c.pending.isNotEmpty) return GeoAction.update;
    return GeoAction.upToDate;
  }

  /// Что именно обновится — для подписи у кнопки «Обновить».
  List<GeoBase> get pending => _lastCheck?.pending ?? const [];

  int? get pendingBytes => _lastCheck?.pendingBytes;

  /// Перечитать состояние файлов на диске.
  Future<void> refresh() async {
    _status = await GeoBases.status();
    _backups = await GeoBases.backups();
    _lastCheckAt ??= (await GeoBasesStore.load()).lastCheckAt;
    _notify();
  }

  /// Спросить релиз: есть ли что обновлять.
  ///
  /// Сети касается ровно двумя короткими запросами (файлы контрольных сумм) —
  /// ничего не качает и ничего не меняет на диске.
  Future<GeoCheckResult> check() async {
    if (_busy) return _lastCheck ?? GeoCheckResult(at: DateTime.now(), files: const []);
    _busy = true;
    _checking = true;
    _error = null;
    _outcome = GeoOutcome.none;
    _notify();
    try {
      final result = await GeoBases.check(client: _http);
      _lastCheck = result;
      _lastCheckAt = result.at;
      _status = await GeoBases.status();
      _error = result.error;
      _outcome = result.failed
          ? GeoOutcome.failed
          : (result.pending.isEmpty ? GeoOutcome.upToDate : GeoOutcome.none);
      return result;
    } finally {
      _busy = false;
      _checking = false;
      _notify();
    }
  }

  /// Скачать/обновить базы — ТОЛЬКО после явного согласия.
  ///
  /// [confirm] получает план (что и сколько) и возвращает решение человека.
  /// Возвращает `true`, если файлы реально скачаны.
  ///
  /// ⚠️ СОГЛАСИЕ — ПАРАМЕТР, А НЕ ДИАЛОГ ВНУТРИ. Так «пользователь отказался»
  /// проверяется обычным тестом, а не виджет-тестом с нажатием на кнопку в
  /// диалоге. И так же видно, что без ответа «да» ни один байт не поедет.
  Future<bool> download({
    required Future<bool> Function(GeoDownloadPlan plan) confirm,
  }) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _outcome = GeoOutcome.none;
    _progress = null;
    _notify();
    try {
      // Свежая проверка нужна не ради кнопки, а ради двух вещей: сказать
      // человеку размер ДО закачки и получить сумму для сверки скачанного.
      var c = _lastCheck;
      if (c == null) {
        _checking = true;
        _notify();
        c = await GeoBases.check(client: _http);
        _lastCheck = c;
        _lastCheckAt = c.at;
        _checking = false;
        _notify();
      }
      final files = c.pending;
      if (files.isEmpty) {
        // ⚠️ Не изображаем действие. Кнопка сюда не ведёт, но состояние могло
        // измениться между нажатием и этим моментом.
        _outcome = GeoOutcome.upToDate;
        return false;
      }
      final plan = GeoDownloadPlan(
        files: files,
        bytes: c.pendingBytes,
        isUpdate: c.toDownload.isEmpty,
      );
      if (!await confirm(plan)) {
        _outcome = GeoOutcome.declined;
        return false;
      }
      final sums = <GeoBase, String>{
        for (final f in c.files)
          if (f.remoteSum != null) f.base: f.remoteSum!,
      };
      final err = await GeoBases.download(
        files: files,
        expectedSums: sums,
        client: _http,
        onProgress: (p) {
          _progress = p;
          _notify();
        },
      );
      _error = err;
      _outcome = err == null ? GeoOutcome.downloaded : GeoOutcome.failed;
      if (err == null) {
        // Прошлая проверка относилась к прежним файлам — после закачки она
        // больше ничего не значит.
        _lastCheck = null;
      }
      _status = await GeoBases.status();
      _backups = await GeoBases.backups();
      return err == null;
    } finally {
      _busy = false;
      _checking = false;
      _progress = null;
      _notify();
    }
  }

  /// Вернуть прежние базы. `true` — вернули.
  ///
  /// ⚠️ ЭТО ОТДЕЛЬНОЕ ДЕЙСТВИЕ, А НЕ ЧАСТЬ ЗАКАЧКИ. Сломанную маршрутизацию
  /// человек замечает не в момент обновления, а через час — «сайты не
  /// открываются». К этому времени единственное, что должно быть под рукой, —
  /// один шаг назад, работающий без сети.
  Future<bool> restore() async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _outcome = GeoOutcome.none;
    _notify();
    try {
      final err = await GeoBases.restoreBackups();
      _error = err;
      _outcome = err == null ? GeoOutcome.restored : GeoOutcome.failed;
      // Проверка обновлений относилась к тем файлам, которых больше нет.
      if (err == null) _lastCheck = null;
      _status = await GeoBases.status();
      _backups = await GeoBases.backups();
      return err == null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Удалить базы (кнопка «Удалить» в настройках).
  Future<void> remove() async {
    if (_busy) return;
    _busy = true;
    _notify();
    try {
      await GeoBases.remove();
      _lastCheck = null;
      _outcome = GeoOutcome.none;
      _status = await GeoBases.status();
      _backups = await GeoBases.backups();
    } finally {
      _busy = false;
      _notify();
    }
  }
}

/// Пора ли проверять обновления сама.
///
/// ⚠️ АВТОПРОВЕРКА — ЭТО ТОЛЬКО ПРОВЕРКА. Она тратит два запроса по 74 байта и
/// НИЧЕГО не качает: 25 МБ на мобильном тарифе без спроса — не то, что можно
/// сделать «для удобства».
bool shouldAutoCheckGeo({
  required bool enabled,
  required int intervalDays,
  required DateTime? lastCheckAt,
  required DateTime now,
}) {
  if (!enabled) return false;
  if (lastCheckAt == null) return true;
  final days = intervalDays < 1 ? 1 : intervalDays;
  return !now.isBefore(lastCheckAt.add(Duration(days: days)));
}
