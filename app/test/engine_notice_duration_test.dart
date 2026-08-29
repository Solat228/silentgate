import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/ui/home_screen.dart';

/// ТАЙМАУТ АВТОЗАКРЫТИЯ ЗАМЕТКИ О МЁРТВОМ ПРАВИЛЕ — РЕШЕНИЕ ВЛАДЕЛЬЦА: 1 МИНУТА.
///
/// ⚠️ ПОЧЕМУ ЧИСТАЯ ФУНКЦИЯ, А НЕ ВИДЖЕТ-ТЕСТ ВСЕГО ГЛАВНОГО ЭКРАНА.
/// `engineNoticeDuration` вынесена из `_showEngineNotices` ровно ради этого —
/// поднимать `HomeScreen` целиком (провайдеры, движок, локализация) только
/// чтобы проверить одно число, было бы тяжелее самого поведения.
void main() {
  test('⚠️ мёртвый путь правила — минута, а не общие 6/10 секунд', () {
    expect(
        engineNoticeDuration(EngineNoticeKind.deadAppRule, isProblem: false),
        const Duration(minutes: 1));
  });

  test('устаревшая задача Планировщика — дольше обычной заметки', () {
    final d = engineNoticeDuration(EngineNoticeKind.staleScheduledTask,
        isProblem: false);
    expect(d, greaterThan(const Duration(seconds: 6)),
        reason: 'у заметки есть кнопка «Исправить» — 6 секунд мало, чтобы '
            'прочитать и решить');
  });

  test('старые виды поведения не потревожены', () {
    expect(engineNoticeDuration(EngineNoticeKind.blocked, isProblem: false),
        const Duration(seconds: 6));
    expect(engineNoticeDuration(EngineNoticeKind.failed, isProblem: true),
        const Duration(seconds: 10));
  });
}
