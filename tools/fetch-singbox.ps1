# Загружает sing-box (Windows x64) в engine/windows/bin/ — TUN-роутер для раздельного туннелирования.
# Использование:  powershell -ExecutionPolicy Bypass -File tools/fetch-singbox.ps1
#
# sing-box запускается ОТДЕЛЬНЫМ процессом (не линкуется) — это допускает его лицензию GPL
# («mere aggregation»). Не переименовывайте бинарник и соблюдайте no-name-условие sing-box.

# ⚠️ SHA-256 архива закреплён вместе с версией (аудит 25.10.2026, J): подменённый
# архив иначе уехал бы в поставку молча. Обновление: поменять $ver и $sha256 вместе.

$ErrorActionPreference = 'Stop'
$ver = '1.14.3'
$sha256 = 'D8B86EF58936DBA9230EC6A57FFA4243933F3C14EF4809828B6C553440ED1518'
$repoRoot = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $repoRoot 'engine\windows\bin'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$url = "https://github.com/SagerNet/sing-box/releases/download/v$ver/sing-box-$ver-windows-amd64.zip"
$zip = Join-Path $env:TEMP 'singbox.zip'
$tmp = Join-Path $env:TEMP 'sbx'

Write-Host "Загрузка sing-box: $url"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
$got = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($got -ne $sha256) {
  Remove-Item $zip -Force
  throw "SHA-256 архива не совпал: ждали $sha256, получили $got"
}
# Каталог распаковки чистится заранее: после прерванного прогона в нём мог
# остаться exe прежней версии, и `Select-Object -First 1` взял бы его, а не
# только что проверенный по SHA-256 (ревью 29.10.2026, L4).
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $tmp -Force
$exe = Get-ChildItem -Recurse $tmp -Filter 'sing-box.exe' | Select-Object -First 1
Copy-Item $exe.FullName (Join-Path $dest 'sing-box.exe') -Force

# Текст GPL-3.0 из архива — его ОБЯЗАНО получить вместе с бинарником всякое лицо,
# которому мы передаём sing-box (GPLv3 §4/§6). Без него распространение незаконно.
$lic = Get-ChildItem -Recurse $tmp -Include 'LICENSE','LICENSE.txt','LICENSE.md' | Select-Object -First 1
if ($lic) {
  Copy-Item $lic.FullName (Join-Path $dest 'LICENSE-singbox.txt') -Force
} else {
  # В некоторых релизных архивах лицензии нет — тянем из репозитория по тегу.
  $licUrl = "https://raw.githubusercontent.com/SagerNet/sing-box/v$ver/LICENSE"
  try {
    Invoke-WebRequest -Uri $licUrl -OutFile (Join-Path $dest 'LICENSE-singbox.txt') -UseBasicParsing
  } catch {
    Write-Warning "Не удалось получить LICENSE sing-box ($licUrl) — положите его вручную в $dest\LICENSE-singbox.txt"
  }
}

Remove-Item $zip -Force; Remove-Item $tmp -Recurse -Force

& (Join-Path $dest 'sing-box.exe') version | Select-Object -First 1
Write-Host "Готово: $dest\sing-box.exe"
