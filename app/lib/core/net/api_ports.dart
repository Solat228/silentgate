import '../singbox/exit_tags.dart';

/// Раскладка локальных портов API.
///
/// ⚠️ ПОРЯДОК — ЧАСТЬ КОНТРАКТА. Скрипт хардкодит номер порта; «дышащая» между
/// запусками раскладка увела бы запрос в другую страну молча и без ошибки.
/// Поэтому ключи сортируются тем же способом, что в `ExitOutbounds.build`.
class ApiPorts {
  /// Управляющий HTTP-API.
  static const int control = 10870;

  /// «Прямо» — мимо VPN, реальный IP. Нужен, чтобы сравнивать «через VPN» и
  /// «без VPN» одной строкой кода, не выключая туннель.
  static const int direct = 10819;

  /// Первый порт диапазона серверов.
  static const int firstServer = 10820;

  /// Сколько серверов могут получить порт.
  ///
  /// ⚠️ Ограничение осмысленное, а не круглое число: каждый порт — это ещё один
  /// inbound в конфиге ядра. Сорок с запасом покрывает любой реальный набор.
  static const int maxServers = 40;

  /// Порт сервера [key] среди [keys]. `null` — ключа нет или он сверх диапазона.
  static int? forServer(List<String> keys, String key) {
    final sorted = [...keys]..sort();
    final i = sorted.indexOf(key);
    if (i < 0 || i >= maxServers) return null;
    return firstServer + i;
  }

  /// Ключи, которым порт реально достанется (первые [maxServers] по порядку).
  static List<String> withinRange(List<String> keys) {
    final sorted = [...keys]..sort();
    return sorted.length <= maxServers
        ? sorted
        : sorted.sublist(0, maxServers);
  }

  /// Гейт «канал API реально поднят»: тумблер включён И задан токен.
  ///
  /// ⚠️ ЕДИНЫЙ ИСТОЧНИК ПРАВДЫ ДЛЯ ОБЕИХ СТОРОН. `PortCheck` (проверяет порты
  /// перед стартом ядра) и сборка TUN-конфига (создаёт инбаунды) обязаны
  /// решать «есть тут порты или нет» ОДИНАКОВО. Разойдись гейты —
  /// `apiEnabled=true` при пустом токене заставил бы `PortCheck` проверять
  /// порты, которых конфиг всё равно не создаст: стороннее приложение на
  /// любом из 10820–10859 давало бы ложный отказ подключения на ровном месте.
  /// Пустой токен сам по себе уже значит «канал не поднимается» (см.
  /// `SingboxConfigBuilder._apiExitInbounds`) — этот гейт то же самое, но
  /// доступное ДО сборки конфига, когда нужно решить, что проверять портами.
  static bool exitsActive({required bool enabled, required String token}) =>
      enabled && token.isNotEmpty;
}

/// Тег inbound-а, ведущего в сервер [serverKey].
///
/// ⚠️ Выводится из ТОГО ЖЕ ключа, что и тег outbound-а (`exitTagFor`), поэтому
/// правило `inboundTag → outboundTag` не может разъехаться. Разойдись они хоть
/// на символ — правило сослалось бы на несуществующий outbound, а `sing-box
/// check` этого НЕ ловит: конфиг принимается с кодом 0, а трафик уходит в
/// `route.final`, то есть мимо выбранного сервера.
String apiExitInboundTag(String serverKey) =>
    'api-${exitTagFor(serverKey)}';

/// Обратное преобразование тега инбаунда в тег его outbound-а.
String apiExitOutboundOf(String inboundTag) =>
    inboundTag.substring('api-'.length);

/// Инбаунды отдельных портов API: по одному `mixed` на сервер из [serverKeys],
/// у которого есть живой outbound (тег входит в [liveExitTags]).
///
/// ⚠️ ОБЩАЯ ЛОГИКА ДВУХ КОНФИГОВ. Ей пользуются и TUN-построитель
/// (`SingboxConfigBuilder._apiExitInbounds`, задача 3), и маршрутизатор
/// выходов режима «Только прокси» (`ExitRouterConfigBuilder`, задача 3b) —
/// им обоим нужен РОВНО один и тот же инбаунд на порт сервера. Две копии
/// этой логики разъехались бы на первой же правке (урок уже случался в этом
/// проекте — см. `CLAUDE.md`).
///
/// ⚠️ ТОЛЬКО ЖИВЫЕ. Сервер, чей outbound не собрался, порта не получает —
/// иначе правило сослалось бы на несуществующий тег, `sing-box check`
/// пропустил бы это молча, и трафик ушёл бы в `route.final`, то есть мимо
/// выбранного сервера.
List<Map<String, dynamic>> buildApiExitInbounds({
  required List<String> serverKeys,
  required String token,
  required Set<String> liveExitTags,
}) {
  if (token.isEmpty) return const [];
  final out = <Map<String, dynamic>>[];
  for (final key in ApiPorts.withinRange(serverKeys)) {
    if (!liveExitTags.contains(exitTagFor(key))) continue;
    final port = ApiPorts.forServer(serverKeys, key);
    if (port == null) continue;
    out.add({
      'type': 'mixed',
      'tag': apiExitInboundTag(key),
      'listen': '127.0.0.1',
      'listen_port': port,
      'users': [
        {'username': 'sg', 'password': token}
      ],
    });
  }
  return out;
}

/// Правила «инбаунд конкретного сервера → его же выход». Общая логика — см.
/// [buildApiExitInbounds].
List<Map<String, dynamic>> buildApiExitRules(
        List<Map<String, dynamic>> apiExitInbounds) =>
    [
      for (final i in apiExitInbounds)
        {
          'inbound': [i['tag']],
          'action': 'route',
          'outbound': apiExitOutboundOf('${i['tag']}'),
        },
    ];

/// Тег inbound-а порта «Прямо» (см. [ApiPorts.direct]).
///
/// ⚠️ Фиксированный, а не выведенный из ключа сервера — этот порт ни к
/// какому серверу не привязан, он ведёт в инфраструктурный outbound `direct`,
/// который есть безусловно в ОБОИХ построителях (`SingboxConfigBuilder`,
/// `ExitRouterConfigBuilder`).
const String apiDirectInboundTag = 'api-direct';

/// Инбаунд порта «Прямо»: тот же служебный вход, что и у портов серверов
/// ([buildApiExitInbounds]), с теми же кредами (`sg`/токен) и тем же гейтом
/// (пустой токен — канал не поднимается), но ведущий не на конкретный сервер,
/// а на встроенный outbound `direct` — мимо VPN, реальным IP.
///
/// ⚠️ Нужен, чтобы скрипт мог сравнить «через VPN»/«без VPN» одной и той же
/// строкой кода, не выключая туннель: в режиме TUN «просто не указать прокси»
/// не работает — вся машина уже в туннеле, и обойти его снаружи процесса
/// ядра нечем (см. `docs/API.md`).
///
/// ⚠️ ОБЩАЯ ЛОГИКА ДВУХ КОНФИГОВ — по той же причине, что и
/// [buildApiExitInbounds]: `SingboxConfigBuilder` и `ExitRouterConfigBuilder`
/// обязаны создавать этот инбаунд ОДИНАКОВО, иначе он появится в одном
/// конфиге и пропадёт в другом при первой же независимой правке.
List<Map<String, dynamic>> buildApiDirectInbound({required String token}) {
  if (token.isEmpty) return const [];
  return [
    {
      'type': 'mixed',
      'tag': apiDirectInboundTag,
      'listen': '127.0.0.1',
      'listen_port': ApiPorts.direct,
      'users': [
        {'username': 'sg', 'password': token}
      ],
    },
  ];
}

/// Правило «порт «Прямо» → outbound `direct`». Тег outbound-а — буквальный
/// `'direct'`, а не производная от тега инбаунда (в отличие от
/// [buildApiExitRules]/[apiExitOutboundOf]): у этого порта нет «своего»
/// сервера, только один законный адресат.
///
/// [apiDirectInbound] — результат [buildApiDirectInbound]: пустой список,
/// если токен пуст, тогда и правило не строится — раздельные пустые списки
/// синхронны по построению, порознь превращаться в «висячее» правило нечему.
List<Map<String, dynamic>> buildApiDirectRule(
        List<Map<String, dynamic>> apiDirectInbound) =>
    [
      for (final i in apiDirectInbound)
        {
          'inbound': [i['tag']],
          'action': 'route',
          'outbound': 'direct',
        },
    ];
