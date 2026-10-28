# Собирает своё ядро Xray (engine/xraycore) для Store-сборки Windows.
# Использование:  pwsh tools/build-xraycore.ps1 [-Out engine/windows/bin/xray.exe]
#
# Зачем — см. шапку engine/xraycore/main.go: подпись SignPath разрешена только
# для того, что собрано из наших исходников, поэтому в Store-сборку идёт не
# официальный xray.exe, а эта программа, собранная в CI.
#
# Метаданные (ProductName = SilentGate, версия продукта = версия приложения из
# pubspec, версия файла = версия Xray-core) вшивает go-winres — этого требует
# SignPath: «Set all product name attributes to your project's name».
#
# ⚠️ На машине владельца AppLocker не даёт запускать .ps1 с диска I: — там
# выполнять команды этого файла вручную из C:\dev\silentgate.

param(
    [string]$Out = '',
    # Корень репозитория. Задаётся, когда скрипт запущен из копии вне репо.
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = if ($RepoRoot) { $RepoRoot } else { Split-Path -Parent $PSScriptRoot }
$src = Join-Path $repoRoot 'engine\xraycore'
if (-not $Out) { $Out = Join-Path $repoRoot 'engine\windows\bin\xray.exe' }

# Версия приложения: pubspec хранит "X.Y.Z+N", билд-номер не нужен.
$pubspec = Get-Content (Join-Path $repoRoot 'app\pubspec.yaml') -Encoding UTF8
$line = $pubspec | Where-Object { $_ -match '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' } | Select-Object -First 1
if (-not ($line -match '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')) { throw 'Не удалось прочитать версию из app/pubspec.yaml' }
$appVer = $Matches[1]

# Версия Xray-core — из go.mod (v1.YYMMDD.0 → YY.M.D).
$gomod = Get-Content (Join-Path $src 'go.mod')
$req = $gomod | Where-Object { $_ -match 'github\.com/xtls/xray-core v1\.(\d\d)(\d\d)(\d\d)\.0' } | Select-Object -First 1
if (-not ($req -match 'github\.com/xtls/xray-core v1\.(\d\d)(\d\d)(\d\d)\.0')) { throw 'Не удалось прочитать версию xray-core из engine/xraycore/go.mod' }
$xrayVer = '{0}.{1}.{2}' -f [int]$Matches[1], [int]$Matches[2], [int]$Matches[3]

Push-Location $src
try {
    Write-Host "Ресурсы: SilentGate $appVer, Xray-core $xrayVer"
    go run github.com/tc-hib/go-winres@v0.3.3 make --in winres/winres.json --arch amd64 `
        --product-version $appVer --file-version $xrayVer
    if ($LASTEXITCODE -ne 0) { throw 'go-winres завершился с ошибкой' }

    $env:CGO_ENABLED = '0'
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    go build -trimpath -buildvcs=false `
        -ldflags '-s -w -buildid= -X github.com/xtls/xray-core/core.build=SilentGate' `
        -o $Out .
    if ($LASTEXITCODE -ne 0) { throw 'go build завершился с ошибкой' }
} finally {
    Pop-Location
}

$v = & $Out version | Select-Object -First 1
if ($v -notmatch "^Xray $([regex]::Escape($xrayVer)) ") { throw "Ядро ответило не той версией: $v" }
Write-Host "Готово: $Out"
Write-Host $v
