# Подпись кода (SmartScreen / антивирусы)

Неподписанный `silentgate.exe` и установщик вызывают предупреждение **SmartScreen**
(«Неизвестный издатель») и повышают шанс ложных срабатываний антивирусов. Для
коммерческого релиза приложение и установщик стоит подписывать.

## Что нужно
- **Сертификат Authenticode** (OV или, лучше, **EV** — EV сразу снимает SmartScreen-репутацию).
  Поставщики: DigiCert, Sectigo, GlobalSign и т.п. EV обычно на аппаратном токене/HSM.
- **signtool** из Windows SDK (в PATH).

## Подпись exe (в сборке)
`build-exe.bat` подписывает `silentgate.exe` автоматически, ЕСЛИ задан сертификат
(иначе шаг пропускается — сборка не ломается):

```bat
:: из PFX-файла:
set "SIGN_PFX=C:\path\cert.pfx"
set "SIGN_PASS=пароль"
build-exe.bat

:: ИЛИ из системного хранилища (напр. EV-токен) по отпечатку:
set "SIGN_THUMBPRINT=aa11bb22cc33..."
build-exe.bat
```

Используется SHA-256 + RFC 3161 timestamp (`timestamp.digicert.com`) — подпись
остаётся валидной после истечения сертификата.

## Подпись установщика (Inno Setup, `installer/silentgate.iss`)
Inno Setup умеет подписывать выходной setup через директиву `SignTool`:

1. В Inno Setup IDE: **Tools → Configure Sign Tools…** добавить инструмент, напр. `sign`:
   `signtool.exe sign /fd SHA256 /f "C:\path\cert.pfx" /p $q$p$q /tr http://timestamp.digicert.com /td SHA256 $f`
2. В `[Setup]` добавить:
   ```
   SignTool=sign
   SignedUninstaller=yes
   ```

После этого и `setup.exe`, и распакованный `silentgate.exe` (если подписан на шаге
сборки) будут доверенными.

## Проверка
```
signtool verify /pa /v "build\windows\x64\runner\Release\silentgate.exe"
```

> Примечание: сам сертификат в репозиторий НЕ кладём; путь/пароль — через переменные
> окружения на машине сборки или CI-секреты.
