import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/engine/windows/wfp_layout.dart';

/// РАСКЛАДКА СТРУКТУР WFP — СВЕРКА С ЗАМЕРОМ КОМПИЛЯТОРА.
///
/// ⚠️ ЗАЧЕМ ТЕСТ, ЕСЛИ ЭТО ПРОСТО КОНСТАНТЫ. Затем, что цена ошибки здесь —
/// не красная строчка, а машина владельца без интернета. Смещение поля `flags`
/// в `FWPM_SESSION0`, съехавшее на четыре байта, превращает ДИНАМИЧЕСКУЮ сессию
/// в статическую: её фильтры переживают смерть процесса, и снять их будет
/// нечем. Ни компилятор, ни анализатор, ни живой прогон этого не покажут —
/// поведение расходится только в аварии.
///
/// ⚠️ ЧИСЛА НИЖЕ — ВТОРАЯ, НЕЗАВИСИМАЯ КОПИЯ. Они переписаны из вывода
/// `tools/wfp/wfp_layout_probe.c`, собранного MSVC против настоящих заголовков
/// Windows SDK 10.0.26100.0. Смысл дублирования именно в этом: правка
/// константы «чтобы совпало» тут же красит тест, потому что таблица
/// происходит не из того же файла, а из замера.
void main() {
  group('FWPM_FILTER0 — 200 байт', () {
    test('смещения полей совпадают с замером SDK', () {
      expect(WfpFilterOffsets.size, 200);
      expect(WfpFilterOffsets.filterKey, 0);
      expect(WfpFilterOffsets.displayData, 16);
      expect(WfpFilterOffsets.flags, 32);
      expect(WfpFilterOffsets.providerKey, 40);
      expect(WfpFilterOffsets.providerData, 48);
      expect(WfpFilterOffsets.layerKey, 64);
      expect(WfpFilterOffsets.subLayerKey, 80);
      expect(WfpFilterOffsets.weight, 96);
      expect(WfpFilterOffsets.numFilterConditions, 112);
      expect(WfpFilterOffsets.filterCondition, 120);
      expect(WfpFilterOffsets.action, 128);
      expect(WfpFilterOffsets.rawContext, 152);
      expect(WfpFilterOffsets.reserved, 168);
      expect(WfpFilterOffsets.filterId, 176);
      expect(WfpFilterOffsets.effectiveWeight, 184);
    });

    test('⚠️ action лежит по 128 и занимает 20 байт, а не 24', () {
      // GUID выровнен по 4, поэтому `FWPM_ACTION0` = 4 + 16 = 20, и следующее
      // поле начинается с выравниванием по 8 — то есть со 152, а не со 148.
      expect(WfpActionOffsets.size, 20);
      expect(WfpActionOffsets.type, 0);
      expect(WfpActionOffsets.filterType, 4);
      expect(WfpFilterOffsets.action + WfpActionOffsets.size, 148);
      expect(WfpFilterOffsets.rawContext, 152,
          reason: 'между action и rawContext обязаны быть 4 байта выравнивания');
    });
  });

  group('Прочие структуры', () {
    test('FWPM_FILTER_CONDITION0 — 40 байт', () {
      expect(WfpConditionOffsets.size, 40);
      expect(WfpConditionOffsets.fieldKey, 0);
      expect(WfpConditionOffsets.matchType, 16);
      expect(WfpConditionOffsets.conditionValue, 24);
    });

    test('FWP_VALUE0 и FWP_CONDITION_VALUE0 — 16 байт, значение по 8', () {
      expect(WfpValueOffsets.size, 16);
      expect(WfpValueOffsets.type, 0);
      expect(WfpValueOffsets.value, 8);
    });

    test('⚠️ FWPM_SESSION0: flags по 32 — от этого зависит динамичность', () {
      expect(WfpSessionOffsets.size, 72);
      expect(WfpSessionOffsets.sessionKey, 0);
      expect(WfpSessionOffsets.displayData, 16);
      expect(WfpSessionOffsets.flags, 32);
      expect(WfpSessionOffsets.txnWaitTimeoutInMSec, 36);
      expect(WfpSessionOffsets.processId, 40);
      expect(WfpSessionOffsets.sid, 48);
      expect(WfpSessionOffsets.username, 56);
      expect(WfpSessionOffsets.kernelMode, 64);
    });

    test('FWPM_SUBLAYER0 — 72 байта, вес по 64', () {
      expect(WfpSubLayerOffsets.size, 72);
      expect(WfpSubLayerOffsets.subLayerKey, 0);
      expect(WfpSubLayerOffsets.displayData, 16);
      expect(WfpSubLayerOffsets.flags, 32);
      expect(WfpSubLayerOffsets.providerKey, 40);
      expect(WfpSubLayerOffsets.providerData, 48);
      expect(WfpSubLayerOffsets.weight, 64);
    });

    test('⚠️ FWP_V6_ADDR_AND_MASK УПАКОВАН: 17 байт, а не 24', () {
      // 16 байт адреса + 1 байт длины префикса, выравнивание 1. При
      // «естественном» выравнивании вышло бы 24, и ядро прочитало бы мусор.
      expect(WfpConst.v6AddrAndMaskSize, 17);
      expect(WfpConst.v4AddrAndMaskSize, 8);
    });
  });

  group('⚠️ Числа, которые легко перепутать', () {
    test('флаг динамической сессии и флаг постоянного фильтра равны оба', () {
      // Это не опечатка и не ошибка — это ловушка в самом API: одно и то же
      // значение 1 означает «умереть вместе с процессом» у сессии и «пережить
      // перезагрузку» у фильтра. Тест стоит здесь, чтобы никто не «исправил»
      // одно число по другому.
      expect(WfpConst.sessionFlagDynamic, 0x00000001);
      expect(WfpConst.filterFlagPersistent, 0x00000001);
    });

    test('действия и типы значений', () {
      expect(WfpConst.actionBlock, 0x1001);
      expect(WfpConst.actionPermit, 0x1002);
      expect(WfpConst.matchEqual, 0);
      expect(WfpConst.matchFlagsAnySet, 7);
      expect(WfpConst.typeUint8, 1);
      expect(WfpConst.typeUint32, 3);
      expect(WfpConst.typeUint64, 4);
      expect(WfpConst.typeByteBlob, 12);
      expect(WfpConst.typeV4AddrMask, 0x100);
      expect(WfpConst.typeV6AddrMask, 0x101);
      expect(WfpConst.conditionFlagIsLoopback, 0x00000001);
    });
  });

  group('GUID слоёв и условий', () {
    test('⚠️ слоёв ЧЕТЫРЕ: без V6 утечка уходит по IPv6', () {
      expect(WfpLayers.all.length, 4);
      expect(WfpLayers.v4.length, 2);
      expect(WfpLayers.v6.length, 2);
      // Наборы не пересекаются и вместе дают полный список.
      final names = WfpLayers.all.map((g) => g.toString()).toSet();
      expect(names.length, 4, reason: 'дубликат слоя — правило встанет дважды');
    });

    test('значения GUID совпадают с замером SDK', () {
      expect(WfpLayers.aleAuthConnectV4.toString(),
          'C38D57D1-05A7-4C33-904F7FBCEEE60E82');
      expect(WfpLayers.aleAuthConnectV6.toString(),
          '4A72393B-319F-44BC-84C3BA54DCB3B6B4');
      expect(WfpLayers.aleAuthRecvAcceptV4.toString(),
          'E1CD9FE7-F4B5-4273-96C0592E487B8650');
      expect(WfpLayers.aleAuthRecvAcceptV6.toString(),
          'A3B42C97-9F04-4672-B87ECEE9C483257F');
      expect(WfpConditions.aleAppId.toString(),
          'D78E1E87-8644-4EA5-9437D809ECEFC971');
      expect(WfpConditions.ipRemoteAddress.toString(),
          'B235AE9A-1D64-49B8-A44C5FF3D9095045');
      expect(WfpConditions.ipLocalInterface.toString(),
          '4CD62A49-59C3-4969-B7F3BDA5D32890A4');
      expect(WfpConditions.flags.toString(),
          '632CE23B-5167-435C-86D7E903684AA80C');
    });
  });
}
