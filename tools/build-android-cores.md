# Сборка ядер для Android (`libbox.aar`, `libxray.aar`)

Оба AAR собираются из исходников через `gomobile bind` и **не коммитятся** —
как и `xray.exe`/`sing-box.exe` на Windows. Этот файл — воспроизводимый рецепт;
всё, что здесь записано, выяснено практикой, а не взято из документации.

Требуется: Go 1.26+, Android SDK, NDK 27+, JDK 17.

## Ключевая развилка: два РАЗНЫХ gomobile

`sing-box` собирается **форком** `github.com/sagernet/gomobile` (в нём есть флаги
`-libname` и `-javapkg`, которых нет в апстриме), а `libXray` — **апстримным**
`golang.org/x/mobile`. Форк требует, чтобы целевой модуль зависел от
`github.com/sagernet/gomobile/bind`; у libXray такой зависимости нет, и сборка
падает с «no Go package in github.com/sagernet/gomobile/bind».

Поэтому ставим их в РАЗНЫЕ каталоги и подкладываем нужный первым в `PATH`.

```bash
export GOROOT=C:/dev/android/gosdk/go
export GOPATH=C:/dev/android/gopath
export ANDROID_HOME=C:/dev/android/sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.0.12077973
export JAVA_HOME=C:/dev/android/jdk/jdk-17.0.19+10

# форк SagerNet → GOPATH/bin (версия обязана совпадать с пином в go.mod sing-box)
go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.12
go install github.com/sagernet/gomobile/cmd/gobind@v0.1.12

# апстрим → отдельный каталог
GOBIN=C:/dev/android/gobin-upstream go install golang.org/x/mobile/cmd/gomobile@latest
GOBIN=C:/dev/android/gobin-upstream go install golang.org/x/mobile/cmd/gobind@latest
```

## libbox (sing-box, GPL-3.0)

Штатная цель `make lib_android` **не годится**: её набор тегов включает
`with_naive_outbound`, который тянет `github.com/sagernet/cronet-go`, а тот
требует предсобранной нативной библиотеки и валит сборку. Собираем напрямую с
минимальным набором тегов — ровно под нужды SilentGate.

```bash
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH     # форк SagerNet
cd sing-box                                    # git checkout v1.13.14
gomobile bind \
  -target=android/arm64 -androidapi 24 \
  -javapkg=io.nekohasekai -libname=box \
  -tags "with_gvisor,with_quic,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0" \
  -ldflags "-s -w -checklinkname=0 -X github.com/sagernet/sing-box/constant.Version=1.13.14" \
  -trimpath -o libbox.aar ./experimental/libbox
```

Теги: `with_gvisor` — TUN-стек, `with_quic` — hysteria2, `with_utls` — отпечатки
TLS, `with_clash_api` — статистика трафика. Намеренно БЕЗ `naive`, `wireguard`,
`tailscale`: они нам не нужны и только раздувают AAR.

## libXray (MIT)

```bash
export PATH=C:/dev/android/gobin-upstream:$GOROOT/bin:$PATH   # апстрим!
cd libXray
gomobile bind \
  -target=android/arm64 -androidapi 24 \
  -javapkg=com.xtls \
  -tags "badlinkname,tfogo_checklinkname0" \
  -ldflags "-s -w -checklinkname=0" \
  -trimpath -o libxray.aar .
```

Без `-checklinkname=0` линковка падает на `github.com/wlynxg/anet: invalid
reference to net.zoneCache`: пакет лезет во внутренности `net` через
`//go:linkname`, а современный Go это блокирует.

## Куда класть

`engine/android/*.aar` (репозиторный слот, gitignored) и
`app/android/app/libs/` (откуда их берёт Gradle).

## Выясненное API (версии 1.13.14 / libXray HEAD)

**libbox** — в 1.13 НЕТ `BoxService`/`newService` из старых примеров. Актуальный
порядок:

1. `Libbox.setup(SetupOptions)` — базовый, рабочий и временный каталоги;
2. `server = Libbox.newCommandServer(handler, platformInterface)`;
3. `server.start()`;
4. `server.startOrReloadService(configJson, overrideOptions)` — сюда уходит наш
   sing-box-конфиг;
5. `server.closeService()` / `server.close()`.

`PlatformInterface` (его реализует наш `VpnService`) обязан дать 16 методов;
для нас ключевые:

| Метод | Зачем |
|---|---|
| `openTun(TunOptions): int` | сердце интеграции: строим `VpnService.Builder` по `TunOptions` и возвращаем fd |
| `autoDetectInterfaceControl(int)` | `protect(fd)` — анти-петля для сокетов ядра |
| `findConnectionOwner(...)` | `ConnectivityManager.getConnectionOwnerUid`, **без него не работают `package_name`-правила**, то есть блокировка приложений (API 29+) |
| `getInterfaces()`, `startDefaultInterfaceMonitor(...)` | сетевые интерфейсы и события смены сети |
| `useProcFS()` | на Android 10+ обязан возвращать `false` (`/proc` закрыт) |

`TunOptions` отдаёт ровно то, что нужно `Builder`: `getInet4Address()`,
`getInet6Address()`, `getMTU()`, `getAutoRoute()`, `getStrictRoute()`,
`getInet4RouteAddress()`, `getInet4RouteExcludeAddress()`, `getIncludePackage()`,
`getExcludePackage()`, `getDNSServerAddress()`.

**libXray** — единый вход `Invoke(requestJSON): String` с методами
`runXrayFromJson`, `stopXray`, `ping`, `testXray`, `xrayVersion`,
`getXrayState`. Отдельно `SetDNS(DialerController, server)` — `DialerController`
даёт `ProtectFd(int)`, тот же анти-петля-механизм.
