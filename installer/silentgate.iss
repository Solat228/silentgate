; Установщик SilentGate (Inno Setup 6).
; Сборка: установить Inno Setup, затем ISCC.exe installer\silentgate.iss
; (перед этим собрать release: build-exe.bat, чтобы папка Release содержала exe + ядро).

#define MyAppName "SilentGate"
#define MyAppPublisher "SilentGate"
#define MyAppExe "silentgate.exe"
; ⚠️ ПУТЬ К СБОРКЕ ЗАДАЁТСЯ СНАРУЖИ: ISCC.exe /DReleaseDir=<путь> installer\silentgate.iss
; Без `#ifndef` строка ниже переопределяла аргумент командной строки МОЛЧА, и
; установщик собирался из той папки, которая просто лежала в репозитории. Так и
; вышло 16.08.2026: на выходе получился `SilentGateSetup-1.4.3.49.exe`, хотя
; собирали 1.5.1 — версию установщик берёт из exe, поэтому подлог был виден
; только в имени файла.
#ifndef ReleaseDir
  #define ReleaseDir "..\app\build\windows\x64\runner\Release"
#endif

; Версия берётся ИЗ СОБРАННОГО exe (Flutter штампует её из pubspec), а не задаётся
; здесь руками — иначе установщик молча отстаёт от приложения (так и было: 0.2.0
; против 0.13.0). Нет сборки — компиляция падает с понятной ошибкой: сперва
; build-exe.bat, потом установщик.
#if !FileExists(ReleaseDir + "\" + MyAppExe)
  #error Сначала соберите release (build-exe.bat): не найден app\build\windows\x64\runner\Release\silentgate.exe
#endif
#define MyAppVersion GetVersionNumbersString(ReleaseDir + "\" + MyAppExe)

; ⚠️ В ИМЕНИ ФАЙЛА — ТРИ ЧИСЛА, БЕЗ НОМЕРА СБОРКИ.
; `GetVersionNumbersString` отдаёт четыре (`1.5.1.51`), а сервер обновлений
; ссылается на `SilentGateSetup-1.5.1.exe` (docs/APP_UPDATE_SERVER.md §3) —
; четвёртое число там лишнее и даёт 404 по кнопке «Скачать». Внутри установщика
; версия остаётся полной: по ней Windows отличает сборки.
#define ShortVersion Copy(MyAppVersion, 1, RPos(".", MyAppVersion) - 1)

[Setup]
AppId={{B7F3B2A1-5C2E-4E7A-9F1D-51E4C0DE0001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExe}
; ⚠️ ИМЯ СВЕРЕНО С СЕРВЕРОМ ОБНОВЛЕНИЙ, А НЕ ВЫБРАНО НА ВКУС.
; Эндпоинт `/api/app-version` отдаёт ссылку вида `SilentGateSetup-<версия>.exe`
; (см. docs/APP_UPDATE_SERVER.md §3). Здесь раньше стоял `SilentGate-Setup-`
; — с лишним дефисом, — и файл на сервере пришлось бы переименовывать руками
; при каждом выпуске. Ровно так и рождаются «скачал по кнопке, а там 404».
; Меняешь имя тут — меняй и в документе, и на сервере.
OutputBaseFilename=SilentGateSetup-{#ShortVersion}
OutputDir=Output
VersionInfoVersion={#MyAppVersion}
Compression=lzma2
SolidCompression=yes
; Per-user установка без прав администратора; TUN запросит UAC уже в рантайме.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Registry]
; URL-схема silentgate:// (per-user, без админа)
Root: HKCU; Subkey: "Software\Classes\silentgate"; ValueType: string; ValueName: ""; ValueData: "URL:SilentGate Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\silentgate"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\silentgate\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExe},0"
Root: HKCU; Subkey: "Software\Classes\silentgate\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExe}"" ""%1"""

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "Запустить {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Перед удалением: снять системный прокси, убить ядро/sing-box, удалить данные, снять схему.
Filename: "{app}\{#MyAppExe}"; Parameters: "--cleanup"; Flags: runhidden; RunOnceId: "SilentGateCleanup"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\SilentGate"
