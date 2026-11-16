# Локальный API для автоматизации

Windows-клиент умеет поднимать HTTP-API на `127.0.0.1`: читать состояние, переключать сервер/подписку,
настраивать и проверять локальные порты выходов и отправлять трафик через конкретный выход прямо из
скрипта — без интерфейса. Раздел настроек — **Настройки → API для автоматизации**.

⚠️ Документ описывает то, что реально делает код (`core/net/api_ports.dart`,
`core/net/api_server.dart`, `state/api_handlers.dart`).

## Границы

* **Только Windows.** `AppState.applyApiSettings` гейтится буквальным `Platform.isWindows`. На
  Android локальные порты видит любое установленное приложение, отдельная модель угрозы для этого
  ещё не проработана — правило проекта: где нет изоляции, канал не поднимается вовсе.
* **Только loopback.** Слушатели биндятся на `InternetAddress.loopbackIPv4` — с другой машины в
  сети до них не достучаться, даже зная токен.
* **Управляющий порт всегда защищён `Bearer <apiToken>`.** Даже если на прокси-портах выходов выбран
  режим без пароля (`apiProxyAuthMode = none`), HTTP-API на `127.0.0.1:10870` никогда не поднимается
  с пустым токеном и требует `Authorization: Bearer <токен>` на каждый запрос.

## 1. Раскладка портов

```dart
// core/net/api_ports.dart (значения по умолчанию, настраиваются в AppSettings)
control     = 10870              // управляющий HTTP-API (apiControlPort)
auto        = 10818              // «Умный Автовыбор» (urltest по пулу, apiAutoPort)
direct      = 10819              // «Прямо» — мимо VPN, реальный IP (apiDirectPort)
firstServer = 10820              // первый порт диапазона серверов
maxServers  = 250                // до 250 одновременных серверов с отдельным портом
```

| Порт | Что это |
|---|---|
| `10870` | Управляющий HTTP-API — статус, серверы, подписки, выходы, подключение, пинг, проверка портов |
| `10818` | «Умный Автовыбор» (`mixed` SOCKS5+HTTP) — балансировщик `urltest` по выбранному пулу серверов |
| `10819` | «Прямо» (`mixed` SOCKS5+HTTP) — трафик идёт мимо VPN реальным IP |
| `10820…10854`, `10856…10869`, `11200…11400` | До `250` `mixed`-портов под выбранные серверы и профили «Авто» (автоматически обходятся зарезервированные `10855` релея БС, `10870` API и `10910…11199` мостов Xray) |

### Закреплённые (sticky) порты и ручное назначение

С версии `1.18.7` раскладка портов **закрепляется за сервером** (`AppSettings.apiAssignedPorts`):

* когда серверу впервые выдаётся порт, номер сохраняется в `apiAssignedPorts` и **не сдвигается**,
  если позже добавить или снять галочку у соседнего сервера;
* любому серверу можно задать конкретный свободный порт вручную (`1024…65535`, кроме зарезервированных
  системных портов ядра) в интерфейсе или через `POST /v1/exits/configure`;
* при чистом вызове `ApiPorts.forServer(keys, key)` без карты `assignedPorts` сохраняется прежнее
  детерминированное распределение по отсортированному списку ключей из пула `allocateServerPortPool`.

Несмотря на закрепление портов, в скриптах рекомендуется читать актуальный порт из `GET /v1/exits`
(или использовать `sg.proxies_for(...)` в `tools/silentgate.py`).

## 2. Включение, токен и режимы авторизации прокси-портов

Тумблер **выключен по умолчанию**. Пустой `apiToken` означает, что **канал не поднимается вовсе**
(`LocalApiServer.start()` возвращает `false` до попытки `bind`).

Для прокси-портов выходов (`10818`, `10819` и портов серверов) доступны три режима авторизации
(`AppSettings.apiProxyAuthMode`):

1. **`token` (по умолчанию)** — логин `sg`, пароль равен `apiToken`.
2. **`none` (без пароля на `127.0.0.1`)** — для локальных программ, антидетект-браузеров и библиотек,
   не умеющих передавать логин/пароль SOCKS5/HTTP. Слушатель остаётся строго на `127.0.0.1`.
3. **`custom` (свой логин и пароль)** — отдельные креды `apiProxyCustomUser` / `apiProxyCustomPassword`
   для прокси-портов, не раскрывающие управляющий `apiToken`.

### Профили «Авто», XHTTP и дедупликация мостов

* Обычные серверы (`VLESS`, `Trojan`, `Shadowsocks`, `Hysteria2`, `SOCKS`, `HTTP`) поднимаются нативно
  внутри `sing-box`.
* Панельные профили «Авто» (`rawPanelConfig` с собственным балансировщиком `leastPing` /
  `burstObservatory`) и узлы `XHTTP` поднимаются через локальные loopback-мосты Xray (`10910…11199`).
  Идентичные прокси-outbound'ы внутри нескольких профилей «Авто» автоматически **дедуплицируются**
  (`exit-sh-*`), чтобы Xray не открывал десятки дублирующих соединений и проб к одним и тем же
  серверам при выборе «Все Авто».
* Опция **«Автоматически выдавать порты всем профилям Авто»** (`apiAutoIncludeAutoProfiles`)
  автоматически назначает отдельные порты всем панельным и виртуальным профилям «Авто» (включая новые
  при обновлении подписки).

### Пул «Умного Автовыбора» (`10818`) и DNS через выход

* Порт `10818` (`apiAutoPortEnabled`) балансирует трафик через `urltest` (настраиваемые `apiUrltestUrl`
  и `apiUrltestIntervalSec`) по выбранному пулу `apiAutoPool`:
  * `allSubscriptions` (по умолчанию) — все подходящие серверы всех подписок;
  * `activeSubscription` — серверы активной подписки;
  * `selectedExits` — только отмеченные серверы с отдельным портом.
  Платежные/дорогие узлы (`x10`, `оплат`) автоматически исключаются из автопула, пока есть обычные узлы.
* При включённом `apiDnsViaExit` (включено по умолчанию) DNS-запросы каждого порта выхода идут через
  **его собственный выход**, исключая утечку DNS и гео-несовпадение при одновременной работе через
  разные страны.

## 3. Все режимы захвата и фоновый режим без VPN

С версии `1.18.7` порты выходов API (`ApiPorts.exitPortsExistIn` = `true` для всех `CaptureMode`)
работают **во всех трёх режимах захвата**:

* **`CaptureMode.tun` (Обычное подключение / TUN)** — порты выходов и `10818`/`10819` поднимаются
  внутри основного TUN-процесса `sing-box` (плюс вспомогательный `xray` для мостов «Авто»/XHTTP, если
  основное ядро — не Xray).
* **`CaptureMode.systemProxy` (Системный прокси)** — параллельно основной сессии поднимается лёгкий
  фоновый маршрутизатор выходов (`ExitRouterConfigBuilder` на `sing-box` + мосты Xray при необходимости),
  не трогающий настройки WinINET для остальных программ.
* **`CaptureMode.proxyOnly` (Только прокси)** — поднимаются локальные прокси-порты `10808`/`10809` и
  все порты API без TUN-адаптера и без записи в системный прокси Windows.
* **Фоновый режим при выключенном VPN (`apiKeepAliveWhenDisconnected`)** — если включена опция
  «Держать порты API активными при выключенном VPN», отдельный `ExitRouter` держит порты `10818`,
  `10819` и порты выбранных серверов открытыми даже тогда, когда основная кнопка VPN выключена
  (`disconnected`), и бесшовно передаёт их основной сессии при подключении.

## 4. Аутентификация и заголовки управляющего API

* `Authorization: Bearer <токен>` — обязателен на КАЖДЫЙ запрос к управляющему API (`10870`).
  Сравнение — в постоянное время.
* Заголовок `Origin` в запросе или метод `OPTIONS` → **`403 browser_not_allowed`** ещё до проверки
  токена. Заголовков `Access-Control-Allow-*` сервер не выставляет никогда.
* Ответ — всегда JSON, `Content-Type: application/json`.
* Невалидный JSON или JSON не-объект в теле `POST` → `400 bad_request` (пустое тело допустимо для
  вызовов без параметров).

## 5. Эндпоинты

Базовый URL по умолчанию: `http://127.0.0.1:10870/v1`.

### `GET /v1/status` (и `?verify=1`)

Возвращает состояние движка, режим захвата, настройки портов API и режим авторизации прокси-портов
(`proxyAuthMode`: `"token"` | `"none"` | `"custom"`). При `?verify=1` добавляет поле `egress`
с проверкой реального выходного IP машины мимо локальных прокси.

### `GET /v1/servers` (и `?scope=all`)

* Без параметров — список серверов активной витрины (`AppState.servers`).
* `?scope=all` — все серверы **всех подписок** без дублей с полями `subscriptionId`,
  `subscriptionTitle`, `isAutoProfile`, `canBeExit` и назначенным `exitPort` (если есть).

### `GET /v1/exits` (и `?verify=1`)

Возвращает все активные локальные порты выходов:

* запись `kind: "auto"` (`name: "Умный Автовыбор"`, `port: 10818`), если включён порт автовыбора;
* записи `kind: "server"` (`serverKey`, `name`, `country`, `subscriptionId`, `subscriptionTitle`,
  `isAutoProfile`, `pinnedPort`, `port`, `listening`, `authMode`);
* запись `kind: "direct"` (`name: "Прямо"`, `port: 10819`), если включён порт прямого выхода.

При `?verify=1` дополнительно проверяет прохождение трафика и выходной IP через каждый поднятый порт.

### `POST /v1/exits/configure`

Программное управление составом серверов с отдельным портом и настройками выходов без открытия UI:

```bash
# Включить автовыдачу всем Авто-профилям и добавить серверы:
curl -s -X POST http://127.0.0.1:10870/v1/exits/configure \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"autoIncludeAutoProfiles": true, "addServers": ["srv-..."], "assignPorts": {"srv-...": 10825}}'
```

Поддерживаемые поля тела: `mode` (`"all_auto"` | `"all_servers"` | `"clear"`), `servers` (заменить
список), `addServers`, `removeServers`, `assignPorts` (`{"srv-...": 10825}` или `null` для сброса
ручного порта), `autoPortEnabled`, `directPortEnabled`, `autoIncludeAutoProfiles`,
`keepAliveWhenDisconnected`, `autoPool` (`"allSubscriptions"` | `"activeSubscription"` |
`"selectedExits"`). При необходимости автоматически перезапускает фоновый маршрутизатор или живую
сессию.

### `POST /v1/exits/test`

Проверяет задержку (`latencyMs`) и реальный выходной IP/страну конкретного порта (`{"port": 10818}`
или `{"server": "srv-..."}`), либо всех активных портов сразу (`{}`).

### `GET /v1/subscriptions`

Возвращает список всех подписок (`id` вида `sub-...`, `title`, `active`, `isLocal`, `serversCount`,
`usedBytes`, `totalBytes`, `unlimited`, `expiresAt`, `updatedAt`) без раскрытия секретного URL подписки.

### `POST /v1/subscriptions/select` и `POST /v1/subscriptions/refresh`

* `POST /v1/subscriptions/select` с `{"id": "sub-..."}` или `{"title": "..."}` переключает активную
  подписку.
* `POST /v1/subscriptions/refresh` с `{"id": "sub-..."}` или `{"all": true}` обновляет одну или все
  удалённые подписки.

### `GET /v1/traffic`, `GET /v1/subscription`, `POST /v1/connect`, `POST /v1/disconnect`, `POST /v1/ping`

Работают полностью совместимо с предыдущими версиями:

* `GET /v1/traffic` — суммарные `uplinkBytes` / `downlinkBytes` за время работы приложения.
* `GET /v1/subscription` — остаток и срок активной подписки.
* `POST /v1/connect` — `{"server": "srv-..."}`, `{"name": "..."}` или `{"auto": true}` (на живом
  канале меняет сервер без выключения VPN; ищет сервер по всем подпискам).
* `POST /v1/disconnect` — идемпотентное отключение основного VPN.
* `POST /v1/ping` — мгновенный запуск асинхронного пинга серверов.

## 6. Коды ответов и барьер секретов

| Код | Когда |
|---|---|
| `200` | Успех |
| `400 bad_request` | Тело POST — не JSON или не JSON-объект |
| `401 unauthorized` | Заголовка `Authorization` нет либо токен неверный |
| `403 browser_not_allowed` | В запросе есть заголовок `Origin`, либо метод `OPTIONS` |
| `404 not_found` | Неизвестный путь |
| `409 <code>` | Команда неприменима: `server_not_found`, `ambiguous_name`, `server_required`, `subscription_not_found`, `port_invalid`, `api_disabled` |
| `500 internal` | Внутренняя ошибка (в том числе — сработавший барьер секретов `assertNoSecrets`) |

Тело каждого ответа на границе `LocalApiServer` проходит через `assertNoSecrets`
(`core/net/api_secrets.dart`): `apiToken`, `localProxyPassword`, `localProxyUser`,
`apiProxyCustomPassword`, `subscriptionUrl`, `rawJsonOverride`, `rawPanelConfig` и сырые ссылки
прокси-протоколов никогда не покидают сокет.

## 7. `tools/silentgate.py`

Обёртка на Python (`requests`):

```python
from silentgate import SilentGate
import requests

sg = SilentGate(token="...", proxy_user="sg", proxy_password="...")  # или proxy_auth=False для режима без пароля
print(sg.status())

# Включить все профили «Авто» одной командой:
sg.configure_exits(mode="all_auto", keep_alive_when_disconnected=True)

# Прокси для «Умного Автовыбора» (10818), конкретного сервера и прямого выхода (10819):
r_auto = requests.get("https://api.ipify.org?format=json", proxies=sg.proxies_for_auto())
de = next(s["key"] for s in sg.servers(scope="all") if s["country"] == "DE")
r_de = requests.get("https://api.ipify.org?format=json", proxies=sg.proxies_for(de))
r_direct = requests.get("https://api.ipify.org?format=json", proxies=sg.proxies_for(None))
```
