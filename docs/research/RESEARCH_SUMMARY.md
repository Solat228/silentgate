# Сводка исследования конкурентов и ядер

Выжимка из разбора Happ (включая teardown APK и десктопных бинарников), v2RayTun, v2rayNG,
NekoBox, Hiddify, iOS-клиентов и ядер Xray/sing-box/mihomo. Полное обоснование выбора — в
[../STACK_DECISION.md](../STACK_DECISION.md).

---

## Как сделаны популярные клиенты

| Клиент | Платформы | UI-язык | Ядро | Привязка ядра | Лицензия | Open-source |
|---|---|---|---|---|---|---|
| **Happ** | iOS/tvOS, Android/TV, Win, macOS, Linux | Android: Kotlin; Desktop: C++ Qt6/QML; iOS: Swift | Xray-core (+ sing-box для TUN на десктопе) | Android: gomobile JNI in-process; Desktop: xray/sing-box отдельными процессами под демоном `happd` | Проприетарная (ToS разрешает коммерческое *использование*, запрещает ребрендинг) | ❌ |
| **v2RayTun** | Android/TV, iOS, macOS, Win, Linux | Android: Kotlin; iOS/macOS: Swift; **Win/Linux: Flutter** | Xray-core + AmneziaWG | закрыто (предположительно gomobile) | Проприетарная | ❌ |
| **v2rayNG** | Android | Kotlin (~30k LOC) | Xray-core | AndroidLibXrayLite (LGPL) gomobile AAR, in-process в VpnService; TUN через `xray.tun.fd` или hev-socks5-tunnel | **GPL-3.0** | ✅ (референс) |
| **NekoBox** | Android | Kotlin+Java | sing-box | in-repo libcore gomobile AAR; sing-tun в ядре | **GPL-3.0** | ✅ (референс) |
| **Hiddify** | Android, iOS, Win, macOS, Linux | **Flutter/Dart** + нативный Swift NE | sing-box (hiddify-core) | xcframework/gomobile; Swift PacketTunnelProvider; App Group IPC | Open | ✅ (образец формы) |
| **Streisand** | iOS/macOS | Swift (закрыт) | Xray-core | закрыто | Проприетарная | ❌ |

**Главный вывод:** все ядра на Go; клиент = UI-оболочка + Go-ядро (in-process на мобильных через
gomobile, отдельным процессом на десктопе). Для соло-разработчика единый Flutter-код (путь Hiddify)
минимизирует объём работы.

---

## Ядра

| | Xray-core | sing-box | mihomo |
|---|---|---|---|
| Лицензия | **MPL-2.0** (закрытый код OK) | GPL-3.0 + no-name | GPL-3.0 |
| VLESS+Reality+Vision | ✅ референс | ✅ | ✅ |
| Hysteria2 | ✅ (v26.1.23+) | ✅ | ✅ |
| TUIC | ❌ | ✅ | ✅ |
| Память на мобиле | ~80–120 МБ | ~40 МБ | — |
| Мобильная обёртка | libXray (MIT), AndroidLibXrayLite (LGPL) | libbox (в составе GPL) | нет офиц. |
| RU-панели (Remnawave/Marzban/3x-ui) | доминирует | — | — |

**Выбор: Xray-core** — MPL-2.0 (легально в закрытом коммерческом приложении), референс VLESS/Reality,
доминирует в вашей экосистеме. sing-box/mihomo (GPL) — только отдельным процессом.

---

## Лицензии — итог

- **Можно в закрытый код:** Xray-core (MPL-2.0), libXray (MIT), hev-socks5-tunnel (MIT).
- **Условно:** AndroidLibXrayLite (LGPL — обязательства релинковки; лучше своя обёртка над libXray).
- **Нельзя линковать:** sing-box, mihomo (GPL — только отдельным процессом).
- **Код нельзя копировать:** v2rayNG, NekoBox, Hiddify (GPL — только архитектурный референс).
- **Проприетарные:** Happ, v2RayTun, Streisand — переиспользовать нечего; ToS Happ запрещает ребрендинг.

---

## iOS — ключевые ограничения (для этапа M8)

- Только нативный Swift `NEPacketTunnelProvider` (Dart в extension не работает); ядро линкуется в extension через `libXray.xcframework`.
- **Лимит памяти NE ~50 МБ** (с iOS 15; был 15 МБ; на части iOS 17 бывает строже). Xray жрёт больше sing-box →
  обрезка geo-файлов, GC libXray раз/сек, `GOMEMLIMIT`, отключение статистики. Проверять на устройствах рано.
- Аккаунт Apple Developer типа **Organization** (нужно юрлицо), Guideline 5.4.
- **Риски RU App Store:** в 2025 удалено 1213 приложений по требованию RKN (в т.ч. Streisand, v2RayTun, Happ);
  Happ-RU удаляли в июне 2026 и вернули под другим именем. План: нейтральное имя, TestFlight, инструкция non-RU Apple ID.

---

## Обход блокировок (RU/IR, 2026)

- **VLESS + Reality** — стандарт де-факто (RKN-стойкость ~98–99% по замерам сообщества).
- Волна RKN 2026-02 била по VLESS-over-plain-TLS → Reality/CDN.
- Заложить с начала: panel-`routing`, fragment/noise (DPI), fallback-домены подписки.
