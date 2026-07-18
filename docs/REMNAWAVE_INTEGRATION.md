# Интеграция с Remnawave и авторизация через Telegram

Как SilentGate работает с вашей существующей инфраструктурой (панель Remnawave, Telegram-боты, сайт).

---

## 1. Что уже есть у вас (из соседних проектов)

- Панель **Remnawave** (`silentgate.lol:8443`): API `/api/users`, `/api/hosts`, `/api/subscription-templates` (шаблоны `XRAY_JSON`).
- Раздача подписок: `sub.silentgate.lol/sub/<token>`.
- Сайт уже генерирует deep-link'и для сторонних клиентов:
  `happ://add/…`, `v2raytun://import/…`, `streisand://import/…` (см. `VPN_BOT/Site/app.py`).
- Telegram-боты на Python с платежами (YooKassa/Platega/Cryptobot) и метриками (Prometheus/Grafana).

**Вывод:** SilentGate становится ещё одним клиентом той же подписки — панель менять не нужно.
Приложение регистрирует свою схему `silentgate://` рядом с существующими.

---

## 2. Формат подписки (что парсит приложение)

Стандарт экосистемы Xray (тот же, что у v2rayNG/Happ/v2RayTun):

- **Тело ответа** = base64( список share-ссылок через `\n` ):
  `vless://…`, `vmess://…`, `trojan://…`, `ss://…`. Парсер — [share_link_parser.dart](../app/lib/core/parser/share_link_parser.dart).
- **Заголовки ответа** (мета) — уже реализован разбор в [subscription_info.dart](../app/lib/core/models/subscription_info.dart):

| Заголовок | Назначение | Этап |
|---|---|---|
| `profile-title` | Название подписки (может быть base64) | M2 |
| `subscription-userinfo` | `upload=…; download=…; total=…; expire=…` (байты, unix) → трафик/срок | M2 |
| `profile-update-interval` | Часы автообновления | M2 |
| `announce` / `announce-url` | Объявление провайдера (плашка + ссылка) | M2 |
| `routing` | base64-JSON правил маршрутизации от панели (приоритет над локальными) | M4 |

**Заголовки запроса от приложения** (совместимость с device-limit Remnawave) — уже отправляются:
`User-Agent: SilentGate/…`, `X-Device-OS`, `X-App-Version`; добавить `X-HWID`, `X-Device-Model` на M2.

> Совет по панели: Remnawave отдаёт разный контент по `User-Agent`. Убедитесь, что для UA `SilentGate/*`
> отдаётся base64-список share-ссылок (как для v2rayNG), а не clash/sing-box JSON.

---

## 3. Deep links (сайт/бот → приложение)

Зарегистрировать схему `silentgate://` (на Windows — ключ реестра; на Android — intent-filter; на iOS — URL types):

- `silentgate://import-sub?url=<sub_url>` — импорт подписки одним нажатием (зеркало `v2raytun://import-sub`).
- `silentgate://auth?token=<app_token>` — возврат после Telegram-авторизации (см. ниже).

На сайте достаточно добавить кнопку рядом с существующими Happ/v2RayTun:
```
<a href="silentgate://import-sub?url=https://sub.silentgate.lol/sub/{token}">Открыть в SilentGate</a>
```
Разбор уже реализован в [app_state.dart](../app/lib/state/app_state.dart) (`_extractSubUrl`).

---

## 4. Авторизация через Telegram-бота (этап M6)

**Схема (без паролей, привязка к существующему боту):**

```
Приложение                         Бот (Python)                    Remnawave
    │  генерирует nonce                                                │
    │  открывает t.me/SilentGateBot?start=<nonce> ──────▶ /start       │
    │                                    resolve nonce→telegram_id     │
    │                                    найти/создать юзера ──────────▶ POST /api/users
    │                                    получить sub URL     ◀─────────  { subscriptionUrl }
    │                                    сохранить (nonce→token+subURL) │
    │  poll /app/auth?nonce=…  или  deep link silentgate://auth?token= │
    │  ◀── { app_token, subscription_url } ────────────                │
    │  сохранить sub URL → готово к подключению                        │
```

**Что реализовать на бэкенде (Python, ваш стек):**
1. Эндпоинт создания сессии: приложение → `POST /app/session` → `{ nonce, deeplink: "t.me/bot?start=<nonce>" }`.
2. В боте обработчик `/start <nonce>`: связать `nonce` ↔ `telegram_user_id`, получить/создать Remnawave-юзера,
   его sub URL, выписать `app_token`, сохранить `nonce → {app_token, sub_url}`.
3. Эндпоинт обмена: приложение поллит `GET /app/session/<nonce>` → когда готово, отдать `{app_token, sub_url}`.
4. `app_token` — долгоживущий, хранится в приложении (позже — в защищённом хранилище платформы).

**Альтернатива для сайта:** Telegram Login Widget с проверкой HMAC-SHA256 подписи (ключ = токен бота) — стандартно на Python.

**Коммерция:** оплата/продление остаются в боте и на сайте. Приложение в MVP только показывает статус
(тариф, срок, трафик) и ведёт на бота кнопкой «Продлить». На iOS **не** ссылаться на покупки из приложения
(иначе Apple потребует IAP 15–30%).

---

## 5. Защита подписки от перепродажи (этап M6, опционально)

По образцу «crypto links» Happ: sub URL шифруется ключом, встроенным в приложение, и распространяется
как `silentgate://crypt/<encrypted>`. Пользователь не может извлечь исходную ссылку подписки и передать её.
Remnawave уже умеет генерировать Happ-crypto-links — можно сделать аналог для своей схемы.

---

## 6. Порядок внедрения

1. **M1 (сейчас):** ручной импорт sub URL — уже работает.
2. **M2:** заголовки подписки (трафик/срок/автообновление) + `X-HWID`.
3. **M6:** Telegram-авторизация (бэкенд-эндпоинты + обработчик бота) и deep links.
4. Позже: crypto-links, panel-routing (`routing` header), fallback-домены подписки.
