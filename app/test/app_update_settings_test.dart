import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';

/// Настройки самообновления приложения (1.14.0): режим `ask | auto | notify`
/// и «пропущенная версия».
///
/// Отдельный файл, а не строки в `settings_roundtrip_test`: тот страж идёт по
/// булевым и числовым ключам `toJson`, а режим хранится СТРОКОЙ и мимо него
/// проходит — ровно так, как мимо него проходили `logRetention` и
/// `serviceChecksLayout`. Плюс здесь миграция со старого флага, которой в
/// общем страже места нет.
void main() {
  group('AppUpdateMode — сериализация', () {
    test('умолчание — спрашивать (решение владельца 19.09.2026)', () {
      expect(AppSettings.defaults.appUpdateMode, AppUpdateMode.ask);
      expect(const AppSettings().appUpdateMode, AppUpdateMode.ask);
    });

    test('в файл пишется короткое имя: ask | auto | notify', () {
      // ⚠️ Не `.name`: у `notifyOnly` имя в коде длиннее, чем в файле, и
      // страж нужен именно на это расхождение — переименование значения в
      // Dart не должно молча менять формат на диске.
      expect(AppUpdateMode.ask.wireName, 'ask');
      expect(AppUpdateMode.auto.wireName, 'auto');
      expect(AppUpdateMode.notifyOnly.wireName, 'notify');
      expect(
          const AppSettings(appUpdateMode: AppUpdateMode.notifyOnly)
              .toJson()['appUpdateMode'],
          'notify');
    });

    test('каждое значение режима переживает сохранение и загрузку', () {
      for (final v in AppUpdateMode.values) {
        final json = AppSettings(appUpdateMode: v).toJson();
        final loaded = AppSettings.fromJson(json);
        expect(loaded.appUpdateMode, v,
            reason: 'режим обновления «$v» не переживает сохранение');
      }
    });

    test('отсутствие ключа читается как ask', () {
      final json = Map<String, dynamic>.of(const AppSettings().toJson())
        ..remove('appUpdateMode');
      expect(AppSettings.fromJson(json).appUpdateMode, AppUpdateMode.ask);
    });

    test('мусор в ключе читается как ask, а не роняет разбор', () {
      for (final junk in <Object?>['какой-то-режим', 42, true, '', null]) {
        final json = Map<String, dynamic>.of(const AppSettings().toJson())
          ..['appUpdateMode'] = junk;
        expect(AppSettings.fromJson(json).appUpdateMode, AppUpdateMode.ask,
            reason: 'значение $junk должно давать ask');
      }
    });

    test('parse понимает только короткие имена, регистр не прощает', () {
      expect(AppUpdateMode.parse('ask'), AppUpdateMode.ask);
      expect(AppUpdateMode.parse('auto'), AppUpdateMode.auto);
      expect(AppUpdateMode.parse('notify'), AppUpdateMode.notifyOnly);
      // Имя значения из Dart в файле не хранится — и читаться не должно, иначе
      // два формата одного поля разъедутся между версиями.
      expect(AppUpdateMode.parse('notifyOnly'), AppUpdateMode.ask);
      expect(AppUpdateMode.parse('Auto'), AppUpdateMode.ask);
      expect(AppUpdateMode.parse(null), AppUpdateMode.ask);
    });
  });

  group('appUpdateSkippedVersion', () {
    test('умолчание — ничего не пропущено', () {
      expect(AppSettings.defaults.appUpdateSkippedVersion, isNull);
    });

    test('значение переживает сохранение и загрузку', () {
      final json =
          const AppSettings(appUpdateSkippedVersion: '1.14.1').toJson();
      expect(json['appUpdateSkippedVersion'], '1.14.1');
      expect(AppSettings.fromJson(json).appUpdateSkippedVersion, '1.14.1');
    });

    test('null переживает сохранение и загрузку', () {
      final json = const AppSettings().toJson();
      expect(json.containsKey('appUpdateSkippedVersion'), isTrue,
          reason: 'ключ пишется всегда, чтобы страж roundtrip его видел');
      expect(json['appUpdateSkippedVersion'], isNull);
      expect(AppSettings.fromJson(json).appUpdateSkippedVersion, isNull);
    });

    test('copyWith умеет СБРОСИТЬ пропуск (иначе «Пропустить» необратимо)', () {
      const s = AppSettings(appUpdateSkippedVersion: '1.14.1');
      expect(s.copyWith().appUpdateSkippedVersion, '1.14.1',
          reason: 'copyWith без аргумента поле не трогает');
      expect(s.copyWith(clearAppUpdateSkippedVersion: true)
              .appUpdateSkippedVersion,
          isNull);
      expect(s.copyWith(appUpdateSkippedVersion: '1.15.0')
              .appUpdateSkippedVersion,
          '1.15.0');
    });

    test('мусор вместо строки читается как null', () {
      final json = Map<String, dynamic>.of(const AppSettings().toJson())
        ..['appUpdateSkippedVersion'] = 7;
      expect(AppSettings.fromJson(json).appUpdateSkippedVersion, isNull);
    });
  });

  group('миграция со старого appUpdateNotesHidden', () {
    Map<String, dynamic> legacy({required Object? notesHidden}) {
      final json = Map<String, dynamic>.of(const AppSettings().toJson())
        ..remove('appUpdateMode');
      if (notesHidden != null) json['appUpdateNotesHidden'] = notesHidden;
      return json;
    }

    test('true → notifyOnly: человек просил убрать окно, а не обновления', () {
      expect(AppSettings.fromJson(legacy(notesHidden: true)).appUpdateMode,
          AppUpdateMode.notifyOnly);
    });

    test('false → ask', () {
      expect(AppSettings.fromJson(legacy(notesHidden: false)).appUpdateMode,
          AppUpdateMode.ask);
    });

    test('ключа нет → ask', () {
      expect(AppSettings.fromJson(legacy(notesHidden: null)).appUpdateMode,
          AppUpdateMode.ask);
    });

    test('новый ключ важнее старого флага', () {
      // Файл, который уже прошёл через новую версию, а старый ключ в нём
      // остался (или дописан руками): режим берётся из нового ключа.
      final json = legacy(notesHidden: true)..['appUpdateMode'] = 'auto';
      expect(AppSettings.fromJson(json).appUpdateMode, AppUpdateMode.auto);
      final json2 = legacy(notesHidden: true)..['appUpdateMode'] = 'ask';
      expect(AppSettings.fromJson(json2).appUpdateMode, AppUpdateMode.ask,
          reason: 'явный ask в новом ключе не должен перебиваться старым флагом');
    });

    test('ключ appUpdateNotesHidden больше не пишется', () {
      final json = const AppSettings().toJson();
      expect(json.containsKey('appUpdateNotesHidden'), isFalse);
      // И после чтения старого файла он тоже не воскресает.
      final back = AppSettings.fromJson(legacy(notesHidden: true)).toJson();
      expect(back.containsKey('appUpdateNotesHidden'), isFalse);
      expect(back['appUpdateMode'], 'notify');
    });
  });

  test('обновление приложения не требует переподключения туннеля', () {
    // Ни режим, ни пропуск версии в конфиг ядра не запекаются — и требовать
    // из-за них переподключения было бы враньём (см. комментарий у
    // `reconnectReasons`).
    const a = AppSettings();
    const b = AppSettings(
      appUpdateMode: AppUpdateMode.auto,
      appUpdateSkippedVersion: '1.14.1',
      appUpdateCheck: false,
      betaChannel: true,
    );
    expect(a.reconnectReasons(b), isEmpty);
    expect(a.requiresReconnect(b), isFalse);
  });
}
