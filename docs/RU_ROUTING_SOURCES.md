# Маршрутизация РФ: источники гео-списков и что можно настроить в панели

Справка для настройки правил маршрутизации **на стороне Remnawave**, чтобы они приезжали
в клиент внутри XRAY_JSON-подписки. Клиент применяет конфиг панели как есть, поэтому всё,
что описано ниже, настраивается в шаблоне панели без правок приложения.

> Цель типового сценария: **российские сайты, банки и госуслуги — напрямую**, остальное — через VPN.
> Это и быстрее (не гоняем локальный трафик за границу), и не ломает сервисы, которые
> блокируют иностранные IP.

---

## ⚠️ Главное ограничение: категории должны быть в гео-файлах КЛИЕНТА

Xray резолвит `geosite:…` / `geoip:…` по файлам `geosite.dat` / `geoip.dat` **на устройстве**,
а не по данным панели. SilentGate поставляет **официальные** файлы из релиза
[XTLS/Xray-core](https://github.com/XTLS/Xray-core) (`tools/fetch-xray.ps1`).

Если шаблон панели сошлётся на категорию, которой в этих файлах нет, **ядро не запустится**
и подключение упадёт. Проверено на нашей сборке (`xray run -test`, Xray 26.3.27):

| Категория | В наших файлах |
|---|---|
| `geoip:ru`, `geoip:private`, `geoip:cn` | ✅ есть |
| `geoip:telegram`, `geoip:google`, `geoip:netflix`, `geoip:cloudflare` | ✅ есть |
| `geosite:category-ru` (рос. сайты), `geosite:category-gov-ru` (госуслуги) | ✅ есть |
| `geosite:category-media-ru`, `geosite:category-ads-all` | ✅ есть |
| `geosite:vk`, `geosite:mailru`, `geosite:ozon`, `geosite:wildberries`, `geosite:yandex` | ✅ есть |
| `geosite:ru-blocked`, `geosite:refilter`, `geoip:ru-blocked`, `geoip:re-filter` | ❌ **нет** |
| `geosite:sberbank`, `geosite:tinkoff`, `geosite:vtb`, `geosite:category-finance-ru` | ❌ **нет** |

**Вывод:** сценарий «РФ напрямую, остальное через VPN» настраивается **прямо сейчас**, без
изменений в клиенте — на `geoip:ru` + `geosite:category-ru` + `geosite:category-gov-ru`.
Отдельной категории банков в официальных файлах нет: они покрываются `category-ru`
(домены в зоне .ru и российские сервисы), либо перечисляются доменами явно.

Хотите категории вроде `ru-blocked` / `refilter` / отдельных банков — нужно заменить гео-файлы
в клиенте (см. «Если нужны расширенные списки»).

---

## Готовый шаблон правил для панели (работает с текущим клиентом)

Вставляется в `routing.rules` XRAY_JSON-шаблона Remnawave. Порядок важен — правила
проверяются сверху вниз, срабатывает первое подходящее.

```json
"routing": {
  "domainStrategy": "IPIfNonMatch",
  "rules": [
    { "type": "field", "protocol": ["bittorrent"], "outboundTag": "direct" },

    { "type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block" },

    { "type": "field",
      "domain": ["geosite:category-ru", "geosite:category-gov-ru",
                 "geosite:yandex", "geosite:vk", "geosite:mailru",
                 "geosite:ozon", "geosite:wildberries"],
      "outboundTag": "direct" },

    { "type": "field", "ip": ["geoip:ru", "geoip:private"], "outboundTag": "direct" },

    { "type": "field", "network": "tcp,udp", "outboundTag": "proxy" }
  ]
}
```

`domainStrategy: "IPIfNonMatch"` нужен, чтобы правило `geoip:ru` срабатывало и для доменов:
без него IP-правила не применяются к доменным запросам.

Для профилей «Авто …» (с `balancers`) последнее правило вместо `outboundTag` использует
`balancerTag` — как уже сделано в ваших профилях.

---

## Источники списков (для расширенных сценариев)

| Проект | Что даёт | Формат |
|---|---|---|
| [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) | Готовые `geoip.dat`/`geosite.dat` c РФ-категориями: `ru-blocked`, `ru-blocked-all` (~700k доменов), `ru-available-only-inside`, `refilter`, `antifilter-download`, `ru-whitelist`; плюс ASN-категории (`cloudflare`, `google`, `telegram`, `yandex`, `ddos-guard`…). Обновляется **каждые 6 часов** | `.dat` (замена файлов клиента) |
| [runetfreedom/russia-blocked-geosite](https://github.com/runetfreedom/russia-blocked-geosite) · [russia-blocked-geoip](https://github.com/runetfreedom/russia-blocked-geoip) | Исходники предыдущего: домены и подсети, заблокированные РКН | `.dat`, MaxMind `.mmdb`, sing-box `.srs`, nginx allow/deny |
| [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains) | **Russia inside** — заблокированное внутри РФ; **Russia outside** — российские ресурсы, доступные только с РФ-адресов (то, что нужно вести `direct`) | `.lst`, dnsmasq ipset/nfset, ClashX, Kvas, sing-box `.srs`, mihomo `.mrs` |
| [1andrevich/Re-filter-lists](https://github.com/1andrevich/Re-filter-lists) | Re:filter — популярный список заблокированного в РФ | `.dat`, `.srs`, текстовые |
| [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) | Классические расширенные `geosite`/`geoip` (ориентирован на CN, но содержит общие категории) | `.dat` |
| [runetfreedom/russia-v2ray-custom-routing-list](https://github.com/runetfreedom/russia-v2ray-custom-routing-list) | Готовые JSON-правила маршрутизации под перечисленные категории | JSON |

Прямые ссылки на файлы `runetfreedom` (ветка `release`, обновление раз в 6 часов):

```
https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat
https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat
```

---

## Если нужны расширенные списки

Чтобы панель могла ссылаться на `geosite:ru-blocked` и т. п., клиент должен получить те же
гео-файлы. Порядок:

1. Заменить источник в `tools/fetch-xray.ps1`: `xray.exe` по-прежнему из релиза XTLS,
   а `geoip.dat`/`geosite.dat` — по ссылкам `runetfreedom` выше.
2. Пересобрать/переустановить клиент (файлы лежат в `engine/windows/bin/`, рядом с `xray.exe`;
   путь передаётся ядру через `XRAY_LOCATION_ASSET`).
3. Только после этого добавлять новые категории в шаблон панели.

⚠️ Порядок именно такой: если панель начнёт отдавать неизвестную клиенту категорию раньше,
чем обновятся файлы, **у всех пользователей перестанет подключаться VPN** — ядро откажется
стартовать с неизвестной категорией. Безопасная альтернатива на переходный период —
перечислять домены явно (`"domain": ["domain:sberbank.ru", "domain:gosuslugi.ru"]`),
это не требует гео-файлов вообще.

---

## Проверить перед раскаткой

Сгенерированный панелью конфиг всегда можно проверить локально — ошибка вылезет сразу:

```
xray.exe run -test -c config.json     # с XRAY_LOCATION_ASSET на папку с .dat
```

В приложении: ПКМ по серверу → «JSON config» показывает то, что реально пришло от панели,
а Настройки → «Логи» — что ответила панель и чем закончилось подключение.
