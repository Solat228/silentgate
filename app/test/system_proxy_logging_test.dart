import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/engine/windows/system_proxy.dart';

/// ⚠️ СПОСОБ ЗАХВАТА ПО УМОЛЧАНИЮ ОБЯЗАН ОСТАВЛЯТЬ СЛЕД В ЖУРНАЛЕ.
///
/// До этой правки `SystemProxy` не писал НИ ОДНОЙ строки: ни включения, ни
/// снятия, ни отказа `reg.exe`. Хуже того, код возврата `reg add` не смотрел
/// никто — при запрете записи в HKCU (политика домена, повреждённый профиль)
/// приложение показывало «Подключено», а трафик шёл мимо туннеля, под
/// реальным адресом. Разобрать такую жалобу по журналу было нельзя: в нём
/// вообще нечего было читать.
///
/// ⚠️ РЕЕСТР ЗДЕСЬ НЕ ТРОГАЕТСЯ. Запуск `reg.exe` подменён (`SystemProxy
/// .runner`): у владельца в момент прогона может работать VPN, и тест,
/// честно вызвавший `clear()`, оборвал бы ему соединение.
void main() {
  late List<List<String>> calls;
  late Directory tmp;

  /// Подменённый `reg.exe`: [code] — что он вернёт, [err] — что напишет.
  void arm({int code = 0, String err = '', Object? throwIt}) {
    calls = [];
    SystemProxy.runner = (exe, args) async {
      calls.add([exe, ...args]);
      if (throwIt != null) throw throwIt;
      return ProcessResult(0, code, '', err);
    };
  }

  setUp(() {
    arm();
    // ⚠️ Маркер уводим в свой каталог. Он лежит в общем `%TEMP%` и является
    // БОЕВЫМ состоянием: по нему приложение владельца понимает, что прошлый
    // запуск упал с включённым прокси. Тест, стерший его, оставил бы машину
    // без интернета после настоящей аварии.
    tmp = Directory.systemTemp.createTempSync('sg_proxy_marker_');
    SystemProxy.markerPathOverride =
        '${tmp.path}${Platform.pathSeparator}proxy.lock';
  });

  tearDown(() {
    SystemProxy.resetRunnerForTests();
    SystemProxy.markerPathOverride = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  String log() => AppLog.entries.map((e) => e.line).join('\n');

  group('⚠️ Успех называется в журнале', () {
    test('включение пишет адрес, на который увели трафик', () async {
      final before = AppLog.entries.length;
      expect(await SystemProxy.set('127.0.0.1:10809'), isTrue);
      final added = AppLog.entries.skip(before).map((e) => e.line).join('\n');
      expect(added, contains('Системный прокси включён'));
      expect(added, contains('10809'),
          reason: 'без порта строка не отвечает на вопрос «куда именно»');
    });

    test('⚠️ включение оставляет маркер — иначе аварию некому будет убрать',
        () async {
      await SystemProxy.set('127.0.0.1:10809');
      expect(File(SystemProxy.markerPathOverride!).existsSync(), isTrue);
    });

    test('снятие убирает маркер', () async {
      await SystemProxy.set('127.0.0.1:10809');
      await SystemProxy.clear();
      expect(File(SystemProxy.markerPathOverride!).existsSync(), isFalse);
    });

    test('⚠️ маркер прошлой аварии распознаётся и называется в журнале',
        () async {
      File(SystemProxy.markerPathOverride!).writeAsStringSync('127.0.0.1:10809');
      final before = AppLog.entries.length;
      await SystemProxy.recoverIfDirty();
      expect(AppLog.entries.skip(before).map((e) => e.line).join('\n'),
          contains('аварийно'));
    });

    test('снятие пишет отдельную строку', () async {
      final before = AppLog.entries.length;
      expect(await SystemProxy.clear(), isTrue);
      expect(AppLog.entries.skip(before).map((e) => e.line).join('\n'),
          contains('Системный прокси снят'));
    });
  });

  group('⚠️ Отказ виден и назван', () {
    test('⚠️ ненулевой код reg.exe роняет set в false, а не проходит молча',
        () async {
      // Ровно тот случай, ради которого правка и делалась: правка реестра
      // запрещена, а приложение считало перехват включённым.
      arm(code: 1, err: 'ERROR: Access is denied.');
      final before = AppLog.entries.length;
      expect(await SystemProxy.set('127.0.0.1:10809'), isFalse);
      final added = AppLog.entries.skip(before).toList();
      final text = added.map((e) => e.line).join('\n');
      expect(text, contains('reg вернул 1'),
          reason: 'код возврата — единственное, что отличает один отказ '
              'от другого');
      expect(text, contains('НЕ включён'));
      expect(added.map((e) => e.level), contains(LogLevel.error),
          reason: 'трафик идёт мимо туннеля — это ошибка, а не заметка');
    });

    test('⚠️ первая же неудачная правка прекращает остальные', () async {
      // Три правки идут подряд и осмысленны только вместе. Продолжать после
      // отказа значит наполовину прописать прокси и не сказать об этом.
      arm(code: 5);
      await SystemProxy.set('127.0.0.1:10809');
      expect(calls.length, 1);
    });

    test('исключение при запуске reg.exe тоже попадает в журнал', () async {
      arm(throwIt: const ProcessException('reg', ['add']));
      final before = AppLog.entries.length;
      expect(await SystemProxy.clear(), isFalse);
      expect(AppLog.entries.skip(before).map((e) => e.line).join('\n'),
          contains('Системный прокси'));
    });

    test('неснятый прокси называет последствие, а не только факт', () async {
      // «Не удалось снять» человеку ни о чём не говорит; «интернет может не
      // работать» — говорит, что делать дальше.
      arm(code: 1);
      final before = AppLog.entries.length;
      expect(await SystemProxy.clear(), isFalse);
      expect(AppLog.entries.skip(before).map((e) => e.line).join('\n'),
          contains('интернет'));
    });
  });

  group('⚠️ Восстановление после аварии', () {
    test('без маркера молчит — ложной тревоги быть не должно', () async {
      final before = AppLog.entries.length;
      await SystemProxy.recoverIfDirty();
      expect(AppLog.entries.skip(before).map((e) => e.line).join('\n'),
          isNot(contains('аварийно')));
      expect(calls, isEmpty, reason: 'реестр трогать было незачем');
    });
  });

  test('журнал в принципе доступен (страж от пустых проверок выше)', () {
    AppLog.i('контрольная строка');
    expect(log(), contains('контрольная строка'));
  });
}
