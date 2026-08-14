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
}

/// Чтобы не тянуть в тест `dart:io` ради одного исключения.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'нет сети';
}
