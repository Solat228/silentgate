// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonClose => 'Закрыть';

  @override
  String get commonCopy => 'Копировать';

  @override
  String get commonCopied => 'Скопировано';

  @override
  String get commonRefresh => 'Обновить';

  @override
  String get commonCheck => 'Проверить';

  @override
  String get commonOk => 'ОК';

  @override
  String get commonDone => 'Готово';

  @override
  String get commonPathCopied => 'Путь скопирован';

  @override
  String get languageTitle => 'Язык интерфейса';

  @override
  String get languageSubtitle => 'Выберите язык приложения';

  @override
  String get languageSystem => 'Как в системе';

  @override
  String get sectionAppearance => 'Оформление и поведение';

  @override
  String get sectionCapture => 'Захват трафика';

  @override
  String get sectionReliability => 'Надёжность соединения';

  @override
  String get sectionPing => 'Пинг';

  @override
  String get sectionIdentity => 'Представление панели';

  @override
  String get sectionNetwork => 'Сеть';

  @override
  String get sectionAbout => 'О программе';

  @override
  String get sectionSupport => 'Поддержка';

  @override
  String get appearanceTheme => 'Тема';

  @override
  String get themeSystem => 'Системная';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get closeToTrayTitle => 'Сворачивать в трей при закрытии';

  @override
  String get closeToTraySubtitle =>
      'Крестик прячет окно в трей; выключите — крестик закрывает приложение';

  @override
  String get autoUpdateSubTitle => 'Автообновление подписки';

  @override
  String get autoUpdateSubText => 'Периодически обновлять список серверов';

  @override
  String get captureSystemProxy => 'Системный прокси';

  @override
  String get captureSystemProxySub =>
      'Работает сейчас. Без прав администратора.';

  @override
  String get captureTun => 'TUN (полный туннель)';

  @override
  String get captureTunBadgeUac => 'нужен UAC';

  @override
  String get captureTunSub =>
      'Весь трафик, включая UDP и приложения, игнорирующие прокси. Запросит права администратора.';

  @override
  String get tunProvider => 'Провайдер TUN';

  @override
  String get tunRoutingTitle => 'TUN и маршрутизация';

  @override
  String tunRoutingSub(String stack, int mtu, String dns) {
    return 'Стек $stack · MTU $mtu · DNS $dns';
  }

  @override
  String get splitTunnelTitle => 'Раздельное туннелирование';

  @override
  String splitRulesCount(int n, int apps, int sites) {
    return 'правил $n (приложений $apps, сайтов $sites)';
  }

  @override
  String get captureTunHint =>
      'Настройки TUN, DNS и раздельного туннелирования появятся при выборе режима TUN — в режиме системного прокси они не работают.';

  @override
  String get dnsShortVpn => 'через VPN';

  @override
  String get dnsShortSystem => 'системный';

  @override
  String get dnsShortCustom => 'свой';

  @override
  String get tunUacTitle => 'TUN требует прав администратора';

  @override
  String get tunUacBody =>
      'Можно настроить запуск один раз: приложение создаст задачу в Планировщике Windows с высшими правами, и дальше туннель будет стартовать БЕЗ запроса UAC.\n\nСейчас появится один запрос прав администратора. Само приложение продолжит работать без повышенных прав.';

  @override
  String get tunUacLater => 'Позже (спрашивать каждый раз)';

  @override
  String get tunUacSetup => 'Настроить';

  @override
  String get tunUacDone => 'Готово: TUN будет запускаться без запроса UAC';

  @override
  String get tunUacFail =>
      'Не удалось создать задачу — UAC будет запрашиваться при подключении';

  @override
  String get autoReconnectTitle => 'Автопереподключение';

  @override
  String get autoReconnectSub =>
      'Восстанавливать соединение при обрыве и смене сети';

  @override
  String get killSwitchTitle => 'Kill switch';

  @override
  String get alwaysOnTitle => 'Системная защита от утечек';

  @override
  String get alwaysOnSub =>
      'Always-on VPN и «блокировать соединения без VPN» — держит блокировку даже когда приложение закрыто';

  @override
  String get killSwitchSubTun =>
      'Не выпускать трафик мимо VPN, пока идёт восстановление';

  @override
  String get killSwitchSubProxy =>
      'В режиме «Системный прокси» защищает только приложения, уважающие прокси. Полностью — только TUN';

  @override
  String get killSwitchSubOff => 'Требует включённого автопереподключения';

  @override
  String get networkRecoverTitle => 'Восстановить сеть';

  @override
  String get networkRecoverSub =>
      'Если пропал интернет после VPN. Требует прав администратора';

  @override
  String get networkRecoverConfirmTitle => 'Восстановить сеть?';

  @override
  String get networkRecoverConfirmBody =>
      'Сброс winsock, IP-стека, DNS и системного прокси. Потребуются права администратора (UAC). Сброс winsock/IP вступит в силу после перезагрузки.';

  @override
  String get networkRecoverConfirmOk => 'Восстановить';

  @override
  String get interferenceTitle => 'Проверить помехи (другие VPN)';

  @override
  String get interferenceDialogTitle => 'Помехи в сети';

  @override
  String get interferenceNoneFound =>
      'Других VPN и вмешательств не обнаружено.';

  @override
  String get interferenceIgnore => 'Игнорировать';

  @override
  String get identityUserAgent => 'User-Agent';

  @override
  String identityUaAutoNote(String version) {
    return 'Обновляется автоматически вместе с версией приложения. Дополнительно отправляются: X-HWID, X-Device-OS, X-Ver-OS, X-App-Version ($version).';
  }

  @override
  String get urlSchemesTitle => 'URL-схемы';

  @override
  String get urlSchemesSub =>
      'Импорт и управление VPN по ссылке (connect / toggle / update)';

  @override
  String get panelOwnerTitle => 'Для владельца панели';

  @override
  String get panelOwnerBody =>
      'Обычному пользователю это не нужно — можно пропустить.\n\nЧтобы приложение получало вашу подписку в правильном JSON-формате (XRAY_JSON), добавьте этот блок в «Правила ответов» (Response Rules) панели Remnawave — он сопоставляет наш User-Agent:';

  @override
  String get panelOwnerCopy => 'Скопировать блок';

  @override
  String get aboutVersion => 'Версия SilentGate';

  @override
  String get aboutXrayCore => 'Ядро Xray';

  @override
  String get aboutHwid => 'HWID устройства';

  @override
  String get aboutThirdPartyTitle => 'Сторонние компоненты и лицензии';

  @override
  String get aboutThirdPartySub =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), Wintun — запускаются отдельными процессами';

  @override
  String get aboutThirdPartySubEmbedded =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), libXray (MIT) — встроены в приложение';

  @override
  String get thirdPartyBodyEmbedded =>
      'На Android ядра ВСТРОЕНЫ в приложение (нативная библиотека внутри APK).\n\n• sing-box — GPL-3.0. Библиотека слинкована с приложением, поэтому производные обязаны оставаться под GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nИсходный код клиента: https://github.com/Solat228/silentgate\nПолные тексты лицензий — кнопками ниже.';

  @override
  String get logsTitle => 'Логи';

  @override
  String get logsSub =>
      'Приложение и TUN (sing-box): импорт подписки, пинг, ошибки';

  @override
  String get thirdPartyTitle => 'Сторонние компоненты';

  @override
  String get thirdPartyBody =>
      'SilentGate поставляется вместе со сторонними исполняемыми файлами. Они запускаются ОТДЕЛЬНЫМИ процессами и не встроены в приложение.\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  TUN-туннель и прокси-ядро для Hysteria2\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — лицензия Wintun\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — данные маршрутизации, CC-BY-SA-4.0\n\nПолные тексты лицензий — в папке «licenses» рядом с приложением.';

  @override
  String get supportSectionNote =>
      'Нажмите «Написать в поддержку» — откроется окно, где вы сами сгенерируете файл-лог (версии, ОС, настройки, app.log + хвост singbox.log; без паролей и токена подписки, URL скрыт). После этого появится кнопка отправки в Telegram поддержки.';

  @override
  String get supportButtonTitle => 'Написать в поддержку';

  @override
  String get supportButtonSub => 'Сгенерировать лог и открыть чат поддержки';

  @override
  String get supportDialogTitle => 'Поддержка';

  @override
  String get supportDialogTitleDone => 'Лог готов — кому отправить';

  @override
  String get supportWhatWillHappen => 'Что будет сделано:';

  @override
  String get supportBullet1 =>
      '• В один файл соберутся версии, ОС, настройки и логи (app.log + хвост singbox.log). Паролей и токена подписки в нём нет, URL подписки скрыт.';

  @override
  String get supportBullet2 =>
      '• После нажатия откроется СНАЧАЛА папка с файлом, затем сам файл. Впишите описание проблемы вверху, сохраните — и появится кнопка отправки в поддержку.';

  @override
  String supportError(String error) {
    return 'Не удалось собрать отчёт: $error';
  }

  @override
  String get supportDoneText =>
      'Отчёт собран и открыт (папка, затем файл). Впишите описание проблемы вверху, сохраните файл и отправьте его в поддержку — приложение поможет открыть Telegram.';

  @override
  String get supportWhoTo => 'Кому отправить:';

  @override
  String get supportContact => 'Написать в поддержку';

  @override
  String supportContactNamed(String name) {
    return 'Написать в поддержку ($name)';
  }

  @override
  String get supportDevServiceName => 'Разработчик клиента';

  @override
  String get supportShowOnPc => 'Показать на ПК';

  @override
  String get supportCopyPath => 'Копировать путь';

  @override
  String get supportGenerating => 'Собираю…';

  @override
  String get supportGenerateButton => 'Сгенерировать лог для поддержки';

  @override
  String get pingTwoPhaseTitle => 'Проверять работоспособность (через туннель)';

  @override
  String get pingTwoPhaseSubOn =>
      'После TCP — запрос через сервер: отсекает нерабочие (Reality и т.п.)';

  @override
  String get pingTwoPhaseSubOff => 'Работает один выбранный метод (ниже)';

  @override
  String get pingMethodCheck => 'Метод проверки:';

  @override
  String get pingMethodPing => 'Метод пинга:';

  @override
  String get speedTestProbe => 'Проба теста скорости:';

  @override
  String get speedTestFull => '20 МБ (точнее)';

  @override
  String get speedTestLight => '5 МБ (экономно)';

  @override
  String get testUrlLabel => 'Тестовый URL (via Proxy)';

  @override
  String get appUpdateServerUnavailable => 'Сервер обновлений недоступен';

  @override
  String appUpdateAvailable(String version) {
    return 'Доступна версия $version';
  }

  @override
  String get appUpdateLatest => 'У вас последняя версия';

  @override
  String get appUpdateDownload => 'Скачать';

  @override
  String get appUpdateCheckTitle => 'Проверять обновления при запуске';

  @override
  String get appUpdateManual => 'Скачивание и установка — вручную';

  @override
  String get appUpdateEndpointLabel => 'Эндпоинт версии';

  @override
  String get urlSchemeSilentgateTitle => 'Ссылки silentgate://';

  @override
  String get urlSchemeSilentgateSub =>
      'Импорт и управление VPN по ссылке. Включено по умолчанию';

  @override
  String get urlSchemeDisableTitle => 'Отключить ссылки silentgate://?';

  @override
  String get urlSchemeDisableBody =>
      'Перестанут работать импорт по ссылке и управляющие схемы (connect / disconnect / toggle / update). Оставьте включённым, если не уверены.';

  @override
  String get urlSchemeDisableOk => 'Отключить';

  @override
  String get urlSchemeServerTitle => 'Открывать ссылки серверов';

  @override
  String get urlSchemeServerSub =>
      'Перехватить vless:// и другие у других клиентов';

  @override
  String get urlSchemeServerConfirmTitle => 'Перехватывать ссылки серверов?';

  @override
  String urlSchemeServerConfirmBody(String schemes) {
    return '$schemes\n\nЭти ссылки обычно привязаны к другому VPN-клиенту (Happ, v2rayTun). SilentGate заберёт их себе.';
  }

  @override
  String get urlSchemeServerConfirmOk => 'Перехватить';

  @override
  String get urlSchemeAutoConnect => 'Подключаться после импорта';

  @override
  String get autoTitle => 'Автонастройка';

  @override
  String get autoClearResults => 'Очистить результаты';

  @override
  String autoFoundWorking(Object count) {
    return 'Найдено рабочих: $count';
  }

  @override
  String get autoPinnedTop => ' — закреплены сверху списка';

  @override
  String get autoSearchContinues => ' (поиск продолжается…)';

  @override
  String get autoCheckServices => 'Проверять сервисы';

  @override
  String get autoPinFoundOnTop => 'Закреплять найденные сверху списка';

  @override
  String get autoTryFragment => 'Перебирать обход (fragment)';

  @override
  String get autoNoSubscriptionPasteKey =>
      'Подписки нет. Вставьте один ключ — подберём рабочие настройки:';

  @override
  String get autoTuneByKey => 'Подобрать по ключу';

  @override
  String autoTesting(int index, int total) {
    return 'Тестируется $index/$total: ';
  }

  @override
  String autoVariant(Object label) {
    return 'Вариант: $label';
  }

  @override
  String autoServicesPassed(int ok, int total) {
    return 'сервисов $ok из $total';
  }

  @override
  String get autoConnect => 'Подключиться';

  @override
  String get autoStopSearch => 'Остановить поиск';

  @override
  String get autoDoneRefreshPing => 'Готово — обновить пинг найденных';

  @override
  String autoFoundPinnedRefreshing(Object count) {
    return 'Найдено $count, закреплены сверху. Обновляю пинг…';
  }

  @override
  String autoServersForTuning(int selected, int total) {
    return 'Серверы для подбора ($selected/$total)';
  }

  @override
  String get autoSelectAll => 'Все';

  @override
  String get autoDeselectAll => 'Снять';

  @override
  String get autoTuneSelected => 'Подобрать для выбранных';

  @override
  String autoTuned(Object label) {
    return 'Подобрано: $label';
  }

  @override
  String get infoDialogTitle => 'Пояснение';

  @override
  String get infoCopied => 'Пояснение скопировано';

  @override
  String get commonGotIt => 'Понятно';

  @override
  String get enumSplitAll => 'Все — через VPN';

  @override
  String get enumSplitOnly => 'Только отмеченные — через VPN';

  @override
  String get enumSplitExcept => 'Отмеченные — мимо VPN';

  @override
  String get enumActionTunnel => 'Туннель';

  @override
  String get enumActionDirect => 'Прямо';

  @override
  String get enumActionBlock => 'Блок';

  @override
  String homeUpdateAvailable(Object version) {
    return 'Доступна версия $version';
  }

  @override
  String get homeDownload => 'Скачать';

  @override
  String homeSubscriptionUpdated(Object summary) {
    return 'Подписка обновлена: $summary';
  }

  @override
  String get homeReconnect => 'Переподключить';

  @override
  String homePingProgress(int done, int total) {
    return 'Пинг серверов: $done из $total';
  }

  @override
  String get homeAutoConfigStarting => 'Автонастройка запускается…';

  @override
  String homeAutoConfigProgress(int current, int total, String name) {
    return 'Автонастройка: $current из $total — $name';
  }

  @override
  String get homeImport => 'Импорт';

  @override
  String get homeSettings => 'Настройки';

  @override
  String get homeAutoBest => 'Авто (лучший сервер)';

  @override
  String get homeAutoConfig => 'Автонастройка';

  @override
  String homeServersCount(Object count) {
    return 'Серверы ($count)';
  }

  @override
  String homeFoundCount(int found, int total) {
    return 'Найдено $found из $total';
  }

  @override
  String get homePingServers => 'Пинг серверов';

  @override
  String get homePingFound => 'Пинг найденных';

  @override
  String get homeNothingFound => 'Ничего не найдено';

  @override
  String get homeOnboardingTitle => 'Начните с импорта подписки';

  @override
  String get homeOnboardingSubtitle =>
      'Вставьте ссылку Remnawave или отдельный ключ';

  @override
  String get homeImportSubscription => 'Импортировать подписку';

  @override
  String homeSessionTraffic(String down, String up) {
    return 'За сессию: ↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'ГБ';

  @override
  String subBarUsage(String used, String total) {
    return '$used из $total';
  }

  @override
  String get subBarSubscription => 'Подписка';

  @override
  String get subBarRefreshing => 'Обновляю…';

  @override
  String get subBarRefreshSubscription => 'Обновить подписку';

  @override
  String get subBarSupport => 'Поддержка';

  @override
  String get subBarRefresh => 'Обновить';

  @override
  String get subBarAddSubscription => 'Добавить подписку';

  @override
  String get subBarCopyLink => 'Копировать ссылку';

  @override
  String get subBarDeleteSubscription => 'Удалить подписку';

  @override
  String get subBarLinkCopied => 'Ссылка скопирована';

  @override
  String get subBarDeleteConfirmTitle => 'Удалить подписку?';

  @override
  String get subBarDeleteConfirmBody =>
      'Серверы из подписки будут убраны из списка.';

  @override
  String subBarDeletePinned(Object count) {
    return 'Удалить и закреплённые ($count) с их правками';
  }

  @override
  String get subBarDeletePinnedHint =>
      'Иначе они останутся в списке и переживут удаление';

  @override
  String get subBarCancel => 'Отмена';

  @override
  String get subBarDelete => 'Удалить';

  @override
  String get subBarSubscriptionDeleted => 'Подписка удалена';

  @override
  String subBarSubscriptionUpdated(Object summary) {
    return 'Подписка обновлена: $summary';
  }

  @override
  String get subBarMore => 'Подробнее';

  @override
  String subBarAdded(Object count) {
    return 'Добавлены ($count)';
  }

  @override
  String subBarRemoved(Object count) {
    return 'Удалены ($count)';
  }

  @override
  String subBarAutoUpdate(Object hours) {
    return '· автообновление $hoursч';
  }

  @override
  String subBarValidPerpetual(Object auto) {
    return 'Действует: бессрочно  $auto';
  }

  @override
  String get subBarExpired => 'Подписка истекла:';

  @override
  String get subBarValidUntil => 'Действует до:';

  @override
  String get infoCaptureMode =>
      'Как перехватывается трафик. «Системный прокси» — прописывает локальный прокси в системе (без прав администратора, ловит браузеры и большинство приложений). «TUN» — виртуальный сетевой адаптер, ловит ВЕСЬ трафик (в т.ч. UDP и приложения, игнорирующие прокси), но требует прав администратора.';

  @override
  String get infoSystemProxy =>
      'Локальный HTTP-прокси в системных настройках (реестр WinINET). Без прав администратора. Не перехватывает UDP и приложения, игнорирующие системный прокси.';

  @override
  String get infoTunMode =>
      'Полный туннель через виртуальный адаптер wintun + sing-box. Ловит весь трафик, включая UDP. Запрашивает права администратора (UAC) при включении.';

  @override
  String get infoTunProvider =>
      'Драйвер виртуального сетевого адаптера. На Windows используется wintun (поставляется с ядром). Другие драйверы не требуются.';

  @override
  String get infoTunStack =>
      'Сетевой стек TUN (sing-box).\n\n«auto» — АВТОПОДБОР: если туннель не поднялся, приложение само перебирает system → gvisor → mixed, а затем уменьшает MTU (1400, 1280). Комбинация, на которой всё заработало, запоминается и в следующий раз пробуется первой. Ход подбора виден в статусе и в логе.\n\nЯвный выбор отключает подбор: system — стек ОС, быстрее всего, но капризнее к антивирусам; gvisor — userspace, медленнее, максимально совместим; mixed — TCP через system, UDP через gvisor.';

  @override
  String get infoTunMtu =>
      'Максимальный размер пакета в TUN-адаптере. По умолчанию 1500; уменьшайте (1400, 1280), если бывают обрывы — слишком маленький снижает скорость.\n\nПри стеке «auto» это лишь стартовое значение: если туннель не поднимется, приложение само попробует меньшие MTU.';

  @override
  String get infoTunStrictRoute =>
      'Строгая маршрутизация sing-box. На Windows лечит две типовые беды: утечку DNS (система по умолчанию шлёт запросы во все адаптеры сразу) и ошибки «сеть недоступна». Выключайте, только если ломает VirtualBox/Hyper-V.';

  @override
  String get infoTunIpv6 =>
      'Вести IPv6 внутрь туннеля. Если выключить, а у провайдера IPv6 включён, часть трафика пойдёт МИМО VPN (утечка реального адреса) либо будет зависать. Выключайте только при проблемах с IPv6-сетью.';

  @override
  String get infoTunEndpointIndependentNat =>
      'Режим NAT для UDP. Нужен играм, голосовым чатам и WebRTC — без него соединения могут не устанавливаться. Отключайте только для экономии памяти.';

  @override
  String get infoTunBypassLan =>
      'Локальная сеть (частные адреса 192.168.*, 10.*, роутер, принтеры, NAS) идёт мимо VPN. Обычно нужно включённым, иначе пропадёт доступ к устройствам в сети.';

  @override
  String get infoTunExcludeCidrs =>
      'Дополнительные подсети, которые всегда идут мимо VPN (формат CIDR, напр. 10.8.0.0/24). Полезно для корпоративных сетей и других VPN.';

  @override
  String get infoTunPrivilege =>
      'TUN требует прав администратора. Один раз создаём задачу в Планировщике Windows с высшими правами — после этого туннель стартует БЕЗ запроса UAC при каждом подключении. Задача принадлежит вам и удаляется кнопкой ниже или при удалении программы.';

  @override
  String get infoAppUpdate =>
      'Раз в запуск приложение спрашивает у вашего сервера, нет ли версии новее, и показывает уведомление с кнопкой «Скачать».\n\nПриложение НИЧЕГО не скачивает и не запускает само: установщик не подписан сертификатом, и самозапуск скачанного exe упирается в SmartScreen и выглядит для антивирусов как поведение зловреда. Обновление ставите вы.\n\nЕсли сервер недоступен — приложение просто молчит, запись уходит в лог. Формат ответа и настройка сервера описаны в docs/APP_UPDATE.md.';

  @override
  String get infoSpeedTest =>
      'Объём данных, который скачивается при замере скорости (ПКМ по серверу → «Информация о сервере» → «Измерить скорость»).\n\n20 МБ — основной режим: на быстрых каналах (100+ Мбит/с) короткая проба не успевает разогнаться и занижает результат.\n5 МБ — экономный: заметно дешевле по трафику, удобно прогнать много серверов.\n\nЗамер запускается ТОЛЬКО вручную и расходует трафик вашей подписки. Скорость меряется дважды: напрямую и через выбранный сервер, чтобы было видно, сколько именно теряется на VPN.';

  @override
  String get infoAutoReconnect =>
      'Если ядро упало, сервер отвалился или сменилась сеть (Wi-Fi ↔ кабель, выход из сна, новый IP) — приложение само поднимает подключение заново. Паузы между попытками растут: 0,8 с → 3 с → 8 с → 20 с, до 8 попыток, после чего показывается ошибка. Отключение кнопкой всегда отменяет восстановление.\n\nСмена сети определяется по реальным адресам чужих адаптеров: собственный туннель и служебные адреса (link-local) не учитываются, изменение принимается только если продержалось два опроса подряд, и первые 15 секунд после подключения сигнал игнорируется. Без этих предохранителей подъём туннеля сам считался «сменой сети» и вызывал бесконечное переподключение.';

  @override
  String get infoKillSwitch =>
      'Не выпускать трафик мимо VPN, пока соединение восстанавливается. Захват НЕ снимается между попытками: в TUN-режиме адаптер остаётся поднятым, в режиме «Системный прокси» прокси остаётся прописанным — приложения получают ошибку соединения вместо незашифрованного выхода в интернет.\n\nЧестно о границах: в режиме «Системный прокси» это защищает только программы, уважающие системный прокси (браузеры и большинство приложений). Программы, игнорирующие прокси, и UDP пойдут напрямую — полную герметичность даёт только TUN-режим. Требует включённого автопереподключения.';

  @override
  String get infoUserAgent =>
      'Как приложение представляется панели (заголовок User-Agent). Всегда отправляется «SilentGate/версия (Windows)».\n\nПанель Remnawave по этому имени выбирает ФОРМАТ подписки. Нужен XRAY_JSON — в нём приходят готовые конфиги серверов; из base64-списка ссылок часть настроек восстанавливается приблизительно, и автовыбор (burstObservatory) работает хуже.\n\nНастраивается в панели: Templates → Response Rules → правило с условием user-agent CONTAINS SilentGate и типом ответа XRAY_JSON (поставьте его выше правила Fallback Base64).\n\nПоле переопределения нужно только как временный обходной путь — если панель ещё не знает приложение, можно представиться клиентом, который она знает.';

  @override
  String get infoDnsMode =>
      'Кто резолвит домены в TUN-режиме. «Через VPN» (рекомендуется) — запросы уходят в туннель по TCP, провайдер не видит, какие сайты вы открываете. «Системный» — как в Windows: возможна утечка DNS, а если сервер не пропускает UDP — интернет может пропасть совсем. «Свой» — указанный вами сервер через туннель.';

  @override
  String get infoDnsCustomServer =>
      'Адрес DNS-сервера для режима «Свой» (например 9.9.9.9 или 8.8.8.8). Запросы к нему идут через туннель по TCP.';

  @override
  String get infoDnsHijack =>
      'Перехватывать DNS-запросы (UDP порт 53) внутри туннеля. Без этого запросы уходят мимо правил: возможна утечка, а доменные правила раздельного туннелирования работают менее точно.';

  @override
  String get infoDnsStrategy =>
      'Какие адреса запрашивать: prefer_ipv4 (рекомендуется) — сначала IPv4, ipv4_only — только IPv4 (лечит проблемы с кривым IPv6), prefer_ipv6/ipv6_only — для IPv6-сетей.';

  @override
  String get infoSingboxLogLevel =>
      'Подробность лога sing-box (%APPDATA%\\SilentGate\\singbox.log). warn — обычный режим. info/debug — если туннель не работает: в логе будет видна точная причина. debug заметно увеличивает размер файла.';

  @override
  String get infoSplitMode =>
      'База — куда идёт всё, чему не задано действие вручную, и какое действие присваивается новым записям. «Все — через VPN»: по умолчанию весь трафик в туннель. «Только отмеченные — через VPN»: по умолчанию напрямую, в туннель — лишь помеченные «Туннель». «Отмеченные — мимо VPN»: наоборот, всё в туннель, а помеченные «Прямо» — напрямую.';

  @override
  String get infoSplitApps =>
      'Нажмите на приложение — откроется окно, где выбираются действие (Туннель — через VPN, Прямо — мимо VPN, Блок — нет сети) и способ сопоставления: по имени exe (надёжно) или по полному пути. Можно выбрать из запущенных или указать .exe.';

  @override
  String get infoSplitDomains =>
      'Домены (суффиксы). Например, youtube.com покрывает и www.youtube.com. Работает по имени из TLS-соединения (SNI).';

  @override
  String get infoVerifyViaProxy =>
      'Сначала проверяем работоспособность через прокси (сервер реально отдаёт 204), и только если сервер ответил — отдельно измеряем задержку выбранным методом (TCP/ICMP).';

  @override
  String get infoProxyGet =>
      'Запрос GET через туннель к тест-URL. Проверяет, что сервер реально пропускает трафик и отдаёт 204. Самый честный тест работоспособности; чуть медленнее.';

  @override
  String get infoProxyHead =>
      'Как GET, но только заголовки — быстрее и меньше трафика. Отдельные серверы/CDN могут не поддерживать HEAD.';

  @override
  String get infoTcp =>
      'Время TCP-рукопожатия до адреса сервера. Быстрый и точный показатель задержки, но не доказывает работу туннеля: Reality-сервер ответит на TCP даже если проксирование заблокировано. Рекомендуется для задержки.';

  @override
  String get infoIcmp =>
      'Системный ping. Часто бесполезен для Reality/CDN: ICMP могут блокировать, либо он меряет ближайший узел CDN. Оставляйте для диагностики сети.';

  @override
  String get infoTestUrl =>
      'URL для проверки работоспособности через прокси. По умолчанию https://www.gstatic.com/generate_204 — отдаёт пустой ответ 204, что удобно и быстро.';

  @override
  String get infoAutoConfig =>
      'Перебирает серверы и варианты обхода (fragment, fingerprint) и собирает список тех, где работают выбранные сервисы. Не останавливается на первом — вы выбираете из найденных. Проверка через прокси, VPN на это время не включается.';

  @override
  String get infoAutoConfigServices =>
      'Какие сервисы должны работать, чтобы сервер считался пригодным. Проверка устойчива к заглушкам провайдера (сверяется сигнатура ответа, а не просто «200 OK»).';

  @override
  String get infoAutoPinFound =>
      'Найденные рабочие связки (сервер + вариация обхода) сразу закрепляются сверху общего списка серверов, чтобы ими можно было пользоваться не возвращаясь сюда. Выключите, если не хотите, чтобы автонастройка меняла порядок вашего списка — результаты останутся видны на этом экране.';

  @override
  String get infoTryFragment =>
      'Пробовать вариант с фрагментацией TLS ClientHello (обход DPI), если «голый» сервер не работает. Немного дольше, но находит рабочую связку на зарезанных серверах.';

  @override
  String get infoAutoStrategy =>
      '«Первый рабочий» — перебрать всё и подключиться к любому найденному (вы выбираете). «Лучший за бюджет» — искать в пределах времени и выбрать самый быстрый.';

  @override
  String get infoScheme =>
      'Регистрирует протокол silentgate:// в системе (для текущего пользователя, без прав администратора). После этого клик по ссылке silentgate://import?url=… (импорт) или silentgate://connect / toggle (управление) в браузере открывает приложение и выполняет действие. Включено по умолчанию.';

  @override
  String get infoAutoConnectAfterImport =>
      'Сразу подключаться к первому серверу после успешного импорта подписки по ссылке.';

  @override
  String get infoNetworkRecover =>
      'Сброс сетевых параметров, если после сбоя/выключения ПК с включённым VPN пропал интернет: winsock, IP-стек, DNS-кэш, системный прокси. Требует прав администратора; сброс winsock и IP-стека вступает в силу после ПЕРЕЗАГРУЗКИ.';

  @override
  String get infoInterference =>
      'Проверка других VPN и вмешательств в сеть (чужие TUN-адаптеры, процессы VPN, zapret/GoodbyeDPI), которые могут конфликтовать с SilentGate. Можно закрыть или игнорировать.';

  @override
  String get pingInfoProxyGet =>
      'Запрос GET через туннель к тест-URL. Проверяет, что сервер реально пропускает трафик и отдаёт 204. Самый честный тест работоспособности; чуть медленнее из-за полной загрузки ответа. Рекомендуется для проверки работоспособности.';

  @override
  String get pingInfoProxyHead =>
      'Как GET, но запрашивает только заголовки — меньше трафика и быстрее. Проверяет работоспособность туннеля; отдельные серверы/CDN могут не поддерживать HEAD.';

  @override
  String get pingInfoTcp =>
      'Замер времени TCP-рукопожатия до адреса сервера. Быстрый и точный показатель задержки эндпоинта, но не доказывает, что туннель работает: Reality-сервер ответит на TCP, даже если проксирование заблокировано. Рекомендуется для задержки.';

  @override
  String get pingInfoIcmp =>
      'Системный ping (эхо-запрос). Часто бесполезен для Reality/CDN: ICMP могут блокировать, либо он измеряет ближайший узел CDN, а не сервер. Оставляйте для диагностики сети.';

  @override
  String get pingInfoTwoPhase =>
      'После TCP-проверки ответившие сервера дополнительно проверяются запросом через туннель (GET/HEAD к тест-URL). Так отсекаются сервера, которые держат порт открытым, но трафик не проксируют. Задержка всё равно показывается по TCP.';

  @override
  String get pingInfoTunStage =>
      'Полный туннель (TUN) — следующий этап. Сейчас работает режим «Системный прокси». В TUN-режиме весь трафик (включая UDP и приложения, игнорирующие прокси) пойдёт через виртуальный адаптер wintun + tun2socks. Требует прав администратора.';

  @override
  String get pingInfoTunStack =>
      'Сетевой стек TUN (sing-box). auto — оставить на усмотрение ядра (сейчас mixed). system — стек ОС: максимальная скорость, но капризнее к правам/антивирусам. gvisor — userspace-стек: медленнее, зато самый совместимый. mixed — TCP через system, UDP через gvisor (баланс). Если TUN не подключается или рвёт соединения — попробуйте gvisor.';

  @override
  String get pingInfoAutoConfig =>
      'При включении приложение само перебирает серверы и варианты обхода (fragment, fingerprint) и подключается к первому, где работают выбранные сервисы (проверка через прокси, без включения VPN на время перебора).';

  @override
  String get logsTabApp => 'Приложение';

  @override
  String get logsTabTun => 'TUN (sing-box)';

  @override
  String get logsRefresh => 'Обновить';

  @override
  String get logsCopy => 'Копировать';

  @override
  String get logsClearApp => 'Очистить лог приложения';

  @override
  String get logsCopied => 'Лог скопирован';

  @override
  String get logsLoading => 'Загрузка…';

  @override
  String get logsEmpty => 'Пока пусто.';

  @override
  String get logsTunEmpty => 'Пусто — TUN ещё не запускался в этой системе.';

  @override
  String get importScrDone => 'Импортировано';

  @override
  String get importScrWelcome => 'Добро пожаловать в SilentGate';

  @override
  String get importScrTitle => 'Импорт подписки';

  @override
  String get importScrSubscriptionFallback => 'Подписка';

  @override
  String get importScrHint =>
      'Вставьте ссылку подписки (Remnawave), deep link silentgate:// или одиночную ссылку vless:// / vmess:// / trojan:// / ss:// / hysteria2://';

  @override
  String get importScrLoading => 'Загрузка…';

  @override
  String get importScrPasteImport => 'Импорт из буфера обмена';

  @override
  String get importScrImportField => 'Импортировать из поля';

  @override
  String get serversTitle => 'Серверы';

  @override
  String serversFound(int found, int total) {
    return 'Серверы — найдено $found из $total';
  }

  @override
  String get serversRefresh => 'Обновить подписку';

  @override
  String get serversPinging => 'Пинг идёт…';

  @override
  String get serversPingAll => 'Пинговать все';

  @override
  String get serversPingFound => 'Пинговать найденные';

  @override
  String get serversEmpty => 'Список серверов пуст. Импортируйте подписку.';

  @override
  String get serversNothingFound => 'Ничего не найдено';

  @override
  String get toastCopied => 'Скопировано';

  @override
  String get toastHide => 'Скрыть';

  @override
  String get srvInfoTitle => 'Информация о сервере';

  @override
  String srvInfoProbeFailed(Object error) {
    return 'Не удалось поднять пробное соединение: $error';
  }

  @override
  String get srvInfoServerAddressFailed =>
      'Не удалось определить адрес сервера';

  @override
  String get srvInfoSectionExit => 'Куда вы выходите';

  @override
  String get srvInfoExitHint =>
      'Определяется по адресу сервера — туннель для этого не поднимается.';

  @override
  String get srvInfoAddressLocation => 'Адрес и локация сервера';

  @override
  String get srvInfoCheckAgain => 'Проверить заново';

  @override
  String get srvInfoSectionSpeed => 'Скорость';

  @override
  String srvInfoSpeedHint(Object size) {
    return 'Проба скачивает $size и расходует трафик подписки. Размер меняется в настройках.';
  }

  @override
  String get srvInfoViaServer => 'Через сервер';

  @override
  String get srvInfoWithoutVpn => 'Без VPN';

  @override
  String get srvInfoMeasuring => 'Измеряю…';

  @override
  String get srvInfoMeasureSpeed => 'Измерить скорость';

  @override
  String get srvInfoSectionParams => 'Параметры подключения';

  @override
  String get srvInfoParamAddress => 'Адрес';

  @override
  String get srvInfoParamProtocol => 'Протокол';

  @override
  String get srvInfoParamTransport => 'Транспорт';

  @override
  String get srvInfoParamTlsFingerprint => 'Отпечаток TLS';

  @override
  String get srvInfoParamType => 'Тип';

  @override
  String get srvInfoPanelAutoProfile => 'Профиль автовыбора от панели';

  @override
  String get srvInfoCouldNotDetermine => 'не удалось определить';

  @override
  String get srvInfoCopy => 'Копировать';

  @override
  String get editorJsonTitle => 'JSON конфиг';

  @override
  String get editorCopy => 'Копировать';

  @override
  String get editorClose => 'Закрыть';

  @override
  String get editorTitle => 'Редактировать сервер';

  @override
  String get editorFieldName => 'Имя';

  @override
  String get editorFieldAddress => 'Адрес';

  @override
  String get editorFieldPort => 'Порт';

  @override
  String get editorFieldUuidPassword => 'UUID / пароль';

  @override
  String get editorFieldObfs => 'Обфускация (обычно salamander)';

  @override
  String get editorFieldObfsPassword => 'Пароль обфускации';

  @override
  String get editorFieldPortHopping => 'Порт-хоппинг (напр. 20000-21000)';

  @override
  String get editorAllowSelfSigned => 'Разрешить самоподписанный сертификат';

  @override
  String get editorAllowSelfSignedSub =>
      'Нужно, только если так настроен сервер';

  @override
  String get editorTransport => 'Транспорт';

  @override
  String get editorSecurity => 'Безопасность';

  @override
  String get editorNone => '(нет)';

  @override
  String get editorCancel => 'Отмена';

  @override
  String get editorSave => 'Сохранить';

  @override
  String jsonProfileServers(int count, String burst) {
    return '$count серверов$burst';
  }

  @override
  String get jsonCompositionUnknown => 'состав неизвестен';

  @override
  String get jsonYourSavedOverride => 'Ваш сохранённый JSON (override)';

  @override
  String jsonPanelProfileApplied(Object summary) {
    return 'Профиль автовыбора от панели: $summary — применяется целиком';
  }

  @override
  String get jsonPanelConfig => 'Конфиг от панели (XRAY_JSON)';

  @override
  String get jsonBuiltFromShareLink =>
      'Собран из share-ссылки — панель не прислала JSON. Обновите подписку; если не помогло, проверьте правило Response Rules в панели.';

  @override
  String get jsonInvalidJson => 'Некорректный JSON';

  @override
  String get jsonSaved => 'Сохранено';

  @override
  String get jsonTitle => 'JSON конфиг';

  @override
  String get jsonFieldEditor => 'Редактор полей';

  @override
  String get jsonCopy => 'Копировать';

  @override
  String get jsonClose => 'Закрыть';

  @override
  String get jsonSave => 'Сохранить';

  @override
  String get srvTileEdit => 'Редактировать';

  @override
  String get srvTileNotice => 'Уведомление';

  @override
  String get srvTileRefresh => 'Обновить';

  @override
  String get srvTileSubscriptionUpdated => 'Подписка обновлена';

  @override
  String get srvTileCopy => 'Скопировать';

  @override
  String get srvTileInfo => 'Информация о сервере';

  @override
  String get srvTilePing => 'Пинговать';

  @override
  String get srvTileUnpin => 'Открепить';

  @override
  String get srvTilePin => 'Закрепить';

  @override
  String get srvTileJsonConfig => 'JSON конфиг';

  @override
  String get srvTileSmart => 'Умный подбор параметров';

  @override
  String get srvTileDelete => 'Удалить';

  @override
  String get srvTileServerDeleted => 'Сервер удалён';

  @override
  String get srvTileSaved => 'Сохранено';

  @override
  String get pingNa => 'n/a';

  @override
  String get pingNaTooltip => 'Не ответил по TCP — сервер недоступен (мёртв)';

  @override
  String get pingTimeout => 'таймаут';

  @override
  String get pingTimeoutTooltip =>
      'TCP-проба не уложилась в таймаут — сервер недоступен';

  @override
  String pingMs(Object ms) {
    return '$ms мс';
  }

  @override
  String get pingNoProxy => 'нет прокси';

  @override
  String get pingNoProxyTooltip =>
      'Отвечает по TCP (задержка показана), но проверка через туннель (GET/HEAD) не прошла — трафик не идёт';

  @override
  String get pingOk => 'ok';

  @override
  String get pingOkTooltip =>
      'Задержка TCP до сервера. Сервер рабочий: ответил по TCP и прошёл проверку через туннель (GET/HEAD)';

  @override
  String get searchHint => 'Поиск по названию, стране, адресу…';

  @override
  String get searchReset => 'Сбросить';

  @override
  String get splitTitle => 'Раздельное туннелирование';

  @override
  String get splitTunOnlyBanner =>
      'Работает только в TUN-режиме. В режиме «Системный прокси» приложения сами решают, использовать ли прокси — управлять ими принудительно нельзя.';

  @override
  String get splitEnableTun => 'Включить TUN';

  @override
  String get splitModeHeader => 'Режим';

  @override
  String get splitAppsHeader => 'Приложения';

  @override
  String get splitAppsHint =>
      'Нажмите на приложение — действие (Туннель / Прямо / Блок) и способ сопоставления. Галочка слева включает/выключает правило.';

  @override
  String get splitByName => 'По имени';

  @override
  String get splitByPath => 'По пути';

  @override
  String get splitRuleDisabled => 'Отключено — правило не применяется';

  @override
  String get splitRemove => 'Убрать';

  @override
  String get splitFromRunning => 'Из запущенных';

  @override
  String get splitPickInstalled => 'Выбрать приложение';

  @override
  String get splitInstalledApps => 'Установленные приложения';

  @override
  String get splitPickExe => 'Выбрать .exe';

  @override
  String get splitSitesHeader => 'Сайты (домены)';

  @override
  String get splitSitesHint =>
      'Нажмите на сайт, чтобы выбрать действие (Туннель / Прямо / Блок). Домен покрывает и поддомены; поддомены группируются деревом. Можно указать порт.';

  @override
  String splitOnlyPort(Object port) {
    return 'только порт $port';
  }

  @override
  String get splitProgramsFileType => 'Программы';

  @override
  String get splitRunningApps => 'Запущенные приложения';

  @override
  String get splitSearchByName => 'Поиск по имени';

  @override
  String get splitNothingFound => 'Ничего не найдено';

  @override
  String get splitClose => 'Закрыть';

  @override
  String get splitPortRange => 'Порт 1–65535';

  @override
  String get splitAction => 'Действие';

  @override
  String get splitPortOptional => 'Порт (необязательно)';

  @override
  String get splitAnyPort => 'любой';

  @override
  String get splitPortHelper =>
      'Пусто = любой порт. Иначе правило только для этого порта';

  @override
  String get splitMatching => 'Сопоставление';

  @override
  String get splitByNameSubtitle =>
      'Имя exe, независимо от расположения (надёжно)';

  @override
  String get splitByPathSubtitle => 'Полный путь к exe (точное совпадение)';

  @override
  String get splitDone => 'Готово';

  @override
  String get splitEnterDomain => 'Введите домен';

  @override
  String get splitAddSite => 'Добавить сайт';

  @override
  String get splitPort => 'Порт';

  @override
  String get splitAdd => 'Добавить';

  @override
  String get routeBlock => 'Блок';

  @override
  String get routeBlocked => 'Заблокировано';

  @override
  String get routeYourPc => 'Ваш ПК';

  @override
  String get routeTunnel => 'Туннель';

  @override
  String get routeViaVpn => 'Через VPN';

  @override
  String get routeVpn => 'VPN';

  @override
  String get routeInternet => 'Интернет';

  @override
  String get routeRest => 'Остальное';

  @override
  String get routeDirectly => 'Напрямую';

  @override
  String get routeDirectPlusRest => 'Прямо + остальное';

  @override
  String get routeDirect => 'Прямо';

  @override
  String get routeEmptyList => 'список пуст';

  @override
  String get trayShow => 'Показать';

  @override
  String get trayToggle => 'Подключить / Отключить';

  @override
  String get trayQuit => 'Выход';

  @override
  String get trayMinimizeTitle => 'Свернуть в трей';

  @override
  String get trayMinimizeBody => 'Приложение продолжит работать в трее.';

  @override
  String get trayDontAsk => 'Не спрашивать больше';

  @override
  String get trayMinimizeOk => 'Свернуть';

  @override
  String get trayVpnTitle => 'VPN подключён';

  @override
  String get trayVpnBody => 'Отключить VPN и выйти из приложения?';

  @override
  String get trayStay => 'Остаться';

  @override
  String get trayQuitVpn => 'Отключить и выйти';

  @override
  String get tunTaskDone => 'Готово: TUN будет запускаться без запроса UAC';

  @override
  String get tunTaskFailed =>
      'Не удалось создать задачу (UAC отклонён или запрещено политикой)';

  @override
  String get tunLogTitle => 'Лог TUN (sing-box)';

  @override
  String get tunLogEmpty => 'Лог пуст — туннель ещё не запускался.';

  @override
  String get tunCopy => 'Копировать';

  @override
  String get tunClose => 'Закрыть';

  @override
  String get tunTitle => 'TUN и маршрутизация';

  @override
  String get tunSectionPrivilege => 'Права администратора';

  @override
  String get tunChecking => 'Проверяю…';

  @override
  String get tunNoUacConfigured => 'Запуск без UAC настроен';

  @override
  String get tunUacEachConnect =>
      'UAC будет запрашиваться при каждом подключении';

  @override
  String get tunTaskSubtitle =>
      'Задача Планировщика Windows с высшими правами (создаётся один раз).';

  @override
  String get tunRecreateTask => 'Пересоздать задачу';

  @override
  String get tunSetupOneUac => 'Настроить (один UAC)';

  @override
  String get tunRemoveTask => 'Удалить задачу';

  @override
  String get tunSectionAdapter => 'Адаптер';

  @override
  String get tunStack => 'Стек TUN';

  @override
  String get tunSectionRouting => 'Маршрутизация';

  @override
  String get tunStrictRoute => 'Строгая маршрутизация (strict_route)';

  @override
  String get tunIpv6 => 'IPv6 в туннеле';

  @override
  String get tunEndpointNat => 'Endpoint-independent NAT (UDP, игры)';

  @override
  String get tunLanBypass => 'Локальная сеть мимо VPN';

  @override
  String get tunDnsServer => 'DNS-сервер';

  @override
  String get tunDnsHijack => 'Перехватывать DNS (порт 53)';

  @override
  String get tunResolveStrategy => 'Стратегия резолва';

  @override
  String get tunSectionDiagnostics => 'Диагностика';

  @override
  String get tunSingboxLogLevel => 'Уровень лога sing-box';

  @override
  String get tunShowLog => 'Показать лог TUN';

  @override
  String get tunDnsVpn => 'Через VPN (рекомендуется)';

  @override
  String get tunDnsSystem => 'Системный';

  @override
  String get tunDnsCustom => 'Свой сервер';

  @override
  String get tunDnsVpnHint => 'Запросы уходят в туннель по TCP — без утечек';

  @override
  String get tunDnsSystemHint => 'Как в Windows: возможна утечка DNS';

  @override
  String get tunDnsCustomHint => 'Указанный сервер, тоже через туннель';

  @override
  String get tunExcludeSubnets => 'Подсети мимо VPN';

  @override
  String get tunAdd => 'Добавить';

  @override
  String get urlGroupImport => 'Импорт';

  @override
  String get urlGroupControl => 'Управление';

  @override
  String get urlHintSubUrl => 'URL подписки';

  @override
  String get urlHintServerLink => 'ссылка сервера';

  @override
  String get urlDescImportSub => 'Импортировать подписку';

  @override
  String get urlDescImportServer =>
      'Добавить один сервер (vless / trojan / ss / hysteria2 …)';

  @override
  String get urlDescConnect => 'Подключить VPN';

  @override
  String get urlDescDisconnect => 'Отключить VPN';

  @override
  String get urlDescToggle => 'Переключить VPN';

  @override
  String get urlDescUpdate => 'Обновить активную подписку';

  @override
  String get urlSupportedImport =>
      'При импорте приложение понимает: ссылку подписки (http/https), а также одиночные серверы vless:// / vmess:// / trojan:// / ss:// / hysteria2:// (hy2://).';

  @override
  String get reportTitle => 'SilentGate — отчёт для техподдержки';

  @override
  String get reportDescribeHere =>
      '>>> ОПИШИТЕ ПРОБЛЕМУ ЗДЕСЬ (заполните и сохраните файл): <<<';

  @override
  String get reportWhatDid => 'Что делали:';

  @override
  String get reportWhatExpected => 'Что ожидали:';

  @override
  String get reportWhatHappened => 'Что произошло:';

  @override
  String get reportWhenStarted => 'Когда началось:';

  @override
  String get reportTechNoticeLine1 =>
      'Ниже — техническая информация. Проверьте её перед отправкой;';

  @override
  String get reportTechNoticeLine2 =>
      'паролей и токена подписки здесь нет, URL подписки скрыт.';

  @override
  String get noRealIpTitle => 'Не выходить под реальным IP';

  @override
  String get noRealIpSub =>
      'Даже при рабочем VPN весь «прямой» трафик идёт через VPN (RU-сайты — тоже). Локальная сеть остаётся напрямую.';

  @override
  String get flagAuto => 'АВТО';

  @override
  String get autoUpdateIntervalLabel => 'Интервал обновления, ч';

  @override
  String get autoUpdatePreferSub => 'Брать интервал из подписки';

  @override
  String get pingLegendInfo =>
      'Цвет плашки пинга: зелёный/жёлтый/оранжевый — сервер рабочий (TCP + проверка через туннель). Серый — отвечает по TCP, но трафик не проксирует (типичный Reality-порт). Красный «n/a» — не ответил, из проверки исключён. Пинг всегда меряется НАПРЯМУЮ (вне VPN).';

  @override
  String get pingUntestedHint =>
      'Ещё не проверен. Hysteria2 и профили «Авто» на мобильном измеряются только при поднятом соединении.';

  @override
  String get panelTunnelMarker => 'Своё раздельное туннелирование';

  @override
  String panelInfoServers(Object n) {
    return 'Серверов в профиле: $n (выбирается лучший)';
  }

  @override
  String get panelInfoDirect =>
      'Часть трафика (напр. локальные сайты) идёт напрямую, мимо VPN';

  @override
  String get panelInfoBlock => 'Часть трафика блокируется (реклама/торренты)';

  @override
  String get serviceChecksTitle => 'Проверка сервисов';

  @override
  String get serviceChecksInfo =>
      'Шесть популярных сервисов проверяются сами: первый раз — при запуске приложения, пока VPN выключен, второй — сразу после подключения. Два кружка рядом показывают «было → стало», чтобы видеть, что изменил именно VPN. Нажатие проверяет сервис заново. Зелёный — открывается, оранжевый — блокировка по стране, красный — недоступен.';

  @override
  String get serviceStatusOk => 'Работает';

  @override
  String get serviceStatusGeo => 'Открывается, но заблокирован в стране выхода';

  @override
  String get serviceStatusFail => 'Не открывается';

  @override
  String get serviceStatusChecking => 'Проверка…';

  @override
  String get serviceStatusTap => 'Нажмите, чтобы проверить';

  @override
  String serviceLatencyMs(Object ms) {
    return '$ms мс';
  }

  @override
  String get homeTunAutotuneProgress => 'Подбираю параметры TUN…';

  @override
  String get homeTunAutotuneDone => 'Параметры TUN подобраны';

  @override
  String get homeTunAutotuneFailed => 'Не удалось подобрать параметры TUN';

  @override
  String get hy2NoteTitle => 'Серверы Hysteria2';

  @override
  String get hy2NoteBody =>
      'Hysteria2-серверы приходят только в формате XRAY_JSON — SilentGate его и запрашивает, sing-box поднимает их автоматически. Если Hysteria2 не появляется в списке: (владельцу панели Remnawave) включите hysteria-инбаунды и назначьте их подписке. Важно: Remnawave до 2.8.0 отдаёт Hysteria2 ТОЛЬКО в XRAY_JSON — в base64/CLASH/SINGBOX её нет, поэтому правило Response Rules → XRAY_JSON выше обязательно.';

  @override
  String get enumStatusDisconnected => 'Отключено';

  @override
  String get enumStatusConnecting => 'Подключение…';

  @override
  String get enumStatusConnected => 'Подключено';

  @override
  String get enumStatusDisconnecting => 'Отключение…';

  @override
  String get enumStatusError => 'Ошибка';

  @override
  String get enumVariantPlain => 'обычный';

  @override
  String get tagAutoSelect => 'АВТОВЫБОР';

  @override
  String get tagPanel => 'ПАНЕЛЬ';

  @override
  String get tagPortHopping => 'ПОРТ-ХОППИНГ';

  @override
  String syncServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сервера',
      many: '$count серверов',
      few: '$count сервера',
      one: '$count сервер',
    );
    return '$_temp0';
  }

  @override
  String get syncNoChanges => 'без изменений';

  @override
  String get errInvalidJson => 'Некорректный JSON';

  @override
  String get errPickServerFirst => 'Сначала выберите сервер';

  @override
  String get errImportSubscriptionFirst => 'Сначала импортируйте подписку';

  @override
  String get speedSizeFull => '20 МБ';

  @override
  String get speedSizeLight => '5 МБ';

  @override
  String speedMbPerSec(String value) {
    return '$value МБ/с';
  }

  @override
  String speedKbPerSec(String value) {
    return '$value КБ/с';
  }

  @override
  String portBusyTitle(int port, String by) {
    return 'Порт $port уже занят $by.';
  }

  @override
  String get srvTileMenu => 'Действия с сервером';

  @override
  String get supportCopyReport => 'Скопировать отчёт';

  @override
  String get supportReportCopied =>
      'Отчёт скопирован — вставьте его в чат поддержки';

  @override
  String subBarUsedOnly(String used) {
    return 'Израсходовано $used';
  }

  @override
  String get subBarUnlimitedTraffic => 'трафик без ограничений';

  @override
  String get supportDescribeLabel => 'Опишите проблему';

  @override
  String get supportDescribeHint =>
      'Что делали, что ожидали, что произошло и когда началось';

  @override
  String get supportDescribeRequired =>
      'Опишите проблему — без описания отчёт бесполезен';

  @override
  String get supportNoScreenshots =>
      'Скриншоты сюда не вставляйте — присылайте их отдельным сообщением в чат Telegram.';

  @override
  String get supportDescriptionSection => 'ОПИСАНИЕ ОТ ПОЛЬЗОВАТЕЛЯ';

  @override
  String get splitAllowRealIp => 'Разрешить этому правилу реальный IP';

  @override
  String get splitAllowRealIpOn =>
      'Поднята: это исключение, трафик выйдет под вашим реальным адресом';

  @override
  String get splitAllowRealIpOff =>
      'Снята: правило идёт через VPN — защита выше всех правил';

  @override
  String get splitRealIpExposed => 'реальный IP';

  @override
  String get splitRealIpProtected => 'через VPN';

  @override
  String get vpnActiveBadge => 'VPN активен';

  @override
  String get splitCopyDomain => 'Скопировать адрес';

  @override
  String get splitCopyPath => 'Скопировать путь';

  @override
  String get homeServerInfo => 'Информация о сервере';

  @override
  String get serverInfoVerifyInBrowser => 'Проверить в браузере';

  @override
  String get tunDnsForAll => 'DNS всех приложений через VPN';

  @override
  String get infoDnsForAll =>
      'Работает только в режиме «Только отмеченные». Включено: ни один DNS-запрос не уходит провайдеру, но домены НЕотмеченных приложений резолвятся через туннель — CDN отдаёт адрес в стране выхода, и такие приложения идут напрямую, но на дальний сервер (заметно медленнее). Выключено: неотмеченные приложения получают близкий CDN и работают быстро, зато провайдер видит, куда ходят все приложения, включая защищаемые. ⚠️ Изменение применяется только после переподключения.';

  @override
  String get homeSettingsNeedReconnect =>
      'Настройка изменена — переподключитесь, чтобы применить';

  @override
  String blockPageWindowTitle(String app) {
    return 'Заблокировано — $app';
  }

  @override
  String get blockPageHeading => 'Сайт заблокирован';

  @override
  String blockPageBody(String host, String app) {
    return 'Адрес $host заблокирован правилом раздельного туннелирования в $app.';
  }

  @override
  String get blockPageHint =>
      'Правило можно изменить: Настройки → Раздельное туннелирование → Сайты.';

  @override
  String get blockPageNote =>
      'Это страница самого приложения, а не ошибка сети. Сайт не открывается потому, что вы сами добавили его в список блокировки.';

  @override
  String get settingsBlockPage => 'Страница-заглушка при блокировке';

  @override
  String get settingsBlockPageSub =>
      'Вместо ошибки соединения открывается страница с объяснением, каким правилом закрыт сайт. Работает только для http: у https подменить страницу нельзя без установки своего корневого сертификата в систему, а он позволил бы читать весь ваш защищённый трафик.';

  @override
  String get trayCloseFully => 'Закрыть полностью';

  @override
  String errorVpnConflictApp(String app) {
    return 'Похоже, мешает $app: у него поднят собственный VPN-туннель. Два туннеля одновременно борются за маршрут по умолчанию.';
  }

  @override
  String errorCloseApp(String app) {
    return 'Закрыть $app';
  }

  @override
  String toastAppClosed(String app) {
    return '$app закрыт';
  }

  @override
  String toastAppCloseFailed(String app) {
    return 'Не удалось закрыть $app — закройте вручную';
  }

  @override
  String get tunBlockQuic => 'Запрещать QUIC (HTTP/3)';

  @override
  String get infoBlockQuic =>
      'Правила по сайтам применяются к ИМЕНИ, а имя приложение видит только в обычном TLS. Браузер, ушедший на HTTP/3, имени не показывает — и правило по домену молча не срабатывает. Запрет возвращает браузер на обычное соединение, где имя видно. Сайты от этого не ломаются: HTTP/3 для них не обязателен, но видео может грузиться чуть медленнее. Включайте, если правила по сайтам не действуют.';

  @override
  String get tunBlockEncryptedDns => 'Запрещать шифрованный DNS (DoH/DoT)';

  @override
  String get infoBlockEncryptedDns =>
      'Браузеры и Windows умеют спрашивать адреса сайтов по HTTPS в обход нашего перехвата. Тогда правила «Прямо» и «Блок» на уровне DNS не работают вовсе. Запрет возвращает запросы под наш контроль. ⚠️ Если в браузере жёстко выбран поставщик шифрованного DNS, он не откатится на обычный, а просто перестанет открывать сайты — тогда выключите настройку или уберите поставщика в браузере. Список известных поставщиков неполон по своей природе: свой можно поднять за вечер.';

  @override
  String get autoUseSpeed => 'Учитывать скорость';

  @override
  String get infoAutoUseSpeed =>
      'После отбора по сервисам и задержке трёх лучших кандидатов проверяем скачиванием и ставим первым того, кто реально быстрее. Скорость сравнивается с ВАШИМ каналом: сервер, отдающий почти весь ваш канал, дальше не оценивается по мегабитам — там решает задержка, потому что лишняя скорость сверх канала вам всё равно не достанется. ⚠️ Расходует трафик подписки: 5 МБ на ваш канал и по 5 МБ на каждого из трёх кандидатов, около 20 МБ за прогон.';

  @override
  String get autoSpeedOwn => 'Замеряю скорость своего канала…';

  @override
  String autoSpeedServer(String server, int index, int total) {
    return 'Замеряю скорость: $server ($index из $total)';
  }

  @override
  String autoSpeedShare(int percent) {
    return '$percent % вашего канала';
  }

  @override
  String get conflictDialogTitle => 'Обнаружен другой VPN';

  @override
  String conflictDialogBody(String app) {
    return 'Похоже, работает $app — у него поднят собственный туннель. Два туннеля одновременно борются за маршрут по умолчанию, и подключение может не подняться или подняться без доступа в сеть.';
  }

  @override
  String get conflictCloseAndConnect => 'Закрыть и подключиться';

  @override
  String get conflictConnectAnyway => 'Всё равно подключиться';

  @override
  String get serviceChecksLegendBefore =>
      'Доступность сервисов проверена без VPN';

  @override
  String get serviceChecksLegendAfter => 'Слева — без VPN, справа — через VPN';

  @override
  String get serviceChecksBefore => 'Без VPN';

  @override
  String get serviceChecksAfter => 'Через VPN';

  @override
  String get serviceChecksNoBaseline => 'Без VPN не проверялось';

  @override
  String autoSpeedValue(String value) {
    return '$value Мбит/с';
  }

  @override
  String get splitShowBlockPage => 'Показать страницу блокировки';

  @override
  String get splitBlockPageNeedsVpn =>
      'Страница блокировки работает только при включённом VPN';

  @override
  String get srvInfoNeedsConnection =>
      'Замер через сервер на этой платформе возможен только при включённом VPN';

  @override
  String get serviceYoutubeThrottleNote =>
      '⚠️ Замедление YouTube эта проверка не видит: провайдер отвечает нормально, но режет скорость видео. Зелёный здесь означает «сервис доступен», а не «видео проигрывается».';

  @override
  String get urlSchemeConnectServer =>
      'silentgate://connect?server=<имя сервера>';

  @override
  String get urlDescConnectServer =>
      'Подключиться к КОНКРЕТНОМУ серверу. Имя — то же, что видно в списке и что присылает подписка, например «Польша 1.5». Флаг-эмодзи и регистр можно опустить. Точного совпадения нет — сработает поиск: по стране, адресу или протоколу. Работает и с toggle.';

  @override
  String get splitSelectAllFound => 'Отметить всё найденное';

  @override
  String splitAddSelected(int count) {
    return 'Добавить ($count)';
  }

  @override
  String get splitQuicNote =>
      'Пока есть хотя бы одно правило по сайту, приложение отключает HTTP/3 (QUIC) для всего трафика. Иначе браузер уходит на HTTP/3, не оставляет имени сайта, и правило молча не срабатывает — трафик идёт мимо. Сайты от этого не ломаются: они переходят на обычный TLS, лишь чуть медленнее.';

  @override
  String get splitNoRealIpBanner =>
      'Включено «Не выходить под реальным IP»: правила «Прямо» без поднятой галочки идут через VPN';

  @override
  String get settingsNoRealIpAffects =>
      'Затрагивает правила «Прямо»: без галочки «разрешить реальный IP» они пойдут через VPN';

  @override
  String get splitAppOverrideSites => 'Важнее правил по сайтам';

  @override
  String get splitAppOverrideSitesSub =>
      'Весь трафик приложения идёт как указано, даже если для сайта задано другое';

  @override
  String get settingsMyRulesOverridePanel => 'Мои правила важнее правил панели';

  @override
  String get settingsMyRulesOverridePanelSub =>
      'Панель отдаёт своё разделение — обычно «российские сайты мимо VPN». Оно применяется после ваших правил, поэтому сайт, помеченный «Туннель», может выйти напрямую под реальным IP. Включено: написано «туннель» — значит туннель. Цена: российские сайты пойдут кругом и медленнее.';

  @override
  String get commonOpen => 'Открыть';

  @override
  String get tunRouteOnlySubnets => 'В туннель ТОЛЬКО эти подсети';

  @override
  String get infoTunRouteOnlyCidrs =>
      'Единственный способ на Windows сделать часть трафика по-настоящему независимой от VPN-клиента.\n\nОбычно туннель забирает маршрут по умолчанию, и в него заходит ВЕСЬ трафик машины: пометка «Прямо» разбирается уже внутри ядра, которое принимает пакет и выпускает его наружу от своего имени. Такой трафик живёт ровно столько, сколько живёт ядро, и зависает вместе с ним.\n\nЕсли список не пуст, маршрут по умолчанию туннелю не отдаётся: он забирает только перечисленные подсети, а всё прочее система отправляет обычным адаптером — клиент этого трафика не видит вовсе.\n\nЦена: деление идёт по адресу, а правила по приложениям и сайтам — по имени. Сайт, чей адрес не попал в список, ядро не увидит ни одним правилом. Оставьте пусто, чтобы туннель работал как обычно.';

  @override
  String get tunRouteOnlyWarning =>
      'Туннель забирает только перечисленные подсети. Правила по приложениям и сайтам действуют ТОЛЬКО внутри них: то, что в туннель не зашло, ядру не показали — заблокировать или увести такой сайт нельзя.';

  @override
  String get tunAlsoSystemProxy => 'Системный прокси вместе с туннелем';

  @override
  String get infoTunAlsoSystemProxy =>
      'Смешанный режим: работает и туннель, и системный прокси одновременно.\n\nПриложения, которые уважают системный прокси (браузеры, Telegram), пойдут коротким путём прямо в локальный порт, минуя пользовательский стек туннеля, и отдадут ядру имя домена вместо голого адреса — правила по сайтам для них станут точнее и перестанут зависеть от разбора TLS.\n\nНезависимыми от клиента они при этом НЕ становятся: ходят через тот же процесс.';

  @override
  String get tunMixedModeWarning =>
      'У соединения, пришедшего через системный прокси, нет процесса-владельца — для ядра это локальное подключение. Поэтому правила ПО ПРИЛОЖЕНИЯМ для таких программ не срабатывают. Правила по сайтам работают, и даже точнее обычного.';

  @override
  String get tunWatchdog => 'Сторож зависшего ядра';

  @override
  String get infoTunWatchdog =>
      'Сколько секунд ядру туннеля можно не отвечать, прежде чем считать его зависшим и снять туннель.\n\nЕсли ядро падает, Windows убирает за ним сама — адаптер, маршруты и правила брандмауэра снимаются, сеть возвращается. Если ядро зависает, не снимается ничего: адаптер остаётся и глотает весь трафик машины, включая помеченный «Прямо». Снаружи это «интернет пропал совсем», и само оно не проходит.\n\nСторож вооружается только после первого успешного ответа ядра: иначе он убивал бы подключение там, где не удалось поднять служебный порт. 0 — не следить. Минимум 10 секунд.';

  @override
  String get tunWatchdogOff =>
      'Выключен: зависание туннеля отслеживаться не будет';

  @override
  String tunWatchdogSubtitle(int seconds) {
    return 'Снять туннель, если ядро молчит дольше $seconds с';
  }

  @override
  String get tunDnsForAllWarning =>
      'Резолв имён ВСЕЙ машины пойдёт через туннель. Если туннель встанет, имена перестанут определяться даже у приложений, которые идут напрямую и в VPN не нуждаются, — со стороны это выглядит как полная потеря интернета.';

  @override
  String get tunCidrInvalid => 'Нужен адрес с префиксом, например 10.8.0.0/24';

  @override
  String get geoTitle => 'Гео-базы маршрутизации';

  @override
  String get geoMissing =>
      'Не скачаны — правила по странам и категориям не работают';

  @override
  String geoPresent(String size, String date) {
    return '$size, обновлены $date';
  }

  @override
  String get geoDownload => 'Скачать';

  @override
  String get geoUpdate => 'Обновить';

  @override
  String geoDownloading(String file) {
    return 'Скачиваю $file…';
  }

  @override
  String get geoDone => 'Гео-базы обновлены';

  @override
  String geoFailed(String error) {
    return 'Не удалось скачать: $error';
  }

  @override
  String get infoGeoAssets =>
      'Файлы geoip.dat и geosite.dat — списки адресов по странам и доменов по категориям (например «российские сайты», «госуслуги», «ВКонтакте»). По ним работают правила маршрутизации, которые задаёт панель подписки.\n\nВ приложение они не вложены: вдвоём весят около 30 МБ, а нужны не всем — обычному серверу они не требуются вовсе.\n\nПока файлов нет, такие правила из конфига убираются, и трафик, который они уводили напрямую, идёт через VPN. Это безопасно, но медленнее, и российские сайты могут отказывать в доступе из-за иностранного адреса. Правила по конкретным сайтам и приложениям, заданные вами, работают в любом случае — они не зависят от этих файлов.';

  @override
  String get supportBullet2Android =>
      '• После нажатия отчёт соберётся в один файл, и откроется системное окно «Поделиться» — выберите Telegram, и он уйдёт одним вложением. Опишите проблему в поле выше: без описания разбирать нечего.';

  @override
  String get supportDoneTextAndroid =>
      'Отчёт собран в один файл. Выберите в системном окне, куда его отправить — в Telegram он уйдёт вложением, а не текстом.';
}
