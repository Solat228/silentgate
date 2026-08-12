import 'package:flutter/foundation.dart';

import '../core/models/vpn_server.dart';
import '../core/parser/share_link_parser.dart';
import '../core/probe/auto_config_engine.dart';
import '../core/probe/cancel_token.dart';
import '../core/probe/ping_result.dart';
import '../core/settings/app_settings.dart';
import '../core/xray/outbound_variant.dart';
import '../data/results_store.dart';
import '../engine/probe_factory.dart';

/// Управляет автонастройкой: прогресс, отмена, накопительный список найденных рабочих связок
/// (сервер + вариация), сохранение результатов между запусками.
class AutoConfigController extends ChangeNotifier {
  final AutoConfigEngine _engine;
  AutoConfigController({AutoConfigEngine? engine})
      : _engine = engine ??
            AutoConfigEngine(harnessFactory: createProbeHarness);

  AutoConfigProgress? _progress;
  final List<AutoConfigResult> _found = [];
  bool _running = false;
  String? _error;

  /// Что сейчас меряется по скорости. null — замера нет.
  String? _speedStatus;
  String? get speedStatus => _speedStatus;
  CancelToken? _cancel;

  /// Хук #1: закрепить найденный сервер сразу (реальный пин с рабочей вариацией).
  /// Задаётся экраном автонастройки; найденные «всплывают» сверху списка вживую.
  void Function(VpnServer server, OutboundVariant variant)? onPinFound;

  /// Хук #3.2: отдать измеренную задержку в общий пинг, чтобы значение на главной
  /// подменилось сразу (метод — из настроек, TCP/ICMP).
  void Function(VpnServer server, PingResult result)? onPingMeasured;

  AutoConfigProgress? get progress => _progress;
  List<AutoConfigResult> get found => List.unmodifiable(_found);
  bool get running => _running;
  String? get error => _error;

  /// Итог последнего прогона и момент завершения — для уведомления слева снизу,
  /// которое висит ещё несколько секунд после конца работы.
  String? _lastSummary;

  /// Подбор не начинался: платформа не умеет пропускать запросы через кандидата.
  /// Отличать от «прогнали и ничего не нашли» обязательно — это разные новости.
  /// Один текст на экран-предупреждение и на отказ: разойдись они — человек
  /// получил бы два разных объяснения одному и тому же.
  static const unsupportedMessage =
      'Автонастройка недоступна на этой платформе: проверить доступность '
      'сервисов через сервер нечем. Пользуйтесь пингом.';

  bool _unsupported = false;
  bool get unsupported => _unsupported;
  DateTime? _finishedAt;
  String? get lastSummary => _lastSummary;
  DateTime? get finishedAt => _finishedAt;

  // ── Выбор серверов для подбора ─────────────────────────────────────────────
  //
  // ⚠️ ЖИВЁТ ЗДЕСЬ, А НЕ В `State` ЭКРАНА, И ЭТО ФИКС ДЕФЕКТА. Галочки лежали в
  // `_BatchTuneState._sel`; экран автонастройки — обычный маршрут, при уходе с
  // него `State` умирает. Человек снимал полсотни галочек, отходил посмотреть
  // список серверов, возвращался — и снова видел отмеченными ВСЕ.
  final Set<String> _selection = {};
  bool _selectionInit = false;

  Set<String> get selection => Set.unmodifiable(_selection);

  /// Первое заполнение — все серверы. Зовётся из `build`, поэтому НЕ уведомляет
  /// слушателей: `notifyListeners()` во время сборки кадра роняет Flutter.
  void ensureSelection(Iterable<String> keys) {
    if (_selectionInit) return;
    _selectionInit = true;
    _selection.addAll(keys);
  }

  void setSelected(String key, bool on) {
    _selectionInit = true;
    if (on) {
      _selection.add(key);
    } else {
      _selection.remove(key);
    }
    notifyListeners();
  }

  void selectAll(Iterable<String> keys) {
    _selectionInit = true;
    _selection
      ..clear()
      ..addAll(keys);
    notifyListeners();
  }

  void clearSelection() {
    _selectionInit = true;
    _selection.clear();
    notifyListeners();
  }

  // ── Таймер «прошло / осталось» ─────────────────────────────────────────────
  DateTime? _startedAt;

  /// Когда пользователь запустил прогон. null — прогона не было.
  DateTime? get startedAt => _startedAt;

  /// Фаза и её собственная точка отсчёта.
  ///
  /// ⚠️ У фаз РАЗНАЯ стоимость шага: перебор кандидата — это подъём харнесса и
  /// несколько проб, а шаг замера скорости — скачивание 5 МБ. Считать их одной
  /// средней значило бы показать заведомо неверный остаток ровно в тот момент,
  /// когда прогон переходит из одной фазы в другую.
  AutoConfigPhase _phase = AutoConfigPhase.probing;
  DateTime? _phaseStartedAt;
  int _phaseDone = 0;
  int _phaseTotal = 0;

  void _notePhase(AutoConfigPhase phase, int index, int total) {
    if (phase != _phase || _phaseStartedAt == null) {
      _phase = phase;
      _phaseStartedAt = DateTime.now();
    }
    // ⚠️ ЗАВЕРШЁННЫХ — `index`, А НЕ `index + 1`. Кандидат с номером `index`
    // только НАЧАЛСЯ; записав его в пройденные, мы поделили бы время на
    // завышенное число и занизили оценку. Пока не закончился ни один —
    // оценки нет вовсе, и это честнее выдуманной.
    _phaseDone = index;
    _phaseTotal = total;
  }

  /// Сколько прогон уже идёт.
  Duration? elapsed([DateTime? now]) {
    final start = _startedAt;
    if (start == null) return null;
    return (now ?? DateTime.now()).difference(start);
  }

  /// Оценка остатка ТЕКУЩЕЙ фазы или null, если оценивать пока не по чему.
  Duration? remainingEstimate([DateTime? now]) {
    final start = _phaseStartedAt;
    if (start == null) return null;
    return estimateRemaining(
      elapsed: (now ?? DateTime.now()).difference(start),
      done: _phaseDone,
      total: _phaseTotal,
    );
  }

  /// Остаток по ФАКТИЧЕСКОЙ стоимости пройденного, а не по числу кандидатов.
  ///
  /// ⚠️ ПОЧЕМУ НЕ «СКОЛЬКО ОСТАЛОСЬ × КОНСТАНТА». Стоимость кандидата
  /// отличается в разы: отвечающий сервер добавляет к пробам ещё и замер
  /// задержки, а у молчащего КАЖДАЯ проба ждёт полный таймаут. Оценка по
  /// одному лишь числу давала бы то втрое меньше, то втрое больше — то есть
  /// была бы хуже отсутствия оценки. Здесь средняя берётся из уже прожитого
  /// времени этой же фазы, поэтому она сама подстраивается под состав списка.
  static Duration? estimateRemaining({
    required Duration elapsed,
    required int done,
    required int total,
  }) {
    if (done <= 0 || elapsed <= Duration.zero) return null;
    final left = total - done;
    if (left <= 0) return Duration.zero;
    return Duration(microseconds: elapsed.inMicroseconds ~/ done * left);
  }

  /// Загрузка сохранённых результатов прошлого прогона.
  Future<void> init() async {
    try {
      final data = await ResultsStore.autoConfig.load();
      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            final r = AutoConfigResult.fromJson(item.cast<String, dynamic>());
            if (r != null) _found.add(r);
          }
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Подбор по одному вставленному ключу (vless:// и др.) с расширенным перебором настроек.
  Future<void> startForKey(String key, AppSettings settings) async {
    final server = ShareLinkParser.tryParse(key.trim());
    if (server == null) {
      _error = 'Не удалось распознать ключ '
          '(нужен vless:// / vmess:// / trojan:// / ss:// / hysteria2://)';
      notifyListeners();
      return;
    }
    await start([server], settings, variants: AutoConfigEngine.deepVariants());
  }

  Future<void> start(
    List<VpnServer> servers,
    AppSettings settings, {
    List<OutboundVariant>? variants,
  }) async {
    if (_running) return;
    _running = true;
    _error = null;
    _progress = null;
    _lastSummary = null;
    _unsupported = false;
    _startedAt = DateTime.now();
    _phase = AutoConfigPhase.probing;
    _phaseStartedAt = _startedAt;
    _phaseDone = 0;
    _phaseTotal = 0;
    // ⚠️ ЧИСТИМ ТОЛЬКО УЧАСТНИКОВ ЭТОГО ПРОГОНА, А НЕ ВЕСЬ СПИСОК.
    //
    // Раньше здесь стоял `_found.clear()`, и это молча уничтожало результаты,
    // на которых держался весь остальной экран: подбор одного сервера из
    // контекстного меню (`startForKey`) стирал итоги предыдущего прогона по
    // всей подписке, а верхняя кнопка «Подобрать для выбранных» — данные
    // нижней кнопки «Готово». Пользователь не делал ничего, что означало бы
    // «забудь всё найденное».
    final runKeys = servers.map((s) => s.key).toSet();
    _found.removeWhere((r) => runKeys.contains(r.server.key));
    notifyListeners();

    // Найденное ИМЕННО В ЭТОМ прогоне: итог и текст ошибки обязаны говорить
    // про него, а не про накопленный список (иначе прогон, не нашедший ничего,
    // отчитывался бы чужими находками).
    final runFound = <AutoConfigResult>[];
    final cancel = _cancel = CancelToken();
    try {
      final ranked = await _engine.run(
        servers: servers,
        settings: settings,
        cancel: cancel,
        variantsOverride: variants,
        onCandidate: (i, total, server, variant) {
          _notePhase(AutoConfigPhase.probing, i, total);
          _progress = AutoConfigProgress(
            index: i,
            total: total,
            candidateName: server.displayName,
            candidateKey: server.key,
            variant: variant,
            services: {
              for (final s in settings.autoConfigServices) s: ProbeState.pending,
            },
          );
          notifyListeners();
        },
        // Фаза замера скорости отчитывается о себе сама. Без этого `_progress`
        // оставался с последним кандидатом перебора, и экран десятки секунд
        // уверял, что «тестирует» сервер, который давно проверен.
        onSpeedCandidate: (i, total, server, variant) {
          _notePhase(AutoConfigPhase.speed, i, total);
          _progress = AutoConfigProgress(
            index: i,
            total: total,
            candidateName: server?.displayName ?? '',
            candidateKey: server?.key ?? '',
            variant: variant,
            services: const {},
            phase: AutoConfigPhase.speed,
          );
          notifyListeners();
        },
        onService: (service, ok) {
          final p = _progress;
          if (p != null) {
            p.services[service] = ok ? ProbeState.ok : ProbeState.fail;
            notifyListeners();
          }
        },
        // Замер скорости идёт ПОСЛЕ отбора и занимает десятки секунд. Без этой
        // строки пользователь видел бы застывший экран и решил, что подбор завис.
        onSpeed: (message) {
          _speedStatus = message;
          notifyListeners();
        },
        onFound: (result) {
          _found.add(result);
          runFound.add(result);
          onPinFound?.call(result.server, result.variant); // #1 — сразу в пины
          final ping = result.ping;
          if (ping != null) {
            onPingMeasured?.call(result.server, ping); // #3.2 — пинг на главной
          }
          notifyListeners();
        },
      );
      _speedStatus = null;
      // Порядок берём У ДВИЖКА: он единственный знает, чем в итоге отсортировано
      // — числом пройденных сервисов и задержкой либо, если включён учёт
      // скорости, оценкой с замером. Раньше возвращённый список молча
      // выбрасывался, и результат замера скорости не влиял ни на что.
      if (ranked.isNotEmpty) {
        // Итог прогона встаёт СВЕРХУ, ранее найденное по другим серверам —
        // следом. Порядок внутри `ranked` задаёт движок, и трогать его нельзя.
        _found.removeWhere((r) => runKeys.contains(r.server.key));
        _found.insertAll(0, ranked);
        runFound
          ..clear()
          ..addAll(ranked);
      }
      if (runFound.isEmpty) _error = 'Рабочих серверов не найдено';
    } on CancelledException {
      // частичные результаты остаются в _found
    } on AutoConfigUnsupported {
      // Не «ничего не нашли», а «проверить нечем»: подбор смотрит, открывается
      // ли YouTube/ChatGPT ЧЕРЕЗ сервер, а на этой платформе замер отдаёт одну
      // задержку и порта не даёт. Раньше это выглядело как «найдено 0» на
      // рабочей подписке — то есть как поломка серверов.
      _error = unsupportedMessage;
      _unsupported = true;
    } catch (e) {
      _error = 'Ошибка: $e';
    } finally {
      _running = false;
      _progress = null;
      // Оценка остатка живёт ровно столько, сколько идёт прогон: показывать
      // «осталось 3:20» после его конца — прямое враньё.
      _phaseStartedAt = null;
      _phaseDone = 0;
      _phaseTotal = 0;
      _lastSummary = _unsupported
          ? 'Автонастройка недоступна на этой платформе'
          : runFound.isEmpty
              ? 'Автонастройка: рабочих серверов не найдено'
              : 'Автонастройка завершена: найдено ${runFound.length}';
      _finishedAt = DateTime.now();
      await _persist();
      notifyListeners();
    }
  }

  void cancel() => _cancel?.cancel();

  Future<void> clear() async {
    _found.clear();
    _error = null;
    await ResultsStore.autoConfig.save(const []);
    notifyListeners();
  }

  Future<void> _persist() async {
    // ⚠️ НЕ пересортировывать. Порядок задаёт движок, и при включённом учёте
    // скорости он другой: первым стоит тот, кто реально быстрее, а не тот, у
    // кого меньше пинг. Сортировка здесь этот результат стирала.
    await ResultsStore.autoConfig.save(_found.map((r) => r.toJson()).toList());
  }
}
