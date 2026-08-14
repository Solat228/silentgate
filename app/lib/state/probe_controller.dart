import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/models/vpn_server.dart';
import '../core/net/speed_test.dart';
import '../core/probe/cancel_token.dart';
import '../core/probe/ping_result.dart';
import '../core/probe/proxy_probe.dart';
import '../core/probe/tcp_ping.dart';
import '../core/platform/app_log.dart';
import '../core/probe/probe_harness.dart';
import '../core/settings/app_settings.dart';
import '../core/util/key_migration.dart';
// HarnessRealism не входит в реэкспорт probe_harness.dart (там только сущности
// самого харнесса), поэтому берём его из первоисточника.
import '../core/xray/harness_config_builder.dart' show HarnessRealism;
import '../core/xray/outbound_variant.dart';
import '../data/results_store.dart';
import '../engine/probe_factory.dart';

/// Подпись замера скорости. Совпадает с [SpeedTest.download], но объявлена
/// отдельно, чтобы её можно было подменить в тесте (лишние необязательные
/// именованные параметры настоящей функции подстановке не мешают).
typedef SpeedDownload = Future<SpeedResult> Function({
  required SpeedTestSize size,
  int? proxyPort,
  String proxyUser,
  String proxyPassword,
});

/// Пинг серверов. Модель проверки — как просил пользователь:
///   1. **TCP до всех** серверов (быстро, без ядра). Кто не ответил — «мёртв»,
///      из дальнейшей проверки исключается.
///   2. **GET/HEAD-верификация** оставшихся (через проброс-харнесс): отделяет
///      по-настоящему рабочие сервера от тех, что просто отвечают на TCP-порт.
/// **Показываемая задержка — всегда TCP.** hysteria2 — исключение: TCP у него
/// нет (QUIC/UDP), поэтому он идёт сразу на верификацию, а число берётся оттуда.
/// Системный прокси не трогается.
///
/// ⚠️ ЧЕРЕЗ ЧТО ИДЁТ ФАЗА 2 — ЗАВИСИТ ОТ СЕРВЕРА:
///   * **подключённый сервер при живом канале** — через ЖИВОЕ ядро, тем же
///     путём, что и трафик браузера. Это буквально «включил VPN и открыл сайт»;
///   * **остальные** — через проброс-харнесс, конфиг которого теперь несёт
///     боевые правила по сайтам и DNS ([HarnessRealism]).
/// ⚠️ Честная граница: для НЕАКТИВНЫХ серверов это всё равно проверка через
/// прокси-порт, а не через TUN-адаптер. Поломку самого TUN такая проба не
/// увидит — её видно только на активном сервере.
///
/// ⚠️ ФАЗА 1 НЕ ОБЪЯВЛЯЕТ СЕРВЕР РАБОЧИМ. TCP-ответ даёт только достижимость
/// ([PingOutcome.ok]); итог проверки живёт отдельно в [PingResult.verification]
/// и до фазы 2 стоит в `pending` (проверка идёт) либо `notRun` (её не будет).
/// Прежний код ставил «рабочий» авансом — на сервере, через который не работало
/// ничего, плашка горела зелёным всё время фазы 2. Не возвращать аванс.
class ProbeController extends ChangeNotifier {
  final ProbeHarness Function() _harnessFactory;

  final Map<String, PingResult> _results = {};
  bool _running = false;
  CancelToken? _cancel;

  /// Как скачивать пробу при замере скорости. Поле, а не прямой вызов
  /// [SpeedTest.download], ровно ради теста: настоящий замер уходит в интернет
  /// и тратит трафик подписки, а проверять гейт «не прошёл GET — не мерим»
  /// надо без единого байта наружу.
  SpeedDownload speedDownload = SpeedTest.download;

  /// Порт ЖИВОГО соединения и ключ сервера, который сейчас поднят.
  ///
  /// ⚠️ ИСПОЛЬЗУЮТСЯ НА ВСЕХ ПЛАТФОРМАХ, а не только там, где нет харнесса.
  /// Раньше живой канал был запасным вариантом для Android; теперь это ОСНОВНОЙ
  /// путь проверки подключённого сервера везде — харнесс с голым конфигом
  /// проходил там, где боевое подключение не работает.
  ///
  /// Через живой туннель честно проверяется РОВНО ОДИН сервер — тот, что сейчас
  /// подключён; для остальных такая проба измеряла бы чужой канал и давала
  /// одинаковые цифры всему списку, что хуже честного «не проверен».
  ///
  /// [liveProxyPort] обязан отдавать 0, пока канал не «Подключено» (так и
  /// сделано в `home_screen`): «подключается» — не «живой».
  int Function()? liveProxyPort;
  String? Function()? activeServerKey;

  ProbeController({
    ProbeHarness Function()? harnessFactory,
    this.liveProxyPort,
    this.activeServerKey,
  }) : _harnessFactory = harnessFactory ?? createProbeHarness;

  bool get running => _running;
  PingResult resultFor(VpnServer s) => _results[s.key] ?? PingResult.untested;

  // ── Прогресс для уведомления слева снизу ───────────────────────────────────
  List<VpnServer> _batch = const [];

  /// Ключи серверов, полностью «сделанных» в текущем прогоне (мёртвые в фазе 1
  /// либо прошедшие верификацию). Считать «сделан» по outcome нельзя: в двухфазном
  /// режиме TCP-ответивший получает outcome=ok ещё до GET/HEAD, и полоска прыгала
  /// бы на 100% на всё время фазы 2 (самой долгой).
  final Set<String> _done = {};
  String? _lastSummary;
  DateTime? _finishedAt;
  Set<String> _unfinished = const {};

  /// Ключи серверов текущего прогона. Держим отдельным множеством, а не считаем
  /// по [_batch]: спрашивают его на каждую перерисовку меню подписок, а
  /// уведомлений за прогон приходят сотни.
  Set<String> _batchKeys = const {};

  /// Сколько серверов в текущем прогоне.
  int get total => _batch.length;

  /// Сколько уже полностью проверено (с учётом фазы верификации).
  int get done => _batch.where((s) => _done.contains(s.key)).length;

  /// Ключи серверов, которые прогон проверяет ПРЯМО СЕЙЧАС. Пусто, когда прогон
  /// не идёт: [_batch] после конца прогона остаётся заполненным (по нему живёт
  /// итоговая полоска хода), и отдавать его как «в работе» значило бы держать
  /// счётчики подписок в состоянии «идёт проверка» до следующего пинга.
  ///
  /// ⚠️ КЛЮЧИ, А НЕ ОДИН ФЛАГ [running]. Перепроверка ОДНОЙ строки (`pingOne`
  /// по тапу на плашке пинга) идёт через тот же `_pingBatch` и поднимает тот же
  /// флаг: по нему счётчик стосерверной подписки прятал число за многоточие
  /// из-за единственного сервера. Кто и насколько задет прогоном, видно только
  /// из состава прогона.
  Set<String> get runningKeys => _running ? _batchKeys : const {};

  /// Ключи серверов, до которых прогон НЕ ДОШЁЛ: отмена пользователем либо
  /// сбой. Пометка живёт ПО СЕРВЕРАМ, а не «по последнему прогону»: снимается
  /// она с тех, кого новый прогон взял в работу, и переживает перезапуск
  /// приложения (файл `ping_unfinished.json`, читается в [init]).
  ///
  /// ⚠️ ОТМЕНА — НЕ РЕЗУЛЬТАТ, И СНАРУЖИ ЭТО ОБЯЗАНО БЫТЬ ВИДНО. Прогон,
  /// отменённый на четвёртом сервере из ста одного, оставляет ровно ту же
  /// картину, что законченный: у части серверов вердикт есть, у остальных нет.
  /// Счётчик подписки показывал это как «101 · 4» — то есть «проверили все,
  /// работают четверо». По самим результатам отличить нельзя: `notRun` стоит и
  /// у «не успели проверить», и у «проверка не предполагалась». Поэтому список
  /// недостигнутых ведёт сам прогон — тот, кто единственный это знает.
  Set<String> get unfinishedKeys => _unfinished;

  /// Забыть пометку у серверов, которых приложение больше не знает.
  ///
  /// ⚠️ БЕЗ ЭТОГО СПИСОК ТОЛЬКО РОС, И ХУЖЕ РАЗМЕРА БЫЛО ВОСКРЕШЕНИЕ. Ключ
  /// снимает лишь тот прогон, который взял сервер В РАБОТУ (см. `_pingBatch`), а
  /// сервер, пропавший из подписки, не возьмёт уже никто — его пометка остаётся
  /// в `ping_unfinished.json` навсегда. Вернётся узел с тем же ключом (панель
  /// вернула его в подписку, человек переимпортировал её) — и подписка тут же
  /// пометится неполной по прогону, которого в этой её жизни не было.
  ///
  /// [knownKeys] — ВСЁ, что приложение знает сейчас: активный список плюс
  /// серверы остальных подписок (`AppState.allSubscriptionServers`). Меньший
  /// список сюда передавать нельзя — стёрлась бы живая пометка.
  ///
  /// ⚠️ ПУСТОЙ [knownKeys] НЕ ЧИСТИТ НИЧЕГО. «Список не собрался» и «серверов
  /// нет» здесь неразличимы, а цена ошибки — молча стёртая пометка у всех.
  ///
  /// Без [notifyListeners] намеренно: снимаются ключи, которых нет ни в одном
  /// списке серверов, а счётчик подписки сверяет пометку СО СВОИМИ серверами
  /// (`SubscriptionPingCount.of`) — показанные числа от этой чистки не меняются.
  Future<void> forgetUnknownServers(Iterable<String> knownKeys) async {
    if (_unfinished.isEmpty) return;
    final known = knownKeys.toSet();
    if (known.isEmpty) return;
    final kept = {
      for (final k in _unfinished)
        if (known.contains(k)) k,
    };
    if (kept.length == _unfinished.length) return;
    _unfinished = kept;
    await _persistUnfinished();
  }

  /// Итог последнего прогона и момент завершения — уведомление висит ещё
  /// несколько секунд после конца, поэтому текст нужен и после `running == false`.
  String? get lastSummary => _lastSummary;
  DateTime? get finishedAt => _finishedAt;

  /// #6 — сохранённая вариация сервера (fragment/fingerprint из автонастройки).
  /// Без неё сервер, работающий только с обходом, не проходит проверку via Proxy
  /// и показывает «n/a». Хук ставит AppState (см. HomeScreen).
  OutboundVariant Function(VpnServer server)? variantFor;

  OutboundVariant _variantOf(VpnServer s) =>
      variantFor?.call(s) ?? OutboundVariant.none;

  /// Загрузка сохранённых результатов пинга и замеров скорости.
  Future<void> init() async {
    try {
      final data = await ResultsStore.ping.load();
      if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            _results['$key'] = PingResult.fromJson(value.cast<String, dynamic>());
          }
        });
        notifyListeners();
      }
    } catch (_) {}
    try {
      // ⚠️ ПОМЕТКА «ПРОГОН НЕ ДОШЁЛ» ЧИТАЕТСЯ С ДИСКА ВМЕСТЕ С РЕЗУЛЬТАТАМИ, И
      // ИНАЧЕ НЕЛЬЗЯ. Она жила только в памяти: результаты пинга перезапуск
      // переживали, а знание о том, что половину списка проверить не успели, —
      // нет. После перезапуска счётчик подписки снова показывал недосчитанное
      // число как законченный вердикт — то есть врал ровно так же, как до
      // появления пометки, только теперь ещё и убедительнее (цифра-то есть).
      final data = await _unfinishedStore.load();
      if (data is List) {
        // Ключи приводим к каноническому виду тем же переносом, что и результаты
        // пинга (`ResultsStore.migrate`): у живого сервера ключ всегда приходит
        // из парсера уже канонизированным, и без переноса пометка после смены
        // написания ссылки осталась бы висеть на ключах, которых больше ни у
        // кого нет, — то есть просто исчезла бы.
        _unfinished = KeyMigration.remapList(
          [for (final k in data) '$k'],
          logLabel: _unfinishedStore.fileName,
        ).toSet();
        notifyListeners();
      }
    } catch (_) {}
    try {
      final data = await _speedStore.load();
      if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            final s = ServerSpeed.fromJson(value.cast<String, dynamic>());
            if (s != null) _speeds['$key'] = s;
          }
        });
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final terminal = <String, dynamic>{};
    _results.forEach((key, result) {
      if (result.isTerminal) terminal[key] = result.toJson();
    });
    await ResultsStore.ping.save(terminal);
  }

  /// Файл пометки «прогон сюда не дошёл» — список ключей.
  ///
  /// ⚠️ ОТДЕЛЬНЫМ ФАЙЛОМ, А НЕ ПОЛЕМ В `ping_results.json`: там записи лежат ПО
  /// КЛЮЧАМ измеренных серверов, а недостигнутый сервер — это ровно тот, у кого
  /// записи нет. Класть его туда пришлось бы выдуманным результатом, а
  /// выдуманный результат — начало всех бед этого счётчика.
  static const _unfinishedStore = ResultsStore('ping_unfinished.json');

  Future<void> _persistUnfinished() =>
      _unfinishedStore.save(_unfinished.toList());

  /// #3.2 — записать готовый результат извне (автонастройка меряет задержку сама),
  /// чтобы пинг на главной сразу подменился, а не ждал отдельного прогона.
  void setResult(VpnServer server, PingResult result) {
    _results[server.key] = result;
    notifyListeners();
    _persist();
  }

  Future<void> pingAll(List<VpnServer> servers, AppSettings settings) =>
      _pingBatch(servers, settings);

  Future<void> pingOne(VpnServer server, AppSettings settings) =>
      _pingBatch([server], settings);

  void cancel() => _cancel?.cancel();

  // ── Скорость сервера ───────────────────────────────────────────────────────
  //
  // Отдельная подсистема поверх того же харнесса. Дорогая: одна проба стоит
  // 5–20 МБ ТРАФИКА ПОДПИСКИ, поэтому запускается только вручную и только по
  // серверам, прошедшим проверку канала (см. [PingResult.speedMeasurable]).

  /// Файл замеров. Отдельно от `ping_results.json`, потому что и живут они
  /// отдельно: прогон пинга перезаписывает свой результат целиком.
  static const _speedStore = ResultsStore('speed_results.json');

  final Map<String, ServerSpeed> _speeds = {};
  bool _speedRunning = false;
  CancelToken? _speedCancel;
  int _speedTotal = 0;
  int _speedDone = 0;
  String? _speedSummary;
  DateTime? _speedFinishedAt;

  /// Замер скорости этого сервера. `null` — не мерили.
  ServerSpeed? speedFor(VpnServer s) => _speeds[s.key];

  bool get speedRunning => _speedRunning;
  int get speedTotal => _speedTotal;
  int get speedDone => _speedDone;
  String? get speedSummary => _speedSummary;
  DateTime? get speedFinishedAt => _speedFinishedAt;

  /// Кого имеет смысл гнать в прогон по списку: прошёл проверку канала, ещё не
  /// измерен И есть чем измерить. Второе условие — прямое требование владельца
  /// «уже замеренное повторно не меряется»: за каждый повтор платит трафик
  /// подписки. Ручной замер одного сервера гейтом «уже измерено» не ограничен —
  /// там человек знает, что делает; а вот [canMeasureSpeed] обязателен и там.
  List<VpnServer> speedTargets(Iterable<VpnServer> servers) => [
        for (final s in servers)
          if (resultFor(s).speedMeasurable &&
              _speeds[s.key] == null &&
              canMeasureSpeed(s))
            s,
      ];

  /// Есть ли ЧЕМ измерить скорость этого сервера.
  ///
  /// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА 1.4.3: «на телефоне нет измерения скорости». Так и
  /// было, и молча: замер качает пробу через локальный http-порт, а на Android
  /// харнесс порта не отдаёт — `LibXray.ping` поднимает ядро ВНУТРИ вызова,
  /// меряет сам и гасит его; наружу отдаётся только число миллисекунд.
  /// `proxyPortFor` там всегда 0, и прогон писал в журнал «харнесс не дал
  /// порт», а человек видел «измерено 0 из 1» без единого слова о причине.
  ///
  /// Что при этом ЕСТЬ на Android: живой туннель. У него инбаунд проб на
  /// 127.0.0.1:10811 (заведён ради сервис-чипов), через него ходит и проверка
  /// канала подключённого сервера. Скачать через него пробу можно — значит
  /// скорость ПОДКЛЮЧЁННОГО сервера измерима на обеих платформах, а остальных
  /// на Android — нет, и интерфейс обязан это знать, а не обещать.
  ///
  /// ⚠️ Спрашиваем САМ ХАРНЕСС (`supportsProxyRequests`), а не `Platform.isX`:
  /// платформенная развилка уже описана в одном месте (`probe_factory`), и
  /// вторая её копия здесь разъехалась бы с первой на первой же платформе.
  bool canMeasureSpeed(VpnServer s) =>
      _harnessCanMeasure || _liveTargetIn([s]) != null;

  /// Кэш ответа харнесса: план прогона спрашивают на каждое нажатие, а создание
  /// харнесса на Android генерирует пароль через `Random.secure`.
  bool? _harnessCanMeasureCache;

  bool get _harnessCanMeasure {
    final known = _harnessCanMeasureCache;
    if (known != null) return known;
    try {
      return _harnessCanMeasureCache = _harnessFactory().supportsProxyRequests;
    } catch (_) {
      // Платформа без харнесса вовсе (`createProbeHarness` бросает) —
      // остаётся живой канал.
      return _harnessCanMeasureCache = false;
    }
  }

  /// Скорости, уже посчитанные автонастройкой, — в строку сервера, без повтора.
  ///
  /// ⚠️ Молча, без [notifyListeners], когда ничего не изменилось: метод зовётся
  /// с каждой перерисовки главного экрана, и безусловное уведомление устроило
  /// бы бесконечный цикл «notify → build → notify».
  void adoptSpeeds(Map<String, ServerSpeed> byKey) {
    var changed = false;
    byKey.forEach((key, speed) {
      // Ручной замер сильнее: он свежее и сделан по настройке пользователя.
      // Иначе список из автонастройки затирал бы только что измеренное.
      final have = _speeds[key];
      if (have != null && !have.fromAutoConfig) return;
      if (have != null && have.mbps == speed.mbps) return;
      _speeds[key] = speed;
      changed = true;
    });
    if (!changed) return;
    notifyListeners();
    unawaited(_persistSpeeds());
  }

  /// Замер одного сервера — пункт контекстного меню строки.
  Future<void> measureSpeedOne(VpnServer server, AppSettings settings) =>
      _measureSpeeds([server], settings, force: true);

  /// Прогон по списку. Вызывающий ОБЯЗАН спросить подтверждение и назвать
  /// объём: 101 сервер × 5–20 МБ — это до двух гигабайт подписки.
  Future<void> measureSpeedAll(List<VpnServer> servers, AppSettings settings) =>
      _measureSpeeds(servers, settings, force: false);

  void cancelSpeed() => _speedCancel?.cancel();

  Future<void> _measureSpeeds(List<VpnServer> servers, AppSettings settings,
      {required bool force}) async {
    // Один харнесс на процесс: пинг и замер делят те же локальные порты, и
    // параллельный запуск отобрал бы порт у уже идущего прогона.
    if (_speedRunning || _running) return;
    final targets = force
        ? [
            for (final s in servers)
              if (resultFor(s).speedMeasurable && canMeasureSpeed(s)) s,
          ]
        : speedTargets(servers);
    if (targets.isEmpty) {
      // ⚠️ МОЛЧА ВЫЙТИ НЕЛЬЗЯ, ЕСЛИ ЧЕЛОВЕК НАЖАЛ ПУНКТ МЕНЮ. Прочие причины
      // пустого списка интерфейс объясняет сам (не прошёл проверку канала —
      // `speedNotVerified`, нечего мерить — `speedNoTargets`), а вот «мерить
      // нечем на этой платформе» он до 1.4.4 не знал: прогон уходил в харнесс,
      // получал порт 0 и заканчивался безликим «измерено 0 из 1».
      if (force &&
          servers.any(
              (s) => resultFor(s).speedMeasurable && !canMeasureSpeed(s))) {
        _speedSummary = 'Скорость этого сервера здесь не измерить: замер идёт '
            'через живое подключение. Подключитесь к нему и повторите';
        _speedFinishedAt = DateTime.now();
        notifyListeners();
      }
      return;
    }

    _speedRunning = true;
    _speedTotal = targets.length;
    _speedDone = 0;
    _speedSummary = null;
    final cancel = _speedCancel = CancelToken();
    notifyListeners();

    var ok = 0;
    final sw = Stopwatch()..start();
    AppLog.i('Скорость: ${targets.length} серверов по '
        '${settings.speedTestSize.label}');
    try {
      for (final s in targets) {
        if (cancel.isCancelled) break;
        // ── ПОДКЛЮЧЁННЫЙ СЕРВЕР МЕРЯЕТСЯ ЧЕРЕЗ ЖИВОЙ КАНАЛ, А НЕ ХАРНЕССОМ.
        //
        // ⚠️ ЭТО И ЕСТЬ ЗАМЕР НА ANDROID, КОТОРОГО НЕ БЫЛО (жалоба 1.4.3).
        // Харнесс там порта наружу не даёт (см. [canMeasureSpeed]), а живой
        // туннель даёт: инбаунд проб на 127.0.0.1:10811 уже поднят ради
        // сервис-чипов и проверки канала. Тот же путь используется и на
        // Windows — не ради единообразия, а потому что он ЧЕСТНЕЕ: качаем
        // ровно через тот канал, которым человек сейчас пользуется, со всеми
        // его правилами, а не через временное ядро с голым конфигом.
        //
        // ⚠️ Ровно ОДИН сервер — подключённый ([_liveTargetIn] сверяет ключ).
        // Соседний сервер, измеренный через чужой живой туннель, получил бы
        // скорость этого туннеля — то есть заведомо чужое число в своей строке.
        //
        // Честная граница: правило пользователя «этот домен — Прямо» уведёт
        // пробу мимо VPN, и цифра будет про прямой канал. Иначе и быть не
        // может: живой туннель на то и живой, что работает по своим правилам.
        final live = _liveTargetIn([s]);
        if (live != null) {
          try {
            final res = await speedDownload(
              size: settings.speedTestSize,
              proxyPort: live.port,
              // Креды ЖИВОГО инбаунда — сессионные, не харнессные: это другой
              // процесс (Windows) / другой экземпляр ядра (Android) со своим
              // паролем. Подставить сюда пароль харнесса значит получить 407 и
              // «замер не удался» на исправном канале.
              proxyUser: ProxyProbe.user,
              proxyPassword: ProxyProbe.password,
            );
            if (_recordSpeed(s, res)) ok++;
          } catch (e) {
            AppLog.w('Скорость «${s.displayName}» по живому каналу — $e');
          }
          _speedDone++;
          notifyListeners();
          continue;
        }

        HarnessHandle? handle;
        try {
          handle = await _harnessFactory().start([
            HarnessEntry(key: s.key, server: s, variant: _variantOf(s)),
          ]);
          if (cancel.isCancelled) break;
          final port = handle.proxyPortFor(0);
          if (port > 0) {
            // ⚠️ КРЕДЫ ХАРНЕССА — ОБЯЗАТЕЛЬНО. Инбаунды закрыты паролем
            // (1.3.0/1.4.1), и без них ядро отвечает 407, а `catch` превращает
            // это в безликое «замер не удался» на КАЖДОМ сервере. Ровно так
            // молча умер замер скорости, когда пароль добавили пингу и забыли
            // про скорость.
            final res = await speedDownload(
              size: settings.speedTestSize,
              proxyPort: port,
              proxyUser: handle.proxyUser,
              proxyPassword: handle.proxyPassword,
            );
            if (_recordSpeed(s, res)) ok++;
          } else {
            // Сюда теперь попадает только сбой харнесса: платформа, которая
            // порта не даёт, до цикла не доходит вовсе ([canMeasureSpeed]).
            AppLog.w('Скорость «${s.displayName}»: харнесс не дал порт');
          }
        } catch (e) {
          AppLog.w('Скорость «${s.displayName}» не замерена — $e');
        } finally {
          await handle?.stop();
        }
        _speedDone++;
        notifyListeners();
      }
    } finally {
      _speedRunning = false;
      _speedFinishedAt = DateTime.now();
      _speedSummary = cancel.isCancelled
          ? 'Замер скорости отменён: измерено $ok из ${targets.length}'
          : 'Скорость измерена: $ok из ${targets.length} '
              '(${sw.elapsed.inSeconds} с)';
      AppLog.i(_speedSummary!);
      await _persistSpeeds();
      notifyListeners();
    }
  }

  /// Записать удачный замер. Возвращает, засчитан ли он.
  ///
  /// ОДНА запись на оба пути (живой канал и харнесс): разъедься они, и один из
  /// путей однажды перестал бы сохранять результат — а какой именно, стало бы
  /// видно только по жалобе «на телефоне скорость не запоминается».
  bool _recordSpeed(VpnServer s, SpeedResult res) {
    if (!res.ok) {
      AppLog.w('Скорость «${s.displayName}»: ${res.error}');
      return false;
    }
    _speeds[s.key] = ServerSpeed(
      mbps: res.bitsPerSecond / 1000000,
      measuredAt: DateTime.now(),
    );
    return true;
  }

  Future<void> _persistSpeeds() async {
    await _speedStore.save({
      for (final e in _speeds.entries) e.key: e.value.toJson(),
    });
  }

  static bool _isHy2(VpnServer s) => s.protocol == 'hysteria2';

  static bool _hasFullConfig(VpnServer s) =>
      (s.rawJsonOverride ?? '').isNotEmpty || (s.rawPanelConfig ?? '').isNotEmpty;

  /// Сервер без осмысленного одиночного TCP-адреса: hysteria2 (QUIC) и полные
  /// конфиги (профиль «Авто …» — это балансировщик; json:// — адрес может быть
  /// `config:0`). Такие НЕ пингуем по TCP: адрес одного узла ничего не значит,
  /// а по нему сервер ошибочно попадал в «мёртвые». Только через прокси.
  static bool _proxyLatency(VpnServer s) => _isHy2(s) || _hasFullConfig(s);

  /// Метод верификации: HEAD, если пользователь выбрал его в настройках; иначе GET.
  static bool _verifyHead(AppSettings s) =>
      s.pingPrimary == PingMethod.proxyHead ||
      s.pingFallback == PingMethod.proxyHead;

  Future<void> _pingBatch(List<VpnServer> servers, AppSettings settings) async {
    // Замер скорости держит харнесс и те же локальные порты — начинать пинг
    // поверх него значит отобрать порт у идущего прогона.
    if (_running || _speedRunning || servers.isEmpty) return;
    _running = true;
    _batch = List.unmodifiable(servers);
    _batchKeys = {for (final s in servers) s.key};
    _done.clear();
    _lastSummary = null;
    // ⚠️ ПОМЕТКА СНИМАЕТСЯ ТОЛЬКО С СЕРВЕРОВ ЭТОГО ПРОГОНА, А НЕ ЦЕЛИКОМ.
    // Раньше здесь стояло `_unfinished = const {}`, и через эту строку проходит
    // ТАКЖЕ перепроверка одной строки (`pingOne` — тот же `_pingBatch`).
    // Обычный сценарий: отменил прогон на сотне серверов → ткнул в одну строку
    // «перепроверь» → пометка стёрлась вся, и счётчик снова выдавал
    // недосчитанный итог за законченный вердикт.
    //
    // Снимаем сразу, а не в конце прогона: иначе счётчик всё время нового
    // прогона носил бы клеймо старой отмены.
    _unfinished = {
      for (final k in _unfinished)
        if (!_batchKeys.contains(k)) k,
    };
    // Прогон, упавший с исключением, так же неполон, как отменённый: часть
    // серверов проверить не успели. Пишем один флаг на оба случая — снаружи
    // разницы нет, а «4 из 101» без пометки одинаково врёт и там, и там.
    var interrupted = false;
    final cancel = _cancel = CancelToken();
    for (final s in servers) {
      _results[s.key] = PingResult.testing;
    }
    notifyListeners();

    final sw = Stopwatch()..start();
    final timeout = Duration(milliseconds: settings.pingTimeoutMs);
    final twoPhase = settings.pingTwoPhase;
    final method = settings.pingPrimary;
    // При отжатой галочке работает ОДИН выбранный метод (TCP/ICMP/GET/HEAD).
    final proxySingle = !twoPhase &&
        (method == PingMethod.proxyGet || method == PingMethod.proxyHead);
    final icmpSingle = !twoPhase && method == PingMethod.icmp;
    // GET/HEAD для прокси-фазы: двухфазный — из настроек; одиночный прокси — по
    // методу; иначе (добивание hy2/профилей при TCP/ICMP) — обычный GET.
    final head = twoPhase
        ? _verifyHead(settings)
        : (proxySingle ? method == PingMethod.proxyHead : false);
    // ⚠️ ВНУТРИ try. Раньше строка стояла выше него, и на платформе без ICMP
    // (Android — сырые сокеты без root недоступны) `createIcmpPinger()`
    // бросал ДО входа в try: `finally` не отрабатывал, `_running` оставался
    // `true` навсегда, и пинг больше не запускался до перезапуска приложения.
    // В интерфейсе метод скрыт, но значение персистится и приезжает из чужого
    // файла настроек — на Android этого достаточно, чтобы получить дефект.
    try {
      final icmp = icmpSingle ? createIcmpPinger() : null;
      AppLog.i('Пинг: ${servers.length} серверов — '
          '${twoPhase ? "TCP + проверка ${head ? "HEAD" : "GET"}" : "метод ${method.name}"}');

      // ── ФАЗА 1: измерение выбранным методом. Кто не ответил (TCP/ICMP) — «мёртв».
      //    hysteria2/полные конфиги и режим «через прокси» уходят сразу в фазу 2.
      final survivors = <VpnServer>[]; // ответили по TCP (для двухфазной проверки)
      final proxyPlain = <VpnServer>[]; // обычные, но меряются через прокси (GET/HEAD)
      final noTcp = <VpnServer>[]; // hy2/профили — только через прокси
      final pool = Pool(settings.pingConcurrency);
      await Future.wait([
        for (final s in servers)
          pool.run(() async {
            if (cancel.isCancelled) return;
            if (_proxyLatency(s)) {
              noTcp.add(s);
              return;
            }
            if (proxySingle) {
              proxyPlain.add(s);
              return;
            }
            if (icmp != null) {
              final r = await icmp.ping(s.address, timeout: timeout);
              // ⚠️ ICMP-ответ НЕ доказывает, что сервер проксирует (часто это
              // вообще ближайший узел CDN). Раньше здесь ставилось «рабочий» —
              // плашка зеленела по эху. Проверки не было — значит `notRun`.
              _results[s.key] = PingResult(
                outcome: r.outcome,
                latencyMs: r.latencyMs,
                lossPct: r.lossPct,
                verification: PingVerification.notRun,
                latencyMethod: PingMethod.icmp,
                measuredAt: DateTime.now(),
              );
              _done.add(s.key);
              notifyListeners();
              return;
            }
            final r = await TcpPing.measure(s.address, s.port, timeout: timeout);
            if (r.outcome == PingOutcome.ok) {
              // ⚠️ ЗДЕСЬ БЫЛ ГЛАВНЫЙ ОБМАН: сервер помечался «рабочим» авансом,
              // по признаку `twoPhase && proxyProbeSupported` — то есть «фаза 2
              // БУДЕТ», а не «фаза 2 ПРОШЛА». Плашка зеленела сразу после TCP и
              // держалась зелёной всю фазу 2 (самую долгую), в том числе на
              // сервере, через который не работало ничего.
              //
              // TCP-ответ говорит ровно одно: порт открыт — а на типичном
              // Reality-порту он открыт всегда. Поэтому итог проверки ставится
              // отдельно: `pending`, если фаза 2 будет, иначе `notRun`.
              final willVerify = twoPhase && proxyProbeSupported;
              _results[s.key] = PingResult(
                outcome: PingOutcome.ok,
                latencyMs: r.latencyMs,
                verification: willVerify
                    ? PingVerification.pending
                    : PingVerification.notRun,
                latencyMethod: PingMethod.tcp,
                measuredAt: DateTime.now(),
              );
              survivors.add(s);
              // Без фазы 2 сервер уже финализирован; иначе «сделан» — после GET/HEAD.
              if (!twoPhase) _done.add(s.key);
            } else {
              _results[s.key] = PingResult(
                outcome: PingOutcome.failed,
                latencyMethod: PingMethod.tcp,
                measuredAt: DateTime.now(),
              );
              _done.add(s.key); // мёртв — дальше не проверяем
            }
            notifyListeners();
          }),
      ]);

      // ── ФАЗА 2: проба через прокси. Для hy2/профилей — всегда; для TCP-выживших —
      //    при двухфазности; для обычных — при одиночном методе GET/HEAD.
      final verify = <VpnServer>[
        ...noTcp,
        if (twoPhase) ...survivors,
        ...proxyPlain,
      ];
      // ── АКТИВНЫЙ СЕРВЕР ПРИ ЖИВОМ КАНАЛЕ — ЧЕРЕЗ ЖИВОЕ ЯДРО, НЕ ЧЕРЕЗ ХАРНЕСС.
      //
      // ⚠️ ЭТО И ЕСТЬ «НАСТОЯЩАЯ» ПРОВЕРКА, О КОТОРОЙ ПРОСИЛ ВЛАДЕЛЕЦ: «как
      // если бы юзер включил VPN, зашёл на сайт, и у него загрузилось или нет».
      // Харнесс — отдельный процесс ядра с голым конфигом: без правил
      // пользователя, без его DNS, без блокировок. Он проходил там, где боевое
      // подключение не работает, — и ровно это объясняло жалобу: плашка пинга
      // зелёная (достучался харнесс), а сервис-чипы под кнопкой Connect в тот
      // же момент красные (они всегда ходили через живое ядро). Теперь
      // подключённый сервер проверяется тем же путём, что и трафик браузера.
      //
      // ⚠️ Ровно один сервер — подключённый. Через живой канал идёт трафик
      // ТЕКУЩЕГО узла: для остальных такая проба измеряла бы чужой канал и
      // выдала бы одинаковые цифры всему списку.
      final live = _liveTargetIn(verify);
      if (live != null && !cancel.isCancelled) {
        verify.remove(live.server);
        AppLog.i('Проверка «${live.server.remark}»: через ЖИВОЕ ядро '
            '(127.0.0.1:${live.port}) — тем же путём, что идёт обычный трафик');
        await _applyVerify(live.server, live.port, settings,
            head: head, forceProxy: proxySingle);
      }

      // Платформа без харнесса (Android): проверить «реально ли проксирует»
      // нечем — второй экземпляр ядра рядом с живым туннелем не поднять.
      // Оставляем результат одной фазы вместо падения всего пинга: раньше
      // здесь вылетал UnsupportedError и обнулял проверку всех серверов.
      if (verify.isNotEmpty && !proxyProbeSupported) {
        for (final s in verify) {
          if (cancel.isCancelled) break;
          if (noTcp.contains(s)) {
            // Профили «Авто» и hysteria2 без пробы подтвердить нечем: TCP до
            // одного узла из десятков ничего не значит, а у QUIC его и нет.
            _results[s.key] = PingResult(
              outcome: PingOutcome.untested,
              verification: PingVerification.notRun,
              latencyMethod: settings.pingPrimary,
            );
          }
        }
        // Строка условная намеренно: журнал, обещающий проверку, которой не
        // было, дороже отсутствующей строки — по нему потом ищут причину.
        AppLog.i('Проба через прокси: харнесса нет, не проверено '
            '${verify.length}'
            '${live != null ? " (подключённый сервер проверен по живому каналу)" : ""}');
        notifyListeners();
      } else if (verify.isNotEmpty && !cancel.isCancelled) {
        // Полный конфиг (правка/профиль «Авто …») — своим харнессом: у него свои
        // теги и балансировщик, в общий мешать нельзя (#8.2).
        final shared = <VpnServer>[];
        final ownConfig = <VpnServer>[];
        for (final s in verify) {
          (_hasFullConfig(s) ? ownConfig : shared).add(s);
        }
        AppLog.i('Проба через прокси ${verify.length} '
            '(общий ${shared.length}, свой конфиг ${ownConfig.length})');
        await _verifyShared(shared, settings, cancel,
            head: head, forceProxy: proxySingle);
        for (final s in ownConfig) {
          if (cancel.isCancelled) break;
          await _verifyOne(s, settings, cancel,
              head: head, forceProxy: proxySingle);
        }
      }

      final ok = _goodCount(servers);
      // ⚠️ Слово подбирается по ФАКТУ проверки, а не по галочке в настройках:
      // «рабочих» — только когда проба через сервер реально была. Иначе итог
      // обещал бы проверку, которой не делали.
      final word = _anyVerified(servers) ? 'рабочих' : 'доступных';
      _lastSummary = cancel.isCancelled
          ? 'Пинг отменён: $word $ok из ${servers.length}'
          : 'Пинг завершён: $word $ok из ${servers.length} '
              '(${sw.elapsed.inSeconds} с)';
      AppLog.i('Пинг: $word $ok из ${servers.length} за '
          '${sw.elapsed.inSeconds} с');
    } catch (e) {
      interrupted = true;
      _lastSummary = 'Пинг прерван ошибкой';
      AppLog.e('Пинг: сбой — $e');
    } finally {
      // Кого прогон не успел проверить — считаем ДО очистки состояния: только
      // здесь ещё известны и состав прогона, и то, до кого он дошёл.
      //
      // ⚠️ ДОПОЛНЯЕМ, А НЕ ПЕРЕЗАПИСЫВАЕМ: своих серверов в пометке уже нет
      // (сняты на входе), а чужие — недостигнутые прошлыми прогонами — остаются
      // в силе, их этот прогон не касался. Законченный прогон сюда не заходит
      // вовсе: снятия на входе достаточно.
      if (interrupted || cancel.isCancelled) {
        _unfinished = {
          ..._unfinished,
          for (final s in servers)
            if (!_done.contains(s.key)) s.key,
        };
      }
      // ⚠️ НЕПРОВЕРЕННОЕ ОСТАЁТСЯ НЕПРОВЕРЕННЫМ. Раньше здесь всё, что не успело
      // измериться, переводилось в `failed` — при отмене прогона или падении
      // харнесса живые серверы красились в красное «n/a» И ТАКИМИ СОХРАНЯЛИСЬ на
      // диск, а красный человек читает как «не подключайся сюда».
      for (final s in servers) {
        final r = _results[s.key];
        if (r == null) continue;
        if (r.outcome == PingOutcome.testing) {
          // Замера не было вовсе: `untested` не терминален и на диск не поедет.
          _results[s.key] = PingResult.untested;
        } else if (r.verification == PingVerification.pending) {
          // Замер есть, проверка не завершилась. Оставить `pending` нельзя:
          // прогон окончен, а плашка вечно показывала бы «проверяю».
          _results[s.key] = r.withVerification(PingVerification.notRun);
        }
      }
      _running = false;
      _finishedAt = DateTime.now();
      await _persist();
      await _persistUnfinished();
      notifyListeners();
    }
  }

  /// Подключённый сейчас сервер из списка [servers] и порт его ЖИВОГО ядра.
  /// `null` — живого канала нет либо подключён сервер не из этого прогона.
  ///
  /// ⚠️ «ЖИВОЙ», А НЕ «ПОДКЛЮЧАЕТСЯ»: [liveProxyPort] отдаёт порт только при
  /// состоянии «Подключено» и 0 во всех остальных (см. `home_screen`). Пока
  /// канал поднимается, порт уже слушает, но никуда не доставляет — проба
  /// через него дала бы ложный провал (на этом уже горели сервис-чипы, см.
  /// историю 1.0.2). Ноль здесь трактуем как «живого канала нет».
  ({VpnServer server, int port})? _liveTargetIn(List<VpnServer> servers) {
    final port = liveProxyPort?.call() ?? 0;
    final key = activeServerKey?.call();
    if (port <= 0 || key == null || key.isEmpty) return null;
    for (final s in servers) {
      if (s.key == key) return (server: s, port: port);
    }
    return null;
  }

  /// Боевые настройки, влияющие на достижимость мишени, — в конфиг харнесса.
  ///
  /// ⚠️ Правила по ПРИЛОЖЕНИЯМ сюда не попадают, и это не забывчивость: у
  /// соединения, пришедшего в локальный прокси, нет процесса-владельца —
  /// сопоставлять ядру не с чем (по той же причине правила приложений не
  /// работают у системного прокси Windows).
  static HarnessRealism _realismFor(AppSettings s) {
    // Свой резолвер — единственная DNS-настройка, которая способна СЛОМАТЬ
    // открытие сайта: режимы «системный» и «через VPN» в харнессе и так
    // воспроизводятся (имя резолвит сервер на своей стороне).
    var dns = '';
    if (s.dnsMode == DnsMode.custom) {
      final raw = s.dnsCustomServer.trim();
      // Только адрес: строку вида `https://dns.example/query` Xray не примет, а
      // конфиг, который ядро отвергло, — это ноль проверенных серверов.
      if (InternetAddress.tryParse(raw) != null) dns = raw;
    }
    // Ограничивающие стратегии переносим, «предпочитать» — нет: предпочтение
    // ничего не запрещает, а лишняя dns-секция меняла бы конфиг всем подряд.
    final strategy = switch (s.dnsStrategy) {
      DnsStrategy.ipv4Only => 'UseIPv4',
      DnsStrategy.ipv6Only => 'UseIPv6',
      DnsStrategy.preferIpv4 || DnsStrategy.preferIpv6 => null,
    };
    return HarnessRealism.fromRules(s.splitTunnel,
        dnsServer: dns, queryStrategy: strategy);
  }

  /// Сколько серверов в прогоне «хорошие».
  ///
  /// ⚠️ Считается по [PingResult.verification], а не по авансовому флагу.
  /// Раньше итог брался из `isWorking`, а он до фазы 2 стоял по признаку «будет
  /// ли проверка»: при ВЫКЛЮЧЕННОЙ двухфазности каждый прогон заканчивался
  /// «рабочих 0 из N» на полностью живой подписке. Проверка не проводилась —
  /// значит судим по достижимости, а не выдумываем провал.
  int _goodCount(List<VpnServer> servers) => servers.where((s) {
        final r = _results[s.key];
        if (r == null) return false;
        return r.isWorking || r.isReachableUnverified;
      }).length;

  /// Была ли в этом прогоне хоть одна настоящая проба через сервер.
  bool _anyVerified(List<VpnServer> servers) => servers.any((s) {
        final v = _results[s.key]?.verification;
        return v == PingVerification.passed || v == PingVerification.failed;
      });

  /// Проба группы серверов через прокси на одном общем харнессе.
  Future<void> _verifyShared(
      List<VpnServer> servers, AppSettings settings, CancelToken cancel,
      {required bool head, required bool forceProxy}) async {
    if (servers.isEmpty) return;
    HarnessHandle? handle;
    try {
      final realism = _realismFor(settings);
      final entries = [
        for (final s in servers)
          HarnessEntry(
              key: s.key,
              server: s,
              variant: _variantOf(s),
              realism: realism),
      ];
      handle = await _harnessFactory().start(entries);

      final pool = Pool(settings.pingConcurrency);
      final futures = <Future<void>>[];
      for (var i = 0; i < servers.length; i++) {
        final idx = i;
        final server = servers[i];
        futures.add(pool.run(() async {
          if (cancel.isCancelled) return;
          // -1 = кандидата обслуживало второе ядро, а оно не поднялось.
          final raw = handle?.proxyPortFor(idx);
          final port = (raw == null || raw <= 0) ? null : raw;

          // ⚠️ Платформа может померить САМА и порта не дать: на Android
          // `LibXray.ping` поднимает свой экземпляр ядра и возвращает сразу
          // миллисекунды, поэтому `proxyPortFor` там ВСЕГДА 0.
          //
          // Без этой ветки каждый сервер уходил в `_applyVerify` с port == null
          // и помечался «отвечает по TCP, но не проксирует» — то есть ВЕСЬ
          // список красился в нерабочий, включая заведомо живые серверы,
          // которыми пользователь в этот момент пользовался. В `_verifyOne`
          // (полные конфиги, профили «Авто») то же самое было учтено, а здесь —
          // на пути, по которому идут ОБЫЧНЫЕ серверы, то есть почти все, — нет.
          if (port == null) {
            final ready = await handle?.delayMs(idx);
            if (cancel.isCancelled) return;
            if (ready != null) {
              // Замер сделан ЧЕРЕЗ поднятое ядро (LibXray) — это и есть проба,
              // а не TCP-рукопожатие: состояние `passed` здесь заслуженное.
              _results[server.key] = PingResult(
                outcome: PingOutcome.ok,
                latencyMs: ready,
                proxyRttMs: ready,
                reachableViaProxy: true,
                verification: PingVerification.passed,
                latencyMethod: settings.pingPrimary,
                measuredAt: DateTime.now(),
              );
              _done.add(server.key); // иначе полоска прогресса не доходит до конца
              notifyListeners();
              return;
            }
          }
          await _applyVerify(server, port, settings,
              head: head,
              forceProxy: forceProxy,
              proxyUser: handle?.proxyUser,
              proxyPassword: handle?.proxyPassword);
        }));
      }
      await Future.wait(futures);
    } finally {
      await handle?.stop();
    }
  }

  /// Проба одного сервера с полным JSON-конфигом на отдельном харнессе (#8.2).
  Future<void> _verifyOne(
      VpnServer server, AppSettings settings, CancelToken cancel,
      {required bool head, required bool forceProxy}) async {
    HarnessHandle? handle;
    try {
      handle = await _harnessFactory().start([
        HarnessEntry(
            key: server.key,
            server: server,
            variant: _variantOf(server),
            realism: _realismFor(settings)),
      ]);
      final rawPort = handle.proxyPortFor(0);
      final port = rawPort <= 0 ? null : rawPort;
      if (cancel.isCancelled) return;
      // Платформа может померить сама и порта не дать (Android: LibXray.ping
      // возвращает миллисекунды). Тогда ходить через прокси нечем и незачем.
      final ready = port == null ? await handle.delayMs(0) : null;
      if (cancel.isCancelled) return;
      if (port == null && ready != null) {
        // Как и в `_verifyShared`: цифру дало ядро, поднятое ради этой пробы, —
        // проверка состоялась.
        _results[server.key] = PingResult(
          outcome: PingOutcome.ok,
          latencyMs: ready,
          proxyRttMs: ready,
          reachableViaProxy: true,
          verification: PingVerification.passed,
          latencyMethod: settings.pingPrimary,
          measuredAt: DateTime.now(),
        );
        _done.add(server.key);
        notifyListeners();
        return;
      }
      await _applyVerify(server, port, settings,
          head: head,
          forceProxy: forceProxy,
          proxyUser: handle.proxyUser,
          proxyPassword: handle.proxyPassword);
    } finally {
      await handle?.stop();
    }
  }

  /// GET/HEAD через прокси-порт и запись итога. Обычно показываемая цифра остаётся
  /// TCP; для серверов без TCP (hysteria2, полный конфиг) и при одиночном методе
  /// «через прокси» ([forceProxy]) — RTT пробы: другого числа нет.
  Future<void> _applyVerify(VpnServer s, int? port, AppSettings settings,
      {required bool head,
      required bool forceProxy,
      // Креды ИМЕННО ЭТОГО порта. `null` — живое ядро, у него свои сессионные
      // (ProxyProbe.user/password). У харнесса пароль свой, на прогон, и
      // подставить сюда сессионный значило бы получить 407 на каждом сервере.
      String? proxyUser,
      String? proxyPassword}) async {
    final proxyLat = _proxyLatency(s) || forceProxy;
    try {
      if (port == null) {
        // ⚠️ «НЕ ПРОВЕРЕН» И «МЁРТВ» — РАЗНЫЕ НОВОСТИ, И ПУТАТЬ ИХ НЕЛЬЗЯ.
        //
        // Порт `null` значит «замерить нечем» (харнесс не поднялся, ядро
        // кандидата не стартовало, платформа так не умеет), а не «сервер не
        // отвечает» и не «сервер не проксирует». На Android харнесс не умеет
        // hysteria2 вовсе (`ProbeHarnessAndroid` кладёт для него null), и
        // заведомо рабочий сервер красился в красное «n/a»; обычный сервер при
        // упавшем харнессе получал «отвечает, но не проксирует» — оба вердикта
        // выдуманные. Красный человек читает как «не подключайся сюда» и
        // послушно уходит на худший узел.
        //
        // Пробы НЕ БЫЛО ⇒ `notRun`. Число TCP при этом сохраняем: оно измерено.
        _results[s.key] = proxyLat
            ? PingResult(
                // TCP-цифры у таких серверов нет вовсе — показывать нечего.
                outcome: PingOutcome.untested,
                verification: PingVerification.notRun,
                latencyMethod: settings.pingPrimary,
                measuredAt: DateTime.now(),
              )
            : PingResult(
                outcome: PingOutcome.ok,
                latencyMs: _results[s.key]?.latencyMs,
                verification: PingVerification.notRun,
                latencyMethod: PingMethod.tcp,
                measuredAt: _results[s.key]?.measuredAt ?? DateTime.now(),
              );
        notifyListeners();
        return;
      }

      final probe = await ProxyProbe.check(
        port,
        settings.testUrl,
        head: head,
        timeout: Duration(milliseconds: settings.pingTimeoutMs),
        proxyUser: proxyUser,
        proxyPassword: proxyPassword,
      );
      // Проба состоялась — вот теперь вердикт настоящий.
      final verdict =
          probe.ok ? PingVerification.passed : PingVerification.failed;
      if (proxyLat) {
        _results[s.key] = PingResult(
          outcome: probe.ok ? PingOutcome.ok : PingOutcome.failed,
          latencyMs: probe.rttMs, // TCP нет — показываем RTT пробы
          proxyRttMs: probe.rttMs,
          verification: verdict,
          reachableViaProxy: probe.ok,
          latencyMethod: head ? PingMethod.proxyHead : PingMethod.proxyGet,
          measuredAt: DateTime.now(),
        );
      } else {
        _results[s.key] = PingResult(
          outcome: PingOutcome.ok, // TCP уже подтвердил достижимость
          latencyMs: _results[s.key]?.latencyMs, // показываем TCP
          proxyRttMs: probe.rttMs,
          verification: verdict,
          reachableViaProxy: probe.ok,
          latencyMethod: PingMethod.tcp,
          measuredAt: DateTime.now(),
        );
      }
      notifyListeners();
    } finally {
      // Проба завершена — этот сервер «сделан» (для прогресс-полоски).
      _done.add(s.key);
    }
  }
}
