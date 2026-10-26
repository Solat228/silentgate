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
rem ==== занят ли exe ====
rem Если приложение запущено ИЗ ЭТОЙ папки, линковка падает с LNK1104.
rem Раньше в этот момент сборка молча уходила в обходную папку на C:, и
rem владелец продолжал запускать старую версию, не зная об этом.
rem Рабочая копия владельца лежит в соседней папке Release ^(2^) - её
rem закрывать не нужно, собираем мы только в Release без цифры.
if not exist "%REL%\silentgate.exe" goto :sg_free
2>nul (>>"%REL%\silentgate.exe" (call )) || goto :sg_busy
goto :sg_free

:sg_busy
echo.
echo === SILENTGATE.EXE ЗАНЯТ ===
echo Файл: %REL%\silentgate.exe
echo Его держит запущенное приложение - линковка упадёт с LNK1104.
echo Закройте SilentGate, запущенный из этой папки, и повторите сборку.
echo.
pause
exit /b 1

:sg_free
rem Бета собирается только осознанно: задайте SILENTGATE_CHANNEL=beta до запуска,
rem обычная сборка (переменная не задана) остаётся стабильной без канала.
rem Прочитается в "О программе" через AppInfo.channel (String.fromEnvironment).
set "CHANNEL_DEFINE="
if defined SILENTGATE_CHANNEL set "CHANNEL_DEFINE=--dart-define=SILENTGATE_CHANNEL=%SILENTGATE_CHANNEL%"
rem Сборка для Microsoft Store: задайте SILENTGATE_STORE=msstore до запуска.
rem Отличие одно - окно согласия на данные устройства (AppStoreInfo.current).
set "STORE_DEFINE="
if defined SILENTGATE_STORE set "STORE_DEFINE=--dart-define=SILENTGATE_STORE=%SILENTGATE_STORE%"
rem Сборка без драйвера (Microsoft Store, EXE, заявка MS3): задайте SILENTGATE_NO_TUN=1.
rem В поставку не идут wintun.dll и sing-box.exe - оба несут драйвер wintun, а правило
rem Store 10.2.4.2 сторонние драйверы запрещает. Интерфейс прячет TUN, раздельное
rem туннелирование и hysteria2 (AppStoreInfo.tunAvailable). Портативный архив не
rem собирается: его имя совпало бы с обычным и затёрло бы его.
set "NOTUN_DEFINE="
if defined SILENTGATE_NO_TUN set "NOTUN_DEFINE=--dart-define=SILENTGATE_NO_TUN=true"

rem === Версия для имени артефактов (контракт с сайтом, docs\APP_UPDATE_SERVER.md) ===
rem pubspec хранит "X.Y.Z+N" - билд-номер после + сайту не нужен, срезаем.
for /f "tokens=2 delims=: " %%v in ('findstr /b "version:" "%JUNCTION%\app\pubspec.yaml"') do set "PUBVER=%%v"
for /f "tokens=1 delims=+" %%p in ("%PUBVER%") do set "VER=%%p"
if not defined VER (
  echo.
  echo === Не удалось прочитать версию из pubspec.yaml ===
  pause
  exit /b 1
)

echo Сборка release...
call "%FLUTTER%" build windows --release %CHANNEL_DEFINE% %STORE_DEFINE% %NOTUN_DEFINE%
if errorlevel 1 (
  echo.
  echo === СБОРКА НЕ УДАЛАСЬ ===
  pause
  exit /b 1
)

set "REL=%JUNCTION%\app\build\windows\x64\runner\Release"
set "BIN=%JUNCTION%\engine\windows\bin"
rem Ядра и базы ОБЯЗАТЕЛЬНЫ: без них приложение собирается, но не подключается.
rem Раньше отсутствующий файл молча пропускался, и в поставку уходила сборка
rem без ядра (аудит 25.10.2026, J).
set "CORES=xray.exe sing-box.exe geoip.dat geosite.dat wintun.dll"
if defined SILENTGATE_NO_TUN set "CORES=xray.exe geoip.dat geosite.dat"
for %%f in (%CORES%) do (
  if not exist "%BIN%\%%f" (
    echo.
    echo === Нет %%f в engine\windows\bin - запустите tools\fetch-xray.ps1 и tools\fetch-singbox.ps1 ===
    pause
    exit /b 1
  )
  copy /Y "%BIN%\%%f" "%REL%\" >nul
  if errorlevel 1 (
    echo.
    echo === Не удалось скопировать %%f в Release ===
    pause
    exit /b 1
  )
)
if exist "%PROJECT%\uninstall.bat" copy /Y "%PROJECT%\uninstall.bat" "%REL%\" >nul
rem Release общий для обеих сборок: файлы драйвера от прошлой обычной сборки
rem надо убрать, иначе установщик Inno заберёт их из папки целиком.
if defined SILENTGATE_NO_TUN (
  for %%f in (sing-box.exe wintun.dll licenses\LICENSE-wintun.txt licenses\LICENSE-singbox.txt) do (
    if exist "%REL%\%%f" del /q "%REL%\%%f"
    if exist "%REL%\%%f" (
      echo.
      echo === Не удалось удалить %%f из Release - файл занят? ===
      pause
      exit /b 1
    )
  )
)

rem ==== Лицензии сторонних компонентов ====
rem Обязательны при распространении: sing-box - GPL-3.0 (п.4/п.6 требуют передавать
rem текст лицензии и обеспечивать доступ к исходникам), Xray-core - MPL-2.0 (п.3.2
rem требует прикладывать текст к Executable Form), Wintun - своя лицензия.
if not exist "%REL%\licenses\" mkdir "%REL%\licenses"
if exist "%BIN%\LICENSE"             copy /Y "%BIN%\LICENSE"             "%REL%\licenses\LICENSE-xray.txt" >nul
if not defined SILENTGATE_NO_TUN if exist "%BIN%\LICENSE-wintun.txt"  copy /Y "%BIN%\LICENSE-wintun.txt"  "%REL%\licenses\LICENSE-wintun.txt" >nul
if not defined SILENTGATE_NO_TUN if exist "%BIN%\LICENSE-singbox.txt" copy /Y "%BIN%\LICENSE-singbox.txt" "%REL%\licenses\LICENSE-singbox.txt" >nul
if exist "%BIN%\LICENSE-GPL-3.0.txt" copy /Y "%BIN%\LICENSE-GPL-3.0.txt" "%REL%\licenses\LICENSE-GPL-3.0.txt" >nul
if exist "%PROJECT%\THIRD-PARTY.md"  copy /Y "%PROJECT%\THIRD-PARTY.md"  "%REL%\licenses\" >nul
if not defined SILENTGATE_NO_TUN if not exist "%BIN%\LICENSE-singbox.txt" echo [!] Нет LICENSE-singbox.txt - запустите tools\fetch-singbox.ps1

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
  if errorlevel 1 (
    echo.
    echo === ПОДПИСЬ НЕ УДАЛАСЬ - неподписанный exe в поставку не идёт ===
    pause
    exit /b 1
  )
) else if defined SIGN_THUMBPRINT (
  echo Подпись silentgate.exe ^(хранилище^)...
  signtool sign /fd SHA256 /sha1 "%SIGN_THUMBPRINT%" /tr http://timestamp.digicert.com /td SHA256 "%REL%\silentgate.exe"
  if errorlevel 1 (
    echo.
    echo === ПОДПИСЬ НЕ УДАЛАСЬ - неподписанный exe в поставку не идёт ===
    pause
    exit /b 1
  )
) else (
  echo [i] Сертификат не задан ^(SIGN_PFX / SIGN_THUMBPRINT^) - подпись пропущена.
)

rem ==== Портативный архив (контракт с сайтом, docs\APP_UPDATE_SERVER.md) ====
rem Собираем ПОСЛЕ подписи - в архив должен попасть уже подписанный exe.
set "PORTZIP=не собирался (сборка без драйвера)"
if defined SILENTGATE_NO_TUN goto :sg_done
rem !! Метка portable.txt кладётся ТОЛЬКО в архив, а НЕ в %REL% - иначе
rem обычная (не портативная) установка, собранная тем же REL, начала бы
rem писать данные рядом с собой вместо %APPDATA%, и инсталлятор молча
rem унаследовал бы портативный режим.
set "PORTSTAGE=%TEMP%\sg-portable-stage"
if exist "%PORTSTAGE%" rmdir /s /q "%PORTSTAGE%"
mkdir "%PORTSTAGE%\SilentGate"
rem *.bak - rezerv geo-baz ot zapushchennogo exe, ne sborka: v arhiv ne kladem
robocopy "%REL%" "%PORTSTAGE%\SilentGate" /E /XF *.bak /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo.
  echo === Не удалось скопировать Release для портативной сборки ===
  pause
  exit /b 1
)
> "%PORTSTAGE%\SilentGate\portable.txt" (
  echo Портативная сборка SilentGate.
  echo.
  echo Обновление: распакуйте новый архив поверх этой папки. Папка sg-data -
  echo в ней подписки, настройки и журнал - трогать не нужно, архив её не
  echo содержит и не заменит.
  echo.
  echo Не удаляйте этот файл. По его наличию приложение узнаёт, что данные
  echo нужно хранить рядом с собой, а не в %%APPDATA%%. Удалите его - и
  echo приложение перейдёт на обычный каталог данных Windows.
)
set "PORTZIP=%JUNCTION%\app\build\windows\x64\runner\SilentGate-Portable-%VER%.zip"
if exist "%PORTZIP%" del /q "%PORTZIP%"
powershell -NoProfile -Command "Compress-Archive -Path '%PORTSTAGE%\SilentGate' -DestinationPath '%PORTZIP%' -Force"
if not exist "%PORTZIP%" (
  echo.
  echo === Портативный архив не собрался ===
  pause
  exit /b 1
)
rmdir /s /q "%PORTSTAGE%"

:sg_done
echo.
echo === ГОТОВО ===
echo Версия:     %VER%
if defined SILENTGATE_CHANNEL echo Канал:      %SILENTGATE_CHANNEL%
if defined SILENTGATE_STORE echo Магазин:    %SILENTGATE_STORE%
if defined SILENTGATE_NO_TUN echo Драйвер:    нет ^(без TUN, wintun.dll и sing-box.exe^)
echo Приложение: %REL%\silentgate.exe
echo Портатив:   %PORTZIP%
start "" "%REL%"
endlocal
