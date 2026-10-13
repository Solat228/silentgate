import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ДВИЖОК FLUTTER НА ANDROID ОБЯЗАН ПЕРЕЖИВАТЬ ACTIVITY.
///
/// ⚠️ Решение 4а было записано в июле и не сделано до 13.10.2026: каждая
/// Activity поднимала свой движок и уносила его с собой. Система снимает
/// Activity в фоне когда хочет, и у владельца весь Dart перезапускался по
/// нескольку раз в минуту: пинг обрывался, интерфейс открывался на главном,
/// QR с камеры распознавался, но ответ сканера ждать было некому.
///
/// Проверить это поведение можно только на устройстве (эмулятор с
/// `always_finish_activities 1`), а сломать — одной строкой. Поэтому страж на
/// исходник: каждая из четырёх частей по отдельности выглядит лишней.
void main() {
  String read(String p) =>
      File(p).readAsStringSync().replaceAll('\r\n', '\n');

  final activity =
      read('android/app/src/main/kotlin/lol/silentgate/MainActivity.kt');
  final qr =
      read('android/app/src/main/kotlin/lol/silentgate/platform/QrScanner.kt');

  /// Тело companion object — от его начала до первой строки с отступом в
  /// четыре пробела и закрывающей скобкой.
  String companionOf(String src) {
    final start = src.indexOf('companion object {');
    expect(start, greaterThanOrEqualTo(0));
    final end = src.indexOf('\n    }\n', start);
    return src.substring(start, end);
  }

  test('движок берётся из кэша и не гасится вместе с Activity', () {
    expect(activity, contains('override fun provideFlutterEngine('));
    expect(activity, contains('FlutterEngineCache.getInstance()'));
    expect(activity,
        contains('override fun shouldDestroyEngineWithHost(): Boolean = false'));
  });

  test('⚠️ ожидание ответа сканера живёт дольше Activity', () {
    expect(companionOf(qr), contains('var pending: MethodChannel.Result?'),
        reason: 'поле экземпляра теряется вместе с Activity — QR с камеры '
            'распознаётся, а импорта нет');
  });

  test('⚠️ согласие на VPN, ссылка и сток событий — в companion', () {
    final c = companionOf(activity);
    for (final field in [
      'var pendingResult:',
      'var pendingConfig:',
      'var pendingLink:',
      'var dartTookInitial',
      'var events:',
      'var eventsEngine:',
    ]) {
      expect(c, contains(field), reason: field);
    }
  });

  test('⚠️ ссылка при живом Dart отдаётся сразу, а не копится', () {
    // Новая Activity при живом движке получает ссылку в configureFlutterEngine;
    // `consumeInitial` второй раз никто не позовёт.
    expect(activity, contains('dartTookInitial = true'));
    expect(activity, contains('linkFrom(intent)?.let { deliverLink(it) }'));
    expect(RegExp(r'if \(dartTookInitial && ch != null\)').hasMatch(activity),
        isTrue);
  });

  test('канал событий регистрируется один раз на движок', () {
    expect(activity, contains('if (eventsEngine !== flutterEngine)'));
  });

  test('обработчики, живущие с движком, не держатся за Activity', () {
    expect(RegExp(r'(^|[^`.])runOnUiThread \{', multiLine: true).hasMatch(activity),
        isFalse,
        reason: 'ответ Dart обязан дойти и после того, как Activity сняли');
    expect(activity, isNot(contains('MainThreadResult(this,')));
  });
}
