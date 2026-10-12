# «Настоящий прямой режим»: трафик мимо TUN и мимо прокси, который никто не уважает

**Файл:** `docs/research/NATIVE_DIRECT_MODE.md`
**Дата:** 19.09.2026. Исследование — только чтение кода, документации и чужих репозиториев; на
хосте ничего не запускалось, VPN/TUN/прокси не поднимались (правило №1 CLAUDE.md).
**Вопрос владельца дословно:** «как можно сделать впн клиент в котором будет НАСТОЯЩИЙ режим
напрямую где всё не заворачивается в tun или прокси (который никто не уважает). как это сделать?
только свой драйвер?»
**Связанные записи (не повторяются здесь, только ссылки):** `docs/research/REAL_APP_BYPASS.md`
(17.08.2026 — обход туннеля по имени программы на Windows, разбор `FwpmConnectionPolicyAdd0`,
смета на драйвер), `docs/research/VPN_DETECTION.md` (обновление 17–18.09.2026 — опыт с двумя
рычагами на Android закрыт отрицательно), `docs/BACKLOG.md` #21 (решение «драйвер не делаем») и
#32 (kill switch на WFP — уже пользуемся user-mode WFP), память `windows-usermode-process-routing`,
`windows-dns-belongs-to-svchost`, `rejected-approaches`.

Пометки у источников: **[документация]** — вендор ОС/ядра; **[репозиторий]** — исходники или
README проекта; **[статья]** — блог, форум, обзор (проверять критически).

---

## 1. Прямой ответ владельцу

**Да. На Windows и Android без драйвера ядра (Windows) или root (Android) режима «трафик чужого
приложения уходит в наш VPN сам, без TUN-адаптера и без того, чтобы приложение согласилось на
прокси» — НЕ СУЩЕСТВУЕТ.** Это не пробел в поиске, а устройство обеих систем: другой процесс
отдаёт свои сокеты только ядру ОС, и встать между ним и ядром можно ровно тремя способами.

| Точка вставки | Что это у нас сейчас | Видит ли приложение | Нужен ли код в ядре |
|---|---|---|---|
| **Адаптер** (виртуальная сетевая карта) | TUN через wintun + sing-box | видит `tun`-адаптер / `TRANSPORT_VPN` | драйвер уже есть (wintun, подписан WireGuard) / `VpnService` |
| **Сокет** (перехват `connect()`/`bind()` чужого процесса в ядре) | нет | не видит ничего, отказаться не может | **ДА — только callout-драйвер / root** |
| **Само приложение** (системный прокси, инжект) | системный прокси WinINET | может проигнорировать | нет |

То, чего хочет владелец, — вторая строка. На Windows это слой WFP `ALE_CONNECT_REDIRECT` /
`ALE_BIND_REDIRECT`, и Microsoft прямо пишет, что он для «application layer enforcement (ALE)
**callout drivers**» [документация: Using Bind or Connect Redirection]. В пользовательской
`fwpuclnt.dll` ни одной функции этого семейства нет — проверено экспортами в
`REAL_APP_BYPASS.md` §2.13. **Все без исключения** программы, которые делают на Windows
«прозрачный проксификатор» (Proxifier, ProxyCap/NetDetour, NetFilter SDK → Netch, Windows Packet
Filter → ProxiFyre, WinDivert), возят с собой `.sys` — см. таблицу §5. Исключений нет ни одного.

**Что при этом надо честно сказать:** «без прокси» в строгом смысле для нашего протокола
невозможно вообще. VLESS/Reality/Hysteria2 живут в пользовательском процессе Go (Xray, sing-box);
драйвер лишь **заставляет** приложение подключиться к этому процессу вместо настоящего адреса.
То есть режим «который никто не уважает» превращается в режим «который никто не может не
уважать» — но прокси на `127.0.0.1` остаётся. Единственный способ убрать пользовательский
прокси целиком — реализовать протокол в ядре, как WireGuardNT [репозиторий], а это (а) всё
равно виртуальный адаптер, (б) невозможно для Reality/uTLS и (в) удваивает драйверную смету.

**Единственный юзермод-механизм по процессу — `FwpmConnectionPolicyAdd0` — решает ДРУГУЮ
задачу** («вывести приложение на физическую карту», не «завернуть в наш аутбаунд»), не
существует на Windows 10, требует администратора на каждую правку и **до сих пор не проверен
против TUN-маршрута никем** (§3.4). С августа появился первый посторонний потребитель этого API
(NetLane), но он подтверждает лишь, что API живой, — не то, что он перебивает VPN.

**Android без root — тупик, доказанный не документацией, а нашим же опытом 18.09.2026**
(`VPN_DETECTION.md`, «Опыт закрыт»): режим без `VpnService` работает ровно постольку, поскольку
приложения сами настроены на `127.0.0.1`, то есть «VPN выключен». С root задача решается штатно
(iptables TPROXY, eBPF) — §4.

**Где желание владельца — буквально API операционной системы: macOS** (`NETransparentProxyProvider`,
macOS 11+): система отдаёт расширению потоки TCP/UDP всех приложений по правилам, без utun,
приложение отказаться не может. Цена — системное расширение, Developer ID, нотаризация (§6.1).
**Linux** — то же самое штатными средствами ядра (cgroup + TPROXY / eBPF), без единой подписи (§6.2).
**iOS** — тупик (§6.3).

---

## 2. Почему «прокси никто не уважает» и почему TUN — это не баг, а следствие

Системный прокси на Windows — это запись в реестре WinINET (`engine/windows/system_proxy.dart`).
Её читают WinINET/WinHTTP, браузеры, Electron, .NET; её **не обязаны** читать программы на Go,
Java, Qt с собственным сетевым стеком, игры и всё, что ходит по UDP. На Android то же самое с
прокси Wi-Fi и `VpnService.Builder.setHttpProxy` (API 29): по документации Android это
рекомендация, приложения с сырыми сокетами её игнорируют [документация: VpnService.Builder;
статья: android-proxy-setup]. Поэтому все клиенты нашего класса (v2rayN, Clash Verge Rev,
Hiddify, NekoRay, Happ, sing-box SFA, v2rayNG) держат ровно два режима — **системный прокси**
(добровольный) и **TUN** (принудительный, но с адаптером) — и ни у одного нет третьего.
`REAL_APP_BYPASS.md` §4.1 и BACKLOG #21 это уже фиксировали для «обхода»; для «захвата» картина
та же, и по той же причине: третий режим — это драйвер.

---

## 3. Windows — все реальные механизмы, по одному

### 3.1 Callout-драйвер WFP на слоях ALE redirect — единственный «настоящий» путь

**Что даёт.** Перехват `connect()` любого процесса в ядре, до того как пакет существует.
Для **захвата**: подмена адреса назначения на наш локальный порт (приложение думает, что
подключилось к `example.com:443`, а подключилось к `127.0.0.1:10809`; исходный адрес драйвер
сообщает прокси). Для **обхода**: подмена локального адреса/интерфейса при `bind()` — сокет
«рождается» на физической карте, и туннельный `0.0.0.0/0` его не касается. Покрывает TCP, UDP,
ICMP, raw; трафик исключённого приложения живёт при смерти ядра (Xray/sing-box). Это то, что у
Mullvad, Proton, Windscribe, Proxifier.

**Что требует.** Kernel-mode `.sys`: KMDF/WDM, `FwpsCalloutRegister1+` [документация: Using Bind or
Connect Redirection]; EV-сертификат для регистрации организации в Partner Center; attestation-
подпись Microsoft на каждую сборку (в марте 2026 её раздел переименован в «Attestation signed
drivers **for testing scenarios**», «for testing purposes only» [документация: Driver Signing
Options, ms.date 23.03.2026]); с апреля 2026 Windows Driver Policy сняла доверие с cross-signed
драйверов на 24H2/25H2/26H1 [статья: Microsoft Tech Community, 26.03.2026]. Полная смета и
блокеры — `REAL_APP_BYPASS.md` §6; здесь не повторяется.

**Как это делают реальные клиенты (проверено по их коду/документации):**

- **Mullvad `win-split-tunnel`** [репозиторий] — `ALE_BIND_REDIRECT_V4/V6`, `ALE_CONNECT_REDIRECT_V4/V6`,
  `ALE_AUTH_CONNECT`, `ALE_AUTH_RECV_ACCEPT`; 13 968 строк C/C++; лицензия GPL-3.0-or-later ИЛИ
  MPL-2.0; делает ТОЛЬКО обход (исключение), не захват. README задокументировал: DNS исключённого
  приложения всё равно уходит в туннель («all DNS requests are made by a particular instance of
  svchost»), исключённым ломается UDP на localhost, мультикаст [репозиторий: README; статья:
  Mullvad «The limitations of split tunneling»].
- **Proton `ProtonVPN.CalloutDriver`** [репозиторий: win-app, GPL-3.0 по API GitHub, последний пуш
  27.07.2026] — «redirecting socket bindings when Split Tunnel is enabled and preventing DNS leak
  by sending SERVFAIL response packet for DNS requests which were made from other interfaces».
  Тоже обход, плюс DNS-защита ответом SERVFAIL из ядра.
- **Windscribe `WindscribeSplitTunnel.sys`** [репозиторий: desktop-v2/Desktop-App, GPL-2.0] —
  callout на ALE-слоях, идентификация по AppId. ⚠️ GPL-2.0-only с нашим GPL-3.0 кодом **в одном
  произведении** несовместима; как отдельный бинарь рядом — «простая совокупность», допустимо, но
  форкать в своё дерево нельзя.
- **AmneziaVPN** (GPL-3.0) — своего драйвера не писал, грузит подписанный `mullvad-split-tunnel.sys`
  под именем «AmneziaVPNSplitTunnel» (`REAL_APP_BYPASS.md` §4.1). ⚠️ Это **единственный** известный
  способ получить kernel-mode обход без собственной подписи: байт в байт чужой подписанный `.sys` +
  свой пользовательский агент по IOCTL-протоколу Mullvad. Цена: агент с нуля (у Mullvad он на Rust
  внутри приложения), ABI ломался в 1.3.0.0, конфликт сублоя при установленном Mullvad, `.sys`
  остаётся в системе после удаления. И это только обход — захвата у драйвера Mullvad нет.
- **Proxifier v4** [документация: proxifier.com/docs/win-v4/install.html] — «uses a Windows
  Filtering Platform (WFP) callout driver to intercept network connections», «Only an administrator
  can install, uninstall, start, or stop the driver», подписан SHA-2. Захват (проксификация),
  закрытый код.
- **ProxyCap → NetDetour** [статья: proxytool.app] — «WFP interception», закрытый код. Первичной
  документации вендора о драйвере не нашёл — считать «по обзору».
- **NetFilter SDK (`netfilter2.sys`)** [документация: netfiltersdk.com] — коммерческий WFP-драйвер
  (Windows 7–11, x86/x64/ARM64, сборка 1.7.7.1 от 09.09.2026), на нём **Netch** «ProcessMode — Use
  Netfilter driver to intercept process traffic» [репозиторий: netchx/netch, GPL-3.0]. Цена лицензии
  на сайте не раскрыта, для GPL-проекта — закрытый бинарь третьей стороны.

### 3.2 NDIS Lightweight Filter (уровень пакетов, ниже сокетов) — тоже драйвер

**Windows Packet Filter (WinpkFilter, NT Kernel Resources)** [документация: ntkernel.com] — NDIS 6
LWF-драйвер; на нём **ProxiFyre** («SOCKS5 proxifier … leveraging NDISAPI to transparently route
TCP and UDP traffic on a per-app basis», AGPL-3.0, UDP и QUIC поддержаны, нужен администратор)
[репозиторий: wiresock/proxifyre] и WireSock. Лицензия драйвера: «free for personal or educational
use, including non-profit organizations»; для издателей ПО — Developer License $3 000 (готовые
драйверы) или Source Code License $9 000, редистрибуция «as part of commercial software» только с
лицензией [документация: ntkernel.com/licensing]. ⚠️ Для клиента коммерческого сервиса под GPL-3.0
это серая зона — считать, что нужна платная лицензия. Принцип тот же: код в ядре, только на
уровне пакетов, и сопоставление с процессом делается уже сложнее (по таблице сокетов), не через ALE.

### 3.3 WinDivert — подписанный чужой драйвер, но перенаправление писать самим

[документация: reqrypt.org/windivert-doc.html; репозиторий: basil00/WinDivert] Дуальная LGPL-3.0 /
GPL-2.0, готовые `WinDivert64.sys` подписаны автором, Windows 10/11. Ключевые ограничения из
документации:

- на слоях **`SOCKET`/`FLOW`** есть `ProcessId`, но «it is not possible to inject new or modified
  socket events», события FLOW «can be captured, but not blocked nor injected» — то есть по
  процессу можно **только смотреть и блокировать**, не перенаправлять;
- на слое **`NETWORK`** пакеты модифицируются и реинжектятся (можно переписать адрес назначения на
  локальный прокси), но «process ID information is not available at these layers».

Значит захват по процессу через WinDivert = самописный NAT в пользовательском режиме
(корреляция FLOW-событий с пятёрками пакетов + переписывание + обратная трансляция) поверх
третьего драйвера в поставке. Это ровно то, что BACKLOG #21 отверг как «полурешение по цене
почти полного». Плюс FAQ автора предупреждает о систематических ложных срабатываниях антивирусов
[документация: windivert-faq].

### 3.4 Юзермод без драйвера: что РЕАЛЬНО можно и чего нельзя

| Механизм | Что даёт | Захват в наш аутбаунд | Обход по процессу | Статус |
|---|---|---|---|---|
| `FwpmFilterAdd0` на `ALE_AUTH_CONNECT` (permit/block по `ALE_APP_ID`) | блокировать/разрешать приложению сеть | нет | нет | **уже у нас** — kill switch на WFP (BACKLOG #32) |
| **`FwpmConnectionPolicyAdd0`** + слой `OUTBOUND_NETWORK_CONNECTION_POLICY` | назначить соединению интерфейс/источник/шлюз по `ALE_APP_ID` («process-based routing» дословно у Microsoft) | **нет** (это маршрутизация, не redirect) | теоретически да | живой, но необкатанный — ниже |
| Системный прокси WinINET | добровольный прокси | только для тех, кто уважает | — | у нас по умолчанию |
| TUN + правила `process_name` внутри sing-box | принудительный захват; «Прямо» — внутри ядра | да, но через адаптер | нет (трафик живёт, пока живо ядро) | у нас |
| Windows VPN Platform (`IVpnPlugIn`) | принуждение драйвером Microsoft | требует переписать датапуть в UWP | да | отвергнуто, `REAL_APP_BYPASS.md` §4.3 |
| Инжект `IP_UNICAST_IF` / Detours в чужой процесс (модель ForceBindIP, SocksCap) | подмена сокетов изнутри процесса | частично | частично | отвергнуто: только для процессов, запущенных нами; антивирусы |
| Сетевые компартменты | раздельная маршрутизация | — | чужой процесс не переселить | отвергнуто |

**Про `FwpmConnectionPolicyAdd0` — что изменилось с 17.08.2026.** Тогда в `REAL_APP_BYPASS.md` §1
стояло «никто в мире этим не пользуется». Теперь есть **NetLane** [репозиторий: n3tf4c3/netlane]:
«Serviço com políticas em JSON e roteamento por AppId/LUID usando a API nativa
`FwpmConnectionPolicyAdd0` (IPv4/IPv6)». Проверено по README и API GitHub: создан **05.09.2026**,
C#/.NET 8, лицензии нет, 0 звёзд, 0 форков, «Fase 3 em andamento», UI без прав + **сервис с
повышением** через именованный канал; ограничения авторами же перечислены — «UDP/QUIC e IPv6
continuam pendentes», проверка «handshake-level validation only», «does not prove the policy caused
observed traffic direction». Ни слова о VPN, TUN, метриках и WireGuard; минимальная версия
Windows не указана. **Вывод:** API рабочий (это подтверждение нашего §2 в `REAL_APP_BYPASS.md`
чужими руками), но главный вопрос — перебивает ли политика `0.0.0.0/0` с метрикой 0 на нашем
адаптере — по-прежнему **не проверял никто**. Страница Microsoft за это время не менялась
(ms.date 29.04.2024, поля «Minimum supported client/server» пустые) [документация:
nf-fwpmu-fwpmconnectionpolicyadd0]. Протокол опыта в VM на ~200 строк — `REAL_APP_BYPASS.md` §9.2;
NetLane теперь годится как образец раскладки структур для C#, что удешевляет опыт.

⚠️ И даже при успехе этот API — **только обход**, не захват: он умеет сказать «этот exe — на
Wi-Fi через такой-то шлюз», но не «этот exe — на 127.0.0.1:10809». Заворачивать чужой процесс в
наш аутбаунд без TUN он не может по построению.

### 3.5 TDI и LSP — почему не годятся

TDI и Winsock LSP «As of Windows 8 … are deprecated» [документация: Porting Packet-Processing
Drivers and Apps to WFP]. LSP — DLL, встраивающаяся в цепочку Winsock каждого процесса: работает
только для Winsock-приложений, не видит UDP-«сырых» стеков, ломается от любого другого LSP,
классический вектор малвари, и на нём жили старые проксификаторы. Microsoft: TDI-фильтрам —
переходить на WFP, TDI-клиентам — на WSK. Закрыто, не рассматривать.

### 3.6 Мины, которые не снимает НИКАКОЙ вариант на Windows

Перечислены в `REAL_APP_BYPASS.md` §5, здесь напоминание, потому что они относятся и к захвату:

1. **DNS принадлежит `svchost.exe`** (память `windows-dns-belongs-to-svchost`; README Mullvad —
   то же дословно). Захватить «DNS этого приложения» по процессу нельзя ни драйвером, ни
   политикой. Proton лечит SERVFAIL-ом из ядра для ВСЕГО DNS мимо туннеля — это не per-app.
2. **`strict_route` sing-box режет порт 53 мимо туннеля** — любой обойдённый трафик остаётся без DNS.
3. **Перенаправленный/обойдённый трафик не видит ядро** — правила по сайтам и «Блок» к нему
   неприменимы.
4. **Redirect ломает локальные функции приложений** (UDP на localhost, мультикаст) — задокументировано
   Mullvad, «no generally applicable mitigations are available».

---

## 4. Android — без root тупик, с root штатно

| Способ | TUN / `TRANSPORT_VPN` | Приложение может не уважать | Root | Статус |
|---|---|---|---|---|
| `VpnService` + `addAllowedApplication`/`addDisallowedApplication` | да (для включённых) | нет — принудительно | нет | **у нас**. Исключённые «use system networking as if the VPN wasn't running» [документация: developer.android.com/develop/connectivity/vpn] — это и есть **настоящий нативный обход**, на уровне ОС |
| `allowBypass()` | да | приложение само выбирает сеть | нет | даёт приложениям право уйти, не нам — право завернуть |
| Прокси Wi-Fi / `setHttpProxy` (API 29) | нет | **да** | нет | рекомендация; сырые сокеты игнорируют. Опыт 18.09: «трафик не туннелируется вовсе» |
| Локальный SOCKS/HTTP без `VpnService` («только прокси», 6 из 11 конкурентов) | нет | **да** | нет | тот же опыт; детекта нет только потому, что VPN фактически выключен |
| **iptables REDIRECT/TPROXY + policy routing** (box_for_magisk, box4magisk, AsteriskBOX TPROXY) | **нет TUN** | нет — принудительно | **да** | работает; sing-box TPROXY-инбаунд [репозиторий: taamarin/box_for_magisk] |
| **eBPF TC + `bpf_sk_assign`** (Flux-rs; AsteriskBOX «eBPF»/«BPF2SOCKS») | **нет TUN**, «does not create a VPN, alter packets' IP addresses or ports» | нет | **да**, ядро ≥ 5.15, страница 4096, cgroup v2 | GPL-3.0-only; по UID сокета — то есть настоящий per-app [репозиторий: Chth1z/Flux-rs; Asterisk4Magisk/AsteriskBOX] |
| Сокрытие `TRANSPORT_VPN` при живом `VpnService` | — | — | root + модуль ядра | `VPN_DETECTION.md` (vpnhide) |

**Вывод для Android.** «Без `VpnService` и без прокси» — это ровно root-путь (TPROXY или eBPF), и
он у сообщества есть в нескольких зрелых реализациях. Для обычного пользователя без root
единственный принудительный захват — `VpnService`, а единственный принудительный обход —
`addDisallowedApplication`, который у нас уже стоит и который регуляторная методичка сама признаёт
недетектируемым для серверных проверок (`VPN_DETECTION.md`, 17.09). Ничего, что приложения
«уважали бы больше прокси», в Android нет: либо система заворачивает сама (VPN), либо приложение
решает само (прокси). Опция «root-режим (TPROXY)» технически доступна и лицензионно чиста
(sing-box GPL, наш GPL), но это отдельный продукт для другой аудитории — решать владельцу.

⚠️ Не проверено: отдаёт ли система `TRANSPORT_VPN` при eBPF/TPROXY-режиме (интерфейса `tun0` нет,
значит, по идее, нет и метки, но подтверждения в README Flux-rs не нашёл).

---

## 5. Что делают реальные клиенты — сводная таблица

| Клиент / инструмент | Платформа | Механизм «прямого»/принудительного режима | Свой драйвер | Подпись | Лицензия | Тип |
|---|---|---|---|---|---|---|
| Mullvad | Windows | обход по процессу: WFP callout, `ALE_BIND/CONNECT_REDIRECT` | да, `mullvad-split-tunnel.sys` | EV + attestation Microsoft (ручная операция по RELEASE.md) | GPL-3.0-or-later / MPL-2.0 | [репозиторий] |
| Proton VPN | Windows | обход по процессу + SERVFAIL на DNS мимо туннеля | да, `ProtonVPN.CalloutDriver` | не описана в README | GPL-3.0 | [репозиторий] |
| Windscribe | Windows | обход по процессу, ALE-слои | да, `WindscribeSplitTunnel.sys` | не описана | GPL-2.0 | [репозиторий] |
| AmneziaVPN | Windows | обход по процессу | **чужой** (Mullvad, переименован) | подпись Mullvad | GPL-3.0 | [репозиторий, по `REAL_APP_BYPASS.md`] |
| Proxifier v4 | Windows | захват (проксификация) по процессу, WFP callout | да | SHA-2, вендор | проприетарная | [документация] |
| ProxyCap / NetDetour | Windows | захват по процессу, WFP | да | — | проприетарная | [статья] |
| Netch | Windows | захват по процессу через NetFilter SDK (`netfilter2.sys`); TUN через wintun | чужой коммерческий | вендор SDK | клиент GPL-3.0, драйвер закрыт | [репозиторий] |
| ProxiFyre / WireSock | Windows | захват по процессу, NDIS LWF (WinpkFilter), TCP+UDP+QUIC | чужой (NT Kernel Resources) | вендор | AGPL-3.0 / драйвер: free personal, $3 000–9 000 коммерческая | [репозиторий, документация] |
| WinDivert | Windows | пакетный перехват; PID только на SOCKET/FLOW (без инжекта) | да | автор | LGPL-3.0 / GPL-2.0 | [документация] |
| NetLane | Windows | обход по процессу через `FwpmConnectionPolicyAdd0` | **нет** | — (сервис с UAC) | не указана | [репозиторий], 05.09.2026, незрелый |
| WireGuardNT | Windows | сам протокол в ядре; адаптер | да | не указана на странице | GPL-2.0 (бинари — свободнее) | [репозиторий] |
| Cloudflare WARP / One | Windows | split только по IP/CIDR/домену; по приложению — нет | — | — | проприетарная | [документация] |
| v2rayN, Clash Verge Rev, Hiddify, NekoRay, Happ, SFA | Windows | системный прокси / TUN; «Прямо» — внутри ядра | нет | — | разные | [по BACKLOG #21] |
| box_for_magisk, box4magisk, AsteriskBOX | Android | TPROXY/REDIRECT (iptables), eBPF | — | — | GPL | root [репозиторий] |
| Flux-rs | Android | eBPF TC + `bpf_sk_assign`, по UID | — | — | GPL-3.0-only | root, ядро ≥ 5.15 [репозиторий] |
| Mullvad, v2rayNG, SFA и др. | Android | `VpnService` + allowed/disallowed | — | — | — | без root, единственный путь |
| **SilentGate сейчас** | Windows / Android | системный прокси, TUN (sing-box), «только прокси»; kill switch на WFP из юзермода; `VpnService` + disallowed | **нет** | — | GPL-3.0 | — |

---

## 6. Остальные платформы — коротко

### 6.1 macOS — единственная ОС, где «прямой режим» есть как API

**`NETransparentProxyProvider`** (macOS 11+) [документация: developer.apple.com; статья: Apple DTS
«Which NetworkExtension API to use», thread 671743]: системное расширение получает **потоки
TCP/UDP всех приложений** по `NENetworkRule` (`includedNetworkRules`/`excludedNetworkRules`),
**без utun и без VPN-интерфейса**; если `handleNewFlow` вернул `false`, «the system will then
process the flow as if your proxy didn't exist» — то есть обход и захват в одном механизме и
приложение не может ни отказаться, ни заметить прокси. Ограничения: только TCP/UDP (ни ICMP, ни
raw); распространение — Developer ID + нотаризация + System Extension + значение entitlement
`app-proxy-provider-systemextension` (для Mac App Store — `app-proxy-provider`), MDM **не нужен**
[статья: Apple Developer Forums 664126]. `NEAppProxyProvider` per-app — только для управляемых
через MDM приложений. Также sing-box `redirect`-инбаунд «Only supported on Linux and macOS»
[документация: sing-box] — то есть pf-редирект как второй вариант. Для будущего этапа M9 это
меняет план `docs/platforms/MACOS.md`: захват стоит планировать через транспарентный прокси, а не
через utun.

⚠️ Не проверено: выдаёт ли Apple NE-entitlement индивидуальному Developer ID-аккаунту без
запроса (по форуму — стандартная capability, но для VPN-продуктов в App Store действует
Guideline 5.4 и требование организации, см. `docs/research/IOS_PORT.md`).

### 6.2 Linux — штатно, без драйвера и без подписи

Всё, что просит владелец, есть в ядре: **cgroup v2 + iptables/nftables TPROXY** по приложению
(cgproxy, GPL-2.0, root или `cap_net_admin`) [репозиторий: springzfx/cgproxy]; **eBPF
`cgroup/connect4`** — перезапись адреса назначения в `connect()` процессов выбранной cgroup на
локальный прокси, «completely transparent to the client» [статьи: eBPFChirp, iximiuz]; sing-box
`redirect`/`tproxy`-инбаунды и `auto_redirect` (nftables, без изменения таблицы маршрутов)
[документация: sing-box]; policy routing по `fwmark`. Нужен root/CAP_NET_ADMIN — но это обычная
цена любого VPN на Linux, а не драйвер с EV-подписью. DNS по процессу здесь тоже штатно
(cgroup видит `sendto` резолвера самого приложения, если оно не через systemd-resolved — с ним та
же история, что с `svchost`).

### 6.3 iOS — тупик

Только `NEPacketTunnelProvider` (TUN). `NEAppProxyProvider`/per-app VPN «limited to apps installed
via MDM» — нужен `VPNUUID` от MDM, тестовый `NETestAppMapping` в продакшн не годится
[статья: Apple Developer Forums 77050]. `NETransparentProxyProvider` — macOS only. Подробности и
прочие упоры — `docs/research/IOS_PORT.md`.

---

## 7. Цена своего WFP-драйвера для GPL-проекта — что добавилось к смете 17.08

Смета и четыре блокера — `REAL_APP_BYPASS.md` §6 (деньги ≈ $400–950 первый год; блокеры —
юрлицо для Partner Center, апрельская Windows Driver Policy, 14 тыс. строк чужого ядра, DNS не
решается). Здесь только то, чего там нет:

- **Лицензионно с GPL-3.0 совместимо**, если драйвер — свой код или форк Mullvad (GPL-3.0-or-later /
  MPL-2.0) или Proton (GPL-3.0). Windscribe (GPL-2.0-only) — только как отдельный бинарь, не
  форк. Драйверы NetFilter SDK и WinpkFilter — закрытые, редистрибуция по платной лицензии;
  ProxiFyre (AGPL-3.0) как код совместим (GPL-3.0 §13), но его драйвер — нет.
- **Подпись — не «на первую сборку», а на КАЖДУЮ**: Microsoft перезатирает embedded-подпись своим
  сертификатом и выдаёт новый `.cat`; без похода в Partner Center рабочего `.sys` не существует.
  Хотфикс драйвера — дни, а не минуты.
- **Attestation в документации переведён в «для тестирования»** (23.03.2026); «Attestation signed
  drivers can't be published to Windows Update for retail audiences» — сайдлоад через установщик
  остаётся, но направление Microsoft читается однозначно [документация: Driver Signing Options].
- **Обслуживание:** HVCI/Memory Integrity (у WFP-callout драйверов — известное больное место),
  Driver Verifier, стенд с kernel debugging вместо SG-Test, BSOD у пользователей = наша
  ответственность, антивирусы на `.sys` без репутации, конфликты сублоёв с другими VPN (Mullvad
  прямо пишет: «Split tunneling stops working if you have multiple applications (kernel drivers)
  that are fighting to manage new network connections»).
- **И главное — драйвер даёт захват/обход по процессу, но НЕ даёт «без прокси»** (§1) и НЕ даёт
  DNS по процессу (§3.6).

---

## 8. Что это значит для SilentGate

1. **Не писать драйвер и не грузить чужой.** Решение BACKLOG #21 подтверждается третий раз, теперь
   со стороны «захвата», а не только «обхода». Единственная лазейка без своей подписи —
   подписанный `.sys` Mullvad (путь Amnezia) — даёт только обход, требует агента с нуля и
   наследует все мины §3.6.
2. **Один опыт в VM SG-Test по `FwpmConnectionPolicyAdd0`** (`REAL_APP_BYPASS.md` §9.2, ~200 строк,
   теперь с NetLane как шпаргалкой по структурам). Это единственная работа, которая может дать
   настоящий **обход** по имени программы без драйвера — на Windows 11 и с элевированным
   помощником. Критерий тот же: убить оба ядра при живой политике — держится соединение, значит
   обход настоящий. При провале — закрыть тему и дописать в #21.
3. **Честные слова в интерфейсе.** Режим «Прямо» на Windows — это «внутри ядра», а не «мимо VPN»;
   «Только прокси» — «работает только для программ, которые сами уважают прокси». Пользователь,
   который ждёт «настоящего прямого режима», должен прочитать это до того, как проверит
   детектором.
4. **macOS (M9): планировать захват через `NETransparentProxyProvider`, а не через utun.** Это
   единственная платформа, где желание владельца — штатный API; менять `docs/platforms/MACOS.md`
   при старте этапа.
5. **Android: опционально «root-режим (TPROXY)»** для тех, у кого есть root, — технически и
   лицензионно доступно, но это другая аудитория; без решения владельца не начинать. Для
   остальных — правило «Прямо» (`addDisallowedApplication`) остаётся единственным настоящим обходом.

---

## 9. Чего я НЕ проверил

- **Ничего не запускал**: ни одного WFP-объекта, ни TUN, ни ядер — ни на хосте (правило №1), ни
  в VM (в этот заход стенд не поднимался). Всё в этом документе — чтение.
- **Перебивает ли `FwpmConnectionPolicyAdd0` TUN-маршрут с метрикой 0** — по-прежнему никто, включая
  NetLane. Минимальную версию Windows для NetLane авторы не указали.
- **Отдаёт ли Android `TRANSPORT_VPN` в eBPF/TPROXY-режимах** — в README Flux-rs/AsteriskBOX не
  сказано.
- **Механизм ProxyCap/NetDetour** — только по стороннему обзору, первичной документации вендора не
  нашёл.
- **Точную формулировку Android про `setHttpProxy`** («только рекомендация, приложения могут
  игнорировать») — страница developer.android.com отдала только навигацию; утверждение
  опирается на API-гайд и сторонние разборы плюс наш опыт 18.09.
- **Переживает ли attestation-подпись Mullvad апрельскую Windows Driver Policy** — по
  умолчанию считаю «да» (Mullvad живёт на 24H2), но это вывод, не факт.
- **Условия выдачи NE-entitlement** индивидуальному Developer ID-аккаунту для VPN-продукта.
- **Лицензия NetLane** — не указана в репозитории вовсе (код брать нельзя, только читать).

---

## 10. Источники

**Документация (вендоры ОС/ядер):**
- Microsoft, [Using Bind or Connect Redirection](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/using-bind-or-connect-redirection) — redirect-слои только для callout-драйверов
- Microsoft, [FwpmConnectionPolicyAdd0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmconnectionpolicyadd0) (ms.date 29.04.2024) — «process-based routing», поля версии пустые
- Microsoft, [Driver Signing Options](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/driver-signing-offerings) (ms.date 23.03.2026) — attestation «for testing scenarios», EV обязателен
- Microsoft, [Porting Packet-Processing Drivers and Apps to WFP](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/porting-packet-processing-drivers-and-apps-to-wfp) — TDI/LSP deprecated с Windows 8
- Microsoft, [Using Proxied Connections Tracking](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/using-proxied-connections-tracking) — модель «два сокета у прокси-службы»
- Android, [VPN guide](https://developer.android.com/develop/connectivity/vpn) — allowed/disallowed, «as if the VPN wasn't running», `allowBypass`, один VPN на профиль
- Android, [VpnService.Builder](https://developer.android.com/reference/android/net/VpnService.Builder) — `setHttpProxy` (API 29)
- Apple, [NETransparentProxyProvider](https://developer.apple.com/documentation/networkextension/netransparentproxyprovider); [Network Extensions Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension)
- sing-box, [Redirect inbound](https://sing-box.sagernet.org/configuration/inbound/redirect/) — «Only supported on Linux and macOS»; [Tun](https://sing-box.sagernet.org/configuration/inbound/tun/) — `auto_redirect` Linux only
- Proxifier, [Installation and Driver](https://www.proxifier.com/docs/win-v4/install.html)
- WinDivert, [Documentation 2.2](https://reqrypt.org/windivert-doc.html), [FAQ](https://reqrypt.org/windivert-faq.html), [README](https://www.reqrypt.org/windivert-readme.txt)
- NT Kernel Resources, [Windows Packet Filter](https://www.ntkernel.com/windows-packet-filter/), [Licensing](https://www.ntkernel.com/licensing/)
- NetFilter SDK, [главная](https://www.netfiltersdk.com/)

**Репозитории:**
- [mullvad/win-split-tunnel](https://github.com/mullvad/win-split-tunnel) — README (DNS через svchost, localhost/UDP)
- [ProtonVPN/win-app](https://github.com/ProtonVPN/win-app) — GPL-3.0 (API GitHub), README про Callout Driver
- [Windscribe/desktop-v2](https://github.com/Windscribe/desktop-v2/blob/master/backend/windows/WindscribeSplitTunnel/CalloutFunctions.h), [Windscribe/Desktop-App](https://github.com/Windscribe/Desktop-App) — GPL-2.0
- [n3tf4c3/netlane](https://github.com/n3tf4c3/netlane) — первый посторонний потребитель `FwpmConnectionPolicyAdd0`
- [wiresock/proxifyre](https://github.com/wiresock/proxifyre) — AGPL-3.0, NDISAPI
- [netchx/netch](https://github.com/netchx/netch) — ProcessMode на Netfilter
- [Zensey/split-tunnel](https://github.com/Zensey/split-tunnel) — маленький callout-драйвер policy-routing по процессу (PoC)
- [basil00/WinDivert](https://github.com/basil00/WinDivert)
- [git.zx2c4.com/wireguard-nt](https://git.zx2c4.com/wireguard-nt/about/)
- [taamarin/box_for_magisk](https://github.com/taamarin/box_for_magisk), [Asterisk4Magisk/AsteriskBOX](https://github.com/Asterisk4Magisk/AsteriskBOX), [Chth1z/Flux-rs](https://github.com/Chth1z/Flux-rs) — Android root: TPROXY/eBPF без TUN
- [springzfx/cgproxy](https://github.com/springzfx/cgproxy) — Linux cgroup + TPROXY

**Статьи (проверять критически):**
- Mullvad, [The limitations of split tunneling](https://mullvad.net/en/blog/limitations-split-tunneling)
- Microsoft Tech Community, [Removing trust for the cross-signed driver program](https://techcommunity.microsoft.com/blog/windows-itpro-blog/advancing-windows-driver-security-removing-trust-for-the-cross-signed-driver-pro/4504818) (26.03.2026)
- Apple Developer Forums: [Which NetworkExtension API to use](https://developer.apple.com/forums/thread/671743), [Developer ID PP for app with Network Extension](https://developer.apple.com/forums/thread/664126), [Must NEAppProxyProvider be used with MDM](https://developer.apple.com/forums/thread/77050)
- Cloudflare, [Split Tunnels](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/configure/route-traffic/split-tunnels/) — только IP/CIDR/домен
- [proxytool.app — обзор проксификаторов](https://proxytool.app/blog/best-proxy-client-for-windows) — ProxyCap/NetDetour (вторичный источник)
- [eBPFChirp — Transparent Proxy with eBPF](https://ebpfchirp.substack.com/p/transparent-proxy-implementation), [iximiuz — Transparent Egress Proxy with eBPF](https://labs.iximiuz.com/tutorials/ebpf-envoy-egress-dc77ccd7)
- [android-proxy-setup](https://github.com/wordstotech-design/android-proxy-setup) — прокси Wi-Fi игнорируется сырыми сокетами
- Apriorit, [User Mode and Driver Mode Techniques](https://www.apriorit.com/dev-blog/688-driver-controlling-and-monitoring-networks-with-user-mode-and-driver-mode-techniques)
