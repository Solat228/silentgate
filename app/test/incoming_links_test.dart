import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/incoming_links.dart';

/// ССЫЛКА ХОЛОДНОГО СТАРТА НЕ ДОЛЖНА ТЕРЯТЬСЯ.
///
/// ⚠️ Владелец 13.10.2026: «импорт со страницы подписки открывает приложение, но
/// подписка не добавляется». Шина была broadcast-потоком, а у broadcast нет
/// памяти: событие без слушателя пропадает. Слушатель — `AppState`, а его
/// создаёт ленивый провайдер при первой отрисовке; ссылку же забирает с
/// нативной стороны `bindPlatform()` ещё до `runApp`. Кто успеет первым —
/// не задано ничем.
void main() {
  setUp(IncomingLinks.resetForTest);

  test('⚠️ ссылка, пришедшая до подписки, доходит до первого слушателя',
      () async {
    IncomingLinks.add('silentgate://import?url=https%3A%2F%2Fexample.test%2Fx');

    final got = <String>[];
    final sub = IncomingLinks.stream.listen(got.add);
    await pumpEventQueue();

    expect(got, ['silentgate://import?url=https%3A%2F%2Fexample.test%2Fx']);
    await sub.cancel();
  });

  test('ссылка при живом слушателе приходит один раз', () async {
    final got = <String>[];
    final sub = IncomingLinks.stream.listen(got.add);
    IncomingLinks.add('silentgate://connect');
    await pumpEventQueue();

    expect(got, ['silentgate://connect']);
    await sub.cancel();
  });

  test('порядок сохраняется, отложенные не повторяются второму слушателю',
      () async {
    IncomingLinks.add('a://1');
    IncomingLinks.add('a://2');

    final first = <String>[];
    final s1 = IncomingLinks.stream.listen(first.add);
    await pumpEventQueue();
    final second = <String>[];
    final s2 = IncomingLinks.stream.listen(second.add);
    await pumpEventQueue();

    expect(first, ['a://1', 'a://2']);
    expect(second, isEmpty,
        reason: 'повторный импорт той же ссылки — тоже дефект');
    await s1.cancel();
    await s2.cancel();
  });

  test('пустая строка не копится', () async {
    IncomingLinks.add('   ');
    final got = <String>[];
    final sub = IncomingLinks.stream.listen(got.add);
    await pumpEventQueue();
    expect(got, isEmpty);
    await sub.cancel();
  });
}
