/* Снимок ПРАВДЫ из настоящего Windows SDK: раскладка структур WFP и значения GUID.
   Нужен затем, что раскладку x64 нельзя выводить по памяти: ошибка на 4 байта
   сдвигает флаги, и сессия из динамической становится статической. */
#include <initguid.h>
#include <winsock2.h>
#include <windows.h>
#include <fwpmu.h>
#include <stdio.h>
#include <stddef.h>

#define OFF(T, F) printf("  %-28s off=%3zu\n", #F, offsetof(T, F))
#define SZ(T)     printf("%s: sizeof=%zu align=%zu\n", #T, sizeof(T), __alignof(T))
#define G(N)      pg(#N, &N)
#define E(N)      printf("  %-42s = 0x%llX (%llu)\n", #N, (unsigned long long)(N), (unsigned long long)(N))

static void pg(const char* name, const GUID* g) {
  printf("  %-38s 0x%08lX 0x%04X 0x%04X  %02X%02X%02X%02X%02X%02X%02X%02X\n",
    name, (unsigned long)g->Data1, g->Data2, g->Data3,
    g->Data4[0], g->Data4[1], g->Data4[2], g->Data4[3],
    g->Data4[4], g->Data4[5], g->Data4[6], g->Data4[7]);
}

int main(void) {
  printf("=== РАЗМЕРЫ И СМЕЩЕНИЯ (x64) ===\n");
  SZ(GUID);
  SZ(FWPM_DISPLAY_DATA0);
  SZ(FWP_BYTE_BLOB);
  OFF(FWP_BYTE_BLOB, size); OFF(FWP_BYTE_BLOB, data);

  SZ(FWP_VALUE0);
  OFF(FWP_VALUE0, type); OFF(FWP_VALUE0, uint32); OFF(FWP_VALUE0, byteBlob);

  SZ(FWP_CONDITION_VALUE0);
  OFF(FWP_CONDITION_VALUE0, type); OFF(FWP_CONDITION_VALUE0, uint32);
  OFF(FWP_CONDITION_VALUE0, byteBlob); OFF(FWP_CONDITION_VALUE0, v4AddrMask);
  OFF(FWP_CONDITION_VALUE0, v6AddrMask);

  SZ(FWP_V4_ADDR_AND_MASK);
  OFF(FWP_V4_ADDR_AND_MASK, addr); OFF(FWP_V4_ADDR_AND_MASK, mask);
  SZ(FWP_V6_ADDR_AND_MASK);
  OFF(FWP_V6_ADDR_AND_MASK, addr); OFF(FWP_V6_ADDR_AND_MASK, prefixLength);

  SZ(FWPM_ACTION0);
  OFF(FWPM_ACTION0, type); OFF(FWPM_ACTION0, filterType);

  SZ(FWPM_SESSION0);
  OFF(FWPM_SESSION0, sessionKey); OFF(FWPM_SESSION0, displayData);
  OFF(FWPM_SESSION0, flags); OFF(FWPM_SESSION0, txnWaitTimeoutInMSec);
  OFF(FWPM_SESSION0, processId); OFF(FWPM_SESSION0, sid);
  OFF(FWPM_SESSION0, username); OFF(FWPM_SESSION0, kernelMode);

  SZ(FWPM_SUBLAYER0);
  OFF(FWPM_SUBLAYER0, subLayerKey); OFF(FWPM_SUBLAYER0, displayData);
  OFF(FWPM_SUBLAYER0, flags); OFF(FWPM_SUBLAYER0, providerKey);
  OFF(FWPM_SUBLAYER0, providerData); OFF(FWPM_SUBLAYER0, weight);

  SZ(FWPM_FILTER_CONDITION0);
  OFF(FWPM_FILTER_CONDITION0, fieldKey); OFF(FWPM_FILTER_CONDITION0, matchType);
  OFF(FWPM_FILTER_CONDITION0, conditionValue);

  SZ(FWPM_FILTER0);
  OFF(FWPM_FILTER0, filterKey);   OFF(FWPM_FILTER0, displayData);
  OFF(FWPM_FILTER0, flags);       OFF(FWPM_FILTER0, providerKey);
  OFF(FWPM_FILTER0, providerData);OFF(FWPM_FILTER0, layerKey);
  OFF(FWPM_FILTER0, subLayerKey); OFF(FWPM_FILTER0, weight);
  OFF(FWPM_FILTER0, numFilterConditions); OFF(FWPM_FILTER0, filterCondition);
  OFF(FWPM_FILTER0, action);      OFF(FWPM_FILTER0, rawContext);
  OFF(FWPM_FILTER0, providerContextKey);
  OFF(FWPM_FILTER0, reserved);    OFF(FWPM_FILTER0, filterId);
  OFF(FWPM_FILTER0, effectiveWeight);

  printf("\n=== СЛОИ ===\n");
  G(FWPM_LAYER_ALE_AUTH_CONNECT_V4);
  G(FWPM_LAYER_ALE_AUTH_CONNECT_V6);
  G(FWPM_LAYER_ALE_AUTH_RECV_ACCEPT_V4);
  G(FWPM_LAYER_ALE_AUTH_RECV_ACCEPT_V6);
  G(FWPM_LAYER_ALE_AUTH_LISTEN_V4);
  G(FWPM_LAYER_ALE_AUTH_LISTEN_V6);
  G(FWPM_LAYER_OUTBOUND_IPPACKET_V4);
  G(FWPM_LAYER_OUTBOUND_IPPACKET_V6);
  G(FWPM_LAYER_ALE_RESOURCE_ASSIGNMENT_V4);
  G(FWPM_LAYER_ALE_RESOURCE_ASSIGNMENT_V6);

  printf("\n=== УСЛОВИЯ ===\n");
  G(FWPM_CONDITION_ALE_APP_ID);
  G(FWPM_CONDITION_IP_REMOTE_ADDRESS);
  G(FWPM_CONDITION_IP_LOCAL_ADDRESS);
  G(FWPM_CONDITION_IP_LOCAL_INTERFACE);
  G(FWPM_CONDITION_FLAGS);
  G(FWPM_CONDITION_IP_PROTOCOL);
  G(FWPM_CONDITION_IP_REMOTE_PORT);
  G(FWPM_CONDITION_IP_LOCAL_PORT);
  G(FWPM_CONDITION_ALE_USER_ID);

  printf("\n=== ЧИСЛА ===\n");
  E(FWP_ACTION_BLOCK); E(FWP_ACTION_PERMIT);
  E(FWP_MATCH_EQUAL); E(FWP_MATCH_FLAGS_ALL_SET); E(FWP_MATCH_FLAGS_ANY_SET);
  E(FWP_UINT8); E(FWP_UINT16); E(FWP_UINT32); E(FWP_UINT64);
  E(FWP_BYTE_BLOB_TYPE); E(FWP_V4_ADDR_MASK); E(FWP_V6_ADDR_MASK);
  E(FWPM_SESSION_FLAG_DYNAMIC);
  E(FWPM_FILTER_FLAG_PERSISTENT); E(FWPM_FILTER_FLAG_BOOTTIME);
  E(FWPM_FILTER_FLAG_CLEAR_ACTION_RIGHT);
  E(FWP_CONDITION_FLAG_IS_LOOPBACK); E(FWP_CONDITION_FLAG_IS_IPSEC_SECURED);
  E(FWP_CONDITION_FLAG_IS_OUTBOUND_PASS_THRU);
  E(FWP_EMPTY);
  return 0;
}
