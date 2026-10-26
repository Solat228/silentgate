# Загружает ядро Xray-core (Windows x64) в engine/windows/bin/.
# Использование:  powershell -ExecutionPolicy Bypass -File tools/fetch-xray.ps1
#
# Скачивает ЗАКРЕПЛЁННЫЙ релиз XTLS/Xray-core (Xray-windows-64.zip): xray.exe + geoip.dat + geosite.dat.
# Лицензия ядра — MPL-2.0 (см. docs/STACK_DECISION.md).
#
# ⚠️ Версия и SHA-256 архива закреплены (аудит 25.10.2026, J). Раньше качался
# `latest` без проверки: сборка зависела от дня запуска, а подменённый архив
# уехал бы в поставку молча. Хэш сверен с официальным Xray-windows-64.zip.dgst.
# Обновление ядра: поменять $ver и $sha256 вместе, хэш взять из .dgst релиза.

$ErrorActionPreference = 'Stop'
$ver = '26.3.27'
$sha256 = 'D004C39288CE9ADA487C6F398C7C545F7D749E44BDFDD59DBC9F865AFBA4E1AD'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $repoRoot 'engine\windows\bin'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$url = "https://github.com/XTLS/Xray-core/releases/download/v$ver/Xray-windows-64.zip"
$zip = Join-Path $env:TEMP "xray-windows-64-$ver.zip"

Write-Host "Загрузка Xray-core $ver`: $url"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

$got = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($got -ne $sha256) {
    Remove-Item $zip -Force
    throw "SHA-256 архива не совпал: ждали $sha256, получили $got"
}

Write-Host "Распаковка в $dest"
Expand-Archive -Path $zip -DestinationPath $dest -Force
Remove-Item $zip -Force

$exe = Join-Path $dest 'xray.exe'
if (Test-Path $exe) {
    $v = & $exe version | Select-Object -First 1
    Write-Host "Готово: $exe"
    Write-Host $v
} else {
    throw "xray.exe не найден после распаковки"
}
