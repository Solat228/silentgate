import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/app_info.dart';
import 'package:silentgate/core/platform/apk_installer_android.dart';
import 'package:silentgate/core/update/app_update.dart';
import 'package:silentgate/core/update/app_update_defaults.dart';

/// ПРОВЕРКА ОБНОВЛЕНИЙ: ТРИ ИСХОДА, А НЕ ДВА.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. Раньше `check()` отдавала `null` И когда обновления
/// нет, И когда проверить не удалось. Интерфейс показывал «у вас последняя
/// версия» человеку, у которого просто не было сети или чей запрос упёрся в
/// часовой лимит GitHub. Сказать «всё в порядке», не проверив, — худший вид
/// лжи в проверке обновлений: после неё пользователь перестаёт проверять сам.
///
/// Сеть здесь не нужна нигде: `check` принимает подменённый загрузчик, а разбор
/// ответа вынесен в чистую функцию.
void main() {
  String release({
    String tag = 'v9.9.9',
    List<Map<String, String>> assets = const [],
    String body = 'Что нового',
    String page = 'https://github.com/o/r/releases/tag/v9.9.9',
  }) =>
      jsonEncode({
        'tag_name': tag,
        'html_url': page,
        'body': body,
        'assets': [
          for (final a in assets)
            {'name': a['name'], 'browser_download_url': a['url']},
        ],
      });

  UpdateFetcher ok(String body, {Map<String, String> headers = const {}}) =>
      (_) async => UpdateHttpResponse(200, body, headers: headers);

  UpdateFetcher code(int status, {Map<String, String> headers = const {}}) =>
      (_) async => UpdateHttpResponse(status, '', headers: headers);

  group('Три исхода различимы', () {
    test('⚠️ ГЛАВНОЕ: отказ сети — это НЕ «у вас последняя версия»', () async {
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: (_) async => throw const SocketExceptionStub(),
      );
      expect(r.state, UpdateCheckState.failed,
          reason: 'ЗДЕСЬ БЫЛА ЛОЖЬ: молчаливый null читался как «обновлений нет»');
      expect(r.failure, isNotNull,
          reason: 'пользователю надо сказать, ЧТО пошло не так');
      expect(r.release, isNull);
    });

    test('новее нашей — доступно', () async {
      final r = await AppUpdate.check(
          assetHint: 'Setup.exe', fetcher: ok(release(tag: 'v99.0.0')));
      expect(r.state, UpdateCheckState.available);
      expect(r.release!.version, '99.0.0');
    });

    test('наша же версия — последняя, и это ПРОВЕРЕННЫЙ ответ', () async {
      final r = await AppUpdate.check(
          assetHint: 'Setup.exe', fetcher: ok(release(tag: 'v${AppInfo.version}')));
      expect(r.state, UpdateCheckState.upToDate);
      expect(r.isFailed, isFalse);
    });

    test('старее нашей — тоже «последняя», а не откат', () async {
      final r = await AppUpdate.check(
          assetHint: 'Setup.exe', fetcher: ok(release(tag: 'v0.0.1')));
      expect(r.state, UpdateCheckState.upToDate);
    });
  });

  group('Отказы GitHub различаются по причине', () {
    test('404 — закрытый репозиторий или релизов нет', () async {
      final r = await AppUpdate.check(assetHint: 'Setup.exe', fetcher: code(404));
      expect(r.state, UpdateCheckState.failed);
      expect(r.failure, contains('релиз'),
          reason: 'причина обязана быть узнаваемой, а не «ошибка 404»');
    });

    test('⚠️ исчерпан часовой лимит — отдельная причина', () async {
      // 60 запросов в час на АДРЕС для неавторизованных: за одним адресом
      // сидит вся квартира или офис, так что случай не экзотический.
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: code(403, headers: {'x-ratelimit-remaining': '0'}),
      );
      expect(r.failure, contains('час'),
          reason: 'человеку надо понять, что дело во времени, а не в поломке');
    });

    test('403 без исчерпанного лимита — это отказ в доступе', () async {
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: code(403, headers: {'x-ratelimit-remaining': '42'}),
      );
      expect(r.state, UpdateCheckState.failed);
      expect(r.failure, isNot(contains('час')));
    });

    test('сбой на стороне сервера', () async {
      final r = await AppUpdate.check(assetHint: 'Setup.exe', fetcher: code(503));
      expect(r.state, UpdateCheckState.failed);
    });

    test('⚠️ двухсотый ответ, который не разбирается, — тоже отказ', () async {
      final r = await AppUpdate.check(
          assetHint: 'Setup.exe', fetcher: ok('<html>не json</html>'));
      expect(r.state, UpdateCheckState.failed,
          reason: 'иначе мусор в ответе выдавался бы за «обновлений нет»');
    });
  });

  group('Разбор релиза GitHub', () {
    test('приставка v у тега снимается', () {
      final r = AppUpdate.parseGithubRelease(release(tag: 'v1.4.4'),
          assetHint: 'Setup.exe');
      expect(r!.version, '1.4.4',
          reason: '«доступна v1.4.4» рядом с «у вас 1.4.3» читается как разные '
              'системы нумерации');
    });

    test('артефакт выбирается по платформе', () {
      const body = [
        {'name': 'SilentGate-1.4.4-arm64-v8a.apk', 'url': 'https://x/apk'},
        {'name': 'SilentGateSetup.exe', 'url': 'https://x/exe'},
      ];
      final win = AppUpdate.parseGithubRelease(release(assets: body),
          assetHint: 'Setup.exe');
      final droid = AppUpdate.parseGithubRelease(release(assets: body),
          assetHint: 'arm64-v8a.apk');
      expect(win!.downloadUrl, 'https://x/exe');
      expect(droid!.downloadUrl, 'https://x/apk');
    });

    test('⚠️ x86_64-сборка НЕ подсовывается телефону', () {
      // Обе наши APK содержат «.apk», и поиск по расширению отдал бы первую
      // попавшуюся — на телефон встала бы сборка для эмулятора.
      const body = [
        {'name': 'SilentGate-1.4.4-x86_64.apk', 'url': 'https://x/emu'},
        {'name': 'SilentGate-1.4.4-arm64-v8a.apk', 'url': 'https://x/phone'},
      ];
      final r = AppUpdate.parseGithubRelease(release(assets: body),
          assetHint: 'arm64-v8a.apk');
      expect(r!.downloadUrl, 'https://x/phone');
    });

    test('артефакта под платформу нет — версия всё равно известна', () {
      // Релиз бывает собран под одну платформу. Это не повод считать проверку
      // неудачной: сказать «есть 1.4.4» и открыть страницу полезнее молчания.
      final r = AppUpdate.parseGithubRelease(
          release(assets: const [
            {'name': 'SilentGateSetup.exe', 'url': 'https://x/exe'}
          ]),
          assetHint: 'arm64-v8a.apk');
      expect(r!.version, '9.9.9');
      expect(r.downloadUrl, isNull);
      expect(r.pageUrl, isNotEmpty, reason: 'кнопке «Скачать» нужно куда вести');
    });

    test('без тега разбор не удаётся', () {
      expect(
          AppUpdate.parseGithubRelease(jsonEncode({'body': 'пусто'}),
              assetHint: 'Setup.exe'),
          isNull);
    });

    test('страница релиза берётся из ответа, иначе — общая', () {
      final r = AppUpdate.parseGithubRelease(
          jsonEncode({'tag_name': 'v2.0.0'}), assetHint: 'Setup.exe');
      expect(r!.pageUrl, kGithubReleasesPage);
    });
  });

  group('Сравнение версий', () {
    test('по числам, а не по строкам', () {
      expect(AppUpdate.isNewer('1.4.10', '1.4.9'), isTrue,
          reason: 'строкой «1.4.10» меньше «1.4.9» — классическая ловушка');
      expect(AppUpdate.isNewer('1.4.3', '1.4.3'), isFalse);
      expect(AppUpdate.isNewer('1.4.2', '1.4.3'), isFalse);
      expect(AppUpdate.isNewer('2.0.0', '1.99.99'), isTrue);
    });

    // Раньше суффикс игнорировался: стабильная 1.14.1 и бета 1.14.1-beta.2
    // считались одной версией, и поставивший бету не получал стабильную.
    test('стабильная новее своей беты, бета — не новее стабильной', () {
      expect(AppUpdate.isNewer('1.14.1', '1.14.1-beta'), isTrue);
      expect(AppUpdate.isNewer('1.14.1', '1.14.1-beta.2'), isTrue);
      expect(AppUpdate.isNewer('1.14.1-beta.1', '1.14.1'), isFalse);
      expect(AppUpdate.isNewer('v1.14.1-beta.1', '1.14.0'), isTrue,
          reason: 'числа по-прежнему решают первыми');
    });

    test('беты одного номера — по номеру беты, но только когда он известен', () {
      expect(AppUpdate.isNewer('1.14.1-beta.2', '1.14.1-beta.1'), isTrue);
      expect(AppUpdate.isNewer('1.14.1-beta.1', '1.14.1-beta.2'), isFalse);
      expect(AppUpdate.isNewer('1.14.1-beta.10', '1.14.1-beta.9'), isTrue);
      // Установленная бета знает только, что она бета (AppInfo.isBeta), —
      // без оговорки та же бета предлагалась бы при каждой проверке.
      expect(AppUpdate.isNewer('1.14.1-beta.1', '1.14.1-beta'), isFalse);
      expect(AppUpdate.isNewer('1.14.1-beta.3', '1.14.1-beta'), isFalse);
    });
  });

  group('Запасной источник — наш сайт', () {
    // ⚠️ ЗАЧЕМ ОН ЕСТЬ. У владельца `api.github.com` не открывается вовсе: TLS
    // падает с несовпадением имени в сертификате (воспроизведено в чистой VM
    // без VPN, при живом github.com). Клиентом пользуются там, где интернет
    // фильтруют, — «основной источник недоступен» здесь обычное дело.

    UpdateFetcher pair({required int githubCode, String? panelBody}) =>
        (uri) async => uri.host.contains('github')
            ? UpdateHttpResponse(githubCode, '')
            : UpdateHttpResponse(panelBody == null ? 500 : 200, panelBody ?? '');

    test('⚠️ ГЛАВНОЕ: GitHub недоступен — отвечает сайт', () async {
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: pair(
            githubCode: 403,
            panelBody: '{"version":"99.9.9","url":"https://x/y.exe"}'),
      );
      expect(r.state, UpdateCheckState.available,
          reason: 'иначе фильтрация GitHub оставляла бы человека без обновлений');
      expect(r.release!.version, '99.9.9');
      expect(r.release!.downloadUrl, 'https://x/y.exe');
    });

    test('пока GitHub отвечает, сайт не спрашивается вовсе', () async {
      final seen = <String>[];
      await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: (uri) async {
          seen.add(uri.host);
          return UpdateHttpResponse(
              200, jsonEncode({'tag_name': 'v1.0.0', 'assets': []}));
        },
      );
      expect(seen.where((h) => h.contains('silentgate')), isEmpty,
          reason: 'запасной источник знает про подписки — лишний раз ходить '
              'к нему незачем');
    });

    test('⚠️ оба молчат — причина ПЕРВОГО, она конкретнее', () async {
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: pair(githubCode: 403, panelBody: null),
      );
      expect(r.state, UpdateCheckState.failed);
      expect(r.failure, isNotNull);
    });

    test('⚠️ ссылка не по https в кнопку не попадает', () {
      // Иначе кнопка «Скачать» повела бы за установщиком по открытому каналу,
      // где его можно подменить.
      final r = AppUpdate.parsePanelRelease(
          '{"version":"2.0.0","url":"http://x/y.exe"}');
      expect(r!.downloadUrl, isNull);
      expect(r.version, '2.0.0', reason: 'версию всё равно узнали');
    });

    test('без url версия всё равно известна, кнопка ведёт на страницу', () {
      final r = AppUpdate.parsePanelRelease('{"version":"2.0.0"}');
      expect(r!.downloadUrl, isNull);
      expect(r.pageUrl, isNotEmpty);
    });

    test('мусор вместо ответа — не «обновлений нет»', () {
      expect(AppUpdate.parsePanelRelease('<html>502</html>'), isNull);
    });
  });

  group('Бета-канал: check(beta:) смотрит на СПИСОК релизов, а не /latest', () {
    // ⚠️ РАДИ ЧЕГО ЭТОТ БЛОК. `/releases/latest` пре-релизы не отдаёт по
    // определению GitHub — значит единственный способ узнать про бету, не
    // помещая признак канала в основной манифест (см. предупреждение сайт-
    // агента про 1.12.0), это спросить список `/releases` и взять первый
    // элемент: GitHub уже отдаёт его от новых к старым по дате публикации.

    test('galochka выключена (умолчание) — запрос идёт на /latest', () async {
      final seen = <String>[];
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: (uri) async {
          seen.add(uri.path);
          return UpdateHttpResponse(
              200, jsonEncode({'tag_name': 'v1.0.0', 'assets': []}));
        },
      );
      expect(seen.single, endsWith('/latest'));
      expect(r.release!.isBeta, isFalse);
    });

    test('⚠️ ГЛАВНОЕ: включена — запрос идёт НА СПИСОК, а не на /latest',
        () async {
      final body = jsonEncode([
        {'tag_name': 'v99.0.0-beta.1', 'prerelease': true, 'assets': []},
        {'tag_name': 'v98.0.0', 'prerelease': false, 'assets': []},
      ]);
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        beta: true,
        fetcher: (uri) async {
          expect(uri.path, isNot(endsWith('/latest')),
              reason: '/latest НИКОГДА не отдаёт пре-релизы — бета обязана '
                  'спрашивать список');
          return UpdateHttpResponse(200, body);
        },
      );
      expect(r.state, UpdateCheckState.available);
      expect(r.release!.version, '99.0.0-beta.1');
      expect(r.release!.isBeta, isTrue,
          reason: 'первый элемент списка — пре-релиз, и это обязано быть видно');
    });

    test('черновики (draft) выбрасываются из выбора беты', () async {
      final body = jsonEncode([
        {'tag_name': 'v100.0.0', 'draft': true, 'assets': []},
        {'tag_name': 'v99.0.0', 'prerelease': true, 'assets': []},
      ]);
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        beta: true,
        fetcher: (_) async => UpdateHttpResponse(200, body),
      );
      expect(r.release!.version, '99.0.0',
          reason: 'черновик не опубликован — предлагать его как версию нечестно');
    });

    test('galochka выключена — пре-релиз из основного /latest не пришёл бы '
        'вовсе, но проверяем и явный prerelease:true в ответе', () async {
      // Если бы GitHub всё же вернул на /latest объект с prerelease:true
      // (не должен, но код не обязан на это полагаться), плашка «бета» всё
      // равно обязана появиться — isBeta читается из самого ответа, а не из
      // адреса запроса.
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: (_) async => UpdateHttpResponse(
            200, jsonEncode({'tag_name': 'v99.0.0', 'prerelease': true})),
      );
      expect(r.release!.isBeta, isTrue);
    });

    test('запасной источник беты — ОТДЕЛЬНЫЙ адрес, не app-version', () async {
      final seenPaths = <String>[];
      final r = await AppUpdate.check(
        assetHint: 'Setup.exe',
        beta: true,
        fetcher: (uri) async {
          seenPaths.add(uri.path);
          if (uri.host.contains('github')) return const UpdateHttpResponse(403, '');
          return UpdateHttpResponse(
              200, jsonEncode({'version': '77.0.0', 'beta': true}));
        },
      );
      expect(seenPaths.last, contains('app-version-beta'));
      expect(r.release!.isBeta, isTrue);
    });
  });

  group('parseGithubReleaseList', () {
    test('черновики не попадают в список вовсе', () {
      final body = jsonEncode([
        {'tag_name': 'v2.0.0', 'assets': []},
        {'tag_name': 'v3.0.0', 'draft': true, 'assets': []},
      ]);
      final list =
          AppUpdate.parseGithubReleaseList(body, assetHint: 'Setup.exe');
      expect(list, isNotNull);
      expect(list!.map((r) => r.version), ['2.0.0']);
    });

    test('порядок как у GitHub — новые впереди, не пересортировывается', () {
      final body = jsonEncode([
        {'tag_name': 'v3.0.0', 'assets': []},
        {'tag_name': 'v1.0.0', 'assets': []},
        {'tag_name': 'v2.0.0', 'assets': []},
      ]);
      final list =
          AppUpdate.parseGithubReleaseList(body, assetHint: 'Setup.exe')!;
      expect(list.map((r) => r.version), ['3.0.0', '1.0.0', '2.0.0']);
    });

    test('не массив — не список', () {
      expect(
          AppUpdate.parseGithubReleaseList(jsonEncode({'a': 1}),
              assetHint: 'Setup.exe'),
          isNull);
    });
  });

  group('parsePanelRelease: признак канала', () {
    test('поле beta:true → isBeta', () {
      final r = AppUpdate.parsePanelRelease('{"version":"2.0.0","beta":true}');
      expect(r!.isBeta, isTrue);
    });

    test('поле channel:"beta" → isBeta', () {
      final r = AppUpdate.parsePanelRelease(
          '{"version":"2.0.0","channel":"beta"}');
      expect(r!.isBeta, isTrue);
    });

    test('⚠️ ни того, ни другого поля — isBeta=false (старый ответ панели)', () {
      // Обратная совместимость: панель, которая ещё не знает про канал,
      // отвечает как раньше, и приложение не должно домысливать бету.
      final r = AppUpdate.parsePanelRelease('{"version":"2.0.0"}');
      expect(r!.isBeta, isFalse);
    });
  });

  group('fetchReleaseHistory: список для кнопки отката', () {
    test('лимит применяется, порядок — как у GitHub', () async {
      final body = jsonEncode([
        {'tag_name': 'v3.0.0', 'assets': []},
        {'tag_name': 'v2.0.0', 'assets': []},
        {'tag_name': 'v1.0.0', 'assets': []},
      ]);
      final list = await AppUpdate.fetchReleaseHistory(
        assetHint: 'Setup.exe',
        limit: 2,
        fetcher: (_) async => UpdateHttpResponse(200, body),
      );
      expect(list.map((r) => r.version), ['3.0.0', '2.0.0']);
    });

    test('дата публикации разбирается для отображения', () async {
      final body = jsonEncode([
        {
          'tag_name': 'v1.0.0',
          'assets': [],
          'published_at': '2026-01-02T03:04:05Z',
        },
      ]);
      final list = await AppUpdate.fetchReleaseHistory(
        assetHint: 'Setup.exe',
        fetcher: (_) async => UpdateHttpResponse(200, body),
      );
      expect(list.single.publishedAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('⚠️ сеть недоступна — пустой список, а не исключение наружу', () async {
      // Диалог «Прежние версии» не обязан падать целиком из-за сети — он
      // покажет l.appUpdatePreviousVersionsEmpty и объяснит, что список пуст.
      final list = await AppUpdate.fetchReleaseHistory(
        assetHint: 'Setup.exe',
        fetcher: (_) async => throw const SocketExceptionStub(),
      );
      expect(list, isEmpty);
    });

    test('сервер ответил ошибкой — тоже пустой список, не исключение', () async {
      final list = await AppUpdate.fetchReleaseHistory(
        assetHint: 'Setup.exe',
        fetcher: (_) async => const UpdateHttpResponse(500, ''),
      );
      expect(list, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // САМООБНОВЛЕНИЕ: метаданные релиза.
  //
  // ⚠️ Приложение качает и ставит сборку само только тогда, когда у релиза есть
  // ВСЁ: прямая ссылка на актив, его точное имя и размер, манифест и подпись.
  // Не хватает чего-то одного — прежнее поведение «открыть страницу». Ошибка в
  // этой развилке опасна в обе стороны: лишнее `true` — попытка установки по
  // неполным данным, лишнее `false` — самообновление молча не работает никогда.
  String fullRelease({
    String tag = 'v1.14.0',
    required List<Map<String, Object>> assets,
    bool prerelease = false,
  }) =>
      jsonEncode({
        'tag_name': tag,
        'html_url': 'https://github.com/o/r/releases/tag/$tag',
        'body': 'Что нового',
        'prerelease': prerelease,
        'assets': [
          for (final a in assets)
            {
              'name': a['name'],
              'browser_download_url': a['url'],
              if (a.containsKey('size')) 'size': a['size'],
            },
        ],
      });

  Map<String, Object> asset(String name, {int size = 1000, String? url}) =>
      {'name': name, 'url': url ?? 'https://x/$name', 'size': size};

  group('Самообновление: актив, манифест и подпись релиза GitHub', () {
    tearDown(debugResetUpdateApiOverride);

    test('всё на месте — canSelfUpdate, размер и имя актива попадают', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGateSetup-1.14.0.exe', size: 34932418),
            asset('SilentGate-1.14.0-arm64-v8a.apk', size: 81230968),
            asset('SilentGate-1.14.0.manifest.json', size: 500),
            asset('SilentGate-1.14.0.manifest.sig', size: 89),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.downloadUrl, 'https://x/SilentGateSetup-1.14.0.exe');
      expect(r.assetName, 'SilentGateSetup-1.14.0.exe');
      expect(r.assetSize, 34932418);
      expect(r.manifestUrl, 'https://x/SilentGate-1.14.0.manifest.json');
      expect(r.signatureUrl, 'https://x/SilentGate-1.14.0.manifest.sig');
      expect(r.canSelfUpdate, isTrue);
    });

    test('⚠️ настоящее имя установщика «SilentGateSetup-<версия>.exe» находится',
        () {
      // Inno пишет `SilentGateSetup-1.13.1.exe` (OutputBaseFilename), и
      // `contains('Setup.exe')` его НЕ находил: версия стоит между «Setup» и
      // «.exe». Кнопка на Windows всегда вела на страницу, а не на файл.
      final r = AppUpdate.parseGithubRelease(
          fullRelease(tag: 'v1.13.1', assets: [
            asset('SilentGate-Portable-1.13.1.zip'),
            asset('SilentGateSetup-1.13.1.exe'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.assetName, 'SilentGateSetup-1.13.1.exe',
          reason: 'портативный zip — не установщик');
    });

    test('⚠️ бета находит установщик, названный по версии exe без суффикса',
        () {
      // Inno называет файл по версии exe (`1.14.1`), а тег беты —
      // `v1.14.1-beta.1`: вырезался только полный суффикс, и Windows-бета
      // откатывалась на «открыть страницу».
      final r = AppUpdate.parseGithubRelease(
          fullRelease(tag: 'v1.14.1-beta.1', assets: [
            asset('SilentGateSetup-1.14.1.exe'),
            asset('SilentGate-1.14.1-beta.1.manifest.json'),
            asset('SilentGate-1.14.1-beta.1.manifest.sig'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.assetName, 'SilentGateSetup-1.14.1.exe');
      expect(r.canSelfUpdate, isTrue);
    });

    test('⚠️ похожее имя манифеста («.manifest.json.bak») не берётся', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGateSetup-1.14.0.exe'),
            asset('SilentGate-1.14.0.manifest.json.bak'),
            asset('old-SilentGate-1.14.0.manifest.json'),
            asset('SilentGate-1.14.0.manifest.sig.txt'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.manifestUrl, isNull,
          reason: 'только ТОЧНОЕ имя: иначе проверялась бы подпись не того файла');
      expect(r.signatureUrl, isNull);
      expect(r.canSelfUpdate, isFalse);
      expect(r.downloadUrl, isNotNull, reason: 'ссылка на файл остаётся');
    });

    test('точное имя находится, даже если похожее стоит в списке раньше', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGate-1.14.0.manifest.json.bak', url: 'https://x/bak'),
            asset('SilentGateSetup-1.14.0.exe'),
            asset('SilentGate-1.14.0.manifest.json', url: 'https://x/real'),
            asset('SilentGate-1.14.0.manifest.sig'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.manifestUrl, 'https://x/real');
      expect(r.canSelfUpdate, isTrue);
    });

    test('нет манифеста — canSelfUpdate=false, старое поведение «ссылка»', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGateSetup-1.14.0.exe'),
            asset('SilentGate-1.14.0.manifest.sig'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.manifestUrl, isNull);
      expect(r.canSelfUpdate, isFalse);
      expect(r.downloadUrl, 'https://x/SilentGateSetup-1.14.0.exe');
    });

    test('нет подписи — canSelfUpdate=false', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGateSetup-1.14.0.exe'),
            asset('SilentGate-1.14.0.manifest.json'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.signatureUrl, isNull);
      expect(r.canSelfUpdate, isFalse);
    });

    test('манифест другой версии не подходит', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGateSetup-1.14.0.exe'),
            asset('SilentGate-1.13.2.manifest.json'),
            asset('SilentGate-1.13.2.manifest.sig'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.canSelfUpdate, isFalse);
    });

    test('размера нет или он нулевой — canSelfUpdate=false', () {
      for (final size in [0, -1]) {
        final r = AppUpdate.parseGithubRelease(
            fullRelease(assets: [
              asset('SilentGateSetup-1.14.0.exe', size: size),
              asset('SilentGate-1.14.0.manifest.json'),
              asset('SilentGate-1.14.0.manifest.sig'),
            ]),
            assetHint: 'Setup.exe')!;
        expect(r.canSelfUpdate, isFalse, reason: 'size=$size');
      }
      final noSize = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            {'name': 'SilentGateSetup-1.14.0.exe', 'url': 'https://x/s.exe'},
            asset('SilentGate-1.14.0.manifest.json'),
            asset('SilentGate-1.14.0.manifest.sig'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(noSize.assetSize, isNull);
      expect(noSize.canSelfUpdate, isFalse);
    });

    test('бета-тег v1.14.1-beta.1 — имена с ПОЛНОЙ версией', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(tag: 'v1.14.1-beta.1', prerelease: true, assets: [
            asset('SilentGateSetup-1.14.1-beta.1.exe'),
            asset('SilentGate-1.14.1.manifest.json', url: 'https://x/short'),
            asset('SilentGate-1.14.1.manifest.sig', url: 'https://x/short-sig'),
            asset('SilentGate-1.14.1-beta.1.manifest.json'),
            asset('SilentGate-1.14.1-beta.1.manifest.sig'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.isBeta, isTrue);
      expect(r.assetName, 'SilentGateSetup-1.14.1-beta.1.exe');
      expect(r.manifestUrl, 'https://x/SilentGate-1.14.1-beta.1.manifest.json');
      expect(r.signatureUrl, 'https://x/SilentGate-1.14.1-beta.1.manifest.sig');
      expect(r.canSelfUpdate, isTrue);
    });

    test('Android: подпись схемы APK (.apk.idsig) не принимается за APK', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGate-1.14.0-arm64-v8a.apk.idsig'),
            asset('TEST-ONLY-emulator-SilentGate-1.14.0-x86_64.apk'),
            asset('SilentGate-1.14.0-arm64-v8a.apk', size: 81230968),
          ]),
          assetHint: platformAssetHint(android: true, androidAbi: 'arm64-v8a'))!;
      expect(r.assetName, 'SilentGate-1.14.0-arm64-v8a.apk');
      expect(r.assetSize, 81230968);
    });

    test('эмулятор x86_64 получает TEST-ONLY-сборку, а не телефонную', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGate-1.14.0-arm64-v8a.apk'),
            asset('TEST-ONLY-emulator-SilentGate-1.14.0-x86_64.apk'),
          ]),
          assetHint: platformAssetHint(android: true, androidAbi: 'x86_64'))!;
      expect(r.assetName, 'TEST-ONLY-emulator-SilentGate-1.14.0-x86_64.apk');
    });

    test('⚠️ http:// без override — canSelfUpdate=false', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGateSetup-1.14.0.exe',
                url: 'http://x/SilentGateSetup-1.14.0.exe'),
            asset('SilentGate-1.14.0.manifest.json'),
            asset('SilentGate-1.14.0.manifest.sig'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.canSelfUpdate, isFalse,
          reason: 'открытый канал в боевом режиме не принимается ни для чего');
    });

    test('http:// манифест без override — тоже отказ', () {
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGateSetup-1.14.0.exe'),
            asset('SilentGate-1.14.0.manifest.json',
                url: 'http://x/SilentGate-1.14.0.manifest.json'),
            asset('SilentGate-1.14.0.manifest.sig'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.canSelfUpdate, isFalse);
    });

    test('с override http:// допустим — целостность держит подпись', () {
      debugSetUpdateApiOverride('http://127.0.0.1:8080');
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGateSetup-1.14.0.exe',
                url: 'http://127.0.0.1:8080/d/SilentGateSetup-1.14.0.exe'),
            asset('SilentGate-1.14.0.manifest.json',
                url: 'http://127.0.0.1:8080/d/SilentGate-1.14.0.manifest.json'),
            asset('SilentGate-1.14.0.manifest.sig',
                url: 'http://127.0.0.1:8080/d/SilentGate-1.14.0.manifest.sig'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.canSelfUpdate, isTrue);
    });

    test('схема не http(s) не принимается даже с override', () {
      debugSetUpdateApiOverride('http://127.0.0.1:8080');
      final r = AppUpdate.parseGithubRelease(
          fullRelease(assets: [
            asset('SilentGateSetup-1.14.0.exe',
                url: 'file:///C:/SilentGateSetup-1.14.0.exe'),
            asset('SilentGate-1.14.0.manifest.json'),
            asset('SilentGate-1.14.0.manifest.sig'),
          ]),
          assetHint: 'Setup.exe')!;
      expect(r.canSelfUpdate, isFalse);
    });

    test('старый вызов конструктора без новых полей — canSelfUpdate=false', () {
      const r = AppRelease(version: '9.9.9', downloadUrl: 'https://x/y.exe');
      expect(r.assetName, isNull);
      expect(r.assetSize, isNull);
      expect(r.manifestUrl, isNull);
      expect(r.signatureUrl, isNull);
      expect(r.canSelfUpdate, isFalse);
    });

    test('список релизов разбирает те же поля у каждого элемента', () {
      final body = jsonEncode([
        jsonDecode(fullRelease(tag: 'v1.14.1-beta.1', prerelease: true, assets: [
          asset('SilentGateSetup-1.14.1-beta.1.exe'),
          asset('SilentGate-1.14.1-beta.1.manifest.json'),
          asset('SilentGate-1.14.1-beta.1.manifest.sig'),
        ])),
        jsonDecode(fullRelease(tag: 'v1.14.0', assets: [
          asset('SilentGateSetup-1.14.0.exe'),
        ])),
      ]);
      final list =
          AppUpdate.parseGithubReleaseList(body, assetHint: 'Setup.exe')!;
      expect(list[0].canSelfUpdate, isTrue);
      expect(list[1].canSelfUpdate, isFalse);
      expect(list[1].downloadUrl, isNotNull);
    });
  });

  group('Самообновление: поля ответа панели', () {
    tearDown(debugResetUpdateApiOverride);

    test('manifest/sig/size/asset — canSelfUpdate', () {
      final r = AppUpdate.parsePanelRelease(jsonEncode({
        'version': '1.14.0',
        'url': 'https://silentgate.lol/download/SilentGateSetup-1.14.0.exe',
        'asset': 'SilentGateSetup-1.14.0.exe',
        'size': 34932418,
        'manifest':
            'https://silentgate.lol/download/SilentGate-1.14.0.manifest.json',
        'sig': 'https://silentgate.lol/download/SilentGate-1.14.0.manifest.sig',
      }))!;
      expect(r.assetName, 'SilentGateSetup-1.14.0.exe');
      expect(r.assetSize, 34932418);
      expect(r.manifestUrl,
          'https://silentgate.lol/download/SilentGate-1.14.0.manifest.json');
      expect(r.signatureUrl,
          'https://silentgate.lol/download/SilentGate-1.14.0.manifest.sig');
      expect(r.canSelfUpdate, isTrue);
    });

    test('размер строкой тоже понимается', () {
      final r = AppUpdate.parsePanelRelease(jsonEncode({
        'version': '1.14.0',
        'url': 'https://x/SilentGateSetup-1.14.0.exe',
        'asset': 'SilentGateSetup-1.14.0.exe',
        'size': '1234',
        'manifest': 'https://x/m.json',
        'sig': 'https://x/m.sig',
      }))!;
      expect(r.assetSize, 1234);
      expect(r.canSelfUpdate, isTrue);
    });

    test('старый ответ панели (новых полей нет) — canSelfUpdate=false', () {
      final r = AppUpdate.parsePanelRelease(
          '{"version":"1.14.0","url":"https://x/SilentGateSetup-1.14.0.exe"}')!;
      expect(r.downloadUrl, isNotNull);
      expect(r.manifestUrl, isNull);
      expect(r.signatureUrl, isNull);
      expect(r.assetName, isNull);
      expect(r.assetSize, isNull);
      expect(r.canSelfUpdate, isFalse);
    });

    test('⚠️ http:// в манифесте панели без override — отказ', () {
      final r = AppUpdate.parsePanelRelease(jsonEncode({
        'version': '1.14.0',
        'url': 'https://x/SilentGateSetup-1.14.0.exe',
        'asset': 'SilentGateSetup-1.14.0.exe',
        'size': 10,
        'manifest': 'http://x/m.json',
        'sig': 'https://x/m.sig',
      }))!;
      expect(r.canSelfUpdate, isFalse);
    });

    test('с override http:// у панели допустим', () {
      debugSetUpdateApiOverride('http://10.0.2.2:8080');
      final r = AppUpdate.parsePanelRelease(jsonEncode({
        'version': '1.14.0',
        'url': 'http://10.0.2.2:8080/SilentGateSetup-1.14.0.exe',
        'asset': 'SilentGateSetup-1.14.0.exe',
        'size': 10,
        'manifest': 'http://10.0.2.2:8080/m.json',
        'sig': 'http://10.0.2.2:8080/m.sig',
      }))!;
      expect(r.downloadUrl, isNotNull);
      expect(r.canSelfUpdate, isTrue);
    });
  });

  group('Тестовый override адреса API обновлений', () {
    tearDown(debugResetUpdateApiOverride);

    test('без override — GitHub', () {
      debugSetUpdateApiOverride(null);
      expect(kUpdateApiOverridden, isFalse);
      expect(kGithubReleasesApi,
          'https://api.github.com/repos/Solat228/silentgate/releases/latest');
      expect(kGithubReleasesListApi,
          'https://api.github.com/repos/Solat228/silentgate/releases');
    });

    test('override меняет базу обоих адресов API', () {
      debugSetUpdateApiOverride('http://127.0.0.1:8080/');
      expect(kUpdateApiOverridden, isTrue);
      expect(kUpdateApiOverride, 'http://127.0.0.1:8080',
          reason: 'хвостовой слэш срезается, иначе «//repos»');
      expect(kGithubReleasesApi,
          'http://127.0.0.1:8080/repos/Solat228/silentgate/releases/latest');
      expect(kGithubReleasesListApi,
          'http://127.0.0.1:8080/repos/Solat228/silentgate/releases');
      expect(AppUpdate.endpoint, kGithubReleasesApi);
    });

    test('check() под override спрашивает стенд', () async {
      debugSetUpdateApiOverride('http://127.0.0.1:8080');
      final seen = <Uri>[];
      await AppUpdate.check(
        assetHint: 'Setup.exe',
        fetcher: (uri) async {
          seen.add(uri);
          return UpdateHttpResponse(
              200, jsonEncode({'tag_name': 'v1.0.0', 'assets': []}));
        },
      );
      expect(seen.single.toString(),
          'http://127.0.0.1:8080/repos/Solat228/silentgate/releases/latest');
    });

    test('мусор вместо адреса — override не включается', () {
      for (final bad in ['', '   ', 'ftp://x', 'не адрес', 'http://', '127.0.0.1']) {
        debugSetUpdateApiOverride(bad);
        expect(kUpdateApiOverridden, isFalse, reason: '«$bad»');
        expect(kGithubReleasesApi, startsWith('https://api.github.com/'));
      }
    });

    test('Android: файл update_api.txt в каталоге данных', () async {
      final dir = await Directory.systemTemp.createTemp('sg_update_api_');
      addTearDown(() => dir.delete(recursive: true));

      expect(loadUpdateApiOverrideFrom(dir.path), isNull,
          reason: 'файла нет — нет override');
      expect(kUpdateApiOverridden, isFalse);

      File('${dir.path}${Platform.pathSeparator}update_api.txt')
          .writeAsStringSync('  http://10.0.2.2:8080/  \r\n');
      expect(loadUpdateApiOverrideFrom(dir.path), 'http://10.0.2.2:8080');
      expect(kGithubReleasesApi,
          'http://10.0.2.2:8080/repos/Solat228/silentgate/releases/latest');
    });

    test('⚠️ override не касается публичного ключа', () async {
      // Стенд подменяет только АДРЕС. Ключ, которым проверяется подпись, —
      // константа в своём файле, и ни одна ветка override до неё не дотянется.
      final src =
          await File('lib/core/update/app_update_defaults.dart').readAsString();
      final imports = RegExp(r'^\s*import\s+.*$', multiLine: true)
          .allMatches(src)
          .map((m) => m.group(0)!)
          .toList();
      expect(imports.where((i) => !i.contains("'dart:")), isEmpty,
          reason: 'файл адресов не импортирует ничего, кроме dart:*');
      expect(RegExp(r'kUpdatePublicKey').hasMatch(src), isFalse);
    });

    test('проверка обновлений идёт мимо прокси (findProxy DIRECT)', () async {
      // Иначе запрос уходил бы через системный прокси нашего же туннеля.
      final src = await File('lib/core/update/app_update.dart').readAsString();
      expect(src, contains("findProxy = (_) => 'DIRECT'"));
    });
  });

  group('platformAssetHint по ABI', () {
    test('Windows — установщик', () {
      expect(platformAssetHint(android: false), 'Setup.exe');
      expect(platformAssetHint(android: false, androidAbi: 'x86_64'), 'Setup.exe');
    });

    test('arm64-v8a и x86_64 — своя сборка', () {
      expect(platformAssetHint(android: true, androidAbi: 'arm64-v8a'),
          '-arm64-v8a.apk');
      expect(platformAssetHint(android: true, androidAbi: 'x86_64'),
          '-x86_64.apk');
      expect(platformAssetHint(android: true, androidAbi: ' ARM64-v8a '),
          '-arm64-v8a.apk');
    });

    test('ABI неизвестна (канал не ответил) — телефонная сборка', () {
      expect(platformAssetHint(android: true), 'arm64-v8a.apk');
      expect(platformAssetHint(android: true, androidAbi: ''), 'arm64-v8a.apk');
    });

    test('⚠️ ABI, под которую сборки нет, не получает «похожую»', () {
      // armeabi-v7a установит arm64-APK и не запустит; x86 — то же с x86_64.
      for (final abi in ['armeabi-v7a', 'x86', 'arm64']) {
        final hint = platformAssetHint(android: true, androidAbi: abi);
        final r = AppUpdate.parseGithubRelease(
            fullRelease(assets: [
              asset('SilentGate-1.14.0-arm64-v8a.apk'),
              asset('TEST-ONLY-emulator-SilentGate-1.14.0-x86_64.apk'),
            ]),
            assetHint: hint)!;
        expect(r.downloadUrl, isNull, reason: 'ABI $abi → «$hint»');
      }
    });

    test('таблица ABI одна: та же, что у установщика APK', () {
      for (final abi in ['arm64-v8a', 'x86_64', 'armeabi-v7a', 'x86', null, '']) {
        expect(androidAssetHintForAbi(abi),
            ApkInstallerAndroid.assetHintForAbi(abi),
            reason: 'ABI $abi');
      }
    });

    test('kPlatformAssetHint — обёртка без ABI', () {
      expect(kPlatformAssetHint, platformAssetHint());
    });
  });
}

/// Чтобы не тянуть в тест `dart:io` ради одного исключения.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'нет сети';
}
