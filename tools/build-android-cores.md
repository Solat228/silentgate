# Сборка ядер для Android (`libbox.aar`, `libxray.aar`)

Оба AAR собираются из исходников через `gomobile bind` и **не коммитятся** —
как и `xray.exe`/`sing-box.exe` на Windows. Этот файл — воспроизводимый рецепт;
всё, что здесь записано, выяснено практикой, а не взято из документации.

Требуется: Go 1.26+ (sing-box 1.14 требует не ниже 1.25.5), Android SDK, NDK 27+, JDK 17.

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
cd sing-box                                    # git checkout v1.14.3
gomobile bind \
  -target=android/arm64 -androidapi 24 \
  -javapkg=io.nekohasekai -libname=box \
  -tags "with_gvisor,with_quic,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0" \
  -ldflags "-s -w -checklinkname=0 -X github.com/sagernet/sing-box/constant.Version=1.14.3" \
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

## Оба ядра — ОДНИМ AAR (обязательно)

Раздельные `libbox.aar` и `libxray.aar` собираются, но **подключить их вместе
нельзя**: каждый gomobile-AAR несёт свою копию Go-рантайма, и сборка падает на
`Duplicate class go.Seq found in modules libbox.aar and libxray.aar`. Решение —
один Go-модуль, тянущий оба пакета, и одна команда `gomobile bind`.

```bash
mkdir cores && cd cores
cat > go.mod <<'EOF'
module silentgate/cores
go 1.26
EOF
cat > cores.go <<'EOF'
package cores

import (
	_ "github.com/sagernet/sing-box/experimental/libbox"
	_ "github.com/xtls/libxray"
)
EOF
# Форк SagerNet генерирует код, импортирующий СВОЙ bind-пакет; без явной
# зависимости gobind падает с «no Go package in github.com/sagernet/gomobile/bind».
cat > bind_dep.go <<'EOF'
//go:build tools
package cores
import _ "github.com/sagernet/gomobile/bind"
EOF
go mod edit -require=github.com/sagernet/sing-box@v1.14.3
go mod edit -require=github.com/sagernet/gomobile@v0.1.12
go mod edit -require=github.com/xtls/libxray@v0.0.0
go mod edit -replace=github.com/xtls/libxray=<путь к клону libXray>
go mod edit -replace=github.com/sagernet/sing-box=<путь к клону sing-box>
go mod tidy      # тянет и tailscale-зависимости; сеть должна быть терпеливой

export PATH=$GOPATH/bin:$GOROOT/bin:$PATH      # форк SagerNet
gomobile bind -target=android/arm64,android/amd64 -androidapi 24   -javapkg=lol.silentgate.cores -libname=cores   -tags "with_gvisor,with_quic,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0"   -ldflags "-s -w -checklinkname=0 -X github.com/sagernet/sing-box/constant.Version=1.14.3 '-extldflags=-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384'"   -trimpath -o cores.aar   github.com/sagernet/sing-box/experimental/libbox github.com/xtls/libxray
```

`android/amd64` — ядро для эмулятора (`TEST-ONLY-emulator-…-x86_64.apk`).

## ⚠️ Выравнивание 16 КБ (обязательно)

Устройства с Android 15+ бывают со страницей памяти 16 КБ, а Google Play с
01.11.2025 требует такую совместимость для targetSdk 35. Библиотека, у которой
сегменты `LOAD` выровнены на 4 КБ, на таком устройстве не загрузится вовсе.
NDK r27 по умолчанию даёт 4 КБ (16 КБ по умолчанию — только с r28), поэтому флаг
линковщика выше обязателен: без него `libcores.so` выходил с выравниванием 4096
при том, что все библиотеки самого Flutter уже стояли на 16–64 КБ (найдено
10.10.2026). Упаковку в APK по 16 КБ AGP делает сам. Страж —
`app/test/android_16k_alignment_test.dart`: читает ELF внутри AAR.

Результат — `cores.aar` ~46 МБ на две ABI (`libcores.so` для arm64 — 67 МБ без сжатия; рантайм Go общий).
Java-пакеты внутри: `lol.silentgate.cores.libbox` и `lol.silentgate.cores.libXray`,
нативная библиотека одна — `libcores.so`.

Проверка, что склейка удалась:

```bash
unzip -p cores.aar classes.jar > /tmp/c.jar && unzip -l /tmp/c.jar | grep -c "go/Seq.class"   # ровно 1
```

## ⚠️ Патч libbox: без SSH-оболочки Tailscale (иначе ядро на 20 МБ толще)

В 1.14 файл `experimental/libbox/native_shell_session.go` собирается на Android
без всяких тегов и тянет `protocol/tailscale/tailssh`, а за ним `tsnet` — 208
пакетов Tailscale. Тег `with_tailscale` при этом не нужен: импорт безусловный.
`libcores.so` для arm64 вырастал с 58 до 78 МБ. Нам оболочка не нужна вовсе:
`usePlatformShell()` отвечает `false`. Патч прячет файл за тегом
`with_platform_shell`, которого мы не ставим, и включает заглушку. С ним
`libcores.so` весит 67 МБ.

```bash
cd C:/dev/android/src/sing-box && git checkout v1.14.3
git apply <репозиторий>/engine/android/libbox-1.14.3-no-platform-shell.patch
```

Проверка: `go list -deps` для `experimental/libbox` с нашими тегами и
`GOOS=android` не должен показать ни одного пакета `tailscale`.

### Снятый патч sing-tun (до 1.15.2)

`sing-box 1.13.14` тянул `sing-tun v0.8.11`, где `LinkEndpointFilter.Attach(nil)`
заворачивал `nil` в обёртку, и туннель не снимался после «Отключить» (найдено
19.09.2026 kprobe-трассировкой). В `sing-box 1.14.3` стоит sing-tun
`v0.9.7-…`, где это исправлено (`if dispatcher == nil`), поэтому replace на
локальный sing-tun снят. Проверка живьём та же: подключиться → «Отключить» →
`adb shell ip -o link show tun0` обязан ответить «does not exist» в течение
~10 с.

## Куда класть

`engine/android/cores.aar` (репозиторный слот, gitignored) и
`app/android/app/libs/cores.aar` (откуда его берёт Gradle).

## Выясненное API (версии 1.14.3 / libXray HEAD)

**libbox** — в 1.13 НЕТ `BoxService`/`newService` из старых примеров. Актуальный
порядок:

1. `Libbox.setup(SetupOptions)` — базовый, рабочий и временный каталоги;
2. `server = Libbox.newCommandServer(handler, platformInterface)`;
3. `server.start()`;
4. `server.startOrReloadService(configJson, overrideOptions)` — сюда уходит наш
   sing-box-конфиг;
5. `server.closeService()` / `server.close()`.

`PlatformInterface` (его реализует наш `VpnService`) в 1.14 требует 27 методов.
`systemCertificates()` убран. Добавлены методы для Tailscale, SSH-оболочки,
моста и таблицы соседей (`usePlatformShell`, `openShellSession`, `createBridge`,
`startNeighborMonitor` и другие). Нам они не нужны: отвечаем `false` или
«не поддерживается», как и официальный клиент SFA без root.
`CommandServerHandler` получил `triggerNativeCrash()` и `connectSSHAgent()`
(отвечаем `-1`). Для нас ключевые:

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

⚠️ В 1.14 `getDNSServerAddress()` отдаёт `StringIterator` (было `StringBox`), и
появился `getDNSMode()`. При режиме `Libbox.DNSModeDisabled` DNS системе не
назначаем: ядро его не перехватывает, и запросы ушли бы в никуда.

**libXray** — единый вход `Invoke(requestJSON): String` с методами
`runXrayFromJson`, `stopXray`, `ping`, `testXray`, `xrayVersion`,
`getXrayState`. Отдельно `SetDNS(DialerController, server)` — `DialerController`
даёт `ProtectFd(int)`, тот же анти-петля-механизм.
