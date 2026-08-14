import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/core/models/vpn_status.dart';
import 'package:silentgate/core/probe/tunnel_health.dart';
import 'package:silentgate/engine/engine_base.dart';

/// СТОРОЖ КАНАЛА, ВЕРНУВШИЙСЯ ИЗ ДОЛГОЙ ПРОБЫ, НЕ ИМЕЕТ ПРАВА ТРОГАТЬ ЧУЖОГО.
///
/// ⚠️ Что именно стережём. Признав канал мёртвым, сторож делает ещё одну,
/// подтверждающую пробу — до трёх мишеней по 8 секунд, то есть до ~24 секунд.
/// Пользователь, который сам заметил мёртвый интернет, за это время успевает
/// нажать «Отключить» и «Подключить»: туннель поднимается за 3-5 секунд, и у
/// НОВОЙ сессии уже стоит свой сторож.
///
/// Ветка разрыва это учитывала (в ней перепроверяется отмена), а ветка
/// ВОССТАНОВЛЕНИЯ — нет: она безусловно звала `startHealthWatch`.
///
/// ⚠️ ⚠️ ЗАЩИТ ЗДЕСЬ ДВЕ, И ТЕСТЫ РАЗВЕДЕНЫ ПО НИМ ПОИМЁННО. Первая — входной
/// гейт `startHealthWatch` («устаревший вызов не трогает поле»), вторая —
/// перепроверка в самой ветке восстановления. Прошлый заход утверждал, что его
/// тест краснеет от снятия ВТОРОЙ, — проверка опытом это ОПРОВЕРГЛА: при снятой
/// перепроверке сценарий «пользователь переподключился» ловит входной гейт, и
/// тест остаётся зелёным. Поэтому ниже у каждой защиты свой тест, и у каждого в
/// заголовке сказано, снятие ЧЕГО его красит:
///
///  * «устаревший вызов не снимает живого сторожа» — входной гейт;
///  * «канал за время пробы умер…» — перепроверка, условие `!status.isConnected`
///    (единственное реально достижимое сегодня: поколение не меняется);
///  * «у новой сессии уже есть свой сторож…» — перепроверка, условие
///    `!identical(_health, h)`;
///  * «восстановление на подтверждающей пробе…» — инвариант целиком, краснеет
///    только когда сняты ОБЕ защиты.
///
/// Проверять это настоящей пробой нельзя (интервал 45 с, приговор после трёх
/// промахов), поэтому проба подменяется через `createHealthProbe` — те же ветки
/// за миллисекунды.

/// Проба, которой управляет тест: первый такт — промах (канал «умер»),
/// подтверждающая проба висит, пока тест её не отпустит.
class _ScriptedHealth extends TunnelHealth {
  _ScriptedHealth()
      : super(
          proxyPort: 1,
          interval: const Duration(milliseconds: 5),
          failuresToDeclareDown: 1,
        );

  int calls = 0;
  final confirmStarted = Completer<void>();
  final confirmResult = Completer<bool>();

  @override
  Future<bool> probeOnce() {
    calls++;
    if (calls == 1) return Future.value(false); // канал мёртв → onDown
    if (calls == 2) {
      // Та самая долгая подтверждающая проба.
      if (!confirmStarted.isCompleted) confirmStarted.complete();
      return confirmResult.future;
    }
    return Future.value(true);
  }
}

/// Исправный канал: сторож новой сессии, который никто не должен трогать.
class _AliveHealth extends TunnelHealth {
  _AliveHealth()
      : super(
          proxyPort: 2,
          interval: const Duration(milliseconds: 5),
          failuresToDeclareDown: 1,
        );

  @override
  Future<bool> probeOnce() => Future.value(true);
}

class _HealthEngine extends VpnEngineBase {
  final List<TunnelHealth> made = [];
  late TunnelHealth Function() factory;

  @override
  TunnelHealth createHealthProbe({
    required int proxyPort,
    required String proxyUser,
    required String proxyPassword,
  }) {
    final h = factory();
    made.add(h);
    return h;
  }

  @override
  Future<void> startSession() async {}

  @override
  Future<void> teardownCore({bool keepCapture = false}) async {}

  @override
  Future<void> platformCleanup() async {}
}

void main() {
  // ── Входной гейт `startHealthWatch` ───────────────────────────────────────
  test('устаревший вызов не снимает живого сторожа', () {
    final e = _HealthEngine();
    addTearDown(e.stopHealthWatch);
    e.factory = _AliveHealth.new;
    e.setStatus(VpnConnectionState.connected);

    e.startHealthWatch(() => false);
    final live = e.healthWatch;
    expect(live, isNotNull);

    // Запуск, который УЖЕ устарел (поколение сменилось), пытается вооружиться.
    e.startHealthWatch(() => true);

    expect(e.healthWatch, same(live),
        reason: 'сторож живой сессии снят вызовом из мёртвого поколения — '
            'а вооружиться вместо него отменённый уже не может');
  });

  // ── Перепроверка в ветке восстановления: `!status.isConnected` ────────────
  //
  // ⚠️ ЕДИНСТВЕННОЕ УСЛОВИЕ ЭТОЙ ПЕРЕПРОВЕРКИ, ДОСТИЖИМОЕ БЕЗ СМЕНЫ ПОКОЛЕНИЯ.
  // Ядро умирает само (`onCoreDied`), повтор при выключенном автоподключении не
  // планируется — статус уходит в «Ошибка», а поколение растёт только внутри
  // `cleanup()`/нового запуска, то есть ПОСЛЕ. Всё это время `aborted()`
  // отвечает «нет», и входной гейт `startHealthWatch` пропустил бы вызов.
  test('канал за время пробы умер: сторож не вооружается заново на мёртвом порту',
      () async {
    final e = _HealthEngine();
    addTearDown(e.stopHealthWatch);
    final dying = _ScriptedHealth();
    e.factory = () => e.made.isEmpty ? dying : _AliveHealth();
    e.setStatus(VpnConnectionState.connected);

    // Поколение за весь тест не меняется — замыкание отмены всегда «нет».
    e.startHealthWatch(() => false);
    await dying.confirmStarted.future;

    // Пока висела подтверждающая проба, ядро остановилось, и восстановить его
    // не удалось: VPN выключен, локальный порт мёртв.
    e.setStatus(VpnConnectionState.error, message: 'ядро остановилось');

    // Подтверждающая проба всё-таки прошла (мишень ответила через обычную сеть
    // — прокси уже не слушает, но HttpClient успел получить отказ иначе):
    // сторож идёт в ветку восстановления.
    dying.confirmResult.complete(true);
    await pumpEventQueue();

    expect(e.made, hasLength(1),
        reason: 'сторож вооружился ЗАНОВО поверх выключенного VPN: проба раз '
            'в 45 с в мёртвый порт и строка «сторож вооружён» в журнале при '
            'отсутствующем туннеле');
    expect(e.healthWatch, same(dying),
        reason: 'в поле обязан остаться тот же (уже остановленный) сторож');
    expect(dying.isRunning, isFalse,
        reason: 'таймер снят самим TunnelHealth перед onDown и обратно не '
            'заводится');
  });

  // ── Перепроверка в ветке восстановления: `!identical(_health, h)` ─────────
  //
  // ⚠️ ЧЕСТНО О ДОСТИЖИМОСТИ. Оба сегодняшних вызывающих (`windows_engine`,
  // `android_engine`) строят `aborted` от поколения, поэтому в бою вместе со
  // сменой сторожа меняется и ответ `aborted()` — и первым срабатывает входной
  // гейт. Это условие держит запрет «не трогать чужого» НЕЗАВИСИМО от того, как
  // вызывающий собрал своё условие отмены, и тест пиньит именно его: сторожа
  // подменяют при `aborted()`, который так и остался «нет».
  test('у новой сессии уже есть свой сторож — прошлый его не подменяет',
      () async {
    final e = _HealthEngine();
    addTearDown(e.stopHealthWatch);
    final dying = _ScriptedHealth();
    e.factory = () => e.made.isEmpty ? dying : _AliveHealth();
    e.setStatus(VpnConnectionState.connected);

    e.startHealthWatch(() => false);
    await dying.confirmStarted.future;

    // Сторожа вооружила другая сессия — с условием отмены, не завязанным на
    // поколение прошлой.
    e.startHealthWatch(() => false);
    final fresh = e.healthWatch!;
    addTearDown(fresh.stop);
    expect(fresh, isNot(same(dying)), reason: 'предпосылка теста');

    dying.confirmResult.complete(true);
    await pumpEventQueue();

    expect(e.made, hasLength(2),
        reason: 'прошлый сторож снял чужого и завёл ТРЕТЬЕГО вместо него');
    expect(e.healthWatch, same(fresh));
    expect(fresh.isRunning, isTrue,
        reason: 'у новой сессии не осталось сквозной проверки вовсе');
  });

  // ── Инвариант целиком: краснеет только при снятии ОБЕИХ защит ─────────────
  test('восстановление на подтверждающей пробе не глушит сторожа НОВОЙ сессии',
      () async {
    final e = _HealthEngine();
    addTearDown(e.stopHealthWatch);
    final dying = _ScriptedHealth();
    e.factory = () => e.made.isEmpty ? dying : _AliveHealth();
    e.setStatus(VpnConnectionState.connected);

    // Сторож ПРОШЛОЙ сессии: первая же проба промахивается, и он уходит в
    // подтверждающую — ту, что идёт до 24 секунд.
    var staleGen = false;
    e.startHealthWatch(() => staleGen);
    await dying.confirmStarted.future;

    // Пока он там висит, пользователь переподключился: новое поколение и свой
    // сторож. Прошлый `aborted` с этой секунды отвечает «устарел».
    staleGen = true;
    e.startHealthWatch(() => false);
    final fresh = e.healthWatch;
    expect(fresh, isNotNull);
    expect(fresh, isNot(same(dying)));
    addTearDown(fresh!.stop);

    // Подтверждающая проба ПРОШЛА — прошлый сторож идёт в ветку восстановления.
    dying.confirmResult.complete(true);
    await pumpEventQueue();

    expect(e.healthWatch, same(fresh),
        reason: 'сторож прошлой сессии подменил собой сторожа новой');
    expect(fresh.isRunning, isTrue,
        reason: 'у новой сессии не осталось сквозной проверки вовсе — '
            'следующий обрыв снова пройдёт молча');
  });
}
