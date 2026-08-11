import 'dart:convert';

import '../net/api_ports.dart';
import '../settings/split_tunnel.dart';
import 'api_exit_guard.dart';

/// Маршрутизатор выходов для режима «Только прокси» (задача 3b).
///
/// **Почему он вообще существует.** Порты серверов из `ApiPorts` живут в
/// конфиге sing-box, а sing-box на Windows до этой задачи стартовал ТОЛЬКО
/// при `captureMode == CaptureMode.tun` — значит в режиме «Только прокси»
/// портов серверов не было физически, второе ядро там не поднималось вовсе.
/// Решение — отдельный, отдельно живущий экземпляр sing-box: чистый
/// маршрутизатор выходов, БЕЗ прав администратора (туннеля нет — поднимать
/// его тем же путём, что и hysteria2-прокси, см. `SingboxProcess`).
///
/// ⚠️ Он НАМЕРЕННО не похож на TUN-конфиг (`SingboxConfigBuilder`):
///  * НЕТ `tun`-инбаунда — трафик приходит только в явно открытые порты;
///  * НЕТ `dns`-секции — резолвит сам процесс, системным резолвером, как
///    обычная программа: перехватывать здесь нечего, петли через себя быть
///    не может, потому что нет адаптера, забирающего трафик машины;
///  * НЕТ обычных правил раздельного туннелирования («Прямо», «Туннель через
///    другой сервер») — у порта уже есть адресат, назначенный самим фактом
///    обращения к нему, и переопределять его чужим правилом означало бы
///    ровно то, от чего защищались в задаче 3 (`_addApiExitBlockGuard`).
///
/// Единственное исключение — БЛОК, и только под настройкой
/// `AppSettings.applyRulesInProxyOnly` (умолчание выключено, см. [applyRules]):
/// в этом режиме раздельное туннелирование не действует ни для одной
/// программы машины (ничего не перехватывается), и включать блок-правила по
/// умолчанию значило бы завести их там, где они больше нигде не работают.
class ExitRouterConfigBuilder {
  /// Ключи серверов, которым нужен отдельный порт (см. `ApiPorts.forServer`).
  final List<String> serverKeys;

  /// Токен API — он же пароль этих инбаундов. Пусто — инбаунды не создаются.
  final String token;

  /// Готовые outbound-ы серверов — С УЖЕ ПРОСТАВЛЕННЫМИ тегами (см.
  /// `exitTagFor`). ⚠️ ЕДИНСТВЕННЫЙ ИСТОЧНИК ПРАВДЫ о том, какие выходы живы:
  /// инбаунд создаётся ТОЛЬКО если для сервера есть outbound здесь — иначе
  /// получился бы висячий тег (`sing-box check` его не ловит, трафик молча
  /// уходит в `route.final`).
  final List<Map<String, dynamic>> exitOutbounds;

  /// Применять ли блок-правила раздельного туннелирования к этим портам.
  /// См. `AppSettings.applyRulesInProxyOnly`.
  final bool applyRules;

  /// Правила раздельного туннелирования — источник блок-списка при
  /// [applyRules] == true. Игнорируется, если [applyRules] == false.
  final SplitTunnelConfig split;

  const ExitRouterConfigBuilder({
    required this.serverKeys,
    required this.token,
    required this.exitOutbounds,
    this.applyRules = false,
    this.split = const SplitTunnelConfig(),
  });

  /// Теги, которые реально есть в [exitOutbounds].
  Set<String> get _liveExitTags => {
        for (final o in exitOutbounds)
          if (o['tag'] is String) o['tag'] as String,
      };

  /// Инбаунды портов серверов — общая логика с TUN-построителем, см.
  /// `buildApiExitInbounds` (`core/net/api_ports.dart`).
  List<Map<String, dynamic>> get _serverInbounds => buildApiExitInbounds(
        serverKeys: serverKeys,
        token: token,
        liveExitTags: _liveExitTags,
      );

  /// Инбаунд порта «Прямо» — та же общая логика, что у TUN-построителя (см.
  /// `buildApiDirectInbound`). В отличие от [_serverInbounds] не зависит от
  /// [serverKeys]/[exitOutbounds]: ведёт во встроенный `direct`-outbound,
  /// который ниже, в [buildMap], добавляется безусловно.
  List<Map<String, dynamic>> get _directInbound =>
      buildApiDirectInbound(token: token);

  Map<String, dynamic> buildMap() {
    final serverInbounds = _serverInbounds;
    final directInbound = _directInbound;
    final inbounds = [...serverInbounds, ...directInbound];
    final tags = [for (final i in inbounds) '${i['tag']}'];

    final rules = <Map<String, dynamic>>[
      // Блок — ВЫШЕ маршрута на выход: порт уже явно выбрал адресата (сервер
      // или «Прямо»), и собственный запрет пользователя обязан сработать
      // раньше, чем запрос до него доедет (та же логика, что
      // `_addApiExitBlockGuard` в задаче 3). ⚠️ Гейт `userRulesActive` — ТОТ
      // ЖЕ, что у TUN-построителя: в режиме «Всё через VPN» пользовательских
      // правил нет вовсе (они сохранены, но не входят в конфиг), включая
      // блок. Без этого гейта блок на портах API включался бы даже там, где
      // такой же блок в TUN-конфиге не действует — расхождение поведения
      // между двумя конфигами, которого брифом не было.
      if (applyRules && userRulesActive(split))
        ...apiExitBlockGuardRules(split: split, inboundTags: tags),
      // Порт X → сервер X, БЕЗ ИСКЛЮЧЕНИЙ, кроме блокировки выше.
      ...buildApiExitRules(serverInbounds),
      // Порт «Прямо» → direct, той же логикой.
      ...buildApiDirectRule(directInbound),
    ];

    return {
      'log': {'level': 'warn', 'timestamp': true},
      'inbounds': inbounds,
      'outbounds': [
        ...exitOutbounds,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'rules': rules,
        // Никакого auto_detect_interface/sniff — маршрутизатор не выбирает
        // адресата сам, у каждого запроса он уже задан портом, в который тот
        // пришёл. Трафик БЕЗ правила (порт не создался — пустой токен или
        // сервер не собрался) уходит прямо, а не теряется молча.
        'final': 'direct',
      },
    };
  }

  String buildJson() =>
      const JsonEncoder.withIndent('  ').convert(buildMap());
}
