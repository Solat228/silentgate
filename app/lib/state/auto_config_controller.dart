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
    _found.clear();
    notifyListeners();

    final cancel = _cancel = CancelToken();
    try {
      final ranked = await _engine.run(
        servers: servers,
        settings: settings,
        cancel: cancel,
        variantsOverride: variants,
        onCandidate: (i, total, server, variant) {
          _progress = AutoConfigProgress(
            index: i,
            total: total,
            candidateName: server.displayName,
            variant: variant,
            services: {
              for (final s in settings.autoConfigServices) s: ProbeState.pending,
            },
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
        _found
          ..clear()
          ..addAll(ranked);
      }
      if (_found.isEmpty) _error = 'Рабочих серверов не найдено';
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
      _lastSummary = _unsupported
          ? 'Автонастройка недоступна на этой платформе'
          : _found.isEmpty
              ? 'Автонастройка: рабочих серверов не найдено'
              : 'Автонастройка завершена: найдено ${_found.length}';
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
