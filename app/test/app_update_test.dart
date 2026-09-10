import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/app_info.dart';
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
}

/// Чтобы не тянуть в тест `dart:io` ради одного исключения.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'нет сети';
}
