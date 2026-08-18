import 'dart:async';
import 'dart:io';

import '../../../core/platform/app_env.dart';
import '../../../core/platform/app_log.dart';
import '../../../core/platform/app_paths.dart';
import '../../../core/probe/probe_harness.dart';
import '../../../core/xray/harness_config_builder.dart';
import '../xray_paths.dart';
import '../xray_process.dart';

/// Windows-реализация проброс-харнесса: отдельный процесс xray.exe с http-inbound'ами.
/// Не устанавливает системный прокси.
class XrayHarnessWindows implements ProbeHarness {
  /// Отдельный процесс ядра с http-инбаундом: через порт кандидата можно
  /// послать любой запрос, поэтому доступность сервисов тут проверяема.
  @override
  bool get supportsProxyRequests => true;

  final HarnessConfigBuilder builder;

  /// Изолированная копия (SILENTGATE_PORT_OFFSET) занимает свой диапазон портов.
  ///
  /// [secret] — пароль инбаундов. Не передан — генерируется свой на этот
  /// экземпляр, то есть на прогон: харнесс создаётся заново на каждый запуск.
  /// ⚠️ Пароль обязателен: без него порт 21000+ был бы входом в туннель для
  /// любого процесса машины на всё время прогона.
  /// ⚠️ КАЖДОМУ ЭКЗЕМПЛЯРУ — СВОЙ ДИАПАЗОН ПОРТОВ И СВОЙ ФАЙЛ КОНФИГА.
  ///
  /// Найдено ревью 18.08.2026, дефект внесён параллельной автонастройкой
  /// (`autoConfigConcurrency`, умолчание 3). База была КОНСТАНТОЙ, поэтому три
  /// одновременных харнесса просили один и тот же порт 21000 и писали один и
  /// тот же `harness_config.json`. Итог хуже, чем просто отказ: два `xray.exe`
  /// падали на «address already in use», а `_waitReady(21000)` проходил у всех
  /// троих — порт-то слушает ВЫЖИВШИЙ. Дальше пробы уходили на чужое ядро: у
  /// кого пароль не совпал, тот получал 407 и объявлял исправный сервер
  /// нерабочим; у кого совпал — мерил ЧУЖОЙ сервер и записывал результат
  /// своему кандидату. Плюс `stop()` любого из троих гасил единственное живое
  /// ядро посреди чужих проб. То есть список «лучших серверов» собирался из
  /// перепутанных замеров, и включалось это УМОЛЧАНИЕМ.
  ///
  /// ⚠️ Тот же баг уже был оплачен на Android — там его закрывает
  /// `withPortBase` (`harness_config_builder.dart`), но Windows его не звал
  /// нигде. Держим сдвиг здесь, чтобы платформы не разъезжались снова.
  ///
  /// Шаг 16 — с запасом: у харнесса по два порта на запись (socks+http), а
  /// записей в одном прогоне бывает несколько.
  XrayHarnessWindows({HarnessPorts? ports, String? secret})
      : _slot = _nextSlot(),
        builder = HarnessConfigBuilder(
          ports: ports ??
              HarnessPorts(base: 21000 + AppEnv.portOffset + _peekSlot() * 16),
        ).withAuth(harnessProxyUser, secret ?? newHarnessSecret());

  /// Номер экземпляра — разводит и порты, и имя файла конфига.
  final int _slot;

  static int _slotCounter = 0;

  /// Счётчик по кругу: 64 слота с запасом перекрывают потолок
  /// одновременных кандидатов (`AppSettings.autoConfigConcurrencyMax` = 5),
  /// а по кругу — чтобы номера портов не уползали вверх бесконечно.
  static int _nextSlot() => _slotCounter = (_slotCounter + 1) % 64;

  /// Значение, УЖЕ выданное текущему экземпляру.
  ///
  /// ⚠️ Инициализаторы полей считаются в порядке объявления: `_slot` стоит
  /// первым и успевает сдвинуть счётчик, поэтому здесь читаем счётчик КАК ЕСТЬ.
  /// Прибавить единицу — значит развести порт и имя файла на разные слоты:
  /// уникальность сохранится, но соответствие «порт ↔ конфиг» сломается, и
  /// разбираться в этом придётся по чужому логу.
  static int _peekSlot() => _slotCounter;

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    final location = XrayPaths.locate();
    if (location == null) {
      throw StateError('Не найден xray.exe для проброс-харнесса');
    }

    final dir = await AppPaths.supportDir();
    // Имя файла тоже с номером слота: один общий файл переписывался бы гонкой,
    // и ядро читало бы чужой конфиг.
    final file = File(
        '${dir.path}${Platform.pathSeparator}harness_config_$_slot.json');
    await file.writeAsString(builder.buildJson(entries));

    final process = XrayProcess();
    await process.start(
      executable: location.executable,
      configPath: file.path,
      assetDir: location.assetDir,
    );

    await _waitReady(builder.portFor(0));
    return _WindowsHarnessHandle(process, builder);
  }

  /// Сколько ждать, пока ядро харнесса откроет свой первый порт.
  ///
  /// ⚠️ БЫЛО ТРИ СЕКУНДЫ, И ЭТОГО НЕ ХВАТАЛО — А СДАВАЛСЯ ОЖИДАТЕЛЬ МОЛЧА.
  /// Дальше пробы уходили в порт, которого ещё нет, и ВЕСЬ список получал
  /// «n/a» — неотличимое от честного «сервер не проксирует». На машине с
  /// антивирусом (каждый запуск нового exe проверяется), на холодном старте
  /// после установки и просто под нагрузкой — когда рядом идёт пачка проб
  /// сервисов — xray.exe в три секунды не укладывается.
  ///
  /// Пятнадцать секунд ничего не стоят в успешном случае: цикл выходит по
  /// первому же удавшемуся соединению, обычно на первой сотне миллисекунд.
  static const _readyTimeout = Duration(seconds: 15);

  /// Дольше этого — уже не «мгновенно»: пишем в журнал, чтобы разбор
  /// «почему пинг долгий» не начинался с гадания.
  static const _readySlow = Duration(seconds: 3);

  Future<void> _waitReady(int port) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < _readyTimeout) {
      try {
        final s = await Socket.connect('127.0.0.1', port,
            timeout: const Duration(milliseconds: 300));
        s.destroy();
        if (sw.elapsed > _readySlow) {
          AppLog.i('Проброс-харнесс: ядро открыло порт $port за '
              '${sw.elapsedMilliseconds} мс');
        }
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
    // Молчать здесь нельзя: снаружи это выглядит как «все серверы мёртвые», и
    // разбираться человек идёт к серверам, а не к ядру, которое не поднялось.
    AppLog.w('Проброс-харнесс: порт $port не открылся за '
        '${_readyTimeout.inSeconds} с — пробы этого прогона уйдут в никуда, '
        'результаты будут «n/a»');
  }
}

class _WindowsHarnessHandle implements HarnessHandle {
  final XrayProcess _process;
  final HarnessConfigBuilder _builder;
  _WindowsHarnessHandle(this._process, this._builder);

  @override
  int proxyPortFor(int index) => _builder.portFor(index);

  @override
  String get proxyUser => _builder.user;

  @override
  String get proxyPassword => _builder.password;

  /// Windows меряет через прокси-порт — готовой задержки нет.
  @override
  Future<int?> delayMs(int index) async => null;

  @override
  Future<void> stop() async {
    await _process.stop();
    _process.dispose();
  }
}
