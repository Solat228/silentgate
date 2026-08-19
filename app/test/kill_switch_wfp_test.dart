import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/kill_switch_wfp.dart';

/// СОСТАВ БЛОКИРОВКИ — ЕДИНСТВЕННОЕ, ЧТО МОЖНО ПРОВЕРИТЬ ТЕСТОМ.
///
/// ⚠️ ПОЧЕМУ ЗДЕСЬ НЕТ НИ ОДНОГО ВЫЗОВА К СИСТЕМЕ. Фильтры Windows Filtering
/// Platform действуют на сеть ВСЕЙ машины, а тесты гоняются на машине
/// владельца, где в это время идёт его работа. Ошибка в тесте здесь означала бы
/// не красную строчку, а человека без интернета. Поэтому состав правил вынесен
/// в чистую функцию и проверяется тут, а сами вызовы — только в изолированной
/// VM, руками.
///
/// ⚠️ И ОТДЕЛЬНО — ДВА СТРАЖА, КОТОРЫЕ СМОТРЯТ НА ИСХОДНИК, А НЕ НА ПОВЕДЕНИЕ.
/// Флаг постоянного фильтра и статическая сессия не проявляются в тестах никак:
/// они проявляются на чужой машине через сутки, когда снять их уже нечем.
/// Единственный способ их стеречь — искать в тексте файла.
void main() {
  group('Состав блокировки', () {
    test('⚠️ адреса серверов разрешены ВСЕГДА', () {
      // Иначе туннель не поднимется заново: ядру некуда постучаться, и
      // блокировка станет вечной — сама себя не снимет.
      final plan = KillSwitchWfp.planFor(
        serverIps: {'203.0.113.10', '198.51.100.7'},
        tunnelAppPaths: const [],
        blockEverything: true,
      );
      expect(plan.allowServerIps, {'203.0.113.10', '198.51.100.7'});
    });

    test('⚠️ свои бинари разрешены даже при полной блокировке', () {
      // Иначе приложение не сможет ни проверить канал, ни обновить подписку,
      // ни объяснить человеку, что происходит: мёртвая сеть и молчащее окно.
      final plan = KillSwitchWfp.planFor(
        serverIps: const {},
        tunnelAppPaths: const [],
        blockEverything: true,
      );
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
      // остаётся исключением и из блокировки. Человек сам сказал, что этим
      // приложениям VPN не нужен, — рубить им сеть значит спорить с ним.
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

  group('⚠️ Стражи по исходнику: цена ошибки — машина без интернета', () {
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
      expect(source.contains('0x00000001 << 1'), isFalse);
    });

    test('⚠️ сессия объявлена ДИНАМИЧЕСКОЙ', () {
      // Только динамическая сессия снимается самой Windows при смерти
      // процесса — включая аварийную. Статическая переживёт крах.
      expect(source.contains('_sessionFlagDynamic = 0x00000001'), isTrue);
      expect(source.contains('session.ref.flags = _sessionFlagDynamic'), isTrue,
          reason: 'флаг обязан выставляться, а не просто быть объявленным');
    });

    test('⚠️ разведка ОТКАТЫВАЕТ транзакцию, а не применяет', () {
      // Разведка не имеет права оставить в системе ни одного объекта.
      expect(source.contains('_txnAbort(engine)'), isTrue);
      expect(source.contains('FwpmTransactionCommit0'), isFalse,
          reason: 'пока идёт только разведка, применять нечего и незачем');
    });

    test('⚠️ добавления настоящих фильтров ещё НЕТ', () {
      // Страж на порядок работ: правила появятся только после того, как
      // разведка подтвердит права в VM. Если этот тест покраснел — значит
      // фильтры написаны, и его надо заменить на проверки их состава.
      expect(source.contains('FwpmFilterAdd0'), isFalse,
          reason: 'фильтры добавляем только после живой проверки разведки');
    });
  });
}
