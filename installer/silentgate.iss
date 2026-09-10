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
; ⚠️ ИМЯ МЬЮТЕКСА ЛЕЖИТ РОВНО ОДИН РАЗ. По нему установщик судит о том,
; запущено ли приложение (`AppMutex` ниже) И его же ждёт после просьбы выйти
; (`WaitForMutexGone`). Второй литерал означал бы, что одна из двух проверок
; однажды начнёт смотреть не туда — и замолчит, ничего не сломав заметно.
; Встречное имя — `AppInstanceMutex.name` в приложении, страж —
; test/installer_test.dart.
#define MyAppMutex "SilentGateAppMutex"

; ⚠️ ДОГОВОР С ПРИЛОЖЕНИЕМ О САМОЗАКРЫТИИ. Числа и слова ниже обязаны совпадать
; с `app/lib/core/platform/quit_protocol.dart`: два файла не компилируются
; вместе, поэтому расхождение не поймает ни компилятор, ни анализатор — его
; ловит test/installer_test.dart, сверяя эти `#define` с константами Dart.
;
; ⚠️ MinQuitVersion — НЕ ФОРМАЛЬНОСТЬ. Старый exe аргумента `--quit` не знает и
; запустится ОБЫЧНЫМ ОБРАЗОМ: второй экземпляр перешлёт первому «покажи окно» и
; тихо выйдет с кодом 0. То есть без этой проверки установщик принял бы запуск
; второй копии за успешное закрытие первой.
#define MinQuitVersion "1.13.0"
#define QuitArg "--quit"
#define QuitArgForce "--quit-force"
#define QuitExitBye 0
#define QuitExitBusy 10
#define QuitExitNoContact 2
#define QuitExitNoSecret 3
#define QuitExitForeign 4

; Диалог с тремя кнопками — `SuppressibleTaskDialogMsgBox`, она появилась в
; Inno 6.1. На более старом ISCC сборка обязана падать внятно, а не собирать
; установщик, который молча не спросит ничего.
#if VER < EncodeVer(6,1,0)
  #error Требуется Inno Setup 6.1 или новее: SuppressibleTaskDialogMsgBox появилась там
#endif
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
AppMutex={#MyAppMutex}
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
; ⚠️ ОБЯЗАТЕЛЬНЫЙ СПУТНИК АВТОЗАКРЫТИЯ. Строка выше помечена `skipifsilent`,
; поэтому после тихой установки приложение просто ИСЧЕЗЛО БЫ: мы его закрыли
; сами, а поднять было бы некому. Поднимаем только то, что закрыли сами и
; только в тихом режиме (`ShouldRelaunch`) — в обычном человек решает галочкой.
Filename: "{app}\{#MyAppExe}"; Flags: nowait; Check: ShouldRelaunch

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

; ── Приложение запущено и держит VPN ────────────────────────────────────────
; Три кнопки, и третья не «на всякий случай»: «закрыть, но оставить VPN»
; невозможно (выход всегда идёт после disconnect), «продолжить, не закрывая» =
; установка упадёт на занятом файле. А «я отключусь сам» — это сегодняшнее
; поведение, сохранённое как осознанный выбор: у человека может идти закачка.

ru.QuitVpnTitle=Соединение SilentGate активно
en.QuitVpnTitle=SilentGate is connected to a VPN
es.QuitVpnTitle=SilentGate está conectado a una VPN
fr.QuitVpnTitle=SilentGate est connecté à un VPN
de.QuitVpnTitle=SilentGate ist mit einem VPN verbunden
pt.QuitVpnTitle=O SilentGate está ligado a uma VPN
tr.QuitVpnTitle=SilentGate bir VPN'e bağlı
ar.QuitVpnTitle=‏SilentGate متصل بشبكة VPN

ru.QuitVpnText=Чтобы обновить программу, её нужно закрыть: файлы заняты работающим приложением.%n%nЗакрыть приложение и разорвать соединение?
en.QuitVpnText=The app must be closed before it can be updated: its files are in use.%n%nClose the app and drop the connection?
es.QuitVpnText=Para actualizar el programa hay que cerrarlo: sus archivos están en uso.%n%n¿Cerrar la aplicación y cortar la conexión?
fr.QuitVpnText=Le programme doit être fermé pour être mis à jour : ses fichiers sont utilisés.%n%nFermer l'application et couper la connexion ?
de.QuitVpnText=Für die Aktualisierung muss das Programm geschlossen werden – seine Dateien sind in Benutzung.%n%nAnwendung schließen und die Verbindung trennen?
pt.QuitVpnText=Para atualizar o programa é preciso fechá-lo: os seus ficheiros estão em uso.%n%nFechar a aplicação e terminar a ligação?
tr.QuitVpnText=Programı güncellemek için kapatmak gerekiyor: dosyaları kullanımda.%n%nUygulama kapatılıp bağlantı kesilsin mi?
ar.QuitVpnText=يجب إغلاق البرنامج لتحديثه؛ ملفاته قيد الاستخدام.%n%nهل تريد إغلاق التطبيق وقطع الاتصال؟

ru.QuitBtnClose=Закрыть приложение
en.QuitBtnClose=Close the app
es.QuitBtnClose=Cerrar la aplicación
fr.QuitBtnClose=Fermer l'application
de.QuitBtnClose=Anwendung schließen
pt.QuitBtnClose=Fechar a aplicação
tr.QuitBtnClose=Uygulamayı kapat
ar.QuitBtnClose=إغلاق التطبيق

ru.QuitBtnSelf=Я отключусь сам
en.QuitBtnSelf=I will disconnect myself
es.QuitBtnSelf=Me desconectaré yo mismo
fr.QuitBtnSelf=Je me déconnecterai moi-même
de.QuitBtnSelf=Ich trenne selbst
pt.QuitBtnSelf=Eu desligo-me
tr.QuitBtnSelf=Bağlantıyı kendim keseceğim
ar.QuitBtnSelf=سأقطع الاتصال بنفسي

ru.QuitBtnCancel=Отмена
en.QuitBtnCancel=Cancel
es.QuitBtnCancel=Cancelar
fr.QuitBtnCancel=Annuler
de.QuitBtnCancel=Abbrechen
pt.QuitBtnCancel=Cancelar
tr.QuitBtnCancel=İptal
ar.QuitBtnCancel=إلغاء

ru.QuitBusySilent=Отказ: SilentGate подключён к VPN. Рвать живое соединение молча нельзя — запустите установщик без /SILENT либо укажите /FORCEQUIT.
en.QuitBusySilent=Aborted: SilentGate is connected to a VPN. A live connection must not be dropped silently — run the installer without /SILENT or pass /FORCEQUIT.
es.QuitBusySilent=Cancelado: SilentGate está conectado a una VPN. Una conexión activa no puede cortarse en silencio: ejecute el instalador sin /SILENT o use /FORCEQUIT.
fr.QuitBusySilent=Abandon : SilentGate est connecté à un VPN. Une connexion active ne peut pas être coupée en silence — lancez le programme d'installation sans /SILENT ou ajoutez /FORCEQUIT.
de.QuitBusySilent=Abgebrochen: SilentGate ist mit einem VPN verbunden. Eine aktive Verbindung darf nicht stillschweigend getrennt werden – starten Sie das Setup ohne /SILENT oder mit /FORCEQUIT.
pt.QuitBusySilent=Cancelado: o SilentGate está ligado a uma VPN. Uma ligação ativa não pode ser terminada em silêncio — execute o instalador sem /SILENT ou use /FORCEQUIT.
tr.QuitBusySilent=İptal edildi: SilentGate bir VPN'e bağlı. Etkin bir bağlantı sessizce kesilemez — kurulumu /SILENT olmadan çalıştırın veya /FORCEQUIT ekleyin.
ar.QuitBusySilent=تم الإلغاء: ‏SilentGate متصل بشبكة VPN. لا يجوز قطع اتصال نشط بصمت — شغِّل المثبِّت بدون ‎/SILENT‎ أو أضف ‎/FORCEQUIT‎.

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

{ Вопросы про версию: обновление / переустановка / откат. Отдельной функцией,
  потому что InitializeSetup теперь делает ДВА дела, и порядок между ними имеет
  значение: сперва человек решает, ставим ли мы вообще, и только потом мы
  трогаем работающее приложение. Иначе отказ от отката гасил бы VPN «за
  компанию». }
function ConfirmVersionChange: Boolean;
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

{ ── АВТОЗАКРЫТИЕ РАБОТАЮЩЕГО ПРИЛОЖЕНИЯ ──────────────────────────────────────

  ⚠️ РАДИ ЧЕГО. До этой правки установщик показывал «обнаружен запущенный
  экземпляр» и ждал, пока человек пойдёт в трей и нажмёт «Выход». А с треем
  приложение запущено почти всегда — ручное действие требовалось на САМОМ
  ЧАСТОМ пути обновления.

  ⚠️ ПРАВО ЗАМЕНЯТЬ ФАЙЛЫ ДАЁТ ИСЧЕЗНУВШИЙ МЬЮТЕКС, А НЕ КОД ВОЗВРАТА ПОМОЩНИКА.
  Иначе чужой процесс, занявший порт 47654 и ответивший «bye», обошёл бы
  проверку целиком; и старая версия, не знающая `--quit`, запустилась бы
  обычным образом и вернула 0. Помощник только ПРОСИТ; судит мьютекс.

  ⚠️ ПРО ПРАВА. `PrivilegesRequired=lowest`, и это условие безопасности, а не
  удобства: путь к exe мы читаем из HKCU — куста, доступного самому
  пользователю на запись. Пока установщик работает от него же, подмена пути —
  самоатака ценой ноль. Поднимут привилегии — та же строка станет повышением
  прав, и запускать по ней ничего будет нельзя. }

var
  GClosedByUs: Boolean;

{ Путь к установленному exe — из той же ветки реестра, что и версия. }
function InstalledLocation: String;
var
  loc: String;
begin
  Result := '';
  loc := '';
  if not RegQueryStringValue(HKEY_CURRENT_USER, GetUninstallKey, 'InstallLocation', loc) then
    if not RegQueryStringValue(HKEY_LOCAL_MACHINE, GetUninstallKey, 'InstallLocation', loc) then
      loc := '';
  if loc = '' then Exit;
  Result := AddBackslash(RemoveQuotes(loc)) + '{#MyAppExe}';
end;

function AppIsRunning: Boolean;
begin
  Result := CheckForMutexes('{#MyAppMutex}');
end;

{ Ждём, пока приложение действительно умрёт. Мьютекс освобождается ядром при
  завершении процесса, то есть ПОСЛЕ того, как приложение сняло туннель и
  погасило ядра, — а это и есть та задержка, ради которой ожидание нужно. }
function WaitForMutexGone(TimeoutMs: Integer): Boolean;
var
  waited: Integer;
begin
  waited := 0;
  while AppIsRunning and (waited < TimeoutMs) do
  begin
    Sleep(200);
    waited := waited + 200;
  end;
  Result := not AppIsRunning;
end;

{ /FORCEQUIT — согласие на разрыв живого туннеля, данное заранее. Нужен только
  тихому режиму: в нём вопрос задавать некому (это контракт будущей кнопки
  «Обновить» внутри приложения — там подтверждение уже нажато). }
function ForceQuitRequested: Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if CompareText(ParamStr(i), '/FORCEQUIT') = 0 then
    begin
      Result := True;
      Exit;
    end;
end;

{ Запустить помощника и вернуть его код возврата (QuitProtocol.exit*).
  Не запустился вовсе — считаем «не достучались»: это ровно тот случай, когда
  дальше обязан вступить штатный диалог Inno. }
function RunQuitHelper(Force: Boolean): Integer;
var
  exe, params: String;
  code: Integer;
begin
  Result := {#QuitExitNoContact};
  exe := InstalledLocation;
  if (exe = '') or (not FileExists(exe)) then
  begin
    Log('Автозакрытие: путь к установленному ' + '{#MyAppExe}' + ' не найден');
    Exit;
  end;
  if Force then
    params := '{#QuitArgForce}'
  else
    params := '{#QuitArg}';
  if not Exec(exe, params, ExtractFileDir(exe), SW_HIDE, ewWaitUntilTerminated, code) then
  begin
    Log('Автозакрытие: помощник не запустился');
    Exit;
  end;
  Log('Автозакрытие: помощник ' + params + ' вернул ' + IntToStr(code));
  Result := code;
end;

function AskAboutActiveVpn: Integer;
begin
  Result := SuppressibleTaskDialogMsgBox(
    CustomMessage('QuitVpnTitle'),
    CustomMessage('QuitVpnText'),
    { ⚠️ ОТКРЫВАЮЩАЯ СКОБКА МАССИВА ОБЯЗАНА СТОЯТЬ В КОНЦЕ ЭТОЙ СТРОКИ.
      Inno считает секцией ЛЮБУЮ строку, чей первый непробельный символ — `[`,
      отступ его не спасает. Перенесённая на свою строку скобка даёт
      «Error on line NNN: Invalid section tag» и обрывает компиляцию целиком. }
    mbConfirmation, MB_YESNOCANCEL, [CustomMessage('QuitBtnClose'),
    CustomMessage('QuitBtnSelf'), CustomMessage('QuitBtnCancel')],
    0, IDCANCEL);
end;

{ Поднять приложение после ТИХОЙ установки — и только если закрыли его мы сами.
  В обычном режиме за это отвечает галочка в конце мастера. }
function ShouldRelaunch: Boolean;
begin
  Result := GClosedByUs and WizardSilent;
end;

function EnsureAppClosed: Boolean;
var
  installed: String;
  code, answer: Integer;
begin
  Result := True;
  { Не запущено — и делать нечего. }
  if not AppIsRunning then Exit;

  installed := InstalledVersion;
  if (installed = '') or (CompareVersions(installed, '{#MinQuitVersion}') < 0) then
  begin
    Log('Автозакрытие пропущено: установленная версия "' + installed +
        '" не понимает ' + '{#QuitArg}' + ' — дальше решает штатная проверка AppMutex');
    Exit;
  end;

  code := RunQuitHelper(False);

  if code = {#QuitExitBusy} then
  begin
    if WizardSilent then
    begin
      { ⚠️ РВАТЬ ЖИВОЙ ТУННЕЛЬ МОЛЧА НЕЛЬЗЯ. Тихая установка — это скрипт или
        кнопка «Обновить»; человек за экраном может в этот момент работать
        через VPN и не узнает даже задним числом. }
      if not ForceQuitRequested then
      begin
        Log(CustomMessage('QuitBusySilent'));
        Result := False;
        Exit;
      end;
      code := RunQuitHelper(True);
    end
    else
    begin
      answer := AskAboutActiveVpn;
      if answer = IDYES then
        code := RunQuitHelper(True)
      else if answer = IDNO then
      begin
        Log('Автозакрытие: человек закроет приложение сам');
        Exit;
      end
      else
      begin
        Result := False;
        Exit;
      end;
    end;
  end;

  if code <> {#QuitExitBye} then
  begin
    Log('Автозакрытие не подтверждено (код ' + IntToStr(code) +
        ') — дальше решает штатная проверка AppMutex');
    Exit;
  end;

  { ⚠️ ВОТ ЗДЕСЬ И РЕШАЕТСЯ ПРАВО СТАВИТЬ ФАЙЛЫ. Ответ «bye» — это обещание;
    выполнено оно или нет, показывает только исчезнувший мьютекс. }
  if not WaitForMutexGone(20000) then
  begin
    Log('Автозакрытие: ответ получен, но мьютекс за 20 с не освободился');
    Exit;
  end;
  GClosedByUs := True;
  Log('Автозакрытие: работавшее приложение закрыто по просьбе установщика');
end;

function InitializeSetup(): Boolean;
begin
  { Порядок обязателен: сперва согласие на саму установку, потом — закрытие
    работающего приложения. Наоборот означало бы гасить чужой VPN ради
    установки, от которой человек в следующем окне откажется. }
  Result := ConfirmVersionChange;
  if not Result then Exit;
  Result := EnsureAppClosed;
end;
