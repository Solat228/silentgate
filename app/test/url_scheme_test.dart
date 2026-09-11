import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/url_scheme.dart';

void main() {
  group('URL-схемы: управление', () {
    test('connect/disconnect/toggle/update распознаются', () {
      expect(AppUrlScheme.controlAction('silentgate://connect'), 'connect');
      expect(AppUrlScheme.controlAction('silentgate://disconnect'),
          'disconnect');
      expect(AppUrlScheme.controlAction('silentgate://toggle'), 'toggle');
      expect(AppUrlScheme.controlAction('silentgate://update'), 'update');
    });

    test('регистр и слэши не мешают', () {
      expect(AppUrlScheme.controlAction('SilentGate://Toggle'), 'toggle');
      expect(AppUrlScheme.controlAction('silentgate://connect/'), 'connect');
    });

    test('импорт и неизвестное — не управление', () {
      expect(AppUrlScheme.controlAction('silentgate://import?url=x'), isNull);
      expect(AppUrlScheme.controlAction('vless://id@a.com:443'), isNull);
      expect(AppUrlScheme.controlAction('silentgate://reset'), isNull);
    });
  });

  group('URL-схемы: импорт', () {
    test('разворачивает ?url= и ?config=', () {
      expect(
          AppUrlScheme.importPayload(
              'silentgate://import?url=https://sub.example/x'),
          'https://sub.example/x');
      expect(
          AppUrlScheme.importPayload(
              'silentgate://import?config=vless%3A%2F%2Fid%40a.com%3A443'),
          'vless://id@a.com:443');
    });

    test('config имеет приоритет над url, чужие ссылки — null', () {
      expect(
          AppUrlScheme.importPayload('silentgate://import?config=A&url=B'),
          'A');
      expect(AppUrlScheme.importPayload('vless://id@a.com:443'), isNull);
    });

    test('import-sub не поддерживается; работают import?url и управление', () {
      // Список схем теперь отображается локализованно в UI (_schemeGroups),
      // а их РАЗБОР — здесь: проверяем, что реально работает.
      expect(AppUrlScheme.controlAction('silentgate://toggle'), 'toggle');
      expect(AppUrlScheme.controlAction('silentgate://update'), 'update');
      expect(
          AppUrlScheme.importPayload('silentgate://import?url=https://x/sub'),
          'https://x/sub');
      // import-sub — устаревшая схема, не распознаётся ни как управление, ни импорт.
      expect(AppUrlScheme.controlAction('silentgate://import-sub'), isNull);
      expect(AppUrlScheme.importPayload('silentgate://import-sub'), isNull);
    });
  });

  group('URL-схемы: своя отраслевая форма add/ и import/', () {
    // BACKLOG «Своя схема в отраслевой форме»: у всех клиентов
    // `<клиент>://add/<url>` или `://import/<url>`, у нас исторически был
    // только `import?url=`. Обе новые формы обязаны давать ТОТ ЖЕ payload,
    // что и историческая — иначе панель, собирающая кнопку по отраслевому
    // шаблону, привела бы к разным результатам в зависимости от формы ссылки.
    const sub = 'https://sub.example/x';
    final reference =
        AppUrlScheme.importPayload('silentgate://import?url=$sub');

    test('add/<url> голый — тот же payload, что ?url=', () {
      expect(AppUrlScheme.importPayload('silentgate://add/$sub'), reference);
    });

    test('add/<url> url-кодированный — тот же payload', () {
      expect(
          AppUrlScheme.importPayload(
              'silentgate://add/${Uri.encodeComponent(sub)}'),
          reference);
    });

    test('import/<url> голый — тот же payload, что ?url=', () {
      expect(
          AppUrlScheme.importPayload('silentgate://import/$sub'), reference);
    });

    test('import/<url> url-кодированный — тот же payload', () {
      expect(
          AppUrlScheme.importPayload(
              'silentgate://import/${Uri.encodeComponent(sub)}'),
          reference);
    });

    test('регистр схемы/маркера не мешает', () {
      expect(AppUrlScheme.importPayload('SilentGate://Add/$sub'), reference);
      expect(
          AppUrlScheme.importPayload('SilentGate://Import/$sub'), reference);
    });

    test('существующие формы не сломаны', () {
      expect(
          AppUrlScheme.importPayload('silentgate://import?url=$sub'), sub);
      expect(
          AppUrlScheme.importPayload(
              'silentgate://import?config=vless%3A%2F%2Fid%40a.com%3A443'),
          'vless://id@a.com:443');
      expect(AppUrlScheme.importPayload('happ://add/$sub'), sub);
      expect(AppUrlScheme.controlAction('silentgate://connect'), 'connect');
      expect(AppUrlScheme.controlAction('silentgate://toggle/'), 'toggle');
    });

    // ⚠️ ЛОВУШКА (память one-parser-for-permission-and-execution): новая
    // форма — это ИМПОРТ, а не управляющая команда. Вложенная ссылка
    // `silentgate://connect` внутри `add/` не должна разрешиться как
    // команда connect — ни на уровне controlAction (разрешение), ни как
    // побочный эффект в вызывающем коде (там payload идёт в importSource,
    // а не повторно в controlAction/handleIncomingUrl).
    test('add/silentgate://connect — импорт мусора, а НЕ команда connect', () {
      const trap = 'silentgate://add/silentgate://connect';
      // Верхний уровень (то, что реально проверяют перед выполнением команды)
      // не должен посчитать это управляющим действием.
      expect(AppUrlScheme.controlAction(trap), isNull);
      // Импорт достаёт вложенную строку как значение для импорта (сервер/
      // подписка), а не как новую команду — дальше она уйдёт в importSource
      // и будет отвергнута как невалидная ссылка, а не выполнена.
      expect(AppUrlScheme.importPayload(trap), 'silentgate://connect');
    });

    test('та же ловушка через import/ — тоже не команда', () {
      const trap = 'silentgate://import/silentgate://toggle';
      expect(AppUrlScheme.controlAction(trap), isNull);
      expect(AppUrlScheme.importPayload(trap), 'silentgate://toggle');
    });
  });
}
