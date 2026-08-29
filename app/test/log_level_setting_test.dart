import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/platform/app_log.dart';
import 'package:silentgate/core/platform/app_paths.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/core/singbox/singbox_config_builder.dart';
import 'package:silentgate/data/settings_storage.dart';
import 'package:silentgate/state/settings_controller.dart';

/// ⚠️ ПОРОГ ЖУРНАЛА ОБЯЗАН ДОХОДИТЬ ДО САМОГО ЖУРНАЛА.
///
/// Настройка, которая сохраняется, показывается в интерфейсе и ни на что не
/// влияет, — это худший вид дефекта: человек уверен, что подробности включены,
/// а в отчёте поддержки их нет, и авария разбирается вслепую. В этом проекте
/// такое уже случалось (виджет написан и не вызван), поэтому здесь проверяется
/// не «поле сохранилось», а «AppLog.minLevel действительно изменился».
void main() {
  late Directory tmp;
  late LogLevel savedLevel;

  setUp(() {
    // ⚠️ Боевой %APPDATA% тестам трогать нельзя (правило проекта): контроллер
    // пишет настройки на диск, и без подмены корня он перезаписал бы файл
    // владельца.
    tmp = Directory.systemTemp.createTempSync('sg_loglevel_');
    AppPaths.overrideRoot(tmp);
    savedLevel = AppLog.minLevel; // порог глобальный — вернём как было
  });

  tearDown(() {
    AppLog.minLevel = savedLevel;
    AppPaths.resetForTests();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<SettingsController> controller() async {
    final c = SettingsController(storage: SettingsStorage());
    await c.init();
    return c;
  }

  group('⚠️ Настройка доходит до журнала', () {
    test('умолчание — прежнее поведение (info)', () async {
      await controller();
      expect(AppLog.minLevel, LogLevel.info,
          reason: 'умолчание обязано совпадать с тем, что было до появления '
              'порога: иначе обновление молча обрежет чужие журналы');
    });

    test('⚠️ выбор уровня меняет порог СРАЗУ, не дожидаясь перезапуска', () async {
      final c = await controller();
      await c.update((s) => s.copyWith(appLogLevel: AppLogLevel.debug));
      expect(AppLog.minLevel, LogLevel.debug);
      await c.update((s) => s.copyWith(appLogLevel: AppLogLevel.warn));
      expect(AppLog.minLevel, LogLevel.warn);
    });

    test('⚠️ «всё подряд» сильнее выбранного уровня', () async {
      final c = await controller();
      await c.update(
          (s) => s.copyWith(appLogLevel: AppLogLevel.warn, verboseLogging: true));
      expect(AppLog.minLevel, LogLevel.debug,
          reason: 'галочка задумана как один переключатель на случай аварии');
    });

    test('снятая галочка возвращает выбранный уровень, а не умолчание', () async {
      // Выбор человека не должен теряться из-за временного включения
      // подробностей — иначе после разбора аварии настройки молча «съедут».
      final c = await controller();
      await c.update(
          (s) => s.copyWith(appLogLevel: AppLogLevel.warn, verboseLogging: true));
      await c.update((s) => s.copyWith(verboseLogging: false));
      expect(AppLog.minLevel, LogLevel.warn);
      expect(c.settings.appLogLevel, AppLogLevel.warn);
    });

    test('порог восстанавливается при запуске из сохранённых настроек', () async {
      final c = await controller();
      await c.update((s) => s.copyWith(appLogLevel: AppLogLevel.debug));
      AppLog.minLevel = LogLevel.info; // как будто приложение перезапустили
      await controller();
      expect(AppLog.minLevel, LogLevel.debug,
          reason: 'настройка обязана применяться и при загрузке, а не только '
              'при изменении');
    });
  });

  group('⚠️ Порог действительно отсекает строки', () {
    test('отладочная строка не пишется на уровне info', () {
      AppLog.minLevel = LogLevel.info;
      final before = AppLog.entries.length;
      AppLog.d('это не должно попасть в журнал');
      expect(AppLog.entries.length, before,
          reason: 'иначе порог экономит только на бумаге');
    });

    test('на debug пишется', () {
      AppLog.minLevel = LogLevel.debug;
      final before = AppLog.entries.length;
      AppLog.d('строка уровня debug');
      expect(AppLog.entries.length, greaterThan(before));
      expect(AppLog.entries.last.level, LogLevel.debug);
    });

    test('⚠️ авария пишется ВСЕГДА, какой бы порог ни стоял', () {
      // Ошибку нельзя отключить настройкой: именно она нужна в отчёте.
      AppLog.minLevel = LogLevel.warn;
      final before = AppLog.entries.length;
      AppLog.e('сообщение об ошибке');
      expect(AppLog.entries.length, greaterThan(before));
    });
  });

  group('⚠️ Настройки переживают сохранение', () {
    test('оба поля round-trip', () {
      for (final v in AppLogLevel.values) {
        final json = AppSettings(appLogLevel: v, verboseLogging: true).toJson();
        final back = AppSettings.fromJson(json);
        expect(back.appLogLevel, v);
        expect(back.verboseLogging, isTrue);
      }
    });

    test('неизвестное значение читается как info, а не роняет разбор', () {
      // Битый файл настроек обнуляет ВСЁ — этот класс ошибок в проекте уже
      // ловили, поэтому неизвестное значение обязано падать на умолчание.
      final json = AppSettings.defaults.toJson()
        ..['appLogLevel'] = 'какой-то-будущий-уровень';
      expect(AppSettings.fromJson(json).appLogLevel, AppLogLevel.info);
    });

    test('отсутствие ключей — прежнее поведение', () {
      final json = AppSettings.defaults.toJson()
        ..remove('appLogLevel')
        ..remove('verboseLogging');
      final back = AppSettings.fromJson(json);
      expect(back.appLogLevel, AppLogLevel.info);
      expect(back.verboseLogging, isFalse);
    });
  });

  group('⚠️ «Всё подряд» доходит и до ЯДРА', () {
    test('действующий уровень ядра поднимается до debug', () {
      const s = AppSettings(
          singboxLogLevel: SingboxLogLevel.warn, verboseLogging: true);
      expect(s.effectiveSingboxLogLevel, SingboxLogLevel.debug);
    });

    test('без галочки действует выбранный руками', () {
      const s = AppSettings(singboxLogLevel: SingboxLogLevel.info);
      expect(s.effectiveSingboxLogLevel, SingboxLogLevel.info);
    });

    test('⚠️ уровень попадает в КОНФИГ ядра, а не только в настройки', () {
      // Ровно тот разрыв, из-за которого настройка была бы декоративной:
      // приложение пишет подробнее, ядро — как раньше, и человек уверен, что
      // включил всё.
      final o = TunOptions.fromSettings(const AppSettings(
          singboxLogLevel: SingboxLogLevel.warn, verboseLogging: true));
      expect(o.logLevel, 'debug');
    });
  });

  group('⚠️ Переподключение — только когда конфиг ядра вправду изменился', () {
    test('уровень журнала ПРИЛОЖЕНИЯ туннель не трогает', () {
      // Порог приложения живёт в памяти процесса; рвать из-за него живой
      // туннель значило бы наказывать за попытку собрать журнал.
      const a = AppSettings(appLogLevel: AppLogLevel.info);
      const b = AppSettings(appLogLevel: AppLogLevel.debug);
      expect(a.requiresReconnect(b), isFalse);
    });

    test('включение «всё подряд» переподключения требует — в режиме туннеля',
        () {
      // ⚠️ ИМЕННО В ТУННЕЛЕ. Уровень уходит в конфиг TUN-ядра, а оно
      // поднимается только в этом режиме; прокси-ядро уровень не спрашивает
      // вовсе. Умолчание же `captureMode` — системный прокси, поэтому тест на
      // умолчаниях проверял бы обратное тому, что задумано.
      const a = AppSettings(captureMode: CaptureMode.tun);
      const b = AppSettings(captureMode: CaptureMode.tun, verboseLogging: true);
      expect(a.requiresReconnect(b), isTrue,
          reason: 'уровень ядра запекается в конфиг при подъёме');
      expect(a.reconnectReasons(b), contains('уровень лога ядра'));
    });

    test('⚠️ вне туннеля «всё подряд» живой сеанс не рвёт', () {
      const a = AppSettings(captureMode: CaptureMode.systemProxy);
      const b = AppSettings(
          captureMode: CaptureMode.systemProxy, verboseLogging: true);
      expect(a.requiresReconnect(b), isFalse,
          reason: 'журнал приложения меняется в памяти, а прокси-ядро уровень '
              'не читает — переподключаться не за чем');
    });

    test('⚠️ при включённом «всё подряд» правка уровня ядра НЕ рвёт туннель',
        () {
      // Оба раза ядро на `debug` — конфиг тот же самый. Сравнение по
      // выбранному руками полю давало бы здесь ложное «переподключитесь».
      const a = AppSettings(
          captureMode: CaptureMode.tun,
          singboxLogLevel: SingboxLogLevel.warn,
          verboseLogging: true);
      const b = AppSettings(
          captureMode: CaptureMode.tun,
          singboxLogLevel: SingboxLogLevel.info,
          verboseLogging: true);
      expect(a.requiresReconnect(b), isFalse);
    });
  });
}
