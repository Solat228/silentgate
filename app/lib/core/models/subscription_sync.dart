import 'dart:io' show InternetAddress;

import 'vpn_server.dart';

/// «Сервер тот же, а ключ другой» — диагностика расхождения форматов ссылки.
///
/// ⚠️ ХРАНИТ ТОЛЬКО ИМЕНА ПОЛЕЙ, НИКОГДА — ЗНАЧЕНИЯ. Ключ сервера это его
/// share-ссылка, а в ней лежат учётные данные (uuid VLESS, пароль trojan/ss,
/// пароль обфускации hysteria2). Запись «было → стало» отправила бы их в
/// `app.log` и оттуда в отчёт поддержки, который владелец пересылает в чат.
class ServerKeyChange {
  /// Имя сервера ДЛЯ ЖУРНАЛА — см. [SubscriptionSyncResult.journalName].
  ///
  /// ⚠️ ЭТО НЕ `VpnServer.displayName`. Тот при пустом имени вырождается в
  /// «адрес:порт», а адрес сервера подписки — ровно то, что блокируют.
  final String name;

  /// Имена полей, которыми отличаются старая и новая ссылки (без значений).
  /// Пусто — значит поля совпали, разошлась только ЗАПИСЬ ссылки: ровно так
  /// выглядел дефект gRPC (`serviceName=` против `path=`).
  final List<String> fields;

  const ServerKeyChange({required this.name, required this.fields});
}

/// Итог обновления подписки: что изменилось в составе серверов (как в NekoBox)
/// и сколько серверов пришло с конфигом от панели.
class SubscriptionSyncResult {
  final int total;
  final List<String> added;
  final List<String> removed;

  /// Серверов с авторитетным конфигом панели (формат XRAY_JSON).
  final int withPanelConfig;

  /// Из них — профилей «Авто …» с готовым балансировщиком.
  final int panelProfiles;

  /// Серверы, оставшиеся на месте, но сменившие ключ. В баннер НЕ идут —
  /// пользователю это ничего не говорит; нужны для журнала (см. [keyChangeReport]).
  final List<ServerKeyChange> keyChanges;

  final DateTime at;

  const SubscriptionSyncResult({
    required this.total,
    required this.added,
    required this.removed,
    required this.withPanelConfig,
    required this.panelProfiles,
    required this.at,
    this.keyChanges = const [],
  });

  /// Сравнение состава подписки ПО ТОЖДЕСТВУ СЕРВЕРА, а не по его ключу.
  ///
  /// ⚠️ ДЕФЕКТ, РАДИ КОТОРОГО ЭТО НАПИСАНО: раньше состав считался по
  /// [VpnServer.key], то есть по полной share-ссылке. Ссылка законно меняется,
  /// когда панель поправила серверу отпечаток, sni или путь, — и баннер писал
  /// «+1 · −1» у сервера «Москва 1. GRPC», который никуда не девался. Первая
  /// линия защиты — канонический ключ (`ShareLinkParser`), эта вторая: даже при
  /// будущем расхождении форматов баннер останется честным.
  ///
  /// Переименование сервера — намеренно добавление + удаление: человек узнаёт
  /// узел по имени, и «Москва 1» вместо «Москва 2» для него другой сервер.
  factory SubscriptionSyncResult.diff({
    required List<VpnServer> before,
    required List<VpnServer> after,
    required int withPanelConfig,
    required int panelProfiles,
    DateTime? at,
  }) {
    final beforeById = {for (final s in before) s.identityKey: s};
    final afterById = {for (final s in after) s.identityKey: s};

    final changes = <ServerKeyChange>[];
    // Порядковый номер среди РАЗЛИЧНЫХ серверов нового списка: им подписываются
    // записи, чьё имя нельзя печатать (см. [journalName]).
    var position = 0;
    for (final e in afterById.entries) {
      position++;
      final old = beforeById[e.key];
      // Тождество сохранилось, а ключ другой — значит расходится ЗАПИСЬ
      // сервера. Именно это молча съедало пины и результаты пинга.
      if (old != null && old.key != e.value.key) {
        changes.add(ServerKeyChange(
          name: journalName(e.value, position),
          fields: changedFields(old, e.value),
        ));
      }
    }

    return SubscriptionSyncResult(
      total: after.length,
      added: [
        for (final e in afterById.entries)
          if (!beforeById.containsKey(e.key)) e.value.displayName,
      ],
      removed: [
        for (final e in beforeById.entries)
          if (!afterById.containsKey(e.key)) e.value.displayName,
      ],
      withPanelConfig: withPanelConfig,
      panelProfiles: panelProfiles,
      keyChanges: changes,
      at: at ?? DateTime.now(),
    );
  }

  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty;

  /// Строки для журнала: чем именно отличается новая запись сервера.
  ///
  /// Одинаковые расхождения свёрнуты в одну строку с числом: у владельца
  /// gRPC-серверов было 190 — столько же строк в `app.log` сделали бы журнал
  /// нечитаемым и вытеснили бы из него всё остальное ротацией.
  ///
  /// ⚠️ ИМЕНА ПОЛЕЙ И ЖУРНАЛЬНЫЕ ИМЕНА СЕРВЕРОВ — И БОЛЬШЕ НИЧЕГО. Значения
  /// полей и сами ключи не печатаются: там учётные данные (см.
  /// [ServerKeyChange]). Имя сервера пропущено через [journalName], поэтому из
  /// строки не вытащить адрес — а вытащить его раньше было можно у любого
  /// сервера без названия.
  List<String> get keyChangeReport {
    if (keyChanges.isEmpty) return const [];
    // Группируем по НАБОРУ полей, сохраняя порядок появления, — так строка
    // журнала отвечает на вопрос «что именно разошлось», а не «сколько всего».
    final groups = <String, List<String>>{};
    for (final c in keyChanges) {
      groups.putIfAbsent(c.fields.join(', '), () => <String>[]).add(c.name);
    }
    final lines = <String>[];
    for (final g in groups.entries) {
      final names = g.value;
      final sample = names.take(3).join(', ');
      final tail = names.length > 3 ? ' и ещё ${names.length - 3}' : '';
      final what = g.key.isEmpty
          ? 'изменилась только запись ссылки'
          : 'изменились поля: ${g.key}';
      lines.add('Ключ сервера сменился (сервер тот же): ${names.length} шт., '
          '$what; например: $sample$tail');
    }
    return lines;
  }

  /// Как назвать сервер В ЖУРНАЛЕ, чтобы по строке нельзя было восстановить его
  /// адрес.
  ///
  /// ⚠️ ДЕФЕКТ, РАДИ КОТОРОГО ЭТО НАПИСАНО. Раньше сюда клали
  /// `VpnServer.displayName`, а он при пустом имени вырождается в
  /// «адрес:порт» — то есть в ровно тот адрес, который и блокируют. Строка
  /// уходит в `app.log`, а он целиком вкладывается в отчёт поддержки, который
  /// владелец пересылает в чат. `scrubSecrets` здесь не спасает: он режет
  /// share-ссылки и URL, а голое `ru1.example.com:443` для него обычный текст.
  ///
  /// Название от панели печатаем как есть — человек узнаёт узел именно по нему,
  /// и без имени журнал бесполезен. Но если название САМО похоже на адрес,
  /// подставляем порядковый номер.
  ///
  /// ⚠️ СВЕРЯТЬ ИМЯ С `s.address` НЕДОСТАТОЧНО, И ЭТО НЕ ТЕОРИЯ. Панель обычно
  /// раздаёт узлы по домену (`de1.panel.net`), а зовёт их по IP —
  /// «DE-1 (203.0.113.10)». Имя адрес из ссылки не содержит, проверка «имя
  /// содержит `s.address`» молчит, и в `app.log` дословно уезжает боевой IP
  /// сервера — ровно то, что блокируют. Поэтому решает не совпадение с одним
  /// полем, а ФОРМА строки: [looksLikeAddress] ловит адрес ЛЮБОГО вида —
  /// IPv4, IPv6, `host:port`, доменное имя.
  ///
  /// [position] — порядковый номер среди РАЗЛИЧНЫХ серверов того списка,
  /// который прислала панель (1-based; дубликаты схлопнуты по тождеству, как и
  /// везде в [SubscriptionSyncResult.diff]).
  ///
  /// ⚠️ ЭТО НЕ НОМЕР СТРОКИ В ПРИЛОЖЕНИИ, И ОБЕЩАТЬ ОБРАТНОЕ НЕЛЬЗЯ. На экране
  /// список строится иначе: закреплённые серверы уезжают наверх, работают
  /// поиск и переключение подписок. «Сервер №7» из отчёта и седьмая строка на
  /// экране — почти всегда разные серверы. Номер годится ровно на два дела:
  /// различать записи внутри строки журнала и сверяться с выдачей САМОЙ панели
  /// (её видит владелец сервиса, которому отчёт и адресован). Пользователю по
  /// нему сказать нечего — это не идентификатор сервера.
  static String journalName(VpnServer s, int position) {
    final remark = s.remark.trim();
    final address = s.address.trim();
    final leaks = remark.isEmpty ||
        (address.isNotEmpty &&
            remark.toLowerCase().contains(address.toLowerCase())) ||
        looksLikeAddress(remark);
    return leaks ? 'сервер №$position' : remark;
  }

  /// Похоже ли [text] на адрес — В ЛЮБОМ ВИДЕ и в любом окружении.
  ///
  /// ⚠️ ДЕФЕКТ, РАДИ КОТОРОГО ЭТО ПЕРЕПИСАНО (найден запуском, а не чтением).
  /// Прежняя версия резала строку по символам, которых в адресе быть не может,
  /// и проверяла КУСОК ЦЕЛИКОМ. Но буквы, дефис и подчёркивание такими
  /// символами не являются, поэтому «NL-185.199.108.153» и «DE1-203.0.113.10»
  /// оставались одним куском, ни на что не похожим, — проверку они ПРОХОДИЛИ и
  /// уезжали в журнал дословно. А «страна-адрес» — самая обычная схема
  /// именования узлов у панелей, то есть пропускался самый частый случай.
  ///
  /// Поэтому ищется ФОРМА, а не соседство с конкретным разделителем:
  ///  * **IPv4** — любые четыре подряд идущие числовые метки, которые разбирает
  ///    платформа: «nl-185.199.108.153», «DE (1.2.3.4)», «ru185.199.108.153»;
  ///  * **IPv6** — каждый непрерывный кусок из шестнадцатеричных цифр и
  ///    двоеточий: «NL-2a03:4000:8:1::5», «[2a03::5]:443», «fe80::1%wlan»;
  ///  * **`host:port` и доменное имя** — по куску между символами, которых в
  ///    адресе не бывает (пробелы, скобки, кириллица, эмодзи).
  ///
  /// ⚠️ ПЕРЕСТРАХОВКА ЗДЕСЬ НАМЕРЕННАЯ. Имя «US-West.Fast» адресом не
  /// является, но от домена неотличимо, и такое имя тоже станет номером; то же
  /// с четырёхчастной версией вроде «Сборка 1.2.3.4». Цена ложного
  /// срабатывания — номер вместо имени в одной строке журнала; цена пропуска —
  /// боевой адрес сервера в чате поддержки. Второе дороже.
  static bool looksLikeAddress(String text) {
    final lower = text.toLowerCase();
    for (final run in _digitRuns.allMatches(lower)) {
      if (_containsIpv4(run[0]!)) return true;
    }
    for (final run in _hexRuns.allMatches(lower)) {
      if (_isIpLiteral(run[0]!)) return true;
    }
    for (final token in lower.split(_notAddressChars)) {
      if (_isAddressToken(token)) return true;
    }
    return false;
  }

  /// Всё, что не может быть частью адреса, — разделитель. Точка, двоеточие,
  /// дефис, подчёркивание и `%` (зона IPv6) остаются внутри куска.
  static final RegExp _notAddressChars = RegExp(r'[^0-9a-z:._%-]+');

  /// Кусок из цифр и точек — кандидат в IPv4, каким бы ни было окружение:
  /// буквы, дефис и скобки в такой кусок не входят и потому его не прячут.
  static final RegExp _digitRuns = RegExp(r'[0-9.]+');

  /// Кусок из шестнадцатеричных цифр и двоеточий — кандидат в IPv6. Зона
  /// (`%wlan`) и скобки в класс не входят, поэтому отрезаются сами собой.
  static final RegExp _hexRuns = RegExp(r'[0-9a-f:]+');

  /// Есть ли внутри [run] (только цифры и точки) четыре подряд идущие метки,
  /// которые платформа разбирает как IPv4.
  ///
  /// Скользящее окно, а не разбор куска целиком: «v1.203.0.113.10» — это тот же
  /// адрес с приклеенным номером версии, и целиком он не разбирается.
  static bool _containsIpv4(String run) {
    final parts = run.split('.');
    for (var i = 0; i + 4 <= parts.length; i++) {
      final quad = parts.sublist(i, i + 4);
      if (quad.any((p) => p.isEmpty)) continue;
      if (_isIpLiteral(quad.join('.'))) return true;
    }
    return false;
  }

  /// IP-литерал в понимании платформы: своей арифметике по октетам тут делать
  /// нечего, а IPv6 своей регуляркой не разобрать вовсе.
  ///
  /// ⚠️ Одной `tryParse` недостаточно: «::» она разбирает как адрес, а в имени
  /// узла это оформление («🇩🇪 DE :: 01»), а не адрес. Настоящий адрес
  /// содержит хотя бы одну шестнадцатеричную цифру.
  static bool _isIpLiteral(String s) =>
      _hexDigit.hasMatch(s) && InternetAddress.tryParse(s) != null;

  /// `хост:порт` — порт отрезаем и проверяем хост отдельно: `1.2.3.4:443`
  /// целиком не разбирает ни один парсер IP.
  static final RegExp _hostPort = RegExp(r'^(.+):(\d{1,5})$');

  /// Доменное имя: минимум две метки, последняя — только буквы. Требование
  /// букв в конце отсекает версии и номера («v2.5», «1.10»), которые в именах
  /// узлов встречаются постоянно.
  static final RegExp _domain =
      RegExp(r'^(?:[a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])?\.)+[a-z]{2,}\.?$');

  static final RegExp _hexDigit = RegExp(r'[0-9a-f]');

  static bool _isAddressToken(String token) {
    if (token.isEmpty) return false;
    // Зону (`fe80::1%wlan`) `tryParse` не принимает, поэтому отрезаем её сами.
    if (_isIpLiteral(token.split('%').first)) return true;
    final hostPort = _hostPort.firstMatch(token);
    if (hostPort != null) {
      final port = int.tryParse(hostPort.group(2)!) ?? 0;
      if (port >= 1 && port <= 65535 && _isAddressToken(hostPort.group(1)!)) {
        return true;
      }
    }
    return _domain.hasMatch(token);
  }

  /// Имена полей, которыми отличаются две записи одного и того же сервера.
  ///
  /// Список закрытый и перечислен руками: рефлексии в Dart нет, а автоматом по
  /// `toString()` пришлось бы печатать значения — то есть учётные данные.
  /// ⚠️ Добавили поле в [VpnServer] — добавьте его и сюда, иначе расхождение
  /// формата снова станет невидимым.
  static List<String> changedFields(VpnServer a, VpnServer b) {
    final diff = <String>[];
    void cmp(String name, Object? x, Object? y) {
      if (x != y) diff.add(name);
    }

    // Адрес входит в тождество, но там он приведён к нижнему регистру:
    // расхождение только в регистре ловится здесь.
    cmp('address', a.address, b.address);
    cmp('id', a.id, b.id);
    cmp('encryption', a.encryption, b.encryption);
    cmp('alterId', a.alterId, b.alterId);
    cmp('flow', a.flow, b.flow);
    cmp('network', a.network, b.network);
    cmp('security', a.security, b.security);
    cmp('sni', a.sni, b.sni);
    cmp('host', a.host, b.host);
    cmp('path', a.path, b.path);
    cmp('fingerprint', a.fingerprint, b.fingerprint);
    cmp('publicKey', a.publicKey, b.publicKey);
    cmp('shortId', a.shortId, b.shortId);
    cmp('spiderX', a.spiderX, b.spiderX);
    cmp('alpn', a.alpn, b.alpn);
    cmp('headerType', a.headerType, b.headerType);
    cmp('authority', a.authority, b.authority);
    cmp('xhttpMode', a.xhttpMode, b.xhttpMode);
    cmp('xPadding', a.xPadding, b.xPadding);
    cmp('obfs', a.obfs, b.obfs);
    cmp('obfsPassword', a.obfsPassword, b.obfsPassword);
    cmp('allowInsecure', a.allowInsecure, b.allowInsecure);
    cmp('hopPorts', a.hopPorts, b.hopPorts);
    return diff;
  }

  /// Короткая сводка для баннера: «7 серверов · +2 · −1» либо «без изменений».
  ///
  /// Локализованную версию строит UI — `syncSummary` в
  /// `core/i18n/enum_labels.dart`: плюрализация зависит от языка, а модель
  /// не имеет доступа к `AppLocalizations`. Здесь остаётся русский фолбэк
  /// для логов и отчёта поддержки, которые принципиально не переводятся.
  String get summary {
    final parts = <String>['$total ${_plural(total)}'];
    if (added.isNotEmpty) parts.add('+${added.length}');
    if (removed.isNotEmpty) parts.add('−${removed.length}');
    if (!hasChanges) parts.add('без изменений');
    return parts.join(' · ');
  }

  static String _plural(int n) {
    final n100 = n % 100, n10 = n % 10;
    if (n100 >= 11 && n100 <= 14) return 'серверов';
    if (n10 == 1) return 'сервер';
    if (n10 >= 2 && n10 <= 4) return 'сервера';
    return 'серверов';
  }
}
