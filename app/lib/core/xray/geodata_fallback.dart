import 'dart:convert';

import 'private_networks.dart';

/// Что пришлось сделать с конфигом из-за отсутствующих гео-баз.
class GeodataFallbackReport {
  /// Заменённые на явные подсети ссылки (`geoip:private`).
  final int replaced;

  /// Выброшенные ссылки, которым замены нет (`geoip:ru`, `geosite:*`).
  final int dropped;

  /// Правила, удалённые целиком, потому что от них не осталось условий.
  final int rulesRemoved;

  /// Имена выброшенных категорий — для честного сообщения пользователю.
  final List<String> categories;

  /// ⚠️ ПОСЛЕ ЧИСТКИ ССЫЛКИ ВСЁ РАВНО ОСТАЛИСЬ.
  ///
  /// Значит мы не знаем какого-то места, где они лежат, и ядро отвергнет
  /// конфиг несмотря на «страховку». Молчать тут нельзя: снаружи это выглядит
  /// как «запасной путь есть и не сработал», а разбираться будет некому.
  final bool residual;

  const GeodataFallbackReport({
    this.replaced = 0,
    this.dropped = 0,
    this.rulesRemoved = 0,
    this.categories = const [],
    this.residual = false,
  });

  bool get changed => replaced > 0 || dropped > 0 || rulesRemoved > 0;

  /// Строка для журнала и для подсказки в интерфейсе.
  String describe() {
    final parts = <String>[];
    if (replaced > 0) parts.add('$replaced заменено явными подсетями');
    if (dropped > 0) {
      parts.add('$dropped отброшено (${categories.take(6).join(", ")}'
          '${categories.length > 6 ? ', …' : ''})');
    }
    if (rulesRemoved > 0) parts.add('$rulesRemoved правил удалено целиком');
    return parts.join('; ');
  }
}

/// Результат: конфиг без ссылок на гео-базы плюс отчёт.
class GeodataFallbackResult {
  final String json;
  final GeodataFallbackReport report;
  const GeodataFallbackResult(this.json, this.report);
}

/// Убирает из конфига Xray ссылки на `geoip:`/`geosite:`, когда гео-баз нет.
///
/// ⚠️ ЗАЧЕМ ЭТО СУЩЕСТВУЕТ. Xray резолвит такие ссылки по файлам `geoip.dat` и
/// `geosite.dat` **на устройстве**. На Android их нет: в APK они не кладутся, и
/// ядро ищет их в рабочем каталоге процесса. В журнале владельца это выглядело
/// так:
///
/// ```
/// failed to parse json config > failed to build routing configuration
///   > invalid field rule > illegal ip rule: geoip:private
///   > failed to open geoip.dat > stat /system/bin/geoip.dat: no such file
/// ```
///
/// и на этом **весь VPN-сервис останавливался**. У владельца ссылки на гео-базы
/// есть в 46 панельных профилях из 250 — то есть «Авто» с российской
/// маршрутизацией на телефоне не поднимался вовсе.
///
/// ⚠️ САМОЕ ОПАСНОЕ МЕСТО — ПУСТОЕ ПРАВИЛО. Правило вида
/// `{"ip":["geoip:ru"],"outboundTag":"direct"}` после вычистки списка
/// превратилось бы в `{"outboundTag":"direct"}` — то есть в БЕЗУСЛОВНЫЙ увод
/// ВСЕГО трафика мимо VPN. Тихая утечка реального IP вместо честной ошибки.
/// Поэтому правило, у которого не осталось ни одного условия, удаляется
/// целиком, а не «упрощается».
///
/// `geoip:private` — единственная ссылка с точной заменой: это фиксированный
/// список приватных диапазонов, он лежит в [kPrivateNetworks]. Остальным
/// (`geoip:ru`, `geosite:category-ru`…) замены нет: списки живут в самих
/// файлах. Их условия выбрасываются, и трафик, который они уводили напрямую,
/// пойдёт по общему правилу — то есть через VPN. Это медленнее, но безопасно:
/// обратный выбор означал бы пускать мимо туннеля то, о чём мы ничего не знаем.
GeodataFallbackResult stripGeodata(String json) {
  // ⚠️ Разбор в try. Функция стоит НА ПУТИ ПОДКЛЮЧЕНИЯ, и исключение отсюда
  // выглядело бы как ошибка нашей обработки, хотя виноват входной конфиг.
  // Пусть битый конфиг отвергнет ядро — оно скажет об этом внятнее нас.
  final Object? root;
  try {
    root = jsonDecode(json);
  } catch (_) {
    return GeodataFallbackResult(json, const GeodataFallbackReport());
  }
  if (root is! Map<String, dynamic>) {
    return GeodataFallbackResult(json, const GeodataFallbackReport());
  }
  var replaced = 0, dropped = 0, rulesRemoved = 0;
  final categories = <String>{};
  final kept = <dynamic>[];

  // ⚠️ БЕЗ РАННЕГО ВЫХОДА. Раньше отсутствие `routing.rules` заканчивало работу
  // сразу — и секция `dns` оставалась нетронутой у конфигов, где ссылки лежат
  // только там. Разбираем то, что есть, и идём дальше.
  final routing = root['routing'];
  final rules = (routing is Map) ? routing['rules'] : null;

  for (final rule in (rules is List ? rules : const [])) {
    if (rule is! Map) {
      kept.add(rule);
      continue;
    }
    // Было ли правило вообще сужено по адресу или домену. Правило без таких
    // условий (например `{inboundTag:[…]}` или хвостовой catch-all) трогать
    // нельзя — оно и раньше было безусловным, это его законная форма.
    final hadIp = rule['ip'] is List && (rule['ip'] as List).isNotEmpty;
    final hadDomain = rule['domain'] is List && (rule['domain'] as List).isNotEmpty;

    if (hadIp) {
      final out = <dynamic>[];
      for (final e in (rule['ip'] as List)) {
        final s = '$e';
        if (s == 'geoip:private') {
          out.addAll(kPrivateNetworks);
          replaced++;
        } else if (s.startsWith('geoip:') || s.startsWith('geosite:')) {
          categories.add(s);
          dropped++;
        } else {
          out.add(e);
        }
      }
      rule['ip'] = out;
    }
    if (hadDomain) {
      final out = <dynamic>[];
      for (final e in (rule['domain'] as List)) {
        final s = '$e';
        if (s.startsWith('geosite:') || s.startsWith('geoip:')) {
          categories.add(s);
          dropped++;
        } else {
          out.add(e);
        }
      }
      rule['domain'] = out;
    }

    // ⚠️ ВОТ ЗДЕСЬ И ЖИВЁТ УТЕЧКА, ЕСЛИ ОШИБИТЬСЯ.
    // Правило было сужено, а после вычистки условий не осталось — значит оно
    // стало безусловным. Удаляем.
    final ipNowEmpty = hadIp && (rule['ip'] as List).isEmpty;
    final domainNowEmpty = hadDomain && (rule['domain'] as List).isEmpty;
    final nothingLeft = (hadIp || hadDomain) &&
        (!hadIp || ipNowEmpty) &&
        (!hadDomain || domainNowEmpty);
    if (nothingLeft) {
      rulesRemoved++;
      continue;
    }
    // Пустые списки убираем: Xray не любит `"ip": []`, а смысла в них нет.
    if (ipNowEmpty) rule.remove('ip');
    if (domainNowEmpty) rule.remove('domain');
    kept.add(rule);
  }

  if (routing is Map && rules is List) routing['rules'] = kept;

  // ⚠️ ССЫЛКИ ЖИВУТ НЕ ТОЛЬКО В МАРШРУТАХ. У встроенного DNS Xray свои
  // серверы со списком доменов (`dns.servers[].domains`), и туда тоже пишут
  // `geosite:`. Первая версия чистила лишь `routing.rules`: конфиг выглядел
  // обработанным, `changed` оставался false, лог молчал — а ядро всё равно
  // падало. Тот же почерк, что мы ловим в этом проекте девятый раз.
  final dns = root['dns'];
  if (dns is Map) {
    final servers = dns['servers'];
    if (servers is List) {
      for (final srv in servers) {
        if (srv is! Map) continue;
        final domains = srv['domains'];
        if (domains is! List) continue;
        final out = <dynamic>[];
        for (final e in domains) {
          final s = '$e';
          if (s.startsWith('geosite:') || s.startsWith('geoip:')) {
            categories.add(s);
            dropped++;
          } else {
            out.add(e);
          }
        }
        if (out.isEmpty) {
          srv.remove('domains');
        } else {
          srv['domains'] = out;
        }
      }
    }
  }

  final encoded = jsonEncode(root);
  final report = GeodataFallbackReport(
    replaced: replaced,
    dropped: dropped,
    rulesRemoved: rulesRemoved,
    categories: categories.toList()..sort(),
    // Перепроверяем СВОЙ ЖЕ результат: дешевле одной строки кода, а ловит
    // ровно тот случай, когда мы чего-то не знаем о формате конфига.
    residual: needsGeodata(encoded),
  );
  if (!report.changed && !report.residual) {
    return GeodataFallbackResult(json, report);
  }
  return GeodataFallbackResult(encoded, report);
}

/// Есть ли в конфиге ссылки на гео-базы (быстрая проверка без разбора JSON).
///
/// Нужна, чтобы не трогать конфиг зря и чтобы понимать, стоит ли предлагать
/// пользователю скачать файлы.
bool needsGeodata(String json) =>
    json.contains('geoip:') || json.contains('geosite:');
