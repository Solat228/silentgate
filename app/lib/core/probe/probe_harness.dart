import '../xray/harness_config_builder.dart';

export '../xray/harness_config_builder.dart' show HarnessEntry, HarnessPorts;

/// Проброс-харнесс: отдельный экземпляр движка (Xray) с http-inbound'ами на 127.0.0.1,
/// по одному на кандидата. Используется для пинга «via Proxy» и проб автонастройки.
/// НИКОГДА не устанавливает системный прокси.
abstract class ProbeHarness {
  /// Запускает харнесс для набора кандидатов. Порядок [entries] задаёт индексы портов.
  Future<HarnessHandle> start(List<HarnessEntry> entries);
}

abstract class HarnessHandle {
  /// Локальный http-прокси порт для кандидата с индексом [index] (0-based).
  ///
  /// **Может вернуть -1**: часть кандидатов обслуживает второе ядро, и если оно
  /// не поднялось, остальные всё равно проверяются. Вызывающий обязан считать
  /// неположительный порт отсутствием прокси, а не портом.
  int proxyPortFor(int index);

  /// Остановить харнесс (убить процесс движка).
  Future<void> stop();
}
