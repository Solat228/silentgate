import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/tun/app_alive_mutex.dart';

/// «ЖИВ ЛИ ИНТЕРФЕЙС» — ПРЕДОХРАНИТЕЛЬ ПЕРЕД ВКЛЮЧЕНИЕМ KILL SWITCH.
///
/// ⚠️ РАДИ ЧЕГО. Фильтры WFP держит элевейтнутый помощник TUN, и его смерть —
/// штатный сигнал снять блокировку. Но с интерфейсом он не связан ничем:
/// закройте приложение — помощник останется работать, а блокировка стоять, и
/// снять её будет некому. Машина без сети.
///
/// ⚠️ ЧЕГО ЗДЕСЬ ПРОВЕРИТЬ НЕЛЬЗЯ, И ПОЧЕМУ. Положительный случай («владелец
/// жив») в одном процессе не воспроизводится: мьютекс, взятый этим же потоком,
/// захватывается ПОВТОРНО, и `WaitForSingleObject` возвращает `WAIT_OBJECT_0`,
/// а не `WAIT_TIMEOUT`. То есть тест увидел бы «умер» там, где помощник —
/// отдельный процесс — увидит «жив». Врать себе зелёным тестом хуже, чем не
/// иметь его: проверяем то, что проверяется, а остальное — живым прогоном в VM.
void main() {
  group('Имя сессии', () {
    test('⚠️ у каждой сессии своё имя, а не номер процесса', () {
      // Номер процесса Windows переиспользует — помощник начал бы следить за
      // посторонним. Имя случайное и длинное: совпадение исключено на практике.
      final a = AppAliveMutex.tokenForTest();
      final b = AppAliveMutex.tokenForTest();
      expect(a, isNot(b));
      expect(a, startsWith('SilentGateAlive-'));
      expect(a.length, greaterThan('SilentGateAlive-'.length + 20));
    });
  });

  group('⚠️ «Не знаю» ведёт себя как «нельзя»', () {
    test('пустое имя — наблюдения нет', () {
      // Помощник без наблюдения не имеет права поднимать блокировку: снять её
      // будет некому. Поэтому неизвестность обязана давать null, а не объект.
      expect(AppAliveMutex.watch(''), isNull);
    });

    test('несуществующее имя — наблюдения нет', () {
      expect(AppAliveMutex.watch(r'Local\SilentGateAlive-нетакого0000'), isNull,
          reason: 'приложения с таким мьютексом нет — значит его нет вовсе');
    }, skip: !Platform.isWindows);
  });

  group('⚠️ Стражи по исходнику', () {
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join(String.fromCharCode(10));

    test('⚠️ мьютекс НИКОГДА не отпускается', () {
      // Отпущенный мьютекс перестаёт быть признаком жизни: ожидающий тут же
      // получит WAIT_OBJECT_0 и решит, что приложение умерло, — то есть снимет
      // защиту посреди рабочей сессии.
      final s = code('lib/engine/windows/tun/app_alive_mutex.dart');
      expect(s.contains('ReleaseMutex'), isFalse,
          reason: 'признак жизни держится ровно на невозвращённом владении');
      expect(s, contains('_createMutex(nullptr, 1,'),
          reason: 'мьютекс обязан браться ВО ВЛАДЕНИЕ (initialOwner = 1)');
    });

    test('⚠️ помощник выходит, когда интерфейс умер', () {
      final s = code('lib/engine/windows/tun/tun_helper.dart');
      expect(s, contains('alive.appAlive'),
          reason: 'без этой проверки помощник переживает приложение');
      expect(s, contains('AppAliveMutex.watch('));
    });

    test('⚠️ имя передаётся ДО запуска помощника', () {
      // Помощник читает имя один раз, на старте. Положив файл позже, мы
      // получили бы помощника без слежения — ровно того, кто переживёт падение.
      final s = code('lib/engine/windows/tun/singbox_router_windows.dart');
      final acquireAt = s.indexOf('AppAliveMutex.acquire()');
      final launchAt = s.indexOf('TunScheduledTask.exists()');
      expect(acquireAt, greaterThan(0));
      expect(launchAt, greaterThan(acquireAt),
          reason: 'признак жизни обязан лечь на диск раньше запуска');
    });

    test('⚠️ stop-файл больше не стирается в начале попытки', () {
      // Это и была гонка: неудачная комбинация ставит stop-файл, а следующая
      // стирала его раньше, чем помощник успевал прочитать (400 мс опрос против
      // окна в 393–515 мс). Промах = живой помощник, которого не остановить.
      final s = code('lib/engine/windows/tun/singbox_router_windows.dart');
      final waitAt = s.indexOf('waitStopConsumed');
      final clearAt = s.indexOf('clearStopAt');
      expect(waitAt, greaterThan(0), reason: 'ожидание должно появиться');
      expect(clearAt, greaterThan(waitAt),
          reason: 'стирание допустимо только ПОСЛЕ неудачного ожидания');
    });
  });

  group('⚠️ Порядок подъёма блокировки', () {
    /// ⚠️ ЭТИ ИНВАРИАНТЫ ПЕРЕПИСАНЫ 20.08.2026 ПОСЛЕ РАЗБОРА СКЕПТИКАМИ.
    /// Первая редакция поднимала фильтры ПОСЛЕ старта ядра и снимала их по
    /// смерти ядра — то есть защита пропадала ровно в тот момент, ради
    /// которого её и ставили. Прежние стражи это одобряли: они проверяли
    /// порядок, который сам по себе был неверен.
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join(String.fromCharCode(10));

    late String helper;
    setUp(() => helper = code('lib/engine/windows/tun/tun_helper.dart'));

    test('⚠️ базовый набор поднимается ДО запуска ядра', () {
      // Иначе окно «ядро уже работает, адаптера ещё нет» остаётся дырой:
      // трафик в эти секунды идёт мимо VPN под настоящим адресом.
      final engageAt = helper.indexOf('_engageBase(log, alive, configPath)');
      final startAt = helper.indexOf('Process.start(');
      expect(engageAt, greaterThan(0));
      expect(startAt, greaterThan(engageAt),
          reason: 'ядро обязано стартовать ПОСЛЕ подъёма блокировки');
    });

    test('⚠️ kill switch обязан был подняться, но не поднялся — ядро НЕ идёт', () {
      // Туннель, который может течь, при интерфейсе, обещающем защиту, — это
      // исходная жалоба владельца, воспроизведённая своими руками.
      //
      // ⚠️ ГЕЙТ ПЕРЕИМЕНОВАН 23.08.2026, И НЕ РАДИ КРАСОТЫ. Он спрашивал
      // «просили ли блокировку», а спрашивать надо «обязана ли она была
      // подняться»: у неудачи есть безобидный случай — блокировать нечего
      // (режим «только отмеченные» без единой отмеченной программы, либо все
      // отмеченные пропали с диска). На нём прежний гейт запрещал подключение
      // вообще. Подробности и стражи — `kill_switch_missing_app_test.dart`.
      expect(helper, contains('_mustHaveKillSwitch(configPath)'));
      expect(helper.contains('if (hold == null && _wantsKillSwitch(configPath))'),
          isFalse,
          reason: 'вернулся прежний гейт — пустой план снова запретит туннель');
      expect(helper, contains('НЕ ЗАПУСКАЮ ЯДРО'));
    });

    test('⚠️ без связи с интерфейсом блокировка НЕ поднимается', () {
      final body = helper.substring(helper.indexOf('_engageBase('));
      final guardAt = body.indexOf('alive == null');
      final engageAt = body.indexOf('KillSwitchWfp.engage(');
      expect(guardAt, greaterThan(0), reason: 'проверки связи нет вовсе');
      expect(engageAt, greaterThan(guardAt),
          reason: 'подъём обязан стоять ПОСЛЕ проверки связи');
    });

    test('⚠️ СМЕРТЬ ЯДРА НЕ СНИМАЕТ БЛОКИРОВКУ', () {
      // Главная находка разбора. Адаптер исчезает вместе с ядром, маршрут по
      // умолчанию возвращается на физическую сеть — и если бы помощник тут
      // выходил, трафик ушёл бы под реальным адресом. Ровно та жалоба, из-за
      // которой всё затевалось.
      final loop = helper.substring(helper.indexOf('while (true) {'));
      final at = loop.indexOf('if (procExited)');
      expect(at, greaterThan(0));
      final branch = loop.substring(at, at + 220);
      expect(branch, contains('if (hold == null) break'),
          reason: 'выходить по смерти ядра можно ТОЛЬКО когда блокировки нет');
      expect(branch, contains('блокировка ДЕРЖИТСЯ'));
    });

    test('⚠️ правило туннеля дописывается В ЦИКЛЕ, а не отдельным ожиданием', () {
      // Отдельный цикл ожидания LUID (до 15 с) не смотрел ни stop-файл, ни
      // признак жизни — и заново открывал гонку, которую закрыл предыдущий
      // коммит.
      final loop = helper.substring(helper.indexOf('while (true) {'));
      expect(loop, contains('TunLuid.forAlias()'),
          reason: 'LUID обязан спрашиваться внутри общего тика');
      expect(loop, contains('reengage('));
      expect(helper.contains('_waitTunLuid'), isFalse,
          reason: 'отдельного ожидания LUID быть не должно');
    });

    test('⚠️ не удалось разрешить туннель — останавливаемся', () {
      // Базовый набор без правила туннеля душит ровно тот трафик, ради
      // которого VPN включали: человек увидит «Подключено» и мёртвый интернет.
      final loop = helper.substring(helper.indexOf('while (true) {'));
      expect(loop, contains('не удалось разрешить туннель'));
    });

    test('⚠️ блокировка снимается ЯВНО, а не только смертью процесса', () {
      // Между `proc.kill()` и концом процесса помощник живёт секунды, и всё это
      // время блокировка стояла бы уже без туннеля.
      expect(helper, contains('hold.release()'));
    });

    test('⚠️ каталог данных берётся рядом с конфигом, а не свой', () {
      // На учётке с отдельным админом %APPDATA% помощника — чужой (правка #7).
      // Спросив свой каталог, он не нашёл бы ни признака жизни, ни плана.
      expect(helper, contains('static Directory _dataDir(String configPath)'));
      final body = helper.substring(helper.indexOf('_engageBase('));
      expect(body.contains('AppPaths.supportDir()'), isFalse,
          reason: 'подъём блокировки не имеет права смотреть в свой %APPDATA%');
    });

    test('⚠️ токен берётся ДО записи плана, а не после', () {
      // Поймано живым прогоном в VM 20.08.2026. План уносил имя мьютекса, а
      // само имя рождалось позже — в роутере, — то есть в файл уезжала пустая
      // строка. Помощник сверял её с непустым именем из tun_alive и молча
      // отвергал план как чужой: блокировка не поднималась ВООБЩЕ, и ни одной
      // строки в журнале («плана нет» — штатный молчаливый случай).
      final eng = code('lib/engine/windows/windows_engine.dart');
      final acquireAt = eng.indexOf('AppAliveMutex.acquire()');
      final writeAt = eng.indexOf('KillSwitchPlanFile.write(');
      expect(acquireAt, greaterThan(0), reason: 'мьютекс не берётся вовсе');
      expect(writeAt, greaterThan(acquireAt),
          reason: 'план обязан писаться ПОСЛЕ того, как имя появилось');
      expect(eng.contains('sessionToken: AppAliveMutex.name'), isFalse,
          reason: 'читать имя из статики — снова зависеть от порядка вызовов');
    });

    test('план чужой сессии не принимается', () {
      expect(helper, contains('expectToken: _readAliveName(configPath)'));
    });
  });

  group('⚠️ Наблюдение за выбранными именами', () {
    /// ⚠️ ПОЧЕМУ ЭТО СТЕРЕЖЁТСЯ ПО ИСХОДНИКУ, А НЕ ПРОГОНОМ.
    ///
    /// Правило «по имени файла» фильтром WFP стать не может: слой ALE принимает
    /// только идентификатор существующего полного пути. Значит имя — это
    /// ПОДПИСКА, и весь смысл в том, что помощник делает в своём цикле. Поднять
    /// настоящие фильтры в тесте нельзя: они действуют на сеть всей машины, а
    /// тесты идут на машине владельца во время его работы. Проверяем ровно то,
    /// что проверяется без системы, — форму цикла; остальное живой прогон в VM.
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join(String.fromCharCode(10));

    late String helper;
    setUp(() => helper = code('lib/engine/windows/tun/tun_helper.dart'));

    /// Тело цикла — от `while (true)` до явного снятия блокировки, которое
    /// стоит уже ПОСЛЕ него. Без верхней границы в «цикл» попадал бы весь
    /// хвост метода, и проверки «внутри цикла такого нет» ничего не значили бы.
    String loopBody() {
      final start = helper.indexOf('while (true) {');
      final end = helper.indexOf('hold.release()');
      expect(start, greaterThan(0), reason: 'общий цикл пропал');
      expect(end, greaterThan(start), reason: 'снятие обязано быть после цикла');
      return helper.substring(start, end);
    }

    test('⚠️ процессы перечисляются В ЦИКЛЕ, а не один раз на старте', () {
      // Вторую копию той же программы запускают уже после подключения —
      // однократное перечисление на старте не увидит её никогда.
      expect(loopBody(), contains('ProcessListWindows.enumerate()'));
    });

    test('⚠️ план перечитывается и материализуется на каждом проходе', () {
      expect(loopBody(), contains('_freshPlan('),
          reason: 'без свежего плана состав путей застынет на старте');
      final fresh =
          helper.substring(helper.indexOf('static KillSwitchPlan? _freshPlan('));
      expect(fresh, contains('withMaterializedAppPaths('),
          reason: 'имя обязано превращаться в пути живых процессов');
      expect(fresh, contains('withOwnBinaries('),
          reason: 'свои бинари обязаны оставаться разрешёнными и после замены');
    });

    test('⚠️ неизменившийся состав не трогает WFP вовсе', () {
      // Замена набора — транзакция, а тик идёт 2,5 раза в секунду. Без
      // сравнения помощник перекладывал бы фильтры всю сессию подряд.
      final body = loopBody();
      final compareAt = body.indexOf('!_sameApps(wanted, applied)');
      final applyAt = body.indexOf('ok = hold.reengage(');
      expect(compareAt, greaterThan(0), reason: 'сравнения составов нет вовсе');
      expect(applyAt, greaterThan(compareAt),
          reason: 'замена обязана стоять ПОСЛЕ проверки «изменилось ли»');
    });

    test('⚠️ новый путь применяется ЗАМЕНОЙ, без снятия старого набора', () {
      // «Снять, потом поставить» оставило бы окно вообще без блокировки —
      // ровно ту утечку, ради предотвращения которой всё и затевалось.
      final body = loopBody();
      expect(body, contains('hold.reengage('));
      expect(body.contains('release()'), isFalse,
          reason: 'внутри цикла набор не снимают, его ЗАМЕНЯЮТ одной сделкой');
    });

    test('⚠️ снимок применённого состава обновляется только после успеха', () {
      // Иначе первая же неудача навсегда убедила бы помощника, что новый
      // состав уже стоит, и он перестал бы пробовать.
      final body = loopBody();
      final at = body.indexOf('ok = hold.reengage(');
      expect(at, greaterThan(0));
      expect(body.substring(at, at + 120), contains('if (ok) applied = wanted;'));
    });

    test('⚠️ неудачная замена НЕ рвёт цикл и НЕ убивает ядро', () {
      // Прежний набор остаётся рабочим: отказ — повод повторить на следующем
      // проходе, а не повод остаться без защиты или без туннеля.
      final body = loopBody();
      final from = body.indexOf('final reason = msgs.join');
      final to = body.indexOf('if (procExited)');
      expect(from, greaterThan(0), reason: 'причина отказа нигде не называется');
      expect(to, greaterThan(from));
      final branch = body.substring(from, to);
      expect(branch, contains('ДЕРЖИТСЯ'),
          reason: 'журнал обязан сказать, что старая защита осталась');
      expect(branch.contains('break'), isFalse,
          reason: 'отказ замены не имеет права выгонять помощника из цикла');
      expect(branch.contains('proc.kill()'), isFalse,
          reason: 'отказ замены не имеет права убивать ядро');
      expect(branch, contains('lastUpdateFailure'),
          reason: 'одна и та же причина не должна писаться 2,5 раза в секунду');
    });

    test('⚠️ путь, однажды совпавший с именем, из набора не исчезает', () {
      // Программу закрыли и открыли снова — фильтр обязан стоять всё это время,
      // иначе каждый перезапуск открывает окно без защиты. Исчезнувшие с диска
      // пути выбрасывает обычная очистка, отдельного снятия фильтров нет.
      final body = loopBody();
      expect(body, contains('matched[p.path.toLowerCase()] = p'));
      expect(body.contains('matched.clear()'), isFalse);
      expect(body.contains('matched.remove('), isFalse);
    });

    test('⚠️ держатель рождается после старта ядра только через общий подъём',
        () {
      // Единственный законный случай — план «только отмеченные» был пуст,
      // потому что выбранную программу ещё не запустили. Проверка связи с
      // интерфейсом при этом обязана остаться: блокировка, которую некому
      // снять, опаснее её отсутствия.
      final body = loopBody();
      expect(body, contains('_engageLate('));
      expect(body.contains('KillSwitchWfp.engage('), isFalse,
          reason: 'подъём обязан идти через общую проверку связи, а не мимо');
      final raiser = helper
          .substring(helper.indexOf('static KillSwitchHold? _engageLate('));
      expect(raiser, contains('alive == null'),
          reason: 'без связи с интерфейсом нельзя поднимать и через час');
    });

    test('⚠️ за именами следят, только если их выбрали', () {
      // Перечисление процессов не бесплатно, а состав плана за сеанс не
      // меняется: сессии с правилами по полному пути не платят за наблюдение.
      final body = loopBody();
      final gateAt = body.indexOf('watched.isNotEmpty');
      final enumAt = body.indexOf('ProcessListWindows.enumerate()');
      expect(gateAt, greaterThan(0), reason: 'наблюдение включено безусловно');
      expect(enumAt, greaterThan(gateAt),
          reason: 'перечисление обязано стоять ПОД проверкой выбранных имён');
    });
  });
}
