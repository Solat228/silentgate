# Раскладывает ядра, базы и лицензии рядом с собранным silentgate.exe — то же,
# что делает build-exe.bat после `flutter build windows`, но для CI
# (.github/workflows/build.yml). Батник на раннере не годится: он ждёт junction,
# путь к Flutter владельца и `pause` на ошибках.
#
# ⚠️ Состав файлов обязан совпадать с build-exe.bat (переменная CORES и блок
# лицензий). Расхождение стережёт test/ci_workflow_test.dart.
#
# Использование:  pwsh tools/stage-release.ps1 [-NoTun]

param(
    # Сборка без драйвера (Microsoft Store, заявка MS3): без sing-box и wintun.
    [switch]$NoTun
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$rel = Join-Path $repoRoot 'app\build\windows\x64\runner\Release'
$bin = Join-Path $repoRoot 'engine\windows\bin'

if (-not (Test-Path (Join-Path $rel 'silentgate.exe'))) {
    throw "Нет $rel\silentgate.exe — сначала flutter build windows --release"
}

# Ядра и базы ОБЯЗАТЕЛЬНЫ: без них приложение собирается, но не подключается.
$cores = if ($NoTun) {
    @('xray.exe', 'geoip.dat', 'geosite.dat')
} else {
    @('xray.exe', 'sing-box.exe', 'geoip.dat', 'geosite.dat', 'wintun.dll')
}
foreach ($f in $cores) {
    $src = Join-Path $bin $f
    if (-not (Test-Path $src)) { throw "Нет $f в engine\windows\bin" }
    Copy-Item $src $rel -Force
}
$uninstallBat = Join-Path $repoRoot 'uninstall.bat'
if (Test-Path $uninstallBat) { Copy-Item $uninstallBat $rel -Force }

# Лицензии сторонних компонентов: Xray-core — MPL-2.0 (п. 3.2 требует текст при
# распространении), sing-box — GPL-3.0, wintun — своя лицензия.
$lic = Join-Path $rel 'licenses'
New-Item -ItemType Directory -Force -Path $lic | Out-Null
$licenses = [ordered]@{
    'LICENSE'             = 'LICENSE-xray.txt'
    'LICENSE-GPL-3.0.txt' = 'LICENSE-GPL-3.0.txt'
}
if (-not $NoTun) {
    $licenses['LICENSE-wintun.txt'] = 'LICENSE-wintun.txt'
    $licenses['LICENSE-singbox.txt'] = 'LICENSE-singbox.txt'
}
foreach ($k in $licenses.Keys) {
    $src = Join-Path $bin $k
    if (Test-Path $src) { Copy-Item $src (Join-Path $lic $licenses[$k]) -Force }
}
# Текст GPL-3.0 кладёт fetch-singbox.ps1; в сборке без драйвера sing-box не
# качается — тогда берём LICENSE самого клиента, это тот же текст GPL-3.0.
if (-not (Test-Path (Join-Path $lic 'LICENSE-GPL-3.0.txt'))) {
    Copy-Item (Join-Path $repoRoot 'LICENSE') (Join-Path $lic 'LICENSE-GPL-3.0.txt') -Force
}
Copy-Item (Join-Path $repoRoot 'THIRD-PARTY.md') $lic -Force

# Без драйвера в поставке не должно остаться ни одного его файла: установщик
# Inno забирает Release целиком.
if ($NoTun) {
    foreach ($f in @('sing-box.exe', 'wintun.dll', 'licenses\LICENSE-wintun.txt', 'licenses\LICENSE-singbox.txt')) {
        $p = Join-Path $rel $f
        if (Test-Path $p) { Remove-Item $p -Force }
    }
}

Get-ChildItem $rel -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' } |
    ForEach-Object { '{0,-40} {1}' -f $_.Name, $_.VersionInfo.ProductName }
