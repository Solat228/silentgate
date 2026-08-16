; Установщик SilentGate (Inno Setup 6).
; Сборка: установить Inno Setup, затем ISCC.exe installer\silentgate.iss
; (перед этим собрать release: build-exe.bat, чтобы папка Release содержала exe + ядро).

#define MyAppName "SilentGate"
#define MyAppPublisher "SilentGate"
#define MyAppExe "silentgate.exe"
#define MyAppSite "https://silentgate.lol"
; ⚠️ ОТДЕЛЬНОЙ КОНСТАНТОЙ, А НЕ ЛИТЕРАЛОМ В ДВУХ МЕСТАХ: по этому же GUID секция
; [Code] ищет установленную версию в реестре (`<AppId>_is1`). Разъедутся —
; проверка отката перестанет находить установку и замолчит, ничего не сломав
; заметно. Брать значение через `SetupSetting("AppId")` нельзя: оно вернёт
; строку вместе с экранирующей фигурной скобкой.
#define MyAppId "{B7F3B2A1-5C2E-4E7A-9F1D-51E4C0DE0001}"
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
AppId={{#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
; Без этого Windows пишет в «Программы и компоненты» имя вида
; «SilentGate, версия 1.5.1.51» — версия дублируется с колонкой «Версия».
AppVerName={#MyAppName} {#ShortVersion}
AppPublisher={#MyAppPublisher}
; Три ссылки, которые Windows показывает в свойствах программы. Пустые они и
; были — человеку, нашедшему SilentGate в списке установленного, некуда пойти.
AppPublisherURL={#MyAppSite}
AppSupportURL={#MyAppSite}
AppUpdatesURL={#MyAppSite}/download
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExe}
UninstallDisplayName={#MyAppName}
; ⚠️ ИМЯ СВЕРЕНО С СЕРВЕРОМ ОБНОВЛЕНИЙ, А НЕ ВЫБРАНО НА ВКУС.
; Эндпоинт `/api/app-version` отдаёт ссылку вида `SilentGateSetup-<версия>.exe`
; (см. docs/APP_UPDATE_SERVER.md §3). Здесь раньше стоял `SilentGate-Setup-`
; — с лишним дефисом, — и файл на сервере пришлось бы переименовывать руками
; при каждом выпуске. Ровно так и рождаются «скачал по кнопке, а там 404».
; Меняешь имя тут — меняй и в документе, и на сервере.
OutputBaseFilename=SilentGateSetup-{#ShortVersion}
OutputDir=Output
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} — установка
Compression=lzma2
SolidCompression=yes
; Per-user установка без прав администратора; TUN запросит UAC уже в рантайме.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Клиент собран под современный Windows (Flutter desktop + WinUI-зависимости);
; на 8.1 он не запустится, и честнее сказать это до распаковки 130 МБ.
MinVersion=10.0.17763
WizardStyle=modern
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
; Клиент под GPL-3.0 — текст лицензии обязан ехать с поставкой, и показать его
; при установке дешевле, чем объяснять потом.
LicenseFile=..\LICENSE
; На обновлении не переспрашиваем каталог и группу: оба уже выбраны в прошлый
; раз, а лишние страницы мастера — то, из-за чего обновление кажется установкой
; второй копии.
DisableDirPage=auto
DisableProgramGroupPage=auto
; ⚠️ КЛЮЧЕВОЕ ДЛЯ ОБНОВЛЕНИЯ ПОВЕРХ. Мьютекс заводит само приложение
; (`core/platform/app_instance_mutex.dart`, имя обязано совпадать).
;
; Живой прогон 16.08.2026 в VM `SG-Test`: обновление при ЗАПУЩЕННОМ приложении
; проваливалось с кодом 5, версия на диске оставалась прежней, объяснения не
; было. А приложение с треем запущено почти всегда — отказ приходился на самый
; частый случай обновления.
;
; ⚠️ Одного `CloseApplications` мало, и это не догадка: Restart Manager закрывает
; приложение посылкой `WM_CLOSE`, а у нас на закрытие окна висит свёртывание в
; трей — процесс жив, файл занят, RM рапортует об успехе. Мьютекс от поведения
; окна не зависит.
AppMutex=SilentGateAppMutex
; RM всё равно оставляем: он корректно подхватывает случаи, когда окна нет вовсе.
CloseApplications=yes
; ⚠️ А ВОТ ПЕРЕЗАПУСКАТЬ САМИ — НЕТ. Приложение поднимает VPN и просит UAC под
; TUN; всплывший сам собой запрос прав после установки выглядит как чужое
; вмешательство. Запуск предлагается галочкой в конце (секция [Run]).
RestartApplications=no

[Languages]
; ⚠️ ЯЗЫКОВ 8 ИЗ 10, И ЭТО ПОТОЛОК INNO, А НЕ НЕДОРАБОТКА. В поставке Inno 6 нет
; ни фарси, ни китайского (`Languages\` содержит арабский, но не эти два), а
; тянуть неофициальные переводы в установщик — значит отвечать за их текст.
; Приложение все 10 языков поддерживает: язык интерфейса от языка мастера
; установки не зависит.
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "pt"; MessagesFile: "compiler:Languages\Portuguese.isl"
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "ar"; MessagesFile: "compiler:Languages\Arabic.isl"

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
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Перед удалением: снять системный прокси, убить ядро/sing-box, удалить данные, снять схему.
Filename: "{app}\{#MyAppExe}"; Parameters: "--cleanup"; Flags: runhidden; RunOnceId: "SilentGateCleanup"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\SilentGate"

[Messages]
ru.WelcomeLabel2=Будет установлен {#MyAppName} {#ShortVersion} — VPN-клиент.%n%nРекомендуется закрыть все другие приложения перед продолжением.
en.WelcomeLabel2={#MyAppName} {#ShortVersion} — VPN client — will be installed.%n%nIt is recommended that you close all other applications before continuing.

[CustomMessages]
; ⚠️ ПЕРЕВОД ОБЯЗАН БЫТЬ У КАЖДОГО ЯЗЫКА ИЗ [Languages].
; Недостающий Inno подставляет из ПЕРВОГО объявленного (у нас — русского) и
; сообщает об этом всего лишь предупреждением компиляции. То есть француз
; получил бы русский текст, а сборка при этом считалась бы успешной. Именно так
; и вышло при первой компиляции 16.08.2026: 17 предупреждений, exit 0.

ru.OlderInstalled=Установлена версия %1. Она будет обновлена до %2.%n%nНастройки, подписки и правила сохранятся.
en.OlderInstalled=Version %1 is installed. It will be updated to %2.%n%nYour settings, subscriptions and rules will be kept.
es.OlderInstalled=La versión %1 está instalada. Se actualizará a la %2.%n%nSe conservarán su configuración, suscripciones y reglas.
fr.OlderInstalled=La version %1 est installée. Elle sera mise à jour vers la version %2.%n%nVos paramètres, abonnements et règles seront conservés.
de.OlderInstalled=Version %1 ist installiert. Sie wird auf Version %2 aktualisiert.%n%nIhre Einstellungen, Abonnements und Regeln bleiben erhalten.
pt.OlderInstalled=A versão %1 está instalada. Será atualizada para a versão %2.%n%nAs suas definições, subscrições e regras serão mantidas.
tr.OlderInstalled=%1 sürümü kurulu. %2 sürümüne güncellenecek.%n%nAyarlarınız, abonelikleriniz ve kurallarınız korunacak.
ar.OlderInstalled=الإصدار %1 مثبَّت. سيتم تحديثه إلى الإصدار %2.%n%nسيتم الاحتفاظ بإعداداتك واشتراكاتك وقواعدك.

ru.SameInstalled=Версия %1 уже установлена.%n%nПереустановить её?
en.SameInstalled=Version %1 is already installed.%n%nReinstall it?
es.SameInstalled=La versión %1 ya está instalada.%n%n¿Desea reinstalarla?
fr.SameInstalled=La version %1 est déjà installée.%n%nVoulez-vous la réinstaller ?
de.SameInstalled=Version %1 ist bereits installiert.%n%nMöchten Sie sie erneut installieren?
pt.SameInstalled=A versão %1 já está instalada.%n%nDeseja reinstalá-la?
tr.SameInstalled=%1 sürümü zaten kurulu.%n%nYeniden kurmak istiyor musunuz?
ar.SameInstalled=الإصدار %1 مثبَّت بالفعل.%n%nهل تريد إعادة تثبيته؟

ru.NewerInstalled=Установлена БОЛЕЕ НОВАЯ версия %1, а этот установщик содержит %2.%n%nУстановка откатит программу назад. Продолжить?
en.NewerInstalled=A NEWER version %1 is installed, but this installer contains %2.%n%nInstalling will roll the program back. Continue?
es.NewerInstalled=Hay instalada una versión MÁS RECIENTE (%1), y este instalador contiene la %2.%n%nLa instalación revertirá el programa a una versión anterior. ¿Continuar?
fr.NewerInstalled=Une version PLUS RÉCENTE (%1) est installée, alors que ce programme d'installation contient la version %2.%n%nL'installation reviendra à une version antérieure. Continuer ?
de.NewerInstalled=Es ist eine NEUERE Version (%1) installiert, dieses Setup enthält jedoch Version %2.%n%nDie Installation setzt das Programm auf eine ältere Version zurück. Fortfahren?
pt.NewerInstalled=Está instalada uma versão MAIS RECENTE (%1), mas este instalador contém a versão %2.%n%nA instalação irá reverter o programa para uma versão anterior. Continuar?
tr.NewerInstalled=DAHA YENİ bir sürüm (%1) kurulu, ancak bu kurulum %2 sürümünü içeriyor.%n%nKurulum programı eski sürüme döndürecek. Devam edilsin mi?
ar.NewerInstalled=يوجد إصدار أحدث (%1) مثبَّت، بينما يحتوي هذا المثبِّت على الإصدار %2.%n%nسيؤدي التثبيت إلى الرجوع بالبرنامج إلى إصدار أقدم. هل تريد المتابعة؟

ru.NewerInstalledSilent=Отказ: установлена более новая версия %1 (в установщике %2). Для отката запустите установщик без /SILENT либо укажите /FORCEDOWNGRADE.
en.NewerInstalledSilent=Aborted: a newer version %1 is installed (installer has %2). To roll back, run without /SILENT or pass /FORCEDOWNGRADE.
es.NewerInstalledSilent=Cancelado: hay instalada una versión más reciente (%1); el instalador contiene la %2. Para revertir, ejecute el instalador sin /SILENT o use /FORCEDOWNGRADE.
fr.NewerInstalledSilent=Abandon : une version plus récente (%1) est installée (ce programme contient la %2). Pour revenir en arrière, lancez-le sans /SILENT ou ajoutez /FORCEDOWNGRADE.
de.NewerInstalledSilent=Abgebrochen: Eine neuere Version (%1) ist installiert (Setup enthält %2). Für ein Downgrade starten Sie das Setup ohne /SILENT oder mit /FORCEDOWNGRADE.
pt.NewerInstalledSilent=Cancelado: está instalada uma versão mais recente (%1); o instalador contém a %2. Para reverter, execute o instalador sem /SILENT ou use /FORCEDOWNGRADE.
tr.NewerInstalledSilent=İptal edildi: daha yeni bir sürüm (%1) kurulu (kurulumda %2 var). Geri almak için kurulumu /SILENT olmadan çalıştırın veya /FORCEDOWNGRADE ekleyin.
ar.NewerInstalledSilent=تم الإلغاء: يوجد إصدار أحدث (%1) مثبَّت (المثبِّت يحتوي على %2). للرجوع إلى إصدار أقدم، شغِّل المثبِّت بدون ‎/SILENT‎ أو أضف ‎/FORCEDOWNGRADE‎.

[Code]
{ ⚠️ ЧТО ЗДЕСЬ ЛЕЧИТСЯ. Inno сам НЕ СРАВНИВАЕТ версии: он ставит поверх что
  угодно чем угодно. Живой прогон 16.08.2026 (VM `SG-Test`): установщик 1.4.3,
  запущенный поверх установленной 1.5.1, МОЛЧА откатил программу назад — код
  возврата 0, ни вопроса, ни предупреждения. Сценарий бытовой: старый файл
  остался в «Загрузках», человек кликнул не по тому.

  Обратный случай (новый установщик поверх старой версии) технически работал и
  до правки, но человек об этом не знал: мастер выглядел как первая установка и
  ничего не говорил ни про обновление, ни про сохранность данных. }

function GetUninstallKey: String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppId}_is1';
end;

{ Установленная версия или пустая строка. Ставим мы per-user (PrivilegesRequired=lowest),
  но прежние сборки могли лечь и в HKLM — смотрим оба куста, иначе «ничего не
  установлено» при живой установке. }
function InstalledVersion: String;
begin
  Result := '';
  if RegQueryStringValue(HKEY_CURRENT_USER, GetUninstallKey, 'DisplayVersion', Result) then Exit;
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, GetUninstallKey, 'DisplayVersion', Result) then Exit;
  Result := '';
end;

{ Отрицательное — a старее b, 0 — равны, положительное — a новее.
  Сравниваем ПО ЧИСЛАМ: строкой «1.4.10» меньше «1.4.9» — та же ловушка, что уже
  ловил `AppUpdate.isNewer` в самом приложении (test/app_update_test.dart). }
function CompareVersions(a, b: String): Integer;
var
  pa, pb: Integer;
  sa, sb: String;
begin
  Result := 0;
  while (Result = 0) and ((a <> '') or (b <> '')) do
  begin
    pa := Pos('.', a);
    if pa > 0 then begin sa := Copy(a, 1, pa - 1); a := Copy(a, pa + 1, Length(a)); end
    else begin sa := a; a := ''; end;
    pb := Pos('.', b);
    if pb > 0 then begin sb := Copy(b, 1, pb - 1); b := Copy(b, pb + 1, Length(b)); end
    else begin sb := b; b := ''; end;
    Result := StrToIntDef(sa, 0) - StrToIntDef(sb, 0);
  end;
end;

function ForcedDowngrade: Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if CompareText(ParamStr(i), '/FORCEDOWNGRADE') = 0 then
    begin
      Result := True;
      Exit;
    end;
end;

function InitializeSetup(): Boolean;
var
  installed: String;
  diff: Integer;
begin
  Result := True;
  installed := InstalledVersion;
  if installed = '' then Exit;

  diff := CompareVersions(installed, '{#MyAppVersion}');

  if diff > 0 then
  begin
    { Откат назад. Молча этого делать нельзя — данные писала более новая версия. }
    if ForcedDowngrade then Exit;
    if WizardSilent then
    begin
      Log(FmtMessage(CustomMessage('NewerInstalledSilent'), [installed, '{#MyAppVersion}']));
      Result := False;
      Exit;
    end;
    Result := SuppressibleMsgBox(
      FmtMessage(CustomMessage('NewerInstalled'), [installed, '{#MyAppVersion}']),
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES;
    Exit;
  end;

  { Тихий режим ниже не спрашивает ничего: он для автоматизации и для будущей
    кнопки «Обновить» в самом приложении, где вопросы задавать некому. }
  if WizardSilent then Exit;

  if diff = 0 then
    Result := SuppressibleMsgBox(
      FmtMessage(CustomMessage('SameInstalled'), [installed]),
      mbConfirmation, MB_YESNO or MB_DEFBUTTON1, IDYES) = IDYES
  else
    SuppressibleMsgBox(
      FmtMessage(CustomMessage('OlderInstalled'), [installed, '{#MyAppVersion}']),
      mbInformation, MB_OK, IDOK);
end;
