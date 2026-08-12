@echo off
rem ==== Сборка SilentGate (Windows, release) в обход "!" в пути через junction ====
rem Двойной клик по этому файлу: создаст junction (если нет), соберёт exe,
rem положит ядро рядом и откроет папку с готовым silentgate.exe.
setlocal
set "JUNCTION=C:\dev\silentgate"
set "PROJECT=I:\!Backup\!Projects\!VPN\SilentGateApp"
set "FLUTTER=C:\Users\User\flutter\bin\flutter.bat"

if not exist "%JUNCTION%\" (
  if not exist "C:\dev\" mkdir "C:\dev"
  mklink /J "%JUNCTION%" "%PROJECT%"
)

cd /d "%JUNCTION%\app"
set "REL=%JUNCTION%\app\build\windows\x64\runner\Release"
rem ==== exe занят? ====
rem Если приложение запущено ИЗ ЭТОЙ папки, линковка падает с LNK1104. Раньше в
rem этот момент сборка уходила в обходную папку на C:, и владелец продолжал
rem запускать старую версию, не зная об этом. Теперь честно останавливаемся.
rem Рабочая копия владельца живёт в соседней папке Release ^(2^) - её НЕ трогаем.
if exist "%REL%\silentgate.exe" (
  2>nul ^( ^>^>"%REL%\silentgate.exe" call ^) ^|^| (
    echo.
    echo === silentgate.exe ЗАНЯТ ===
    echo Файл: %REL%\silentgate.exe
    echo Его держит запущенное приложение. Закройте SilentGate и повторите.
    echo Свою рабочую копию из Release ^(2^) закрывать не нужно.
    echo.
    pause
    exit /b 1
  )
)

echo Сборка release...
call "%FLUTTER%" build windows --release
if errorlevel 1 (
  echo.
  echo === СБОРКА НЕ УДАЛАСЬ ===
  pause
  exit /b 1
)

set "REL=%JUNCTION%\app\build\windows\x64\runner\Release"
set "BIN=%JUNCTION%\engine\windows\bin"
if exist "%BIN%\xray.exe"     copy /Y "%BIN%\xray.exe"     "%REL%\" >nul
if exist "%BIN%\sing-box.exe" copy /Y "%BIN%\sing-box.exe" "%REL%\" >nul
if exist "%BIN%\geoip.dat"    copy /Y "%BIN%\geoip.dat"    "%REL%\" >nul
if exist "%BIN%\geosite.dat"  copy /Y "%BIN%\geosite.dat"  "%REL%\" >nul
if exist "%BIN%\wintun.dll"   copy /Y "%BIN%\wintun.dll"   "%REL%\" >nul
if exist "%PROJECT%\uninstall.bat" copy /Y "%PROJECT%\uninstall.bat" "%REL%\" >nul

rem ==== Лицензии сторонних компонентов ====
rem Обязательны при распространении: sing-box - GPL-3.0 (п.4/п.6 требуют передавать
rem текст лицензии и обеспечивать доступ к исходникам), Xray-core - MPL-2.0 (п.3.2
rem требует прикладывать текст к Executable Form), Wintun - своя лицензия.
if not exist "%REL%\licenses\" mkdir "%REL%\licenses"
if exist "%BIN%\LICENSE"             copy /Y "%BIN%\LICENSE"             "%REL%\licenses\LICENSE-xray.txt" >nul
if exist "%BIN%\LICENSE-wintun.txt"  copy /Y "%BIN%\LICENSE-wintun.txt"  "%REL%\licenses\LICENSE-wintun.txt" >nul
if exist "%BIN%\LICENSE-singbox.txt" copy /Y "%BIN%\LICENSE-singbox.txt" "%REL%\licenses\LICENSE-singbox.txt" >nul
if exist "%BIN%\LICENSE-GPL-3.0.txt" copy /Y "%BIN%\LICENSE-GPL-3.0.txt" "%REL%\licenses\LICENSE-GPL-3.0.txt" >nul
if exist "%PROJECT%\THIRD-PARTY.md"  copy /Y "%PROJECT%\THIRD-PARTY.md"  "%REL%\licenses\" >nul
if not exist "%BIN%\LICENSE-singbox.txt" echo [!] Нет LICENSE-singbox.txt - запустите tools\fetch-singbox.ps1

rem ==== Подпись кода (опционально) ====
rem Подпись убирает предупреждение SmartScreen и снижает ложные срабатывания
rem антивирусов. Шаг ВЫПОЛНЯЕТСЯ ТОЛЬКО если задан сертификат - иначе пропускается.
rem   set "SIGN_PFX=C:\path\cert.pfx" ^& set "SIGN_PASS=пароль"   ИЛИ
rem   set "SIGN_THUMBPRINT=отпечаток-сертификата-из-хранилища"
rem Нужен signtool (Windows SDK). Подробнее - docs/CODE_SIGNING.md.
where signtool >nul 2>&1
if errorlevel 1 (
  echo [i] signtool не найден - подпись пропущена ^(установите Windows SDK^).
) else if defined SIGN_PFX (
  echo Подпись silentgate.exe ^(PFX^)...
  signtool sign /fd SHA256 /f "%SIGN_PFX%" /p "%SIGN_PASS%" /tr http://timestamp.digicert.com /td SHA256 "%REL%\silentgate.exe"
) else if defined SIGN_THUMBPRINT (
  echo Подпись silentgate.exe ^(хранилище^)...
  signtool sign /fd SHA256 /sha1 "%SIGN_THUMBPRINT%" /tr http://timestamp.digicert.com /td SHA256 "%REL%\silentgate.exe"
) else (
  echo [i] Сертификат не задан ^(SIGN_PFX / SIGN_THUMBPRINT^) - подпись пропущена.
)

echo.
echo === ГОТОВО ===
echo Приложение: %REL%\silentgate.exe
start "" "%REL%"
endlocal
