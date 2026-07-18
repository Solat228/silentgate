import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/url_scheme_windows.dart';

void main() {
  group('URL-схемы: управление', () {
    test('connect/disconnect/toggle/update распознаются', () {
      expect(UrlSchemeWindows.controlAction('silentgate://connect'), 'connect');
      expect(UrlSchemeWindows.controlAction('silentgate://disconnect'),
          'disconnect');
      expect(UrlSchemeWindows.controlAction('silentgate://toggle'), 'toggle');
      expect(UrlSchemeWindows.controlAction('silentgate://update'), 'update');
    });

    test('регистр и слэши не мешают', () {
      expect(UrlSchemeWindows.controlAction('SilentGate://Toggle'), 'toggle');
      expect(UrlSchemeWindows.controlAction('silentgate://connect/'), 'connect');
    });

    test('импорт и неизвестное — не управление', () {
      expect(UrlSchemeWindows.controlAction('silentgate://import?url=x'), isNull);
      expect(UrlSchemeWindows.controlAction('vless://id@a.com:443'), isNull);
      expect(UrlSchemeWindows.controlAction('silentgate://reset'), isNull);
    });
  });

  group('URL-схемы: импорт', () {
    test('разворачивает ?url= и ?config=', () {
      expect(
          UrlSchemeWindows.importPayload(
              'silentgate://import?url=https://sub.example/x'),
          'https://sub.example/x');
      expect(
          UrlSchemeWindows.importPayload(
              'silentgate://import?config=vless%3A%2F%2Fid%40a.com%3A443'),
          'vless://id@a.com:443');
    });

    test('config имеет приоритет над url, чужие ссылки — null', () {
      expect(
          UrlSchemeWindows.importPayload('silentgate://import?config=A&url=B'),
          'A');
      expect(UrlSchemeWindows.importPayload('vless://id@a.com:443'), isNull);
    });

    test('import-sub не поддерживается; работают import?url и управление', () {
      // Список схем теперь отображается локализованно в UI (_schemeGroups),
      // а их РАЗБОР — здесь: проверяем, что реально работает.
      expect(UrlSchemeWindows.controlAction('silentgate://toggle'), 'toggle');
      expect(UrlSchemeWindows.controlAction('silentgate://update'), 'update');
      expect(
          UrlSchemeWindows.importPayload('silentgate://import?url=https://x/sub'),
          'https://x/sub');
      // import-sub — устаревшая схема, не распознаётся ни как управление, ни импорт.
      expect(UrlSchemeWindows.controlAction('silentgate://import-sub'), isNull);
      expect(UrlSchemeWindows.importPayload('silentgate://import-sub'), isNull);
    });
  });
}
