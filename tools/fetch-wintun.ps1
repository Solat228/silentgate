# Загружает wintun.dll (Windows x64) в engine/windows/bin/ — драйвер TUN-адаптера,
# который использует sing-box в режиме раздельного туннелирования.
# Использование:  powershell -ExecutionPolicy Bypass -File tools/fetch-wintun.ps1
#
# wintun — разрешительная лицензия (см. engine/windows/bin/LICENSE-wintun.txt).
# Бинарник в репозиторий не коммитим — скачиваем при сборке.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ver = '0.14.1'
# ⚠️ SHA-256 архива закреплён (аудит 25.10.2026, J). Драйвер ставится в систему
# с правами администратора — подменённый архив хуже всего именно здесь.
$sha256 = '07C256185D6EE3652E09FA55C0B673E2624B565E02C4B9091C79CA7D2F24EF51'
$url = "https://www.wintun.net/builds/wintun-$ver.zip"
$dest = Join-Path $PSScriptRoot '..\engine\windows\bin'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$zip = Join-Path $env:TEMP "wintun-$ver.zip"
$tmp = Join-Path $env:TEMP "wintun-$ver"
Write-Host "Загрузка wintun: $url"
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip -TimeoutSec 120
$got = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($got -ne $sha256) {
    Remove-Item $zip -Force
    throw "SHA-256 архива не совпал: ждали $sha256, получили $got"
}
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $tmp -Force

# В архиве wintun/bin/amd64/wintun.dll
$dll = Get-ChildItem -Recurse $tmp -Filter 'wintun.dll' |
    Where-Object { $_.FullName -match 'amd64' } | Select-Object -First 1
if (-not $dll) { throw "wintun.dll (amd64) не найден после распаковки" }
Copy-Item $dll.FullName -Destination (Join-Path $dest 'wintun.dll') -Force
Write-Host "Готово: $(Join-Path $dest 'wintun.dll')"
