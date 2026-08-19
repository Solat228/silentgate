import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/platform/app_log.dart';
import '../../../core/platform/app_paths.dart';
import '../../../core/platform/interference_scanner.dart';
import '../../../core/settings/split_tunnel.dart';
import '../../../core/singbox/singbox_config_builder.dart';
import '../../../core/singbox/tun_autotune.dart';
import '../../../data/tun_tuning_store.dart';
import '../elevation.dart';
import 'app_alive_mutex.dart';
import 'tun_helper.dart';
import 'tun_router.dart';
import 'tun_scheduled_task.dart';

/// Windows-реализация TUN-роутера на sing-box: пишет конфиг и поднимает элевейтнутый
/// хелпер, который запускает sing-box (wintun + маршрутизация) и заворачивает
/// прокси-трафик в локальный SOCKS Xray. Остановка — через stop-файл.
///
/// Права: сначала пробуем задачу Планировщика (без UAC), иначе — прямой UAC-запуск.
/// После старта ОБЯЗАТЕЛЬНО проверяем, что туннель реально поднялся: раньше сбой
/// sing-box был невидим и приложение показывало «Подключено» без туннеля.
class SingboxRouterWindows implements TunRouter {
  bool _started = false;
  String _stopPath = '';

  /// Выходы мульти-VPN текущей сессии.
  ///
  /// ⚠️ Держим полями, а не тащим через параметры `_startOnce`: автоподбор
  /// стека и MTU переcобирает конфиг до девяти раз, и забытый аргумент в одной
  /// из веток дал бы туннель БЕЗ выходов — при этом рабочий. Такой дефект
  /// проявился бы только на второй комбинации, то есть у части пользователей.
  List<Map<String, dynamic>> _exitOutbounds = const [];
  String _socksUser = '';
  String _socksPassword = '';

  /// Ключи серверов с отдельным портом API и сам токен — те же поля, что и
  /// остальные параметры сессии (см. комментарий у [_exitOutbounds]): держим
  /// полями, а не тащим через параметры `_startOnce`, по той же причине.
  List<String> _apiExitServerKeys = const [];

  /// Из [_apiExitServerKeys] — те, чей outbound живёт ТОЛЬКО ради порта, и
  /// правилам раздельного туннелирования не адресат (см.
  /// `SingboxConfigBuilder.apiOnlyExitKeys`).
  List<String> _apiOnlyExitKeys = const [];
  String _apiToken = '';

  @override
  Future<void> start(SplitTunnelConfig split,
      {required int xraySocksPort,
      required TunOptions options,
      void Function(String message)? onProgress,
      bool Function()? abort,
      List<Map<String, dynamic>> exitOutbounds = const [],
      String xraySocksUser = '',
      String xraySocksPassword = '',
      List<String> apiExitServerKeys = const [],
      List<String> apiOnlyExitKeys = const [],
      String apiToken = ''}) async {
    _prime(
      exitOutbounds: exitOutbounds,
      xraySocksUser: xraySocksUser,
      xraySocksPassword: xraySocksPassword,
      apiExitServerKeys: apiExitServerKeys,
      apiOnlyExitKeys: apiOnlyExitKeys,
      apiToken: apiToken,
    );
    // «Авто» — реальный подбор: перебираем стек и MTU, пока туннель не поднимется.
    // Явно выбранный стек уважаем и ничего не перебираем.
    if (!options.autotune) {
      await _startOnce(split, xraySocksPort, options, abort: abort);
      return;
    }

    final store = TunTuningStore();
    final combos = TunAutotune.combos(
      preferred: await store.load(),
      baseMtu: options.mtu,
    );

    TunStartException? last;
    for (var i = 0; i < combos.length; i++) {
      // Пользователь отключился, пока шёл перебор — прекращаем, НЕ поднимаем ещё
      // одну комбинацию (иначе туннель встанет уже после «Отключить»).
      if (abort?.call() ?? false) {
        AppLog.i('TUN автоподбор прерван (отключение пользователем)');
        return;
      }
      final c = combos[i];
      final attempt = options.copyWith(stack: c.stack, mtu: c.mtu);
      onProgress?.call('Подбираю параметры TUN: ${c.label} '
          '(${i + 1} из ${combos.length})');
      AppLog.i('TUN автоподбор: пробую ${c.label}');
      try {
        await _startOnce(split, xraySocksPort, attempt, abort: abort);
        // Успели подняться, но пользователь уже отключился — снимаем сразу.
        if (abort?.call() ?? false) {
          AppLog.i('TUN поднялся после отмены — снимаю');
          await stop();
          return;
        }
        AppLog.i('TUN автоподбор: заработало на ${c.label}');
        await store.save(c); // в следующий раз пробуем это первым
        return;
      } on TunElevationDenied {
        // Прав нет — перебирать стеки бессмысленно: без администратора не
        // поднимется ни одна комбинация. Раньше цикл шёл дальше и запрашивал
        // права ЗАНОВО на каждой из девяти: пользователь получал девять окон
        // UAC подряд, а при зависшем запросе — три минуты «Подключение…» без
        // единого признака жизни.
        rethrow;
      } on TunStartException catch (e) {
        last = e;
        AppLog.w('TUN автоподбор: ${c.label} не подошло');
      }
    }
    throw TunStartException(
      'Туннель не поднялся ни на одной из ${combos.length} комбинаций '
      'стека и MTU.\n${last?.message ?? ""}',
      details: last?.details ?? '',
    );
  }

  /// Одна попытка запуска с конкретными параметрами.
  Future<void> _startOnce(SplitTunnelConfig split, int xraySocksPort,
      TunOptions options, {bool Function()? abort}) async {
    final dir = await AppPaths.supportDir();
    final cfgPath = TunHelper.configPathFor(dir);
    await File(cfgPath).writeAsString(configJsonFor(split, xraySocksPort, options));

    // ⚠️ ПРИЗНАК «ИНТЕРФЕЙС ЖИВ» — ДО ЗАПУСКА ПОМОЩНИКА, А НЕ ПОСЛЕ.
    //
    // Помощник читает имя один раз, на старте. Положив файл позже, мы получили
    // бы помощника без слежения — то есть ровно того, кто переживёт падение
    // приложения и оставит блокировку стоять.
    //
    // Мьютекс берётся один раз на всю жизнь процесса и не отпускается: он и
    // есть признак жизни. Пустое имя (взять не удалось) записываем тоже —
    // помощник тогда честно скажет в журнал, что следить ему не за чем.
    final aliveName = AppAliveMutex.acquire();
    try {
      await File(TunHelper.aliveFilePathFor(dir)).writeAsString(aliveName);
    } catch (e) {
      AppLog.w('Не удалось передать помощнику признак жизни интерфейса: $e');
    }

    _stopPath = TunHelper.stopFilePathFor(dir);
    // ⚠️ НЕ СТИРАЕМ stop-ФАЙЛ, А ЖДЁМ, ПОКА ЕГО ЗАБЕРЁТ ПРОШЛЫЙ ХЕЛПЕР.
    //
    // Здесь стоял `clearStopAt`, и он же был причиной гонки: неудачная
    // комбинация автоподбора ставит stop-файл, а следующая стирала его раньше,
    // чем хелпер успевал прочитать (он смотрит раз в 400 мс, окно замерено в
    // 393–515 мс). Промах = живой хелпер, которого больше никто не остановит.
    // Разбор — `docs/BACKLOG.md` #32.
    if (!await TunHelper.waitStopConsumed(_stopPath)) {
      // Никто не забрал за пять секунд: прошлого хелпера, скорее всего, и не
      // было (права не дали, задача не запустилась). Файл убираем сами — иначе
      // он убьёт СЛЕДУЮЩИЙ хелпер сразу после старта.
      AppLog.w('stop-файл TUN никто не забрал за 5 с — убираю сам. '
          'Если прошлый помощник всё же жив, он останется работать.');
      TunHelper.clearStopAt(_stopPath);
    }
    // ⚠️ ЛОГ ЗДЕСЬ НЕ ОБРЕЗАЕТСЯ. И В `TunHelper.run` ТОЖЕ БОЛЬШЕ НЕ ОБРЕЗАЕТСЯ.
    //
    // Раньше здесь стоял `_truncateLog`: обрезка ИЗ ЭТОГО процесса файла,
    // который открытым на дозапись держит ДРУГОЙ (элевейтнутый хелпер). Его
    // `IOSink` помнит смещение с момента открытия и после обрезки продолжает
    // писать по старому адресу — Windows заполняет пропуск нулями. У владельца
    // так набралось 1 048 209 нулевых байт (69 %) в `singbox.log`.
    //
    // ⚠️ Переезд обрезки в хелпер вылечил нули, но породил вторую беду: каждая
    // попытка подъёма стирала лог. А `_startOnce` зовётся до ДЕВЯТИ раз подряд
    // (автоподбор стека и MTU) и ещё раз на каждом восстановлении после
    // обрыва — то есть журнал аварии уничтожался ответом на эту же аварию.
    // Теперь лог НАКАПЛИВАЕТСЯ с ротацией (`RotatingLog(keepPrevious: true)`),
    // и обрезать его отсюда нельзя тем более.

    // ⚠️ ЗАДАЧУ СНАЧАЛА СВЕРЯЕМ, А ПОТОМ ЗАПУСКАЕМ. Она создаётся один раз и
    // не пересматривается: у владельца живёт задача от 20.07.2026, ведущая в
    // папку сборки и без путей конфига. Запустив такую, мы подняли бы ЧУЖОЙ
    // (старый) бинарь под правами администратора и читали бы не тот конфиг —
    // а в журнале это выглядело бы как обычный успешный старт.
    //
    // Устаревшая задача не чинится молча: пересоздание требует UAC, и
    // выпрашивать его при каждом подключении хуже, чем один раз сказать
    // словами. Поэтому просто идём запасным путём и пишем причину.
    final taskExists = await TunScheduledTask.exists();
    final taskCurrent = taskExists && await TunScheduledTask.isCurrent();
    if (taskExists && !taskCurrent) {
      AppLog.w('Задача Планировщика «${TunScheduledTask.taskName}» устарела — '
          'она запускает другой файл или другие пути. Поднимаю туннель обычным '
          'путём (спросит права). Пересоздать: настройки → «TUN и '
          'маршрутизация» → запуск без UAC.');
    }
    final viaTask = taskCurrent && await TunScheduledTask.run();
    if (!viaTask) {
      // Fallback: разовый UAC-запуск хелпера. Если приложение уже возвышено,
      // окна UAC не будет вовсе — хелпер стартует напрямую (см. Elevation).
      final ok = await Elevation.runElevatedAsync(
        Platform.resolvedExecutable,
        '--tun "$cfgPath" "$_stopPath"',
      );
      if (!ok) {
        throw TunElevationDenied(
          'Не удалось получить права администратора для TUN (UAC отклонён).\n'
          'Чтобы больше не спрашивало — настройте запуск без UAC в разделе «TUN и маршрутизация».',
        );
      }
    }
    _started = true;

    await _waitUp(abort: abort);
  }

  /// Конфиг, который реально уйдёт в файл для sing-box.
  ///
  /// ⚠️ Вынесен ОТДЕЛЬНО от [_startOnce] (который дальше запрашивает права и
  /// стартует процесс), чтобы тест мог проверить РЕАЛЬНО СОБИРАЕМЫЙ роутером
  /// конфиг — а не тот, что собран в тесте вручную мимо этого класса. Именно
  /// так был пропущен API: `SingboxConfigBuilder` умел `apiExitServerKeys`/
  /// `apiToken`, но здесь, в единственном месте на Windows, где он реально
  /// вызывается, их никто не передавал — прямые тесты `SingboxConfigBuilder`
  /// этого не ловили, потому что собирали конфиг в обход роутера.
  @visibleForTesting
  String configJsonFor(
          SplitTunnelConfig split, int xraySocksPort, TunOptions options) =>
      SingboxConfigBuilder(
        xraySocksPort: xraySocksPort,
        // Без этих двух строк туннель уходит в SOCKS Xray без пароля и
        // получает 407 — «Подключено» при нулевом трафике.
        xraySocksUser: _socksUser,
        xraySocksPassword: _socksPassword,
        options: options,
        exitOutbounds: _exitOutbounds,
        apiExitServerKeys: _apiExitServerKeys,
        apiOnlyExitKeys: _apiOnlyExitKeys,
        apiToken: _apiToken,
      ).buildJson(split);

  /// Сохраняет параметры сессии в поля. Общий узел для [start] и
  /// [primeSessionForTest] — ОДИН код пути, а не два места, которые могут
  /// разойтись между собой.
  void _prime({
    required List<Map<String, dynamic>> exitOutbounds,
    required String xraySocksUser,
    required String xraySocksPassword,
    required List<String> apiExitServerKeys,
    required List<String> apiOnlyExitKeys,
    required String apiToken,
  }) {
    _exitOutbounds = exitOutbounds;
    _socksUser = xraySocksUser;
    _socksPassword = xraySocksPassword;
    _apiExitServerKeys = apiExitServerKeys;
    _apiOnlyExitKeys = apiOnlyExitKeys;
    _apiToken = apiToken;
  }

  /// Заполняет поля сессии, как это делает [start] — но без запроса прав и
  /// без запуска хелпера. ТОЛЬКО для тестов: [configJsonFor] обязан отражать
  /// реальные параметры сессии, которые прошли бы через настоящий [start], а
  /// не то, что тест соберёт мимо класса. Делегирует в [_prime] — тот же путь,
  /// которым идёт [start], поэтому расхождение между ними исключено.
  @visibleForTesting
  void primeSessionForTest({
    List<Map<String, dynamic>> exitOutbounds = const [],
    String xraySocksUser = '',
    String xraySocksPassword = '',
    List<String> apiExitServerKeys = const [],
    List<String> apiOnlyExitKeys = const [],
    String apiToken = '',
  }) =>
      _prime(
        exitOutbounds: exitOutbounds,
        xraySocksUser: xraySocksUser,
        xraySocksPassword: xraySocksPassword,
        apiExitServerKeys: apiExitServerKeys,
        apiOnlyExitKeys: apiOnlyExitKeys,
        apiToken: apiToken,
      );

  /// Ждём появления TUN-адаптера. Не появился — отдаём реальную причину из лога.
  /// ⚠️ [abort] ПРОВЕРЯЕТСЯ ВНУТРИ ЦИКЛА, А НЕ ТОЛЬКО СНАРУЖИ.
  ///
  /// Просьба владельца 20.08.2026: «сделай возможность отключения VPN до того,
  /// как он автоматически подключится, чтобы не ждать, пока подберутся
  /// параметры». Раньше отмена читалась только МЕЖДУ комбинациями автоподбора,
  /// а самое долгое ожидание — здесь: до двенадцати секунд на каждую из девяти.
  /// Нажав «Отключить» на первой же, человек ждал конца текущей попытки, и
  /// кнопка выглядела не нажатой.
  ///
  /// Возвращаемся МОЛЧА, без исключения: снаружи (в цикле подбора и в
  /// `WindowsEngine`) отмена и так проверяется сразу после вызова, и там же
  /// поднятое снимается. Бросать здесь ошибку значило бы показать человеку
  /// «не удалось подключиться» на действие, которое он сам и совершил.
  Future<void> _waitUp({bool Function()? abort}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      if (abort?.call() ?? false) {
        AppLog.i('Ожидание TUN-адаптера прервано: отключение пользователем');
        return;
      }
      if (await _adapterUp()) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    final log = await TunHelper.tailLog();
    _started = false;
    TunHelper.requestStopAt(_stopPath); // не оставляем полуживой процесс

    final conflict = await _conflictingTunnels();
    final hint = conflict.isNotEmpty
        ? 'Обнаружен другой активный VPN-туннель: ${conflict.join(', ')}.\n'
            'Два TUN-адаптера одновременно борются за маршрут по умолчанию — '
            'отключите другой VPN и попробуйте снова.\n\n'
        : '';
    throw TunStartException(
      'TUN-адаптер не поднялся за 12 секунд — sing-box не запустился.',
      details: hint +
          (log.isEmpty
              ? 'Лог sing-box пуст. Проверьте, что рядом с xray.exe лежат '
                  'sing-box.exe и wintun.dll.'
              : log),
    );
  }

  /// Чужие активные TUN-адаптеры (другой VPN-клиент) — частая причина, по которой
  /// наш туннель не поднимается или сеть умирает.
  Future<List<String>> _conflictingTunnels() async {
    try {
      final found = await InterferenceScanner.scan();
      return found
          .where((i) => i.kind == 'adapter')
          .map((i) => '${i.name} (${i.detail})')
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Появился ли наш TUN-адаптер.
  ///
  /// Берём ПОЛНЫЙ список интерфейсов и ищем своё имя подстрокой: фильтр `name=…`
  /// на локализованной Windows при отсутствии адаптера печатает ошибку с кодом 0,
  /// то есть давал бы ложный успех. Имя адаптера ASCII — локаль не мешает.
  Future<bool> _adapterUp() async {
    try {
      final r = await Process.run('netsh', ['interface', 'show', 'interface']);
      if ('${r.stdout}'.toLowerCase().contains('silentgate-tun')) return true;
    } catch (_) {
      // netsh недоступен (SRP, урезанный PATH) — ищем НАШ адрес туннеля.
      //
      // Раньше здесь проверялось «жив ли процесс sing-box.exe», но с v0.9.0 это
      // имя носят ещё прокси-ядро (hysteria2) и пинг-харнесс: признак срабатывал
      // бы на них, и приложение показывало бы «Подключено» без всякого туннеля,
      // пока трафик идёт напрямую. Адрес 172.19.0.1 принадлежит только нам.
      try {
        final ifaces = await NetworkInterface.list(
            includeLoopback: false, type: InternetAddressType.any);
        for (final i in ifaces) {
          for (final a in i.addresses) {
            if (a.address.startsWith('172.19.0.') ||
                a.address.toLowerCase().startsWith('fdfe:dcba:9876:')) {
              return true;
            }
          }
        }
      } catch (_) {}
    }
    return false;
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    TunHelper.requestStopAt(_stopPath.isNotEmpty
        ? _stopPath
        : TunHelper.stopFilePathFor(await AppPaths.supportDir()));
    _started = false;
  }
}
