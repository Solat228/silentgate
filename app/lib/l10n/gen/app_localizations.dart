import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fa.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fa'),
    Locale('fr'),
    Locale('pt'),
    Locale('ru'),
    Locale('tr'),
    Locale('zh')
  ];

  /// Заголовок экрана настроек
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// No description provided for @commonCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get commonCancel;

  /// No description provided for @commonClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get commonClose;

  /// No description provided for @commonCopy.
  ///
  /// In ru, this message translates to:
  /// **'Копировать'**
  String get commonCopy;

  /// No description provided for @commonCopied.
  ///
  /// In ru, this message translates to:
  /// **'Скопировано'**
  String get commonCopied;

  /// No description provided for @commonRefresh.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get commonRefresh;

  /// No description provided for @commonCheck.
  ///
  /// In ru, this message translates to:
  /// **'Проверить'**
  String get commonCheck;

  /// No description provided for @commonOk.
  ///
  /// In ru, this message translates to:
  /// **'ОК'**
  String get commonOk;

  /// No description provided for @commonDone.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get commonDone;

  /// No description provided for @commonPathCopied.
  ///
  /// In ru, this message translates to:
  /// **'Путь скопирован'**
  String get commonPathCopied;

  /// Заголовок раздела выбора языка
  ///
  /// In ru, this message translates to:
  /// **'Язык интерфейса'**
  String get languageTitle;

  /// No description provided for @languageSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Выберите язык приложения'**
  String get languageSubtitle;

  /// Пункт: следовать языку системы
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get languageSystem;

  /// No description provided for @sectionAppearance.
  ///
  /// In ru, this message translates to:
  /// **'Оформление и поведение'**
  String get sectionAppearance;

  /// No description provided for @sectionCapture.
  ///
  /// In ru, this message translates to:
  /// **'Захват трафика'**
  String get sectionCapture;

  /// No description provided for @sectionReliability.
  ///
  /// In ru, this message translates to:
  /// **'Надёжность соединения'**
  String get sectionReliability;

  /// No description provided for @sectionPing.
  ///
  /// In ru, this message translates to:
  /// **'Пинг'**
  String get sectionPing;

  /// No description provided for @sectionIdentity.
  ///
  /// In ru, this message translates to:
  /// **'Представление панели'**
  String get sectionIdentity;

  /// No description provided for @sectionNetwork.
  ///
  /// In ru, this message translates to:
  /// **'Сеть'**
  String get sectionNetwork;

  /// No description provided for @sectionAbout.
  ///
  /// In ru, this message translates to:
  /// **'О программе'**
  String get sectionAbout;

  /// No description provided for @sectionSupport.
  ///
  /// In ru, this message translates to:
  /// **'Поддержка'**
  String get sectionSupport;

  /// No description provided for @appearanceTheme.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get appearanceTheme;

  /// No description provided for @themeSystem.
  ///
  /// In ru, this message translates to:
  /// **'Системная'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get themeDark;

  /// No description provided for @closeToTrayTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сворачивать в трей при закрытии'**
  String get closeToTrayTitle;

  /// No description provided for @closeToTraySubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Крестик прячет окно в трей; выключите — крестик закрывает приложение'**
  String get closeToTraySubtitle;

  /// No description provided for @autoUpdateSubTitle.
  ///
  /// In ru, this message translates to:
  /// **'Автообновление подписки'**
  String get autoUpdateSubTitle;

  /// No description provided for @autoUpdateSubText.
  ///
  /// In ru, this message translates to:
  /// **'Периодически обновлять список серверов'**
  String get autoUpdateSubText;

  /// No description provided for @captureSystemProxy.
  ///
  /// In ru, this message translates to:
  /// **'Системный прокси'**
  String get captureSystemProxy;

  /// No description provided for @captureSystemProxySub.
  ///
  /// In ru, this message translates to:
  /// **'Работает сейчас. Без прав администратора.'**
  String get captureSystemProxySub;

  /// No description provided for @captureTun.
  ///
  /// In ru, this message translates to:
  /// **'TUN (полный туннель)'**
  String get captureTun;

  /// No description provided for @captureTunBadgeUac.
  ///
  /// In ru, this message translates to:
  /// **'нужен UAC'**
  String get captureTunBadgeUac;

  /// No description provided for @captureTunSub.
  ///
  /// In ru, this message translates to:
  /// **'Весь трафик, включая UDP и приложения, игнорирующие прокси. Запросит права администратора.'**
  String get captureTunSub;

  /// No description provided for @tunProvider.
  ///
  /// In ru, this message translates to:
  /// **'Провайдер TUN'**
  String get tunProvider;

  /// No description provided for @tunRoutingTitle.
  ///
  /// In ru, this message translates to:
  /// **'TUN и маршрутизация'**
  String get tunRoutingTitle;

  /// No description provided for @tunRoutingSub.
  ///
  /// In ru, this message translates to:
  /// **'Стек {stack} · MTU {mtu} · DNS {dns}'**
  String tunRoutingSub(String stack, int mtu, String dns);

  /// No description provided for @splitTunnelTitle.
  ///
  /// In ru, this message translates to:
  /// **'Раздельное туннелирование'**
  String get splitTunnelTitle;

  /// No description provided for @splitRulesCount.
  ///
  /// In ru, this message translates to:
  /// **'правил {n} (приложений {apps}, сайтов {sites})'**
  String splitRulesCount(int n, int apps, int sites);

  /// No description provided for @captureTunHint.
  ///
  /// In ru, this message translates to:
  /// **'Настройки TUN, DNS и раздельного туннелирования появятся при выборе режима TUN — в режиме системного прокси они не работают.'**
  String get captureTunHint;

  /// No description provided for @captureProxyOnly.
  ///
  /// In ru, this message translates to:
  /// **'Только прокси'**
  String get captureProxyOnly;

  /// No description provided for @captureProxyOnlySub.
  ///
  /// In ru, this message translates to:
  /// **'Ядро поднято, локальные порты слушают, но компьютер не в туннеле: через VPN идёт только тот, кто явно указал наш прокси'**
  String get captureProxyOnlySub;

  /// No description provided for @apiSectionTitle.
  ///
  /// In ru, this message translates to:
  /// **'API для автоматизации'**
  String get apiSectionTitle;

  /// No description provided for @apiEnableTitle.
  ///
  /// In ru, this message translates to:
  /// **'Включить локальный API'**
  String get apiEnableTitle;

  /// No description provided for @apiEnableSub.
  ///
  /// In ru, this message translates to:
  /// **'HTTP на 127.0.0.1:{port} — управление клиентом из скриптов'**
  String apiEnableSub(int port);

  /// No description provided for @apiTokenTitle.
  ///
  /// In ru, this message translates to:
  /// **'Токен'**
  String get apiTokenTitle;

  /// No description provided for @apiTokenUnset.
  ///
  /// In ru, this message translates to:
  /// **'Не задан — API не поднимается'**
  String get apiTokenUnset;

  /// No description provided for @apiTokenRegenerate.
  ///
  /// In ru, this message translates to:
  /// **'Обновить токен'**
  String get apiTokenRegenerate;

  /// No description provided for @apiTokenWarning.
  ///
  /// In ru, this message translates to:
  /// **'Токен лежит в файле настроек открытым текстом. В журнал и отчёт для поддержки он не попадает, но тот, у кого он есть, может переключать сервер и читать состояние подписки.'**
  String get apiTokenWarning;

  /// No description provided for @apiExitsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Серверы с отдельным портом'**
  String get apiExitsTitle;

  /// No description provided for @apiExitsSub.
  ///
  /// In ru, this message translates to:
  /// **'Каждому выдаётся свой локальный порт — запрос в него идёт через этот сервер'**
  String get apiExitsSub;

  /// No description provided for @apiCopyPythonExample.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать пример для Python'**
  String get apiCopyPythonExample;

  /// No description provided for @apiPortsHint.
  ///
  /// In ru, this message translates to:
  /// **'Управление — порт {control}. «Прямо» — порт {direct}. Серверы — с {first}.'**
  String apiPortsHint(int control, int direct, int first);

  /// No description provided for @apiRulesInProxyOnly.
  ///
  /// In ru, this message translates to:
  /// **'Применять правила раздельного туннелирования'**
  String get apiRulesInProxyOnly;

  /// No description provided for @apiRulesInProxyOnlySub.
  ///
  /// In ru, this message translates to:
  /// **'В этом режиме правила по умолчанию не действуют ни для одной программы. Включите, если хотите, чтобы список «Блок» распространялся и на запросы через локальные порты.'**
  String get apiRulesInProxyOnlySub;

  /// No description provided for @apiCaptureModeWarning.
  ///
  /// In ru, this message translates to:
  /// **'⚠️ Выбран захват «Системный прокси» — порты выходов в нём не открываются, и соединение в них будет отвергнуто. Управляющий порт {control} работает при любом захвате. Нужны порты выходов — выберите «TUN (полный туннель)» или «Только прокси».'**
  String apiCaptureModeWarning(int control);

  /// No description provided for @apiPortBusyTitle.
  ///
  /// In ru, this message translates to:
  /// **'API не поднялся'**
  String get apiPortBusyTitle;

  /// No description provided for @apiPortBusy.
  ///
  /// In ru, this message translates to:
  /// **'Порт {port} занят программой {holder}. Закройте её полностью, в том числе из трея, и включите тумблер заново.'**
  String apiPortBusy(int port, String holder);

  /// No description provided for @apiPortBusyUnknown.
  ///
  /// In ru, this message translates to:
  /// **'Порт {port} занят другой программой, определить её не удалось. Чаще всего это другой VPN-клиент. Закройте его и включите тумблер заново.'**
  String apiPortBusyUnknown(int port);

  /// No description provided for @apiRulesInProxyOnlyEdit.
  ///
  /// In ru, this message translates to:
  /// **'Список «Блок» редактируется на экране раздельного туннелирования'**
  String get apiRulesInProxyOnlyEdit;

  /// No description provided for @dnsShortVpn.
  ///
  /// In ru, this message translates to:
  /// **'через VPN'**
  String get dnsShortVpn;

  /// No description provided for @dnsShortSystem.
  ///
  /// In ru, this message translates to:
  /// **'системный'**
  String get dnsShortSystem;

  /// No description provided for @dnsShortCustom.
  ///
  /// In ru, this message translates to:
  /// **'свой'**
  String get dnsShortCustom;

  /// No description provided for @tunUacTitle.
  ///
  /// In ru, this message translates to:
  /// **'TUN требует прав администратора'**
  String get tunUacTitle;

  /// No description provided for @tunUacBody.
  ///
  /// In ru, this message translates to:
  /// **'Можно настроить запуск один раз: приложение создаст задачу в Планировщике Windows с высшими правами, и дальше туннель будет стартовать БЕЗ запроса UAC.\n\nСейчас появится один запрос прав администратора. Само приложение продолжит работать без повышенных прав.'**
  String get tunUacBody;

  /// No description provided for @tunUacLater.
  ///
  /// In ru, this message translates to:
  /// **'Позже (спрашивать каждый раз)'**
  String get tunUacLater;

  /// No description provided for @tunUacSetup.
  ///
  /// In ru, this message translates to:
  /// **'Настроить'**
  String get tunUacSetup;

  /// No description provided for @tunUacDone.
  ///
  /// In ru, this message translates to:
  /// **'Готово: TUN будет запускаться без запроса UAC'**
  String get tunUacDone;

  /// No description provided for @tunUacFail.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось создать задачу — UAC будет запрашиваться при подключении'**
  String get tunUacFail;

  /// No description provided for @autoReconnectTitle.
  ///
  /// In ru, this message translates to:
  /// **'Автопереподключение'**
  String get autoReconnectTitle;

  /// No description provided for @autoReconnectSub.
  ///
  /// In ru, this message translates to:
  /// **'Восстанавливать соединение при обрыве и смене сети'**
  String get autoReconnectSub;

  /// No description provided for @killSwitchTitle.
  ///
  /// In ru, this message translates to:
  /// **'Kill switch'**
  String get killSwitchTitle;

  /// No description provided for @alwaysOnTitle.
  ///
  /// In ru, this message translates to:
  /// **'Системная защита от утечек'**
  String get alwaysOnTitle;

  /// No description provided for @alwaysOnSub.
  ///
  /// In ru, this message translates to:
  /// **'Always-on VPN и «блокировать соединения без VPN» — держит блокировку даже когда приложение закрыто'**
  String get alwaysOnSub;

  /// No description provided for @killSwitchSubTun.
  ///
  /// In ru, this message translates to:
  /// **'Не выпускать трафик мимо VPN, пока идёт восстановление'**
  String get killSwitchSubTun;

  /// No description provided for @killSwitchSubProxy.
  ///
  /// In ru, this message translates to:
  /// **'В режиме «Системный прокси» защищает только приложения, уважающие прокси. Полностью — только TUN'**
  String get killSwitchSubProxy;

  /// No description provided for @killSwitchSubOff.
  ///
  /// In ru, this message translates to:
  /// **'Требует включённого автопереподключения'**
  String get killSwitchSubOff;

  /// No description provided for @networkRecoverTitle.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить сеть'**
  String get networkRecoverTitle;

  /// No description provided for @networkRecoverSub.
  ///
  /// In ru, this message translates to:
  /// **'Если пропал интернет после VPN. Требует прав администратора'**
  String get networkRecoverSub;

  /// No description provided for @networkRecoverConfirmTitle.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить сеть?'**
  String get networkRecoverConfirmTitle;

  /// No description provided for @networkRecoverConfirmBody.
  ///
  /// In ru, this message translates to:
  /// **'Сброс winsock, IP-стека, DNS и системного прокси. Потребуются права администратора (UAC). Сброс winsock/IP вступит в силу после перезагрузки.'**
  String get networkRecoverConfirmBody;

  /// No description provided for @networkRecoverConfirmOk.
  ///
  /// In ru, this message translates to:
  /// **'Восстановить'**
  String get networkRecoverConfirmOk;

  /// No description provided for @interferenceTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверить помехи (другие VPN)'**
  String get interferenceTitle;

  /// No description provided for @interferenceDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Помехи в сети'**
  String get interferenceDialogTitle;

  /// No description provided for @interferenceNoneFound.
  ///
  /// In ru, this message translates to:
  /// **'Других VPN и вмешательств не обнаружено.'**
  String get interferenceNoneFound;

  /// No description provided for @interferenceIgnore.
  ///
  /// In ru, this message translates to:
  /// **'Игнорировать'**
  String get interferenceIgnore;

  /// No description provided for @identityUserAgent.
  ///
  /// In ru, this message translates to:
  /// **'User-Agent'**
  String get identityUserAgent;

  /// No description provided for @identityUaAutoNote.
  ///
  /// In ru, this message translates to:
  /// **'Обновляется автоматически вместе с версией приложения. Дополнительно отправляются: X-HWID, X-Device-OS, X-Ver-OS, X-App-Version ({version}).'**
  String identityUaAutoNote(String version);

  /// No description provided for @urlSchemesTitle.
  ///
  /// In ru, this message translates to:
  /// **'URL-схемы'**
  String get urlSchemesTitle;

  /// No description provided for @urlSchemesSub.
  ///
  /// In ru, this message translates to:
  /// **'Импорт и управление VPN по ссылке (connect / toggle / update)'**
  String get urlSchemesSub;

  /// No description provided for @panelOwnerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Для владельца панели'**
  String get panelOwnerTitle;

  /// No description provided for @panelOwnerBody.
  ///
  /// In ru, this message translates to:
  /// **'Обычному пользователю это не нужно — можно пропустить.\n\nЧтобы приложение получало вашу подписку в правильном JSON-формате (XRAY_JSON), добавьте этот блок в «Правила ответов» (Response Rules) панели Remnawave — он сопоставляет наш User-Agent:'**
  String get panelOwnerBody;

  /// No description provided for @panelOwnerCopy.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать блок'**
  String get panelOwnerCopy;

  /// No description provided for @aboutVersion.
  ///
  /// In ru, this message translates to:
  /// **'Версия SilentGate'**
  String get aboutVersion;

  /// No description provided for @aboutXrayCore.
  ///
  /// In ru, this message translates to:
  /// **'Ядро Xray'**
  String get aboutXrayCore;

  /// No description provided for @aboutHwid.
  ///
  /// In ru, this message translates to:
  /// **'HWID устройства'**
  String get aboutHwid;

  /// No description provided for @aboutThirdPartyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сторонние компоненты и лицензии'**
  String get aboutThirdPartyTitle;

  /// No description provided for @aboutThirdPartySub.
  ///
  /// In ru, this message translates to:
  /// **'Xray-core (MPL-2.0), sing-box (GPL-3.0), Wintun — запускаются отдельными процессами'**
  String get aboutThirdPartySub;

  /// No description provided for @aboutThirdPartySubEmbedded.
  ///
  /// In ru, this message translates to:
  /// **'Xray-core (MPL-2.0), sing-box (GPL-3.0), libXray (MIT) — встроены в приложение'**
  String get aboutThirdPartySubEmbedded;

  /// No description provided for @thirdPartyBodyEmbedded.
  ///
  /// In ru, this message translates to:
  /// **'На Android ядра ВСТРОЕНЫ в приложение (нативная библиотека внутри APK).\n\n• sing-box — GPL-3.0. Библиотека слинкована с приложением, поэтому производные обязаны оставаться под GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nИсходный код клиента: https://github.com/Solat228/silentgate\nПолные тексты лицензий — кнопками ниже.'**
  String get thirdPartyBodyEmbedded;

  /// No description provided for @logsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Логи'**
  String get logsTitle;

  /// No description provided for @logsSub.
  ///
  /// In ru, this message translates to:
  /// **'Приложение и TUN (sing-box): импорт подписки, пинг, ошибки'**
  String get logsSub;

  /// No description provided for @thirdPartyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сторонние компоненты'**
  String get thirdPartyTitle;

  /// No description provided for @thirdPartyBody.
  ///
  /// In ru, this message translates to:
  /// **'SilentGate поставляется вместе со сторонними исполняемыми файлами. Они запускаются ОТДЕЛЬНЫМИ процессами и не встроены в приложение.\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  TUN-туннель и прокси-ядро для Hysteria2\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — лицензия Wintun\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — данные маршрутизации, CC-BY-SA-4.0\n\nПолные тексты лицензий — в папке «licenses» рядом с приложением.'**
  String get thirdPartyBody;

  /// No description provided for @supportSectionNote.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите «Написать в поддержку» — откроется окно, где вы сами сгенерируете файл-лог (версии, ОС, настройки, app.log + хвост singbox.log; без паролей и токена подписки, URL скрыт). После этого появится кнопка отправки в Telegram поддержки.'**
  String get supportSectionNote;

  /// No description provided for @supportButtonTitle.
  ///
  /// In ru, this message translates to:
  /// **'Написать в поддержку'**
  String get supportButtonTitle;

  /// No description provided for @supportButtonSub.
  ///
  /// In ru, this message translates to:
  /// **'Сгенерировать лог и открыть чат поддержки'**
  String get supportButtonSub;

  /// No description provided for @supportDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Поддержка'**
  String get supportDialogTitle;

  /// No description provided for @supportDialogTitleDone.
  ///
  /// In ru, this message translates to:
  /// **'Лог готов — кому отправить'**
  String get supportDialogTitleDone;

  /// No description provided for @supportWhatWillHappen.
  ///
  /// In ru, this message translates to:
  /// **'Что будет сделано:'**
  String get supportWhatWillHappen;

  /// No description provided for @supportBullet1.
  ///
  /// In ru, this message translates to:
  /// **'• В один файл соберутся версии, ОС, настройки и логи (app.log + хвост singbox.log). Паролей и токена подписки в нём нет, URL подписки скрыт.'**
  String get supportBullet1;

  /// No description provided for @supportBullet2.
  ///
  /// In ru, this message translates to:
  /// **'• После нажатия откроется СНАЧАЛА папка с файлом, затем сам файл. Впишите описание проблемы вверху, сохраните — и появится кнопка отправки в поддержку.'**
  String get supportBullet2;

  /// No description provided for @supportError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось собрать отчёт: {error}'**
  String supportError(String error);

  /// No description provided for @supportDoneText.
  ///
  /// In ru, this message translates to:
  /// **'Отчёт собран и открыт (папка, затем файл). Впишите описание проблемы вверху, сохраните файл и отправьте его в поддержку — приложение поможет открыть Telegram.'**
  String get supportDoneText;

  /// No description provided for @supportWhoTo.
  ///
  /// In ru, this message translates to:
  /// **'Кому отправить:'**
  String get supportWhoTo;

  /// No description provided for @supportContact.
  ///
  /// In ru, this message translates to:
  /// **'Написать в поддержку'**
  String get supportContact;

  /// No description provided for @supportContactNamed.
  ///
  /// In ru, this message translates to:
  /// **'Написать в поддержку ({name})'**
  String supportContactNamed(String name);

  /// No description provided for @supportDevServiceName.
  ///
  /// In ru, this message translates to:
  /// **'Разработчик клиента'**
  String get supportDevServiceName;

  /// No description provided for @supportShowOnPc.
  ///
  /// In ru, this message translates to:
  /// **'Показать на ПК'**
  String get supportShowOnPc;

  /// No description provided for @supportCopyPath.
  ///
  /// In ru, this message translates to:
  /// **'Копировать путь'**
  String get supportCopyPath;

  /// No description provided for @supportGenerating.
  ///
  /// In ru, this message translates to:
  /// **'Собираю…'**
  String get supportGenerating;

  /// No description provided for @supportGenerateButton.
  ///
  /// In ru, this message translates to:
  /// **'Сгенерировать лог для поддержки'**
  String get supportGenerateButton;

  /// No description provided for @pingTwoPhaseTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверять работоспособность (через туннель)'**
  String get pingTwoPhaseTitle;

  /// No description provided for @pingTwoPhaseSubOn.
  ///
  /// In ru, this message translates to:
  /// **'После TCP — запрос через сервер: отсекает нерабочие (Reality и т.п.)'**
  String get pingTwoPhaseSubOn;

  /// No description provided for @pingTwoPhaseSubOff.
  ///
  /// In ru, this message translates to:
  /// **'Работает один выбранный метод (ниже)'**
  String get pingTwoPhaseSubOff;

  /// No description provided for @pingMethodCheck.
  ///
  /// In ru, this message translates to:
  /// **'Метод проверки:'**
  String get pingMethodCheck;

  /// No description provided for @pingMethodPing.
  ///
  /// In ru, this message translates to:
  /// **'Метод пинга:'**
  String get pingMethodPing;

  /// No description provided for @speedTestProbe.
  ///
  /// In ru, this message translates to:
  /// **'Проба теста скорости:'**
  String get speedTestProbe;

  /// No description provided for @speedTestFull.
  ///
  /// In ru, this message translates to:
  /// **'20 МБ (точнее)'**
  String get speedTestFull;

  /// No description provided for @speedTestLight.
  ///
  /// In ru, this message translates to:
  /// **'5 МБ (экономно)'**
  String get speedTestLight;

  /// No description provided for @testUrlLabel.
  ///
  /// In ru, this message translates to:
  /// **'Тестовый URL (via Proxy)'**
  String get testUrlLabel;

  /// No description provided for @appUpdateServerUnavailable.
  ///
  /// In ru, this message translates to:
  /// **'Сервер обновлений недоступен'**
  String get appUpdateServerUnavailable;

  /// No description provided for @appUpdateAvailable.
  ///
  /// In ru, this message translates to:
  /// **'Доступна версия {version}'**
  String appUpdateAvailable(String version);

  /// No description provided for @appUpdateLatest.
  ///
  /// In ru, this message translates to:
  /// **'У вас последняя версия'**
  String get appUpdateLatest;

  /// No description provided for @appUpdateDownload.
  ///
  /// In ru, this message translates to:
  /// **'Скачать'**
  String get appUpdateDownload;

  /// No description provided for @appUpdateCheckTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверять обновления при запуске'**
  String get appUpdateCheckTitle;

  /// No description provided for @appUpdateManual.
  ///
  /// In ru, this message translates to:
  /// **'Скачивание и установка — вручную'**
  String get appUpdateManual;

  /// No description provided for @appUpdateEndpointLabel.
  ///
  /// In ru, this message translates to:
  /// **'Эндпоинт версии'**
  String get appUpdateEndpointLabel;

  /// No description provided for @urlSchemeSilentgateTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ссылки silentgate://'**
  String get urlSchemeSilentgateTitle;

  /// No description provided for @urlSchemeSilentgateSub.
  ///
  /// In ru, this message translates to:
  /// **'Импорт и управление VPN по ссылке. Включено по умолчанию'**
  String get urlSchemeSilentgateSub;

  /// No description provided for @urlSchemeDisableTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отключить ссылки silentgate://?'**
  String get urlSchemeDisableTitle;

  /// No description provided for @urlSchemeDisableBody.
  ///
  /// In ru, this message translates to:
  /// **'Перестанут работать импорт по ссылке и управляющие схемы (connect / disconnect / toggle / update). Оставьте включённым, если не уверены.'**
  String get urlSchemeDisableBody;

  /// No description provided for @urlSchemeDisableOk.
  ///
  /// In ru, this message translates to:
  /// **'Отключить'**
  String get urlSchemeDisableOk;

  /// No description provided for @urlSchemeServerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Открывать ссылки серверов'**
  String get urlSchemeServerTitle;

  /// No description provided for @urlSchemeServerSub.
  ///
  /// In ru, this message translates to:
  /// **'Перехватить vless:// и другие у других клиентов'**
  String get urlSchemeServerSub;

  /// No description provided for @urlSchemeServerConfirmTitle.
  ///
  /// In ru, this message translates to:
  /// **'Перехватывать ссылки серверов?'**
  String get urlSchemeServerConfirmTitle;

  /// No description provided for @urlSchemeServerConfirmBody.
  ///
  /// In ru, this message translates to:
  /// **'{schemes}\n\nЭти ссылки обычно привязаны к другому VPN-клиенту (Happ, v2rayTun). SilentGate заберёт их себе.'**
  String urlSchemeServerConfirmBody(String schemes);

  /// No description provided for @urlSchemeServerConfirmOk.
  ///
  /// In ru, this message translates to:
  /// **'Перехватить'**
  String get urlSchemeServerConfirmOk;

  /// No description provided for @urlSchemeAutoConnect.
  ///
  /// In ru, this message translates to:
  /// **'Подключаться после импорта'**
  String get urlSchemeAutoConnect;

  /// No description provided for @autoTitle.
  ///
  /// In ru, this message translates to:
  /// **'Автонастройка'**
  String get autoTitle;

  /// No description provided for @autoClearResults.
  ///
  /// In ru, this message translates to:
  /// **'Очистить результаты'**
  String get autoClearResults;

  /// No description provided for @autoFoundWorking.
  ///
  /// In ru, this message translates to:
  /// **'Найдено рабочих: {count}'**
  String autoFoundWorking(Object count);

  /// No description provided for @autoPinnedTop.
  ///
  /// In ru, this message translates to:
  /// **' — закреплены сверху списка'**
  String get autoPinnedTop;

  /// No description provided for @autoSearchContinues.
  ///
  /// In ru, this message translates to:
  /// **' (поиск продолжается…)'**
  String get autoSearchContinues;

  /// No description provided for @autoCheckServices.
  ///
  /// In ru, this message translates to:
  /// **'Проверять сервисы'**
  String get autoCheckServices;

  /// No description provided for @autoPinFoundOnTop.
  ///
  /// In ru, this message translates to:
  /// **'Закреплять найденные сверху списка'**
  String get autoPinFoundOnTop;

  /// No description provided for @autoTryFragment.
  ///
  /// In ru, this message translates to:
  /// **'Перебирать обход (fragment)'**
  String get autoTryFragment;

  /// No description provided for @autoNoSubscriptionPasteKey.
  ///
  /// In ru, this message translates to:
  /// **'Подписки нет. Вставьте один ключ — подберём рабочие настройки:'**
  String get autoNoSubscriptionPasteKey;

  /// No description provided for @autoTuneByKey.
  ///
  /// In ru, this message translates to:
  /// **'Подобрать по ключу'**
  String get autoTuneByKey;

  /// No description provided for @autoTesting.
  ///
  /// In ru, this message translates to:
  /// **'Тестируется {index}/{total}: '**
  String autoTesting(int index, int total);

  /// No description provided for @autoVariant.
  ///
  /// In ru, this message translates to:
  /// **'Вариант: {label}'**
  String autoVariant(Object label);

  /// No description provided for @autoServicesPassed.
  ///
  /// In ru, this message translates to:
  /// **'сервисов {ok} из {total}'**
  String autoServicesPassed(int ok, int total);

  /// No description provided for @autoConnect.
  ///
  /// In ru, this message translates to:
  /// **'Подключиться'**
  String get autoConnect;

  /// No description provided for @autoStopSearch.
  ///
  /// In ru, this message translates to:
  /// **'Остановить поиск'**
  String get autoStopSearch;

  /// No description provided for @autoDoneRefreshPing.
  ///
  /// In ru, this message translates to:
  /// **'Готово — обновить пинг найденных'**
  String get autoDoneRefreshPing;

  /// No description provided for @autoFoundPinnedRefreshing.
  ///
  /// In ru, this message translates to:
  /// **'Найдено {count}, закреплены сверху. Обновляю пинг…'**
  String autoFoundPinnedRefreshing(Object count);

  /// No description provided for @autoServersForTuning.
  ///
  /// In ru, this message translates to:
  /// **'Серверы для подбора ({selected}/{total})'**
  String autoServersForTuning(int selected, int total);

  /// No description provided for @autoSelectAll.
  ///
  /// In ru, this message translates to:
  /// **'Все'**
  String get autoSelectAll;

  /// No description provided for @autoDeselectAll.
  ///
  /// In ru, this message translates to:
  /// **'Снять'**
  String get autoDeselectAll;

  /// No description provided for @autoTuneSelected.
  ///
  /// In ru, this message translates to:
  /// **'Подобрать для выбранных'**
  String get autoTuneSelected;

  /// No description provided for @autoTuned.
  ///
  /// In ru, this message translates to:
  /// **'Подобрано: {label}'**
  String autoTuned(Object label);

  /// No description provided for @infoDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пояснение'**
  String get infoDialogTitle;

  /// No description provided for @infoCopied.
  ///
  /// In ru, this message translates to:
  /// **'Пояснение скопировано'**
  String get infoCopied;

  /// No description provided for @commonGotIt.
  ///
  /// In ru, this message translates to:
  /// **'Понятно'**
  String get commonGotIt;

  /// No description provided for @enumSplitAll.
  ///
  /// In ru, this message translates to:
  /// **'Все — через VPN'**
  String get enumSplitAll;

  /// No description provided for @enumSplitOnly.
  ///
  /// In ru, this message translates to:
  /// **'Только отмеченные — через VPN'**
  String get enumSplitOnly;

  /// No description provided for @enumSplitExcept.
  ///
  /// In ru, this message translates to:
  /// **'Отмеченные — мимо VPN'**
  String get enumSplitExcept;

  /// No description provided for @enumActionTunnel.
  ///
  /// In ru, this message translates to:
  /// **'Туннель'**
  String get enumActionTunnel;

  /// No description provided for @enumActionDirect.
  ///
  /// In ru, this message translates to:
  /// **'Прямо'**
  String get enumActionDirect;

  /// No description provided for @enumActionBlock.
  ///
  /// In ru, this message translates to:
  /// **'Блок'**
  String get enumActionBlock;

  /// No description provided for @homeUpdateAvailable.
  ///
  /// In ru, this message translates to:
  /// **'Доступна версия {version}'**
  String homeUpdateAvailable(Object version);

  /// No description provided for @homeDownload.
  ///
  /// In ru, this message translates to:
  /// **'Скачать'**
  String get homeDownload;

  /// No description provided for @homeSubscriptionUpdated.
  ///
  /// In ru, this message translates to:
  /// **'Подписка обновлена: {summary}'**
  String homeSubscriptionUpdated(Object summary);

  /// No description provided for @homeReconnect.
  ///
  /// In ru, this message translates to:
  /// **'Переподключить'**
  String get homeReconnect;

  /// No description provided for @homePingProgress.
  ///
  /// In ru, this message translates to:
  /// **'Пинг серверов: {done} из {total}'**
  String homePingProgress(int done, int total);

  /// No description provided for @homeAutoConfigStarting.
  ///
  /// In ru, this message translates to:
  /// **'Автонастройка запускается…'**
  String get homeAutoConfigStarting;

  /// No description provided for @homeAutoConfigProgress.
  ///
  /// In ru, this message translates to:
  /// **'Автонастройка: {current} из {total} — {name}'**
  String homeAutoConfigProgress(int current, int total, String name);

  /// No description provided for @homeImport.
  ///
  /// In ru, this message translates to:
  /// **'Импорт'**
  String get homeImport;

  /// No description provided for @homeSettings.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get homeSettings;

  /// No description provided for @homeAutoBest.
  ///
  /// In ru, this message translates to:
  /// **'Авто (лучший сервер)'**
  String get homeAutoBest;

  /// No description provided for @homeAutoConfig.
  ///
  /// In ru, this message translates to:
  /// **'Автонастройка'**
  String get homeAutoConfig;

  /// No description provided for @homeServersCount.
  ///
  /// In ru, this message translates to:
  /// **'Серверы ({count})'**
  String homeServersCount(Object count);

  /// No description provided for @homeFoundCount.
  ///
  /// In ru, this message translates to:
  /// **'Найдено {found} из {total}'**
  String homeFoundCount(int found, int total);

  /// No description provided for @homePingServers.
  ///
  /// In ru, this message translates to:
  /// **'Пинг серверов'**
  String get homePingServers;

  /// No description provided for @homePingFound.
  ///
  /// In ru, this message translates to:
  /// **'Пинг найденных'**
  String get homePingFound;

  /// No description provided for @homeNothingFound.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get homeNothingFound;

  /// No description provided for @homeOnboardingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Начните с импорта подписки'**
  String get homeOnboardingTitle;

  /// No description provided for @homeOnboardingSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Вставьте ссылку Remnawave или отдельный ключ'**
  String get homeOnboardingSubtitle;

  /// No description provided for @homeImportSubscription.
  ///
  /// In ru, this message translates to:
  /// **'Импортировать подписку'**
  String get homeImportSubscription;

  /// No description provided for @homeSessionTraffic.
  ///
  /// In ru, this message translates to:
  /// **'За сессию: ↓ {down}   ↑ {up}'**
  String homeSessionTraffic(String down, String up);

  /// No description provided for @subBarGbUnit.
  ///
  /// In ru, this message translates to:
  /// **'ГБ'**
  String get subBarGbUnit;

  /// No description provided for @subBarUsage.
  ///
  /// In ru, this message translates to:
  /// **'{used} из {total}'**
  String subBarUsage(String used, String total);

  /// No description provided for @subBarSubscription.
  ///
  /// In ru, this message translates to:
  /// **'Подписка'**
  String get subBarSubscription;

  /// No description provided for @subBarRefreshing.
  ///
  /// In ru, this message translates to:
  /// **'Обновляю…'**
  String get subBarRefreshing;

  /// No description provided for @subBarRefreshSubscription.
  ///
  /// In ru, this message translates to:
  /// **'Обновить подписку'**
  String get subBarRefreshSubscription;

  /// No description provided for @subBarSupport.
  ///
  /// In ru, this message translates to:
  /// **'Поддержка'**
  String get subBarSupport;

  /// No description provided for @subBarRefresh.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get subBarRefresh;

  /// No description provided for @subBarAddSubscription.
  ///
  /// In ru, this message translates to:
  /// **'Добавить подписку'**
  String get subBarAddSubscription;

  /// No description provided for @subBarCopyLink.
  ///
  /// In ru, this message translates to:
  /// **'Копировать ссылку'**
  String get subBarCopyLink;

  /// No description provided for @subBarDeleteSubscription.
  ///
  /// In ru, this message translates to:
  /// **'Удалить подписку'**
  String get subBarDeleteSubscription;

  /// No description provided for @subBarLinkCopied.
  ///
  /// In ru, this message translates to:
  /// **'Ссылка скопирована'**
  String get subBarLinkCopied;

  /// No description provided for @subBarDeleteConfirmTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить подписку?'**
  String get subBarDeleteConfirmTitle;

  /// No description provided for @subBarDeleteConfirmBody.
  ///
  /// In ru, this message translates to:
  /// **'Серверы из подписки будут убраны из списка.'**
  String get subBarDeleteConfirmBody;

  /// No description provided for @subBarDeletePinned.
  ///
  /// In ru, this message translates to:
  /// **'Удалить и закреплённые ({count}) с их правками'**
  String subBarDeletePinned(Object count);

  /// No description provided for @subBarDeletePinnedHint.
  ///
  /// In ru, this message translates to:
  /// **'Иначе они останутся в списке и переживут удаление'**
  String get subBarDeletePinnedHint;

  /// No description provided for @subBarCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get subBarCancel;

  /// No description provided for @subBarDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get subBarDelete;

  /// No description provided for @subBarSubscriptionDeleted.
  ///
  /// In ru, this message translates to:
  /// **'Подписка удалена'**
  String get subBarSubscriptionDeleted;

  /// No description provided for @subBarSubscriptionUpdated.
  ///
  /// In ru, this message translates to:
  /// **'Подписка обновлена: {summary}'**
  String subBarSubscriptionUpdated(Object summary);

  /// No description provided for @subBarMore.
  ///
  /// In ru, this message translates to:
  /// **'Подробнее'**
  String get subBarMore;

  /// No description provided for @subBarAdded.
  ///
  /// In ru, this message translates to:
  /// **'Добавлены ({count})'**
  String subBarAdded(Object count);

  /// No description provided for @subBarRemoved.
  ///
  /// In ru, this message translates to:
  /// **'Удалены ({count})'**
  String subBarRemoved(Object count);

  /// No description provided for @subBarAutoUpdate.
  ///
  /// In ru, this message translates to:
  /// **'· автообновление {hours}ч'**
  String subBarAutoUpdate(Object hours);

  /// No description provided for @subBarValidPerpetual.
  ///
  /// In ru, this message translates to:
  /// **'Действует: бессрочно  {auto}'**
  String subBarValidPerpetual(Object auto);

  /// No description provided for @subBarExpired.
  ///
  /// In ru, this message translates to:
  /// **'Подписка истекла:'**
  String get subBarExpired;

  /// No description provided for @subBarValidUntil.
  ///
  /// In ru, this message translates to:
  /// **'Действует до:'**
  String get subBarValidUntil;

  /// No description provided for @infoCaptureMode.
  ///
  /// In ru, this message translates to:
  /// **'Как перехватывается трафик. «Системный прокси» — прописывает локальный прокси в системе (без прав администратора, ловит браузеры и большинство приложений). «TUN» — виртуальный сетевой адаптер, ловит ВЕСЬ трафик (в т.ч. UDP и приложения, игнорирующие прокси), но требует прав администратора.'**
  String get infoCaptureMode;

  /// No description provided for @infoSystemProxy.
  ///
  /// In ru, this message translates to:
  /// **'Локальный HTTP-прокси в системных настройках (реестр WinINET). Без прав администратора. Не перехватывает UDP и приложения, игнорирующие системный прокси.'**
  String get infoSystemProxy;

  /// No description provided for @infoTunMode.
  ///
  /// In ru, this message translates to:
  /// **'Полный туннель через виртуальный адаптер wintun + sing-box. Ловит весь трафик, включая UDP. Запрашивает права администратора (UAC) при включении.'**
  String get infoTunMode;

  /// No description provided for @infoTunProvider.
  ///
  /// In ru, this message translates to:
  /// **'Драйвер виртуального сетевого адаптера. На Windows используется wintun (поставляется с ядром). Другие драйверы не требуются.'**
  String get infoTunProvider;

  /// No description provided for @infoTunStack.
  ///
  /// In ru, this message translates to:
  /// **'Сетевой стек TUN (sing-box).\n\n«auto» — АВТОПОДБОР: если туннель не поднялся, приложение само перебирает system → gvisor → mixed, а затем уменьшает MTU (1400, 1280). Комбинация, на которой всё заработало, запоминается и в следующий раз пробуется первой. Ход подбора виден в статусе и в логе.\n\nЯвный выбор отключает подбор: system — стек ОС, быстрее всего, но капризнее к антивирусам; gvisor — userspace, медленнее, максимально совместим; mixed — TCP через system, UDP через gvisor.'**
  String get infoTunStack;

  /// No description provided for @infoTunMtu.
  ///
  /// In ru, this message translates to:
  /// **'Максимальный размер пакета в TUN-адаптере. По умолчанию 1500; уменьшайте (1400, 1280), если бывают обрывы — слишком маленький снижает скорость.\n\nПри стеке «auto» это лишь стартовое значение: если туннель не поднимется, приложение само попробует меньшие MTU.'**
  String get infoTunMtu;

  /// No description provided for @infoTunStrictRoute.
  ///
  /// In ru, this message translates to:
  /// **'Строгая маршрутизация sing-box. На Windows лечит две типовые беды: утечку DNS (система по умолчанию шлёт запросы во все адаптеры сразу) и ошибки «сеть недоступна». Выключайте, только если ломает VirtualBox/Hyper-V.'**
  String get infoTunStrictRoute;

  /// No description provided for @infoTunIpv6.
  ///
  /// In ru, this message translates to:
  /// **'Вести IPv6 внутрь туннеля. Если выключить, а у провайдера IPv6 включён, часть трафика пойдёт МИМО VPN (утечка реального адреса) либо будет зависать. Выключайте только при проблемах с IPv6-сетью.'**
  String get infoTunIpv6;

  /// No description provided for @infoTunEndpointIndependentNat.
  ///
  /// In ru, this message translates to:
  /// **'Режим NAT для UDP. Нужен играм, голосовым чатам и WebRTC — без него соединения могут не устанавливаться. Отключайте только для экономии памяти.'**
  String get infoTunEndpointIndependentNat;

  /// No description provided for @infoTunBypassLan.
  ///
  /// In ru, this message translates to:
  /// **'Локальная сеть (частные адреса 192.168.*, 10.*, роутер, принтеры, NAS) идёт мимо VPN. Обычно нужно включённым, иначе пропадёт доступ к устройствам в сети.'**
  String get infoTunBypassLan;

  /// No description provided for @infoTunExcludeCidrs.
  ///
  /// In ru, this message translates to:
  /// **'Дополнительные подсети, которые всегда идут мимо VPN (формат CIDR, напр. 10.8.0.0/24). Полезно для корпоративных сетей и других VPN.'**
  String get infoTunExcludeCidrs;

  /// No description provided for @infoTunPrivilege.
  ///
  /// In ru, this message translates to:
  /// **'TUN требует прав администратора. Один раз создаём задачу в Планировщике Windows с высшими правами — после этого туннель стартует БЕЗ запроса UAC при каждом подключении. Задача принадлежит вам и удаляется кнопкой ниже или при удалении программы.'**
  String get infoTunPrivilege;

  /// No description provided for @infoAppUpdate.
  ///
  /// In ru, this message translates to:
  /// **'Раз в запуск приложение спрашивает у вашего сервера, нет ли версии новее, и показывает уведомление с кнопкой «Скачать».\n\nПриложение НИЧЕГО не скачивает и не запускает само: установщик не подписан сертификатом, и самозапуск скачанного exe упирается в SmartScreen и выглядит для антивирусов как поведение зловреда. Обновление ставите вы.\n\nЕсли сервер недоступен — приложение просто молчит, запись уходит в лог. Формат ответа и настройка сервера описаны в docs/APP_UPDATE.md.'**
  String get infoAppUpdate;

  /// No description provided for @infoSpeedTest.
  ///
  /// In ru, this message translates to:
  /// **'Объём данных, который скачивается при замере скорости (ПКМ по серверу → «Информация о сервере» → «Измерить скорость»).\n\n20 МБ — основной режим: на быстрых каналах (100+ Мбит/с) короткая проба не успевает разогнаться и занижает результат.\n5 МБ — экономный: заметно дешевле по трафику, удобно прогнать много серверов.\n\nЗамер запускается ТОЛЬКО вручную и расходует трафик вашей подписки. Скорость меряется дважды: напрямую и через выбранный сервер, чтобы было видно, сколько именно теряется на VPN.'**
  String get infoSpeedTest;

  /// No description provided for @infoAutoReconnect.
  ///
  /// In ru, this message translates to:
  /// **'Если ядро упало, сервер отвалился или сменилась сеть (Wi-Fi ↔ кабель, выход из сна, новый IP) — приложение само поднимает подключение заново. Паузы между попытками растут: 0,8 с → 3 с → 8 с → 20 с, до 8 попыток, после чего показывается ошибка. Отключение кнопкой всегда отменяет восстановление.\n\nСмена сети определяется по реальным адресам чужих адаптеров: собственный туннель и служебные адреса (link-local) не учитываются, изменение принимается только если продержалось два опроса подряд, и первые 15 секунд после подключения сигнал игнорируется. Без этих предохранителей подъём туннеля сам считался «сменой сети» и вызывал бесконечное переподключение.'**
  String get infoAutoReconnect;

  /// No description provided for @infoKillSwitch.
  ///
  /// In ru, this message translates to:
  /// **'Не выпускать трафик мимо VPN, пока соединение восстанавливается. Захват НЕ снимается между попытками: в TUN-режиме адаптер остаётся поднятым, в режиме «Системный прокси» прокси остаётся прописанным — приложения получают ошибку соединения вместо незашифрованного выхода в интернет.\n\nЧестно о границах: в режиме «Системный прокси» это защищает только программы, уважающие системный прокси (браузеры и большинство приложений). Программы, игнорирующие прокси, и UDP пойдут напрямую — полную герметичность даёт только TUN-режим. Требует включённого автопереподключения.'**
  String get infoKillSwitch;

  /// No description provided for @infoUserAgent.
  ///
  /// In ru, this message translates to:
  /// **'Как приложение представляется панели (заголовок User-Agent). Всегда отправляется «SilentGate/версия (Windows)».\n\nПанель Remnawave по этому имени выбирает ФОРМАТ подписки. Нужен XRAY_JSON — в нём приходят готовые конфиги серверов; из base64-списка ссылок часть настроек восстанавливается приблизительно, и автовыбор (burstObservatory) работает хуже.\n\nНастраивается в панели: Templates → Response Rules → правило с условием user-agent CONTAINS SilentGate и типом ответа XRAY_JSON (поставьте его выше правила Fallback Base64).\n\nПоле переопределения нужно только как временный обходной путь — если панель ещё не знает приложение, можно представиться клиентом, который она знает.'**
  String get infoUserAgent;

  /// No description provided for @infoDnsMode.
  ///
  /// In ru, this message translates to:
  /// **'Кто резолвит домены в TUN-режиме. «Через VPN» (рекомендуется) — запросы уходят в туннель по TCP, провайдер не видит, какие сайты вы открываете. «Системный» — как в Windows: возможна утечка DNS, а если сервер не пропускает UDP — интернет может пропасть совсем. «Свой» — указанный вами сервер через туннель.'**
  String get infoDnsMode;

  /// No description provided for @infoDnsCustomServer.
  ///
  /// In ru, this message translates to:
  /// **'Адрес DNS-сервера для режима «Свой» (например 9.9.9.9 или 8.8.8.8). Запросы к нему идут через туннель по TCP.'**
  String get infoDnsCustomServer;

  /// No description provided for @infoDnsHijack.
  ///
  /// In ru, this message translates to:
  /// **'Перехватывать DNS-запросы (UDP порт 53) внутри туннеля. Без этого запросы уходят мимо правил: возможна утечка, а доменные правила раздельного туннелирования работают менее точно.'**
  String get infoDnsHijack;

  /// No description provided for @infoDnsStrategy.
  ///
  /// In ru, this message translates to:
  /// **'Какие адреса запрашивать: prefer_ipv4 (рекомендуется) — сначала IPv4, ipv4_only — только IPv4 (лечит проблемы с кривым IPv6), prefer_ipv6/ipv6_only — для IPv6-сетей.'**
  String get infoDnsStrategy;

  /// No description provided for @infoSingboxLogLevel.
  ///
  /// In ru, this message translates to:
  /// **'Подробность лога sing-box (%APPDATA%\\SilentGate\\singbox.log). warn — обычный режим. info/debug — если туннель не работает: в логе будет видна точная причина. debug заметно увеличивает размер файла.'**
  String get infoSingboxLogLevel;

  /// No description provided for @infoSplitMode.
  ///
  /// In ru, this message translates to:
  /// **'База — куда идёт всё, чему не задано действие вручную, и какое действие присваивается новым записям. «Все — через VPN»: по умолчанию весь трафик в туннель. «Только отмеченные — через VPN»: по умолчанию напрямую, в туннель — лишь помеченные «Туннель». «Отмеченные — мимо VPN»: наоборот, всё в туннель, а помеченные «Прямо» — напрямую.'**
  String get infoSplitMode;

  /// No description provided for @infoSplitApps.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите на приложение — откроется окно, где выбираются действие (Туннель — через VPN, Прямо — мимо VPN, Блок — нет сети) и способ сопоставления: по имени exe (надёжно) или по полному пути. Можно выбрать из запущенных или указать .exe.'**
  String get infoSplitApps;

  /// No description provided for @infoSplitDomains.
  ///
  /// In ru, this message translates to:
  /// **'Домены (суффиксы). Например, youtube.com покрывает и www.youtube.com. Работает по имени из TLS-соединения (SNI).'**
  String get infoSplitDomains;

  /// No description provided for @infoVerifyViaProxy.
  ///
  /// In ru, this message translates to:
  /// **'Сначала проверяем работоспособность через прокси (сервер реально отдаёт 204), и только если сервер ответил — отдельно измеряем задержку выбранным методом (TCP/ICMP).'**
  String get infoVerifyViaProxy;

  /// No description provided for @infoProxyGet.
  ///
  /// In ru, this message translates to:
  /// **'Запрос GET через туннель к тест-URL. Проверяет, что сервер реально пропускает трафик и отдаёт 204. Самый честный тест работоспособности; чуть медленнее.'**
  String get infoProxyGet;

  /// No description provided for @infoProxyHead.
  ///
  /// In ru, this message translates to:
  /// **'Как GET, но только заголовки — быстрее и меньше трафика. Отдельные серверы/CDN могут не поддерживать HEAD.'**
  String get infoProxyHead;

  /// No description provided for @infoTcp.
  ///
  /// In ru, this message translates to:
  /// **'Время TCP-рукопожатия до адреса сервера. Быстрый и точный показатель задержки, но не доказывает работу туннеля: Reality-сервер ответит на TCP даже если проксирование заблокировано. Рекомендуется для задержки.'**
  String get infoTcp;

  /// No description provided for @infoIcmp.
  ///
  /// In ru, this message translates to:
  /// **'Системный ping. Часто бесполезен для Reality/CDN: ICMP могут блокировать, либо он меряет ближайший узел CDN. Оставляйте для диагностики сети.'**
  String get infoIcmp;

  /// No description provided for @infoTestUrl.
  ///
  /// In ru, this message translates to:
  /// **'URL для проверки работоспособности через прокси. По умолчанию https://www.gstatic.com/generate_204 — отдаёт пустой ответ 204, что удобно и быстро.'**
  String get infoTestUrl;

  /// No description provided for @infoAutoConfig.
  ///
  /// In ru, this message translates to:
  /// **'Перебирает серверы и варианты обхода (fragment, fingerprint) и собирает список тех, где работают выбранные сервисы. Не останавливается на первом — вы выбираете из найденных. Проверка через прокси, VPN на это время не включается.'**
  String get infoAutoConfig;

  /// No description provided for @infoAutoConfigServices.
  ///
  /// In ru, this message translates to:
  /// **'Какие сервисы должны работать, чтобы сервер считался пригодным. Проверка устойчива к заглушкам провайдера (сверяется сигнатура ответа, а не просто «200 OK»).'**
  String get infoAutoConfigServices;

  /// No description provided for @infoAutoPinFound.
  ///
  /// In ru, this message translates to:
  /// **'Найденные рабочие связки (сервер + вариация обхода) сразу закрепляются сверху общего списка серверов, чтобы ими можно было пользоваться не возвращаясь сюда. Выключите, если не хотите, чтобы автонастройка меняла порядок вашего списка — результаты останутся видны на этом экране.'**
  String get infoAutoPinFound;

  /// No description provided for @infoTryFragment.
  ///
  /// In ru, this message translates to:
  /// **'Пробовать вариант с фрагментацией TLS ClientHello (обход DPI), если «голый» сервер не работает. Немного дольше, но находит рабочую связку на зарезанных серверах.'**
  String get infoTryFragment;

  /// No description provided for @infoAutoStrategy.
  ///
  /// In ru, this message translates to:
  /// **'«Первый рабочий» — перебрать всё и подключиться к любому найденному (вы выбираете). «Лучший за бюджет» — искать в пределах времени и выбрать самый быстрый.'**
  String get infoAutoStrategy;

  /// No description provided for @infoScheme.
  ///
  /// In ru, this message translates to:
  /// **'Регистрирует протокол silentgate:// в системе (для текущего пользователя, без прав администратора). После этого клик по ссылке silentgate://import?url=… (импорт) или silentgate://connect / toggle (управление) в браузере открывает приложение и выполняет действие. Включено по умолчанию.'**
  String get infoScheme;

  /// No description provided for @infoAutoConnectAfterImport.
  ///
  /// In ru, this message translates to:
  /// **'Сразу подключаться к первому серверу после успешного импорта подписки по ссылке.'**
  String get infoAutoConnectAfterImport;

  /// No description provided for @infoNetworkRecover.
  ///
  /// In ru, this message translates to:
  /// **'Сброс сетевых параметров, если после сбоя/выключения ПК с включённым VPN пропал интернет: winsock, IP-стек, DNS-кэш, системный прокси. Требует прав администратора; сброс winsock и IP-стека вступает в силу после ПЕРЕЗАГРУЗКИ.'**
  String get infoNetworkRecover;

  /// No description provided for @infoInterference.
  ///
  /// In ru, this message translates to:
  /// **'Проверка других VPN и вмешательств в сеть (чужие TUN-адаптеры, процессы VPN, zapret/GoodbyeDPI), которые могут конфликтовать с SilentGate. Можно закрыть или игнорировать.'**
  String get infoInterference;

  /// No description provided for @pingInfoProxyGet.
  ///
  /// In ru, this message translates to:
  /// **'Запрос GET через туннель к тест-URL. Проверяет, что сервер реально пропускает трафик и отдаёт 204. Самый честный тест работоспособности; чуть медленнее из-за полной загрузки ответа. Рекомендуется для проверки работоспособности.'**
  String get pingInfoProxyGet;

  /// No description provided for @pingInfoProxyHead.
  ///
  /// In ru, this message translates to:
  /// **'Как GET, но запрашивает только заголовки — меньше трафика и быстрее. Проверяет работоспособность туннеля; отдельные серверы/CDN могут не поддерживать HEAD.'**
  String get pingInfoProxyHead;

  /// No description provided for @pingInfoTcp.
  ///
  /// In ru, this message translates to:
  /// **'Замер времени TCP-рукопожатия до адреса сервера. Быстрый и точный показатель задержки эндпоинта, но не доказывает, что туннель работает: Reality-сервер ответит на TCP, даже если проксирование заблокировано. Рекомендуется для задержки.'**
  String get pingInfoTcp;

  /// No description provided for @pingInfoIcmp.
  ///
  /// In ru, this message translates to:
  /// **'Системный ping (эхо-запрос). Часто бесполезен для Reality/CDN: ICMP могут блокировать, либо он измеряет ближайший узел CDN, а не сервер. Оставляйте для диагностики сети.'**
  String get pingInfoIcmp;

  /// No description provided for @pingInfoTwoPhase.
  ///
  /// In ru, this message translates to:
  /// **'После TCP-проверки ответившие сервера дополнительно проверяются запросом через туннель (GET/HEAD к тест-URL). Так отсекаются сервера, которые держат порт открытым, но трафик не проксируют. Задержка всё равно показывается по TCP.'**
  String get pingInfoTwoPhase;

  /// No description provided for @pingInfoTunStage.
  ///
  /// In ru, this message translates to:
  /// **'Полный туннель (TUN) — следующий этап. Сейчас работает режим «Системный прокси». В TUN-режиме весь трафик (включая UDP и приложения, игнорирующие прокси) пойдёт через виртуальный адаптер wintun + tun2socks. Требует прав администратора.'**
  String get pingInfoTunStage;

  /// No description provided for @pingInfoTunStack.
  ///
  /// In ru, this message translates to:
  /// **'Сетевой стек TUN (sing-box). auto — оставить на усмотрение ядра (сейчас mixed). system — стек ОС: максимальная скорость, но капризнее к правам/антивирусам. gvisor — userspace-стек: медленнее, зато самый совместимый. mixed — TCP через system, UDP через gvisor (баланс). Если TUN не подключается или рвёт соединения — попробуйте gvisor.'**
  String get pingInfoTunStack;

  /// No description provided for @pingInfoAutoConfig.
  ///
  /// In ru, this message translates to:
  /// **'При включении приложение само перебирает серверы и варианты обхода (fragment, fingerprint) и подключается к первому, где работают выбранные сервисы (проверка через прокси, без включения VPN на время перебора).'**
  String get pingInfoAutoConfig;

  /// No description provided for @logsTabApp.
  ///
  /// In ru, this message translates to:
  /// **'Приложение'**
  String get logsTabApp;

  /// No description provided for @logsTabTun.
  ///
  /// In ru, this message translates to:
  /// **'TUN (sing-box)'**
  String get logsTabTun;

  /// No description provided for @logsRefresh.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get logsRefresh;

  /// No description provided for @logsCopy.
  ///
  /// In ru, this message translates to:
  /// **'Копировать'**
  String get logsCopy;

  /// No description provided for @logsClearApp.
  ///
  /// In ru, this message translates to:
  /// **'Очистить лог приложения'**
  String get logsClearApp;

  /// No description provided for @logsCopied.
  ///
  /// In ru, this message translates to:
  /// **'Лог скопирован'**
  String get logsCopied;

  /// No description provided for @logsLoading.
  ///
  /// In ru, this message translates to:
  /// **'Загрузка…'**
  String get logsLoading;

  /// No description provided for @logsEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Пока пусто.'**
  String get logsEmpty;

  /// No description provided for @logsTunEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Пусто — TUN ещё не запускался в этой системе.'**
  String get logsTunEmpty;

  /// No description provided for @importScrDone.
  ///
  /// In ru, this message translates to:
  /// **'Импортировано'**
  String get importScrDone;

  /// No description provided for @importScrWelcome.
  ///
  /// In ru, this message translates to:
  /// **'Добро пожаловать в SilentGate'**
  String get importScrWelcome;

  /// No description provided for @importScrTitle.
  ///
  /// In ru, this message translates to:
  /// **'Импорт подписки'**
  String get importScrTitle;

  /// No description provided for @importScrSubscriptionFallback.
  ///
  /// In ru, this message translates to:
  /// **'Подписка'**
  String get importScrSubscriptionFallback;

  /// No description provided for @importScrHint.
  ///
  /// In ru, this message translates to:
  /// **'Вставьте ссылку подписки (Remnawave), deep link silentgate:// или одиночную ссылку vless:// / vmess:// / trojan:// / ss:// / hysteria2://'**
  String get importScrHint;

  /// No description provided for @importScrLoading.
  ///
  /// In ru, this message translates to:
  /// **'Загрузка…'**
  String get importScrLoading;

  /// No description provided for @importScrPasteImport.
  ///
  /// In ru, this message translates to:
  /// **'Импорт из буфера обмена'**
  String get importScrPasteImport;

  /// No description provided for @importScrImportField.
  ///
  /// In ru, this message translates to:
  /// **'Импортировать из поля'**
  String get importScrImportField;

  /// No description provided for @serversTitle.
  ///
  /// In ru, this message translates to:
  /// **'Серверы'**
  String get serversTitle;

  /// No description provided for @serversFound.
  ///
  /// In ru, this message translates to:
  /// **'Серверы — найдено {found} из {total}'**
  String serversFound(int found, int total);

  /// No description provided for @serversRefresh.
  ///
  /// In ru, this message translates to:
  /// **'Обновить подписку'**
  String get serversRefresh;

  /// No description provided for @serversPinging.
  ///
  /// In ru, this message translates to:
  /// **'Пинг идёт…'**
  String get serversPinging;

  /// No description provided for @serversPingAll.
  ///
  /// In ru, this message translates to:
  /// **'Пинговать все'**
  String get serversPingAll;

  /// No description provided for @serversPingFound.
  ///
  /// In ru, this message translates to:
  /// **'Пинговать найденные'**
  String get serversPingFound;

  /// No description provided for @serversEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Список серверов пуст. Импортируйте подписку.'**
  String get serversEmpty;

  /// No description provided for @serversNothingFound.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get serversNothingFound;

  /// No description provided for @toastCopied.
  ///
  /// In ru, this message translates to:
  /// **'Скопировано'**
  String get toastCopied;

  /// No description provided for @toastHide.
  ///
  /// In ru, this message translates to:
  /// **'Скрыть'**
  String get toastHide;

  /// No description provided for @srvInfoTitle.
  ///
  /// In ru, this message translates to:
  /// **'Информация о сервере'**
  String get srvInfoTitle;

  /// No description provided for @srvInfoProbeFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось поднять пробное соединение: {error}'**
  String srvInfoProbeFailed(Object error);

  /// No description provided for @srvInfoServerAddressFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось определить адрес сервера'**
  String get srvInfoServerAddressFailed;

  /// No description provided for @srvInfoSectionExit.
  ///
  /// In ru, this message translates to:
  /// **'Куда вы выходите'**
  String get srvInfoSectionExit;

  /// No description provided for @srvInfoExitHint.
  ///
  /// In ru, this message translates to:
  /// **'Определяется по адресу сервера — туннель для этого не поднимается.'**
  String get srvInfoExitHint;

  /// No description provided for @srvInfoAddressLocation.
  ///
  /// In ru, this message translates to:
  /// **'Адрес и локация сервера'**
  String get srvInfoAddressLocation;

  /// No description provided for @srvInfoCheckAgain.
  ///
  /// In ru, this message translates to:
  /// **'Проверить заново'**
  String get srvInfoCheckAgain;

  /// No description provided for @srvInfoSectionSpeed.
  ///
  /// In ru, this message translates to:
  /// **'Скорость'**
  String get srvInfoSectionSpeed;

  /// No description provided for @srvInfoSpeedHint.
  ///
  /// In ru, this message translates to:
  /// **'Проба скачивает {size} и расходует трафик подписки. Размер меняется в настройках.'**
  String srvInfoSpeedHint(Object size);

  /// No description provided for @srvInfoViaServer.
  ///
  /// In ru, this message translates to:
  /// **'Через сервер'**
  String get srvInfoViaServer;

  /// No description provided for @srvInfoWithoutVpn.
  ///
  /// In ru, this message translates to:
  /// **'Без VPN'**
  String get srvInfoWithoutVpn;

  /// No description provided for @srvInfoMeasuring.
  ///
  /// In ru, this message translates to:
  /// **'Измеряю…'**
  String get srvInfoMeasuring;

  /// No description provided for @srvInfoMeasureSpeed.
  ///
  /// In ru, this message translates to:
  /// **'Измерить скорость'**
  String get srvInfoMeasureSpeed;

  /// No description provided for @srvInfoSectionParams.
  ///
  /// In ru, this message translates to:
  /// **'Параметры подключения'**
  String get srvInfoSectionParams;

  /// No description provided for @srvInfoParamAddress.
  ///
  /// In ru, this message translates to:
  /// **'Адрес'**
  String get srvInfoParamAddress;

  /// No description provided for @srvInfoParamProtocol.
  ///
  /// In ru, this message translates to:
  /// **'Протокол'**
  String get srvInfoParamProtocol;

  /// No description provided for @srvInfoParamTransport.
  ///
  /// In ru, this message translates to:
  /// **'Транспорт'**
  String get srvInfoParamTransport;

  /// No description provided for @srvInfoParamTlsFingerprint.
  ///
  /// In ru, this message translates to:
  /// **'Отпечаток TLS'**
  String get srvInfoParamTlsFingerprint;

  /// No description provided for @srvInfoParamType.
  ///
  /// In ru, this message translates to:
  /// **'Тип'**
  String get srvInfoParamType;

  /// No description provided for @srvInfoPanelAutoProfile.
  ///
  /// In ru, this message translates to:
  /// **'Профиль автовыбора от панели'**
  String get srvInfoPanelAutoProfile;

  /// No description provided for @srvInfoCouldNotDetermine.
  ///
  /// In ru, this message translates to:
  /// **'не удалось определить'**
  String get srvInfoCouldNotDetermine;

  /// No description provided for @srvInfoCopy.
  ///
  /// In ru, this message translates to:
  /// **'Копировать'**
  String get srvInfoCopy;

  /// No description provided for @editorJsonTitle.
  ///
  /// In ru, this message translates to:
  /// **'JSON конфиг'**
  String get editorJsonTitle;

  /// No description provided for @editorCopy.
  ///
  /// In ru, this message translates to:
  /// **'Копировать'**
  String get editorCopy;

  /// No description provided for @editorClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get editorClose;

  /// No description provided for @editorTitle.
  ///
  /// In ru, this message translates to:
  /// **'Редактировать сервер'**
  String get editorTitle;

  /// No description provided for @editorFieldName.
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get editorFieldName;

  /// No description provided for @editorFieldAddress.
  ///
  /// In ru, this message translates to:
  /// **'Адрес'**
  String get editorFieldAddress;

  /// No description provided for @editorFieldPort.
  ///
  /// In ru, this message translates to:
  /// **'Порт'**
  String get editorFieldPort;

  /// No description provided for @editorFieldUuidPassword.
  ///
  /// In ru, this message translates to:
  /// **'UUID / пароль'**
  String get editorFieldUuidPassword;

  /// No description provided for @editorFieldObfs.
  ///
  /// In ru, this message translates to:
  /// **'Обфускация (обычно salamander)'**
  String get editorFieldObfs;

  /// No description provided for @editorFieldObfsPassword.
  ///
  /// In ru, this message translates to:
  /// **'Пароль обфускации'**
  String get editorFieldObfsPassword;

  /// No description provided for @editorFieldPortHopping.
  ///
  /// In ru, this message translates to:
  /// **'Порт-хоппинг (напр. 20000-21000)'**
  String get editorFieldPortHopping;

  /// No description provided for @editorAllowSelfSigned.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить самоподписанный сертификат'**
  String get editorAllowSelfSigned;

  /// No description provided for @editorAllowSelfSignedSub.
  ///
  /// In ru, this message translates to:
  /// **'Нужно, только если так настроен сервер'**
  String get editorAllowSelfSignedSub;

  /// No description provided for @editorTransport.
  ///
  /// In ru, this message translates to:
  /// **'Транспорт'**
  String get editorTransport;

  /// No description provided for @editorSecurity.
  ///
  /// In ru, this message translates to:
  /// **'Безопасность'**
  String get editorSecurity;

  /// No description provided for @editorNone.
  ///
  /// In ru, this message translates to:
  /// **'(нет)'**
  String get editorNone;

  /// No description provided for @editorCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get editorCancel;

  /// No description provided for @editorSave.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get editorSave;

  /// No description provided for @jsonProfileServers.
  ///
  /// In ru, this message translates to:
  /// **'{count} серверов{burst}'**
  String jsonProfileServers(int count, String burst);

  /// No description provided for @jsonCompositionUnknown.
  ///
  /// In ru, this message translates to:
  /// **'состав неизвестен'**
  String get jsonCompositionUnknown;

  /// No description provided for @jsonYourSavedOverride.
  ///
  /// In ru, this message translates to:
  /// **'Ваш сохранённый JSON (override)'**
  String get jsonYourSavedOverride;

  /// No description provided for @jsonPanelProfileApplied.
  ///
  /// In ru, this message translates to:
  /// **'Профиль автовыбора от панели: {summary} — применяется целиком'**
  String jsonPanelProfileApplied(Object summary);

  /// No description provided for @jsonPanelConfig.
  ///
  /// In ru, this message translates to:
  /// **'Конфиг от панели (XRAY_JSON)'**
  String get jsonPanelConfig;

  /// No description provided for @jsonBuiltFromShareLink.
  ///
  /// In ru, this message translates to:
  /// **'Собран из share-ссылки — панель не прислала JSON. Обновите подписку; если не помогло, проверьте правило Response Rules в панели.'**
  String get jsonBuiltFromShareLink;

  /// No description provided for @jsonInvalidJson.
  ///
  /// In ru, this message translates to:
  /// **'Некорректный JSON'**
  String get jsonInvalidJson;

  /// No description provided for @jsonSaved.
  ///
  /// In ru, this message translates to:
  /// **'Сохранено'**
  String get jsonSaved;

  /// No description provided for @jsonTitle.
  ///
  /// In ru, this message translates to:
  /// **'JSON конфиг'**
  String get jsonTitle;

  /// No description provided for @jsonFieldEditor.
  ///
  /// In ru, this message translates to:
  /// **'Редактор полей'**
  String get jsonFieldEditor;

  /// No description provided for @jsonCopy.
  ///
  /// In ru, this message translates to:
  /// **'Копировать'**
  String get jsonCopy;

  /// No description provided for @jsonClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get jsonClose;

  /// No description provided for @jsonSave.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get jsonSave;

  /// No description provided for @srvTileEdit.
  ///
  /// In ru, this message translates to:
  /// **'Редактировать'**
  String get srvTileEdit;

  /// No description provided for @srvTileNotice.
  ///
  /// In ru, this message translates to:
  /// **'Уведомление'**
  String get srvTileNotice;

  /// No description provided for @srvTileRefresh.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get srvTileRefresh;

  /// No description provided for @srvTileSubscriptionUpdated.
  ///
  /// In ru, this message translates to:
  /// **'Подписка обновлена'**
  String get srvTileSubscriptionUpdated;

  /// No description provided for @srvTileCopy.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать'**
  String get srvTileCopy;

  /// No description provided for @srvTileInfo.
  ///
  /// In ru, this message translates to:
  /// **'Информация о сервере'**
  String get srvTileInfo;

  /// No description provided for @srvTilePing.
  ///
  /// In ru, this message translates to:
  /// **'Пинговать'**
  String get srvTilePing;

  /// No description provided for @srvTileUnpin.
  ///
  /// In ru, this message translates to:
  /// **'Открепить'**
  String get srvTileUnpin;

  /// No description provided for @srvTilePin.
  ///
  /// In ru, this message translates to:
  /// **'Закрепить'**
  String get srvTilePin;

  /// No description provided for @srvTileJsonConfig.
  ///
  /// In ru, this message translates to:
  /// **'JSON конфиг'**
  String get srvTileJsonConfig;

  /// No description provided for @srvTileSmart.
  ///
  /// In ru, this message translates to:
  /// **'Умный подбор параметров'**
  String get srvTileSmart;

  /// No description provided for @srvTileDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get srvTileDelete;

  /// No description provided for @srvTileServerDeleted.
  ///
  /// In ru, this message translates to:
  /// **'Сервер удалён'**
  String get srvTileServerDeleted;

  /// No description provided for @srvTileSaved.
  ///
  /// In ru, this message translates to:
  /// **'Сохранено'**
  String get srvTileSaved;

  /// No description provided for @pingNa.
  ///
  /// In ru, this message translates to:
  /// **'n/a'**
  String get pingNa;

  /// No description provided for @pingNaTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Не ответил по TCP — сервер недоступен (мёртв)'**
  String get pingNaTooltip;

  /// No description provided for @pingTimeout.
  ///
  /// In ru, this message translates to:
  /// **'таймаут'**
  String get pingTimeout;

  /// No description provided for @pingTimeoutTooltip.
  ///
  /// In ru, this message translates to:
  /// **'TCP-проба не уложилась в таймаут — сервер недоступен'**
  String get pingTimeoutTooltip;

  /// No description provided for @pingMs.
  ///
  /// In ru, this message translates to:
  /// **'{ms} мс'**
  String pingMs(Object ms);

  /// No description provided for @pingNoProxy.
  ///
  /// In ru, this message translates to:
  /// **'нет прокси'**
  String get pingNoProxy;

  /// No description provided for @pingNoProxyTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Отвечает по TCP (задержка показана), но проверка через туннель (GET/HEAD) не прошла — трафик не идёт'**
  String get pingNoProxyTooltip;

  /// No description provided for @pingOk.
  ///
  /// In ru, this message translates to:
  /// **'ok'**
  String get pingOk;

  /// No description provided for @pingOkTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Задержка TCP до сервера. Сервер рабочий: ответил по TCP и прошёл проверку через туннель (GET/HEAD)'**
  String get pingOkTooltip;

  /// No description provided for @searchHint.
  ///
  /// In ru, this message translates to:
  /// **'Поиск по названию, стране, адресу…'**
  String get searchHint;

  /// No description provided for @searchReset.
  ///
  /// In ru, this message translates to:
  /// **'Сбросить'**
  String get searchReset;

  /// No description provided for @splitTitle.
  ///
  /// In ru, this message translates to:
  /// **'Раздельное туннелирование'**
  String get splitTitle;

  /// No description provided for @splitTunOnlyBanner.
  ///
  /// In ru, this message translates to:
  /// **'Работает только в TUN-режиме. В режиме «Системный прокси» приложения сами решают, использовать ли прокси — управлять ими принудительно нельзя.'**
  String get splitTunOnlyBanner;

  /// No description provided for @splitProxyOnlyBanner.
  ///
  /// In ru, this message translates to:
  /// **'В режиме «Только прокси» перехватывать нечего: правила не действуют ни для одной программы компьютера. Список «Блок» применяется только к локальным портам API — и только если включён тумблер «Применять правила раздельного туннелирования» в разделе «Захват трафика». Остальные правила можно задать здесь заранее: они заработают при переходе на TUN.'**
  String get splitProxyOnlyBanner;

  /// No description provided for @splitEnableTun.
  ///
  /// In ru, this message translates to:
  /// **'Включить TUN'**
  String get splitEnableTun;

  /// No description provided for @splitModeHeader.
  ///
  /// In ru, this message translates to:
  /// **'Режим'**
  String get splitModeHeader;

  /// No description provided for @splitAppsHeader.
  ///
  /// In ru, this message translates to:
  /// **'Приложения'**
  String get splitAppsHeader;

  /// No description provided for @splitAppsHint.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите на приложение — действие (Туннель / Прямо / Блок) и способ сопоставления. Галочка слева включает/выключает правило.'**
  String get splitAppsHint;

  /// No description provided for @splitByName.
  ///
  /// In ru, this message translates to:
  /// **'По имени'**
  String get splitByName;

  /// No description provided for @splitByPath.
  ///
  /// In ru, this message translates to:
  /// **'По пути'**
  String get splitByPath;

  /// No description provided for @splitRuleDisabled.
  ///
  /// In ru, this message translates to:
  /// **'Отключено — правило не применяется'**
  String get splitRuleDisabled;

  /// No description provided for @splitRemove.
  ///
  /// In ru, this message translates to:
  /// **'Убрать'**
  String get splitRemove;

  /// No description provided for @splitFromRunning.
  ///
  /// In ru, this message translates to:
  /// **'Из запущенных'**
  String get splitFromRunning;

  /// No description provided for @splitPickInstalled.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать приложение'**
  String get splitPickInstalled;

  /// No description provided for @splitInstalledApps.
  ///
  /// In ru, this message translates to:
  /// **'Установленные приложения'**
  String get splitInstalledApps;

  /// No description provided for @splitPickExe.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать .exe'**
  String get splitPickExe;

  /// No description provided for @splitSitesHeader.
  ///
  /// In ru, this message translates to:
  /// **'Сайты (домены)'**
  String get splitSitesHeader;

  /// No description provided for @splitSitesHint.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите на сайт, чтобы выбрать действие (Туннель / Прямо / Блок). Домен покрывает и поддомены; поддомены группируются деревом. Можно указать порт.'**
  String get splitSitesHint;

  /// No description provided for @splitOnlyPort.
  ///
  /// In ru, this message translates to:
  /// **'только порт {port}'**
  String splitOnlyPort(Object port);

  /// No description provided for @splitProgramsFileType.
  ///
  /// In ru, this message translates to:
  /// **'Программы'**
  String get splitProgramsFileType;

  /// No description provided for @splitRunningApps.
  ///
  /// In ru, this message translates to:
  /// **'Запущенные приложения'**
  String get splitRunningApps;

  /// No description provided for @splitSearchByName.
  ///
  /// In ru, this message translates to:
  /// **'Поиск по имени'**
  String get splitSearchByName;

  /// No description provided for @splitNothingFound.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get splitNothingFound;

  /// No description provided for @splitClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get splitClose;

  /// No description provided for @splitPortRange.
  ///
  /// In ru, this message translates to:
  /// **'Порт 1–65535'**
  String get splitPortRange;

  /// No description provided for @splitAction.
  ///
  /// In ru, this message translates to:
  /// **'Действие'**
  String get splitAction;

  /// No description provided for @splitPortOptional.
  ///
  /// In ru, this message translates to:
  /// **'Порт (необязательно)'**
  String get splitPortOptional;

  /// No description provided for @splitAnyPort.
  ///
  /// In ru, this message translates to:
  /// **'любой'**
  String get splitAnyPort;

  /// No description provided for @splitPortHelper.
  ///
  /// In ru, this message translates to:
  /// **'Пусто = любой порт. Иначе правило только для этого порта'**
  String get splitPortHelper;

  /// No description provided for @splitMatching.
  ///
  /// In ru, this message translates to:
  /// **'Сопоставление'**
  String get splitMatching;

  /// No description provided for @splitByNameSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Имя exe, независимо от расположения (надёжно)'**
  String get splitByNameSubtitle;

  /// No description provided for @splitByPathSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Полный путь к exe (точное совпадение)'**
  String get splitByPathSubtitle;

  /// No description provided for @splitDone.
  ///
  /// In ru, this message translates to:
  /// **'Готово'**
  String get splitDone;

  /// No description provided for @splitEnterDomain.
  ///
  /// In ru, this message translates to:
  /// **'Введите домен'**
  String get splitEnterDomain;

  /// No description provided for @splitAddSite.
  ///
  /// In ru, this message translates to:
  /// **'Добавить сайт'**
  String get splitAddSite;

  /// No description provided for @splitPort.
  ///
  /// In ru, this message translates to:
  /// **'Порт'**
  String get splitPort;

  /// No description provided for @splitAdd.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get splitAdd;

  /// No description provided for @routeBlock.
  ///
  /// In ru, this message translates to:
  /// **'Блок'**
  String get routeBlock;

  /// No description provided for @routeBlocked.
  ///
  /// In ru, this message translates to:
  /// **'Заблокировано'**
  String get routeBlocked;

  /// No description provided for @routeYourPc.
  ///
  /// In ru, this message translates to:
  /// **'Ваш ПК'**
  String get routeYourPc;

  /// No description provided for @routeTunnel.
  ///
  /// In ru, this message translates to:
  /// **'Туннель'**
  String get routeTunnel;

  /// No description provided for @routeViaVpn.
  ///
  /// In ru, this message translates to:
  /// **'Через VPN'**
  String get routeViaVpn;

  /// No description provided for @routeVpn.
  ///
  /// In ru, this message translates to:
  /// **'VPN'**
  String get routeVpn;

  /// No description provided for @routeInternet.
  ///
  /// In ru, this message translates to:
  /// **'Интернет'**
  String get routeInternet;

  /// No description provided for @routeRest.
  ///
  /// In ru, this message translates to:
  /// **'Остальное'**
  String get routeRest;

  /// No description provided for @routeDirectly.
  ///
  /// In ru, this message translates to:
  /// **'Напрямую'**
  String get routeDirectly;

  /// No description provided for @routeDirectPlusRest.
  ///
  /// In ru, this message translates to:
  /// **'Прямо + остальное'**
  String get routeDirectPlusRest;

  /// No description provided for @routeDirect.
  ///
  /// In ru, this message translates to:
  /// **'Прямо'**
  String get routeDirect;

  /// No description provided for @routeEmptyList.
  ///
  /// In ru, this message translates to:
  /// **'список пуст'**
  String get routeEmptyList;

  /// No description provided for @trayShow.
  ///
  /// In ru, this message translates to:
  /// **'Показать'**
  String get trayShow;

  /// No description provided for @trayToggle.
  ///
  /// In ru, this message translates to:
  /// **'Подключить / Отключить'**
  String get trayToggle;

  /// No description provided for @trayQuit.
  ///
  /// In ru, this message translates to:
  /// **'Выход'**
  String get trayQuit;

  /// No description provided for @trayMinimizeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть в трей'**
  String get trayMinimizeTitle;

  /// No description provided for @trayMinimizeBody.
  ///
  /// In ru, this message translates to:
  /// **'Приложение продолжит работать в трее.'**
  String get trayMinimizeBody;

  /// No description provided for @trayDontAsk.
  ///
  /// In ru, this message translates to:
  /// **'Не спрашивать больше'**
  String get trayDontAsk;

  /// No description provided for @trayMinimizeOk.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть'**
  String get trayMinimizeOk;

  /// No description provided for @trayVpnTitle.
  ///
  /// In ru, this message translates to:
  /// **'VPN подключён'**
  String get trayVpnTitle;

  /// No description provided for @trayVpnBody.
  ///
  /// In ru, this message translates to:
  /// **'Отключить VPN и выйти из приложения?'**
  String get trayVpnBody;

  /// No description provided for @trayStay.
  ///
  /// In ru, this message translates to:
  /// **'Остаться'**
  String get trayStay;

  /// No description provided for @trayQuitVpn.
  ///
  /// In ru, this message translates to:
  /// **'Отключить и выйти'**
  String get trayQuitVpn;

  /// No description provided for @tunTaskDone.
  ///
  /// In ru, this message translates to:
  /// **'Готово: TUN будет запускаться без запроса UAC'**
  String get tunTaskDone;

  /// No description provided for @tunTaskFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось создать задачу (UAC отклонён или запрещено политикой)'**
  String get tunTaskFailed;

  /// No description provided for @tunLogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Лог TUN (sing-box)'**
  String get tunLogTitle;

  /// No description provided for @tunLogEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Лог пуст — туннель ещё не запускался.'**
  String get tunLogEmpty;

  /// No description provided for @tunCopy.
  ///
  /// In ru, this message translates to:
  /// **'Копировать'**
  String get tunCopy;

  /// No description provided for @tunClose.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть'**
  String get tunClose;

  /// No description provided for @tunTitle.
  ///
  /// In ru, this message translates to:
  /// **'TUN и маршрутизация'**
  String get tunTitle;

  /// No description provided for @tunSectionPrivilege.
  ///
  /// In ru, this message translates to:
  /// **'Права администратора'**
  String get tunSectionPrivilege;

  /// No description provided for @tunChecking.
  ///
  /// In ru, this message translates to:
  /// **'Проверяю…'**
  String get tunChecking;

  /// No description provided for @tunNoUacConfigured.
  ///
  /// In ru, this message translates to:
  /// **'Запуск без UAC настроен'**
  String get tunNoUacConfigured;

  /// No description provided for @tunUacEachConnect.
  ///
  /// In ru, this message translates to:
  /// **'UAC будет запрашиваться при каждом подключении'**
  String get tunUacEachConnect;

  /// No description provided for @tunTaskSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Задача Планировщика Windows с высшими правами (создаётся один раз).'**
  String get tunTaskSubtitle;

  /// No description provided for @tunRecreateTask.
  ///
  /// In ru, this message translates to:
  /// **'Пересоздать задачу'**
  String get tunRecreateTask;

  /// No description provided for @tunSetupOneUac.
  ///
  /// In ru, this message translates to:
  /// **'Настроить (один UAC)'**
  String get tunSetupOneUac;

  /// No description provided for @tunRemoveTask.
  ///
  /// In ru, this message translates to:
  /// **'Удалить задачу'**
  String get tunRemoveTask;

  /// No description provided for @tunSectionAdapter.
  ///
  /// In ru, this message translates to:
  /// **'Адаптер'**
  String get tunSectionAdapter;

  /// No description provided for @tunStack.
  ///
  /// In ru, this message translates to:
  /// **'Стек TUN'**
  String get tunStack;

  /// No description provided for @tunSectionRouting.
  ///
  /// In ru, this message translates to:
  /// **'Маршрутизация'**
  String get tunSectionRouting;

  /// No description provided for @tunStrictRoute.
  ///
  /// In ru, this message translates to:
  /// **'Строгая маршрутизация (strict_route)'**
  String get tunStrictRoute;

  /// No description provided for @tunIpv6.
  ///
  /// In ru, this message translates to:
  /// **'IPv6 в туннеле'**
  String get tunIpv6;

  /// No description provided for @tunEndpointNat.
  ///
  /// In ru, this message translates to:
  /// **'Endpoint-independent NAT (UDP, игры)'**
  String get tunEndpointNat;

  /// No description provided for @tunLanBypass.
  ///
  /// In ru, this message translates to:
  /// **'Локальная сеть мимо VPN'**
  String get tunLanBypass;

  /// No description provided for @tunDnsServer.
  ///
  /// In ru, this message translates to:
  /// **'DNS-сервер'**
  String get tunDnsServer;

  /// No description provided for @tunDnsHijack.
  ///
  /// In ru, this message translates to:
  /// **'Перехватывать DNS (порт 53)'**
  String get tunDnsHijack;

  /// No description provided for @tunResolveStrategy.
  ///
  /// In ru, this message translates to:
  /// **'Стратегия резолва'**
  String get tunResolveStrategy;

  /// No description provided for @tunSectionDiagnostics.
  ///
  /// In ru, this message translates to:
  /// **'Диагностика'**
  String get tunSectionDiagnostics;

  /// No description provided for @tunSingboxLogLevel.
  ///
  /// In ru, this message translates to:
  /// **'Уровень лога sing-box'**
  String get tunSingboxLogLevel;

  /// No description provided for @tunShowLog.
  ///
  /// In ru, this message translates to:
  /// **'Показать лог TUN'**
  String get tunShowLog;

  /// No description provided for @tunDnsVpn.
  ///
  /// In ru, this message translates to:
  /// **'Через VPN (рекомендуется)'**
  String get tunDnsVpn;

  /// No description provided for @tunDnsSystem.
  ///
  /// In ru, this message translates to:
  /// **'Системный'**
  String get tunDnsSystem;

  /// No description provided for @tunDnsCustom.
  ///
  /// In ru, this message translates to:
  /// **'Свой сервер'**
  String get tunDnsCustom;

  /// No description provided for @tunDnsVpnHint.
  ///
  /// In ru, this message translates to:
  /// **'Запросы уходят в туннель по TCP — без утечек'**
  String get tunDnsVpnHint;

  /// No description provided for @tunDnsSystemHint.
  ///
  /// In ru, this message translates to:
  /// **'Как в Windows: возможна утечка DNS'**
  String get tunDnsSystemHint;

  /// No description provided for @tunDnsCustomHint.
  ///
  /// In ru, this message translates to:
  /// **'Указанный сервер, тоже через туннель'**
  String get tunDnsCustomHint;

  /// No description provided for @tunExcludeSubnets.
  ///
  /// In ru, this message translates to:
  /// **'Подсети мимо VPN'**
  String get tunExcludeSubnets;

  /// No description provided for @tunAdd.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get tunAdd;

  /// No description provided for @urlGroupImport.
  ///
  /// In ru, this message translates to:
  /// **'Импорт'**
  String get urlGroupImport;

  /// No description provided for @urlGroupControl.
  ///
  /// In ru, this message translates to:
  /// **'Управление'**
  String get urlGroupControl;

  /// No description provided for @urlHintSubUrl.
  ///
  /// In ru, this message translates to:
  /// **'URL подписки'**
  String get urlHintSubUrl;

  /// No description provided for @urlHintServerLink.
  ///
  /// In ru, this message translates to:
  /// **'ссылка сервера'**
  String get urlHintServerLink;

  /// No description provided for @urlDescImportSub.
  ///
  /// In ru, this message translates to:
  /// **'Импортировать подписку'**
  String get urlDescImportSub;

  /// No description provided for @urlDescImportServer.
  ///
  /// In ru, this message translates to:
  /// **'Добавить один сервер (vless / trojan / ss / hysteria2 …)'**
  String get urlDescImportServer;

  /// No description provided for @urlDescConnect.
  ///
  /// In ru, this message translates to:
  /// **'Подключить VPN'**
  String get urlDescConnect;

  /// No description provided for @urlDescDisconnect.
  ///
  /// In ru, this message translates to:
  /// **'Отключить VPN'**
  String get urlDescDisconnect;

  /// No description provided for @urlDescToggle.
  ///
  /// In ru, this message translates to:
  /// **'Переключить VPN'**
  String get urlDescToggle;

  /// No description provided for @urlDescUpdate.
  ///
  /// In ru, this message translates to:
  /// **'Обновить активную подписку'**
  String get urlDescUpdate;

  /// No description provided for @urlSupportedImport.
  ///
  /// In ru, this message translates to:
  /// **'При импорте приложение понимает: ссылку подписки (http/https), а также одиночные серверы vless:// / vmess:// / trojan:// / ss:// / hysteria2:// (hy2://).'**
  String get urlSupportedImport;

  /// No description provided for @reportTitle.
  ///
  /// In ru, this message translates to:
  /// **'SilentGate — отчёт для техподдержки'**
  String get reportTitle;

  /// No description provided for @reportDescribeHere.
  ///
  /// In ru, this message translates to:
  /// **'>>> ОПИШИТЕ ПРОБЛЕМУ ЗДЕСЬ (заполните и сохраните файл): <<<'**
  String get reportDescribeHere;

  /// No description provided for @reportWhatDid.
  ///
  /// In ru, this message translates to:
  /// **'Что делали:'**
  String get reportWhatDid;

  /// No description provided for @reportWhatExpected.
  ///
  /// In ru, this message translates to:
  /// **'Что ожидали:'**
  String get reportWhatExpected;

  /// No description provided for @reportWhatHappened.
  ///
  /// In ru, this message translates to:
  /// **'Что произошло:'**
  String get reportWhatHappened;

  /// No description provided for @reportWhenStarted.
  ///
  /// In ru, this message translates to:
  /// **'Когда началось:'**
  String get reportWhenStarted;

  /// No description provided for @reportTechNoticeLine1.
  ///
  /// In ru, this message translates to:
  /// **'Ниже — техническая информация. Проверьте её перед отправкой;'**
  String get reportTechNoticeLine1;

  /// No description provided for @reportTechNoticeLine2.
  ///
  /// In ru, this message translates to:
  /// **'паролей и токена подписки здесь нет, URL подписки скрыт.'**
  String get reportTechNoticeLine2;

  /// No description provided for @noRealIpTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не выходить под реальным IP'**
  String get noRealIpTitle;

  /// No description provided for @noRealIpSub.
  ///
  /// In ru, this message translates to:
  /// **'Даже при рабочем VPN весь «прямой» трафик идёт через VPN (RU-сайты — тоже). Локальная сеть остаётся напрямую.'**
  String get noRealIpSub;

  /// No description provided for @flagAuto.
  ///
  /// In ru, this message translates to:
  /// **'АВТО'**
  String get flagAuto;

  /// No description provided for @autoUpdateIntervalLabel.
  ///
  /// In ru, this message translates to:
  /// **'Интервал обновления, ч'**
  String get autoUpdateIntervalLabel;

  /// No description provided for @autoUpdatePreferSub.
  ///
  /// In ru, this message translates to:
  /// **'Брать интервал из подписки'**
  String get autoUpdatePreferSub;

  /// No description provided for @pingLegendInfo.
  ///
  /// In ru, this message translates to:
  /// **'Цвет плашки пинга: зелёный/жёлтый/оранжевый — сервер рабочий (TCP + проверка через туннель). Серый — отвечает по TCP, но трафик не проксирует (типичный Reality-порт). Красный «n/a» — не ответил, из проверки исключён. Пинг всегда меряется НАПРЯМУЮ (вне VPN).'**
  String get pingLegendInfo;

  /// No description provided for @pingUntestedHint.
  ///
  /// In ru, this message translates to:
  /// **'Ещё не проверен. Hysteria2 и профили «Авто» на мобильном измеряются только при поднятом соединении.'**
  String get pingUntestedHint;

  /// No description provided for @panelTunnelMarker.
  ///
  /// In ru, this message translates to:
  /// **'Своё раздельное туннелирование'**
  String get panelTunnelMarker;

  /// No description provided for @panelInfoServers.
  ///
  /// In ru, this message translates to:
  /// **'Серверов в профиле: {n} (выбирается лучший)'**
  String panelInfoServers(Object n);

  /// No description provided for @panelInfoDirect.
  ///
  /// In ru, this message translates to:
  /// **'Часть трафика (напр. локальные сайты) идёт напрямую, мимо VPN'**
  String get panelInfoDirect;

  /// No description provided for @panelInfoBlock.
  ///
  /// In ru, this message translates to:
  /// **'Часть трафика блокируется (реклама/торренты)'**
  String get panelInfoBlock;

  /// No description provided for @serviceChecksTitle.
  ///
  /// In ru, this message translates to:
  /// **'Проверка сервисов'**
  String get serviceChecksTitle;

  /// No description provided for @serviceChecksInfo.
  ///
  /// In ru, this message translates to:
  /// **'Шесть популярных сервисов проверяются сами: первый раз — при запуске приложения, пока VPN выключен, второй — сразу после подключения. Два кружка рядом показывают «было → стало», чтобы видеть, что изменил именно VPN. Нажатие проверяет сервис заново. Зелёный — открывается, оранжевый — блокировка по стране, красный — недоступен.'**
  String get serviceChecksInfo;

  /// No description provided for @serviceStatusOk.
  ///
  /// In ru, this message translates to:
  /// **'Работает'**
  String get serviceStatusOk;

  /// No description provided for @serviceStatusGeo.
  ///
  /// In ru, this message translates to:
  /// **'Открывается, но заблокирован в стране выхода'**
  String get serviceStatusGeo;

  /// No description provided for @serviceStatusFail.
  ///
  /// In ru, this message translates to:
  /// **'Не открывается'**
  String get serviceStatusFail;

  /// No description provided for @serviceStatusChecking.
  ///
  /// In ru, this message translates to:
  /// **'Проверка…'**
  String get serviceStatusChecking;

  /// No description provided for @serviceStatusTap.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите, чтобы проверить'**
  String get serviceStatusTap;

  /// No description provided for @serviceLatencyMs.
  ///
  /// In ru, this message translates to:
  /// **'{ms} мс'**
  String serviceLatencyMs(Object ms);

  /// No description provided for @homeTunAutotuneProgress.
  ///
  /// In ru, this message translates to:
  /// **'Подбираю параметры TUN…'**
  String get homeTunAutotuneProgress;

  /// No description provided for @homeTunAutotuneDone.
  ///
  /// In ru, this message translates to:
  /// **'Параметры TUN подобраны'**
  String get homeTunAutotuneDone;

  /// No description provided for @homeTunAutotuneFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось подобрать параметры TUN'**
  String get homeTunAutotuneFailed;

  /// No description provided for @hy2NoteTitle.
  ///
  /// In ru, this message translates to:
  /// **'Серверы Hysteria2'**
  String get hy2NoteTitle;

  /// No description provided for @hy2NoteBody.
  ///
  /// In ru, this message translates to:
  /// **'Hysteria2-серверы приходят только в формате XRAY_JSON — SilentGate его и запрашивает, sing-box поднимает их автоматически. Если Hysteria2 не появляется в списке: (владельцу панели Remnawave) включите hysteria-инбаунды и назначьте их подписке. Важно: Remnawave до 2.8.0 отдаёт Hysteria2 ТОЛЬКО в XRAY_JSON — в base64/CLASH/SINGBOX её нет, поэтому правило Response Rules → XRAY_JSON выше обязательно.'**
  String get hy2NoteBody;

  /// No description provided for @enumStatusDisconnected.
  ///
  /// In ru, this message translates to:
  /// **'Отключено'**
  String get enumStatusDisconnected;

  /// No description provided for @enumStatusConnecting.
  ///
  /// In ru, this message translates to:
  /// **'Подключение…'**
  String get enumStatusConnecting;

  /// No description provided for @enumStatusConnected.
  ///
  /// In ru, this message translates to:
  /// **'Подключено'**
  String get enumStatusConnected;

  /// No description provided for @enumStatusDisconnecting.
  ///
  /// In ru, this message translates to:
  /// **'Отключение…'**
  String get enumStatusDisconnecting;

  /// No description provided for @enumStatusError.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка'**
  String get enumStatusError;

  /// No description provided for @enumVariantPlain.
  ///
  /// In ru, this message translates to:
  /// **'обычный'**
  String get enumVariantPlain;

  /// No description provided for @tagAutoSelect.
  ///
  /// In ru, this message translates to:
  /// **'АВТОВЫБОР'**
  String get tagAutoSelect;

  /// No description provided for @tagPanel.
  ///
  /// In ru, this message translates to:
  /// **'ПАНЕЛЬ'**
  String get tagPanel;

  /// No description provided for @tagPortHopping.
  ///
  /// In ru, this message translates to:
  /// **'ПОРТ-ХОППИНГ'**
  String get tagPortHopping;

  /// No description provided for @syncServersCount.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{{count} сервер} few{{count} сервера} many{{count} серверов} other{{count} сервера}}'**
  String syncServersCount(int count);

  /// No description provided for @syncNoChanges.
  ///
  /// In ru, this message translates to:
  /// **'без изменений'**
  String get syncNoChanges;

  /// No description provided for @errInvalidJson.
  ///
  /// In ru, this message translates to:
  /// **'Некорректный JSON'**
  String get errInvalidJson;

  /// No description provided for @errPickServerFirst.
  ///
  /// In ru, this message translates to:
  /// **'Сначала выберите сервер'**
  String get errPickServerFirst;

  /// No description provided for @errImportSubscriptionFirst.
  ///
  /// In ru, this message translates to:
  /// **'Сначала импортируйте подписку'**
  String get errImportSubscriptionFirst;

  /// No description provided for @speedSizeFull.
  ///
  /// In ru, this message translates to:
  /// **'20 МБ'**
  String get speedSizeFull;

  /// No description provided for @speedSizeLight.
  ///
  /// In ru, this message translates to:
  /// **'5 МБ'**
  String get speedSizeLight;

  /// No description provided for @speedMbPerSec.
  ///
  /// In ru, this message translates to:
  /// **'{value} МБ/с'**
  String speedMbPerSec(String value);

  /// No description provided for @speedKbPerSec.
  ///
  /// In ru, this message translates to:
  /// **'{value} КБ/с'**
  String speedKbPerSec(String value);

  /// No description provided for @portBusyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Порт {port} уже занят {by}.'**
  String portBusyTitle(int port, String by);

  /// No description provided for @srvTileMenu.
  ///
  /// In ru, this message translates to:
  /// **'Действия с сервером'**
  String get srvTileMenu;

  /// No description provided for @supportCopyReport.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать отчёт'**
  String get supportCopyReport;

  /// No description provided for @supportReportCopied.
  ///
  /// In ru, this message translates to:
  /// **'Отчёт скопирован — вставьте его в чат поддержки'**
  String get supportReportCopied;

  /// No description provided for @subBarUsedOnly.
  ///
  /// In ru, this message translates to:
  /// **'Израсходовано {used}'**
  String subBarUsedOnly(String used);

  /// No description provided for @subBarUnlimitedTraffic.
  ///
  /// In ru, this message translates to:
  /// **'трафик без ограничений'**
  String get subBarUnlimitedTraffic;

  /// No description provided for @supportDescribeLabel.
  ///
  /// In ru, this message translates to:
  /// **'Опишите проблему'**
  String get supportDescribeLabel;

  /// No description provided for @supportDescribeHint.
  ///
  /// In ru, this message translates to:
  /// **'Что делали, что ожидали, что произошло и когда началось'**
  String get supportDescribeHint;

  /// No description provided for @supportDescribeRequired.
  ///
  /// In ru, this message translates to:
  /// **'Опишите проблему — без описания отчёт бесполезен'**
  String get supportDescribeRequired;

  /// No description provided for @supportNoScreenshots.
  ///
  /// In ru, this message translates to:
  /// **'Скриншоты сюда не вставляйте — присылайте их отдельным сообщением в чат Telegram.'**
  String get supportNoScreenshots;

  /// No description provided for @supportDescriptionSection.
  ///
  /// In ru, this message translates to:
  /// **'ОПИСАНИЕ ОТ ПОЛЬЗОВАТЕЛЯ'**
  String get supportDescriptionSection;

  /// No description provided for @splitAllowRealIp.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить этому правилу реальный IP'**
  String get splitAllowRealIp;

  /// No description provided for @splitAllowRealIpOn.
  ///
  /// In ru, this message translates to:
  /// **'Поднята: это исключение, трафик выйдет под вашим реальным адресом'**
  String get splitAllowRealIpOn;

  /// No description provided for @splitAllowRealIpOff.
  ///
  /// In ru, this message translates to:
  /// **'Снята: правило идёт через VPN — защита выше всех правил'**
  String get splitAllowRealIpOff;

  /// No description provided for @splitRealIpExposed.
  ///
  /// In ru, this message translates to:
  /// **'реальный IP'**
  String get splitRealIpExposed;

  /// No description provided for @splitRealIpProtected.
  ///
  /// In ru, this message translates to:
  /// **'через VPN'**
  String get splitRealIpProtected;

  /// No description provided for @vpnActiveBadge.
  ///
  /// In ru, this message translates to:
  /// **'VPN активен'**
  String get vpnActiveBadge;

  /// No description provided for @splitCopyDomain.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать адрес'**
  String get splitCopyDomain;

  /// No description provided for @splitCopyPath.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать путь'**
  String get splitCopyPath;

  /// No description provided for @homeServerInfo.
  ///
  /// In ru, this message translates to:
  /// **'Информация о сервере'**
  String get homeServerInfo;

  /// No description provided for @serverInfoVerifyInBrowser.
  ///
  /// In ru, this message translates to:
  /// **'Проверить в браузере'**
  String get serverInfoVerifyInBrowser;

  /// No description provided for @tunDnsForAll.
  ///
  /// In ru, this message translates to:
  /// **'DNS всех приложений через VPN'**
  String get tunDnsForAll;

  /// No description provided for @infoDnsForAll.
  ///
  /// In ru, this message translates to:
  /// **'Работает только в режиме «Только отмеченные». Включено: ни один DNS-запрос не уходит провайдеру, но домены НЕотмеченных приложений резолвятся через туннель — CDN отдаёт адрес в стране выхода, и такие приложения идут напрямую, но на дальний сервер (заметно медленнее). Выключено: неотмеченные приложения получают близкий CDN и работают быстро, зато провайдер видит, куда ходят все приложения, включая защищаемые. ⚠️ Изменение применяется только после переподключения.'**
  String get infoDnsForAll;

  /// No description provided for @homeSettingsNeedReconnect.
  ///
  /// In ru, this message translates to:
  /// **'Настройка изменена — переподключитесь, чтобы применить'**
  String get homeSettingsNeedReconnect;

  /// No description provided for @blockPageWindowTitle.
  ///
  /// In ru, this message translates to:
  /// **'Заблокировано — {app}'**
  String blockPageWindowTitle(String app);

  /// No description provided for @blockPageHeading.
  ///
  /// In ru, this message translates to:
  /// **'Сайт заблокирован'**
  String get blockPageHeading;

  /// No description provided for @blockPageBody.
  ///
  /// In ru, this message translates to:
  /// **'Адрес {host} заблокирован правилом раздельного туннелирования в {app}.'**
  String blockPageBody(String host, String app);

  /// No description provided for @blockPageHint.
  ///
  /// In ru, this message translates to:
  /// **'Правило можно изменить: Настройки → Раздельное туннелирование → Сайты.'**
  String get blockPageHint;

  /// No description provided for @blockPageNote.
  ///
  /// In ru, this message translates to:
  /// **'Это страница самого приложения, а не ошибка сети. Сайт не открывается потому, что вы сами добавили его в список блокировки.'**
  String get blockPageNote;

  /// No description provided for @settingsBlockPage.
  ///
  /// In ru, this message translates to:
  /// **'Страница-заглушка при блокировке'**
  String get settingsBlockPage;

  /// No description provided for @settingsBlockPageSub.
  ///
  /// In ru, this message translates to:
  /// **'Вместо ошибки соединения открывается страница с объяснением, каким правилом закрыт сайт. Работает только для http: у https подменить страницу нельзя без установки своего корневого сертификата в систему, а он позволил бы читать весь ваш защищённый трафик.'**
  String get settingsBlockPageSub;

  /// No description provided for @trayCloseFully.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть полностью'**
  String get trayCloseFully;

  /// No description provided for @errorVpnConflictApp.
  ///
  /// In ru, this message translates to:
  /// **'Похоже, мешает {app}: у него поднят собственный VPN-туннель. Два туннеля одновременно борются за маршрут по умолчанию.'**
  String errorVpnConflictApp(String app);

  /// No description provided for @errorCloseApp.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть {app}'**
  String errorCloseApp(String app);

  /// No description provided for @toastAppClosed.
  ///
  /// In ru, this message translates to:
  /// **'{app} закрыт'**
  String toastAppClosed(String app);

  /// No description provided for @toastAppCloseFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось закрыть {app} — закройте вручную'**
  String toastAppCloseFailed(String app);

  /// No description provided for @tunBlockQuic.
  ///
  /// In ru, this message translates to:
  /// **'Запрещать QUIC (HTTP/3)'**
  String get tunBlockQuic;

  /// No description provided for @infoBlockQuic.
  ///
  /// In ru, this message translates to:
  /// **'Правила по сайтам применяются к ИМЕНИ, а имя приложение видит только в обычном TLS. Браузер, ушедший на HTTP/3, имени не показывает — и правило по домену молча не срабатывает. Запрет возвращает браузер на обычное соединение, где имя видно. Сайты от этого не ломаются: HTTP/3 для них не обязателен, но видео может грузиться чуть медленнее. Включайте, если правила по сайтам не действуют.'**
  String get infoBlockQuic;

  /// No description provided for @tunBlockEncryptedDns.
  ///
  /// In ru, this message translates to:
  /// **'Запрещать шифрованный DNS (DoH/DoT)'**
  String get tunBlockEncryptedDns;

  /// No description provided for @infoBlockEncryptedDns.
  ///
  /// In ru, this message translates to:
  /// **'Браузеры и Windows умеют спрашивать адреса сайтов по HTTPS в обход нашего перехвата. Тогда правила «Прямо» и «Блок» на уровне DNS не работают вовсе. Запрет возвращает запросы под наш контроль. ⚠️ Если в браузере жёстко выбран поставщик шифрованного DNS, он не откатится на обычный, а просто перестанет открывать сайты — тогда выключите настройку или уберите поставщика в браузере. Список известных поставщиков неполон по своей природе: свой можно поднять за вечер.'**
  String get infoBlockEncryptedDns;

  /// No description provided for @autoUseSpeed.
  ///
  /// In ru, this message translates to:
  /// **'Учитывать скорость'**
  String get autoUseSpeed;

  /// No description provided for @infoAutoUseSpeed.
  ///
  /// In ru, this message translates to:
  /// **'После отбора по сервисам и задержке трёх лучших кандидатов проверяем скачиванием и ставим первым того, кто реально быстрее. Скорость сравнивается с ВАШИМ каналом: сервер, отдающий почти весь ваш канал, дальше не оценивается по мегабитам — там решает задержка, потому что лишняя скорость сверх канала вам всё равно не достанется. ⚠️ Расходует трафик подписки: 5 МБ на ваш канал и по 5 МБ на каждого из трёх кандидатов, около 20 МБ за прогон.'**
  String get infoAutoUseSpeed;

  /// No description provided for @autoSpeedOwn.
  ///
  /// In ru, this message translates to:
  /// **'Замеряю скорость своего канала…'**
  String get autoSpeedOwn;

  /// No description provided for @autoSpeedServer.
  ///
  /// In ru, this message translates to:
  /// **'Замеряю скорость: {server} ({index} из {total})'**
  String autoSpeedServer(String server, int index, int total);

  /// No description provided for @autoSpeedShare.
  ///
  /// In ru, this message translates to:
  /// **'{percent} % вашего канала'**
  String autoSpeedShare(int percent);

  /// No description provided for @conflictDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Обнаружен другой VPN'**
  String get conflictDialogTitle;

  /// No description provided for @conflictDialogBody.
  ///
  /// In ru, this message translates to:
  /// **'Похоже, работает {app} — у него поднят собственный туннель. Два туннеля одновременно борются за маршрут по умолчанию, и подключение может не подняться или подняться без доступа в сеть.'**
  String conflictDialogBody(String app);

  /// No description provided for @conflictCloseAndConnect.
  ///
  /// In ru, this message translates to:
  /// **'Закрыть и подключиться'**
  String get conflictCloseAndConnect;

  /// No description provided for @conflictConnectAnyway.
  ///
  /// In ru, this message translates to:
  /// **'Всё равно подключиться'**
  String get conflictConnectAnyway;

  /// No description provided for @serviceChecksLegendBefore.
  ///
  /// In ru, this message translates to:
  /// **'Доступность сервисов проверена без VPN'**
  String get serviceChecksLegendBefore;

  /// No description provided for @serviceChecksLegendAfter.
  ///
  /// In ru, this message translates to:
  /// **'Слева — без VPN, справа — через VPN'**
  String get serviceChecksLegendAfter;

  /// No description provided for @serviceChecksBefore.
  ///
  /// In ru, this message translates to:
  /// **'Без VPN'**
  String get serviceChecksBefore;

  /// No description provided for @serviceChecksAfter.
  ///
  /// In ru, this message translates to:
  /// **'Через VPN'**
  String get serviceChecksAfter;

  /// No description provided for @serviceChecksNoBaseline.
  ///
  /// In ru, this message translates to:
  /// **'Без VPN не проверялось'**
  String get serviceChecksNoBaseline;

  /// No description provided for @autoSpeedValue.
  ///
  /// In ru, this message translates to:
  /// **'{value} Мбит/с'**
  String autoSpeedValue(String value);

  /// No description provided for @splitShowBlockPage.
  ///
  /// In ru, this message translates to:
  /// **'Показать страницу блокировки'**
  String get splitShowBlockPage;

  /// No description provided for @splitBlockPageNeedsVpn.
  ///
  /// In ru, this message translates to:
  /// **'Страница блокировки работает только при включённом VPN'**
  String get splitBlockPageNeedsVpn;

  /// No description provided for @srvInfoNeedsConnection.
  ///
  /// In ru, this message translates to:
  /// **'Замер через сервер на этой платформе возможен только при включённом VPN'**
  String get srvInfoNeedsConnection;

  /// No description provided for @serviceYoutubeThrottleNote.
  ///
  /// In ru, this message translates to:
  /// **'⚠️ Замедление YouTube эта проверка не видит: провайдер отвечает нормально, но режет скорость видео. Зелёный здесь означает «сервис доступен», а не «видео проигрывается».'**
  String get serviceYoutubeThrottleNote;

  /// No description provided for @urlSchemeConnectServer.
  ///
  /// In ru, this message translates to:
  /// **'silentgate://connect?server=<имя сервера>'**
  String get urlSchemeConnectServer;

  /// No description provided for @urlDescConnectServer.
  ///
  /// In ru, this message translates to:
  /// **'Подключиться к КОНКРЕТНОМУ серверу. Имя — то же, что видно в списке и что присылает подписка, например «Польша 1.5». Флаг-эмодзи и регистр можно опустить. Точного совпадения нет — сработает поиск: по стране, адресу или протоколу. Работает и с toggle.'**
  String get urlDescConnectServer;

  /// No description provided for @splitSelectAllFound.
  ///
  /// In ru, this message translates to:
  /// **'Отметить всё найденное'**
  String get splitSelectAllFound;

  /// No description provided for @splitAddSelected.
  ///
  /// In ru, this message translates to:
  /// **'Добавить ({count})'**
  String splitAddSelected(int count);

  /// No description provided for @splitQuicNote.
  ///
  /// In ru, this message translates to:
  /// **'Пока есть хотя бы одно правило по сайту, приложение отключает HTTP/3 (QUIC) для всего трафика. Иначе браузер уходит на HTTP/3, не оставляет имени сайта, и правило молча не срабатывает — трафик идёт мимо. Сайты от этого не ломаются: они переходят на обычный TLS, лишь чуть медленнее.'**
  String get splitQuicNote;

  /// No description provided for @splitNoRealIpBanner.
  ///
  /// In ru, this message translates to:
  /// **'Включено «Не выходить под реальным IP»: правила «Прямо» без поднятой галочки идут через VPN'**
  String get splitNoRealIpBanner;

  /// No description provided for @settingsNoRealIpAffects.
  ///
  /// In ru, this message translates to:
  /// **'Затрагивает правила «Прямо»: без галочки «разрешить реальный IP» они пойдут через VPN'**
  String get settingsNoRealIpAffects;

  /// No description provided for @splitAppOverrideSites.
  ///
  /// In ru, this message translates to:
  /// **'Важнее правил по сайтам'**
  String get splitAppOverrideSites;

  /// No description provided for @splitAppOverrideSitesSub.
  ///
  /// In ru, this message translates to:
  /// **'Весь трафик приложения идёт как указано, даже если для сайта задано другое'**
  String get splitAppOverrideSitesSub;

  /// No description provided for @settingsMyRulesOverridePanel.
  ///
  /// In ru, this message translates to:
  /// **'Мои правила важнее правил панели'**
  String get settingsMyRulesOverridePanel;

  /// No description provided for @settingsMyRulesOverridePanelSub.
  ///
  /// In ru, this message translates to:
  /// **'Панель отдаёт своё разделение — обычно «российские сайты мимо VPN». Оно применяется после ваших правил, поэтому сайт, помеченный «Туннель», может выйти напрямую под реальным IP. Включено: написано «туннель» — значит туннель. Цена: российские сайты пойдут кругом и медленнее.'**
  String get settingsMyRulesOverridePanelSub;

  /// No description provided for @commonOpen.
  ///
  /// In ru, this message translates to:
  /// **'Открыть'**
  String get commonOpen;

  /// No description provided for @tunRouteOnlySubnets.
  ///
  /// In ru, this message translates to:
  /// **'В туннель ТОЛЬКО эти подсети'**
  String get tunRouteOnlySubnets;

  /// No description provided for @infoTunRouteOnlyCidrs.
  ///
  /// In ru, this message translates to:
  /// **'Единственный способ на Windows сделать часть трафика по-настоящему независимой от VPN-клиента.\n\nОбычно туннель забирает маршрут по умолчанию, и в него заходит ВЕСЬ трафик машины: пометка «Прямо» разбирается уже внутри ядра, которое принимает пакет и выпускает его наружу от своего имени. Такой трафик живёт ровно столько, сколько живёт ядро, и зависает вместе с ним.\n\nЕсли список не пуст, маршрут по умолчанию туннелю не отдаётся: он забирает только перечисленные подсети, а всё прочее система отправляет обычным адаптером — клиент этого трафика не видит вовсе.\n\nЦена: деление идёт по адресу, а правила по приложениям и сайтам — по имени. Сайт, чей адрес не попал в список, ядро не увидит ни одним правилом. Оставьте пусто, чтобы туннель работал как обычно.'**
  String get infoTunRouteOnlyCidrs;

  /// No description provided for @tunRouteOnlyWarning.
  ///
  /// In ru, this message translates to:
  /// **'Туннель забирает только перечисленные подсети. Правила по приложениям и сайтам действуют ТОЛЬКО внутри них: то, что в туннель не зашло, ядру не показали — заблокировать или увести такой сайт нельзя.'**
  String get tunRouteOnlyWarning;

  /// No description provided for @tunAlsoSystemProxy.
  ///
  /// In ru, this message translates to:
  /// **'Системный прокси вместе с туннелем'**
  String get tunAlsoSystemProxy;

  /// No description provided for @infoTunAlsoSystemProxy.
  ///
  /// In ru, this message translates to:
  /// **'Смешанный режим: работает и туннель, и системный прокси одновременно.\n\nПриложения, которые уважают системный прокси (браузеры, Telegram), пойдут коротким путём прямо в локальный порт, минуя пользовательский стек туннеля, и отдадут ядру имя домена вместо голого адреса — правила по сайтам для них станут точнее и перестанут зависеть от разбора TLS.\n\nНезависимыми от клиента они при этом НЕ становятся: ходят через тот же процесс.'**
  String get infoTunAlsoSystemProxy;

  /// No description provided for @tunMixedModeWarning.
  ///
  /// In ru, this message translates to:
  /// **'У соединения, пришедшего через системный прокси, нет процесса-владельца — для ядра это локальное подключение. Поэтому правила ПО ПРИЛОЖЕНИЯМ для таких программ не срабатывают. Правила по сайтам работают, и даже точнее обычного.'**
  String get tunMixedModeWarning;

  /// No description provided for @tunWatchdog.
  ///
  /// In ru, this message translates to:
  /// **'Сторож зависшего ядра'**
  String get tunWatchdog;

  /// No description provided for @infoTunWatchdog.
  ///
  /// In ru, this message translates to:
  /// **'Сколько секунд ядру туннеля можно не отвечать, прежде чем считать его зависшим и снять туннель.\n\nЕсли ядро падает, Windows убирает за ним сама — адаптер, маршруты и правила брандмауэра снимаются, сеть возвращается. Если ядро зависает, не снимается ничего: адаптер остаётся и глотает весь трафик машины, включая помеченный «Прямо». Снаружи это «интернет пропал совсем», и само оно не проходит.\n\nСторож вооружается только после первого успешного ответа ядра: иначе он убивал бы подключение там, где не удалось поднять служебный порт. 0 — не следить. Минимум 10 секунд.'**
  String get infoTunWatchdog;

  /// No description provided for @tunWatchdogOff.
  ///
  /// In ru, this message translates to:
  /// **'Выключен: зависание туннеля отслеживаться не будет'**
  String get tunWatchdogOff;

  /// No description provided for @tunWatchdogSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Снять туннель, если ядро молчит дольше {seconds} с'**
  String tunWatchdogSubtitle(int seconds);

  /// No description provided for @tunDnsForAllWarning.
  ///
  /// In ru, this message translates to:
  /// **'Резолв имён ВСЕЙ машины пойдёт через туннель. Если туннель встанет, имена перестанут определяться даже у приложений, которые идут напрямую и в VPN не нуждаются, — со стороны это выглядит как полная потеря интернета.'**
  String get tunDnsForAllWarning;

  /// No description provided for @tunCidrInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Нужен адрес с префиксом, например 10.8.0.0/24'**
  String get tunCidrInvalid;

  /// No description provided for @geoTitle.
  ///
  /// In ru, this message translates to:
  /// **'Гео-базы маршрутизации'**
  String get geoTitle;

  /// No description provided for @geoMissing.
  ///
  /// In ru, this message translates to:
  /// **'Не скачаны — правила по странам и категориям не работают'**
  String get geoMissing;

  /// No description provided for @geoPresent.
  ///
  /// In ru, this message translates to:
  /// **'{size}, обновлены {date}'**
  String geoPresent(String size, String date);

  /// No description provided for @geoDownload.
  ///
  /// In ru, this message translates to:
  /// **'Скачать'**
  String get geoDownload;

  /// No description provided for @geoUpdate.
  ///
  /// In ru, this message translates to:
  /// **'Обновить'**
  String get geoUpdate;

  /// No description provided for @geoDownloading.
  ///
  /// In ru, this message translates to:
  /// **'Скачиваю {file}…'**
  String geoDownloading(String file);

  /// No description provided for @geoDone.
  ///
  /// In ru, this message translates to:
  /// **'Гео-базы обновлены'**
  String get geoDone;

  /// No description provided for @geoFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось скачать: {error}'**
  String geoFailed(String error);

  /// No description provided for @infoGeoAssets.
  ///
  /// In ru, this message translates to:
  /// **'Файлы geoip.dat и geosite.dat — списки адресов по странам и доменов по категориям (например «российские сайты», «госуслуги», «ВКонтакте»). По ним работают правила маршрутизации, которые задаёт панель подписки.\n\nВ приложение они не вложены: вдвоём весят около 30 МБ, а нужны не всем — обычному серверу они не требуются вовсе.\n\nПока файлов нет, такие правила из конфига убираются, и трафик, который они уводили напрямую, идёт через VPN. Это безопасно, но медленнее, и российские сайты могут отказывать в доступе из-за иностранного адреса. Правила по конкретным сайтам и приложениям, заданные вами, работают в любом случае — они не зависят от этих файлов.'**
  String get infoGeoAssets;

  /// No description provided for @supportBullet2Android.
  ///
  /// In ru, this message translates to:
  /// **'• После нажатия отчёт соберётся в один файл, и откроется системное окно «Поделиться» — выберите Telegram, и он уйдёт одним вложением. Опишите проблему в поле выше: без описания разбирать нечего.'**
  String get supportBullet2Android;

  /// No description provided for @supportDoneTextAndroid.
  ///
  /// In ru, this message translates to:
  /// **'Отчёт собран в один файл. Выберите в системном окне, куда его отправить — в Telegram он уйдёт вложением, а не текстом.'**
  String get supportDoneTextAndroid;

  /// No description provided for @exitsHeader.
  ///
  /// In ru, this message translates to:
  /// **'Выходы'**
  String get exitsHeader;

  /// No description provided for @exitsHint.
  ///
  /// In ru, this message translates to:
  /// **'Правило «Туннель» можно направить в конкретный выход: один сайт через Германию, другой — через США. Без выхода правило идёт в общий туннель, как раньше.'**
  String get exitsHint;

  /// No description provided for @exitsAdd.
  ///
  /// In ru, this message translates to:
  /// **'Добавить выход'**
  String get exitsAdd;

  /// No description provided for @exitsEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Выходов пока нет'**
  String get exitsEmpty;

  /// No description provided for @exitsName.
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get exitsName;

  /// No description provided for @exitsNameHint.
  ///
  /// In ru, this message translates to:
  /// **'Германия'**
  String get exitsNameHint;

  /// No description provided for @exitsServers.
  ///
  /// In ru, this message translates to:
  /// **'Серверы'**
  String get exitsServers;

  /// No description provided for @exitsAutoSelect.
  ///
  /// In ru, this message translates to:
  /// **'Автовыбор по задержке'**
  String get exitsAutoSelect;

  /// No description provided for @exitsAutoSelectSub.
  ///
  /// In ru, this message translates to:
  /// **'Ядро само держит трафик на живом сервере. Цена — проба каждого сервера раз в три минуты; на телефоне это будит радио.'**
  String get exitsAutoSelectSub;

  /// No description provided for @exitsAutoSelectNeedsTwo.
  ///
  /// In ru, this message translates to:
  /// **'Нужно хотя бы два сервера'**
  String get exitsAutoSelectNeedsTwo;

  /// No description provided for @exitsDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить выход'**
  String get exitsDelete;

  /// No description provided for @exitsNoServers.
  ///
  /// In ru, this message translates to:
  /// **'Нет серверов — сначала импортируйте подписку'**
  String get exitsNoServers;

  /// No description provided for @exitsSearch.
  ///
  /// In ru, this message translates to:
  /// **'Поиск сервера'**
  String get exitsSearch;

  /// No description provided for @exitsPickAtLeastOne.
  ///
  /// In ru, this message translates to:
  /// **'Выберите хотя бы один сервер'**
  String get exitsPickAtLeastOne;

  /// No description provided for @exitsUnsupportedNote.
  ///
  /// In ru, this message translates to:
  /// **'Профили «Авто» от панели и hysteria2 отдельным выходом не поднимаются: их держит другое ядро. Такой сервер в списке недоступен.'**
  String get exitsUnsupportedNote;

  /// No description provided for @infoExits.
  ///
  /// In ru, this message translates to:
  /// **'Выход — это адресат правила «Туннель».\n\nПо умолчанию выход состоит из ОДНОГО сервера, и в фоне он не стоит ничего: обычные протоколы постоянного соединения не держат. Группа из нескольких серверов с автовыбором нужна только там, где важна страховка от падения узла, — она добавляет периодические замеры, а на телефоне это пробуждения радио.\n\nВыход имеет смысл ТОЛЬКО у действия «Туннель». «Прямо через Германию» — противоречие: прямое правило идёт мимо всех выходов.\n\nСайт и его поддомен можно отправить в РАЗНЫЕ выходы — приложение само поднимет более конкретное правило выше, иначе родитель поглотил бы поддомен.\n\nВАЖНО: при системном прокси на Windows выходы не работают вовсе — в этом режиме правил маршрутизации не строится. Нужен режим туннеля.'**
  String get infoExits;

  /// No description provided for @ruleServer.
  ///
  /// In ru, this message translates to:
  /// **'Через сервер'**
  String get ruleServer;

  /// No description provided for @ruleServerCurrent.
  ///
  /// In ru, this message translates to:
  /// **'Как основной'**
  String get ruleServerCurrent;

  /// No description provided for @ruleServerCurrentNamed.
  ///
  /// In ru, this message translates to:
  /// **'Как основной ({server})'**
  String ruleServerCurrentNamed(String server);

  /// No description provided for @routeMatchByName.
  ///
  /// In ru, this message translates to:
  /// **'Сопоставление по имени файла'**
  String get routeMatchByName;

  /// No description provided for @routeYourApps.
  ///
  /// In ru, this message translates to:
  /// **'Ваши приложения'**
  String get routeYourApps;

  /// No description provided for @routeYourSites.
  ///
  /// In ru, this message translates to:
  /// **'Ваши сайты'**
  String get routeYourSites;

  /// No description provided for @routeAppsAndSites.
  ///
  /// In ru, this message translates to:
  /// **'Приложения и сайты'**
  String get routeAppsAndSites;

  /// No description provided for @notifCompactTitle.
  ///
  /// In ru, this message translates to:
  /// **'Короткое уведомление'**
  String get notifCompactTitle;

  /// No description provided for @notifCompactSub.
  ///
  /// In ru, this message translates to:
  /// **'Выключено — подписка, сервер и скорость, с кнопками. Включено — в заголовке приложение и подписка, ниже сервер, без скорости и без кнопок.'**
  String get notifCompactSub;

  /// No description provided for @localProxyAuthTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пароль на локальный прокси'**
  String get localProxyAuthTitle;

  /// No description provided for @localProxyAuthInfo.
  ///
  /// In ru, this message translates to:
  /// **'Локальный порт ядра (127.0.0.1) — это полноценный прокси в ваш VPN. Без пароля к нему подключается любая программа на этом же устройстве и получает ваш туннель целиком: выходной IP, квоту подписки и обход ваших же правил раздельного туннелирования — включая приложения, которым вы поставили «Блок». На Android это особенно важно: там локальные порты видит любое установленное приложение.\n\nВыключайте, только если сознательно ходите в этот прокси чем-то, что не умеет аутентификацию.'**
  String get localProxyAuthInfo;

  /// No description provided for @localProxyAuthOff.
  ///
  /// In ru, this message translates to:
  /// **'Выключен: локальный прокси открыт любой программе на устройстве'**
  String get localProxyAuthOff;

  /// No description provided for @localProxyAuthSystemProxy.
  ///
  /// In ru, this message translates to:
  /// **'В режиме системного прокси не применяется: Windows не умеет передавать пароль локальному прокси. Действует в режиме TUN.'**
  String get localProxyAuthSystemProxy;

  /// No description provided for @localProxyAuthRandom.
  ///
  /// In ru, this message translates to:
  /// **'Новый случайный пароль на каждое подключение — не хранится в настройках'**
  String get localProxyAuthRandom;

  /// No description provided for @localProxyAuthCustom.
  ///
  /// In ru, this message translates to:
  /// **'Свои логин и пароль (хранятся в файле настроек)'**
  String get localProxyAuthCustom;

  /// No description provided for @localProxyCredsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Свои логин и пароль'**
  String get localProxyCredsTitle;

  /// No description provided for @localProxyCredsUnset.
  ///
  /// In ru, this message translates to:
  /// **'Не заданы — используется случайный пароль'**
  String get localProxyCredsUnset;

  /// No description provided for @localProxyCredsUser.
  ///
  /// In ru, this message translates to:
  /// **'Логин: {user}'**
  String localProxyCredsUser(String user);

  /// No description provided for @localProxyDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Логин и пароль локального прокси'**
  String get localProxyDialogTitle;

  /// No description provided for @localProxyDialogBody.
  ///
  /// In ru, this message translates to:
  /// **'Нужны, только если вы сами прописываете наш прокси (127.0.0.1) в стороннюю программу. Оставьте поля пустыми — и пароль будет случайным на каждое подключение: он не хранится в настройках и не попадает ни в журнал, ни в отчёт для поддержки. Заданный вручную остаётся в файле настроек открытым текстом.'**
  String get localProxyDialogBody;

  /// No description provided for @localProxyFieldUser.
  ///
  /// In ru, this message translates to:
  /// **'Логин'**
  String get localProxyFieldUser;

  /// No description provided for @localProxyFieldPassword.
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get localProxyFieldPassword;

  /// No description provided for @localProxyFieldHint.
  ///
  /// In ru, this message translates to:
  /// **'пусто — случайный'**
  String get localProxyFieldHint;

  /// No description provided for @lockdownOnTitle.
  ///
  /// In ru, this message translates to:
  /// **'Системная защита включена'**
  String get lockdownOnTitle;

  /// No description provided for @lockdownOnSub.
  ///
  /// In ru, this message translates to:
  /// **'Трафик заблокирован, даже если приложение закроется или его выгрузит система. Это самый надёжный режим.'**
  String get lockdownOnSub;

  /// No description provided for @lockdownHalfTitle.
  ///
  /// In ru, this message translates to:
  /// **'Защита включена наполовину'**
  String get lockdownHalfTitle;

  /// No description provided for @lockdownHalfSub.
  ///
  /// In ru, this message translates to:
  /// **'Постоянная VPN назначена, но «Блокировать соединения без VPN» выключено. Пока приложение живо — трафик защищён; если система его выгрузит, он пойдёт открыто.'**
  String get lockdownHalfSub;

  /// No description provided for @lockdownOffTitle.
  ///
  /// In ru, this message translates to:
  /// **'Системная защита выключена'**
  String get lockdownOffTitle;

  /// No description provided for @lockdownOffSub.
  ///
  /// In ru, this message translates to:
  /// **'Наш kill switch держит трафик, пока работает приложение. Если система его выгрузит, трафик пойдёт мимо VPN. Включите «Постоянная VPN» и «Блокировать соединения без VPN».'**
  String get lockdownOffSub;

  /// No description provided for @lockdownUnknownTitle.
  ///
  /// In ru, this message translates to:
  /// **'Системная защита: состояние неизвестно'**
  String get lockdownUnknownTitle;

  /// No description provided for @lockdownUnknownSub.
  ///
  /// In ru, this message translates to:
  /// **'Узнать состояние можно с Android 10 и только при поднятом туннеле. Проверьте вручную: «Постоянная VPN» и «Блокировать соединения без VPN».'**
  String get lockdownUnknownSub;

  /// No description provided for @lockdownOpenFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось открыть системные настройки VPN. Найдите их вручную: Настройки → Сеть и интернет → VPN.'**
  String get lockdownOpenFailed;

  /// No description provided for @blockNoticeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сообщать о заблокированных сайтах'**
  String get blockNoticeTitle;

  /// No description provided for @blockNoticeSub.
  ///
  /// In ru, this message translates to:
  /// **'Когда приложение или браузер стучится на сайт из списка «Блок», внизу появится уведомление с его именем. Нажмите — откроется этот экран.'**
  String get blockNoticeSub;

  /// No description provided for @siteInsecureScheme.
  ///
  /// In ru, this message translates to:
  /// **'Адрес задан как http:// — соединение не шифруется, и провайдер видит его целиком. Уберите «http://», чтобы браузер шёл по https.'**
  String get siteInsecureScheme;

  /// No description provided for @exitServerGone.
  ///
  /// In ru, this message translates to:
  /// **'Сервер этого правила пропал из подписки — трафик идёт основным туннелем'**
  String get exitServerGone;

  /// No description provided for @exitServerUnsupported.
  ///
  /// In ru, this message translates to:
  /// **'{name}\n\nЭтот сервер нельзя поднять отдельным выходом: панельные профили «Авто» и часть протоколов умеет только Xray, а выходы разводит sing-box. Трафик правила идёт основным туннелем.'**
  String exitServerUnsupported(String name);

  /// No description provided for @noticeRulesAction.
  ///
  /// In ru, this message translates to:
  /// **'Правила'**
  String get noticeRulesAction;

  /// No description provided for @geoVerdictMissingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Гео-базы не скачаны'**
  String get geoVerdictMissingTitle;

  /// No description provided for @geoVerdictMissingSub.
  ///
  /// In ru, this message translates to:
  /// **'Правила подписки по странам и категориям сейчас отключены — этот трафик идёт через VPN, а не напрямую.'**
  String get geoVerdictMissingSub;

  /// No description provided for @geoVerdictUnusableTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ядро не открыло гео-базы'**
  String get geoVerdictUnusableTitle;

  /// No description provided for @geoVerdictUnusableSub.
  ///
  /// In ru, this message translates to:
  /// **'Файлы на месте, но ядро их не прочитало. Помогает перекачивание баз.'**
  String get geoVerdictUnusableSub;

  /// No description provided for @pingPendingTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Задержка TCP до сервера. Проверка канала ещё идёт — рабочий сервер или нет, пока неизвестно.'**
  String get pingPendingTooltip;

  /// No description provided for @pingUnverifiedTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Задержка TCP до сервера. Проверка через туннель не проводилась — известна только достижимость.'**
  String get pingUnverifiedTooltip;

  /// No description provided for @pingMeasuredAt.
  ///
  /// In ru, this message translates to:
  /// **'Замер: {time}'**
  String pingMeasuredAt(String time);

  /// No description provided for @pingChecking.
  ///
  /// In ru, this message translates to:
  /// **'проверяю'**
  String get pingChecking;

  /// No description provided for @autoTimer.
  ///
  /// In ru, this message translates to:
  /// **'Прошло {elapsed} · осталось примерно {remaining}'**
  String autoTimer(String elapsed, String remaining);

  /// No description provided for @autoTimerNoEstimate.
  ///
  /// In ru, this message translates to:
  /// **'Прошло {elapsed}'**
  String autoTimerNoEstimate(String elapsed);

  /// No description provided for @autoSpeedRanking.
  ///
  /// In ru, this message translates to:
  /// **'Замеряю скорость: {name}'**
  String autoSpeedRanking(String name);

  /// No description provided for @autoWarnNoRealIp.
  ///
  /// In ru, this message translates to:
  /// **'Включено «Не выходить под реальным IP» — весь трафик уходит через VPN.'**
  String get autoWarnNoRealIp;

  /// No description provided for @autoWarnAllVpn.
  ///
  /// In ru, this message translates to:
  /// **'Выбран режим «Все — через VPN» — ваши правила сейчас не действуют.'**
  String get autoWarnAllVpn;

  /// No description provided for @autoWarnPanelOverride.
  ///
  /// In ru, this message translates to:
  /// **'Включено «Мои правила важнее правил панели».'**
  String get autoWarnPanelOverride;

  /// No description provided for @autoWarnProbesDirect.
  ///
  /// In ru, this message translates to:
  /// **'На саму проверку это не влияет: пробы идут мимо VPN при любых настройках. Но в режиме TUN они проходят через процесс ядра — если ядро зависло, все результаты будут ложно-отрицательными.'**
  String get autoWarnProbesDirect;

  /// No description provided for @autoWarnTurnOff.
  ///
  /// In ru, this message translates to:
  /// **'Отключить'**
  String get autoWarnTurnOff;

  /// No description provided for @toastCollapse.
  ///
  /// In ru, this message translates to:
  /// **'Свернуть'**
  String get toastCollapse;

  /// No description provided for @toastExpand.
  ///
  /// In ru, this message translates to:
  /// **'Развернуть'**
  String get toastExpand;

  /// No description provided for @toastOpenAutoConfig.
  ///
  /// In ru, this message translates to:
  /// **'Открыть автонастройку'**
  String get toastOpenAutoConfig;

  /// No description provided for @splitAppAlreadyAdded.
  ///
  /// In ru, this message translates to:
  /// **'Это приложение уже в списке правил'**
  String get splitAppAlreadyAdded;

  /// No description provided for @logsFileLine.
  ///
  /// In ru, this message translates to:
  /// **'{name} — {size}, строк {lines}'**
  String logsFileLine(String name, String size, int lines);

  /// No description provided for @logsReportsLine.
  ///
  /// In ru, this message translates to:
  /// **'Отчёты для поддержки: {count} шт., {size}'**
  String logsReportsLine(int count, String size);

  /// No description provided for @logsRetentionTitle.
  ///
  /// In ru, this message translates to:
  /// **'Хранить логи и отчёты'**
  String get logsRetentionTitle;

  /// No description provided for @logsRetentionDay.
  ///
  /// In ru, this message translates to:
  /// **'1 день'**
  String get logsRetentionDay;

  /// No description provided for @logsRetentionTwoWeeks.
  ///
  /// In ru, this message translates to:
  /// **'2 недели'**
  String get logsRetentionTwoWeeks;

  /// No description provided for @logsRetentionMonth.
  ///
  /// In ru, this message translates to:
  /// **'Месяц'**
  String get logsRetentionMonth;

  /// No description provided for @logsRetentionNever.
  ///
  /// In ru, this message translates to:
  /// **'Никогда не удалять'**
  String get logsRetentionNever;

  /// No description provided for @logsRetentionInfo.
  ///
  /// In ru, this message translates to:
  /// **'Логи и отчёты для поддержки удаляются, когда становятся старше выбранного срока. Проверка идёт при запуске приложения. «Никогда» оставляет всё на диске — тогда следите за размером сами: отчёт включает в себя логи целиком и растёт вместе с ними.'**
  String get logsRetentionInfo;

  /// No description provided for @logsCleanNow.
  ///
  /// In ru, this message translates to:
  /// **'Удалить старые сейчас'**
  String get logsCleanNow;

  /// No description provided for @logsCleaned.
  ///
  /// In ru, this message translates to:
  /// **'Удалено файлов: {count}, освобождено {size}'**
  String logsCleaned(int count, String size);

  /// No description provided for @logsNothingToClean.
  ///
  /// In ru, this message translates to:
  /// **'Удалять нечего'**
  String get logsNothingToClean;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'de',
        'en',
        'es',
        'fa',
        'fr',
        'pt',
        'ru',
        'tr',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fa':
      return AppLocalizationsFa();
    case 'fr':
      return AppLocalizationsFr();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'tr':
      return AppLocalizationsTr();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
