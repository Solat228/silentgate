# macOS — план и фичи (этап M9)

Переиспользует общий Flutter-код и desktop-логику движка.

---

## Два пути (выбрать по факту)

1. **Subprocess (как Windows)** — MVP-путь: `xray` отдельным процессом + системный прокси
   (`networksetup -setsocksfirewallproxy`) или TUN через хелпер. Быстро, минимум нативного кода.
2. **NetworkExtension (как iOS)** — `NEPacketTunnelProvider` (System Extension для standalone-приложения
   вне App Store). Нужен аккаунт Developer и подпись/нотаризация. Лучший UX, но сложнее.

**Рекомендация:** начать с subprocess-режима (переиспользовать `engine/desktop`), NE — позже при выходе в Mac App Store.

---

## Задачи

- [ ] `flutter create --platforms=macos .`.
- [ ] `MacosEngine`: запуск `xray` + системный прокси через `networksetup`, либо общий `DesktopEngine`.
- [ ] Сборка `xray` под macOS (arm64 + x64, universal), раскладка ассетов.
- [ ] Подпись и нотаризация (Developer ID) для распространения вне App Store.
- [ ] Трей-иконка, автозапуск (LaunchAgent).

## Особенности

- Нет жёсткого лимита памяти (в отличие от iOS NE) — можно не резать geo-файлы.
- Для TUN-режима — System Extension + entitlements (сложнее, чем на Windows).
