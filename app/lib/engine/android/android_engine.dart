import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/models/vpn_server.dart';
import '../../core/models/vpn_status.dart';
import '../../core/platform/app_log.dart';
import '../../core/platform/app_paths.dart';
import '../../core/settings/split_tunnel.dart';
import '../../core/singbox/singbox_config_builder.dart';
import '../../core/singbox/singbox_outbound_factory.dart';
import '../engine_base.dart';

/// Движок Android: туннель поднимает `libbox` (sing-box) внутри
/// `SilentGateVpnService`.
///
/// Платформо-независимая половина (сессия, поколения, автовосстановление,
/// выбор конфига и ядра) живёт в [VpnEngineBase] и общая с Windows. Здесь
/// остаётся только мост к нативному сервису.
///
/// Дескриптор туннеля передаётся инверсией управления: ядро зовёт
/// `PlatformInterface.openTun`, сервис строит `VpnService.Builder` и
/// возвращает fd. Подробности — `tools/build-android-cores.md`.
///
/// ## Как выбирается ядро
///
/// Ровно как на Windows — через `configFor` в базе: полный конфиг (правка
/// пользователя или панельный профиль «Авто» с `balancers`/`burstObservatory`)
/// поднимает Xray, а туннель заворачивает трафик в его локальный SOCKS.
/// Обычный сервер sing-box обслуживает сам, и тогда промежуточный SOCKS не
/// нужен: outbound встраивается прямо в конфиг туннеля.
///
/// Оба ядра живут в ОДНОМ AAR: раздельные gomobile-библиотеки конфликтуют
/// общим Go-рантаймом (`go.Seq`), и собрать их вместе иначе нельзя
/// (`tools/build-android-cores.md`).
class AndroidEngine extends VpnEngineBase {
  AndroidEngine({super.ports}) {
    _events.receiveBroadcastStream().listen(_onNativeEvent);
  }

  static const _channel = MethodChannel('lol.silentgate/vpn');
  static const _events = EventChannel('lol.silentgate/vpn_events');

  /// Идёт ли сейчас наш собственный подъём: нужно, чтобы не принять
  /// подтверждение «сервис запущен» за неожиданное падение.
  bool _starting = false;

  /// Подхватить туннель, поднятый ПРОШЛЫМ запуском интерфейса.
  ///
  /// ⚠️ На Android интерфейс и туннель живут врозь: `VpnService` переживает
  /// смерть Activity, а состояние движка — нет. Без этой проверки приложение
  /// после возврата показывало «Отключено» при РАБОТАЮЩЕМ VPN, и нажатие
  /// Connect поднимало ВТОРОЙ сеанс поверх живого. Нативная сторона умела
  /// отвечать на `isRunning` с самого начала — её просто никто не спрашивал.
  ///
  /// Сессии здесь нет (конфиг остался в умершем изоляте), поэтому честно
  /// показываем «подключено», но без данных о сервере: пользователь видит
  /// правду и может переподключиться сам.
  @override
  Future<void> adoptRunningTunnel() async {
    try {
      final running = await _channel.invokeMethod<bool>('isRunning') ?? false;
      if (!running || status.isConnected) return;
      AppLog.i('Подхвачен туннель, поднятый прошлым запуском интерфейса');
      markConnected();
      setStatus(VpnConnectionState.connected);
    } catch (e) {
      AppLog.w('Не удалось спросить состояние туннеля: $e');
    }
  }

  @override
  Future<void> startSession() async {
    final session = this.session;
    if (session == null) return;

    final gen = newGeneration();
    bool aborted() => isStale(gen);

    setStatus(VpnConnectionState.connecting);

    try {
      // Ядро выбирается ровно так же, как на Windows (configFor в базе):
      // полный конфиг (правка пользователя или панельный профиль «Авто») —
      // всегда Xray; обычный сервер sing-box поднимает сам.
      // Резолв — ДО сборки конфига: адрес нужен и правилу «мимо туннеля»
      // (ip_cidr), и самому outbound'у. С доменным именем ядро пошло бы за
      // адресом уже из-под поднятого туннеля.
      final hosts = await resolveServerHosts(session.servers);
      if (aborted()) return;
      final serverIps = hosts.values.expand((e) => e).toSet().toList();
      final resolvedIps = VpnEngineBase.pickOneIpPerHost(hosts);

      // ⚠️ Сессия из НЕСКОЛЬКИХ серверов — это «Авто (лучший сервер)»: база
      // уже собрала конфиг с балансировщиком (Xray `balancers` +
      // `burstObservatory`) либо с `urltest` (sing-box) по ВСЕМ серверам и
      // положила его в `session.configJson`. Пересобирать его из
      // `servers.first`, как делалось здесь, значило подключаться к ПЕРВОМУ
      // серверу списка и выдавать это за автовыбор: ни балансировщика, ни
      // замеров, ни переключения на быстрый узел. Windows этот конфиг берёт
      // (`windows_engine.dart:56`), Android — молча выбрасывал.
      final multi = session.servers.length > 1;
      final cfg = multi
          ? (json: session.configJson, core: session.core)
          : configFor(session.servers.first, session.options,
              resolvedIps: resolvedIps);
      // Балансировщик Xray умеет только Xray: при нескольких серверах ядро
      // определяется сессией, а не протоколом первого сервера.
      final viaXray = cfg.core == ProxyCore.xray &&
          (multi || !SingboxOutboundFactory.supports(session.servers.first));

      // Когда сервер поднимает Xray, туннель заворачивает трафик в его
      // локальный SOCKS — как на Windows. Когда справляется sing-box, лишний
      // переход не нужен, и outbound встраивается прямо в конфиг туннеля.
      final tunJson = SingboxConfigBuilder(
        xraySocksPort: ports.socks,
        options: TunOptions.fromSettings(
          session.options.settings,
          serverIps: serverIps,
          android: true,
          // Резолвер для «Прямо». Пусто → прежнее поведение (`local`), то
          // есть домен не отрезолвится: лучше знать об этом из лога, чем
          // молча получить «сайт не открывается».
          directDnsUpstream: await _directDns(),
          // Ядро пишет свой лог САМО: перехватить его вывод здесь нечем —
          // это библиотека в нашем процессе, а redirectStderr ловит только
          // паники Go. Без этого «туннель поднят, трафика нет» не
          // диагностируется вообще.
          logOutput: '${(await AppPaths.supportDir()).path}'
              '${Platform.pathSeparator}singbox.log',
        ),
        // При нескольких серверах на sing-box собранный базой конфиг уже
        // содержит `urltest` по всем узлам — встраивать outbound одного
        // сервера нельзя, это снова свело бы автовыбор к первому.
        proxyOutboundGroup: (!viaXray && multi)
            ? _outboundsOf(session.configJson)
            : null,
        proxyOutbound: (viaXray || multi)
            ? null
            : SingboxOutboundFactory.build(
                session.servers.first,
                resolvedIp:
                    resolvedIps[session.servers.first.address.trim()],
              ),
      ).buildJson(session.options.split);

      if (aborted()) return;

      _starting = true;
      await _channel.invokeMethod<void>('start', {
        'config': tunJson,
        if (viaXray) 'xray_config': cfg.json,
      });
      _starting = false;

      // Пользователь мог отключиться, пока шло согласие на VPN.
      if (aborted()) {
        await _channel.invokeMethod<void>('stop');
        return;
      }

      markConnected();
      setStatus(VpnConnectionState.connected);
    } on PlatformException catch (e) {
      _starting = false;
      // Отказ в согласии — не ошибка подключения, а решение пользователя:
      // повторять его автоматически бессмысленно.
      final wasAborted = aborted();
      await cleanup();
      if (wasAborted) return;
      if (e.code == 'consent_denied') {
        setStatus(VpnConnectionState.error, message: e.message);
        return;
      }
      if (await scheduleRetry('не удалось подключиться: ${e.message}')) return;
      setStatus(VpnConnectionState.error, message: e.message);
    } catch (e) {
      _starting = false;
      final wasAborted = aborted();
      await cleanup();
      if (wasAborted) return;
      if (await scheduleRetry('не удалось подключиться: $e')) return;
      setStatus(VpnConnectionState.error, message: '$e');
    }
  }

  /// Событие от сервиса: туннель поднялся, упал или его отобрала система.
  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final running = event['running'] == true;
    final error = (event['error'] as String?)?.trim();

    if (running || _starting) return;
    if (!status.isConnected && status.state != VpnConnectionState.connecting) {
      return;
    }

    // Сюда попадает и onRevoke (другой VPN перехватил туннель) — пути,
    // которого на Windows нет вовсе.
    AppLog.e('VPN-сервис остановился: ${error ?? 'без причины'}');

    // Текст из нативного слоя ОБЯЗАН доехать до пользователя. Без этого
    // подключение просто «вылетало» молча, и причину нельзя было назвать
    // даже по логам приложения.
    unawaited(_reportStop(error));
  }

  Future<void> _reportStop(String? error) async {
    if (error == null || error.isEmpty) {
      await onCoreDied(0);
      return;
    }
    // Причина известна — показываем её вместо безымянного «ядро остановилось».
    // Повторять попытку смысла нет: конфиг тот же, результат будет тот же.
    await cleanup();
    setStatus(VpnConnectionState.error, message: error);
  }

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {
    // Kill switch: между попытками переподключения туннель ОСТАЁТСЯ поднятым,
    // но никуда не ведёт — трафик фейлится, а не утекает мимо VPN.
    //
    // Раньше здесь сервис гасился целиком, и на время всех попыток (backoff до
    // 20 с, до 8 попыток — это минуты) весь трафик шёл напрямую. Настройка при
    // этом была включена и печаталась в отчёте: пользователь считал себя
    // защищённым, а защиты не было вовсе.
    //
    // libbox владеет дескриптором сам, поэтому «погасить ядро, оставив fd» тут
    // невозможно. Вместо этого перезагружаем ядро конфигом-заглушкой: тот же
    // туннель, те же маршруты, но весь трафик уходит в reject.
    if (keepCapture) {
      try {
        await _channel.invokeMethod<void>('start', {'config': _blackholeJson()});
        AppLog.i('Kill switch: туннель удержан, трафик блокируется');
        return;
      } catch (e) {
        // Не смогли удержать — честнее погасить, чем оставить неизвестное
        // состояние: иначе туннель мог бы жить со СТАРЫМ конфигом.
        AppLog.w('Kill switch: не удалось удержать туннель ($e), гашу');
      }
    }
    await _stopService();
  }

  /// Туннель, который никуда не ведёт: маршруты на месте, весь трафик в reject.
  ///
  /// Собирается тем же билдером, чтобы совпадали адреса, MTU и списки пакетов —
  /// иначе система пересоздала бы интерфейс, и на этот миг трафик пошёл бы
  /// мимо VPN, то есть ровно то, что kill switch и предотвращает.
  String _blackholeJson() => SingboxConfigBuilder(
        options: const TunOptions(platformTun: true, blackhole: true),
      ).buildJson(const SplitTunnelConfig());

  @override
  Future<void> platformCleanup() async => _stopService();

  Future<void> _stopService() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e) {
      AppLog.w('Не удалось остановить VPN-сервис: $e');
    }
  }

  /// Прокси-outbound'ы из конфига, собранного базой (без служебного `direct`).
  ///
  /// Для «Авто» база строит полноценный конфиг прокси-ядра: узлы + группа
  /// `urltest` с тегом `proxy`. Туннелю нужны именно они — свой `direct` он
  /// добавляет сам, а два одноимённых outbound'а ядро отвергает.
  static List<Map<String, dynamic>>? _outboundsOf(String configJson) {
    try {
      final map = jsonDecode(configJson);
      if (map is! Map) return null;
      final outs = map['outbounds'];
      if (outs is! List) return null;
      final list = outs
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((e) => e['tag'] != 'direct')
          .toList();
      return list.isEmpty ? null : list;
    } catch (e) {
      AppLog.w('Не удалось разобрать конфиг автовыбора: $e');
      return null;
    }
  }

  /// DNS физической сети — для доменов с правилом «Прямо».
  ///
  /// ⚠️ Без него ядро оставляет транспорт `local`, и такие домены не
  /// резолвятся ВООБЩЕ. Проверено живым запуском в эмуляторе: сайт «Туннель»
  /// открывался, «Блок» блокировался, а «Прямо» отвечал «No address
  /// associated with hostname». Тот же дефект чинили на Windows.
  static Future<String?> _directDns() async {
    try {
      final dns = await const MethodChannel('lol.silentgate/device')
          .invokeMethod<String>('directDns');
      final v = (dns ?? '').trim();
      return v.isEmpty ? null : v;
    } catch (e) {
      AppLog.w('DNS физической сети недоступен: $e');
      return null;
    }
  }
}
