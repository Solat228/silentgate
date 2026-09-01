import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/engine_notice.dart';
import 'package:silentgate/engine/windows/system_proxy.dart';

/// Молчаливый отказ системного прокси перестаёт быть молчаливым.
///
/// ⚠️ ЧЕМ ЭТО ОПАСНО ИМЕННО ЗДЕСЬ. Системный прокси — способ захвата ПО
/// УМОЛЧАНИЮ на Windows. Если `reg add` не отработал (политика домена,
/// повреждённый профиль), приложение показывает «Подключено», а трафик идёт
/// мимо туннеля — под реальным адресом. С 1.11.0 отказ хотя бы попадает в
/// журнал, но человек узнаёт о нём, только открыв логи, — то есть уже после
/// того, как поработал под реальным IP.
void main() {
  test('отказ системного прокси — это ПРОБЛЕМА, а не обычная заметка', () {
    const notice =
        EngineNotice(EngineNoticeKind.systemProxyFailed, 'не включился');
    expect(notice.isProblem, isTrue,
        reason: 'трафик под реальным адресом при надписи «Подключено» — '
            'красное сообщение, а не серая заметка на 6 секунд');
  });

  test('обычные заметки проблемой не считаются — контроль', () {
    const ok = EngineNotice(EngineNoticeKind.recovered, 'связь вернулась');
    expect(ok.isProblem, isFalse);
  });

  test('⚠️ СТРАЖ: результат SystemProxy.set на месте вызова не выбрасывается',
      () {
    // Функция возвращает `Future<bool>`, и `await` без присваивания — законный
    // Dart: компилятор промолчит, анализатор тоже. Ровно так отказ и жил
    // незамеченным. Проверяем ИСХОДНИК места вызова, а не намерение.
    final src = File('lib/engine/windows/windows_engine.dart');
    expect(src.existsSync(), isTrue);
    final text = src.readAsStringSync();

    final discarded = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('await SystemProxy.set('))
        .toList();
    expect(discarded, isEmpty,
        reason: 'результат обязан быть использован: '
            '`final ok = await SystemProxy.set(...)` и заметка при false');
    expect(text.contains('EngineNoticeKind.systemProxyFailed'), isTrue,
        reason: 'при отказе движок обязан слать заметку, а не только писать '
            'в журнал');
  });
}
