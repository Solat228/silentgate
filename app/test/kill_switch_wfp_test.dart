import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/kill_switch_wfp.dart';

/// СТРАЖИ ПО ИСХОДНИКУ: ЦЕНА ОШИБКИ — МАШИНА БЕЗ ИНТЕРНЕТА.
///
/// ⚠️ ПОЧЕМУ ЗДЕСЬ ПОЧТИ НЕТ ВЫЗОВОВ. Фильтры Windows Filtering Platform
/// действуют на сеть ВСЕЙ машины, а тесты гоняются на машине владельца, где в
/// это время идёт его работа. Вызвать `engage` с непустым планом в тесте —
/// значит поставить настоящую блокировку на настоящий компьютер. Поэтому
/// состав правил проверяется отдельно и целиком в `wfp_rules_test.dart`
/// (чистые данные), а здесь стерегутся свойства, которые не проявляются в
/// поведении вовсе: они проявляются на чужой машине через сутки, когда снять
/// уже нечем.
void main() {
  group('План — тонкая обёртка над построителем', () {
    test('⚠️ адреса серверов разрешены ВСЕГДА', () {
      // Иначе туннель не поднимется заново: ядру некуда постучаться, и
      // блокировка станет вечной — сама себя не снимет.
      final plan = KillSwitchWfp.planFor(
        serverIps: {'203.0.113.10', '198.51.100.7'},
        tunnelAppPaths: const [],
        blockEverything: true,
      );
      expect(plan.allowServerIps, {'203.0.113.10', '198.51.100.7'});
      expect(plan.allowOwnBinaries, isTrue);
      expect(plan.allowLoopback, isTrue);
    });

    test('«всё через VPN» — блокируем всё, список приложений пуст', () {
      final plan = KillSwitchWfp.planFor(
        serverIps: const {'203.0.113.10'},
        tunnelAppPaths: const [r'C:\app\one.exe'],
        blockEverything: true,
      );
      expect(plan.blockAll, isTrue);
      expect(plan.blockedAppPaths, isEmpty,
          reason: 'при полной блокировке перечислять приложения незачем');
    });

    test('⚠️ «только отмеченные» — режем ТОЛЬКО туннельные приложения', () {
      // Решение владельца 19.08.2026 (школа Mullvad): исключение из туннеля
      // остаётся исключением и из блокировки.
      final plan = KillSwitchWfp.planFor(
        serverIps: const {'203.0.113.10'},
        tunnelAppPaths: const [r'C:\app\one.exe', r'C:\app\two.exe'],
        blockEverything: false,
      );
      expect(plan.blockAll, isFalse);
      expect(plan.blockedAppPaths, [r'C:\app\one.exe', r'C:\app\two.exe']);
    });

    test('блокировать нечего — план пуст', () {
      final plan = KillSwitchWfp.planFor(
        serverIps: const {'203.0.113.10'},
        tunnelAppPaths: const [],
        blockEverything: false,
      );
      expect(plan.isEmpty, isTrue,
          reason: 'поднимать фильтры не из-за чего — незачем и трогать систему');
    });
  });

  group('⚠️ Единственный безопасный вызов: пустой план', () {
    test('engage на пустом плане возвращается, НЕ ТРОНУВ систему', () {
      // ⚠️ Это единственный вызов `engage`, допустимый в тесте: на пустом
      // плане он выходит ДО открытия движка, то есть не создаёт ни сессии, ни
      // подслоя, ни фильтра. Любой непустой план поставил бы настоящую
      // блокировку на машину, где идёт работа владельца.
      final plan = KillSwitchWfp.planFor(
        serverIps: const {'203.0.113.10'},
        tunnelAppPaths: const [],
        blockEverything: false,
      );
      final log = <String>[];
      final hold = KillSwitchWfp.engage(plan, log: log.add);
      expect(hold, isNull);
      expect(log.join(), contains('блокировать нечего'),
          reason: 'молчаливый отказ не отличить от молчаливого успеха');
    });
  });

  group('⚠️ Стражи по исходнику', () {
    late String source;

    setUp(() {
      // ⚠️ КОММЕНТАРИИ ВЫРЕЗАЕМ, И ЭТО НЕ ПРИДИРКА. Первая редакция стража
      // искала слово по всему файлу — и краснела на СОБСТВЕННОМ комментарии
      // «PERSISTENT не использовать НИКОГДА». Страж, не отличающий
      // документацию от кода, ловит сам себя: его отключат в первый же день, и
      // он перестанет стеречь то, ради чего написан.
      source = File('lib/engine/windows/kill_switch_wfp.dart')
          .readAsLinesSync()
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join(String.fromCharCode(10));
    });

    test('⚠️ ГЛАВНОЕ: флага постоянного фильтра нет НИГДЕ', () {
      // `FWPM_FILTER_FLAG_PERSISTENT` переживает ПЕРЕЗАГРУЗКУ. Снять его будет
      // некому: службы у нас нет (у Proton есть, и даже там это отдельная
      // кнопка с предупреждением). Появление этого флага означает, что человек
      // может остаться без сети навсегда — и заметить это в тестах никак.
      expect(source.contains('PERSISTENT'), isFalse,
          reason: 'постоянные фильтры запрещены: снять их будет нечем');
      expect(source.contains('filterFlagPersistent'), isFalse);
    });

    test('⚠️ поле flags у фильтра не заполняется вовсе', () {
      // Единственное место, где `FWPM_FILTER_FLAG_PERSISTENT` мог бы оказаться,
      // — это поле `flags` структуры фильтра. Мы его не трогаем: буфер обнулён,
      // и ноль здесь означает «обычный временный фильтр».
      expect(source.contains('WfpFilterOffsets.flags'), isFalse,
          reason: 'запись в flags — единственный путь к постоянному фильтру');
    });

    test('⚠️ ОБЕ сессии объявлены ДИНАМИЧЕСКИМИ', () {
      // Только динамическая сессия снимается самой Windows при смерти
      // процесса — включая аварийную. Статическая переживёт крах.
      // Сессий две: разведка и боевой подъём. Забыть флаг во второй — значит
      // получить блокировку, переживающую падение приложения.
      final marks = RegExp('WfpSessionOffsets.flags, WfpConst.sessionFlagDynamic')
          .allMatches(source)
          .length;
      expect(marks, 2,
          reason: 'флаг обязан стоять и в разведке, и в боевом подъёме');
    });

    test('⚠️ разведка ОТКАТЫВАЕТ транзакцию и ничего не применяет', () {
      // Разведка не имеет права оставить в системе ни одного объекта.
      expect(source.contains('_txnAbort(engine)'), isTrue);
      // Применение — ровно одно, и оно в боевом подъёме.
      expect(RegExp(r'_txnCommit\(engine\)').allMatches(source).length, 1,
          reason: 'второй commit означал бы, что что-то применяет и разведка');
    });

    test('⚠️ у разведки и у блокировки РАЗНЫЕ подслои', () {
      // Общий ключ означал бы, что разведка при поднятой блокировке упрётся в
      // «уже существует» и доложит об отсутствии прав — то есть соврёт.
      expect(source.contains('_subLayerKey ='), isTrue);
      expect(source.contains('_probeSubLayerKey ='), isTrue);
    });

    test('⚠️ откат стоит в finally, а не в ветке ошибки', () {
      // Веток выхода из `engage` много (каждый код возврата — своя), и
      // перечислять откат в каждой значит однажды забыть. `finally` не забудет.
      final finallyAt = source.indexOf('} finally {');
      final abortAt = source.lastIndexOf('_txnAbort(engine)');
      expect(finallyAt, greaterThan(0));
      expect(abortAt, greaterThan(finallyAt),
          reason: 'откат обязан быть в finally, иначе ветка ошибки его минует');
    });
  });
}
