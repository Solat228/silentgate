import '../models/vpn_server.dart';
import '../xray/xray_exit_bridge.dart';
import 'exit_tags.dart';
import 'singbox_outbound_factory.dart';

/// Почему из сервера НЕЛЬЗЯ собрать отдельный выход (`exit-…`); `null` — можно.
///
/// ⚠️ ЕДИНСТВЕННЫЙ ОТВЕТЧИК НА ЭТОТ ВОПРОС. Его спрашивают четверо:
/// [ExitOutbounds.build] (строит физически), `GET /v1/exits`
/// (`state/api_handlers.dart` — публикует порт), чекбокс «выдать порт»
/// (`ui/settings_screen.dart`) и плашка выхода в правиле
/// (`ui/split_tunnel_screen.dart`). Разойдись хоть один — интерфейс пообещает
/// то, чего конфиг не сделает: сервер серым не покажется, порт опубликуется, а
/// инбаунда под него не возникнет, и скрипт получит отказ соединения на адрес,
/// который ему только что назвали.
///
/// Панельные профили «Авто …» (`balancers` + `burstObservatory`) и транспорты
/// Xray (`xhttp`/`splithttp`) поднимаются через локальный SOCKS5-мост Xray ->
/// `sing-box` ([needsXrayExitBridge]). Пустой или повреждённый профиль «Авто»
/// без единого прокси-узла при этом честно отвергается.
///
/// Текст причины уходит в журнал (`ExitOutbounds.skipped`) и не переводится —
/// это диагностика, а не строка интерфейса.
String? exitServerRejection(VpnServer s) {
  if (s.address.trim().isEmpty) return 'у сервера нет адреса';
  // Заглушки истёкшей подписки (`0.0.0.0:1` с текстом в имени). Выход из них
  // собирается синтаксически верным и ведёт в никуда: ядро примет конфиг,
  // а соединение будет отвергнуто уже на самом сокете.
  if (s.isNotice) {
    return 'это не сервер, а сообщение подписки: ${s.displayName}';
  }
  // Сервер, который клиент не умеет собрать вообще (например, hysteria2 с
  // маской finalmask.udp, которую не строит ни одно наше ядро) — решение
  // владельца 25.09.2026: сервер не выбрасывается из списка, но не годится
  // НИ ДЛЯ ЧЕГО, включая отдельный выход.
  if (s.isUnsupported) {
    return 'сервер не поддерживается клиентом (${s.unsupportedReason}): '
        '${s.displayName}';
  }
  if (s.usesWhitelistRelay) {
    return 'обход БС требует собственного WebRTC-звонка и вторым туннелем не поднимается: '
        '${s.displayName}';
  }
  if ((s.isPanelProfile || (s.rawJsonOverride ?? '').trim().isNotEmpty) &&
      s.core == ProxyCore.xray) {
    return fullConfigExitRejection(s);
  }
  if (needsXrayExitBridge(s)) {
    return null;
  }
  if (!SingboxOutboundFactory.supports(s)) {
    return 'протокол не поднимается вторым туннелем: ${s.displayName}';
  }
  return null;
}

/// Годится ли сервер на роль отдельного выхода. Обратная сторона
/// [exitServerRejection] — см. её описание, там причины и предупреждения.
bool canBeExitServer(VpnServer s) => exitServerRejection(s) == null;

/// Сборка outbound-ов для правил, которые идут через ОТДЕЛЬНЫЙ сервер.
///
/// ⚠️ ФАЙЛ ОБЩИЙ ДЛЯ ПЛАТФОРМ НАМЕРЕННО. Разведка 07.08.2026 показала, что
/// общий знаменатель у Windows и Android диктуется телефоном: там процесс Xray
/// РОВНО ОДИН (`LibXray.invoke` — глобальный синглтон без хендла, второй
/// Go-рантайм в процессе не поднять), поэтому «ещё один сервер = ещё один
/// процесс ядра» на Windows развело бы платформы на первом же правиле. Значит
/// и раскладка обязана быть одна.
class ExitOutbounds {
  /// Что уехало в конфиг.
  final List<Map<String, dynamic>> outbounds;

  /// Серверы, которые собрать не удалось: `ключ сервера → причина`.
  ///
  /// ⚠️ Возвращаем причины, а не глотаем. Сервер, тихо выпавший из конфига,
  /// означает, что правило пользователя уехало в основной туннель — то есть в
  /// другую страну. Это обязано попадать в журнал, иначе разбор жалобы
  /// «настроил Германию, а показывает Нидерланды» начинается с нуля.
  final Map<String, String> skipped;

  const ExitOutbounds({this.outbounds = const [], this.skipped = const {}});

  bool get isEmpty => outbounds.isEmpty;

  /// Собрать outbound-ы для перечисленных серверов.
  ///
  /// [servers] — ключ сервера → сам сервер. Состав выбирает
  /// `AppState.exitServerKeysFor`: серверы правил (БЕЗ основного сервера сессии
  /// — он уже живёт под тегом `proxy`) плюс серверы, которым выдан отдельный
  /// порт API (там основной сервер как раз НУЖЕН). ⚠️ Отсюда следует, что тег
  /// в этом списке НЕ означает «правилам можно им пользоваться» — см.
  /// `SingboxConfigBuilder.apiOnlyExitKeys`.
  ///
  /// [resolvedIps] — адреса, отрезолвенные ЗАРАНЕЕ. Домен сервера внутри
  /// туннеля не резолвится: чтобы дойти до сервера, нужен его адрес, а адрес
  /// спрашивается через туннель, которого ещё нет.
  /// [fallbackTag] — куда уводить трафик правила, если его выход умер.
  /// Пусто — запасного пути нет, как было раньше.
  /// [xrayBridgePorts] — локальные порты SOCKS5-мостов Xray для профилей
  /// «Авто» и транспортов `XHTTP`. Если не переданы явно, вычисляются
  /// детерминированно через [assignXrayExitBridgePorts].
  static ExitOutbounds build({
    required Map<String, VpnServer> servers,
    Map<String, String> resolvedIps = const {},
    String fallbackTag = '',
    Map<String, int>? xrayBridgePorts,
    String xrayBridgeUser = '',
    String xrayBridgePassword = '',
  }) {
    final out = <Map<String, dynamic>>[];
    final skipped = <String, String>{};
    final bridgePorts =
        xrayBridgePorts ?? assignXrayExitBridgePorts(servers);

    // Порядок детерминирован: иначе конфиг «дышит» между сборками, и сравнение
    // готового конфига в тестах перестаёт работать.
    final keys = servers.keys.toList()..sort();
    for (final key in keys) {
      final server = servers[key]!;
      final rejection = exitServerRejection(server);
      if (rejection != null) {
        skipped[key] = rejection;
        continue;
      }
      try {
        final tag = exitTagFor(key);
        final bridgePort = bridgePorts[key];
        Map<String, dynamic> buildLeaf(String leafTag) {
          if (bridgePort != null && needsXrayExitBridge(server)) {
            return buildSingboxBridgeSocksOutbound(
              tag: leafTag,
              port: bridgePort,
              user: xrayBridgeUser,
              password: xrayBridgePassword,
            );
          }
          return SingboxOutboundFactory.build(
            server,
            tag: leafTag,
            resolvedIp: resolvedIps[server.address],
          );
        }

        if (fallbackTag.isEmpty) {
          out.add(buildLeaf(tag));
        } else {
          // Сам сервер уезжает под ВНУТРЕННИЙ тег, а имя выхода забирает
          // группа: так ссылки правил, DNS и портов API остаются целыми.
          final nodeTag = exitNodeTagFor(tag);
          out.add(buildLeaf(nodeTag));
          out.add({
            'type': 'selector',
            'tag': tag,
            // ⚠️ ПЕРВЫМ — САМ СЕРВЕР. `default` группа берёт из первого
            // участника, и перепутанный порядок означал бы, что правило с
            // самого начала ходит через запасной путь, а выбранный
            // пользователем сервер не участвует вовсе.
            'outbounds': [nodeTag, fallbackTag],
            // Ядро не должно переключать группу само: выбор здесь делает
            // сторож выходов по факту трёх промахов подряд, а не по задержке.
            'interrupt_exist_connections': false,
          });
        }
      } catch (e) {
        // Фабрика бросает на неизвестном протоколе. Ловим адресно: один
        // непригодный сервер не должен уносить весь конфиг.
        skipped[key] = 'не удалось собрать outbound: ${server.displayName} ($e)';
      }
    }
    return ExitOutbounds(outbounds: out, skipped: skipped);
  }
}
