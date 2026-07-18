# Установка Flutter SDK на Windows (для новой машины разработчика).
# Использование:  powershell -ExecutionPolicy Bypass -File tools/bootstrap-windows.ps1
#
# Клонирует flutter/flutter (stable) в %USERPROFILE%\flutter, добавляет в PATH пользователя,
# включает поддержку Windows-десктопа и выполняет flutter doctor.
# Отдельно требуется Visual Studio 2022 с рабочей нагрузкой "Desktop development with C++".

$ErrorActionPreference = 'Stop'

$flutterDir = Join-Path $env:USERPROFILE 'flutter'
if (-not (Test-Path (Join-Path $flutterDir 'bin\flutter.bat'))) {
    Write-Host "Клонирование Flutter stable в $flutterDir"
    git clone --depth 1 -b stable https://github.com/flutter/flutter.git $flutterDir
} else {
    Write-Host "Flutter уже установлен в $flutterDir"
}

$flutterBin = Join-Path $flutterDir 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$flutterBin*") {
    Write-Host "Добавление $flutterBin в PATH пользователя"
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$flutterBin", 'User')
}
$env:Path = "$env:Path;$flutterBin"

& (Join-Path $flutterBin 'flutter.bat') config --enable-windows-desktop
& (Join-Path $flutterBin 'flutter.bat') doctor

Write-Host ""
Write-Host "Готово. Дальше:"
Write-Host "  powershell -ExecutionPolicy Bypass -File tools/fetch-xray.ps1"
Write-Host "  cd app; flutter pub get; flutter run -d windows"
