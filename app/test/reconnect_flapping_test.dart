import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/settings/app_settings.dart';
import 'package:silentgate/engine/engine_base.dart';
import 'package:silentgate/engine/vpn_engine.dart';

/// ⚠️ ТЕЛЕФОН БЕЗ ИНТЕРНЕТА. РАЗБОР ЖИВОГО ОТЧЁТА ВЛАДЕЛЬЦА (15.08.2026).
///
/// В журнале — один и тот же круг раз в секунду, без конца:
///
/// ```
/// Xray-конфиг: ссылки на гео-базы есть, базы скачаны — отдаю как есть
/// [ERROR] VPN-сервис остановился: Xray не запустился: … routing configuration
/// Ядро не смогло открыть гео-базы… Повторяю без правил по странам
/// Kill switch: ТРАФИК ЗАБЛОКИРОВАН до восстановления связи
/// Автопереподключение: … → попытка 1 через 800 мс      ← ВСЕГДА «попытка 1»
/// Xray-конфиг: ссылки на гео-базы есть, базы скачаны — отдаю как есть  ← опять
/// ```
///
/// ДВЕ ПРИЧИНЫ, И ОБЕ — «ПРИЗНАК ВМЕСТО ФАКТА».
///
/// 1. `markConnected()` обнуляет счётчик попыток в момент ПОДЪЁМА ТУННЕЛЯ, а на
///    Android ядро умирает уже после него. Поэтому предел в восемь попыток не
///    достигался НИКОГДА: каждый круг серия начиналась заново, и приложение
///    не сдавалось и не показывало ошибку — просто держало kill switch.
/// 2. Платформенный предохранитель «гео-базы непригодны» снимался по условию
///    `attempt == 0`, которое из-за (1) было истинным на каждом автоповторе, —
///    то есть конфиг снова собирался с теми самыми базами, на которых ядро
///    падает.
///
/// Ни один из 1412 тестов этого не поймал: оба места по отдельности выглядят
/// разумно, беда рождается только на их стыке.
void main() {
  group('Туннель поднялся и тут же умер', () {
    test('⚠️ ГЛАВНОЕ: серия отказов не начинается заново', () async {
      final e = _FlappingEngine();
      await e.connectWith('{}', _opts(), const []);

      // Пять кругов «поднялся → markConnected → умер через миг».
      for (var i = 0; i < 5; i++) {
        e.markConnected();
        await e.scheduleRetry('ядру недоступны гео-базы');
        e.cancelRetryTimer();
      }

      expect(e.attemptsUsed, greaterThan(1),
          reason: 'ЗДЕСЬ БЫЛ БАГ: счётчик обнулялся подъёмом туннеля, и '
              'приложение крутило цикл вечно, держа трафик заблокированным');
    });

    test('⚠️ без kill switch приложение в конце концов сдаётся и говорит об этом',
        () async {
      final e = _FlappingEngine();
      await e.connectWith('{}', _opts(killSwitch: false), const []);

      var more = true;
      for (var i = 0; i < VpnEngineBase.maxAttempts * 3 && more; i++) {
        e.markConnected();
        more = await e.scheduleRetry('ядру недоступны гео-базы');
        e.cancelRetryTimer();
      }

      expect(more, isFalse,
          reason: 'иначе «Подключение…» крутится вечно и человек не узнаёт '
              'причину — она видна только тому, кто открыл журнал');
    });

    test('⚠️ при kill switch попытки НЕ кончаются — но и не частят', () async {
      // Бесконечные попытки здесь — решение владельца: пока они идут, трафик
      // заблокирован, а прекратить их значило бы выпустить его мимо VPN.
      // Беда была не в бесконечности, а в ЧАСТОТЕ: счётчик обнулялся подъёмом
      // туннеля, пауза откатывалась к 800 мс, и телефон бился раз в секунду
      // сутками. С растущим счётчиком пауза упирается в 20 с и там остаётся.
      final e = _FlappingEngine();
      await e.connectWith('{}', _opts(), const []);

      for (var i = 0; i < VpnEngineBase.maxAttempts + 4; i++) {
        e.markConnected();
        expect(await e.scheduleRetry('ядру недоступны гео-базы'), isTrue,
            reason: 'kill switch держит блокировку до вмешательства человека');
        e.cancelRetryTimer();
      }

      expect(e.attemptsUsed, greaterThan(VpnEngineBase.maxAttempts),
          reason: 'ЗДЕСЬ БЫЛ БАГ: счётчик не рос, пауза не росла, и цикл шёл '
              'раз в секунду без конца');
    });

    test('живая сессия счётчик обнуляет — как и должна', () async {
      // Предохранитель обязан ловить ТОЛЬКО мгновенный развал. Настоящая
      // сессия, продержавшаяся дольше окна, — это успех, и серия отказов после
      // неё считается с нуля.
      final e = _FlappingEngine(upAgo: const Duration(minutes: 5));
      await e.connectWith('{}', _opts(), const []);
      e.markConnected();
      await e.scheduleRetry('обрыв');
      e.cancelRetryTimer();

      expect(e.attemptsUsed, 1, reason: 'после рабочей сессии счёт с начала');
    });
  });

  group('«Свежее подключение» — это команда человека, а не нулевой счётчик', () {
    test('⚠️ ГЛАВНОЕ: автоповтор свежим подключением НЕ считается', () async {
      final e = _FlappingEngine();
      await e.connectWith('{}', _opts(), const []);
      expect(e.freshSeen.last, isTrue, reason: 'кнопка — свежее подключение');

      // Туннель поднялся (счётчик обнулён) и тут же умер → автоповтор.
      e.markConnected();
      expect(e.attemptsUsed, 0, reason: 'предпосылка: подъём обнулил счётчик');
      await e.scheduleRetry('ядру недоступны гео-базы');
      e.cancelRetryTimer();
      await e.startSession();

      expect(e.freshSeen.last, isFalse,
          reason: 'ЗДЕСЬ БЫЛ БАГ: повтор с нулевым счётчиком снимал '
              'платформенный предохранитель и собирал тот же битый конфиг');
    });

    test('новая команда пользователя снова считается свежей', () async {
      // Иначе один отказ ядра выключил бы гео-правила до перезапуска
      // приложения — в том числе после того, как человек перекачал базы.
      final e = _FlappingEngine();
      await e.connectWith('{}', _opts(), const []);
      await e.scheduleRetry('обрыв');
      e.cancelRetryTimer();
      await e.disconnect();

      await e.connectWith('{}', _opts(), const []);
      expect(e.freshSeen.last, isTrue);
    });
  });
}

ConnectionOptions _opts({bool killSwitch = true}) => ConnectionOptions(
      settings: AppSettings(autoReconnect: true, killSwitch: killSwitch),
    );

/// Движок, у которого подъём туннеля ничего не поднимает: нас интересует
/// РЕШЕНИЕ «повторять или сдаться», а не сеть.
class _FlappingEngine extends VpnEngineBase {
  _FlappingEngine({this.upAgo});

  /// Насколько давно «поднялся» туннель — для проверки окна мгновенного развала.
  final Duration? upAgo;

  /// Что видел `startSession` про свежесть подключения на каждом заходе.
  final List<bool> freshSeen = [];

  @override
  Future<void> startSession() async {
    freshSeen.add(isFreshUserConnect);
  }

  @override
  Future<void> platformCleanup() async {}

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {}

  @override
  void markConnected() {
    super.markConnected();
    final ago = upAgo;
    if (ago != null) debugSetLastUp(DateTime.now().subtract(ago));
  }
}
