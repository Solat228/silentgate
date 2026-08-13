import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/core/models/subscription_info.dart';
import 'package:silentgate/core/models/subscription_profile.dart';
import 'package:silentgate/core/models/subscription_sync.dart';
import 'package:silentgate/core/models/traffic_stats.dart';
import 'package:silentgate/core/models/vpn_server.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/parser/share_link_parser.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/platform/device_id.dart';
import 'package:silentgate/core/subscription/subscription_service.dart';
import 'package:silentgate/engine/vpn_engine.dart';
import 'package:silentgate/state/app_state.dart';

/// Движок-пустышка: `AppState` без него не собирается, а VPN тут ни при чём.
class _FakeEngine extends VpnEngine {
  @override
  set onCompactToggledInShade(void Function(bool compact)? handler) {}

  @override
  Stream<VpnStatus> get statusStream => const Stream.empty();

  @override
  Stream<TrafficStats> get statsStream => const Stream.empty();

  @override
  Stream<String> get blockedHostEvents => const Stream.empty();

  @override
  Stream<EngineNotice> get notices => const Stream.empty();

  @override
  VpnStatus get status => const VpnStatus.disconnected();

  @override
  Future<void> connect(VpnServer server,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> connectBalancer(List<VpnServer> servers,
      {ConnectionOptions options = const ConnectionOptions()}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}

/// Панель, которая отдаёт заранее заданный ответ. Сети нет: проверяется
/// проводка внутри `AppState`, а не HTTP.
class _FakePanel extends SubscriptionService {
  _FakePanel(this.result);

  SubscriptionResult result;
  int calls = 0;

  @override
  Future<SubscriptionResult> fetch(String url,
      {Map<String, String> deviceHeaders = const {}}) async {
    calls++;
    return result;
  }
}

/// Заглушка идентификатора устройства: настоящая на Windows лезет в реестр.
class _FakeDeviceId implements DeviceIdProvider {
  @override
  Future<String> hwid() async => 'test-hwid';
  @override
  String osName() => 'Test';
  @override
  Future<String> osVersion() async => '1.0';
  @override
  Future<String> deviceModel() async => 'TestModel';
}

/// Баннер обновления подписки обязан говорить правду.
///
/// ⚠️ ЖАЛОБА ВЛАДЕЛЬЦА (13.08.2026): у сервера «Москва 1. GRPC» КАЖДОЕ обновление
/// подписки писалось «+1 · −1», хотя серверы не менялись. Причина: состав
/// считался по [VpnServer.key], то есть по полной share-ссылке. Ссылка законно
/// меняется, когда панель поправила серверу отпечаток, sni или путь, — для
/// баннера это ложь, сервер никуда не девался.
///
/// Первая линия защиты — канонический ключ (см. `canonical_key_test.dart`).
/// Здесь — вторая: диф сравнивает состав по [VpnServer.identityKey], поэтому
/// баннер останется честным даже при будущем расхождении форматов.
void main() {
  const uuid = '00000000-0000-0000-0000-000000000000';

  String link({
    String host = 'ru1.example.com',
    int port = 443,
    String fp = 'chrome',
    String sni = 'a.example.org',
    String name = 'Москва 1. GRPC',
  }) =>
      'vless://$uuid@$host:$port?type=grpc&security=reality&encryption=none'
      '&sni=$sni&fp=$fp&pbk=KEY&sid=ab&path=my-service'
      // Пустое имя — не «решётка без ничего», а её отсутствие: именно так
      // приходит сервер, которому панель названия не дала.
      '${name.isEmpty ? '' : '#${Uri.encodeComponent(name)}'}';

  VpnServer parse(String l) {
    final s = ShareLinkParser.tryParse(l);
    expect(s, isNotNull, reason: 'ссылка теста должна разбираться: $l');
    return s!;
  }

  SubscriptionSyncResult diff(List<VpnServer> before, List<VpnServer> after) =>
      SubscriptionSyncResult.diff(
        before: before,
        after: after,
        withPanelConfig: 0,
        panelProfiles: 0,
        at: DateTime(2026, 8, 13),
      );

  group('Правка сервера — это не «+1 · −1»', () {
    test('сменился отпечаток: ни добавления, ни удаления', () {
      final was = parse(link(fp: 'chrome'));
      final now = parse(link(fp: 'firefox'));

      // Предпосылка теста: ключ действительно другой — иначе проверка ниже
      // была бы зелёной сама по себе и ничего не ловила.
      expect(was.key, isNot(now.key),
          reason: 'смена fp обязана менять ссылку, иначе тест бессмысленный');

      final r = diff([was], [now]);
      expect(r.added, isEmpty);
      expect(r.removed, isEmpty);
      expect(r.hasChanges, isFalse);
      expect(r.summary, contains('без изменений'));
    });

    test('сменился sni — тоже правка, а не пересоздание сервера', () {
      final r = diff([parse(link())], [parse(link(sni: 'b.example.org'))]);
      expect(r.added, isEmpty);
      expect(r.removed, isEmpty);
    });

    test('⚠️ ПО-СТАРОМУ (по ключу) вышло бы ровно +1 · −1 — это и был дефект', () {
      final was = parse(link(fp: 'chrome'));
      final now = parse(link(fp: 'firefox'));
      // Прежний счёт: карты по s.key. Воспроизводим его здесь, чтобы дефект был
      // виден в самом тесте, а не только в описании коммита.
      final byKeyBefore = {was.key};
      final byKeyAfter = {now.key};
      expect(byKeyAfter.difference(byKeyBefore), hasLength(1));
      expect(byKeyBefore.difference(byKeyAfter), hasLength(1));
    });
  });

  group('Настоящие изменения состава считаются как прежде', () {
    test('новый сервер — добавление', () {
      final old = parse(link());
      final fresh = parse(link(host: 'de1.example.com', name: 'Берлин 1'));
      final r = diff([old], [old, fresh]);
      expect(r.added, ['Берлин 1']);
      expect(r.removed, isEmpty);
      expect(r.total, 2);
      expect(r.hasChanges, isTrue);
    });

    test('исчезнувший сервер — удаление', () {
      final stay = parse(link());
      final gone = parse(link(host: 'de1.example.com', name: 'Берлин 1'));
      final r = diff([stay, gone], [stay]);
      expect(r.added, isEmpty);
      expect(r.removed, ['Берлин 1']);
    });

    test('другой порт того же хоста — другой сервер', () {
      final r = diff([parse(link(port: 443))], [parse(link(port: 8443))]);
      expect(r.added, hasLength(1));
      expect(r.removed, hasLength(1));
    });

    test('переименование — это добавление + удаление, и так и надо', () {
      // Человек узнаёт узел ПО ИМЕНИ: «Москва 1» вместо «Москва 2» для него
      // другой сервер, и умолчать об этом было бы такой же ложью, как «+1 · −1».
      final was = parse(link(name: 'Москва 1. GRPC'));
      final now = parse(link(name: 'Москва 2. GRPC'));
      final r = diff([was], [now]);
      expect(r.added, ['Москва 2. GRPC']);
      expect(r.removed, ['Москва 1. GRPC']);
    });

    test('пустая подписка: все серверы удалены', () {
      final r = diff([parse(link())], []);
      expect(r.removed, hasLength(1));
      expect(r.total, 0);
    });
  });

  group('Диагностика: ключ сменился, сервер тот же', () {
    test('названы ИМЕНА изменившихся полей', () {
      final r = diff([parse(link(fp: 'chrome'))], [parse(link(fp: 'firefox'))]);
      expect(r.keyChanges, hasLength(1));
      expect(r.keyChanges.single.fields, ['fingerprint']);
      expect(r.keyChanges.single.name, 'Москва 1. GRPC');

      final report = r.keyChangeReport;
      expect(report, hasLength(1));
      expect(report.single, contains('fingerprint'));
      expect(report.single, contains('Москва 1. GRPC'));
    });

    test('⚠️ ЗНАЧЕНИЯ НЕ ПИШУТСЯ: в ссылке лежат учётные данные', () {
      // uuid VLESS (у trojan/ss — пароль) уходит в отчёт поддержки вместе с
      // журналом, поэтому в диагностике допустимы только имена полей.
      final r = diff(
        [parse(link(fp: 'chrome'))],
        [parse(link(fp: 'firefox').replaceFirst(uuid, '11111111-1111-1111-1111-111111111111'))],
      );
      final all = r.keyChangeReport.join('\n');
      expect(all, isNot(contains(uuid)));
      expect(all, isNot(contains('11111111')));
      expect(all, isNot(contains('vless://')));
      expect(all, isNot(contains('chrome')));
      expect(all, isNot(contains('firefox')));
      expect(all, contains('id'), reason: 'имя поля назвать надо');
    });

    test('поля совпали, разошлась только запись ссылки', () {
      // Ровно тот случай, что съел данные владельца: gRPC приходил то с
      // `serviceName=`, то с `path=` — поля одинаковы, строка разная.
      final a = parse(link());
      final b = VpnServer(
        protocol: a.protocol,
        remark: a.remark,
        address: a.address,
        port: a.port,
        id: a.id,
        encryption: a.encryption,
        flow: a.flow,
        network: a.network,
        security: a.security,
        sni: a.sni,
        host: a.host,
        path: a.path,
        fingerprint: a.fingerprint,
        publicKey: a.publicKey,
        shortId: a.shortId,
        rawLink: '${a.rawLink}&legacy=1',
      );
      final r = diff([a], [b]);
      expect(r.added, isEmpty);
      expect(r.removed, isEmpty);
      expect(r.keyChanges.single.fields, isEmpty);
      expect(r.keyChangeReport.single, contains('только запись ссылки'));
    });

    test('одинаковые расхождения сворачиваются в одну строку журнала', () {
      // У владельца таких серверов было 190 — по строке на каждый вытеснило бы
      // из журнала всё остальное ротацией.
      final before = <VpnServer>[];
      final after = <VpnServer>[];
      for (var i = 0; i < 5; i++) {
        before.add(parse(link(host: 'ru$i.example.com', name: 'Москва $i')));
        after.add(parse(
            link(host: 'ru$i.example.com', name: 'Москва $i', fp: 'firefox')));
      }
      final r = diff(before, after);
      expect(r.keyChanges, hasLength(5));
      expect(r.keyChangeReport, hasLength(1), reason: 'одно расхождение — одна строка');
      expect(r.keyChangeReport.single, contains('5 шт.'));
      expect(r.keyChangeReport.single, contains('и ещё 2'),
          reason: 'примеров показываем три, остальные — числом');
    });

    test('состав не менялся — диагностики нет вовсе', () {
      final s = parse(link());
      final r = diff([s], [s]);
      expect(r.keyChanges, isEmpty);
      expect(r.keyChangeReport, isEmpty);
    });

    test('новый сервер в диагностику не попадает', () {
      final old = parse(link());
      final fresh = parse(link(host: 'de1.example.com', name: 'Берлин 1'));
      final r = diff([old], [old, fresh]);
      expect(r.keyChanges, isEmpty, reason: 'это добавление, а не смена ключа');
    });
  });

  group('Журнал не должен выдавать адрес сервера', () {
    // ⚠️ ЖАЛОБА, РАДИ КОТОРОЙ ЭТО ЕСТЬ. В строку журнала клали
    // `VpnServer.displayName`, а он при пустом имени вырождается в
    // «адрес:порт». Адрес сервера подписки — ровно то, что блокируют; строка
    // уходит в `app.log`, а он целиком вкладывается в отчёт поддержки, который
    // владелец пересылает в чат. `scrubSecrets` голое `host:port` не режет —
    // для него это обычный текст.

    test('⚠️ БЕЗ ИМЕНИ В ЖУРНАЛ УХОДИТ НОМЕР, А НЕ «адрес:порт»', () {
      final r = diff(
        [parse(link(name: '', host: 'ru7.example.com'))],
        [parse(link(name: '', host: 'ru7.example.com', fp: 'firefox'))],
      );
      final line = r.keyChangeReport.single;
      expect(line, isNot(contains('ru7.example.com')),
          reason: 'адрес в журнале — это и есть утечка');
      expect(line, isNot(contains('443')));
      expect(line, contains('сервер №1'));
      expect(r.keyChanges.single.name, 'сервер №1');
    });

    test('имя, в котором панель записала адрес, тоже подменяется', () {
      // Панель нередко зовёт узлы по хосту; «имя есть» тогда ничего не значит.
      final r = diff(
        [parse(link(name: 'ru7.example.com:443', host: 'ru7.example.com'))],
        [
          parse(link(
              name: 'ru7.example.com:443',
              host: 'ru7.example.com',
              fp: 'firefox'))
        ],
      );
      expect(r.keyChangeReport.single, isNot(contains('ru7.example.com')));
      expect(r.keyChanges.single.name, 'сервер №1');
    });

    test('⚠️ IP В НАЗВАНИИ ПРИ ДОМЕННОМ АДРЕСЕ — ТОТ ЖЕ АДРЕС В ЖУРНАЛЕ', () {
      // Обычная практика панели: в ссылке домен, в названии IP. Сверка имени с
      // `s.address` здесь молчит (общего текста нет), и до этой правки боевой
      // адрес узла уезжал в `app.log` дословно.
      final r = diff(
        [parse(link(name: 'DE-1 (***.***.***.***)', host: 'de1.panel.net'))],
        [
          parse(link(
              name: 'DE-1 (***.***.***.***)',
              host: 'de1.panel.net',
              fp: 'firefox'))
        ],
      );
      expect(r.keyChanges.single.name, 'сервер №1');
      expect(r.keyChangeReport.single, isNot(contains('***.***.***.***')));
    });

    test('IPv6 в названии тоже не печатается', () {
      final r = diff(
        [parse(link(name: 'NL [2a03:4000:8:1::5]', host: 'nl1.panel.net'))],
        [
          parse(link(
              name: 'NL [2a03:4000:8:1::5]',
              host: 'nl1.panel.net',
              fp: 'firefox'))
        ],
      );
      expect(r.keyChanges.single.name, 'сервер №1');
      expect(r.keyChangeReport.single, isNot(contains('2a03:4000')));
    });

    test('чужой домен и host:port в названии — тоже адрес', () {
      // Название указывает на ДРУГОЙ хост, чем ссылка: сверка с `s.address`
      // не сработает ни в одном из этих случаев.
      for (final leak in const [
        'Резерв через relay.other.net',
        'RU-2 relay.other.net:8443',
        'FR 185.199.108.153:443',
      ]) {
        final r = diff(
          [parse(link(name: leak, host: 'ru1.panel.net'))],
          [parse(link(name: leak, host: 'ru1.panel.net', fp: 'firefox'))],
        );
        expect(r.keyChanges.single.name, 'сервер №1',
            reason: 'в журнал ушло имя «$leak»');
      }
    });

    test('обычное имя от панели печатается как есть — иначе журнал бесполезен',
        () {
      final r = diff([parse(link())], [parse(link(fp: 'firefox'))]);
      expect(r.keyChanges.single.name, 'Москва 1. GRPC');
    });

    test('живые имена узлов адресом не считаются', () {
      // Обратная половина: проверка «похоже на адрес» обязана оставлять
      // читаемым нормальное название, иначе журнал превратится в столбик
      // номеров и станет бесполезен — а это ровно та беда, от которой имя в
      // нём и стоит.
      for (final ok in const [
        'Москва 1. GRPC',
        '🎬 Авто (YouTube)',
        'DE :: 01',
        'Нидерланды v2.5',
        'US-West 10 Gbps',
        'Тариф 1:1',
        'Сервер 2.0',
      ]) {
        final r = diff(
          [parse(link(name: ok, host: 'ru1.panel.net'))],
          [parse(link(name: ok, host: 'ru1.panel.net', fp: 'firefox'))],
        );
        expect(r.keyChanges.single.name, ok,
            reason: 'нормальное имя «$ok» подменено номером');
      }
    });

    test('⚠️ «СТРАНА-АДРЕС» — САМАЯ ЧАСТАЯ СХЕМА ИМЕНОВАНИЯ, И ОНА ПРОХОДИЛА',
        () {
      // ⚠️ РОВНО ЭТИ ДВЕ СТРОКИ ПРОВЕРКУ ПРОХОДИЛИ и уезжали в журнал
      // дословно: правило резало имя по символам, невозможным в адресе, а
      // буквы и дефис такими не являются — «nl-185.199.108.153» оставалось
      // одним куском, ни на что не похожим. Примеры настоящие, не выдуманные.
      for (final leak in const [
        'NL-185.199.108.153',
        'DE1-***.***.***.***',
      ]) {
        expect(SubscriptionSyncResult.looksLikeAddress(leak), isTrue,
            reason: 'адрес «$leak» признан безопасным именем');
        final r = diff(
          [parse(link(name: leak, host: 'ru1.panel.net'))],
          [parse(link(name: leak, host: 'ru1.panel.net', fp: 'firefox'))],
        );
        expect(r.keyChanges.single.name, 'сервер №1',
            reason: 'в журнал ушло имя «$leak»');
        expect(r.keyChangeReport.single, isNot(contains('185.199.108.153')));
        expect(r.keyChangeReport.single, isNot(contains('***.***.***.***')));
      }
    });

    test('looksLikeAddress: формы адреса и не-адреса перечислены поимённо', () {
      // Точечная проверка самого правила: через `diff` видна только развилка
      // «имя или номер», а класс дефекта живёт именно в разборе формы.
      for (final addr in const [
        '***.***.***.***',
        '***.***.***.***:443',
        '2a03:4000:8:1::5',
        '[2a03:4000:8:1::5]:443',
        'de1.panel.net',
        'de1.panel.net:8443',
        'sub.node.example.co.uk',
        'vless://uuid@de1.panel.net:443',
        // ⚠️ ФОРМА, А НЕ СОСЕДСТВО С РАЗДЕЛИТЕЛЕМ. Дефис, подчёркивание,
        // приклеенные вплотную буквы и скобки — всё это законное окружение
        // адреса, и ни одно из них не должно его прятать.
        'NL-185.199.108.153',
        'DE1-***.***.***.***',
        'ru_***.***.***.***',
        'nl185.199.108.153',
        'DE-1 (***.***.***.***)',
        'NL-2a03:4000:8:1::5',
        'fe80::1%wlan0',
        'Сборка 1.2.3.4',
      ]) {
        expect(SubscriptionSyncResult.looksLikeAddress(addr), isTrue,
            reason: 'адрес «$addr» признан безопасным именем');
      }
      for (final name in const [
        'Москва 1. GRPC',
        'Авто (YouTube)',
        'DE :: 01',
        'v2.5',
        '1:1',
        '10 Gbps',
        'Сервер №7',
        '',
      ]) {
        expect(SubscriptionSyncResult.looksLikeAddress(name), isFalse,
            reason: 'имя «$name» ошибочно принято за адрес');
      }
    });

    test('безымянные серверы различимы номерами', () {
      final before = <VpnServer>[], after = <VpnServer>[];
      for (var i = 0; i < 3; i++) {
        before.add(parse(link(name: '', host: 'ru$i.example.com')));
        after.add(parse(link(name: '', host: 'ru$i.example.com', fp: 'firefox')));
      }
      final r = diff(before, after);
      expect(r.keyChanges.map((c) => c.name).toList(),
          ['сервер №1', 'сервер №2', 'сервер №3']);
      final line = r.keyChangeReport.single;
      for (var i = 0; i < 3; i++) {
        expect(line, isNot(contains('ru$i.example.com')));
      }
    });

    test('номер считает РАЗЛИЧНЫЕ серверы: дубликат от панели его не сдвигает',
        () {
      // ⚠️ ЧТО ЗДЕСЬ ЗАФИКСИРОВАНО И ЧЕГО НЕ ОБЕЩАНО. Номер — это позиция в
      // списке, который прислала ПАНЕЛЬ, после схлопывания дублей по
      // тождеству (панель законно присылает один узел дважды). Сопоставим он
      // только с выдачей панели: на экране приложения порядок другой —
      // закреплённые серверы уезжают наверх, — поэтому «сервер №2» и вторая
      // строка списка это разные серверы, и утверждать обратное нельзя.
      final alpha = parse(link(name: 'Alpha', host: 'a.example.com'));
      final r = diff(
        [alpha, parse(link(name: '', host: 'ru9.example.com'))],
        [
          alpha,
          alpha, // тот же сервер вторым разом — своей позиции не занимает
          parse(link(name: '', host: 'ru9.example.com', fp: 'firefox')),
        ],
      );
      expect(r.keyChanges.single.name, 'сервер №2',
          reason: 'нумерация пошла по сырому списку панели, а не по различным '
              'серверам — номера разъедутся на первом же дубликате');
    });

    test('номер считается по НОВОМУ списку, а не по числу расхождений', () {
      // Сменил ключ только третий сервер — значит и номер у него третий.
      final same = parse(link(name: 'Alpha', host: 'a.example.com'));
      final same2 = parse(link(name: 'Bravo', host: 'b.example.com'));
      final r = diff(
        [same, same2, parse(link(name: '', host: 'ru9.example.com'))],
        [
          same,
          same2,
          parse(link(name: '', host: 'ru9.example.com', fp: 'firefox')),
        ],
      );
      expect(r.keyChanges.single.name, 'сервер №3');
    });
  });

  group('Проводка в AppState — код ВЫПОЛНЯЕТСЯ, а не читается как текст', () {
    // ⚠️ ЧТО ЗДЕСЬ БЫЛО РАНЬШЕ И ПОЧЕМУ ЭТОГО МАЛО. Три теста читали ИСХОДНЫЙ
    // ТЕКСТ `lib/state/app_state.dart` и искали в нём подстроки. Такой тест
    // краснеет только от дословного отката и молчит, когда: аргументы
    // `before:`/`after:` переставлены местами, счётчики панели уехали не в те
    // параметры, цикл записи в журнал остался, но перестал что-либо писать,
    // код переехал в соседний файл. Здесь `importSource` выполняется
    // по-настоящему — панель подменена фейком, сети нет ни одного запроса.

    const url = 'https://panel.example/sub/token';
    const logoUrl = 'https://panel.example/logo.png';
    final id = SubscriptionProfile.idFor(url);
    Directory? tmp;

    setUp(() => setDeviceIdProviderForTests(_FakeDeviceId()));

    tearDown(() async {
      setDeviceIdProviderForTests(null);
      await AppLog.resetFileForTest();
      // Дать досчитать фоновым цепочкам импорта: подмену каталога снимаем
      // ПОСЛЕ них, иначе запись пошла бы резолвить каталог заново.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      AppPaths.resetForTests();
      try {
        tmp?.deleteSync(recursive: true);
      } catch (_) {}
      tmp = null;
    });

    /// Поднять `AppState` с подпиской [onDisk] и отдать ему [fromPanel].
    Future<AppState> importInto({
      required List<String> onDisk,
      required List<VpnServer> fromPanel,
    }) async {
      tmp = Directory.systemTemp.createTempSync('sg_sync_wiring_');
      AppPaths.overrideRoot(tmp!);
      final sep = Platform.pathSeparator;
      // ⚠️ ЛОГОТИП ПОДСОВЫВАЕМ ГОТОВЫЙ. `importSource` тянет аватарку панели, и
      // без этого тест ушёл бы в сеть. Адрес логотипа совпал с сохранённым, файл
      // на месте — `_refreshLogo` выходит, не сделав ни одного запроса.
      final logo = File('${tmp!.path}${sep}logo.png')
        ..writeAsBytesSync(const [0x89, 0x50, 0x4e, 0x47]);
      // Автообновление по таймеру завело бы таймер и полезло на version-эндпоинт.
      File('${tmp!.path}${sep}silentgate_settings.json')
          .writeAsStringSync(jsonEncode({'autoUpdateEnabled': false}));
      File('${tmp!.path}${sep}subscriptions.json').writeAsStringSync(jsonEncode({
        'activeId': id,
        'items': [
          {
            'id': id,
            'url': url,
            'servers': onDisk,
            'logoUrl': logoUrl,
            'logoPath': logo.path,
            // ⚠️ ДАТУ ДОБАВЛЕНИЯ ЗАДАЁМ ЯВНО, И ЭТО НЕ УКРАШЕНИЕ ФИКСТУРЫ.
            // Профилю без `addedAt` `AppState.init` проставляет её сам и уходит
            // в ФОНОВУЮ запись (`unawaited(_saveSubscriptions())`). Тест к тому
            // времени успевает сбросить подмену каталога в `tearDown` — и
            // запись пошла бы резолвить каталог заново, то есть в боевой
            // `%APPDATA%` владельца. Сегодня её ловит предохранитель
            // `AppPaths`, но правильно — не создавать такой записи вовсе.
            'addedAt': '2026-08-01T00:00:00.000Z',
          },
        ],
      }));

      final panel = _FakePanel(SubscriptionResult(
        fromPanel,
        const SubscriptionInfo(logoUrl: logoUrl),
      ));
      final state = AppState(engine: _FakeEngine(), subscription: panel);
      await state.init();
      // Журнал начинаем с чистого листа: строки самого запуска нас не касаются.
      await AppLog.resetFileForTest();
      await state.importSource(url);
      expect(state.error, isNull, reason: 'импорт не должен падать');
      expect(panel.calls, 1, reason: 'подписка обязана быть запрошена ровно раз');
      return state;
    }

    test('состав считает настоящий диф: «до» с диска, «после» от панели',
        () async {
      // На диске Alpha и Bravo; панель прислала Alpha (с другим отпечатком),
      // Charlie и Delta. Числа и стороны намеренно РАЗНЫЕ: при перестановке
      // `before:`/`after:` местами тест краснеет по каждой строке.
      final state = await importInto(
        onDisk: [
          link(name: 'Alpha', host: 'a.example.com'),
          link(name: 'Bravo', host: 'b.example.com'),
        ],
        fromPanel: [
          parse(link(name: 'Alpha', host: 'a.example.com', fp: 'firefox')),
          parse(link(name: 'Charlie', host: 'c.example.com')),
          parse(link(name: 'Delta', host: 'd.example.com')),
        ],
      );

      final r = state.lastSync!;
      expect(r.added, ['Charlie', 'Delta']);
      expect(r.removed, ['Bravo']);
      expect(r.total, 3,
          reason: 'считается НОВЫЙ список; 2 — это «до» и «после» наоборот');
      expect(r.keyChanges.single.fields, ['fingerprint'],
          reason: 'Alpha на месте, у неё сменился только отпечаток');
    });

    test('счётчики конфигов панели не перепутаны местами', () async {
      // Два сервера с outbound'ом панели и ОДИН профиль «Авто»: числа разные
      // намеренно — на одинаковых перестановка аргументов была бы невидима.
      final withOutbound = parse(link(name: 'Alpha', host: 'a.example.com'))
          .copyWith(rawOutboundJson: '{"tag":"proxy"}');
      final withOutbound2 = parse(link(name: 'Bravo', host: 'b.example.com'))
          .copyWith(rawOutboundJson: '{"tag":"proxy"}');
      final profile = parse(link(name: '🎬 Авто', host: 'c.example.com'))
          .copyWith(rawPanelConfig: '{"outbounds":[]}');

      final state = await importInto(
        onDisk: const [],
        fromPanel: [withOutbound, withOutbound2, profile],
      );

      final r = state.lastSync!;
      expect(r.withPanelConfig, 2);
      expect(r.panelProfiles, 1);
    });

    test('диагностика смены ключа реально уходит в журнал', () async {
      final state = await importInto(
        onDisk: [link(name: 'Alpha', host: 'a.example.com')],
        fromPanel: [
          parse(link(name: 'Alpha', host: 'a.example.com', fp: 'firefox'))
        ],
      );

      final expected = state.lastSync!.keyChangeReport.single;
      final warnings = AppLog.entries
          .where((e) => e.level == LogLevel.warn)
          .map((e) => e.message)
          .toList();
      expect(warnings, contains(expected),
          reason: 'цикл записи в журнал может остаться и перестать писать');
    });

    test('сводка обновления тоже попадает в журнал', () async {
      final state = await importInto(
        onDisk: [link(name: 'Alpha', host: 'a.example.com')],
        fromPanel: [
          parse(link(name: 'Alpha', host: 'a.example.com')),
          parse(link(name: 'Bravo', host: 'b.example.com')),
        ],
      );
      final all = AppLog.entries.map((e) => e.message).join('\n');
      expect(all, contains(state.lastSync!.summary));
    });

    test('⚠️ АДРЕС БЕЗЫМЯННОГО СЕРВЕРА В `app.log` НЕ ПОПАДАЕТ', () async {
      // Сквозная проверка: не «функция вернула правильное», а «в журнале
      // приложения этого нет». Именно журнал уезжает в отчёт поддержки.
      await importInto(
        onDisk: [link(name: '', host: 'ru7.example.com')],
        fromPanel: [
          parse(link(name: '', host: 'ru7.example.com', fp: 'firefox'))
        ],
      );
      final all = AppLog.entries.map((e) => e.message).join('\n');
      expect(all, contains('Ключ сервера сменился'),
          reason: 'предпосылка: диагностика вообще была записана');
      expect(all, isNot(contains('ru7.example.com')));
    });

    test('⚠️ IP, ЗАПИСАННЫЙ ПАНЕЛЬЮ В НАЗВАНИЕ, В `app.log` НЕ ПОПАДАЕТ',
        () async {
      // Сквозная проверка второго класса утечки: имя есть, адрес ссылки в нём
      // не встречается — и всё-таки это адрес. `scrubSecrets` голый IP не
      // режет, а `app.log` целиком уезжает в отчёт поддержки.
      await importInto(
        onDisk: [link(name: 'DE-1 (***.***.***.***)', host: 'de1.panel.net')],
        fromPanel: [
          parse(link(
              name: 'DE-1 (***.***.***.***)',
              host: 'de1.panel.net',
              fp: 'firefox'))
        ],
      );
      final all = AppLog.entries.map((e) => e.message).join('\n');
      expect(all, contains('Ключ сервера сменился'),
          reason: 'предпосылка: диагностика вообще была записана');
      expect(all, isNot(contains('***.***.***.***')));
      expect(all, isNot(contains('de1.panel.net')));
    });

    test('состав не изменился — «без изменений», и диагностики нет', () async {
      final state = await importInto(
        onDisk: [link(name: 'Alpha', host: 'a.example.com')],
        fromPanel: [parse(link(name: 'Alpha', host: 'a.example.com'))],
      );
      expect(state.lastSync!.hasChanges, isFalse);
      expect(state.lastSync!.keyChanges, isEmpty);
      expect(
          AppLog.entries.where((e) => e.level == LogLevel.warn).map((e) => e.message),
          isNot(contains(startsWith('Ключ сервера сменился'))));
    });
  });
}
