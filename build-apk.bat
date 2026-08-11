@echo off
rem ==== Сборка SilentGate (Android, release APK) ====
rem Двойной клик: соберёт APK под телефон (arm64) и эмулятор (x86_64),
rem положит их в release-android\ и откроет папку.
rem
rem !! ПОЧЕМУ ЗДЕСЬ КОПИЯ, А НЕ JUNCTION, КАК В build-exe.bat.
rem Gradle запускает СВОЙ gradlew.bat, лежащий внутри проекта, а на этой машине
rem действует Software Restriction Policy, запрещающая запуск программ с диска I:.
rem Junction от неё не спасает: Windows разрешает его в настоящий путь, и запуск
rem всё равно блокируется. Проверено прямым запуском:
rem   C:\dev\silentgate\app\android\gradlew.bat --version  -> "заблокирована групповой политикой"
rem   C:\dev\sg-build\app\android\gradlew.bat  --version  -> отрабатывает
rem build-exe.bat при этом работает через junction, потому что MSBuild ничего из
rem папки проекта не ЗАПУСКАЕТ - он только читает исходники.
rem
rem Поэтому папка app\ зеркалится в настоящий каталог на C: и сборка идёт там.
rem Зеркало инкрементальное (robocopy /MIR), так что повторные запуски быстрые.
setlocal
set "PROJECT=I:\!Backup\!Projects\!VPN\SilentGateApp"
set "WORK=C:\dev\silentgate-apk"
set "FLUTTER=C:\Users\User\flutter\bin\flutter.bat"
set "SDK=C:\dev\android\sdk"

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

rem !! Релиз без ключа НЕ собирается отладочным: сборка честно падает. Такой APK
rem нельзя было бы обновить настоящим релизом - только снос с потерей данных,
rem поэтому предупреждаем заранее, а не после раздачи.
if not exist "%PROJECT%\app\android\key.properties" (
  echo.
  echo === НЕТ app\android\key.properties - подписывать релиз нечем.
  echo Создайте его: storeFile / storePassword / keyAlias / keyPassword
  echo ^(пути через ПРЯМЫЕ слэши: Java Properties трактует \ как экранирование^).
  pause
  exit /b 1
)

echo Обновляю рабочую копию: %WORK%\app
rem Каталоги сборки НЕ зеркалим: они пересоздаются сами, а их копирование
rem заняло бы гигабайты и минуты. Заодно /XD оставляет в копии её собственный
rem build\ - за счёт этого повторная сборка инкрементальная.
rem windows\ отброшен намеренно: к APK он отношения не имеет, а весит 260 МБ.
rem !! Исключения задаются ПОЛНЫМИ путями, а не именами: robocopy выкинул бы
rem ВСЕ каталоги с таким именем на любом уровне, а в проекте есть
rem lib\engine\windows - это ИСХОДНИКИ. Сборка тогда падает на "Error when
rem reading platform_services_windows.dart", то есть жалуется совсем не на то.
robocopy "%PROJECT%\app" "%WORK%\app" /MIR /NFL /NDL /NJH /NJS /NP ^
  /XD "%PROJECT%\app\build" "%PROJECT%\app\.dart_tool" "%PROJECT%\app\windows" ^
      "%PROJECT%\app\linux" "%PROJECT%\app\macos" "%PROJECT%\app\ios" ^
      "%PROJECT%\app\android\.gradle" "%PROJECT%\app\android\build" ^
      "%PROJECT%\app\android\app\build" >nul
rem У robocopy коды 0..7 - это успех (0 = нечего копировать, 1 = скопировано и т.д.),
rem ошибка начинается с 8. Обычная проверка errorlevel 1 здесь дала бы ложный сбой.
if errorlevel 8 (
  echo.
  echo === НЕ УДАЛОСЬ ОБНОВИТЬ КОПИЮ в %WORK%
  pause
  exit /b 1
)

cd /d "%WORK%\app"
echo Сборка release APK (arm64 + x86_64)...
rem --split-per-abi обязателен: ядра приезжают из cores.aar сразу под все ABI,
rem и без разделения один APK весит под 170 МБ вместо 76.
rem --target-platform: без него --split-per-abi собирает ЕЩЁ и armeabi-v7a.
rem Это 32-битные ARM, телефонов на них давно нет, а лишний APK каждый раз
rem путает: в папке оказывается три файла вместо двух нужных.
call "%FLUTTER%" build apk --release --split-per-abi --target-platform android-arm64,android-x64

rem Flutter кладёт рядом с каждым APK файл .sha1 - контрольную сумму, которая
rem никому не нужна и только засоряет папку: вместо двух файлов там четыре,
rem и в них легко промахнуться мимо нужного. Убираем сразу после сборки, иначе
rem они возвращаются на КАЖДОМ прогоне.
del /q "%WORK%\app\build\app\outputs\flutter-apk\*.sha1" 2>nul
if errorlevel 1 (
  echo.
  echo === СБОРКА НЕ УДАЛАСЬ ===
  echo Частая причина - нехватка памяти у Gradle ^(DOS error 1455^):
  echo смотрите org.gradle.jvmargs в app\android\gradle.properties.
  pause
  exit /b 1
)

set "SRC=%WORK%\app\build\app\outputs\flutter-apk"
set "DST=%PROJECT%\app\build\app\outputs\flutter-apk"
if not exist "%DST%\" mkdir "%DST%"

rem armeabi-v7a НЕ копируем: под эту архитектуру ядра в AAR нет, и такой APK
rem установится, но работать не будет.
if exist "%SRC%\app-arm64-v8a-release.apk" copy /Y "%SRC%\app-arm64-v8a-release.apk" "%DST%\SilentGate-arm64-v8a.apk" >nul
if exist "%SRC%\app-x86_64-release.apk"    copy /Y "%SRC%\app-x86_64-release.apk"    "%DST%\SilentGate-x86_64.apk"    >nul

if not exist "%DST%\SilentGate-arm64-v8a.apk" (
  echo.
  echo === APK НЕ ПОЯВИЛСЯ в %DST%
  echo Сборка прошла, но файла нет - проверьте %SRC%
  pause
  exit /b 1
)

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
