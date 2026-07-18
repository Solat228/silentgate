# Android — план и фичи (этап M7)

Тот же Flutter-UI, что и на Windows. Отличие — движок: ядро крутится **in-process** внутри
`VpnService` через самосборный gomobile-AAR.

---

## Стек

- UI: общий Flutter-код (`app/lib`), плюс нативный слой на **Kotlin** в `app/android`.
- Ядро: **Xray-core** через самосборную обёртку **libXray (MIT)** → `libxray.aar` (`gomobile bind`).
  (Не AndroidLibXrayLite — там LGPL и обязательства релинковки.)
- TUN: fd от `VpnService.establish()` → native tun-inbound Xray (`xray.tun.fd`) **или** `hev-socks5-tunnel` (MIT, JNI).
- Мост Dart ↔ Kotlin: `MethodChannel` (connect/disconnect) + `EventChannel` (статус/трафик).

Референс архитектуры (код НЕ копировать — GPL): v2rayNG, NekoBox.

---

## Задачи

- [ ] Установить Android SDK/NDK; `flutter create --platforms=android .` в `app/`.
- [ ] Сборочный конвейер обёртки: `tools/build-libxray-android` (gomobile, Go + NDK) → `app/android/app/libs/libxray.aar`.
- [ ] `SilentGateVpnService : VpnService` (Kotlin), процесс `:vpn`:
  - `Builder`: `addAddress`, `addRoute 0.0.0.0/0`, `setMtu`, `addDnsServer`, `addDisallowedApplication(self)`.
  - `establish()` → TUN fd → передать в ядро.
  - foreground-нотификация со статусом и трафиком.
- [ ] `MethodChannel`-мост: `connect(configJson)`, `disconnect()`, `queryStats()`.
- [ ] `EngineFactory`: ветка Android → `AndroidEngine` (Dart-обёртка над каналом).
- [ ] Реализовать `VpnEngine` для Android (`app/lib/engine/android/`).
- [ ] Экран per-app split-tunnel (список установленных приложений).
- [ ] Запрос разрешения VPN (`VpnService.prepare`) и обработка отказа.

---

## Дистрибуция

- APK через Telegram-бота, сайт, GitHub Releases (без цензуры магазина).
- Позже: **RuStore** (для РФ) и Google Play (Play жёстче к VPN, но возможно).
- Подпись: собственный keystore (`app/android/key.properties`, не коммитить).

## Особенности

- Ядро в отдельном процессе `:vpn` — краш ядра не роняет UI.
- Автозапуск VPN при старте системы (опция) — `BOOT_COMPLETED` + `VpnService`.
- Always-on VPN совместимость (системная настройка Android).
- Батарея/Doze: foreground-сервис + корректная обработка сна.
