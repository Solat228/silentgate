import 'dart:convert';
import 'dart:io';

import '../platform/app_paths.dart';
import '../subscription/subscription_logo.dart';

/// Иконка (favicon) сайта для списка раздельного туннелирования.
///
/// ⚠️ **ХОДИМ ТОЛЬКО НА САМ САЙТ.** Домены в этом списке — правила VPN, то
/// есть прямой ответ на вопрос «что человек хочет скрыть». Прежние запасные
/// источники (`google.com/s2/favicons?domain=…`, `favicone.com/…`) отдавали имя
/// сайта третьей стороне вместе с адресом пользователя — посредник собирал
/// список ровно из тех доменов, ради которых VPN и ставят. Иконка —
/// украшение, приватность важнее: сайт, который в списке есть, и так узнаёт о
/// нас при первом же соединении, а посредник не узнавал бы ничего.
///
/// Гейт — [allowedIconUrl]; он же прогоняется на КАЖДОМ редиректе (см.
/// [fetchIconBytes]) и на иконке, объявленной в HTML самого сайта.
/// ⚠️ Правило одно и без исключений: **ни одного запроса на хост, которого нет
/// под доменом правила**. Довод «но иконку назвал сам сайт» разобран и
/// отклонён — почему, написано у [iconSources].
///
/// Результат кэшируется в `%APPDATA%\SilentGate\site_icons\<домен>.png`, чтобы
/// не ходить в сеть на каждую перерисовку. Flutter рисует только PNG, поэтому
/// `.ico` не берём.
class SiteFaviconService {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  static final Map<String, String?> _mem = {};
  static final Map<String, Future<String?>> _pending = {};

  /// Путь к PNG-иконке домена или null. Кэшируется в памяти и на диске.
  /// [builtIn] — домен ВШИТ В ПРИЛОЖЕНИЕ (сервис-чипы, автонастройка), а не
  /// внесён пользователем в правила.
  ///
  /// ⚠️ РАЗНИЦА НЕ КОСМЕТИЧЕСКАЯ, А В ТОМ, ЧТО ИМЕННО УТЕКАЕТ. Строгий гейт
  /// заводился ради ОДНОГО: список сайтов из правил раздельного туннелирования
  /// — это перечень того, что человек хочет скрыть, и он у каждого свой.
  /// Вшитый список одинаков у всех, кто поставил приложение; обращение за
  /// иконкой `x.com` не сообщает наблюдателю ничего о пользователе, чего бы он
  /// не узнал из самого факта установки. Поэтому здесь разрешается адрес,
  /// который сайт объявил в своём HTML, — иначе у `x.com` и `instagram.com`
  /// (иконка на `abs.twimg.com` и `static.cdninstagram.com`) вместо картинки
  /// осталась бы буква, и мы заплатили бы видимой ценой за нулевую выгоду.
  ///
  /// ⚠️ Для доменов ИЗ ПРАВИЛ ПОЛЬЗОВАТЕЛЯ послабления нет и быть не должно:
  /// там выбор третьей стороны делает сервер сайта, а проверить его нечем.
  static Future<String?> iconFor(String domain, {bool builtIn = false}) {
    final d = domain.trim().toLowerCase();
    if (d.isEmpty) return Future.value(null);
    // Ключ кэша учитывает режим: иначе первый же чип «доверенного» сервиса
    // положил бы в кэш иконку с чужого хоста, а следующий за ней запрос из
    // правил пользователя получил бы её же — гейт обошёлся бы сам собой.
    final key = builtIn ? 'builtin:$d' : d;
    if (_mem.containsKey(key)) return Future.value(_mem[key]);
    return _pending
        .putIfAbsent(key, () => _resolve(d, builtIn: builtIn))
        .then((path) {
      _mem[key] = path;
      _pending.remove(key);
      return path;
    });
  }

  static Future<String?> _resolve(String domain, {bool builtIn = false}) async {
    try {
      final dir = await AppPaths.supportDir();
      final cacheDir =
          Directory('${dir.path}${Platform.pathSeparator}site_icons');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
      final safe = domain.replaceAll(RegExp(r'[^a-z0-9.\-]'), '_');
      // Файл кэша тоже разный: см. про ключ памяти в [iconFor] — иначе кэш на
      // диске переживёт перезапуск и обойдёт гейт уже навсегда.
      final file = File('${cacheDir.path}${Platform.pathSeparator}'
          '${builtIn ? 'svc_' : ''}$safe.png');
      if (await file.exists() && await file.length() > 0) return file.path;

      // Иконка, объявленная на самой странице сайта (apple-touch-icon/icon):
      // работает там, где типовые пути пустые.
      final fromHtml = await _iconFromHtml(domain);
      // ⚠️ У ВШИТЫХ СЕРВИСОВ ГЕЙТА НЕТ ВОВСЕ, а не «гейт плюс одно исключение».
      // Скрывать нечего: список одинаков у всех, кто поставил приложение (см.
      // [iconSources]). Полугейт же стоил владельцу шести пропавших иконок:
      // объявленный сайтом адрес пускали, а посредника — нет, и у сервисов,
      // чей фавикон нашему запросу не отдаётся, не оставалось ничего.
      final gate = builtIn ? _allowAny : iconGateFor(domain);
      for (final url in iconSources(domain, fromHtml: fromHtml, builtIn: builtIn)) {
        final uri = Uri.tryParse(url);
        if (uri == null) continue;
        // Гейт передаётся ВНУТРЬ загрузки: там он спрашивается и про этот
        // адрес, и про каждый редирект. Двух разборов одного правила быть не
        // должно — расходятся именно они.
        final bytes = await fetchIconBytes(uri, gate);
        if (bytes != null) {
          await file.writeAsBytes(bytes, flush: true);
          return file.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Адреса, по которым ищем иконку домена, — в порядке проб.
  ///
  /// ⚠️ Список пропущен через [allowedIconUrl] ЦЕЛИКОМ, включая [fromHtml] —
  /// иконку, которую сайт объявил в своём HTML. Решение спорное, поэтому
  /// разбор целиком, чтобы его не переоткрывали каждый круг ревью.
  ///
  /// Довод «пустить»: адрес назвал сам сайт, а не мы; имя домена там не
  /// значение параметра, а часть чужой вёрстки; браузер, открывая страницу,
  /// сходил бы туда же. У крупных сайтов иконка почти всегда на соседнем
  /// домене той же компании (`x.com` → `abs.twimg.com`), и строгий гейт
  /// стоит пользователю видимой иконки.
  ///
  /// Довод «не пускать» (принят): наблюдатель опознаёт сайт по САМОМУ адресу
  /// иконки — `static.cdninstagram.com/…` означает `instagram.com` и без
  /// параметров. А «каждый сайт называет свой CDN» на практике неверно: вся
  /// сеть сидит на нескольких общих CDN, поэтому один наблюдатель собрал бы
  /// заметную часть списка — ровно то, за что выкинули `s2/favicons`, только
  /// адресом вместо параметра. Плюс адрес выбирает СЕРВЕР САЙТА: доверять ему
  /// выбор третьей стороны — значит отдать решение о нашей приватности
  /// стороннему коду, а проверить этот выбор нам нечем (белого списка
  /// «CDN той же компании» не существует).
  ///
  /// Цена решения честная: у сайтов, держащих иконку на чужом хосте, вместо
  /// картинки останется буква-заглушка. Иконка — украшение.
  ///
  /// ⚠️ ВСЁ ВЫШЕ — ПРО ДОМЕНЫ ИЗ ПРАВИЛ ПОЛЬЗОВАТЕЛЯ. Для [builtIn] (сервис-чипы
  /// и автонастройка) правило другое, и это не поблажка, а разный предмет
  /// защиты. Тот список ВШИТ В БИНАРЬ и одинаков у всех, кто поставил
  /// приложение: обращение за иконкой `x.com` не сообщает наблюдателю о
  /// пользователе ничего, чего бы он не узнал из самого факта установки.
  /// Секретен перечень САЙТОВ ИЗ ПРАВИЛ — то, что человек хочет скрыть.
  ///
  /// ⚠️ ЧЕМ ЗА СТРОГОСТЬ ЗАПЛАТИЛИ, ПОКА ЭТОГО РАЗДЕЛЕНИЯ НЕ БЫЛО: у Discord,
  /// Claude, Gemini, X, Instagram и Google иконки в чипах пропали и сменились
  /// глобусами — их фавиконы лежат либо на чужом CDN, либо не отдаются нашему
  /// запросу вовсе. Владелец заметил это первым же взглядом на экран.
  /// Публичный ради теста-стража.
  static List<String> iconSources(String domain,
      {String? fromHtml, bool builtIn = false}) {
    final d = domain.trim().toLowerCase();
    // sub.domain → корневой домен (favicon чаще лежит на корне).
    final root = rootDomain(d);
    final own = <String>[
      if (fromHtml != null && fromHtml.isNotEmpty) fromHtml,
      'https://$d/apple-touch-icon.png',
      'https://$d/apple-touch-icon-precomposed.png',
      'https://$d/favicon.png',
      if (root != d) 'https://$root/apple-touch-icon.png',
      if (root != d) 'https://$root/favicon.png',
    ];
    if (!builtIn) {
      return own.where((u) => allowedIconUrl(u, d)).toList();
    }
    // Для вшитых сервисов посредники разрешены — но ПОСЛЕДНИМИ: сначала всё
    // равно пробуем сам сайт, чтобы не ходить к третьей стороне без нужды.
    return [
      ...own,
      'https://www.google.com/s2/favicons?sz=64&domain=$d',
      'https://favicone.com/$d?s=64',
    ];
  }

  /// Разрешено ли идти за иконкой по [url], когда в правилах стоит [domain].
  ///
  /// Разрешены ровно три вещи:
  ///  * сам домен правила (`host == domain`);
  ///  * его ПОДДОМЕНЫ (`static.example.com` при правиле `example.com`) —
  ///    сравнение по метке `.<домен>`, а не голым суффиксом строки, иначе
  ///    `evilexample.com` прошло бы за `example.com`;
  ///  * ТОЧНО его регистрируемый корень (`example.com` при правиле
  ///    `shop.example.com`) — фавикон чаще лежит на корне, чем на поддомене.
  ///
  /// ⚠️ Соседи по корню НЕ разрешены (`sibling.example.com` при правиле
  /// `shop.example.com` — отказ), и это не придирка: [rootDomain] разбирает
  /// домен наивно, без списка публичных суффиксов, поэтому «корнем»
  /// `user.github.io` он считает `github.io`, а `bucket.s3.amazonaws.com` —
  /// `amazonaws.com`. Пускать всё под таким «корнем» значило бы пускать
  /// ЧУЖИХ арендаторов того же хостинга, то есть посредника с другим именем.
  /// Корень разрешён только сам по себе: запрос `https://github.io/favicon.png`
  /// о конкретном `user.` ничего не сообщает.
  /// Цена — правило на поддомене не возьмёт иконку с соседнего поддомена;
  /// на правилах-корнях (обычный случай, `www.` срезается при добавлении)
  /// ничего не теряется.
  ///
  /// Только `https`: саму страницу мы и так тянем по https, и опускаться до
  /// открытого канала ради украшения незачем — по дороге его подменяют.
  /// Публичный ради теста-стража; им же гейтится каждый редирект.
  static bool allowedIconUrl(String url, String domain) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    final d = domain.trim().toLowerCase();
    if (host.isEmpty || d.isEmpty) return false;
    // Литеральный адрес: «корня» у него нет, поэтому только точное совпадение
    // (иначе `1.1` от 192.168.1.1 пустило бы куда угодно вида `x.1.1`).
    if (InternetAddress.tryParse(d) != null) return host == d;
    return host == d || host.endsWith('.$d') || host == rootDomain(d);
  }

  /// Тот же [allowedIconUrl], но в виде предиката по [Uri] — им гейтятся
  /// редиректы и запрос страницы. Публичный ради теста-стража: иначе
  /// проверять пришлось бы копию правила, а не то, что уходит в сеть.
  static bool Function(Uri) iconGateFor(String domain) =>
      (uri) => allowedIconUrl(uri.toString(), domain);

  /// Гейт вшитых сервисов: пускает всё по https.
  ///
  /// ⚠️ Это НЕ «отключённая защита», а другой предмет защиты — см. [iconSources].
  /// Скрывать в этом списке нечего: он одинаков у всех, кто поставил
  /// приложение. https остаётся обязательным: иконка едет по сети, и открытый
  /// http дал бы подменить картинку кому угодно по дороге.
  static bool _allowAny(Uri uri) => uri.scheme == 'https';

  /// Достаёт URL иконки со страницы сайта (`<link rel="apple-touch-icon">` и т.п.),
  /// разбором HTML — той же логикой, что и логотип подписки.
  ///
  /// ⚠️ Редиректы здесь ведутся так же вручную и через тот же гейт: 30x со
  /// страницы сайта на чужой хост увёл бы нас к посреднику ещё до того, как мы
  /// дошли до разбора иконок.
  static Future<String?> _iconFromHtml(String domain) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..userAgent = _ua;
    try {
      final uri = Uri.parse('https://$domain/');
      final resp = await _openGated(client, uri, iconGateFor(domain));
      if (resp.statusCode != 200) return null;
      final ct = resp.headers.contentType?.mimeType ?? '';
      if (!ct.contains('html')) return null;
      final bytes = <int>[];
      await for (final c in resp.timeout(const Duration(seconds: 8))) {
        bytes.addAll(c);
        if (bytes.length > 512 * 1024) break; // хватит на <head>
      }
      final body = utf8.decode(bytes, allowMalformed: true);
      return SubscriptionLogo.extractLogoUrl(body, base: uri);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Корневой домен: `www.sub.example.co.uk` → `example.co.uk`. Простой разбор
  /// с учётом двухуровневых суффиксов (co.uk, com.br и т.п.) — фавикон чаще
  /// лежит на корне, чем на конкретном поддомене. Публичный ради юнит-теста.
  static String rootDomain(String domain) {
    final parts = domain.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return domain;
    const twoLevel = {
      'co', 'com', 'org', 'net', 'gov', 'edu', 'ac', 'or', 'ne', 'go'
    };
    // Если предпоследняя метка — типичный «второй уровень» (co.uk, com.br), берём
    // три. Последняя метка при этом — ДВУХбуквенный ccTLD (uk/br/au): условие
    // `== 2` отсекает ложный `X.go.com` (com — 3-буквенный gTLD, не ccTLD).
    if (twoLevel.contains(parts[parts.length - 2]) &&
        parts[parts.length - 1].length == 2) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return parts.sublist(parts.length - 2).join('.');
  }

  static const _redirectCodes = [301, 302, 303, 307, 308];
  static const _maxHops = 3;

  /// Открывает [start], **проводя редиректы вручную** и спрашивая [allow] про
  /// КАЖДЫЙ адрес — и про сам [start], и про каждый переход. Отказ (или
  /// слишком длинная цепочка) — [_BlockedByGate].
  ///
  /// ⚠️ **`followRedirects` у `HttpClient` по умолчанию TRUE** (и
  /// `maxRedirects = 5`): без явного выключения клиент уходит по 30x САМ, ещё
  /// до того как код увидит статус, — и любой гейт на редиректах становится
  /// мёртвым кодом, который выглядит защитой. Именно так этот файл и жил один
  /// круг ревью. Строка `req.followRedirects = false` ниже — не украшение, без
  /// неё цикл не исполняется ни разу; стережёт `site_favicon_privacy_test`
  /// (настоящий сокет, 302 на чужой источник).
  static Future<HttpClientResponse> _openGated(
      HttpClient client, Uri start, bool Function(Uri) allow) async {
    var uri = start;
    if (!allow(uri)) throw const _BlockedByGate();
    for (var hop = 0;; hop++) {
      final req = await client.getUrl(uri);
      req.followRedirects = false; // ← без этого весь гейт ниже не исполняется
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final loc = resp.headers.value(HttpHeaders.locationHeader);
      if (!_redirectCodes.contains(resp.statusCode) || loc == null) return resp;
      await _drainQuietly(resp);
      if (hop >= _maxHops) throw const _BlockedByGate();
      final next = uri.resolve(loc);
      if (!allow(next)) throw const _BlockedByGate();
      uri = next;
    }
  }

  /// Дочитывает тело редиректа, чтобы соединение не осталось висеть. Тело у
  /// 30x пустое, но враждебный сервер может лить бесконечно — отсюда таймаут.
  static Future<void> _drainQuietly(HttpClientResponse resp) async {
    try {
      await resp.drain<void>().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// Скачивает [url], если это PNG. Один повтор на случай флапа сервера.
  /// [allow] решает про каждый адрес — и про [url], и про каждый редирект
  /// (в приложении — [iconGateFor]). Публичный ради теста-стража: проверить,
  /// что клиент не уходит по 30x сам, можно только настоящим сокетом.
  static Future<List<int>?> fetchIconBytes(
      Uri url, bool Function(Uri) allow) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6)
        ..userAgent = _ua;
      try {
        final resp = await _openGated(client, url, allow);
        if (resp.statusCode != 200) continue; // флап — один повтор
        final ct = resp.headers.contentType?.mimeType ?? '';
        // Ограничиваем и объём (фавикон — килобайты; иначе враждебный/битый ответ
        // раздул бы память), и время чтения тела (иначе зависший поток висел бы).
        const maxBytes = 512 * 1024;
        final bytes = <int>[];
        await for (final c in resp.timeout(const Duration(seconds: 8))) {
          bytes.addAll(c);
          if (bytes.length >= maxBytes) break;
        }
        // Признак PNG — либо Content-Type, либо магические байты.
        final isPng = ct == 'image/png' ||
            (bytes.length > 8 &&
                bytes[0] == 0x89 &&
                bytes[1] == 0x50 &&
                bytes[2] == 0x4e &&
                bytes[3] == 0x47);
        if (isPng && bytes.isNotEmpty) return bytes;
        return null; // ответ есть, но не PNG — повтор даст то же самое
      } on _BlockedByGate {
        return null; // увели в сторону: повтор даст тот же адрес
      } catch (_) {
        // сеть/таймаут — имеет смысл попробовать ещё раз
      } finally {
        client.close(force: true);
      }
    }
    return null;
  }
}

/// Адрес, по которому мы не пошли: не прошёл гейт (сам запрос либо редирект)
/// или цепочка редиректов слишком длинная. Отдельный тип, чтобы отличать его
/// от сетевого сбоя: на сбое повтор осмыслен, на отказе гейта — нет.
class _BlockedByGate implements Exception {
  const _BlockedByGate();
}
