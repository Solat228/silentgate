# SilentGate

[![Версия](https://img.shields.io/github/v/release/Solat228/silentgate?label=%D0%B2%D0%B5%D1%80%D1%81%D0%B8%D1%8F&color=7C4DFF)](https://github.com/Solat228/silentgate/releases/latest)
[![Платформы](https://img.shields.io/badge/%D0%BF%D0%BB%D0%B0%D1%82%D1%84%D0%BE%D1%80%D0%BC%D1%8B-Windows%20%7C%20Android-informational)](#стек-кратко)
[![Лицензия](https://img.shields.io/badge/%D0%BB%D0%B8%D1%86%D0%B5%D0%BD%D0%B7%D0%B8%D1%8F-GPL--3.0-success)](LICENSE)

Кроссплатформенный VPN-клиент для экосистемы **SilentGate** (панель Remnawave + Telegram-бот + сайт).
Один UI-код на **Flutter/Dart**, движок — **Xray-core** (VLESS/Reality) плюс **sing-box**
отдельным процессом для TUN и **Hysteria2**. Авторизация — через Telegram-бота.

**[⬇ Скачать последнюю версию](https://github.com/Solat228/silentgate/releases/latest)** —
установщик (`SilentGateSetup-*.exe`) или портативная сборка (`SilentGate-Portable-*.zip`).

> ⚠️ Бета. Первый таргет — **Windows**, идёт порт на **Android**. Все режимы прогоняются живым
> тестом в изолированной VM и в эмуляторе на реальных подписках — «собралось» релизом не считается.

## Что нового

Версию показывает бейдж выше: он читает последний релиз, поэтому не устаревает, даже если про него
забыть. **Полная история — [CHANGELOG.md](CHANGELOG.md)**; ниже — только текущий выпуск.

### 1.9.2 — окно «что нового» вместо стены сырого markdown

Описание релиза вываливалось в всплывающее сообщение целиком: тысячи символов разметки со
звёздочками и заголовками занимали весь экран телефона, и у этой стены не было ни кнопки закрытия,
ни возможности отказаться от показа. Теперь это окно: разметка снята, текст прокручивается, есть
«Закрыть» и «Больше не показывать» — причём последняя гасит **окно, а не проверку обновлений**.

Вёрстка окна проверяется тестами на **одиннадцати настоящих разрешениях** — от iPhone SE (320×568)
до планшета, включая альбомную ориентацию телефона, где кнопки уезжают за край первыми.

### Что идёт следом

Настоящий kill switch на фильтрах Windows Filtering Platform: существующий ничего не блокирует, а
лишь удерживает TUN-адаптер, и при смерти ядра трафик уходит под реальным адресом. Разведка прав
подтверждена живым прогоном в VM, состав правил закрыт тестами — см. `docs/BACKLOG.md` #32.

---

## Зачем свой клиент

Сейчас пользователи подключаются через сторонние клиенты (Happ, v2RayTun, Streisand) по deep-link'ам,
которые уже генерирует сайт (`happ://add/…`, `v2raytun://import/…`). Свой клиент даёт:

- **Контроль над UX и брендом** (у сторонних клиентов — своя реклама, свои «рекомендованные VPN»).
- **Бесшовную авторизацию через Telegram** без ручного копирования ссылок подписки.
- **Единую точку** для будущей коммерции (личный кабинет, продление, оплата) прямо в приложении.
- **Защиту от увода подписок** (зашифрованные ссылки по образцу Happ crypto-links).

Подробное обоснование и результаты исследования Happ / v2RayTun / v2rayNG / NekoBox / Hiddify — в
[docs/STACK_DECISION.md](docs/STACK_DECISION.md) и [docs/research/RESEARCH_SUMMARY.md](docs/research/RESEARCH_SUMMARY.md).

---

## Стек (кратко)

| Слой | Технология | Почему |
|---|---|---|
| UI (все платформы) | **Flutter / Dart** | Один код на Windows/Android/iOS/macOS/Linux. Путь v2RayTun (Win) и Hiddify (всё). |
| Движок | **Xray-core** (Go) | Референс VLESS/XTLS-Vision/Reality, доминирует в RU-экосистеме. Лицензия **MPL-2.0** — совместима с GPL-3.0, поставляется отдельным бинарником. |
| Привязка ядра — Desktop | `xray.exe` **отдельным процессом** | UI просто запускает и управляет процессом. Обновление ядра = замена бинарника. |
| Привязка ядра — Android | самосборный **gomobile AAR** из `libXray` (MIT) | in-process в `VpnService`. |
| Привязка ядра — iOS | **libXray.xcframework** в нативном Swift `NEPacketTunnelProvider` | Dart не может работать в extension. |
| Захват трафика — Windows MVP | системный прокси (реестр WinINET) | Без TUN-драйвера и прав администратора. TUN — позже. |
| Бэкенд/авторизация/оплата | **Python** (существующие боты) + Remnawave API | Ваш основной язык; логика остаётся на сервере. |

Полностью: [docs/STACK_DECISION.md](docs/STACK_DECISION.md).

---

## Структура репозитория

```
SilentGateApp/
├── README.md                     ← этот файл
├── docs/
│   ├── STACK_DECISION.md          ← выбор языков/ядра/лицензий (обоснование)
│   ├── ARCHITECTURE.md            ← общая архитектура (UI ↔ движок, потоки данных)
│   ├── ROADMAP.md                 ← сквозной поэтапный план: MVP → коммерция
│   ├── REMNAWAVE_INTEGRATION.md   ← API панели, формат подписки, Telegram-авторизация
│   ├── research/RESEARCH_SUMMARY.md ← выжимка исследования конкурентов
│   └── platforms/                 ← ОТДЕЛЬНЫЙ план и фичи под каждую платформу
│       ├── WINDOWS.md   (активная разработка)
│       ├── ANDROID.md
│       ├── IOS.md
│       ├── MACOS.md
│       └── LINUX.md
├── app/                           ← Flutter-приложение (общий код + нативные раннеры)
│   ├── lib/
│   │   ├── core/                  ← бизнес-логика (общая), без платформы:
│   │   │   ├── parser/  models/  subscription/     (парсинг подписки/ссылок)
│   │   │   ├── xray/                                (генератор конфига, фабрика outbound, harness, вариации)
│   │   │   ├── settings/                            (AppSettings)
│   │   │   └── probe/                               (пинг, проброс-харнесс, автонастройка, живая проверка сервисов)
│   │   ├── engine/                ← абстракция движка + реализации по платформам
│   │   │   ├── vpn_engine.dart  engine_factory.dart  probe_factory.dart
│   │   │   └── windows/                  (xray.exe, системный прокси, ICMP, probe/harness)
│   │   ├── data/                  ← хранилище состояния и настроек
│   │   ├── state/                 ← AppState, SettingsController, ProbeController, AutoConfigController, ServiceCheckController
│   │   └── ui/                    ← экраны (home, import, servers, settings, auto_config) и виджеты
│   ├── windows/  android/  ios/  macos/  linux/   ← нативные раннеры (генерирует Flutter)
│   └── pubspec.yaml
├── engine/                        ← бинарники/ассеты ядра по платформам
│   └── windows/bin/               ← сюда кладётся xray.exe (см. tools/fetch-xray.ps1)
└── tools/                         ← вспомогательные скрипты (загрузка ядра, bootstrap)
```

**Как разделены платформы:** UI и бизнес-логика — общие (Dart), а всё платформо-специфичное живёт
в `lib/engine/<platform>/` (Dart через conditional imports) и в нативных папках `app/<platform>/`
(Kotlin для Android, Swift для iOS). Планы и список фич каждой версии — в `docs/platforms/<PLATFORM>.md`.

---

## Быстрый старт (Windows, для разработки)

> Требуется один раз установить Flutter SDK и загрузить ядро Xray.

```powershell
# 1. Установить Flutter SDK (если ещё нет) — см. tools/bootstrap-windows.ps1
#    Клонирует flutter/flutter в C:\Users\<you>\flutter и добавляет в PATH.

# 2. Загрузить ядро xray.exe в engine/windows/bin/
powershell -ExecutionPolicy Bypass -File tools/fetch-xray.ps1

# 3. Запустить приложение на Windows
cd app
flutter pub get
flutter run -d windows
```

Подробности разработки Windows-версии — в [docs/platforms/WINDOWS.md](docs/platforms/WINDOWS.md).

---

## Лицензия

Клиентское приложение SilentGate распространяется под **[GNU GPL-3.0](LICENSE)**. Форки и
производные обязаны оставаться открытыми под той же лицензией. Бэкенд и панель `silentgate.lol` —
отдельный коммерческий сервис (в этот репозиторий не входят).

### Лицензии зависимостей

- **Xray-core — MPL-2.0**: совместим с GPL-3.0 (копилефт на уровне файлов); поставляется **отдельным
  бинарником**, не линкуется.
- **sing-box — GPL-3.0**: поставляется **отдельным процессом/бинарником**; исходники — у апстрима
  (`SagerNet/sing-box`).
- **libXray — MIT**, **hev-socks5-tunnel — MIT**, **wintun — специальная разрешительная**: без копилефта.
- **v2rayNG / NekoBox — GPL-3.0**: только как архитектурный референс, код не копировался.

Ядра (`xray.exe`, `sing-box.exe`, geo-файлы, `wintun.dll`) в репозиторий **не коммитятся** — они
скачиваются скриптами `tools/fetch-*.ps1` при сборке. Полный разбор — `THIRD-PARTY.md` и
[docs/STACK_DECISION.md#лицензии](docs/STACK_DECISION.md).
