import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ГЛАВНЫЙ ПОТОК ANDROID НЕ ЗАНИМАЕМ — НИ ЗАГРУЗКОЙ ЯДЕР, НИ ИХ ПОДЪЁМОМ.
///
/// ⚠️ ЗАЧЕМ ЭТО СТЕРЕЖЁТСЯ ТЕКСТОМ ИСХОДНИКА, А НЕ ПОВЕДЕНИЕМ. Kotlin-часть
/// живёт вне Dart-тестов: собрать и выполнить её здесь нечем, а вживую дефект
/// виден только на устройстве и только как «приложение зависло» — то есть в
/// момент, когда чинить уже поздно. Зато сам инвариант формулируется коротко и
/// проверяется по исходнику однозначно, и это лучше, чем не проверять вовсе.
///
/// ЧТО СЛУЧИЛОСЬ. 15.08.2026 владелец: «на мобилке у меня внезапно зависло
/// приложение». Flutter ждёт vsync и получает касания через `Choreographer`
/// ГЛАВНОГО потока Android: пока он занят, интерфейс не перерисовывается и не
/// реагирует. А занимали его два места сразу.
///
/// 1. `SilentGateApplication.onCreate` — `Class.forName("…libXray.LibXray")`,
///    добавленный в 1.5.0. Через `go.Seq.<clinit>` он тянет
///    `System.loadLibrary("cores")`, то есть СИНХРОННУЮ загрузку `libcores.so`
///    (58 МБ под arm64-v8a) и старт рантайма Go — при КАЖДОМ запуске процесса,
///    ещё до первого кадра Flutter. Полезного он не делал ничего: сообщение
///    того же коммита прямо говорит «ПРОВЕРЕНО ОПЫТОМ — принудительная загрузка
///    ядра сразу после setenv отказ НЕ вылечила», а комментарий рядом со строкой
///    утверждал обратное.
/// 2. `SilentGateVpnService.onStartCommand` — система вызывает его на главном
///    потоке, а внутри поднимались ОБА ядра: `LibXray.invoke(runXrayFromJson)`
///    (с 1.5.0 ещё и с разбором `geoip.dat` на 22,5 МБ) и
///    `startOrReloadService` с повторами через `Thread.sleep`.
void main() {
  final app = File('android/app/src/main/kotlin/lol/silentgate/'
      'SilentGateApplication.kt');
  final service = File('android/app/src/main/kotlin/lol/silentgate/vpn/'
      'SilentGateVpnService.kt');

  setUpAll(() {
    // Путь относительный — тест обязан бежать из `app/`. Скажем об этом явно,
    // иначе «файла нет» выглядело бы как «инвариант нарушен».
    expect(app.existsSync(), isTrue, reason: 'запускать из каталога app/');
    expect(service.existsSync(), isTrue, reason: 'запускать из каталога app/');
  });

  group('Application.onCreate не грузит ядра', () {
    test('⚠️ ГЛАВНОЕ: ни Class.forName, ни System.loadLibrary', () {
      final src = app.readAsStringSync();
      final code = _withoutComments(src);
      expect(code.contains('Class.forName'), isFalse,
          reason: 'принудительная загрузка ядра на главном потоке при каждом '
              'старте процесса — 58 МБ .so и рантайм Go до первого кадра');
      expect(code.contains('System.loadLibrary'), isFalse);
    });

    test('классы ядер не упоминаются в коде — иначе <clinit> сработает сам', () {
      // Достаточно обращения к ЛЮБОМУ типу из AAR: инициализация класса тянет
      // `go.Seq`, а он в своём статическом блоке грузит libcores.so. Именно
      // поэтому здесь запрещён не только `Class.forName`, но и импорт.
      final code = _withoutComments(app.readAsStringSync());
      expect(code.contains('lol.silentgate.cores'), isFalse,
          reason: 'ядро обязано подтягиваться лениво — у потребителя '
              '(SilentGateVpnService, PlatformChannels)');
    });
  });

  group('onStartCommand не поднимает ядра на главном потоке', () {
    late String body;

    setUp(() {
      body = _methodBody(service.readAsStringSync(), 'fun onStartCommand');
    });

    test('очередь работы существует', () {
      expect(body.contains('work.execute'), isTrue,
          reason: 'подъём и остановка ядра обязаны уходить в свой поток');
    });

    test('⚠️ ГЛАВНОЕ: startTunnel/stopTunnel зовутся только из work.execute',
        () {
      final blocks = _blocksOf(body, 'work.execute {');
      expect(blocks, isNotEmpty);
      for (final call in const ['startTunnel(', 'stopTunnel(']) {
        for (final at in _indicesOf(body, call)) {
          expect(blocks.any((b) => at > b.start && at < b.end), isTrue,
              reason: 'вызов «$call» на позиции $at исполняется на ГЛАВНОМ '
                  'потоке: там поднимаются оба ядра и разбирается geoip.dat '
                  '(22,5 МБ) — интерфейс на это время застывает');
        }
      }
    });

    test('сна на главном потоке нет', () {
      // `startOrReloadWithRetry` спит до 2,5 с суммарно, когда прошлый
      // экземпляр ядра ещё держит порт 10811 — это штатный путь перезагрузки
      // при kill switch, а не редкость. Спать он вправе, но только в очереди:
      // сам `onStartCommand` не должен усыплять главный поток ни на миг.
      expect(_withoutComments(body).contains('Thread.sleep'), isFalse);
    });
  });

  group('уведомление публикуется синхронно — контракт foreground-сервиса', () {
    test('startForeground остался в onStartCommand', () {
      // ⚠️ Обратная сторона переезда в фон: `startForegroundService` обязывает
      // показать уведомление в первые секунды, иначе система убьёт процесс
      // (ForegroundServiceDidNotStartInTimeException). Значит эта — дешёвая —
      // часть обязана остаться на главном потоке.
      final body = _methodBody(service.readAsStringSync(), 'fun onStartCommand');
      final at = _indicesOf(body, 'startForeground(');
      expect(at, isNotEmpty,
          reason: 'без этого сервис падает по таймауту foreground-контракта');
      final blocks = _blocksOf(body, 'work.execute {');
      for (final i in at) {
        expect(blocks.any((b) => i > b.start && i < b.end), isFalse,
            reason: 'уведомление обязано показаться немедленно, а очередь '
                'может дойти до него позже пяти секунд');
      }
    });
  });
}

// ── Разбор исходника ─────────────────────────────────────────────────────────

class _Block {
  const _Block(this.start, this.end);
  final int start;
  final int end;
}

/// Тело метода по сигнатуре: от первой `{` после неё до парной закрывающей.
String _methodBody(String src, String signature) {
  final at = src.indexOf(signature);
  if (at < 0) return '';
  final open = src.indexOf('{', at);
  if (open < 0) return '';
  return src.substring(open, _matching(src, open) + 1);
}

/// Блоки `метка { … }` — по парной скобке, а не по отступам.
List<_Block> _blocksOf(String src, String label) {
  final out = <_Block>[];
  for (final at in _indicesOf(src, label)) {
    final open = at + label.length - 1;
    out.add(_Block(open, _matching(src, open)));
  }
  return out;
}

int _matching(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return src.length - 1;
}

List<int> _indicesOf(String src, String needle) {
  final out = <int>[];
  var from = 0;
  while (true) {
    final at = src.indexOf(needle, from);
    if (at < 0) return out;
    out.add(at);
    from = at + 1;
  }
}

/// Убрать комментарии: они в этом проекте длинные и НАЗЫВАЮТ запрещённые
/// конструкции — ровно чтобы объяснить, почему их нельзя возвращать. Проверять
/// надо код, а не рассказ о нём.
String _withoutComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock
      .split('\n')
      .map((l) {
        final at = l.indexOf('//');
        return at < 0 ? l : l.substring(0, at);
      })
      .join('\n');
}
