@echo off
rem ==== Build SilentGate ROOT-Stealth (Android, release APK, flavor stealth) ====
setlocal
set "PROJECT=I:\!Backup\!Projects\!VPN\SilentGateApp"
set "WORK=C:\dev\silentgate-apk"
set "FLUTTER=C:\Users\User\flutter\bin\flutter.bat"
set "SDK=C:\dev\android\sdk"

if not exist "%SDK%\platform-tools\adb.exe" (
  echo.
  echo === Android SDK not found: %SDK%
  pause
  exit /b 1
)
set "ANDROID_SDK_ROOT=%SDK%"
set "ANDROID_HOME=%SDK%"

if not exist "%PROJECT%\app\android\key.properties" (
  echo.
  echo === Missing app\android\key.properties - cannot sign release APK.
  pause
  exit /b 1
)

echo Syncing workspace to %WORK%\app ...
robocopy "%PROJECT%\app" "%WORK%\app" /MIR /NFL /NDL /NJH /NJS /NP ^
  /XD "%PROJECT%\app\build" "%PROJECT%\app\.dart_tool" "%PROJECT%\app\windows" ^
      "%PROJECT%\app\linux" "%PROJECT%\app\macos" "%PROJECT%\app\ios" ^
      "%PROJECT%\app\android\.gradle" "%PROJECT%\app\android\build" ^
      "%PROJECT%\app\android\app\build" >nul
if errorlevel 8 (
  echo.
  echo === robocopy failed (code %ERRORLEVEL%)
  pause
  exit /b 1
)

del /q "%WORK%\app\build\app\outputs\flutter-apk\*.apk"  2>nul
del /q "%WORK%\app\build\app\outputs\flutter-apk\*.sha1" 2>nul

cd /d "%WORK%\app"
set "CHANNEL_DEFINE="
if defined SILENTGATE_CHANNEL set "CHANNEL_DEFINE=--dart-define=SILENTGATE_CHANNEL=%SILENTGATE_CHANNEL%"
set "GIT_SHA_DEFINE="
for /f "delims=" %%g in ('git -C "%PROJECT%" rev-parse --short HEAD 2^>nul') do set "GIT_SHA_DEFINE=--dart-define=SILENTGATE_GIT_SHA=%%g"
set "GIT_BRANCH_DEFINE="
for /f "delims=" %%b in ('git -C "%PROJECT%" rev-parse --abbrev-ref HEAD 2^>nul') do set "GIT_BRANCH_DEFINE=--dart-define=SILENTGATE_GIT_BRANCH=%%b"

echo Building release APK ROOT-Stealth (arm64 + x86_64)...
call "%FLUTTER%" build apk --release --flavor stealth --split-per-abi --target-platform android-arm64,android-x64 %CHANNEL_DEFINE% %GIT_SHA_DEFINE% %GIT_BRANCH_DEFINE%
if errorlevel 1 (
  echo.
  echo !! flutter build apk --flavor stealth failed, code %ERRORLEVEL%.
  exit /b 1
)

del /q "%WORK%\app\build\app\outputs\flutter-apk\*.sha1" 2>nul

set "SRC=%WORK%\app\build\app\outputs\flutter-apk"
set "DST=%PROJECT%\app\build\app\outputs\flutter-apk"
if not exist "%DST%\" mkdir "%DST%"

for /f "tokens=2 delims=: " %%v in ('findstr /b "version:" "%PROJECT%\app\pubspec.yaml"') do set "PUBVER=%%v"
for /f "tokens=1 delims=+" %%p in ("%PUBVER%") do set "VER=%%p"

if exist "%SRC%\app-arm64-v8a-stealth-release.apk" copy /Y "%SRC%\app-arm64-v8a-stealth-release.apk" "%DST%\SilentGate-ROOT-Stealth-%VER%-arm64-v8a.apk" >nul
if exist "%SRC%\app-x86_64-stealth-release.apk"    copy /Y "%SRC%\app-x86_64-stealth-release.apk"    "%DST%\TEST-ONLY-emulator-SilentGate-ROOT-Stealth-%VER%-x86_64.apk" >nul
if exist "%SRC%\app-arm64-v8a-stealth-release.apk" copy /Y "%SRC%\app-arm64-v8a-stealth-release.apk" "%DST%\SilentGate-ROOT-Stealth-%PUBVER%-arm64-v8a.apk" >nul
if exist "%SRC%\app-x86_64-stealth-release.apk"    copy /Y "%SRC%\app-x86_64-stealth-release.apk"    "%DST%\TEST-ONLY-emulator-SilentGate-ROOT-Stealth-%PUBVER%-x86_64.apk" >nul

if not exist "%DST%\SilentGate-ROOT-Stealth-%VER%-arm64-v8a.apk" (
  echo.
  echo === ROOT-Stealth APK not found in %DST%
  pause
  exit /b 1
)

echo.
echo === DONE (ROOT-Stealth) ===
echo   SilentGate-ROOT-Stealth-%VER%-arm64-v8a.apk
echo   TEST-ONLY-emulator-SilentGate-ROOT-Stealth-%VER%-x86_64.apk
endlocal
