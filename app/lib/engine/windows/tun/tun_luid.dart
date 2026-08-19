import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// LUID СЕТЕВОГО ИНТЕРФЕЙСА ПО ЕГО ИМЕНИ.
///
/// ⚠️ ЗАЧЕМ. Правило kill switch «пропускать всё, что идёт в туннель» опирается
/// на условие `FWPM_CONDITION_IP_LOCAL_INTERFACE`, а оно принимает именно LUID —
/// не имя и не индекс. Без этого правила блокировка режет и сам VPN: трафик
/// приложений уходит В адаптер туннеля, и туннель — тоже интерфейс.
///
/// ⚠️ ПОЧЕМУ ОТДЕЛЬНЫЙ ВЫЗОВ, А НЕ `NetworkInterface.list()`. Dart отдаёт имя и
/// адреса, но не LUID — его нет в модели `dart:io` вовсе. Взять неоткуда, кроме
/// как у Windows.
///
/// ⚠️ ЗАЧЕМ ЭТО ПОМОЩНИКУ, А НЕ ИНТЕРФЕЙСУ. Адаптера в момент подъёма
/// блокировки ещё НЕ СУЩЕСТВУЕТ: его создаёт ядро, которое запускает сам
/// помощник. Значит и спрашивать LUID должен он, уже после того, как адаптер
/// появился, — и заменять набор правил на месте. Передать LUID из приложения
/// нельзя: там его тоже нет, пока туннель не поднялся.
abstract final class TunLuid {
  /// Имя нашего адаптера — то же, что уходит в конфиг sing-box
  /// (`interface_name` в TUN-инбаунде). Строка ASCII: локаль не мешает.
  static const adapterAlias = 'silentgate-tun';

  /// LUID интерфейса по имени; `null` — интерфейса нет или спросить не вышло.
  ///
  /// ⚠️ `null` ОБЯЗАН ТРАКТОВАТЬСЯ КАК «НЕЛЬЗЯ ПОДНИМАТЬ БЛОКИРОВКУ», а не как
  /// «поднимем без этого правила». Блокировка без разрешения для туннеля
  /// закрывает ровно тот трафик, ради которого VPN и включали.
  static int? forAlias([String alias = adapterAlias]) {
    if (!Platform.isWindows) return null;
    final arena = Arena();
    try {
      final out = arena<Uint64>();
      final rc = _convert(alias.toNativeUtf16(allocator: arena), out);
      // NO_ERROR == 0. Любой другой код — интерфейса нет либо имя не то.
      return rc == 0 ? out.value : null;
    } catch (_) {
      return null;
    } finally {
      arena.releaseAll();
    }
  }

  static final DynamicLibrary _iphlp = DynamicLibrary.open('iphlpapi.dll');

  /// `ConvertInterfaceAliasToLuid(alias, &luid)`.
  ///
  /// ⚠️ NET_LUID — объединение размером ровно 8 байт, поэтому принимающая
  /// сторона описана как `Uint64`. Ошибка в размере здесь дала бы правилу
  /// мусорный интерфейс: конфиг ядро примет, а пропускать будет не то.
  static final _convert = _iphlp.lookupFunction<
      Uint32 Function(Pointer<Utf16>, Pointer<Uint64>),
      int Function(Pointer<Utf16>,
          Pointer<Uint64>)>('ConvertInterfaceAliasToLuid');
}
