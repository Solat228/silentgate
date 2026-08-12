# iOS — план и фичи (этап M8) 🔒

Самый сложный этап. Начинать после Windows и Android. Заблокирован внешним: нужен аккаунт
Apple Developer типа **Organization** (юрлицо).

> ⚠️ **ЧИТАТЬ ПЕРВЫМ: `docs/research/IOS_PORT.md`** — разведка от 12.08.2026 по первоисточникам
> Apple. Главное оттуда: **раздельного туннелирования по приложениям на iOS не существует**
> (`appRules` и `forPerAppVPN` помечены `API_UNAVAILABLE(ios)` прямо в заголовках SDK; в обычном
> режиме туннелю вообще не сообщают владельца пакета) — экран «по приложениям» надо не портировать
> с ограничениями, а **скрывать целиком**. Там же: почему бесплатный сайдлоад VPN-клиента невозможен
> в принципе, почему SideStore конструктивно конфликтует с нашим приложением, почему DMA-магазины
> бесполезны для аудитории РФ/СНГ, и почему **sing-box нельзя вести в App Store** (GPL против
> условий магазина, исключение по §7 они добавлять отказались) — а Xray под MPL можно.
> И одна хорошая новость: готовый ограничитель памяти из sing-box нам заимствовать **можно**,
> потому что мы под GPL-3.0, а Xray-core — не может.

---

## Стек

- UI: общий Flutter-код. **Flutter живёт только в основном приложении.**
- Туннель: нативный Swift **`NEPacketTunnelProvider`** (app extension) — Dart в extension не работает.
- Ядро: **Xray-core** через **`libXray.xcframework`** (gomobile/cgo), линкуется в extension.
- TUN: fd из NE → native tun-inbound Xray (`xray.tun.fd`) или `hev-socks5-tunnel` (C).
- Связь app ↔ extension: `NETunnelProviderManager` + `sendProviderMessage` + App Group (общий контейнер).

Образец формы (Flutter + Go-ядро + нативный NE): **Hiddify** (`ios/HiddifyPacketTunnel/…`, App Group).

---

## Критичные ограничения

- **Лимит памяти NE ~50 МБ** (с iOS 15; исторически 15 МБ; на части iOS 17 бывает строже, ~15 МБ).
  Xray потребляет больше sing-box → обязательно: обрезка/разделение geoip/geosite, GC libXray раз/сек,
  `GOMEMLIMIT`, отключение статистики, C-tun2socks. **Проверять на реальных устройствах как можно раньше** —
  если Xray не влезает стабильно, это главный риск платформы.
- **Guideline 5.4:** только NetworkExtension API, аккаунт Organization, декларация сбора данных.
- **RU App Store:** массовые удаления по требованию RKN (2025 — 1213 приложений, включая Streisand/v2RayTun/Happ).
  План: нейтральное имя/описание, TestFlight (10k тестеров, публичные ссылки), инструкция non-RU Apple ID.
- **Коммерция:** покупки только вне приложения (бот/сайт); из iOS-сборки на них не ссылаться (иначе Apple IAP 15–30%).

---

## Задачи

- [ ] Регистрация юрлица и аккаунта Apple Developer (Organization).
- [ ] `flutter create --platforms=ios .`; таргеты: App + PacketTunnel Extension; App Group.
- [ ] Сборка `libXray.xcframework` (`tools/build-libxray-apple`).
- [ ] Swift `PacketTunnelProvider`: `NEPacketTunnelNetworkSettings`, запуск ядра, обработка памяти.
- [ ] Dart `IosEngine` через `MethodChannel` → управляет `NETunnelProviderManager`.
- [ ] Тесты памяти на устройствах (iPhone SE/старые) — обрезка гео, лимиты Go.
- [ ] TestFlight-сборка, Beta App Review.

**До выхода iOS-версии:** направлять iOS-пользователей на стоковый **Happ** с вашей ссылкой Remnawave
(у Remnawave first-class интеграция с Happ) — это ничего не стоит и снимает срочность.
