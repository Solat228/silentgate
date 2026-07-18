# Загружает ядро Xray-core (Windows x64) в engine/windows/bin/.
# Использование:  powershell -ExecutionPolicy Bypass -File tools/fetch-xray.ps1
#
# Скачивает последний релиз XTLS/Xray-core (Xray-windows-64.zip): xray.exe + geoip.dat + geosite.dat.
# Лицензия ядра — MPL-2.0 (см. docs/STACK_DECISION.md).

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $repoRoot 'engine\windows\bin'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$url = 'https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip'
$zip = Join-Path $env:TEMP 'xray-windows-64.zip'

Write-Host "Загрузка Xray-core: $url"
Invoke-WebRequest -Uri $url -OutFile $zip

Write-Host "Распаковка в $dest"
Expand-Archive -Path $zip -DestinationPath $dest -Force
Remove-Item $zip -Force

$exe = Join-Path $dest 'xray.exe'
if (Test-Path $exe) {
    $ver = & $exe version | Select-Object -First 1
    Write-Host "Готово: $exe"
    Write-Host $ver
} else {
    throw "xray.exe не найден после распаковки"
}
