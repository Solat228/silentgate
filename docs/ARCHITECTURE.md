# Архитектура SilentGate

Общая для всех платформ. Платформо-специфика вынесена в `docs/platforms/<PLATFORM>.md`.

---

## 1. Принцип: UI ↔ движок разделены

```
┌─────────────────────────────────────────────┐
│  Flutter-приложение (Dart) — общий код        │
│                                               │
│  ┌────────┐   ┌────────┐   ┌───────────────┐  │
│  │  UI    │──▶│ state  │──▶│  core (логика) │  │
│  │ экраны │◀──│ (стор) │◀──│  подписки,     │  │
│  └────────┘   └────────┘   │  Xray-конфиг   │  │
│                            └───────┬───────┘  │
│                     engine (интерфейс VpnEngine)│
└─────────────────────────────┬─────────────────┘
                              │ platform channel / process
              ┌───────────────┴───────────────────┐
              ▼                ▼                   ▼
   Windows/macOS/Linux     Android              iOS
   xray.exe (subprocess)   VpnService +         NEPacketTunnelProvider +
   + системный прокси      libXray AAR          libXray.xcframework
                           (in-process)         (Swift, in-extension)
```

**Ключевая идея:** движок (Xray) всегда изолирован от UI. UI знает только абстракцию `VpnEngine`
(connect/disconnect/статус/статистика). Реализация под платформу подставляется через conditional imports.

### 1.1. Два прокси-ядра (с v0.9.0)

Xray не поддерживает **Hysteria2** (QUIC со своим управлением перегрузкой) и не планирует.
Такие серверы поднимает **sing-box**, который и так есть в комплекте ради TUN.

```
                       VpnServer.core
              ┌──────────────┴──────────────┐
              ▼                             ▼
      ProxyCore.xray                 ProxyCore.singbox
      xray.exe run -c                sing-box.exe run -c
      socks 10808 / http 10809       mixed 10808 / mixed 10809   ← ТЕ ЖЕ порты
      статистика: api statsquery     статистика: Clash API /connections
```

Порты совпадают намеренно: системный прокси, TUN-роутер и проверка занятости портов не должны
знать, какое ядро внизу. TUN-инстанс sing-box — это **третий**, отдельный процесс (с правами
администратора), он просто заворачивает трафик в локальный socks и к выбору ядра отношения не имеет.

Лицензии: Xray — MPL-2.0 (можно линковать), sing-box — GPL, поэтому **только отдельным
процессом, без линковки** (см. CLAUDE.md).

---

## 2. Слои Dart-кода (`app/lib/`)

| Слой | Папка | Ответственность |
|---|---|---|
| **core** | `lib/core/` | Чистая логика без платформы: модели серверов, парсер share-ссылок (`vless://`…), генератор Xray-JSON, разбор заголовков подписки. **Полностью переиспользуется на всех платформах.** |
| **data** | `lib/data/` | Хранилище (подписка, выбранный сервер, настройки), HTTP-клиент к подписке/Remnawave. |
| **engine** | `lib/engine/` | Интерфейс `VpnEngine` + реализации: `windows/`, `android/`, `ios/`, `macos/`, `linux/`. Выбор через `engine_factory.dart` (conditional import). |
| **state** | `lib/state/` | Состояние приложения (ChangeNotifier/Provider): текущий статус, список серверов, трафик. |
| **ui** | `lib/ui/` | Экраны (home, import, servers, settings) и виджеты. |

Правило зависимостей: `ui → state → core/data/engine`. `core` не зависит ни от чего платформенного.

---

## 3. Интерфейс движка `VpnEngine`

```dart
abstract class VpnEngine {
  Stream<VpnStatus> get status;          // disconnected/connecting/connected/error
  Stream<TrafficStats> get stats;        // upload/download байты, скорость
  Future<void> connect(XrayConfig config);
  Future<void> disconnect();
  Future<int> ping(VpnServer server);    // latency-тест (позже — через ядро)
}
```

- **Windows/desktop:** реализация запускает `xray.exe -c config.json`, поднимает локальные inbound'ы
  (SOCKS 127.0.0.1:10808, HTTP 127.0.0.1:10809), ставит системный прокси, тянет статистику по gRPC StatsService ядра.
- **Android:** через MethodChannel вызывает Kotlin `VpnService`, который через AAR (libXray) стартует ядро
  и отдаёт TUN-fd в native tun-inbound Xray.
- **iOS:** через MethodChannel управляет `NETunnelProviderManager`; ядро крутится в Swift-extension.

---

## 4. Поток данных: от подписки до подключения

```
Remnawave sub URL
   │  (HTTP GET с заголовками X-HWID, X-Device-OS, User-Agent)
   ▼
Тело = base64( vless://...\n vless://...\n trojan://... )
   │  + заголовки ответа: profile-title, subscription-userinfo (трафик/срок),
   │    profile-update-interval, announce, routing
   ▼
core/subscription  → List<VpnServer> + SubscriptionInfo
   │
   ▼  пользователь выбрал сервер
core/xray/XrayConfigBuilder(server) → Xray JSON (inbounds + outbound + routing + dns)
   │
   ▼
engine.connect(config) → xray.exe / VpnService / NE
   │
   ▼
Системный прокси / TUN → трафик идёт через сервер
```

Формат подписки и заголовки — стандарт экосистемы (тот же, что парсит v2rayNG и потребляют Happ/v2RayTun).
Детали — [REMNAWAVE_INTEGRATION.md](REMNAWAVE_INTEGRATION.md).

---

## 5. Авторизация через Telegram (общая схема)

```
Приложение → «Войти через Telegram» → открывает t.me/SilentGateBot?start=<nonce>
   Бот (Python): nonce → telegram_user_id → находит/создаёт юзера в Remnawave (API)
        → отдаёт per-user sub URL + app-токен на бэкенд
   Приложение получает токен (deep link silentgate://auth?token=… или поллинг)
        → сохраняет sub URL → готово к подключению
```

Вся коммерция/entitlement остаётся в боте и панели; приложение в MVP «тупое»: токен → подписка → подключение.
Это же обходит сложности Apple IAP на старте (покупки — в боте/на сайте, из iOS-сборки на них не ссылаться).

---

## 6. Обход блокировок (заложить с самого начала)

- **VLESS + Reality** — основной транспорт (RKN-стойкость ~98–99% по замерам сообщества).
- **Панель-управляемый `routing`** — заголовок подписки с base64-JSON правил маршрутизации (как у v2RayTun).
- **Fragment / noise** — DPI-обход через параметры URI (`fragment=`, `noises=`) — заложить в парсер.
- **Fallback-домены подписки** — замена заблокированного домена подписки (как domain-replacement у Happ/v2RayTun).

---

## 7. Хранение секретов

- Sub URL и app-токен — в защищённом хранилище платформы (`flutter_secure_storage`:
  Windows DPAPI / Android Keystore / iOS Keychain).
- Позже — «крипто-ссылки» по образцу Happ: sub URL шифруется ключом, встроенным в приложение,
  чтобы пользователь не мог извлечь и перепродать подписку.
