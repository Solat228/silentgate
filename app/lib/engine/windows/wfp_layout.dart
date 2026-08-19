/// РАСКЛАДКА СТРУКТУР WFP И ЗНАЧЕНИЯ КОНСТАНТ — СНЯТЫ С НАСТОЯЩЕГО SDK.
///
/// ⚠️ ЭТИ ЧИСЛА НЕ ВЫВЕДЕНЫ ПО ПАМЯТИ И НЕ ПОДОБРАНЫ. Они напечатаны программой
/// на C, собранной компилятором MSVC против заголовков Windows SDK 10.0.26100.0
/// (`fwpmu.h`, `fwptypes.h`) через `offsetof`/`sizeof`. Причина такой строгости
/// простая: ошибка на четыре байта сдвигает поле `flags` у сессии, сессия из
/// ДИНАМИЧЕСКОЙ становится статической — и фильтры переживают смерть процесса,
/// оставляя машину без интернета. Такую ошибку не видно ни в тестах, ни глазами.
///
/// ⚠️ ТРИ МЕСТА, ГДЕ ИНТУИЦИЯ ОБМАНЫВАЕТ, И ИХ ПРОВЕРИЛ КОМПИЛЯТОР:
///  1. `FWP_V6_ADDR_AND_MASK` — 17 байт с выравниванием 1 (упакованная!), а не
///     24, как получилось бы при «естественном» выравнивании.
///  2. GUID выровнен по 4, а не по 8. Внутри `FWPM_ACTION0` он лежит по
///     смещению 4 — то есть описать GUID полем `Uint64` (как напрашивается)
///     нельзя: Dart выровнял бы его по 8 и разъехался бы с C.
///  3. [filterFlagPersistent] и [sessionFlagDynamic] РАВНЫ ОБА ЕДИНИЦЕ. Это
///     разные поля разных структур, но перепутать их — значит поставить
///     фильтр, переживающий перезагрузку, вместо сессии, умирающей с процессом.
///
/// Проверять при обновлении SDK нечего: раскладка публичных структур WFP
/// заморожена суффиксом `0` в имени (`FWPM_FILTER0`). Новая версия приходит
/// новым типом (`FWPM_FILTER1`…), а не правкой старого.
library;

/// Смещения полей внутри `FWPM_FILTER0` (sizeof = 200, align = 8).
class WfpFilterOffsets {
  static const int size = 200;
  static const int filterKey = 0;
  static const int displayData = 16;
  static const int flags = 32;
  static const int providerKey = 40;
  static const int providerData = 48;
  static const int layerKey = 64;
  static const int subLayerKey = 80;
  static const int weight = 96;
  static const int numFilterConditions = 112;
  static const int filterCondition = 120;
  static const int action = 128;
  static const int rawContext = 152;
  static const int reserved = 168;
  static const int filterId = 176;
  static const int effectiveWeight = 184;
}

/// Смещения внутри `FWPM_FILTER_CONDITION0` (sizeof = 40, align = 8).
class WfpConditionOffsets {
  static const int size = 40;
  static const int fieldKey = 0;
  static const int matchType = 16;
  static const int conditionValue = 24;
}

/// `FWP_VALUE0` и `FWP_CONDITION_VALUE0` совпадают по раскладке: тип по 0,
/// значение (или указатель на него) по 8. Размер 16, выравнивание 8.
class WfpValueOffsets {
  static const int size = 16;
  static const int type = 0;
  static const int value = 8;
}

/// Смещения внутри `FWPM_SESSION0` (sizeof = 72) и `FWPM_SUBLAYER0` (sizeof = 72).
class WfpSessionOffsets {
  static const int size = 72;
  static const int sessionKey = 0;
  static const int displayData = 16;
  static const int flags = 32;
  static const int txnWaitTimeoutInMSec = 36;
  static const int processId = 40;
  static const int sid = 48;
  static const int username = 56;
  static const int kernelMode = 64;
}

class WfpSubLayerOffsets {
  static const int size = 72;
  static const int subLayerKey = 0;
  static const int displayData = 16;
  static const int flags = 32;
  static const int providerKey = 40;
  static const int providerData = 48;
  static const int weight = 64;
}

/// `FWPM_ACTION0`: тип по 0, GUID по 4. Размер 20, ВЫРАВНИВАНИЕ 4.
class WfpActionOffsets {
  static const int size = 20;
  static const int type = 0;
  static const int filterType = 4;
}

/// Числовые константы WFP.
class WfpConst {
  /// ⚠️ Единственный допустимый флаг сессии. Совпадает по значению с
  /// [filterFlagPersistent] — не перепутать: это поля РАЗНЫХ структур.
  static const int sessionFlagDynamic = 0x00000001;

  /// ⚠️ НЕ ИСПОЛЬЗОВАТЬ. Объявлен здесь ровно затем, чтобы страж-тест мог
  /// доказать его отсутствие в боевом коде: фильтр с этим флагом переживает
  /// перезагрузку, а снимать его будет некому — службы у нас нет.
  static const int filterFlagPersistent = 0x00000001;

  static const int actionBlock = 0x1001;
  static const int actionPermit = 0x1002;

  static const int matchEqual = 0;
  static const int matchFlagsAnySet = 7;

  static const int typeUint8 = 1;
  static const int typeUint16 = 2;
  static const int typeUint32 = 3;
  static const int typeUint64 = 4;
  static const int typeByteBlob = 12;
  static const int typeV4AddrMask = 0x100;
  static const int typeV6AddrMask = 0x101;

  static const int conditionFlagIsLoopback = 0x00000001;

  /// Размер `FWP_V4_ADDR_AND_MASK`: адрес + маска, оба в ХОЗЯЙСКОМ порядке байт.
  static const int v4AddrAndMaskSize = 8;

  /// ⚠️ `FWP_V6_ADDR_AND_MASK` УПАКОВАН: 16 байт адреса + 1 байт длины
  /// префикса = 17, выравнивание 1. Ровно то место, где «естественное»
  /// выравнивание дало бы 24 и разъехалось бы с ядром.
  static const int v6AddrAndMaskSize = 17;
}

/// GUID в виде, пригодном для побайтовой записи.
///
/// ⚠️ Не `Uint64` для последних восьми байт: у GUID выравнивание 4, и поле
/// типа `Uint64` заставило бы Dart выровнять структуру по 8 — раскладка
/// разъехалась бы с C ровно там, где GUID стоит по смещению, не кратному 8
/// (например, внутри `FWPM_ACTION0`).
class WfpGuid {
  final int d1;
  final int d2;
  final int d3;
  final List<int> d4;
  const WfpGuid(this.d1, this.d2, this.d3, this.d4);

  @override
  String toString() {
    String hex(int v, int digits) =>
        v.toRadixString(16).toUpperCase().padLeft(digits, '0');
    final tail = d4.map((b) => hex(b, 2)).join();
    return '${hex(d1, 8)}-${hex(d2, 4)}-${hex(d3, 4)}-$tail';
  }
}

/// Слои фильтрации.
///
/// ⚠️ ЧЕТЫРЕ, А НЕ ДВА. Без версий V6 утечка просто уходит по IPv6, и защита
/// становится украшением: у большинства домашних провайдеров IPv6 включён.
class WfpLayers {
  static const aleAuthConnectV4 =
      WfpGuid(0xC38D57D1, 0x05A7, 0x4C33, [0x90, 0x4F, 0x7F, 0xBC, 0xEE, 0xE6, 0x0E, 0x82]);
  static const aleAuthConnectV6 =
      WfpGuid(0x4A72393B, 0x319F, 0x44BC, [0x84, 0xC3, 0xBA, 0x54, 0xDC, 0xB3, 0xB6, 0xB4]);
  static const aleAuthRecvAcceptV4 =
      WfpGuid(0xE1CD9FE7, 0xF4B5, 0x4273, [0x96, 0xC0, 0x59, 0x2E, 0x48, 0x7B, 0x86, 0x50]);
  static const aleAuthRecvAcceptV6 =
      WfpGuid(0xA3B42C97, 0x9F04, 0x4672, [0xB8, 0x7E, 0xCE, 0xE9, 0xC4, 0x83, 0x25, 0x7F]);

  /// Все четыре — обычный набор для правила, не зависящего от семейства.
  static const all = <WfpGuid>[
    aleAuthConnectV4,
    aleAuthConnectV6,
    aleAuthRecvAcceptV4,
    aleAuthRecvAcceptV6,
  ];

  static const v4 = <WfpGuid>[aleAuthConnectV4, aleAuthRecvAcceptV4];
  static const v6 = <WfpGuid>[aleAuthConnectV6, aleAuthRecvAcceptV6];
}

/// Ключи условий.
class WfpConditions {
  static const aleAppId =
      WfpGuid(0xD78E1E87, 0x8644, 0x4EA5, [0x94, 0x37, 0xD8, 0x09, 0xEC, 0xEF, 0xC9, 0x71]);
  static const ipRemoteAddress =
      WfpGuid(0xB235AE9A, 0x1D64, 0x49B8, [0xA4, 0x4C, 0x5F, 0xF3, 0xD9, 0x09, 0x50, 0x45]);
  static const ipLocalInterface =
      WfpGuid(0x4CD62A49, 0x59C3, 0x4969, [0xB7, 0xF3, 0xBD, 0xA5, 0xD3, 0x28, 0x90, 0xA4]);
  static const flags =
      WfpGuid(0x632CE23B, 0x5167, 0x435C, [0x86, 0xD7, 0xE9, 0x03, 0x68, 0x4A, 0xA8, 0x0C]);
  static const ipProtocol =
      WfpGuid(0x3971EF2B, 0x623E, 0x4F9A, [0x8C, 0xB1, 0x6E, 0x79, 0xB8, 0x06, 0xB9, 0xA7]);
  static const ipRemotePort =
      WfpGuid(0xC35A604D, 0xD22B, 0x4E1A, [0x91, 0xB4, 0x68, 0xF6, 0x74, 0xEE, 0x67, 0x4B]);

  /// ⚠️ ЭТО ЖЕ ПОЛЕ ПЕРЕНОСИТ ТИП ICMP. Не совпадение и не догадка: замер
  /// показал, что `FWPM_CONDITION_ICMP_TYPE` и `FWPM_CONDITION_IP_LOCAL_PORT`
  /// — ОДИН И ТОТ ЖЕ GUID (как и `ICMP_CODE` с `IP_REMOTE_PORT`). Так WFP
  /// описывает ICMP: тип кладётся в поле локального порта. Поэтому имя у
  /// константы одно, а смысл — по протоколу в соседнем условии.
  static const ipLocalPortOrIcmpType =
      WfpGuid(0x0C1BA1AF, 0x5765, 0x453F, [0xAF, 0x22, 0xA8, 0xF7, 0x91, 0xAC, 0x77, 0x5B]);
}

/// Номера протоколов, которые нам нужны.
class IpProto {
  static const int tcp = 6;
  static const int udp = 17;
  static const int icmpV6 = 58;
}
