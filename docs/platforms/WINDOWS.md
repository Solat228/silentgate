# Windows — план и фичи

Активная платформа. Модель: Flutter-GUI запускает `xray.exe` дочерним процессом и ставит
системный прокси. Без TUN-драйвера и прав администратора (TUN — этап M5).

---

## Текущее состояние (сделано)

- [x] Каркас Flutter-приложения (`app/`), раннер Windows.
- [x] `core`: модели, парсер share-ссылок (vless/vmess/trojan/ss), генератор Xray-JSON, загрузчик подписки.
- [x] `engine/windows`: поиск `xray.exe`, запуск/остановка процесса, системный прокси (WinINET+FFI), статистика через `xray api statsquery`.
- [x] `state` + UI: экраны «Домой» (кнопка connect, статус, трафик), «Импорт», «Серверы».
- [x] Загрузка ядра: `tools/fetch-xray.ps1` → `engine/windows/bin/` (xray.exe 26.3.27 + geoip/geosite + wintun.dll).
- [x] Проверено: `flutter analyze` чисто, юнит-тесты проходят, конфиг принят ядром (`Configuration OK`), приложение собирается и запускается.

**Осталось для полного M1:** проверка live-подключения на реальной подписке Remnawave;
надёжное снятие прокси во всех сценариях; индикатор трафика в бою.

---

## Как собрать и запустить

> ⚠️ **Важно:** путь проекта содержит `!` (`I:\!Backup\…`), из-за чего сборка Flutter под Windows
> падает (ограничение MSBuild/CMake). Собираем через junction на «чистом» пути.

```powershell
# 1. Один раз — junction на чистый путь:
cmd /c mklink /J C:\dev\silentgate "I:\!Backup\!Projects\!VPN\SilentGateApp"

# 2. Ядро (если ещё не загружено):
powershell -ExecutionPolicy Bypass -File tools\fetch-xray.ps1
#    (если .ps1 заблокирован политикой — команды из скрипта выполнить вручную)

# 3. Сборка/запуск ЧЕРЕЗ junction:
cd C:\dev\silentgate\app
flutter pub get
flutter run -d windows       # или: flutter build windows
```

Dart-задачи (`analyze`, `test`, `dart run`) работают и по «грязному» пути — junction нужен только для сборки.

Переопределить путь к ядру: переменная окружения `SILENTGATE_XRAY=C:\path\to\xray.exe`.

---

## Архитектура Windows-движка

```
AppState.toggleConnection()
   └─ WindowsEngine.connect(server)
        ├─ XrayPaths.locate()               найти xray.exe + каталог гео-ассетов
        ├─ XrayConfigBuilder.buildJson()    конфиг: socks 10808 + http 10809 + api 10085
        ├─ XrayProcess.start()              xray run -c config.json (XRAY_LOCATION_ASSET=asset dir)
        ├─ SystemProxy.set(127.0.0.1:10809) реестр WinINET + InternetSetOptionW (FFI)
        └─ Timer(1s) → XrayStats.query()    xray api statsquery → uplink/downlink
   disconnect(): снять прокси → убить процесс → сброс статистики
```

Ключевые файлы:
- [app/lib/engine/windows/windows_engine.dart](../../app/lib/engine/windows/windows_engine.dart)
- [app/lib/engine/windows/system_proxy.dart](../../app/lib/engine/windows/system_proxy.dart) — реестр + `wininet.dll` через `dart:ffi`
- [app/lib/engine/windows/xray_process.dart](../../app/lib/engine/windows/xray_process.dart)
- [app/lib/engine/windows/xray_stats.dart](../../app/lib/engine/windows/xray_stats.dart)
- [app/lib/core/xray/xray_config_builder.dart](../../app/lib/core/xray/xray_config_builder.dart)

---

## Специфика Windows по этапам

**M1 (текущий):**
- Гарантированное снятие прокси: маркер-файл `%TEMP%\silentgate_proxy.lock`; при старте `recoverIfDirty()`
  снимает прокси, если прошлый запуск упал (уже реализовано).
- Автозапуск ядра под минимизированным окном; корректная обработка выхода из приложения (снять прокси).

**M5 (TUN-режим):**
- `wintun.dll` (уже в комплекте ядра) + `hev-socks5-tunnel` как tun2socks.
- Привилегированный хелпер-служба (аналог `happd` у Happ) для установки TUN и маршрутов с UAC.
- Установщик (Inno Setup / MSIX), подпись бинарников, выгрузка драйвера при выходе.

**M6 (бренд/авторизация):**
- Регистрация URL-схемы `silentgate://` в реестре (deep links из бота/сайта).
- Автозапуск с Windows (реестр Run / планировщик), сворачивание в трей.

**M10 (релиз):**
- Code-signing (желателен EV-сертификат — иначе SmartScreen).
- Автообновление (свой апдейтер или MSIX/Store).
- Упаковка ядра рядом с exe (release-раскладка `<exe_dir>\xray\xray.exe`).

---

## Известные ограничения MVP

- Системный прокси WinINET перехватывает только WinINET/WinHTTP-приложения (браузеры и большинство
  программ). Приложения, игнорирующие системный прокси, и UDP — не перехватываются. Решение — TUN (M5).
- Нет автопереподключения при обрыве/смене сети (этап M3).
- Секреты пока в открытом JSON (`getApplicationSupportDirectory`); шифрование — M6.
