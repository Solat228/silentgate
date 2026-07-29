@echo off
rem ==== Удаление данных и следов SilentGate ====
rem Кладётся рядом с silentgate.exe. Снимает системный прокси, убивает ядро/sing-box,
rem удаляет данные (%APPDATA%\SilentGate) и URL-схему silentgate://.
echo Очистка SilentGate...
"%~dp0silentgate.exe" --cleanup
echo.
echo Готово. Теперь можно удалить папку приложения.
pause
