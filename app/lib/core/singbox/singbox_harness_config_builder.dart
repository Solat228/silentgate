import 'dart:convert';

// HarnessEntry/HarnessPorts описывают кандидата на пробу и не зависят от ядра,
// поэтому переиспользуются как есть (лежат рядом с Xray-харнессом исторически).
import '../settings/split_tunnel.dart';
import '../xray/harness_config_builder.dart';
import 'singbox_outbound_factory.dart';

/// Проброс-харнесс на sing-box: по одному локальному `mixed`-inbound'у на
/// кандидата, каждый жёстко смаршрутизирован на свой outbound.
///
/// Зачем отдельно от [HarnessConfigBuilder]: hysteria2 умеет только sing-box,
/// а пинг «через прокси» для таких серверов — единственный работающий (прямая
/// TCP-проба до QUIC-порта молчит всегда).
///
/// Как и Xray-харнесс, НИКОГДА не трогает системный прокси: слушает только
/// 127.0.0.1 и не содержит ни TUN, ни Clash API.
///
/// Правила по сайтам из боевых настроек ([HarnessRealism]) переносятся сюда —
/// иначе проба проходила бы там, где реальное подключение упирается в блок.
/// ⚠️ DNS-секция сюда НЕ переносится: боевая склеена с TUN (hijack, резолвер
/// через туннель, зеркала правил), а sing-box отвергает конфиг ЦЕЛИКОМ из-за
/// одного неверного поля — цена ошибки здесь не «менее точная проба», а
/// «hysteria2 не пингуется вовсе». Ограничение осознанное, а не забытое.
class SingboxHarnessConfigBuilder {
  final HarnessPorts ports;

  /// Логин и пароль инбаундов харнесса — см. пояснение у
  /// `HarnessConfigBuilder.user`: это такой же полноценный вход в туннель, и
  /// открытым его оставлять нельзя. Пусто — без пароля (только для тестов).
  final String user;
  final String password;

  const SingboxHarnessConfigBuilder({
    this.ports = const HarnessPorts(base: 21500),
    this.user = '',
    this.password = '',
  });

  SingboxHarnessConfigBuilder withAuth(String user, String password) =>
      SingboxHarnessConfigBuilder(
          ports: ports, user: user, password: password);

  bool get _hasAuth => user.isNotEmpty && password.isNotEmpty;

  /// Пользователи инбаунда sing-box. ⚠️ Поле называется `users`, а не
  /// `accounts` как у Xray, и ключи внутри другие — построители не
  /// взаимозаменяемы, хотя решают одну задачу.
  List<Map<String, String>> get _users => _hasAuth
      ? [
          {'username': user, 'password': password}
        ]
      : const [];

  int portFor(int index) => ports.base + index;

  String buildJson(List<HarnessEntry> entries) =>
      const JsonEncoder.withIndent('  ').convert(buildMap(entries));

  Map<String, dynamic> buildMap(List<HarnessEntry> entries) {
    final realism = realismOf(entries);
    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];

    // ⚠️ ВЫШЕ правил кандидатов, и в том же порядке, что в боевом конфиге:
    // блок, затем «Прямо». Правило кандидата ловит из своего входа ВСЁ, поэтому
    // всё, что оказалось бы ниже, не сработало бы ни разу.
    for (final s in realism.blocked) {
      rules.add({..._siteMatch(s), 'action': 'reject'});
    }
    for (final s in realism.direct) {
      rules.add({..._siteMatch(s), 'action': 'route', 'outbound': 'direct'});
    }

    for (var i = 0; i < entries.length; i++) {
      final inTag = 'in-$i';
      final outTag = 'out-$i';
      inbounds.add({
        'type': 'mixed',
        'tag': inTag,
        'listen': '127.0.0.1',
        'listen_port': portFor(i),
        if (_hasAuth) 'users': _users,
      });
      outbounds.add(SingboxOutboundFactory.build(entries[i].server, tag: outTag));
      rules.add({
        'inbound': [inTag],
        'action': 'route',
        'outbound': outTag,
      });
    }
    outbounds.add({'type': 'direct', 'tag': 'direct'});

    return {
      'log': {'level': 'warn'},
      'inbounds': inbounds,
      'outbounds': outbounds,
      // final нужен ядру как запасной маршрут; сюда трафик проб не попадает.
      'route': {'rules': rules, 'final': 'direct'},
    };
  }

  /// Совпадение по сайту — теми же полями, что в боевом конфиге
  /// (`SingboxConfigBuilder._siteMatch`): суффикс домена и, если задан, порт.
  Map<String, dynamic> _siteMatch(SiteRule s) => {
        'domain_suffix': [s.domain],
        if (s.port != null) 'port': [s.port],
      };
}
