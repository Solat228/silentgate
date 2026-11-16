@echo off
rem ==== Сборка SilentGate для Microsoft Store (пакет MSIX) ====
rem Результат: app\build\msix\SilentGate-<версия>-msstore.msix.
rem
rem Чем отличается от build-exe.bat:
rem  - сборка с SILENTGATE_STORE=msstore (окно согласия на данные устройства);
rem  - на выходе пакет MSIX, а не установщик: Store подписывает его сам,
rem    обновляет сам, удаляет сам (решение владельца 21.10.2026);
rem  - Identity Name и Publisher - из Partner Center, переменными окружения
rem    SG_MSIX_IDENTITY и SG_MSIX_PUBLISHER. Без них пакет ТЕСТОВЫЙ
rem    (SilentGate.Test, CN=SilentGateTest, имя кончается на -test.msix) -
rem    для VM, не для Store;
rem  - для Store ещё SG_MSIX_DISPLAY_NAME (зарезервированное имя продукта,
rem    сейчас SilentGateVPN) и SG_MSIX_PUBLISHER_DISPLAY_NAME (SilentGate) -
rem    со страницы "Удостоверение продукта", дословно;
rem  - подпись для VM: SG_MSIX_PFX=путь к pfx, пароль в MSIX_PFX_PASSWORD.
rem  - версия пакета - из pubspec.yaml ("x.y.z+N" даёт x.y.z.0).
rem
rem !! Release после этой сборки - Store-вариант. Кэш AOT Flutter свой на
rem каждый набор define: перед сборкой GitHub сверять хэш data\app.so.
setlocal
set "JUNCTION=C:\dev\silentgate"
set "PROJECT=I:\!Backup\!Projects\!VPN\SilentGateApp"
set "FLUTTER=C:\Users\User\flutter\bin\flutter.bat"
set "DART=C:\Users\User\flutter\bin\dart.bat"

if not exist "%JUNCTION%\" (
  if not exist "C:\dev\" mkdir "C:\dev"
  mklink /J "%JUNCTION%" "%PROJECT%"
)

cd /d "%JUNCTION%\app"
set "REL=%JUNCTION%\app\build\windows\x64\runner\Release"
if not exist "%REL%\silentgate.exe" goto :sg_free
2>nul (>>"%REL%\silentgate.exe" (call )) || goto :sg_busy
goto :sg_free

:sg_busy
echo.
echo === SILENTGATE.EXE ЗАНЯТ ===
echo Закройте SilentGate, запущенный из папки сборки, и повторите.
echo.
pause
exit /b 1

:sg_free
echo Сборка release для Microsoft Store...
call "%FLUTTER%" build windows --release --dart-define=SILENTGATE_STORE=msstore
if errorlevel 1 (
  echo.
  echo === СБОРКА НЕ УДАЛАСЬ ===
  pause
  exit /b 1
)

set "BIN=%JUNCTION%\engine\windows\bin"
for %%f in (xray.exe sing-box.exe geoip.dat geosite.dat wintun.dll) do (
  if not exist "%BIN%\%%f" (
    echo.
    echo === Нет %BIN%\%%f - пакет без ядра не собирается ===
    pause
    exit /b 1
  )
  copy /Y "%BIN%\%%f" "%REL%\" >nul
)
if not exist "%REL%\licenses\" mkdir "%REL%\licenses"
if exist "%BIN%\LICENSE"             copy /Y "%BIN%\LICENSE"             "%REL%\licenses\LICENSE-xray.txt" >nul
if exist "%BIN%\LICENSE-wintun.txt"  copy /Y "%BIN%\LICENSE-wintun.txt"  "%REL%\licenses\LICENSE-wintun.txt" >nul
if exist "%BIN%\LICENSE-singbox.txt" copy /Y "%BIN%\LICENSE-singbox.txt" "%REL%\licenses\LICENSE-singbox.txt" >nul
if exist "%BIN%\LICENSE-GPL-3.0.txt" copy /Y "%BIN%\LICENSE-GPL-3.0.txt" "%REL%\licenses\LICENSE-GPL-3.0.txt" >nul
if exist "%PROJECT%\THIRD-PARTY.md"  copy /Y "%PROJECT%\THIRD-PARTY.md"  "%REL%\licenses\" >nul

set "MSIX_ARGS="
if defined SG_MSIX_IDENTITY set "MSIX_ARGS=%MSIX_ARGS% --identity-name %SG_MSIX_IDENTITY%"
if defined SG_MSIX_PUBLISHER set "MSIX_ARGS=%MSIX_ARGS% --publisher "%SG_MSIX_PUBLISHER%""
if defined SG_MSIX_DISPLAY_NAME set "MSIX_ARGS=%MSIX_ARGS% --display-name "%SG_MSIX_DISPLAY_NAME%""
if defined SG_MSIX_PUBLISHER_DISPLAY_NAME set "MSIX_ARGS=%MSIX_ARGS% --publisher-display-name "%SG_MSIX_PUBLISHER_DISPLAY_NAME%""
if defined SG_MSIX_PFX set "MSIX_ARGS=%MSIX_ARGS% --sign-pfx "%SG_MSIX_PFX%""

echo Упаковка MSIX...
call "%DART%" run tool/build_msix.dart %MSIX_ARGS%
if errorlevel 1 (
  echo.
  echo === ПАКЕТ НЕ СОБРАН ===
  pause
  exit /b 1
)

echo.
echo === ГОТОВО ===
start "" "%JUNCTION%\app\build\msix"
endlocal
