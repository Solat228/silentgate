import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/platform/app_log.dart';
import '../../core/platform/app_paths.dart';
import '../../core/probe/probe_harness.dart';
import '../../core/xray/harness_config_builder.dart';

/// Проброс-харнесс Android: замер идёт ОТДЕЛЬНЫМ экземпляром Xray внутри
/// нашего же процесса.
///
/// ⚠️ Долго считалось, что харнесса на Android быть не может: «VpnService в
/// приложении один». Это верно для ТУННЕЛЯ, но не для замера — `LibXray.ping`
/// поднимает свой `core.New` и гасит его сразу после измерения, не трогая
/// глобальный инстанс, занятый живым туннелем. Из-за неверного вывода
/// hysteria2 и панельные профили «Авто» не пингуались вообще: TCP у них нет
/// (QUIC / балансировщик по десяткам узлов), а вторая фаза требовала харнесса.
///
/// Конфиг собирает тот же [HarnessConfigBuilder], что и на Windows, — включая
/// ветку полного конфига (профиль «Авто» со своим балансировщиком).
class ProbeHarnessAndroid implements ProbeHarness {
  static const _channel = MethodChannel('lol.silentgate/probe');

  @override
  Future<HarnessHandle> start(List<HarnessEntry> entries) async {
    final dir = await AppPaths.supportDir();
    final files = <String?>[];
    // По файлу на кандидата: `ping` принимает ПУТЬ к конфигу, а не JSON.
    for (var i = 0; i < entries.length; i++) {
      // ⚠️ libXray — это Xray, а он не умеет hysteria2 (QUIC + свой congestion
      // control). Собрать для него конфиг нельзя, и попытка замера пометила бы
      // рабочий сервер мёртвым. Такие кандидаты просто не меряются: их
      // состояние честно остаётся «не проверен», а по живому каналу
      // проверяется активный (см. ProbeController).
      if (entries[i].server.protocol == 'hysteria2') {
        files.add(null);
        continue;
      }
      // По одному кандидату на конфиг: `ping` меряет ОДИН outbound, а общий
      // харнесс Windows держит их пачкой на разных портах.
      final json = HarnessConfigBuilder(ports: const HarnessPorts())
          .buildJson([entries[i]]);
      final f = File('${dir.path}${Platform.pathSeparator}probe_$i.json');
      await f.writeAsString(json);
      files.add(f.path);
    }
    return _AndroidHandle(files);
  }
}

class _AndroidHandle implements HarnessHandle {
  _AndroidHandle(this._files);

  final List<String?> _files;

  /// Порта нет: замер делает нативная сторона целиком, наружу отдаётся сразу
  /// задержка. 0 означает «через порт не ходить» — вызывающий обязан это
  /// учитывать (см. [delayMs]).
  @override
  int proxyPortFor(int index) => 0;

  /// Задержка кандидата в миллисекундах; `null` — не отвечает.
  @override
  Future<int?> delayMs(int index, {int timeoutSec = 5}) async {
    if (index < 0 || index >= _files.length) return null;
    final path = _files[index];
    if (path == null) return null; // hysteria2 — Xray его не поднимет
    try {
      final v = await ProbeHarnessAndroid._channel.invokeMethod<int>('ping', {
        'configPath': path,
        'timeout': timeoutSec,
      });
      return (v == null || v <= 0) ? null : v;
    } catch (e) {
      AppLog.w('Замер через libXray не удался: $e');
      return null;
    }
  }

  @override
  Future<void> stop() async {
    // Экземпляр ядра гасит сама нативная сторона (defer в libXray); нам
    // остаётся убрать временные конфиги, иначе они копятся в каталоге данных.
    for (final p in _files) {
      if (p == null) continue;
      try {
        await File(p).delete();
      } catch (_) {}
    }
  }
}
