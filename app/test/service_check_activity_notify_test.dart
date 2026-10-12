import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentgate/core/probe/probe_harness.dart';
import 'package:silentgate/state/probe_controller.dart';
import 'package:silentgate/state/service_check_controller.dart';
import 'package:silentgate/ui/widgets/ping_gate.dart';

/// КНОПКА ПИНГА ОБЯЗАНА ОЖИВАТЬ, КОГДА ПРОВЕРКА СЕРВИСОВ КОНЧИЛАСЬ.
///
/// ⚠️ РАДИ ЧЕГО ЭТОТ ФАЙЛ. Жалоба владельца 08.10.2026: подключился к
/// умершему серверу, автопрогон проверки сервисов ждал канал, человек отключился
/// — и кнопка «Пинг серверов» осталась серой с подписью «идёт проверка
/// сервисов» до перезапуска приложения. По журналу автопрогон закончился через
/// две секунды после отключения.
///
/// Отметка занятости ([ServiceCheckActivity]) была голым статическим счётчиком:
/// исполнитель её читал, а сообщить о смене ей было некому. Гейт интерфейса
/// (`PingGate.of`) пересчитывается только при перерисовке, а панель серверов
/// перерисовывается по `ProbeController` и `AppState`. После отключения ни тот,
/// ни другой больше не шевелились — кнопка застыла в последнем нарисованном
/// виде.
void main() {
  setUp(ServiceCheckActivity.resetForTests);
  tearDown(ServiceCheckActivity.resetForTests);

  group('Отметка занятости сообщает о смене', () {
    test('начало и конец прогона — два уведомления', () {
      var calls = 0;
      void spy() => calls++;
      ServiceCheckActivity.listenable.addListener(spy);
      addTearDown(() => ServiceCheckActivity.listenable.removeListener(spy));

      ServiceCheckActivity.begin();
      expect(ServiceCheckActivity.busy, isTrue);
      expect(calls, 1);

      ServiceCheckActivity.end();
      expect(ServiceCheckActivity.busy, isFalse);
      expect(calls, 2);
    });

    test('вложенные прогоны: уведомление только на смене «занят/свободен»', () {
      var calls = 0;
      void spy() => calls++;
      ServiceCheckActivity.listenable.addListener(spy);
      addTearDown(() => ServiceCheckActivity.listenable.removeListener(spy));

      ServiceCheckActivity.begin();
      ServiceCheckActivity.begin();
      ServiceCheckActivity.end();
      expect(ServiceCheckActivity.busy, isTrue,
          reason: 'второй прогон ещё идёт');
      expect(calls, 1);
      ServiceCheckActivity.end();
      expect(calls, 2);
    });

    test('лишний end() не уводит счётчик в минус и не шумит', () {
      var calls = 0;
      void spy() => calls++;
      ServiceCheckActivity.listenable.addListener(spy);
      addTearDown(() => ServiceCheckActivity.listenable.removeListener(spy));

      ServiceCheckActivity.end();
      expect(ServiceCheckActivity.busy, isFalse);
      expect(calls, 0);
    });
  });

  group('ProbeController пересылает смену своим слушателям', () {
    test('конец проверки сервисов будит слушателей контроллера пинга', () {
      final probe = ProbeController(harnessFactory: _NoHarness.new);
      addTearDown(probe.dispose);
      var calls = 0;
      probe.addListener(() => calls++);

      ServiceCheckActivity.begin();
      expect(probe.serviceChecksRunning, isTrue);
      ServiceCheckActivity.end();
      expect(probe.serviceChecksRunning, isFalse);
      expect(calls, 2, reason: 'без этого гейт пересчитывать некому');
    });

    test('после dispose смена отметки контроллер не трогает', () {
      final probe = ProbeController(harnessFactory: _NoHarness.new);
      probe.dispose();
      // Уведомление в уничтоженный ChangeNotifier бросает исключение.
      expect(ServiceCheckActivity.begin, returnsNormally);
      expect(ServiceCheckActivity.end, returnsNormally);
    });
  });

  testWidgets('⚠️ кнопка, читающая только ProbeController, оживает сама',
      (tester) async {
    final probe = ProbeController(harnessFactory: _NoHarness.new);
    addTearDown(probe.dispose);

    await tester.pumpWidget(ChangeNotifierProvider<ProbeController>.value(
      value: probe,
      child: MaterialApp(
        home: Builder(builder: (context) {
          final gate = PingGate.of(context.watch<ProbeController>());
          return TextButton(
            onPressed: gate.allowed ? () {} : null,
            child: const Text('Пинг'),
          );
        }),
      ),
    ));
    TextButton button() => tester.widget<TextButton>(find.byType(TextButton));
    expect(button().onPressed, isNotNull);

    ServiceCheckActivity.begin();
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'идёт проверка сервисов');

    // Ровно случай владельца: проверка кончилась, больше НИЧЕГО не меняется.
    ServiceCheckActivity.end();
    await tester.pump();
    expect(button().onPressed, isNotNull,
        reason: 'проверка кончилась — кнопка обязана ожить без перезапуска');
  });
}

/// Харнесс не нужен ни одному тесту здесь: пинг не запускается.
class _NoHarness implements ProbeHarness {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('харнесс в этом тесте не используется');
}
