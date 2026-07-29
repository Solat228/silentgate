@echo off
rem ==== Сборка SilentGate (Android, release APK) ====
rem Двойной клик: соберёт APK под телефон (arm64) и эмулятор (x86_64),
rem положит их в release-android\ и откроет папку.
rem
rem Как и build-exe.bat, работаем через junction: в пути проекта есть "!",
rem а Gradle на нём спотыкается так же, как MSBuild.
setlocal
set "JUNCTION=C:\dev\silentgate"
set "PROJECT=I:\!Backup\!Projects\!VPN\SilentGateApp"
set "FLUTTER=C:\Users\User\flutter\bin\flutter.bat"
set "SDK=C:\dev\android\sdk"

if not exist "%JUNCTION%\" (
  if not exist "C:\dev\" mkdir "C:\dev"
  mklink /J "%JUNCTION%" "%PROJECT%"
)

rem Без SDK Gradle уйдёт искать его сам и упрётся в невнятную ошибку.
if not exist "%SDK%\platform-tools\adb.exe" (
  echo.
  echo === НЕ НАЙДЕН Android SDK: %SDK%
  echo Укажите свой путь в переменной SDK в этом файле.
  pause
  exit /b 1
)
set "ANDROID_SDK_ROOT=%SDK%"
set "ANDROID_HOME=%SDK%"

rem ⚠️ Релиз без ключа теперь НЕ собирается отладочным: сборка честно падает.
rem Такой APK нельзя было бы обновить настоящим релизом — только снос с
rem потерей данных, поэтому предупреждаем заранее, а не после раздачи.
if not exist "%JUNCTION%\app\android\key.properties" (
  echo.
  echo === НЕТ app\android\key.properties — подписывать релиз нечем.
  echo Создайте его: storeFile / storePassword / keyAlias / keyPassword
  echo (пути через ПРЯМЫЕ слэши: Java Properties трактует \ как экранирование).
  pause
  exit /b 1
)

cd /d "%JUNCTION%\app"
echo Сборка release APK (arm64 + x86_64)...
rem --split-per-abi обязателен: ядра приезжают из cores.aar сразу под все ABI,
rem и без разделения один APK весит под 170 МБ вместо 76.
call "%FLUTTER%" build apk --release --split-per-abi
if errorlevel 1 (
  echo.
  echo === СБОРКА НЕ УДАЛАСЬ ===
  echo Частая причина — нехватка памяти у Gradle ^(DOS error 1455^):
  echo смотрите org.gradle.jvmargs в app\android\gradle.properties.
  pause
  exit /b 1
)

set "SRC=%JUNCTION%\app\build\app\outputs\flutter-apk"
set "DST=%JUNCTION%\release-android"
if not exist "%DST%\" mkdir "%DST%"

rem armeabi-v7a НЕ копируем: под эту архитектуру ядра в AAR нет, и такой APK
rem установится, но работать не будет.
if exist "%SRC%\app-arm64-v8a-release.apk" copy /Y "%SRC%\app-arm64-v8a-release.apk" "%DST%\SilentGate-arm64-v8a.apk" >nul
if exist "%SRC%\app-x86_64-release.apk"    copy /Y "%SRC%\app-x86_64-release.apk"    "%DST%\SilentGate-x86_64.apk"    >nul

echo.
echo === ГОТОВО ===
echo   SilentGate-arm64-v8a.apk  - на телефон
echo   SilentGate-x86_64.apk     - на эмулятор
echo.
echo Установка на подключённый телефон:
echo   "%SDK%\platform-tools\adb.exe" install -r "%DST%\SilentGate-arm64-v8a.apk"
echo.
start "" "%DST%"
endlocal
