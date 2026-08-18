import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «ПОСТОЯННАЯ VPN» ОБЯЗАНА ПОДНИМАТЬСЯ БЕЗ КОНФИГА В ИНТЕНТЕ.
///
/// ⚠️ ЗАЧЕМ ЭТО СТЕРЕЖЁТСЯ ТЕКСТОМ ИСХОДНИКА. Kotlin-часть живёт вне Dart-тестов
/// (собрать и выполнить её здесь нечем), а вживую дефект виден только после
/// ПЕРЕЗАГРУЗКИ ТЕЛЕФОНА — то есть в момент, когда пользователь уже остался без
/// интернета и чинить некогда. Инвариант при этом формулируется коротко и по
/// исходнику проверяется однозначно; это лучше, чем не проверять вовсе. Тот же
/// приём уже применён в `android_main_thread_test.dart`.
///
/// ЧТО БЫЛО СЛОМАНО. При включённой «Постоянной VPN» Android поднимает
/// `VpnService` САМ: после перезагрузки, до разблокировки экрана — и конфига в
/// интенте нет по определению, система его не знает. Ветка
/// `if (config.isNullOrBlank())` в `onStartCommand` на это отвечала
/// `lastError = "Пустой конфиг"` и `stopSelf()`, то есть постоянная VPN не
/// работала ВООБЩЕ.
///
/// Цена была не «неудобство»: приложение САМО предлагает включить постоянную
/// VPN, а вместе с системной галочкой «блокировать соединения без VPN» телефон
/// оставался БЕЗ ИНТЕРНЕТА после каждой перезагрузки — и вернуть его можно было
/// только руками, через системные настройки. Записано в CLAUDE.md как
/// «Always-on VPN на Android не реализован» с 1.3.0.
void main() {
  final service = File('android/app/src/main/kotlin/lol/silentgate/vpn/'
      'SilentGateVpnService.kt');

  late String src;

  setUpAll(() {
    expect(service.existsSync(), isTrue,
        reason: 'сервис переехал — тест обязан упасть, а не молча позеленеть: '
            'иначе он перестанет стеречь что-либо, оставшись зелёным навсегда');
    src = service.readAsStringSync();
  });

  group('Системный старт без конфига', () {
    test('⚠️ ГЛАВНОЕ: пустой конфиг пробует восстановить сессию', () {
      expect(src, contains('loadSessionForAlwaysOn()'),
          reason: 'ЗДЕСЬ БЫЛ ОТКАЗ: сервис гасил себя с «Пустой конфиг», и '
              'постоянная VPN не поднималась никогда');
    });

    test('восстановление идёт ДО отказа, а не после', () {
      final restore = src.indexOf('loadSessionForAlwaysOn()');
      final giveUp = src.indexOf('Постоянная VPN: нет сохранённой сессии');
      expect(restore, greaterThan(0));
      expect(giveUp, greaterThan(0));
      expect(restore, lessThan(giveUp),
          reason: 'иначе попытка восстановления недостижима, а ветка отказа '
              'снова гасит сервис молча');
    });

    test('отказ называет ПРИЧИНУ и что делать', () {
      // «Пустой конфиг» человеку не говорит ничего: он не знает ни про интенты,
      // ни про то, что систему конфигом никто не снабжает.
      expect(src, contains('подключитесь один раз вручную'),
          reason: 'сообщение обязано подсказывать выход, а не называть внутренность');
      expect(src, isNot(contains('lastError = "Пустой конфиг"')),
          reason: 'прежний текст ничего не объяснял');
    });
  });

  group('Что именно сохраняем', () {
    test('⚠️ сохраняем ТОЛЬКО поднявшуюся сессию', () {
      // Сохранять конфиг до подъёма значило бы обречь каждую загрузку телефона
      // повторять ту же неудачу.
      // ⚠️ Ищем ВЫЗОВ, а не объявление: `saveSessionForAlwaysOn(configJson:`
      // — это сигнатура метода, и по ней тест сравнивал позицию объявления с
      // позицией успеха, то есть проверял не то. Поймано первым же прогоном.
      final save = src.indexOf('saveSessionForAlwaysOn(configJson, xrayConfigJson)');
      final ok = src.indexOf('            running = true');
      expect(save, greaterThan(0));
      expect(ok, greaterThan(0));
      expect(save, greaterThan(ok),
          reason: 'вызов обязан стоять ПОСЛЕ признака успешного подъёма');
    });

    test('⚠️ отсутствие Xray — тоже состояние, старый файл удаляется', () {
      // Обычный VLESS поднимает только sing-box. Оставленный от прошлой сессии
      // xray.json дал бы на следующей загрузке СБОРНУЮ сессию: туннель ведёт
      // не туда, куда показывает интерфейс.
      expect(src, contains('if (xrayFile.exists()) xrayFile.delete()'),
          reason: 'иначе конфиг Xray переживает сервер, к которому относился');
    });

    test('⚠️ секрет лежит в приватном каталоге приложения', () {
      // Внутри — учётные данные серверов и пароль локального прокси.
      expect(src, contains('filesDir.resolve("always_on")'),
          reason: 'ни кэш, ни общий накопитель для этого не годятся');
    });
  });

  group('Ошибки чтения и записи не роняют сервис', () {
    test('обе операции обёрнуты в runCatching', () {
      // Диск может быть полон, файл — повреждён. Упасть на этом означало бы
      // потерять туннель из-за необязательной подсистемы.
      final save = src.substring(src.indexOf('fun saveSessionForAlwaysOn'));
      expect(save.substring(0, 400), contains('runCatching'));
      final load = src.substring(src.indexOf('fun loadSessionForAlwaysOn'));
      expect(load.substring(0, 400), contains('runCatching'));
    });
  });
  group('Контракт foreground-сервиса соблюдён', () {
    test('⚠️ ГЛАВНОЕ: отказ показывает уведомление ДО stopSelf', () {
      // ⚠️ ПОЙМАНО ПРОГОНОМ НА ЭМУЛЯТОРЕ 18.08.2026, юнит-тесты этого не видели.
      // Система запускает нас через `startForegroundService`, и контракт требует
      // показать уведомление в первые секунды. Ветка отказа звала `stopSelf()`
      // напрямую — Android убивал процесс с `RemoteServiceException:
      // Context.startForegroundService() did not then call
      // Service.startForeground()`. Вместо понятного сообщения пользователь
      // получал падение приложения, причём ровно тогда, когда постоянная VPN
      // включена, а сессии ещё нет: после первой же перезагрузки телефона.
      final branch = src.substring(
        src.indexOf('Сохранённой сессии нет'),
        src.indexOf('return START_NOT_STICKY',
            src.indexOf('Сохранённой сессии нет')),
      );
      expect(branch, contains('startForeground('),
          reason: 'без этого Android убивает процесс, а не показывает отказ');
      final fg = branch.indexOf('startForeground(');
      final stop = branch.indexOf('stopSelf()');
      expect(fg, lessThan(stop),
          reason: 'порядок важен: уведомление обязано успеть ДО остановки');
    });

    test('уведомление снимается вместе с сервисом', () {
      // Висящее «нет сессии» после ухода сервиса — мусор в шторке.
      expect(src, contains('stopForeground(STOP_FOREGROUND_REMOVE)'));
    });

    test('текст отказа переведён во ВСЕ локали', () {
      final dirs = Directory('android/app/src/main/res')
          .listSync()
          .whereType<Directory>()
          // Имя каталога берём из URI: там разделитель всегда `/`,
          // независимо от платформы. Разбор пути по одному символу на
          // Windows возвращал ПОЛНЫЙ путь, фильтр не находил ничего, и
          // тест зеленел бы на пустом списке — то есть не стерёг ничего.
          .where((d) => d.uri.pathSegments
              .where((p) => p.isNotEmpty)
              .last
              .startsWith('values'));
      expect(dirs, isNotEmpty);
      for (final d in dirs) {
        final f = File('${d.path}${Platform.pathSeparator}strings.xml');
        if (!f.existsSync()) continue;
        expect(f.readAsStringSync(), contains('vpn_always_on_no_session'),
            reason: 'локаль ${d.path} осталась без строки — на этом языке в '
                'шторке будет пусто или упадёт поиск ресурса');
      }
    });
  });

}
