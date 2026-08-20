# macOS — план и фичи (этап M9)

Переиспользует общий Flutter-код и desktop-логику движка.

---

## Два пути (выбрать по факту)

1. **Subprocess (как Windows)** — MVP-путь: `xray` отдельным процессом + системный прокси
   (`networksetup -setsocksfirewallproxy`) или TUN через хелпер. Быстро, минимум нативного кода.
2. **NetworkExtension (как iOS)** — `NEPacketTunnelProvider` (System Extension для standalone-приложения
   вне App Store). Нужен аккаунт Developer и подпись/нотаризация. Лучший UX, но сложнее.

**Рекомендация:** начать с subprocess-режима, NE — позже при выходе в Mac App Store.

⚠️ **`engine/desktop` НЕ СУЩЕСТВУЕТ, и рассчитывать на него нельзя.** Здесь стояло
«переиспользовать `engine/desktop`» — каталога с таким именем в проекте нет ни одного дня.
Общего десктопного слоя тоже нет: реализаций ровно две, `engine/windows/` и `engine/android/`,
а общее между ними живёт в `engine/engine_base.dart`. То есть macOS переиспользует **базу**, а
не «десктопный движок», и работа начинается с новой реализации `VpnEngine`, а не с правки чужой.
Разница в оценке — недели.

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
