@echo off
rem ==== Запуск уже собранного SilentGate ====
setlocal
set "REL=C:\dev\silentgate\app\build\windows\x64\runner\Release"
if exist "%REL%\silentgate.exe" (
  start "" "%REL%\silentgate.exe"
) else (
  echo Приложение ещё не собрано. Запустите build-exe.bat
  pause
)
endlocal
