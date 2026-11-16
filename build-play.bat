@echo off
rem ==== Сборка SilentGate для Google Play (release AAB) ====
rem Результат: SilentGate-<версия>-play.aab в app\build\app\outputs\bundle.
rem Его загружают в Play Console; APK для телефонов Play собирает сам.
rem
rem Чем эта сборка отличается от build-apk.bat (флейвор play вместо github):
rem  - НЕТ самообновления и разрешения REQUEST_INSTALL_PACKAGES: правило Play
rem    "Device and Network Abuse" - приложение из Play обновляет только Play;
rem  - окно согласия на отправку данных устройства провайдеру подписки;
rem  - подпись КЛЮЧОМ ЗАГРУЗКИ (signing\silentgate-upload.jks). Людям Play
rem    отдаёт APK, переподписанный нашим ключом выпуска (копия у Play через
rem    PEPK), поэтому копии из Play и с GitHub обновляют друг друга;
rem  - код версии = 2000 + N, как у arm64-APK с GitHub (build.gradle.kts).
rem
rem !! Сборка идёт из ЗЕРКАЛА на C:, как в build-apk.bat: AppLocker не даёт
rem Gradle запустить gradlew.bat с диска I:, и junction тут не помогает.
setlocal
set "PROJECT=I:\!Backup\!Projects\!VPN\SilentGateApp"
set "WORK=C:\dev\silentgate-apk"
set "FLUTTER=C:\Users\User\flutter\bin\flutter.bat"
set "SDK=C:\dev\android\sdk"

if not exist "%SDK%\platform-tools\adb.exe" (
  echo.
  echo === Не найден Android SDK: %SDK%
  pause
  exit /b 1
)
set "ANDROID_SDK_ROOT=%SDK%"
set "ANDROID_HOME=%SDK%"

rem Ключ выпуска нужен и здесь: без key.properties build.gradle.kts роняет
rem любую release-сборку (защита от подписи отладочным ключом).
if not exist "%PROJECT%\app\android\key.properties" (
  echo.
  echo === Нет app\android\key.properties - ключа выпуска.
  pause
  exit /b 1
)
if not exist "%PROJECT%\app\android\upload.properties" (
  echo.
  echo === Нет app\android\upload.properties - ключа загрузки в Google Play.
  echo Ключ: signing\silentgate-upload.jks, пароль - signing\UPLOAD-KEYSTORE-PASSWORD.txt
  pause
  exit /b 1
)

echo Обновляю зеркало проекта: %WORK%\app
rem !! Исключения robocopy - ПОЛНЫМИ путями (CLAUDE.md, правило 2): короткое
rem исключение по одному имени windows выкинуло бы и lib\engine\windows.
robocopy "%PROJECT%\app" "%WORK%\app" /MIR /NFL /NDL /NJH /NJS /NP ^
  /XD "%PROJECT%\app\build" "%PROJECT%\app\.dart_tool" "%PROJECT%\app\windows" ^
      "%PROJECT%\app\linux" "%PROJECT%\app\macos" "%PROJECT%\app\ios" ^
      "%PROJECT%\app\android\.gradle" "%PROJECT%\app\android\build" ^
      "%PROJECT%\app\android\app\build" >nul
if errorlevel 8 (
  echo.
  echo === Не удалось обновить зеркало %WORK%
  pause
  exit /b 1
)

cd /d "%WORK%\app"
echo Собираю release AAB для Google Play (arm64 + x86_64)...
rem --target-platform: ядро (cores.aar) есть только под arm64-v8a и x86_64.
rem armeabi-v7a в AAB дал бы Play повод предлагать приложение телефонам,
rem на которых туннель не поднимется никогда.
call "%FLUTTER%" build appbundle --release --flavor play --target-platform android-arm64,android-x64
if errorlevel 1 (
    echo.
    echo !! flutter build appbundle upal, kod %ERRORLEVEL%. AAB NE sobran, nichego ne kopiruem.
    exit /b 1
)

for /f "tokens=2 delims=: " %%v in ('findstr /b "version:" "%PROJECT%\app\pubspec.yaml"') do set "PUBVER=%%v"
for /f "tokens=1 delims=+" %%p in ("%PUBVER%") do set "VER=%%p"
if not defined VER (
  echo.
  echo === Не удалось прочитать версию из pubspec.yaml ===
  pause
  exit /b 1
)

set "SRC=%WORK%\app\build\app\outputs\bundle\playRelease\app-play-release.aab"
set "DST=%PROJECT%\app\build\app\outputs\bundle"
if not exist "%SRC%" (
  echo.
  echo === Сборка прошла, а AAB нет: %SRC%
  pause
  exit /b 1
)
if not exist "%DST%\" mkdir "%DST%"
copy /Y "%SRC%" "%DST%\SilentGate-%VER%-play.aab" >nul

echo.
echo === ГОТОВО ===
echo   SilentGate-%VER%-play.aab - загрузить в Play Console
echo   ^(Тестирование - Закрытое тестирование - Создать выпуск^)
echo.
start "" "%DST%"
endlocal
