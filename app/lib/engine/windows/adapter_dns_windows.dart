import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// Констант этих в пакете win32 5.15 нет, а тянуть их неоткуда — задаём сами.
// Значения зафиксированы в Winsock и не менялись с 90-х.
const int _afUnspec = 0;
const int _afInet = 2;
const int _afInet6 = 23; // на Windows именно 23, не 10 как в Linux
const int _operStatusUp = 1;
const int _skipAnycast = 0x0002;
const int _skipMulticast = 0x0004;
const int _skipFriendlyName = 0x0020;

/// DNS-серверы физических адаптеров — БЕЗ запуска процессов.
///
/// ## Почему не PowerShell
///
/// Раньше адрес брался командой `Get-DnsClientServerAddress`. Это командлет из
/// того же семейства NetTCPIP/CIM, что и `Get-NetAdapter`, который на машине
/// владельца НЕ ВОЗВРАЩАЛСЯ ВООБЩЕ (оборвали на 90 секундах) и уже был отсюда
/// изгнан. Здесь та же мина была прикрыта таймаутом в 5 секунд, поэтому вместо
/// зависания получался молчаливый отказ — в логе «Не удалось определить DNS
/// адаптера», а следом домены, помеченные «Прямо», переставали резолвиться
/// вовсе: запасной путь `local` под поднятым TUN закольцовывается сам на себя.
/// То есть настройка пользователя тихо переставала работать, и понять это по
/// поведению было нельзя. Живой тест в VM это и показал.
///
/// `GetAdaptersAddresses` — тот самый API, из которого командлет и берёт данные,
/// только без WMI, без запуска процессов и без локали.
class AdapterDnsWindows {
  /// Адреса DNS-серверов активных адаптеров, IPv4-первыми.
  ///
  /// Туннельные адаптеры отбрасываются вызывающим кодом по адресу — здесь мы не
  /// знаем, какие адреса «свои».
  static List<String> servers() {
    final out = <String>[];
    // Размер буфера заранее неизвестен: спрашиваем у системы, потом выделяем.
    final sizePtr = calloc<ULONG>();
    Pointer<IP_ADAPTER_ADDRESSES_LH> buf = nullptr;
    try {
      const flags = _skipAnycast | _skipMulticast | _skipFriendlyName;
      var rc = GetAdaptersAddresses(_afUnspec, flags, nullptr, nullptr, sizePtr);
      if (rc != ERROR_BUFFER_OVERFLOW || sizePtr.value == 0) return out;

      buf = calloc<Uint8>(sizePtr.value).cast<IP_ADAPTER_ADDRESSES_LH>();
      rc = GetAdaptersAddresses(_afUnspec, flags, nullptr, buf, sizePtr);
      if (rc != NO_ERROR) return out;

      for (var a = buf; a != nullptr; a = a.ref.Next) {
        // Только работающие адаптеры: у выключенного Wi-Fi адрес DNS остаётся
        // прописанным, и взяв его, мы получили бы резолвер, до которого не
        // достучаться.
        if (a.ref.OperStatus != _operStatusUp) continue;
        for (var d = a.ref.FirstDnsServerAddress; d != nullptr; d = d.ref.Next) {
          final s = _fromSockaddr(d.ref.Address.lpSockaddr.cast<Uint8>());
          if (s != null && !out.contains(s)) out.add(s);
        }
      }
    } catch (_) {
      // Диагностика не имеет права ронять подключение.
    } finally {
      if (buf != nullptr) free(buf);
      free(sizePtr);
    }
    // IPv4 вперёд: наш DNS-транспорт по умолчанию ходит по IPv4, а адрес
    // IPv6-резолвера в конфиге потребовал бы иной формы записи.
    out.sort((a, b) => (a.contains(':') ? 1 : 0) - (b.contains(':') ? 1 : 0));
    return out;
  }

  /// Читаем sockaddr БАЙТАМИ, а не через структуру: у `SOCKADDR` в пакете
  /// расширения `ref` конфликтуют (Struct и Union), и обращение к полю не
  /// компилируется. Раскладка sockaddr зафиксирована и никуда не денется.
  static String? _fromSockaddr(Pointer<Uint8> b) {
    if (b == nullptr) return null;
    final family = b[0] | (b[1] << 8); // sa_family, little-endian
    if (family == _afInet) {
      // Первые 4 байта — семейство и порт; адрес лежит со смещения 4.
      return '${b[4]}.${b[5]}.${b[6]}.${b[7]}';
    }
    if (family == _afInet6) {
      // sockaddr_in6: 2 семейство + 2 порт + 4 flowinfo, адрес со смещения 8.
      final parts = <String>[];
      for (var i = 0; i < 16; i += 2) {
        parts.add(((b[8 + i] << 8) | b[9 + i]).toRadixString(16));
      }
      return parts.join(':');
    }
    return null;
  }
}
