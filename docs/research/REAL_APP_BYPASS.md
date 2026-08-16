# Настоящий обход туннеля по имени программы на Windows

**Файл:** `docs/research/REAL_APP_BYPASS.md`
**Дата разбора:** 17.08.2026
**Стенд разбора:** хост владельца, Windows 11 24H2, сборка **10.0.26100**, `fwpuclnt.dll` **10.0.26100.1** (544 768 байт), SDK/WDK 10.0.26100.0, VS2022 Community 14.44.35207.
**Связанные записи:** `docs/BACKLOG.md` #21 (решение 04.08.2026), CLAUDE.md §1.1.0 (TUN и «Прямо»), память `windows-dns-belongs-to-svchost`, `docs/research/VPN_DETECTION.md`.
**Статус:** расследование закончено, кода не написано, ни один файл проекта не изменён.

---

## 1. Прямой ответ владельцу

**Доказанного способа увести приложение мимо туннеля по имени программы, без драйвера режима ядра, на сегодня НЕТ.** Ни один из восьми проверенных VPN-клиентов такого способа не нашёл: у всех шести, кто умеет настоящий per-app split на Windows, это .sys. Два оставшихся не умеют вовсе.

Утверждение, которое просили перепроверить, — **подтвердилось буквально**: перенаправление сокета на слоях `ALE_BIND_REDIRECT` / `ALE_CONNECT_REDIRECT` доступно только драйверу. Строчку в BACKLOG #21 править как ошибочную не нужно.

Но **следствие из неё («значит, без .sys нельзя») перестало быть железным**. Microsoft добавила отдельный, не связанный с redirect-слоями механизм: пользовательскую функцию **`FwpmConnectionPolicyAdd0`** из `fwpuclnt.dll` и слой `FWPM_LAYER_OUTBOUND_NETWORK_CONNECTION_POLICY_V4/V6`. Она сопоставляет соединения по пути к exe (`FWPM_CONDITION_ALE_APP_ID`) и назначает им выходной интерфейс, адрес источника и шлюз — Microsoft дословно называет это «process-based routing». **Функция физически есть и живая** на этой машине (проверено экспортом, GetProcAddress и дизассемблером — не заглушка, а настоящий RPC в BFE), ядерная часть слоя тоже на месте (встроенные коллауты найдены в `tcpip.sys` и `fwpkclnt.sys`), сторонний драйвер не требуется.

Почему это всё равно не ответ «делаем»:

1. **Никто в мире этим не пользуется.** Скан всей `C:\Windows\System32` нашёл строку `FwpmConnectionPolicyAdd0` **только в самой `fwpuclnt.dll`** — ни один встроенный компонент Windows её не импортирует. Ни одного VPN-клиента, ни одного примера кода, ни одного образца в WDK. Страница описания настроек у Microsoft — заглушка «TBD».
2. **Главного никто не проверял, и мы тоже.** Что политика перебивает наш `auto_route 0.0.0.0/0` с метрикой 0 — это **вывод по смыслу, а не факт**. Документация нигде не обещает приоритет над таблицей маршрутов.
3. **Пол по версии ОС не объявлен Microsoft вовсе**, а по заголовку он выше Windows 10. Обещать возможность всем пользователям нельзя.
4. **Нужен администратор на каждую правку**, а не разово: политика привязана к LUID и адресу физического адаптера и переписывается при каждой смене сети и правке списка.
5. **DNS этим не закрывается ни при каком исходе** — на Windows запрос принадлежит `svchost.exe`, а не приложению.

**Практический вывод: решение #21 «не делаем» остаётся в силе.** Формулировку посылки надо уточнить (см. §7), потому что она стала неточной, но вывод от этого не меняется — он теперь опирается не на «технически невозможно», а на «есть ровно один необкатанный кандидат, требующий админа, живущий не на всех Windows и не проверенный никем». Цена входа — один опыт в VM на 200 строк (§9.2). До этого опыта единственный доказанный рычаг — деление по адресу (`route_address` / маршруты-исключения).

---

## 2. Что проверено ЗАПУСКОМ

Всё ниже — результат исполнения команд, а не чтения. На хосте выполнялись **только читающие** операции: ни одного WFP-объекта не добавлено, VPN не включался, процессы владельца не трогались.

| # | Факт | Чем проверено |
|---|---|---|
| 1 | `fwpuclnt.dll` экспортирует `FwpmConnectionPolicyAdd0` (ordinal 34, hint 0x21, RVA 0x00013810) и `FwpmConnectionPolicyDeleteByKey0` (ordinal 35, RVA 0x00013990); рядом `FwpmGetAppIdFromFileName0` (ordinal 42) | `dumpbin /EXPORTS C:\Windows\System32\fwpuclnt.dll`, воспроизведено двумя независимыми прогонами |
| 2 | Это не пустое объявление: по 0x180013810 — пролог, проверка `engineHandle` (NULL → `0x8032001C`), настоящий вызов через IAT | `dumpbin /disasm` |
| 3 | Функция резолвится в рантайме из **неэлевейтнутого** x64-процесса | `LoadLibrary` + `GetProcAddress` → адрес получен |
| 4 | Построение `ALE_APP_ID` — юзермод и **без прав**: `FwpmGetAppIdFromFileName0("C:\Windows\System32\notepad.exe")` вернул 0 | прямой вызов из обычной учётки |
| 5 | Слой `FWPM_LAYER_OUTBOUND_NETWORK_CONNECTION_POLICY_V4` (`037f317a-d696-494a-bba5-bffc265e6052`) и V6 **существуют в живом BFE** | оракул `FwpmLayerGetByKey0`: существующий объект даёт `ERROR_ACCESS_DENIED` (5), несуществующий — `FWP_E_LAYER_NOT_FOUND` (0x80320004). Калибровка на 4 заведомо живых слоя и 3 выдуманных GUID, включая «почти такой же» с отличием в один байт |
| 6 | **Ядерная часть слоя штатная**: GUID встроенных коллаутов `103090d4-8e28-4fd6-9894-d1d67d6b10c9` и `4ed3446d-8dc7-459b-b09f-c1cb7a8f8689` найдены в `C:\Windows\System32\drivers\tcpip.sys` (10.0.26100.857) и `fwpkclnt.sys` (10.0.26100.268) | побайтовый поиск сигнатур |
| 7 | Рантайм-id слоя внутри живого диапазона: `FwpmLayerGetById0` даёт существующие 0…98, 99 отсутствует; `fwpsu.h:177` помечает `FWPS_LAYER_OUTBOUND_NETWORK_CONNECTION_POLICY_V4` как **85** | перебор + чтение SDK |
| 8 | **Добавление политики требует администратора.** Из обычной учётки: `FwpmConnectionPolicyAdd0` → **5 (ERROR_ACCESS_DENIED)**, контрольный `FwpmProviderAdd0` → тоже 5 | прямой вызов. Код 5, а не «не поддерживается» — значит операция реализована и упёрлась ровно в проверку доступа |
| 9 | **Ни один встроенный компонент Windows этим API не пользуется**: строка `FwpmConnectionPolicyAdd0` найдена только в самой `FWPUCLNT.DLL` | скан `System32\*.dll` и `*.exe` (~89 с) |
| 10 | Гейт заголовка: `um\fwpmu.h:5379–5399` — `#if (NTDDI_VERSION >= NTDDI_WIN11_ZN)`, тот же гейт в `km\fwpmk.h:5186` и `shared\fwpvi.h:677` | чтение SDK 10.0.26100.0 (перепроверено мной при подготовке этого документа) |
| 11 | `NTDDI_WIN11_ZN` = 0x0A00000E, `NTDDI_WIN11_GE` (24H2) = 0x0A000010 — **гейт НИЖЕ 24H2**, то есть настоящий пол по заголовку неизвестен | `shared\sdkddkver.h:160–166` |
| 12 | SDK Windows 10 RTM (`Include\10.0.10240.0`) не содержит **ни одного** вхождения `ConnectionPolicy` и не знает `NTDDI_WIN11_ZN` | grep по дереву |
| 13 | **Redirect из юзермода недоступен физически**: в `fwpuclnt.dll` ноль совпадений по «redirect», `FwpsCalloutRegister*` нет; `um\fwpsu.h` объявляет всего 7 функций (`FwpsOpenToken0`, `FwpsAleEndpoint*`), вся цепочка `FwpsRedirectHandleCreate0` / `FwpsAcquireWritableLayerDataPointer0` / `FwpsApplyModifiedLayerData0` — только в `km\fwpsk.h` | `dumpbin /exports` + чтение SDK/WDK |
| 14 | Mullvad делает split ровно на этих слоях: grep по `src/firewall/*.cpp` даёт `FWPM_LAYER_ALE_BIND_REDIRECT_V4/V6`, `ALE_CONNECT_REDIRECT_V4/V6`, плюс `ALE_AUTH_CONNECT`, `ALE_AUTH_RECV_ACCEPT` | чтение клона `mullvad/win-split-tunnel`, 17.08.2026 |
| 15 | Объём драйвера **измерен, а не прикинут**: `src/` — 13 968 строк C/C++ (`ioctl.cpp` 1741, `firewall/firewall.cpp` 1710, `firewall/callouts.cpp` 1519, `firewall/appfilters.cpp` 1202, `driverentry.cpp` 754); `leaktest/` — 3 229; `testing/` — 1 481 (пример агента, README: «mostly useful for manual testing»). Живой: последний коммит 25.03.2026, версия 1.3.0.0 | подсчёт по клону |
| 16 | Лицензия Mullvad — GPL-3.0-or-later **ИЛИ** MPL-2.0, с нашей GPL-3.0 совместимо | чтение `LICENSE-GPL.md` / `LICENSE-MPL.txt` |

### ⚠️ Аномалия, которую не удалось объяснить

Два независимых прогона `FwpmEngineOpen0` из обычной (не админ) учётки на **одной и той же** машине дали разное:

* прогон А (PowerShell 5.1, P/Invoke, `RPC_C_AUTHN_WINNT`, `FWPM_SESSION_FLAG_DYNAMIC`) → **0, успех**, сессия открылась;
* прогон Б (`authnService` = 0 / 10 / 0xFFFFFFFF, в том числе с отключённой песочницей) → **50 = ERROR_NOT_SUPPORTED**, одинаково во всех вариантах, при работающей службе BFE.

Причина не установлена. Практический смысл: **без открытой сессии движка `FwpmConnectionPolicyAdd0` вызвать нельзя вообще**, и до опыта в VM надо разобраться, от чего зависит открытие. Скорее всего дело в параметрах вызова (`authnService`, структура `FWPM_SESSION0`), а не в самой ОС, — но это догадка.

---

## 3. Что известно ТОЛЬКО по документации

Ни одно утверждение этого раздела не проверено запуском. Разделение принципиально: путать эти два списка — тот самый способ, которым в проект уже попадали неверные записи.

**Про `FwpmConnectionPolicyAdd0`** (learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmconnectionpolicyadd0, ms.date 29.04.2024):

* назначение — «allows you to configure more expressive routing policies for outbound connections, and thereby to enable more complex scenarios such as source address-based routing, **process-based routing**, port-based routing»;
* допустимые условия: `FWPM_CONDITION_ALE_APP_ID`, `ALE_ORIGINAL_APP_ID`, `ALE_USER_ID`, `ALE_PACKAGE_ID`, `IP_PROTOCOL`, `IP_REMOTE_ADDRESS/PORT`, `IP_LOCAL_ADDRESS/PORT`, `FLAGS`, `COMPARTMENT_ID`;
* настройки маршрута (`FWP_NETWORK_CONNECTION_POLICY_SETTING_TYPE`, `shared\fwptypes.h:263-269`): `SOURCE_ADDRESS`, `NEXT_HOP_INTERFACE` («The LUID of the outgoing interface to use for the connection», `FWP_UINT64`), `NEXT_HOP`;
* политики взвешенные, «a higher weight takes precedence»;
* требования: header `fwpmu.h`, **DLL `Fwpuclnt.dll`** — ни слова о драйвере;
* ⚠️ **поля «Minimum supported client/server» в таблице Requirements ПУСТЫЕ** — Microsoft не заявила ни одной поддерживаемой версии;
* ⚠️ страница enum-а `FWP_NETWORK_CONNECTION_POLICY_SETTING_TYPE` (ne-fwptypes-…, ms.date 03.05.2026) описана буквально «TBD», включая все четыре константы;
* ⚠️ **документация Microsoft противоречит сама себе**: DDI-страница `FwpmConnectionPolicyDeleteByKey0` (fwpmk) заявляет «Minimum supported client: Available starting with Windows Vista» при гейте `NTDDI_WIN11_ZN` в заголовке.

**Чего документация НЕ говорит и что поэтому остаётся недоказанным:**

* что политика перебивает таблицу маршрутов, в том числе `0.0.0.0/0` с метрикой 0 на TUN-адаптере;
* как она ведёт себя для бесконнектного UDP/QUIC (`sendto`) — в описании только «outbound connections»;
* что будет с уже установленными сокетами приложения;
* не отвергнет ли BFE стороннего провайдера на этом слое.

**Про права** (learn.microsoft.com/en-us/windows/win32/fwp/access-control, страница от 31.05.2018): дефолтный дескриптор движка даёт `GENERIC_ALL` только built-in Administrators; `GRGWGX` — network configuration operators и служебным SID (`MpsSvc`, `PolicyAgent`, `NapAgent`, `RpcSs`, `WdiServiceHost`); «Everyone» получает лишь `FWPM_ACTRL_OPEN` и `FWPM_ACTRL_CLASSIFY`. `FWPM_ACTRL_ADD` — «Required to add an object to a container». «BFE skips all access checks for kernel-mode callers».
⚠️ Эта страница описывает контейнеры «providers, callouts, filters» и **connection policy не покрывает вовсе**. Необходимость админа мы проверили запуском (§2.8), **достаточность — нет**. Microsoft называет вызывающего «Trusted Intermediary Agent» — это модель доверенного агента, а не «любой элевейтнутый процесс».

**Про redirect-слои** (learn.microsoft.com/en-us/windows-hardware/drivers/network/using-bind-or-connect-redirection, ms.date 27.09.2024, обновлена 11.07.2025): «enables **application layer enforcement (ALE) callout drivers** to inspect and, if desired, redirect connections»; «Callout drivers that support classification at these layers must register using **FwpsCalloutRegister1 or higher**»; «Changing the local address and port of a flow is only supported in the bind-redirect layer». Страница «Management filtering layer identifiers» помечает пользовательские слои явно («This is a user-mode filtering layer» — IPSEC_*, IKEEXT, RPC_*); у `ALE_BIND_REDIRECT_V4/V6` и `ALE_CONNECT_REDIRECT_V4/V6` такой пометки нет.

**Про DNS** — README `mullvad/win-split-tunnel`, дословно: «From the point of view of the driver, all DNS requests are made by a particular instance of svchost. Because svchost is not excluded, and because we can't easily know which process initiated the request, default processing takes precedence and sends the traffic inside the tunnel».

**Про `strict_route`** — sing-box.sagernet.org/configuration/inbound/tun/: на Windows при `strict_route` ставится WFP-фильтр, блокирующий исходящий порт 53 не с интерфейса туннеля.

---

## 4. Разбор путей

### 4.1 Драйвер режима ядра (ALE bind/connect redirect) — работает, недоступен нам

Единственный путь с доказанной практикой: так делают **Mullvad, Proton VPN, Windscribe, AmneziaVPN, NordVPN, ExpressVPN**. У трёх открытых видно ровно `ALE_BIND_REDIRECT` / `ALE_CONNECT_REDIRECT`.

Самое показательное — **AmneziaVPN**: кроссплатформенный GPL-3.0-клиент нашего класса не стал писать свой драйвер и **не нашёл юзермод-пути**, а загрузил `mullvad-split-tunnel.sys` под именем «AmneziaVPNSplitTunnel» — получив в нагрузку конфликт WFP-сублоя с Mullvad и .sys, остающийся в системе после удаления.

Кто не умеет вовсе: **Cloudflare WARP** на Windows — только IP/CIDR и домены (это в точности наш `tunRouteOnlyCidrs`); **Tailscale** — per-app только на Android, по Windows три открытых feature request.

Смета разобрана в §6. Коротко: деньги не блокер, лицензия не блокер, блокеры — юрлицо, апрельская Windows Driver Policy, 14 тысяч строк чужого кода ядра под чужую архитектуру и то, что драйвер **не решает DNS**.

### 4.2 `FwpmConnectionPolicyAdd0` — единственный кандидат без драйвера

Всё существенное — в §1, §2, §3. Сводка «за/против»:

**За:** .sys не нужен вовсе, коллаут встроенный; вызывается через `dart:ffi` так же, как мы уже дёргаем WinINET; это **единственный найденный механизм, делящий по имени программы, а не по адресу**; снятие — `FwpmConnectionPolicyDeleteByKey0`, плюс динамическая сессия BFE (`FWPM_SESSION_FLAG_DYNAMIC`) убирает объекты вместе с сессией, то есть мусор не копится.

**Против:**

1. ⚠️ **Главное не проверено никем**: перебьёт ли политика `auto_route 0.0.0.0/0` с метрикой 0.
2. ⚠️ Пол по ОС Microsoft не объявила; заголовочный гейт выше Windows 10, экспорт подтверждён только на 26100. У нас `installer\silentgate.iss:77` → `MinVersion=10.0.17763`, а `docs/TEST_PLAN.md:183` заявляет Windows 10 и 11. Значит нужен обязательный `GetProcAddress` с честной деградацией, и **обещать возможность всем нельзя**.
3. ⚠️ Админ на **каждую** правку (проверено кодом 5), а правок много: смена сети/Wi-Fi, переподключение, любое изменение списка «Прямо» — политика привязана к LUID и адресу физического адаптера. Это не «разовый UAC как под TUN», это постоянно живущий элевированный помощник. И он лёг бы ровно в тот путь элевации, который у нас документированно виснет (память `windows-elevation-hangs-in-flutter`).
4. ⚠️ Расширение протокола TUN-хелпера означает перерегистрацию задачи Планировщика: команда запекается при создании (`app/lib/engine/windows/tun/tun_scheduled_task.dart:39-45`, `--tun-task "<cfg>" "<stop>"`) — то есть **новый UAC у каждого существующего пользователя на обновлении**.
5. ⚠️ Одного `NEXT_HOP_INTERFACE`, вероятно, мало: без `SOURCE_ADDRESS` исходящим может остаться адрес TUN.
6. ⚠️ Столкновение с нашим же `strict_route`: sing-box ставит блокирующий фильтр на порт 53 мимо туннеля. Политика назначает маршрут, но **не отменяет чужой запретительный фильтр** — кто выиграет, не проверял никто.
7. Нулевая обкатка в проде: ни in-box потребителей, ни примеров, ни вендоров.

### 4.3 Windows VPN Platform (`IVpnPlugIn` + traffic filters) — механизм честный, нам не годится

Опровергнуты два наших прежних предположения: магазин **не обязателен** (сайдлоад restricted capability разрешён без одобрения), подпись драйвера ни при чём, и работает это для обычных win32 по пути к exe (`VpnAppIdType.FilePath`), а не только для UWP. Приложение, помеченное «ПРЯМО», действительно вообще не касается туннеля, принуждение выполняет драйвер Microsoft.

Цена оказалась не в упаковке, а в датапути:

* платформа берёт транспортом WinRT-сокет **внутри процесса плагина** и требует, чтобы плагин сам делал `Encapsulate`/`Decapsulate` L3-пакетов. Значит VLESS/Reality/XHTTP/Hysteria2 надо **переписать внутри UWP-компонента**, отказавшись от Xray и sing-box на Windows и разведя Windows с Android на разные датапути;
* обходной вариант «тонкий плагин пересылает пакеты в наш локальный sing-box» умирает об изоляцию AppContainer: loopback у пакетированных приложений закрыт, а `CheckNetIsolation LoopbackExempt` требует администратора и прямо назван Microsoft средством разработки;
* traffic filters — **белый список**: «once a TrafficFilterList is added, all traffic is blocked other than the ones matching the rules». Модель инвертирована: перечислять надо «туннельные» приложения, а привычный режим «всё через VPN» в такой профиль не ложится.

**Вердикт: не делаем.** Это переписывание всего Windows-датапути ради одной функции.

### 4.4 Маршруты-исключения `/32` своими руками — дёшево, работает везде, но по адресу

Поверх штатного `auto_route` можно самим ставить `/32` (и `/128`) через физический шлюз: длина совпадения префикса важнее метрики, поэтому такой маршрут бьёт туннельный `0.0.0.0/0`. Это **1 маршрут на адрес** вместо 32 у `route_exclude_address` у sing-box (посчитано по чужим отчётам: 50 адресов через ядро = 1237 маршрутов — тот самый режим, где ловят 100 % CPU в sing-box#2418).

⚠️ Статус: **по документации и по общему поведению стека Windows; на нашем стенде не воспроизведено.** Цифры sing-box#2418 — чужие отчёты, нами не проверены.

Цена та же, что у `route_address`, и её нельзя замолчать: **что не зашло в туннель — ядру не показали**, поэтому правила по сайтам и «Блок» к такому трафику неприменимы. И деление всё равно по адресу, а не по имени программы, то есть исходную задачу владельца это не решает — только смягчает.

### 4.5 Закрыто отрицательно — не возвращаться

| Путь | Почему мёртв |
|---|---|
| `exclude_process_name` / `exclude_process_path` в sing-box | На Windows не существует (проверено ранее, BACKLOG #21) |
| `exclude_package` / `include_package` / `exclude_uid` / `include_interface` и т. п. | `sing-box check` на Windows принимает (exit 0) и **не применяет** — проверено запуском настоящего 1.11.15 |
| WinDivert | Даёт ProcessId на SOCKET/FLOW, умеет перехват и блокировку, но не «увести в обход» — маршрутизацию пришлось бы писать самим |
| `IP_UNICAST_IF` через инжект в winsock (модель ForceBindIP) | Опцию ставит **владелец сокета**, извне никак; работало бы только для процессов, запускаемых нами; без ICMP/raw; гарантированные претензии антивирусов. Тупик |
| Сетевые компартменты | Настоящая раздельная маршрутизация, но переселить туда **чужой** процесс документированно нельзя, а второго компартмента без контейнерной инфраструктуры не существует |
| `route_address_set` (DNS-управляемый обход через конфиг ядра) | На Windows — снимок на момент старта; колбэк обновления регистрируется только при `auto_redirect` (Linux + nftables). Плюс на build 26100 незакрытый баг старта (sing-box#3725, чужой отчёт, нами не воспроизведён). Требовал бы перезапуска туннеля на каждый новый адрес |
| Azure Trusted Signing / Azure Artifact Signing для драйвера | Официальный FAQ прямо: kernel-mode остаётся за Partner Center, EV-сертификаты не выдаются и не будут (§6) |
| Windows 11 25H2 / Server 2025 как источник новых API | 25H2 идёт на той же ветке обслуживания, что 24H2, новых сетевых API не принесла; Server 2025 дал Network ATC/HUD и смену keying modules — не маршрутизацию по процессу |

---

## 5. Мины, общие для ВСЕХ вариантов обхода

Их надо держать в голове независимо от того, какой путь когда-нибудь выберем. Ни одна не снимается драйвером.

1. **⚠️ DNS на Windows принадлежит `svchost.exe`.** Это записано у нас с 1.1.0 и подтверждено README Mullvad слово в слово. Значит «DNS по приложению» на Windows останется невозможным и после драйвера, и после connection policy: данные пойдут мимо туннеля, а имена продолжат резолвиться из-под него. В интерфейсе этого обещать нельзя.
2. **⚠️ `strict_route` режет обойдённый DNS.** sing-box блокирует WFP-фильтром весь исходящий порт 53 не с интерфейса туннеля. Любой обойдённый трафик останется без обычного DNS, пока мы не выключим `strict_route` или не поставим свой разрешающий фильтр весом выше.
3. **⚠️ Что не зашло в туннель — ядру не показали.** Правила по сайтам и «Блок» к обойдённому трафику неприменимы **по построению**. У варианта по процессу цена та же, только приложение уходит целиком.
4. **⚠️ Обход ломает локальные функции приложений** (по README Mullvad, для драйверного пути): исключённым запрещён бинд на `inaddr_any`, ранний бинд переадресуется на физический интерфейс — «if a UDP socket isn't explicitly bound to 127.0.0.1 before sending, it won't be able to talk to localhost… most excluded apps are affected»; плюс ломается приём мультикаста на многодомных машинах, «no generally applicable mitigations are available». Пользователь, пометивший программу «Прямо», получит непонятные поломки и не свяжет их с VPN. **Наш нынешний путь через ядро таких побочек не даёт.**

---

## 6. Смета на драйвер (для протокола: считали, чтобы закрыть вопрос деньгами)

**Деньги — не блокер.** Первый год ≈ 400–950 $, дальше ≈ 350–560 $/год.

| Статья | Цифра (прайсы сняты 17.08.2026) |
|---|---|
| EV Code Signing | SSL.com EV 349 $/год (149 $/год при оплате за 5 лет). Реселлеры: Sectigo/Comodo EV от 279,99 $, DigiCert EV 559,99 $. «Sole Proprietor EV» для ИП — 359 $/год |
| Аппаратный токен | YubiKey у SSL.com +379 $ разово. Свой HSM (BYO) — аттестация 500–1 500 $ |
| Облачная подпись из CI | eSigner — отдельная подписка, цена не раскрыта |
| Partner Center / Hardware Dev Center | Платы в прайсах Microsoft не нашлось — **судя по всему, 0 $** (99 $ — это Microsoft Store, другая программа). Прямой цитатой НЕ подтверждено |
| Attestation-подпись каждой сборки | 0 $ сверх EV; по времени — часы, при застревании сутки |

⚠️ С 01.03.2026 требования CA/Browser Forum ограничивают срок публично доверенных code signing сертификатов **458 днями** — «пятилетний» тариф означает предоплату с перевыпуском примерно каждые 15 месяцев.

**Блокеры — не денежные, их четыре.**

1. **Partner Center требует ОРГАНИЗАЦИЮ.** По learn.microsoft.com/windows-hardware/drivers/dashboard/hardware-program-register (ms.date 11.08.2026): EV-сертификат нужен **для регистрации**, а не для подписи драйвера; вход под учёткой **глобального администратора Microsoft Entra ID организации**; «Identify a legal contact who has the authority to sign agreements on behalf of your organization»; D-U-N-S либо ручной ввод данных компании; анкета о бизнесе. В MS Q&A есть случай: человек завёл тенант на своё ИП — регистрацию заблокировала автоматическая проверка доверия **ещё до загрузки EV**, самому разблокировать нельзя. Это та же стена, что уже зафиксирована по iOS. Отдельно и не проверено: пройдут ли регистрация и выдача EV у западного CA для заявителя из РФ.
2. **⚠️ НОВОЕ, чего не было в BACKLOG #21: Windows Driver Policy, апрель 2026.** С апрельского обновления безопасности Windows перестала доверять по умолчанию драйверам ядра, подписанным по старой cross-signed программе — на Windows 11 24H2, 25H2, 26H1 и Server 2025 (блог Microsoft «Advancing Windows driver security: Removing trust for the cross-signed driver program», 26.03.2026). Доверенными названы драйверы, прошедшие **WHCP** («signed by Microsoft-owned and protected code signing certificates»), и явный список-исключение. Выкат в режиме оценки: ядро аудирует загрузки, после ~100 часов и 3 перезагрузок без нарушений система переходит в enforcement. Снять политику может администратор (`CiTool.exe --remove-policy "{8F9CB695-5D48-48D6-A329-7202B44607E3}"` + перезагрузка).
   **⚠️ Переживает ли ATTESTATION-подпись эту политику — из источников НЕ СЛЕДУЕТ ОДНОЗНАЧНО, и источники прямо расходятся.** support.microsoft.com «The Windows Driver Policy» перечисляет только WHCP и список-исключение; при этом сама документация Microsoft разводит attestation и WHCP («Attestation signed drivers can't be published to Windows Update for retail audiences… you must submit your driver through the Windows Hardware Compatibility Program»), а часть отраслевых разборов (MagicSword, 30.03.2026) пишет об этом как об одном и том же. **Рассуждение (наше, не факт):** политика бьёт по подписям, чьё доверие идёт от сторонних корней CA; attestation выдаёт сам Microsoft своим сертификатом, и технически это «Microsoft-owned certificates» — скорее всего доверие сохраняется. Но это вывод по смыслу, и цена ошибки — весь проект.
   **⚠️ И отдельно:** раздел документации теперь называется «Attestation signed drivers **for testing scenarios**» и открывается словами «For testing purposes only, you can submit your drivers for attestation signing» (ms.date 23.03.2026). Ещё в 2024-м это был штатный путь розничной поставки. Направление движения Microsoft читается однозначно.
3. **Объём и чужая архитектура.** 13 968 строк C/C++ режима ядра, плюс пользовательский агент **с нуля** на нашем стеке (у Mullvad продакшн-агент на Rust в самом приложении, в `testing/` только 1 481 строка «для ручного тестирования»). Агент обязан: держать полный процессный список, передавать пути исключаемых программ, **следить за интерфейсами и постоянно обновлять драйверу IP туннеля и основного адаптера**, вести автомат STARTED→INITIALIZED→READY→ENGAGED через IOCTL, принимать события по модели inverted call. ⚠️ Главное несовпадение: подсистема firewall драйвера написана, чтобы **перекрывать запретительные WFP-фильтры приложения Mullvad** (их kill switch на WFP). У нас WFP-килсвича нет вовсе — захват идёт через `auto_route`. Значит либо переносим kill switch на WFP (новая подсистема, свои гонки и свой класс утечек), либо вырезаем permit-логику и рискуем тем, что исключённый трафик режет наш же kill switch. Это не «форк с косметикой». Оценка **2–4 месяца одного разработчика С ОПЫТОМ WFP/KMDF**; без такого опыта — существенно больше и с риском не сойтись вовсе. ⚠️ ABI Mullvad движется: в 1.3.0.0 «Pass in sublayer GUIDs to use for filters instead of hardcoding them. **This is a breaking change to the initialize IOCTL**» — форк придётся сопровождать.
4. **Драйвер не решает DNS и добавляет свои регрессии** — §5.1 и §5.4.

**Плюс необратимая потеря скорости.** Сегодня правка Dart/Kotlin едет пользователю за минуты. С драйвером любая правка `.sys` — MakeCab, подпись EV с физического токена на доверенной машине (у Mullvad это прямо описано в RELEASE.md как ручная операция человека), загрузка в Partner Center, ожидание, скачивание, пересборка поставки. Microsoft при этом **перезатирает** вашу embedded-подпись своим SHA-2 сертификатом и генерирует новый `.cat` — без похода в Partner Center рабочего `.sys` не существует в принципе. Добавьте BSOD у пользователей, ложные срабатывания антивирусов на `.sys` без репутации, обязательные Driver Verifier + HVCI-прогоны (у WFP callout драйверов совместимость с Memory Integrity — известное больное место, тема на форуме OSR) и стенд с kernel debugging вместо нынешней SG-Test. Это уже не техническая, а репутационная и юридическая ответственность, которой у per-user установки без прав сейчас нет вовсе.

**Побочная польза, не связанная с драйвером:** Azure Artifact Signing (бывший Trusted Signing) за **9,99 $/мес** (Basic, 5 000 подписей) доступен **физлицу** — в FAQ есть «Individual identity validation» через Verified ID и AU10TIX — и годится, чтобы подписать `silentgate.exe` и установщик. Это закрывает давнюю проблему SmartScreen из `docs/APP_UPDATE.md`. К драйверу отношения не имеет.

---

## 7. Вердикт по BACKLOG #21

**Решение «НЕ делаем» подтверждается, и новые данные его укрепляют, а не ослабляют.**

**Что в записи верно и править не надо:**

* «перенаправление на `ALE_BIND_REDIRECT`/`ALE_CONNECT_REDIRECT` доступно только драйверу режима ядра» — подтверждено трижды: документацией WDK, отсутствием `FwpsCalloutRegister*` и всего redirect-семейства в экспортах `fwpuclnt.dll`, и исходником Mullvad;
* WinDivert отвергнут — подтверждается;
* `exclude_*` в sing-box на Windows не работает — подтверждается;
* `route_address` — единственный рычаг, действующий до входа пакета в туннель — **с оговоркой**: к нему добавляется вариант «свои маршруты `/32` поверх auto_route» (§4.4), тоже адресный.

**Что в записи надо УТОЧНИТЬ (формулировка стала неточной):**

Фраза «увести приложение мимо туннеля умеет только драйвер» больше не верна буквально. Правильная формулировка:

> Redirect-слои — только для драйвера (верно и сегодня). Но с некоторой сборки Windows 11 существует отдельный юзермод-механизм маршрутизации по процессу — `FwpmConnectionPolicyAdd0` + слой `OUTBOUND_NETWORK_CONNECTION_POLICY`. Он физически есть в ОС (проверено), но **не проверен против TUN-маршрута, требует администратора на каждую правку, отсутствует на Windows 10 и не имеет ни одного известного потребителя**. До живого опыта считать путь неподтверждённым.

**Три факта, которых в #21 не было и которые надо туда дописать:**

1. Azure Trusted Signing переименован в **Azure Artifact Signing** и для драйверов не годится в принципе — официальный FAQ (ms.date 14.05.2026, обновлён 14.08.2026): «Signing with the Partner Center is kernel-mode signing… Sign your user-mode binaries by using Artifact Signing» и «Artifact Signing doesn't issue Extended Validation (EV) certificates. **There's no plan to issue EV certificates in the future**» — то есть им нельзя ни подписать драйвер, ни даже **зарегистрировать** хардварный аккаунт.
2. С апреля 2026 действует **Windows Driver Policy**, снявшая доверие с cross-signed драйверов на Win11 24H2/25H2/26H1 и Server 2025.
3. Attestation в документации Microsoft **понижен до «for testing purposes only»**.

---

## 8. Что этим расследованием НЕ доказано

Чтобы через полгода не выдать одно за другое:

1. Что connection policy перебивает `auto_route 0.0.0.0/0` с метрикой 0. **Не проверено никем.**
2. Что она вообще применяется к UDP/QUIC-`sendto` и к уже открытым сокетам.
3. Что элевейтнутый вызов проходит (проверен только отказ неэлевейтнутого — код 5).
4. Что BFE пускает стороннего провайдера на этот слой.
5. Что API отсутствует на Windows 10 и Win11 ≤23H2 — это **вывод из NTDDI-гейта и SDK 10240**, живого Windows 10 под рукой не было.
6. Что маршруты `/32` действительно бьют туннельный `0.0.0.0/0` в нашей конфигурации — общее поведение стека, но на стенде не воспроизведено.
7. Что attestation-подпись переживает апрельскую политику.
8. Почему `FwpmEngineOpen0` дал разные коды в двух прогонах (§2, аномалия).

---

## 9. Что делать дальше, по убыванию отдачи

### 9.1 Ничего не менять в коде. Отдача максимальная, цена нулевая

Режим «в туннель только эти подсети» (`tunRouteOnlyCidrs`) остаётся единственным доказанным рычагом. В интерфейсе **не обещать**, что помеченная «Прямо» программа идёт мимо VPN: сегодня она разбирается внутри ядра, и это надо называть своими словами (текущая формулировка в CLAUDE.md 1.1.0 корректна, в UI — проверить).

### 9.2 Один пробный опыт в VM SG-Test. ~200 строк, закрывает главную развилку

Это единственная работа, которая превращает «правдоподобно» в «знаем». **Только в госте, на хосте — ничего** (правило №1).

Протокол:

1. клон SG-Test, снапшот `clean`, внешний коммутатор `SG-External` (память `vm-stand-external-switch`);
2. элевейтнутый native-процесс (не Flutter — исключаем известное зависание элевации): `FwpmEngineOpen0` с `FWPM_SESSION_FLAG_DYNAMIC`; **сначала разобраться с аномалией §2** — какой `authnService` и какая `FWPM_SESSION0` дают успех;
3. `FwpmGetAppIdFromFileName0` на `curl.exe`;
4. политика: условие `ALE_APP_ID` = curl, настройки `NEXT_HOP_INTERFACE` = LUID физического адаптера + `SOURCE_ADDRESS` = его IPv4 (+ `NEXT_HOP` = шлюз, отдельным прогоном без него — проверить, обязателен ли);
5. поднять TUN штатно, прогнать **оба** состояния `strict_route` (вкл — умолчание, и выкл);
6. мишени по отдельности, не суммой: TCP (`curl https://ipinfo.io`), UDP/QUIC, DNS :53, ICMP. Смотреть **выходной IP по каждой**;
7. **⚠️ контрольный опыт, без которого всё бессмысленно:** убить оба ядра (sing-box + Xray) при живой политике. Если соединение curl продолжает работать — это настоящий обход. Если рвётся — политика не увела трафик, а лишь перекрасила его внутри ядра, и ценность нулевая;
8. проверить: не сломался ли остальной трафик машины; снимается ли политика со смертью сессии; что с уже открытыми сокетами (открыть сокет ДО добавления политики);
9. отдельным гостем — Windows 10 22H2: есть ли экспорт вообще.

**Критерии.** Успех = п.7 держится и остальной трафик цел, при выключенном `strict_route` как минимум. Провал = маршрут не перебивается ЛИБО обойдённое приложение теряет DNS без обходного лечения ЛИБО политика не переживает смену сети. При провале — закрыть тему окончательно и дописать результат в #21, чтобы через год не начинать снова.

**Гасить стенд за собой** (`Stop-VM -Name SG-Test -Force`).

### 9.3 Маршруты-исключения `/32` — если нужен дешёвый выигрыш сейчас

Работают на всех Windows, прав сверх нынешних не требуют сверх тех, что уже есть у TUN-пути. Дают то же деление по адресу, но экономнее `route_exclude_address` (1 маршрут вместо 32) и без известного упора в CPU. **Проверять на стенде: перебивает ли `/32` туннельный `0.0.0.0/0` у нас на самом деле.** Это не решает задачу владельца, а смягчает её — и так и надо это подать в интерфейсе.

### 9.4 Разобраться с `strict_route` и DNS независимо от всего остального

Мина §5.2 сработает при **любом** варианте обхода, включая нынешний `route_address`. Нужно понять: свой разрешающий WFP-фильтр весом выше 10 или честное «при обходе DNS идёт через туннель» в интерфейсе. Работа маленькая, польза есть в любом сценарии.

### 9.5 Подписать `silentgate.exe` и установщик через Azure Artifact Signing

9,99 $/мес, доступно физлицу, закрывает SmartScreen из `docs/APP_UPDATE.md`. К обходу отношения не имеет, но это самая дешёвая осязаемая польза, вынесенная из этого расследования.

### 9.6 Обновить записи

`docs/BACKLOG.md` #21 — уточнение формулировки и три новых факта (§7). CLAUDE.md — при желании сослаться на этот документ из блока про TUN и «Прямо».

### 9.7 Не делать

Драйвер (§6), Windows VPN Platform (§4.3), WinDivert, инжект `IP_UNICAST_IF`, компартменты, `route_address_set` на Windows. Всё разобрано, всё закрыто отрицательно.

---

## 10. Источники

**Microsoft Learn:**
`nf-fwpmu-fwpmconnectionpolicyadd0` (ms.date 29.04.2024) · `ne-fwptypes-fwp_network_connection_policy_setting_type` (03.05.2026, «TBD») · `nf-fwpmk-fwpmconnectionpolicydeletebykey0` · `windows/win32/fwp/access-control` (31.05.2018) · `windows/win32/fwp/management-filtering-layer-identifiers-` · `windows-hardware/drivers/network/using-bind-or-connect-redirection` (27.09.2024, обновлена 11.07.2025) · `windows-hardware/drivers/dashboard/hardware-program-register` (11.08.2026) · `windows-hardware/drivers/dashboard/driver-signing-offerings` (23.03.2026) · `azure/artifact-signing/faq` (14.05.2026) · блог «Advancing Windows driver security: Removing trust for the cross-signed driver program» (26.03.2026) · support.microsoft.com «The Windows Driver Policy».

**Локальные файлы (SDK/WDK 10.0.26100.0):**
`um\fwpmu.h:895-904, 2969-2989, 5379-5399` · `um\fwpsu.h:177` · `km\fwpsk.h` · `km\fwpmk.h:5186` · `shared\fwpvi.h:677` · `shared\fwptypes.h:263-269` · `shared\fwpmtypes.h:191-201, 219, 328` · `shared\sdkddkver.h:160-166` · `Include\10.0.10240.0\*` (отрицательный результат).

**Системные бинарники (10.0.26100):**
`C:\Windows\System32\fwpuclnt.dll` 10.0.26100.1 · `bfe.dll` · `drivers\tcpip.sys` 10.0.26100.857 · `drivers\fwpkclnt.sys` 10.0.26100.268.

**Чужой код:** `github.com/mullvad/win-split-tunnel` (v1.3.0.0, коммит 25.03.2026) — `src/firewall/*.cpp`, `README.md`, `RELEASE.md`, `CHANGELOG`, `LICENSE-GPL.md`, `LICENSE-MPL.txt`. AmneziaVPN (загружает `mullvad-split-tunnel.sys` под своим именем).

**Прайсы (сняты 17.08.2026):** ssl.com, signmycode.com, azure.microsoft.com/pricing/details/artifact-signing.

**Чужие отчёты, нами НЕ воспроизведённые:** sing-box#2418 (CPU при большом `route_exclude_address`), sing-box#3725 (`route_address_set` на build 26100), тема OSR «WFP Callout Driver incompatible with Win10/11 Memory Integrity», обращения в MS Q&A про застревание attestation и блокировку регистрации в Partner Center.

**Наши документы:** `docs/BACKLOG.md` #21 · `docs/research/VPN_DETECTION.md` · `docs/TEST_PLAN.md:183` · `installer\silentgate.iss:77` · `app/lib/engine/windows/tun/tun_scheduled_task.dart:39-45` · память `windows-dns-belongs-to-svchost`, `windows-elevation-hangs-in-flutter`, `vm-stand-external-switch`, `ios-port-hard-constraints`.