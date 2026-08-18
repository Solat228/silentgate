/// Каким ядром поднимается сервер. Xray не умеет hysteria2 (QUIC-протокол),
/// поэтому такие серверы обслуживает sing-box — он уже есть в комплекте ради TUN.
/// На Windows sing-box запускается отдельным процессом (сложившаяся архитектура);
/// линковка лицензией не запрещена — приложение под GPL-3.0 (см. CLAUDE.md §3).
enum ProxyCore { xray, singbox }

/// Маркеры переводимых тегов [VpnServer.configTags]. Технические теги
/// (VLESS/TCP/REALITY…) во всех языках одинаковы и в переводе не нуждаются,
/// а эти UI прогоняет через `configTagLabels` (`core/i18n/enum_labels.dart`).
///
/// Значения — русский фолбэк: он же используется в логах и отчёте поддержки,
/// которые принципиально не переводятся.
abstract final class VpnServerTags {
  static const autoSelect = 'АВТОВЫБОР';
  static const panel = 'ПАНЕЛЬ';
  static const portHopping = 'ПОРТ-ХОППИНГ';
}

/// Разобранный сервер из share-ссылки
/// (vless:// / vmess:// / trojan:// / ss:// / hysteria2://).
///
/// Хранит достаточно полей, чтобы [XrayConfigBuilder] построил outbound.
/// `rawLink` сохраняется, чтобы можно было пере-парсить при загрузке из хранилища.
class VpnServer {
  final String protocol; // 'vless' | 'vmess' | 'trojan' | 'shadowsocks' | 'hysteria2'
  final String remark; // человекочитаемое имя (из #fragment / ps)
  final String address;
  final int port;

  // Аутентификация
  final String id; // uuid (vless/vmess) или пароль (trojan/ss)
  final String? encryption; // vless: 'none'; ss: метод шифрования; vmess: cipher
  final int alterId; // vmess alterId
  final String? flow; // vless flow (напр. xtls-rprx-vision)

  // Транспорт (streamSettings)
  final String network; // 'tcp' | 'ws' | 'grpc' | 'http' | 'quic' | 'kcp'
  final String security; // 'none' | 'tls' | 'reality'
  final String? sni; // serverName
  final String? host; // Host-заголовок (ws/http)
  final String? path; // путь ws/http или serviceName для grpc
  final String? fingerprint; // uTLS fp (chrome/firefox/…)
  final String? publicKey; // reality pbk
  final String? shortId; // reality sid
  final String? spiderX; // reality spx
  final String? alpn;
  final String? headerType; // тип заголовка tcp (none/http)
  final String? authority; // grpc authority
  final String? xhttpMode; // xhttp mode (auto/…)
  final String? xPadding; // xhttp extra.xPaddingBytes

  // ── Hysteria2 ──────────────────────────────────────────────────────────────
  /// Обфускация QUIC-пакетов: пока существует единственный тип `salamander`.
  final String? obfs;
  final String? obfsPassword;

  /// Разрешить самоподписанный сертификат (`insecure=1` в ссылке). Отдельный
  /// флаг, а не поле [security]: у hysteria2 TLS включён всегда — это QUIC.
  final bool allowInsecure;

  /// Порт-хоппинг (`mport=1000-2000,3000`): сервер слушает диапазон, клиент
  /// перескакивает между портами, чтобы не попасть под лимит по одному порту.
  final String? hopPorts;

  final String rawLink;

  /// Сырой Xray-JSON, заданный пользователем в редакторе — применяется как есть при подключении
  /// (сессионный override, не сохраняется локально, перезаписывается при обновлении подписки).
  final String? rawJsonOverride;

  /// **Авторитетный outbound от панели** (формат XRAY_JSON, который Remnawave отдаёт
  /// Happ/v2rayNG). Используется вместо пересборки из share-ссылки: пересборка теряет
  /// детали streamSettings, из-за чего автовыбор (burstObservatory) получал нерабочие
  /// outbound'ы. См. [XrayJsonSubscription].
  final String? rawOutboundJson;

  /// **Полный конфиг профиля от панели.** Заполняется для «сложных» профилей —
  /// «Авто …» с десятками outbound'ов, `balancers` и `burstObservatory`. Такой конфиг
  /// применяется ЦЕЛИКОМ: выдёргивать из него один outbound нельзя — теряется весь
  /// автовыбор (у профиля «Авто (YouTube)» это 80 серверов + балансировщик).
  final String? rawPanelConfig;

  /// Профиль-автовыбор от панели (готовый balancer/burstObservatory).
  bool get isPanelProfile => (rawPanelConfig ?? '').isNotEmpty;

  /// «Служебный» сервер-заглушка: панель Remnawave при истёкшей подписке
  /// возвращает фейковые серверы с адресом `0.0.0.0:1`, а в имени — сообщения
  /// («После оплаты нажмите…», «Ваша подписка истекла!»). Подключаться к ним
  /// нельзя; в списке вместо пинга показываем кнопку «Обновить».
  bool get isNotice {
    final a = address.trim();
    return a.isEmpty || a == '0.0.0.0' || a == '0' || port <= 1;
  }

  const VpnServer({
    required this.protocol,
    required this.remark,
    required this.address,
    required this.port,
    required this.id,
    this.encryption,
    this.alterId = 0,
    this.flow,
    this.network = 'tcp',
    this.security = 'none',
    this.sni,
    this.host,
    this.path,
    this.fingerprint,
    this.publicKey,
    this.shortId,
    this.spiderX,
    this.alpn,
    this.headerType,
    this.authority,
    this.xhttpMode,
    this.xPadding,
    this.obfs,
    this.obfsPassword,
    this.allowInsecure = false,
    this.hopPorts,
    required this.rawLink,
    this.rawJsonOverride,
    this.rawOutboundJson,
    this.rawPanelConfig,
  });

  /// Стабильный ключ для карт результатов (пинг, автонастройка).
  String get key => rawLink;

  /// «Тот же самый узел» — для сравнения СОСТАВА подписки.
  ///
  /// ⚠️ ОТЛИЧАЕТСЯ ОТ [key] НАМЕРЕННО. Ключ — это полная ссылка: он меняется,
  /// когда панель поправила у сервера отпечаток, sni или путь. Для хранения
  /// пинов и пингов так и надо (изменился конфиг — изменился и результат), а
  /// вот для баннера «что добавилось, что пропало» это ложь: пользователю
  /// сообщали «−1 · +1» там, где сервер никуда не девался.
  ///
  /// Здесь берём то, по чему человек узнаёт узел в списке: протокол, адрес,
  /// порт и имя. ⚠️ Имя обязательно: у панели десятки узлов на одном адресе
  /// различаются только им.
  String get identityKey {
    // ⚠️ ПРОФИЛЬ «АВТО …» ОПОЗНАЁТСЯ ТОЛЬКО ПО ИМЕНИ. Его адрес и порт взяты у
    // ПЕРВОГО узла внутри балансировщика, а состав балансировщика панель
    // перетасовывает — узлов там десятки. Считай тождество по адресу, и профиль
    // на каждом обновлении выглядел бы «удалён и добавлен»: ровно та жалоба,
    // ради которой этот диф и переписывался.
    if (isPanelProfile) return 'panel|${remark.trim()}';
    return '$protocol|${address.toLowerCase()}|$port|${remark.trim()}';
  }

  /// Каким ядром поднимать этот сервер. Профиль панели — всегда Xray-конфиг.
  /// Полный конфиг, который РЕАЛЬНО применится при подключении, или пустая
  /// строка, если сервер поднимается из полей ссылки.
  ///
  /// ⚠️ ЕДИНСТВЕННЫЙ ИСТОЧНИК ПРАВДЫ, И ЭТО НЕ КРАСОТА РАДИ КРАСОТЫ. Порядок
  /// «правка → конфиг панели → поля» был выписан РУКАМИ в двух местах: в движке
  /// (`configFor`) и в копировании ключа в буфер. Они уже разошлись — движок для
  /// hysteria2 Xray-JSON игнорирует («поднимаю sing-box»), а копирование его
  /// всё равно отдавало. Наружу это выглядело бы так: человек копирует конфиг,
  /// вставляет обратно и получает ДРУГОЙ сервер, чем тот, к которому
  /// подключался. Тот же класс, что уже записан в CLAUDE.md про разрешение и
  /// исполнение: два независимых разбора одного и того же — всегда расхождение.
  ///
  /// ⚠️ У hysteria2 конфига здесь нет НИКОГДА: JSON панели и редактора — это
  /// всегда конфиг Xray, а Xray такого протокола не знает и просто не стартует.
  ///
  /// ⚠️ Пустой считается и строка из одних пробелов: раньше движок проверял
  /// `isNotEmpty` без обрезки и на пробельной правке уходил в ветку «полный
  /// конфиг», то есть подключался пустотой.
  String get effectiveFullConfig {
    if (core == ProxyCore.singbox) return '';
    final override = rawJsonOverride ?? '';
    if (override.trim().isNotEmpty) return override;
    final panel = rawPanelConfig ?? '';
    return panel.trim().isNotEmpty ? panel : '';
  }

  ProxyCore get core =>
      protocol == 'hysteria2' && !isPanelProfile ? ProxyCore.singbox : ProxyCore.xray;

  /// Короткое имя для UI (если remark пуст — адрес:порт).
  String get displayName =>
      remark.trim().isNotEmpty ? remark.trim() : '$address:$port';

  String get protocolLabel {
    switch (protocol) {
      case 'vless':
        return 'VLESS${security == 'reality' ? ' · Reality' : ''}';
      case 'vmess':
        return 'VMess';
      case 'trojan':
        return 'Trojan';
      case 'shadowsocks':
        return 'Shadowsocks';
      case 'hysteria2':
        return 'Hysteria2${(obfs ?? '').isNotEmpty ? ' · обфускация' : ''}';
      default:
        return protocol;
    }
  }

  /// Теги параметров из конфига для подписи под именем (как в Happ: VLESS / GRPC / REALITY).
  ///
  /// Технические теги (VLESS/TCP/REALITY…) одинаковы во всех языках; переводимые
  /// возвращаются маркерами из [VpnServerTags] — UI прогоняет список через
  /// `configTagLabels` (`core/i18n/enum_labels.dart`).
  List<String> get configTags {
    // Профиль «Авто …» — готовый автовыбор панели: показываем это вместо
    // параметров одного из десятков серверов внутри.
    if (isPanelProfile) {
      return const [VpnServerTags.autoSelect, VpnServerTags.panel];
    }
    final tags = <String>[protocol.toUpperCase(), network.toUpperCase()];
    if (security == 'reality') {
      tags.add('REALITY');
    } else if (security == 'tls') {
      tags.add('TLS');
    }
    if (flow != null && flow!.contains('vision')) tags.add('VISION');
    if ((obfs ?? '').isNotEmpty) tags.add('OBFS');
    if ((hopPorts ?? '').isNotEmpty) tags.add(VpnServerTags.portHopping);
    return tags;
  }

  VpnServer copyWith({
    String? protocol,
    String? remark,
    String? address,
    int? port,
    String? id,
    String? encryption,
    int? alterId,
    String? flow,
    String? network,
    String? security,
    String? sni,
    String? host,
    String? path,
    String? fingerprint,
    String? publicKey,
    String? shortId,
    String? spiderX,
    String? alpn,
    String? headerType,
    String? authority,
    String? xhttpMode,
    String? xPadding,
    String? obfs,
    String? obfsPassword,
    bool? allowInsecure,
    String? hopPorts,
    String? rawLink,
    String? rawJsonOverride,
    String? rawOutboundJson,
    String? rawPanelConfig,

    /// Сбросить конфиги, пришедшие от панели. Нужно при РУЧНОЙ правке полей:
    /// [XrayOutboundFactory] отдаёт приоритет outbound'у панели, поэтому иначе
    /// изменённые адрес/SNI/пароль молча не применялись бы до перезапуска.
    bool clearPanelConfigs = false,
  }) {
    return VpnServer(
      protocol: protocol ?? this.protocol,
      remark: remark ?? this.remark,
      address: address ?? this.address,
      port: port ?? this.port,
      id: id ?? this.id,
      encryption: encryption ?? this.encryption,
      alterId: alterId ?? this.alterId,
      flow: flow ?? this.flow,
      network: network ?? this.network,
      security: security ?? this.security,
      sni: sni ?? this.sni,
      host: host ?? this.host,
      path: path ?? this.path,
      fingerprint: fingerprint ?? this.fingerprint,
      publicKey: publicKey ?? this.publicKey,
      shortId: shortId ?? this.shortId,
      spiderX: spiderX ?? this.spiderX,
      alpn: alpn ?? this.alpn,
      headerType: headerType ?? this.headerType,
      authority: authority ?? this.authority,
      xhttpMode: xhttpMode ?? this.xhttpMode,
      xPadding: xPadding ?? this.xPadding,
      obfs: obfs ?? this.obfs,
      obfsPassword: obfsPassword ?? this.obfsPassword,
      allowInsecure: allowInsecure ?? this.allowInsecure,
      hopPorts: hopPorts ?? this.hopPorts,
      rawLink: rawLink ?? this.rawLink,
      rawJsonOverride: rawJsonOverride ?? this.rawJsonOverride,
      rawOutboundJson:
          clearPanelConfigs ? null : (rawOutboundJson ?? this.rawOutboundJson),
      rawPanelConfig:
          clearPanelConfigs ? null : (rawPanelConfig ?? this.rawPanelConfig),
    );
  }

  /// Протоколы, у которых [buildShareLink] НЕ пересобирает настоящую ссылку и
  /// выдаёт опознавательный идентификатор `<протокол>://<хост>:<порт>#<имя>`
  /// (см. запасную ветку в конце метода).
  ///
  /// ⚠️ ЭТОТ ЖЕ НАБОР ЧИТАЕТ РАЗБОР (`ShareLinkParser`). Разрешение и
  /// исполнение обязаны спрашивать один код: пока идентификатор писала сборка,
  /// а разбор о нём не знал, панельный узел shadowsocks/vmess исчезал из списка
  /// после первого же перезапуска. Появится протокол, который сборка тоже не
  /// умеет пересобирать, — его имя обязано попасть сюда, иначе повторится ровно
  /// та же потеря. Круг стережёт `test/canonical_key_test.dart`.
  static const Set<String> identifierProtocols = {'vmess', 'shadowsocks'};

  /// Сериализация обратно в share-ссылку (для сохранения правок редактора).
  /// Полностью пересобираются vless/trojan/hysteria2; vmess и shadowsocks
  /// возвращают исходную ссылку, а без неё — идентификатор
  /// (см. [identifierProtocols]).
  String buildShareLink() {
    if (protocol == 'hysteria2') {
      final q = <String, String>{};
      void add(String k, String? v) {
        if (v != null && v.isNotEmpty) q[k] = v;
      }

      add('sni', sni);
      add('alpn', alpn);
      add('obfs', obfs);
      add('obfs-password', obfsPassword);
      add('mport', hopPorts);
      // Разбор `fp` читает — значит сборка обязана его писать, иначе ссылка
      // после круга «разобрали → собрали» отличается от исходной, и ключ
      // сервера меняется сам по себе при каждом чтении с диска.
      add('fp', fingerprint);
      if (allowInsecure) q['insecure'] = '1';
      final query = q.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final frag = remark.isNotEmpty ? '#${Uri.encodeComponent(remark)}' : '';
      return 'hysteria2://${Uri.encodeComponent(id)}@${_hostPart()}:$port'
          '${query.isEmpty ? '' : '?$query'}$frag';
    }
    if (protocol == 'vless' || protocol == 'trojan') {
      final q = <String, String>{
        'type': network,
        'security': security,
      };
      if (protocol == 'vless') q['encryption'] = encryption ?? 'none';
      void add(String k, String? v) {
        if (v != null && v.isNotEmpty) q[k] = v;
      }

      add('sni', sni);
      add('fp', fingerprint);
      add('pbk', publicKey);
      add('sid', shortId);
      add('spx', spiderX);
      add('flow', flow);
      add('host', host);
      add('path', path);
      add('headerType', headerType);
      add('alpn', alpn);
      add('authority', authority);
      add('mode', xhttpMode);
      if (xPadding != null && xPadding!.isNotEmpty) {
        q['extra'] = '{"xPaddingBytes":"$xPadding"}';
      }

      final query = q.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final frag = remark.isNotEmpty ? '#${Uri.encodeComponent(remark)}' : '';
      return '$protocol://$id@${_hostPart()}:$port?$query$frag';
    }
    // ⚠️ ПРОТОКОЛЫ, КОТОРЫЕ МЫ НЕ ПЕРЕСОБИРАЕМ (vmess, ss), НО КЛЮЧ ИМ НУЖЕН.
    //
    // Обычно у них есть исходная ссылка, и она же ключ. Но из панельного
    // XRAY_JSON сервер приходит БЕЗ ссылки (`rawLink: ''`), и тогда `key`
    // получался ПУСТОЙ СТРОКОЙ — одной на всех. Все такие серверы делили один
    // ключ: пинг, пин, ручная правка и конфиг панели писались друг поверх
    // друга, а после перезапуска сервер исчезал из списка вместе с
    // сохранённым по нему (`tryParse('')` возвращает null).
    //
    // Поэтому собираем опознавательный идентификатор из того, что есть. Он не
    // подключаемая ссылка — учётные данные узла живут в `rawOutboundJson`,
    // который панель прислала и который лежит в `panel_outbounds.json` по этому
    // же ключу (`AppState._withStoredExtras`). Ровно та же схема, что у
    // профилей `panel://…`.
    //
    // ⚠️ ЧИТАЕТСЯ ОБРАТНО ТЕМ ЖЕ КОДОМ: `ShareLinkParser` разбирает эту форму
    // (`_parseNodeId`) и принимает её ТОЛЬКО если обратная сборка дала ту же
    // строку байт в байт. Пока разбора не было, ветка молча ломала всё, что
    // обещала: `AppState._serverFromStoredLink` возвращал null, и узел
    // выбрасывался `whereType<VpnServer>()` без единой записи в журнале.
    //
    // ⚠️ ФОРМУ МЕНЯТЬ НЕЛЬЗЯ БЕЗ МИГРАЦИИ. Это ключ, по которому на диске уже
    // лежат пины, ручные правки и результаты пинга; метод и пароль из него не
    // вывести — их тут никогда не было, поэтому «собрать настоящую ss://»
    // задним числом не получится. Написание закреплено тестом.
    if (rawLink.trim().isEmpty) {
      final frag = remark.isNotEmpty ? '#${Uri.encodeComponent(remark)}' : '';
      return '$protocol://${_hostPart()}:$port$frag';
    }
    return rawLink;
  }

  /// Адрес для ссылки. IPv6 обязан быть в квадратных скобках: `Uri.host` их
  /// снимает, и собранная обратно ссылка `hysteria2://p@2001:db8::1:443`
  /// больше не парсится — сервер молча исчезал из списка после перезапуска
  /// вместе со своим пином, правкой и пингом.
  String _hostPart() {
    final h = address.trim();
    if (h.contains(':') && !h.startsWith('[')) return '[$h]';
    return h;
  }
}
