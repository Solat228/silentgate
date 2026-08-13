import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/platform/app_log.dart';
import '../../core/platform/app_paths.dart';
import '../../core/probe/probe_harness.dart';
import '../../core/xray/harness_config_builder.dart';

/// Проброс-харнесс Android: замер идёт ОТДЕЛЬНЫМ экземпляром Xray внутри
/// нашего же процесса.
///
/// ⚠️ Долго считалось, что харнесса на Android быть не может: «VpnService в
/// приложении один». Это верно для ТУННЕЛЯ, но не для замера — `LibXray.ping`
/// поднимает свой `core.New` и гасит его сразу после измерения, не трогая
/// глобальный инстанс, занятый живым туннелем. Из-за неверного вывода
/// hysteria2 и панельные профили «Авто» не пингуались вообще: TCP у них нет
/// (QUIC / балансировщик по десяткам узлов), а вторая фаза требовала харнесса.
///
/// Конфиг собирает тот же построитель, что и на Windows, — включая ветку
/// полного конфига (профиль «Авто» со своим балансировщиком).
///
/// ⚠️ ИНБАУНД ЗДЕСЬ НАСТОЯЩИЙ, И ДО 1.4.2 ОН БЫЛ ОТКРЫТ. Замер только выглядит
/// «полностью нативным»: `LibXray.ping` поднимает НАШ конфиг целиком — то есть
/// http-инбаунд на 127.0.0.1 — и сам ходит через него по адресу из поля
/// `proxy`. Всё время прогона порт слушает, а loopback на Android между
/// приложениями НЕ изолирован: любое приложение с разрешением INTERNET могло
/// подключиться и получить туннель кандидата целиком (выходной IP, квота
/// подписки, обход правил пользователя). В 1.4.1 инбаунд закрыли паролем
/// только на Windows, а комментарии в обоих файлах утверждали, что боевой путь
/// креды выдаёт всегда. Теперь выдаёт: см. [builder] и [_AndroidHandle._proxyUrl].
class ProbeHarnessAndroid implements ProbeHarness {
  static const _channel = MethodChannel('lol.silentgate/probe');

  /// Построитель конфига — ВСЕГДА С КРЕДАМИ.
  ///
  /// Пароль свой на экземпляр, то есть на прогон: харнесс создаётся заново на
  /// каждый запуск пинга или подбора и живёт только пока идёт замер.
  ///
  /// ⚠️ ЧЕСТНО ПРО ОБА ПАРАМЕТРА: боевой путь не передаёт НИ ОДНОГО —
  /// `createProbeHarness()` зовёт `ProbeHarnessAndroid()` без аргументов, и
  /// другого места создания в `lib/` нет. Они нужны ТЕСТАМ: проверять нечего,
  /// пока порт и пароль каждый раз новые. Сигнатура при этом та же, что у
  /// `XrayHarnessWindows`, где [secret] боевой — там его задаёт
  /// `MixedProbeHarness`, чтобы оба ядра одного прогона закрылись одним
  /// паролем; здесь ядро одно, и такой нужды нет.
  final HarnessConfigBuilder builder;

  ProbeHarnessAndroid({HarnessPorts? ports, String? secret})
      : builder = HarnessConfigBuilder(ports: ports ?? const HarnessPorts())
            .withAuth(harnessProxyUser, secret ?? newHarnessSecret());

  /// Порт наружу не отдаётся: `LibXray.ping` поднимает ядро внутри вызова,
  /// ходит через инбаунд САМ и возвращает готовые миллисекунды. Задержку это
  /// даёт, доступность СЕРВИСОВ — нет (произвольный запрос послать некуда).
  @override
  bool get supportsProxyRequests => false;

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    final dir = await AppPaths.supportDir();
    final files = <String?>[];
    try {
      await _writeConfigs(entries, dir, files);
    } catch (_) {
      // ⚠️ УБОРКА НА ПУТИ ОШИБКИ, И ОНА НЕ ФОРМАЛЬНОСТЬ. Свалиться запись
      // может на любом кандидате (нет места, файл занят, каталог не тот) — и
      // на пятидесятом из ста пяти это значит полсотни уже записанных
      // конфигов, в каждом из которых пароль харнесса и учётные данные
      // сервера. Прибрать их некому: исключение уходит наверх ДО того, как
      // появится хендл, поэтому `finally` вызывающего (`ProbeController`,
      // `AutoConfigEngine`) зовёт `stop()` на `null` и не делает ничего.
      await _deleteConfigs(files);
      rethrow;
    }
    return _AndroidHandle(files, builder);
  }

  /// Пишет по конфигу на кандидата, складывая пути в [files] ПО ХОДУ ДЕЛА.
  ///
  /// ⚠️ Список пополняется именно здесь, а не возвращается целиком в конце:
  /// упавшему [start] нужно знать, что уже легло на диск, — иначе убирать
  /// нечего и незачем.
  Future<void> _writeConfigs(
    List<HarnessEntry> entries,
    Directory dir,
    List<String?> files,
  ) async {
    // По файлу на кандидата: `ping` принимает ПУТЬ к конфигу, а не JSON.
    for (var i = 0; i < entries.length; i++) {
      // ⚠️ libXray — это Xray, а он не умеет hysteria2 (QUIC + свой congestion
      // control). Собрать для него конфиг нельзя, и попытка замера пометила бы
      // рабочий сервер мёртвым. Такие кандидаты просто не меряются: их
      // состояние честно остаётся «не проверен», а по живому каналу
      // проверяется активный (см. ProbeController).
      if (entries[i].server.protocol == 'hysteria2') {
        files.add(null);
        continue;
      }
      // По одному кандидату на конфиг: `ping` меряет ОДИН outbound, а общий
      // харнесс Windows держит их пачкой на разных портах.
      //
      // ⚠️ ПОРТ — СВОЙ НА КАНДИДАТА, ИНАЧЕ ОНИ ДЕРУТСЯ ЗА ОДИН. Внутри своего
      // конфига кандидат всегда идёт под индексом 0, поэтому без сдвига базы
      // все они просили бы `HarnessPorts.base` (21000). А `ProbeController`
      // гоняет замеры пачкой (`Pool(pingConcurrency)`, по умолчанию 8
      // одновременно): второй бинд на занятый порт не проходит, `ping` молча
      // отдаёт пустоту, и сервер красится в «n/a» — плавающе, по тому, кто
      // успел первым. Ровно это и объясняло n/a, которые не воспроизводились
      // поштучно. Раскладка теперь та же, что на Windows: base + индекс.
      final json =
          builder.withPortBase(builder.portFor(i)).buildJson([entries[i]]);
      final f = File('${dir.path}${Platform.pathSeparator}probe_$i.json');
      // Путь запоминаем ДО записи: файл может быть создан и оборван на
      // середине — такой обрывок тоже надо убрать, а `delete` отсутствующего
      // файла проглатывается в [_deleteConfigs].
      files.add(f.path);
      await f.writeAsString(json);
    }
  }
}

/// Убрать временные конфиги харнесса. ОДНА уборка на оба пути: конец прогона
/// (`_AndroidHandle.stop`) и откат `start()`, упавшего на полпути. Две копии
/// этого цикла разъехались бы на первой же правке — а цена расхождения здесь
/// это файл с паролем инбаунда, оставшийся лежать в каталоге данных.
///
/// `null` в списке — кандидат, которому конфиг не писался вовсе (hysteria2);
/// ошибку удаления глотаем: убирать мусор ценой падения прогона незачем.
Future<void> _deleteConfigs(List<String?> paths) async {
  for (final p in paths) {
    if (p == null) continue;
    try {
      await File(p).delete();
    } catch (_) {}
  }
}

class _AndroidHandle implements HarnessHandle {
  _AndroidHandle(this._files, this._builder);

  final List<String?> _files;
  final HarnessConfigBuilder _builder;

  /// Креды инбаунда. Порт наружу не отдаётся (см. [proxyPortFor]), но пара
  /// едет тем же объектом по общему контракту [HarnessHandle]: пустые креды
  /// здесь означали бы «инбаунд открыт», а он закрыт.
  @override
  String get proxyUser => _builder.user;

  @override
  String get proxyPassword => _builder.password;

  /// Порта нет: замер делает нативная сторона целиком, наружу отдаётся сразу
  /// задержка. 0 означает «через порт не ходить» — вызывающий обязан это
  /// учитывать (см. [delayMs]).
  ///
  /// ⚠️ «Порта не отдаём» ≠ «порта нет»: инбаунд поднимается и слушает, просто
  /// его единственный потребитель — сам замер, см. [_proxyUrl].
  @override
  int proxyPortFor(int index) => 0;

  /// Адрес инбаунда для нативного замера — ВМЕСТЕ С КРЕДАМИ.
  ///
  /// ⚠️ Забыть их здесь — значит получить 407 на КАЖДОМ сервере и молчаливое
  /// «все мёртвые»: инбаунд отвергнет запрос собственного замера. Ровно на
  /// этом сгорел v2rayNG (#5549): включили аутентификацию, забыли прокинуть в
  /// потребителя. Поэтому пароль берётся из того же [_builder], который его в
  /// конфиг и положил, — разъехаться им негде.
  ///
  /// Почему basic-auth вообще доезжает: libXray отдаёт эту строку как есть в
  /// `http.Transport.Proxy` (`nodep.CoreHTTPClient` → `url.Parse`), а Go сам
  /// делает из userinfo заголовок `Proxy-Authorization` — для https-мишени
  /// (умолчание `generate_204`) в запросе CONNECT. Проверено по исходникам
  /// обоих, а не по документации.
  ///
  /// Экранирование не украшение: строка едет и в URL, и в JSON, который
  /// нативная сторона собирает конкатенацией. Сегодняшний алфавит
  /// [newHarnessSecret] — только буквы и цифры, но смена алфавита не должна
  /// молча ломать замер.
  ///
  /// ⚠️ ПОРТ — ТОЖЕ ПО ИНДЕКСУ КАНДИДАТА. Конфиг кандидата i собран с базой
  /// `base + i` (см. [ProbeHarnessAndroid.start]), и адрес обязан указывать на
  /// ТОТ ЖЕ порт: разъехавшись, замер стучался бы в чужой инбаунд (а при
  /// параллельном прогоне — в чужой туннель) или в никуда.
  String _proxyUrl(int index) {
    final creds = _builder.user.isEmpty
        ? ''
        : '${Uri.encodeComponent(_builder.user)}:'
            '${Uri.encodeComponent(_builder.password)}@';
    return 'http://${creds}127.0.0.1:${_builder.portFor(index)}';
  }

  /// Задержка кандидата в миллисекундах; `null` — не отвечает.
  @override
  Future<int?> delayMs(int index, {int timeoutSec = 5}) async {
    if (index < 0 || index >= _files.length) return null;
    final path = _files[index];
    if (path == null) return null; // hysteria2 — Xray его не поднимет
    try {
      final v = await ProbeHarnessAndroid._channel.invokeMethod<int>('ping', {
        'configPath': path,
        'timeout': timeoutSec,
        // ⚠️ Адрес инбаунда ОБЯЗАТЕЛЕН. Харнесс поднимает HTTP-прокси СВОЙ НА
        // КАЖДОГО КАНДИДАТА (`base + индекс`, см. [_proxyUrl]), а нативная
        // сторона без этого поля берёт `socks5://127.0.0.1:0` — и порт
        // несуществующий, и протокол не тот. Считать порт одним нельзя: из
        // этого предположения и вырос дефект с плавающими «n/a» — замер уходил
        // в инбаунд чужого кандидата.
        // Замер молча возвращал пустоту, а весь список серверов помечался
        // «отвечает по TCP, но не проксирует» — включая сервер, через который
        // пользователь в этот момент работал.
        'proxy': _proxyUrl(index),
      });
      return (v == null || v <= 0) ? null : v;
    } catch (e) {
      AppLog.w('Замер через libXray не удался: $e');
      return null;
    }
  }

  @override
  Future<void> stop() async {
    // Экземпляр ядра гасит сама нативная сторона (defer в libXray); нам
    // остаётся убрать временные конфиги — иначе они копятся в каталоге данных,
    // и в каждом лежит пароль своего прогона.
    await _deleteConfigs(_files);
  }
}
