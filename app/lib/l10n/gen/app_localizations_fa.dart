// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get settingsTitle => 'تنظیمات';

  @override
  String get commonCancel => 'لغو';

  @override
  String get commonClose => 'بستن';

  @override
  String get commonCopy => 'کپی';

  @override
  String get commonClear => 'پاک کردن';

  @override
  String get commonCopied => 'کپی شد';

  @override
  String get commonRefresh => 'بازخوانی';

  @override
  String get commonCheck => 'بررسی';

  @override
  String get commonOk => 'تأیید';

  @override
  String get commonDone => 'انجام شد';

  @override
  String get commonPathCopied => 'مسیر کپی شد';

  @override
  String get languageTitle => 'زبان رابط کاربری';

  @override
  String get languageSubtitle => 'زبان برنامه را انتخاب کنید';

  @override
  String get languageSystem => 'پیش‌فرض سیستم';

  @override
  String get sectionAppearance => 'ظاهر و رفتار';

  @override
  String get sectionCapture => 'گرفتن ترافیک';

  @override
  String get sectionReliability => 'پایداری اتصال';

  @override
  String get sectionPing => 'پینگ';

  @override
  String get sectionIdentity => 'معرفی به پنل';

  @override
  String get sectionNetwork => 'شبکه';

  @override
  String get sectionAbout => 'درباره';

  @override
  String get sectionSupport => 'پشتیبانی';

  @override
  String get settingsSearchHint => 'جست‌وجو در تنظیمات';

  @override
  String settingsSearchEmpty(String query) {
    return 'چیزی پیدا نشد: «$query»';
  }

  @override
  String get settingsExpand => 'باز کردن';

  @override
  String get settingsCollapse => 'جمع کردن';

  @override
  String get appearanceTheme => 'پوسته';

  @override
  String get themeSystem => 'سیستمی';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeDark => 'تیره';

  @override
  String get closeToTrayTitle => 'کوچک شدن به تری هنگام بستن';

  @override
  String get closeToTraySubtitle =>
      'دکمه بستن پنجره را در تری پنهان می‌کند؛ خاموش کنید تا به‌جای آن برنامه بسته شود';

  @override
  String get autoUpdateSubTitle => 'به‌روزرسانی خودکار اشتراک';

  @override
  String get autoUpdateSubText => 'به‌صورت دوره‌ای فهرست سرورها را تازه کن';

  @override
  String get captureSystemProxy => 'پروکسی سیستمی';

  @override
  String get captureSystemProxySub =>
      'همین حالا کار می‌کند. بدون نیاز به دسترسی مدیر.';

  @override
  String get captureTun => 'TUN (تونل کامل)';

  @override
  String get captureTunBadgeUac => 'نیازمند UAC';

  @override
  String get captureTunSub =>
      'تمام ترافیک، شامل UDP و برنامه‌هایی که پروکسی را نادیده می‌گیرند. نیازمند دسترسی مدیر است.';

  @override
  String get tunProvider => 'ارائه‌دهنده TUN';

  @override
  String get tunRoutingTitle => 'TUN و مسیریابی';

  @override
  String tunRoutingSub(String stack, int mtu, String dns) {
    return 'استک $stack · MTU $mtu · DNS $dns';
  }

  @override
  String get splitTunnelTitle => 'تونل تفکیکی';

  @override
  String splitRulesCount(int n, int apps, int sites) {
    return '$n قانون ($apps برنامه، $sites سایت)';
  }

  @override
  String get captureTunHint =>
      'تنظیمات TUN، DNS و تونل تفکیکی هنگام انتخاب حالت TUN نمایان می‌شوند — در حالت پروکسی سیستمی بی‌اثرند.';

  @override
  String get captureProxyOnly => 'فقط پروکسی';

  @override
  String get captureProxyOnlySub =>
      'هسته بالا آمده و پورت‌های محلی گوش می‌دهند، اما رایانه در تونل نیست: فقط چیزی که صراحتاً به پروکسی ما اشاره کند از VPN عبور می‌کند';

  @override
  String get apiSectionTitle => 'API برای اتوماسیون';

  @override
  String get apiEnableTitle => 'فعال‌سازی API محلی';

  @override
  String apiEnableSub(int port) {
    return 'HTTP روی 127.0.0.1:$port — کنترل کلاینت از طریق اسکریپت‌ها';
  }

  @override
  String get apiTokenTitle => 'توکن';

  @override
  String get apiTokenUnset => 'تنظیم نشده — API بالا نمی‌آید';

  @override
  String get apiTokenRegenerate => 'بازسازی توکن';

  @override
  String get apiTokenWarning =>
      'توکن به‌صورت متن ساده در پروندهٔ تنظیمات است. به لاگ و گزارش پشتیبانی نمی‌رسد، اما هر کس آن را داشته باشد می‌تواند سرور را عوض کند و وضعیت اشتراک شما را بخواند.';

  @override
  String get apiExitsTitle => 'سرورهای دارای پورت اختصاصی';

  @override
  String get apiExitsSub =>
      'به هر کدام پورت محلی جداگانه‌ای داده می‌شود — درخواست به آن پورت از همان سرور عبور می‌کند';

  @override
  String get apiCopyPythonExample => 'کپی نمونه پایتون';

  @override
  String apiPortsHint(int control, int direct, int first) {
    return 'کنترل — پورت $control. «مستقیم» — پورت $direct. سرورها — از $first.';
  }

  @override
  String get apiRulesInProxyOnly => 'اعمال قوانین تونل تفکیکی';

  @override
  String get apiRulesInProxyOnlySub =>
      'در این حالت قوانین پیش‌فرض برای هیچ برنامه‌ای اعمال نمی‌شوند. اگر می‌خواهید فهرست «مسدودسازی» درخواست‌های ارسالی از طریق پورت‌های محلی را هم پوشش دهد، این را فعال کنید.';

  @override
  String apiCaptureModeWarning(int control) {
    return '⚠️ حالت گرفتن ترافیک روی «پروکسی سیستمی» است — در این حالت درگاه‌های خروج باز نمی‌شوند و اتصال به آن‌ها رد می‌شود. درگاه کنترل $control با هر حالتی کار می‌کند. اگر به درگاه‌های خروج نیاز دارید «TUN (تونل کامل)» یا «فقط پروکسی» را انتخاب کنید.';
  }

  @override
  String get apiPortBusyTitle => 'API بالا نیامد';

  @override
  String apiPortBusy(int port, String holder) {
    return 'درگاه $port در اختیار $holder است. آن برنامه را کامل ببندید، از جمله از سینی سیستم، و سپس کلید را دوباره روشن کنید.';
  }

  @override
  String apiPortBusyUnknown(int port) {
    return 'درگاه $port در اختیار برنامهٔ دیگری است که شناسایی نشد. معمولاً یک کلاینت VPN دیگر است. آن را ببندید و کلید را دوباره روشن کنید.';
  }

  @override
  String get apiRulesInProxyOnlyEdit =>
      'فهرست «مسدود» در صفحهٔ تونل تفکیکی ویرایش می‌شود';

  @override
  String get dnsShortVpn => 'از طریق VPN';

  @override
  String get dnsShortSystem => 'سیستمی';

  @override
  String get dnsShortCustom => 'سفارشی';

  @override
  String get tunUacTitle => 'TUN نیازمند دسترسی مدیر است';

  @override
  String get tunUacBody =>
      'می‌توانید یک‌بار آن را تنظیم کنید: برنامه یک وظیفه در زمان‌بند وظایف ویندوز با بالاترین سطح دسترسی می‌سازد و پس از آن تونل بدون درخواست UAC آغاز می‌شود.\n\nاکنون یک درخواست دسترسی مدیر ظاهر می‌شود. خودِ برنامه بدون دسترسی بالا به کارش ادامه می‌دهد.';

  @override
  String get tunUacLater => 'بعداً (هربار بپرس)';

  @override
  String get tunUacSetup => 'تنظیم';

  @override
  String get tunUacDone => 'انجام شد: TUN بدون درخواست UAC آغاز می‌شود';

  @override
  String get tunUacFail =>
      'ساخت وظیفه ممکن نشد — هنگام اتصال UAC درخواست خواهد شد';

  @override
  String get autoReconnectTitle => 'اتصال مجدد خودکار';

  @override
  String get autoReconnectSub => 'بازگرداندن اتصال هنگام قطعی و تغییر شبکه';

  @override
  String get killSwitchTitle => 'کیل‌سوییچ';

  @override
  String get alwaysOnTitle => 'محافظت در سطح سیستم';

  @override
  String get alwaysOnSub =>
      'VPN همیشه‌روشن و «مسدودکردن اتصال بدون VPN» — حتی با برنامهٔ بسته کار می‌کند';

  @override
  String get killSwitchSubTun =>
      'نگذار ترافیک هنگام اتصال مجدد از کنار VPN عبور کند';

  @override
  String get killSwitchSubProxy =>
      'در حالت «پروکسی سیستمی» فقط از برنامه‌های سازگار با پروکسی محافظت می‌کند. کامل — فقط با TUN';

  @override
  String get killSwitchSubOff => 'نیازمند فعال بودن اتصال مجدد خودکار است';

  @override
  String get networkRecoverTitle => 'بازیابی شبکه';

  @override
  String get networkRecoverSub =>
      'اگر پس از VPN اینترنت قطع شد. نیازمند دسترسی مدیر';

  @override
  String get networkRecoverConfirmTitle => 'شبکه بازیابی شود؟';

  @override
  String get networkRecoverConfirmBody =>
      'بازنشانی winsock، پشته IP، DNS و پروکسی سیستمی. دسترسی مدیر (UAC) لازم است. بازنشانی winsock/IP پس از راه‌اندازی مجدد اعمال می‌شود.';

  @override
  String get networkRecoverConfirmOk => 'بازیابی';

  @override
  String get interferenceTitle => 'بررسی تداخل (VPNهای دیگر)';

  @override
  String get interferenceDialogTitle => 'تداخل شبکه';

  @override
  String get interferenceNoneFound => 'VPN دیگر یا تداخلی یافت نشد.';

  @override
  String get interferenceIgnore => 'نادیده بگیر';

  @override
  String get identityUserAgent => 'User-Agent';

  @override
  String identityUaAutoNote(String version) {
    return 'به‌صورت خودکار همراه با نسخه برنامه به‌روزرسانی می‌شود. همچنین ارسال می‌شوند: X-HWID، X-Device-OS، X-Ver-OS، X-App-Version ($version).';
  }

  @override
  String get urlSchemesTitle => 'طرح‌های URL';

  @override
  String get urlSchemesSub =>
      'درون‌ریزی و کنترل VPN از طریق لینک (connect / toggle / update)';

  @override
  String get panelOwnerTitle => 'برای مالک پنل';

  @override
  String get panelOwnerBody =>
      'کاربران عادی به این نیازی ندارند — می‌توانید از آن بگذرید.\n\nبرای اینکه برنامه اشتراک شما را در قالب صحیح JSON (XRAY_JSON) دریافت کند، این بلوک را به Response Rules پنل Remnawave خود اضافه کنید — با User-Agent ما تطبیق می‌یابد:';

  @override
  String get panelOwnerCopy => 'کپی بلوک';

  @override
  String get aboutVersion => 'نسخه SilentGate';

  @override
  String get aboutXrayCore => 'هسته Xray';

  @override
  String get aboutHwid => 'HWID دستگاه';

  @override
  String get aboutThirdPartyTitle => 'مؤلفه‌ها و مجوزهای شخص ثالث';

  @override
  String get aboutThirdPartySub =>
      'Xray-core (MPL-2.0)، sing-box (GPL-3.0)، Wintun — به‌صورت فرآیندهای جداگانه اجرا می‌شوند';

  @override
  String get aboutThirdPartySubEmbedded =>
      'Xray-core (MPL-2.0)، sing-box (GPL-3.0)، libXray (MIT) — درون برنامه جای گرفته‌اند';

  @override
  String get thirdPartyBodyEmbedded =>
      'On Android the cores are BUILT INTO the app (a native library inside the APK).\n\n• sing-box — GPL-3.0. The library is linked into the app, so derivatives must stay under GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nClient source code: https://github.com/Solat228/silentgate\nFull license texts — buttons below.';

  @override
  String get logsTitle => 'گزارش‌ها';

  @override
  String get logsSub =>
      'برنامه و TUN (sing-box): درون‌ریزی اشتراک، پینگ، خطاها';

  @override
  String get thirdPartyTitle => 'مؤلفه‌های شخص ثالث';

  @override
  String get thirdPartyBody =>
      'SilentGate همراه با فایل‌های اجرایی شخص ثالث عرضه می‌شود. آن‌ها به‌صورت فرآیندهای جداگانه اجرا می‌شوند و درون برنامه تعبیه نشده‌اند.\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  تونل TUN و هسته پروکسی برای Hysteria2\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — مجوز Wintun\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — داده‌های مسیریابی، CC-BY-SA-4.0\n\nمتن کامل مجوزها در پوشه «licenses» کنار برنامه است.';

  @override
  String get supportSectionNote =>
      'روی «تماس با پشتیبانی» بزنید — پنجره‌ای باز می‌شود که در آن خودتان یک فایل گزارش می‌سازید (نسخه‌ها، سیستم‌عامل، تنظیمات، app.log و انتهای singbox.log؛ بدون رمز عبور یا توکن اشتراک، URL پنهان است). پس از آن دکمه‌ای برای ارسال به پشتیبانی تلگرام ظاهر می‌شود.';

  @override
  String get supportButtonTitle => 'تماس با پشتیبانی';

  @override
  String get supportButtonSub => 'ساخت یک گزارش و باز کردن چت پشتیبانی';

  @override
  String get supportDialogTitle => 'پشتیبانی';

  @override
  String get supportDialogTitleDone => 'گزارش آماده است — کجا ارسال شود';

  @override
  String get supportWhatWillHappen => 'چه اتفاقی می‌افتد:';

  @override
  String get supportBullet1 =>
      '• یک فایل، نسخه‌ها، سیستم‌عامل، تنظیمات و گزارش‌ها (app.log و انتهای singbox.log) را گرد می‌آورد. هیچ رمز عبور یا توکن اشتراکی در آن نیست و URL اشتراک پنهان است.';

  @override
  String get supportBullet2 =>
      '• پس از زدن دکمه، ابتدا پوشه حاوی فایل و سپس خودِ فایل باز می‌شود. مشکل را در بالای فایل بنویسید، ذخیره کنید — و دکمه‌ای برای ارسال به پشتیبانی ظاهر می‌شود.';

  @override
  String supportError(String error) {
    return 'ساخت گزارش ناموفق بود: $error';
  }

  @override
  String get supportDoneText =>
      'گزارش ساخته و باز شد (ابتدا پوشه، سپس فایل). مشکل را در بالای فایل بنویسید، فایل را ذخیره و به پشتیبانی ارسال کنید — برنامه به باز کردن تلگرام کمک می‌کند.';

  @override
  String get supportWhoTo => 'کجا ارسال شود:';

  @override
  String get supportContact => 'تماس با پشتیبانی';

  @override
  String supportContactNamed(String name) {
    return 'تماس با پشتیبانی ($name)';
  }

  @override
  String get supportDevServiceName => 'توسعه‌دهنده کلاینت';

  @override
  String get supportShowOnPc => 'نمایش روی رایانه';

  @override
  String get supportCopyPath => 'کپی مسیر';

  @override
  String get supportGenerating => 'در حال ساخت…';

  @override
  String get supportGenerateButton => 'ساخت گزارش برای پشتیبانی';

  @override
  String get pingTwoPhaseTitle => 'بررسی کارکرد (از طریق تونل)';

  @override
  String get pingTwoPhaseSubOn =>
      'پس از TCP — درخواستی از طریق سرور: موارد ناکارآمد (Reality و غیره) را کنار می‌گذارد';

  @override
  String get pingTwoPhaseSubOff =>
      'فقط تنها روش انتخاب‌شده (پایین) استفاده می‌شود';

  @override
  String get pingMethodCheck => 'روش بررسی:';

  @override
  String get pingMethodPing => 'روش پینگ:';

  @override
  String get speedTestProbe => 'کاوشگر تست سرعت:';

  @override
  String get speedTestFull => '۲۰ مگابایت (دقیق‌تر)';

  @override
  String get speedTestLight => '۵ مگابایت (صرفه‌جویانه)';

  @override
  String get testUrlLabel => 'URL آزمایشی (از طریق پروکسی)';

  @override
  String get appUpdateServerUnavailable => 'سرور به‌روزرسانی در دسترس نیست';

  @override
  String appUpdateAvailable(String version) {
    return 'نسخه $version موجود است';
  }

  @override
  String get appUpdateLatest => 'شما آخرین نسخه را دارید';

  @override
  String get appUpdateDownload => 'دانلود';

  @override
  String get appUpdateCheckTitle => 'بررسی به‌روزرسانی هنگام اجرا';

  @override
  String get appUpdateManual => 'دانلود و نصب — به‌صورت دستی';

  @override
  String get appUpdateEndpointLabel => 'نقطه پایانی نسخه';

  @override
  String get urlSchemeSilentgateTitle => 'لینک‌های silentgate://';

  @override
  String get urlSchemeSilentgateSub =>
      'درون‌ریزی و کنترل VPN از طریق لینک. به‌صورت پیش‌فرض فعال';

  @override
  String get urlSchemeDisableTitle => 'لینک‌های silentgate:// غیرفعال شوند؟';

  @override
  String get urlSchemeDisableBody =>
      'درون‌ریزی از طریق لینک و طرح‌های کنترلی (connect / disconnect / toggle / update) از کار می‌افتند. اگر مطمئن نیستید روشن بگذارید.';

  @override
  String get urlSchemeDisableOk => 'غیرفعال کن';

  @override
  String get urlSchemeServerTitle => 'باز کردن لینک‌های سرور';

  @override
  String get urlSchemeServerSub =>
      'گرفتن vless:// و دیگر لینک‌ها از کلاینت‌های دیگر';

  @override
  String get urlSchemeServerConfirmTitle => 'لینک‌های سرور گرفته شوند؟';

  @override
  String urlSchemeServerConfirmBody(String schemes) {
    return '$schemes\n\nاین لینک‌ها معمولاً به کلاینت VPN دیگری (Happ، v2rayTun) وصل‌اند. SilentGate آن‌ها را به خود می‌گیرد.';
  }

  @override
  String get urlSchemeServerConfirmOk => 'بگیر';

  @override
  String get urlSchemeAutoConnect => 'اتصال پس از درون‌ریزی';

  @override
  String get autoTitle => 'پیکربندی خودکار';

  @override
  String get autoClearResults => 'پاک کردن نتایج';

  @override
  String autoFoundWorking(Object count) {
    return 'موارد کارآمد یافت‌شده: $count';
  }

  @override
  String get autoPinnedTop => ' — در بالای فهرست سنجاق شدند';

  @override
  String get autoSearchContinues => ' (جستجو ادامه دارد…)';

  @override
  String get autoCheckServices => 'بررسی سرویس‌ها';

  @override
  String get autoPinFoundOnTop => 'سنجاق کردن سرورهای یافت‌شده در بالای فهرست';

  @override
  String get autoTryFragment => 'امتحان دور زدن (fragment)';

  @override
  String get autoNoSubscriptionPasteKey =>
      'اشتراکی نیست. یک کلید را جای‌گذاری کنید — تنظیمات کارآمد را پیدا می‌کنیم:';

  @override
  String get autoTuneByKey => 'تنظیم بر اساس کلید';

  @override
  String autoTesting(int index, int total) {
    return 'در حال آزمایش $index/$total: ';
  }

  @override
  String autoVariant(Object label) {
    return 'گونه: $label';
  }

  @override
  String autoServicesPassed(int ok, int total) {
    return '$ok از $total سرویس';
  }

  @override
  String get autoConnect => 'اتصال';

  @override
  String get autoStopSearch => 'توقف جستجو';

  @override
  String get autoDoneRefreshPing => 'انجام شد — بازخوانی پینگ موارد یافت‌شده';

  @override
  String autoFoundPinnedRefreshing(Object count) {
    return '$count مورد یافت شد و در بالا سنجاق شد. در حال بازخوانی پینگ…';
  }

  @override
  String autoServersForTuning(int selected, int total) {
    return 'سرورهای قابل تنظیم ($selected/$total)';
  }

  @override
  String get autoSelectAll => 'همه';

  @override
  String get autoDeselectAll => 'پاک کردن';

  @override
  String get autoTuneSelected => 'تنظیم موارد انتخاب‌شده';

  @override
  String autoTuned(Object label) {
    return 'تنظیم شد: $label';
  }

  @override
  String get infoDialogTitle => 'توضیح';

  @override
  String get infoCopied => 'توضیح کپی شد';

  @override
  String get commonGotIt => 'متوجه شدم';

  @override
  String get enumSplitAll => 'همه — از طریق VPN';

  @override
  String get enumSplitOnly => 'فقط انتخاب‌شده‌ها — از طریق VPN';

  @override
  String get enumSplitExcept => 'انتخاب‌شده‌ها — بیرون از VPN';

  @override
  String get enumActionTunnel => 'تونل';

  @override
  String get enumActionDirect => 'مستقیم';

  @override
  String get enumActionBlock => 'مسدود';

  @override
  String homeUpdateAvailable(Object version) {
    return 'نسخه $version موجود است';
  }

  @override
  String get homeDownload => 'دانلود';

  @override
  String homeSubscriptionUpdated(Object summary) {
    return 'اشتراک به‌روزرسانی شد: $summary';
  }

  @override
  String get homeReconnect => 'اتصال مجدد';

  @override
  String homePingProgress(int done, int total) {
    return 'پینگ سرورها: $done از $total';
  }

  @override
  String get homeAutoConfigStarting => 'پیکربندی خودکار در حال آغاز…';

  @override
  String homeAutoConfigProgress(int current, int total, String name) {
    return 'پیکربندی خودکار: $current از $total — $name';
  }

  @override
  String get homeImport => 'درون‌ریزی';

  @override
  String get homeSettings => 'تنظیمات';

  @override
  String get homeAutoBest => 'خودکار (بهترین سرور)';

  @override
  String get homeAutoConfig => 'پیکربندی خودکار';

  @override
  String homeServersCount(Object count) {
    return 'سرورها ($count)';
  }

  @override
  String homeFoundCount(int found, int total) {
    return '$found از $total یافت شد';
  }

  @override
  String get homePingServers => 'پینگ سرورها';

  @override
  String get homePingFound => 'پینگ موارد یافت‌شده';

  @override
  String get homeNothingFound => 'چیزی یافت نشد';

  @override
  String get homeOnboardingTitle => 'با درون‌ریزی یک اشتراک شروع کنید';

  @override
  String get homeOnboardingSubtitle =>
      'یک لینک Remnawave یا یک کلید تکی را جای‌گذاری کنید';

  @override
  String get homeImportSubscription => 'درون‌ریزی اشتراک';

  @override
  String homeSessionTraffic(String down, String up) {
    return 'این نشست: ↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'گیگابایت';

  @override
  String subBarUsage(String used, String total) {
    return '$used از $total';
  }

  @override
  String get subBarSubscription => 'اشتراک';

  @override
  String get subBarRefreshing => 'در حال بازخوانی…';

  @override
  String get subBarRefreshSubscription => 'بازخوانی اشتراک';

  @override
  String get subBarSupport => 'پشتیبانی';

  @override
  String get subBarRefresh => 'بازخوانی';

  @override
  String get subBarAddSubscription => 'افزودن اشتراک';

  @override
  String get subBarCopyLink => 'کپی لینک';

  @override
  String get subBarDeleteSubscription => 'حذف اشتراک';

  @override
  String get subBarLinkCopied => 'لینک کپی شد';

  @override
  String get subBarDeleteConfirmTitle => 'اشتراک حذف شود؟';

  @override
  String get subBarDeleteConfirmBody =>
      'سرورهای این اشتراک از فهرست حذف خواهند شد.';

  @override
  String subBarDeletePinned(Object count) {
    return 'موارد سنجاق‌شده ($count) هم با ویرایش‌هایشان حذف شوند';
  }

  @override
  String get subBarDeletePinnedHint =>
      'در غیر این صورت در فهرست می‌مانند و از حذف جان به در می‌برند';

  @override
  String get subBarCancel => 'لغو';

  @override
  String get subBarDelete => 'حذف';

  @override
  String get subBarSubscriptionDeleted => 'اشتراک حذف شد';

  @override
  String subBarSubscriptionUpdated(Object summary) {
    return 'اشتراک به‌روزرسانی شد: $summary';
  }

  @override
  String get subBarMore => 'جزئیات';

  @override
  String subBarAdded(Object count) {
    return 'افزوده شد ($count)';
  }

  @override
  String subBarRemoved(Object count) {
    return 'حذف شد ($count)';
  }

  @override
  String subBarAutoUpdate(Object hours) {
    return '· به‌روزرسانی خودکار $hours ساعت';
  }

  @override
  String subBarValidPerpetual(Object auto) {
    return 'اعتبار: نامحدود  $auto';
  }

  @override
  String get subBarExpired => 'اشتراک منقضی شد:';

  @override
  String get subBarValidUntil => 'معتبر تا:';

  @override
  String get subSwitcherPingAll => 'آزمودن سرورهای همهٔ اشتراک‌ها';

  @override
  String get subSwitcherPingBusySpeed =>
      'پینگ در دسترس نیست: آزمایش سرعت در حال اجراست';

  @override
  String get subSwitcherExpired => 'منقضی';

  @override
  String subSwitcherExpiredOn(String date) {
    return 'اشتراک در $date منقضی شد';
  }

  @override
  String subSwitcherCountTotal(int total) {
    return 'سرورهای این اشتراک: $total. هنوز بررسی کانال انجام نشده — «آزمودن سرورهای همهٔ اشتراک‌ها» را اجرا کنید.';
  }

  @override
  String subSwitcherCountWorking(int total, int working) {
    return 'سرورهای این اشتراک: $total که از آن‌ها $working سرور بررسی کانال (درخواست از راه سرور) را گذرانده‌اند.';
  }

  @override
  String subSwitcherCountChecking(int total) {
    return 'تعداد سرورهای این اشتراک: $total. بررسی هم‌اکنون در حال اجراست — تعداد سرورهای سالم پس از پایان آن نمایش داده می‌شود.';
  }

  @override
  String subSwitcherCountPartial(int total, int working) {
    return 'تعداد سرورهای این اشتراک: $total. بررسی به پایان نرسید (لغو یا قطع شد)، بنابراین عدد ناقص است: از میان سرورهایی که بررسی شدند، $working سرور آزمون کانال را گذراند.';
  }

  @override
  String get infoCaptureMode =>
      'شیوه گرفتن ترافیک. «پروکسی سیستمی» یک پروکسی محلی در سیستم تنظیم می‌کند (بدون دسترسی مدیر؛ مرورگرها و بیشتر برنامه‌ها را می‌گیرد). «TUN» یک آداپتور شبکه مجازی است که تمام ترافیک را می‌گیرد (شامل UDP و برنامه‌هایی که پروکسی را نادیده می‌گیرند)، اما نیازمند دسترسی مدیر است.';

  @override
  String get infoSystemProxy =>
      'یک پروکسی HTTP محلی در تنظیمات سیستم (رجیستری WinINET). بدون دسترسی مدیر. UDP و برنامه‌هایی که پروکسی سیستمی را نادیده می‌گیرند را نمی‌گیرد.';

  @override
  String get infoTunMode =>
      'یک تونل کامل از طریق آداپتور مجازی wintun + sing-box. تمام ترافیک، شامل UDP، را می‌گیرد. هنگام فعال‌سازی دسترسی مدیر (UAC) درخواست می‌کند.';

  @override
  String get infoTunProvider =>
      'درایور آداپتور شبکه مجازی. در ویندوز از wintun استفاده می‌شود (همراه هسته عرضه می‌شود). درایور دیگری لازم نیست.';

  @override
  String get infoTunStack =>
      'پشته شبکه TUN (sing-box).\n\n«auto» — انتخاب خودکار: اگر تونل بالا نیاید، خودِ برنامه به‌ترتیب system ← gvisor ← mixed را امتحان می‌کند و سپس MTU را کاهش می‌دهد (۱۴۰۰، ۱۲۸۰). ترکیبی که کار کرد ذخیره می‌شود و بار بعد نخست امتحان می‌شود. روند انتخاب در وضعیت و گزارش نمایش داده می‌شود.\n\nانتخاب صریح، انتخاب خودکار را غیرفعال می‌کند: system — پشته سیستم‌عامل، سریع‌ترین اما با آنتی‌ویروس‌ها ناسازگارتر؛ gvisor — فضای کاربر، کندتر، بیشترین سازگاری؛ mixed — TCP از طریق system و UDP از طریق gvisor.';

  @override
  String get infoTunMtu =>
      'بیشینه اندازه بسته در آداپتور TUN. پیش‌فرض ۱۵۰۰ است؛ اگر قطعی دارید آن را کاهش دهید (۱۴۰۰، ۱۲۸۰) — مقدار بیش از حد کوچک سرعت را کم می‌کند.\n\nبا پشته «auto» این فقط مقدار آغازین است: اگر تونل بالا نیاید، خودِ برنامه MTUهای کوچک‌تر را امتحان می‌کند.';

  @override
  String get infoTunStrictRoute =>
      'مسیریابی سخت‌گیرانه در sing-box. در ویندوز دو مشکل رایج را برطرف می‌کند: نشت DNS (به‌طور پیش‌فرض سیستم پرس‌وجوها را همزمان به همه آداپتورها می‌فرستد) و خطای «شبکه در دسترس نیست». فقط اگر VirtualBox/Hyper-V را خراب کند آن را خاموش کنید.';

  @override
  String get infoTunIpv6 =>
      'هدایت IPv6 به داخل تونل. اگر آن را خاموش کنید در حالی که ISP شما IPv6 فعال دارد، بخشی از ترافیک بیرون از VPN می‌رود (نشت آدرس واقعی) یا معلق می‌ماند. فقط هنگام مشکلات شبکه IPv6 آن را خاموش کنید.';

  @override
  String get infoTunEndpointIndependentNat =>
      'حالت NAT برای UDP. برای بازی‌ها، چت‌های صوتی و WebRTC لازم است — بدون آن ممکن است اتصال‌ها برقرار نشوند. فقط برای صرفه‌جویی در حافظه آن را غیرفعال کنید.';

  @override
  String get infoTunBypassLan =>
      'شبکه محلی (آدرس‌های خصوصی 192.168.*، 10.*، روتر، چاپگرها، NAS) از کنار VPN عبور می‌کند. معمولاً بهتر است روشن باشد، وگرنه دسترسی به دستگاه‌های شبکه را از دست می‌دهید.';

  @override
  String get infoTunExcludeCidrs =>
      'زیرشبکه‌های بیشتری که همیشه از کنار VPN عبور می‌کنند (قالب CIDR، مثلاً 10.8.0.0/24). برای شبکه‌های سازمانی و VPNهای دیگر مفید است.';

  @override
  String get infoTunPrivilege =>
      'TUN نیازمند دسترسی مدیر است. یک‌بار، وظیفه‌ای در زمان‌بند وظایف ویندوز با بالاترین سطح دسترسی می‌سازیم — پس از آن تونل بدون درخواست UAC در هر اتصال آغاز می‌شود. این وظیفه متعلق به شماست و با دکمه پایین یا هنگام حذف برنامه پاک می‌شود.';

  @override
  String get infoAppUpdate =>
      'برنامه یک‌بار در هر اجرا از سرور شما می‌پرسد که آیا نسخه جدیدتری هست و اعلانی با دکمه «دانلود» نمایش می‌دهد.\n\nبرنامه به‌تنهایی هیچ چیزی دانلود یا اجرا نمی‌کند: نصب‌کننده با گواهی امضا نشده و اجرای خودکار یک exe دانلود‌شده به SmartScreen برمی‌خورد و برای آنتی‌ویروس‌ها مانند رفتار بدافزار به نظر می‌رسد. به‌روزرسانی را خودتان نصب می‌کنید.\n\nاگر سرور در دسترس نباشد، برنامه فقط سکوت می‌کند و ورودی‌ای در گزارش می‌نویسد. قالب پاسخ و راه‌اندازی سرور در docs/APP_UPDATE.md توضیح داده شده است.';

  @override
  String get infoSpeedTest =>
      'حجم داده‌ای که هنگام سنجش سرعت دانلود می‌شود (کلیک راست روی سرور ← «اطلاعات سرور» ← «سنجش سرعت»).\n\n۲۰ مگابایت — حالت اصلی: روی خطوط پرسرعت (۱۰۰+ مگابیت بر ثانیه) یک کاوش کوتاه فرصت شتاب‌گیری ندارد و نتیجه را کمتر از واقع نشان می‌دهد.\n۵ مگابایت — حالت صرفه‌جویانه: از نظر ترافیک به‌مراتب ارزان‌تر، برای عبور از سرورهای زیاد کاربردی است.\n\nسنجش فقط به‌صورت دستی اجرا می‌شود و از ترافیک اشتراک شما مصرف می‌کند. سرعت دو بار سنجیده می‌شود: مستقیم و از طریق سرور انتخاب‌شده، تا دقیقاً ببینید چقدر روی VPN از دست می‌رود.';

  @override
  String get infoAutoReconnect =>
      'اگر هسته از کار بیفتد، سرور قطع شود یا شبکه تغییر کند (وای‌فای ↔ کابل، بیدار شدن از خواب، آی‌پی جدید)، برنامه خودش اتصال را دوباره برقرار می‌کند. فاصلهٔ میان تلاش‌ها بیشتر می‌شود: ۰٫۸ ثانیه ← ۳ ثانیه ← ۸ ثانیه ← ۲۰ ثانیه و پس از آن روی ۲۰ ثانیه می‌ماند. هشت تلاش انجام می‌شود و پس از آن برنامه تسلیم می‌شود و خطا نشان می‌دهد. قطع اتصال با دکمه همیشه بازیابی را لغو می‌کند.\n\n⚠️ با روشن بودن کلید قطع، تلاش‌ها هرگز تمام نمی‌شوند. تا زمانی که ادامه دارند ترافیک مسدود می‌ماند، و متوقف کردنشان یعنی رها کردن آن به بیرون از وی‌پی‌ان — بنابراین برنامه هر ۲۰ ثانیه تلاش را ادامه می‌دهد تا خودتان وی‌پی‌ان را خاموش کنید، و دربارهٔ شکست حداکثر هر ۱۵ دقیقه یک‌بار یادآوری می‌کند. سروری که یک ساعت بعد برگردد، خودبه‌خود دوباره گرفته می‌شود.\n\nدر حالت «خودکار (بهترین سرور)» برنامه آخرین تلاش را روی سرور مرده هدر نمی‌دهد: همان در هفتمین از هشت، به نامزد بعدی می‌رود و شمارش آنجا از نو آغاز می‌شود.\n\nتغییر شبکه از روی نشانی‌های واقعی کارت‌های دیگر تشخیص داده می‌شود: تونل خودمان و نشانی‌های سرویس (link-local) به حساب نمی‌آیند، تغییر تنها وقتی پذیرفته می‌شود که در دو بررسی پیاپی پابرجا مانده باشد، و در ۱۵ ثانیهٔ نخست پس از اتصال این نشانه نادیده گرفته می‌شود. بدون این محافظ‌ها، بالا آمدن خود تونل «تغییر شبکه» شمرده می‌شد و باعث اتصال مجدد بی‌پایان می‌گشت.';

  @override
  String get infoKillSwitch =>
      'نگذار ترافیک هنگام بازیابی اتصال از کنار VPN بیرون برود. گرفتن ترافیک بین تلاش‌ها رها نمی‌شود: در حالت TUN آداپتور بالا می‌ماند و در حالت «پروکسی سیستمی» پروکسی همچنان تنظیم‌شده می‌ماند — برنامه‌ها به‌جای دسترسی رمزنگاری‌نشده به اینترنت، خطای اتصال می‌گیرند.\n\nصادقانه درباره محدودیت‌ها: در حالت «پروکسی سیستمی» این فقط از برنامه‌هایی که به پروکسی سیستمی احترام می‌گذارند محافظت می‌کند (مرورگرها و بیشتر برنامه‌ها). برنامه‌هایی که پروکسی را نادیده می‌گیرند و UDP به‌طور مستقیم عبور می‌کنند — آب‌بندی کامل فقط با حالت TUN فراهم می‌شود. نیازمند فعال بودن اتصال مجدد خودکار است.';

  @override
  String get infoUserAgent =>
      'شیوه معرفی برنامه به پنل (هدر User-Agent). همیشه «SilentGate/version (Windows)» ارسال می‌شود.\n\nپنل Remnawave بر اساس این نام قالب اشتراک را انتخاب می‌کند. XRAY_JSON لازم است — پیکربندی آماده سرورها را می‌فرستد؛ از فهرست base64 لینک‌ها برخی تنظیمات به‌طور تقریبی بازسازی می‌شوند و انتخاب خودکار (burstObservatory) بدتر کار می‌کند.\n\nدر پنل تنظیم می‌شود: Templates ← Response Rules ← قانونی با شرط user-agent CONTAINS SilentGate و نوع پاسخ XRAY_JSON (آن را بالای قانون Fallback Base64 قرار دهید).\n\nفیلد جایگزینی فقط به‌عنوان راه‌حل موقت لازم است — اگر پنل هنوز برنامه را نمی‌شناسد، می‌توانید خود را به‌عنوان کلاینتی که می‌شناسد معرفی کنید.';

  @override
  String get infoDnsMode =>
      'چه کسی دامنه‌ها را در حالت TUN تفکیک می‌کند. «از طریق VPN» (توصیه‌شده) — پرس‌وجوها از طریق TCP وارد تونل می‌شوند و ISP شما نمی‌بیند چه سایت‌هایی باز می‌کنید. «سیستمی» — مانند ویندوز: نشت DNS ممکن است و اگر سرور UDP را عبور ندهد، اینترنت ممکن است به‌کلی قطع شود. «سفارشی» — سروری که تعیین می‌کنید، از طریق تونل.';

  @override
  String get infoDnsCustomServer =>
      'آدرس سرور DNS برای حالت «سفارشی» (مثلاً 9.9.9.9 یا 8.8.8.8). پرس‌وجوها به آن از طریق TCP از تونل عبور می‌کنند.';

  @override
  String get infoDnsHijack =>
      'گرفتن پرس‌وجوهای DNS (پورت UDP ۵۳) داخل تونل. بدون این، پرس‌وجوها از کنار قوانین می‌گذرند: نشت ممکن است و قوانین دامنه‌ای تونل تفکیکی دقت کمتری دارند.';

  @override
  String get infoDnsStrategy =>
      'کدام آدرس‌ها درخواست شوند: prefer_ipv4 (توصیه‌شده) — نخست IPv4، ipv4_only — فقط IPv4 (مشکلات IPv6 خراب را رفع می‌کند)، prefer_ipv6/ipv6_only — برای شبکه‌های IPv6.';

  @override
  String get infoSingboxLogLevel =>
      'میزان جزئیات گزارش sing-box (%APPDATA%\\SilentGate\\singbox.log). warn — حالت عادی. info/debug — اگر تونل کار نمی‌کند: گزارش علت دقیق را نشان می‌دهد. debug اندازه فایل را به‌شکل محسوسی افزایش می‌دهد.';

  @override
  String get infoSplitMode =>
      'پایه — همه چیزی که به‌صورت دستی برایش کنشی تعیین نشده به کجا می‌رود و به ورودی‌های جدید چه کنشی داده می‌شود. «همه — از طریق VPN»: به‌طور پیش‌فرض تمام ترافیک به تونل. «فقط انتخاب‌شده‌ها — از طریق VPN»: به‌طور پیش‌فرض مستقیم، فقط موارد نشان‌دار «تونل» به تونل. «انتخاب‌شده‌ها — بیرون از VPN»: برعکس، همه به تونل و موارد نشان‌دار «مستقیم» مستقیم می‌روند.';

  @override
  String get infoSplitApps =>
      'روی یک برنامه کلیک کنید — پنجره‌ای باز می‌شود که در آن کنش (تونل — از طریق VPN، مستقیم — بیرون از VPN، مسدود — بدون شبکه) و شیوه تطبیق را انتخاب می‌کنید: بر اساس نام exe (مطمئن) یا بر اساس مسیر کامل. می‌توانید از میان برنامه‌های در حال اجرا انتخاب کنید یا یک .exe مشخص کنید.';

  @override
  String get infoSplitDomains =>
      'دامنه‌ها (پسوندها). برای مثال youtube.com شامل www.youtube.com هم می‌شود. بر اساس نام موجود در اتصال TLS (SNI) کار می‌کند.';

  @override
  String get infoVerifyViaProxy =>
      'نخست کارکرد را از طریق پروکسی بررسی می‌کنیم (سرور واقعاً ۲۰۴ برمی‌گرداند) و تنها اگر سرور پاسخ داد، تأخیر را جداگانه با روش انتخاب‌شده (TCP/ICMP) می‌سنجیم.';

  @override
  String get infoProxyGet =>
      'یک درخواست GET از طریق تونل به URL آزمایشی. بررسی می‌کند که سرور واقعاً ترافیک را عبور می‌دهد و ۲۰۴ برمی‌گرداند. صادقانه‌ترین تست کارکرد؛ کمی کندتر.';

  @override
  String get infoProxyHead =>
      'مانند GET، اما فقط هدرها — سریع‌تر و کم‌ترافیک‌تر. برخی سرورها/CDNها ممکن است از HEAD پشتیبانی نکنند.';

  @override
  String get infoTcp =>
      'زمان دست‌دهی TCP به آدرس سرور. شاخصی سریع و دقیق از تأخیر، اما کارکرد تونل را ثابت نمی‌کند: یک سرور Reality حتی اگر پروکسی‌سازی مسدود باشد به TCP پاسخ می‌دهد. برای سنجش تأخیر توصیه می‌شود.';

  @override
  String get infoIcmp =>
      'پینگ سیستمی. اغلب برای Reality/CDN بی‌فایده است: ICMP ممکن است مسدود باشد یا نزدیک‌ترین گره CDN را می‌سنجد. برای عیب‌یابی شبکه نگه دارید.';

  @override
  String get infoTestUrl =>
      'URL بررسی کارکرد از طریق پروکسی. به‌طور پیش‌فرض https://www.gstatic.com/generate_204 — پاسخ خالی ۲۰۴ برمی‌گرداند که راحت و سریع است.';

  @override
  String get infoAutoConfig =>
      'از میان سرورها و گونه‌های دور زدن (fragment، fingerprint) می‌گذرد و فهرستی از مواردی می‌سازد که سرویس‌های انتخاب‌شده در آن‌ها کار می‌کنند. در اولین مورد نمی‌ایستد — شما از میان موارد یافت‌شده انتخاب می‌کنید. بررسی از طریق پروکسی انجام می‌شود؛ در این مدت VPN فعال نمی‌شود.';

  @override
  String get infoAutoConfigServices =>
      'کدام سرویس‌ها باید کار کنند تا سرور مناسب تلقی شود. بررسی در برابر صفحه‌های جایگزین ISP مقاوم است (امضای پاسخ راستی‌آزمایی می‌شود، نه فقط یک «200 OK»).';

  @override
  String get infoAutoPinFound =>
      'ترکیب‌های کارآمد یافت‌شده (سرور + گونه دور زدن) بی‌درنگ در بالای فهرست عمومی سرورها سنجاق می‌شوند تا بدون بازگشت به اینجا از آن‌ها استفاده کنید. اگر نمی‌خواهید پیکربندی خودکار ترتیب فهرست شما را تغییر دهد آن را خاموش کنید — نتایج همچنان در این صفحه دیده می‌شوند.';

  @override
  String get infoTryFragment =>
      'اگر سرور «خام» کار نکرد، گونه با قطعه‌قطعه‌سازی TLS ClientHello (دور زدن DPI) را امتحان کنید. کمی طولانی‌تر است، اما روی سرورهای محدودشده ترکیب کارآمد پیدا می‌کند.';

  @override
  String get infoAutoStrategy =>
      '«اولین کارآمد» — همه را بررسی کن و به هر مورد یافت‌شده وصل شو (شما انتخاب می‌کنید). «بهترین در بودجه» — در محدوده زمانی جستجو کن و سریع‌ترین را انتخاب کن.';

  @override
  String get infoScheme =>
      'پروتکل silentgate:// را در سیستم ثبت می‌کند (برای کاربر فعلی، بدون دسترسی مدیر). پس از آن، کلیک روی لینک silentgate://import?url=… (درون‌ریزی) یا silentgate://connect / toggle (کنترل) در مرورگر، برنامه را باز کرده و کنش را انجام می‌دهد. به‌طور پیش‌فرض فعال است.';

  @override
  String get infoAutoConnectAfterImport =>
      'بی‌درنگ پس از درون‌ریزی موفق اشتراک از طریق لینک، به اولین سرور وصل شو.';

  @override
  String get infoNetworkRecover =>
      'بازنشانی پارامترهای شبکه اگر پس از خرابی/خاموش شدن رایانه با VPN روشن، اینترنت قطع شد: winsock، پشته IP، حافظه نهان DNS، پروکسی سیستمی. نیازمند دسترسی مدیر است؛ بازنشانی winsock و پشته IP پس از راه‌اندازی مجدد اعمال می‌شود.';

  @override
  String get infoInterference =>
      'بررسی VPNهای دیگر و تداخل‌های شبکه (آداپتورهای TUN بیگانه، فرآیندهای VPN، zapret/GoodbyeDPI) که ممکن است با SilentGate تداخل کنند. می‌توانید آن‌ها را ببندید یا نادیده بگیرید.';

  @override
  String get pingInfoProxyGet =>
      'یک درخواست GET از طریق تونل به URL آزمایشی. بررسی می‌کند که سرور واقعاً ترافیک را عبور می‌دهد و ۲۰۴ برمی‌گرداند. صادقانه‌ترین تست کارکرد؛ به‌دلیل دانلود کامل پاسخ کمی کندتر است. برای بررسی کارکرد توصیه می‌شود.';

  @override
  String get pingInfoProxyHead =>
      'مانند GET، اما فقط هدرها را درخواست می‌کند — کم‌ترافیک‌تر و سریع‌تر. کارکرد تونل را بررسی می‌کند؛ برخی سرورها/CDNها ممکن است از HEAD پشتیبانی نکنند.';

  @override
  String get pingInfoTcp =>
      'سنجش زمان دست‌دهی TCP به آدرس سرور. شاخصی سریع و دقیق از تأخیر نقطه پایانی، اما کارکرد تونل را ثابت نمی‌کند: یک سرور Reality حتی اگر پروکسی‌سازی مسدود باشد به TCP پاسخ می‌دهد. برای سنجش تأخیر توصیه می‌شود.';

  @override
  String get pingInfoIcmp =>
      'پینگ سیستمی (درخواست echo). اغلب برای Reality/CDN بی‌فایده است: ICMP ممکن است مسدود باشد یا نزدیک‌ترین گره CDN را به‌جای سرور می‌سنجد. برای عیب‌یابی شبکه نگه دارید.';

  @override
  String get pingInfoTwoPhase =>
      'پس از بررسی TCP، سرورهایی که پاسخ داده‌اند علاوه بر آن با درخواستی از طریق تونل (GET/HEAD به URL آزمایشی) بررسی می‌شوند. این کار سرورهایی را که پورت را باز نگه می‌دارند اما ترافیک را پروکسی نمی‌کنند کنار می‌گذارد. تأخیر همچنان بر اساس TCP نمایش داده می‌شود.';

  @override
  String get pingInfoTunStage =>
      'تونل کامل (TUN) مرحله بعدی است. اکنون حالت «پروکسی سیستمی» در حال استفاده است. در حالت TUN تمام ترافیک (شامل UDP و برنامه‌هایی که پروکسی را نادیده می‌گیرند) از آداپتور مجازی wintun + tun2socks عبور خواهد کرد. نیازمند دسترسی مدیر است.';

  @override
  String get pingInfoTunStack =>
      'پشته شبکه TUN (sing-box). auto — به صلاحدید هسته واگذار کن (اکنون mixed). system — پشته سیستم‌عامل: بیشترین سرعت، اما با دسترسی‌ها/آنتی‌ویروس‌ها ناسازگارتر. gvisor — پشته فضای کاربر: کندتر، اما سازگارترین. mixed — TCP از طریق system و UDP از طریق gvisor (توازن). اگر TUN وصل نمی‌شود یا اتصال‌ها را قطع می‌کند — gvisor را امتحان کنید.';

  @override
  String get pingInfoAutoConfig =>
      'هنگام فعال بودن، برنامه خودش از میان سرورها و گونه‌های دور زدن (fragment، fingerprint) می‌گذرد و به اولین موردی که سرویس‌های انتخاب‌شده در آن کار می‌کنند وصل می‌شود (بررسی از طریق پروکسی، بدون فعال کردن VPN در حین جستجو).';

  @override
  String get logsTabApp => 'برنامه';

  @override
  String get logsTabTun => 'TUN (sing-box)';

  @override
  String get logsRefresh => 'بازخوانی';

  @override
  String get logsCopy => 'کپی';

  @override
  String get logsClearApp => 'پاک کردن گزارش برنامه';

  @override
  String get logsCopied => 'گزارش کپی شد';

  @override
  String get logsLoading => 'در حال بارگذاری…';

  @override
  String get logsEmpty => 'فعلاً خالی است.';

  @override
  String get logsTunEmpty => 'خالی — TUN هنوز روی این سیستم آغاز نشده است.';

  @override
  String get importScrDone => 'درون‌ریزی شد';

  @override
  String get importScrWelcome => 'به SilentGate خوش آمدید';

  @override
  String get importScrTitle => 'درون‌ریزی اشتراک';

  @override
  String get importScrSubscriptionFallback => 'اشتراک';

  @override
  String get importScrHint =>
      'یک لینک اشتراک (Remnawave)، یک دیپ‌لینک silentgate:// یا یک لینک تکی vless:// / vmess:// / trojan:// / ss:// / hysteria2:// را جای‌گذاری کنید';

  @override
  String get importScrLoading => 'در حال بارگذاری…';

  @override
  String get importScrPasteImport => 'درون‌ریزی از کلیپ‌بورد';

  @override
  String get importScrImportField => 'درون‌ریزی از فیلد';

  @override
  String get serversTitle => 'سرورها';

  @override
  String serversFound(int found, int total) {
    return 'سرورها — $found از $total یافت شد';
  }

  @override
  String get serversRefresh => 'بازخوانی اشتراک';

  @override
  String get serversPinging => 'در حال پینگ…';

  @override
  String get serversPingAll => 'پینگ همه';

  @override
  String get serversPingFound => 'پینگ موارد یافت‌شده';

  @override
  String get serversEmpty => 'فهرست سرورها خالی است. یک اشتراک درون‌ریزی کنید.';

  @override
  String get serversNothingFound => 'چیزی یافت نشد';

  @override
  String get toastCopied => 'کپی شد';

  @override
  String get toastHide => 'پنهان کردن';

  @override
  String get srvInfoTitle => 'اطلاعات سرور';

  @override
  String srvInfoProbeFailed(Object error) {
    return 'برقراری اتصال آزمایشی ناموفق بود: $error';
  }

  @override
  String get srvInfoServerAddressFailed => 'تعیین آدرس سرور ممکن نشد';

  @override
  String get srvInfoSectionExit => 'محل خروج شما';

  @override
  String get srvInfoExitHint =>
      'از روی آدرس سرور تعیین می‌شود — برای این کار تونلی بالا نمی‌آید.';

  @override
  String get srvInfoAddressLocation => 'آدرس و موقعیت سرور';

  @override
  String get srvInfoCheckAgain => 'بررسی دوباره';

  @override
  String get srvInfoSectionSpeed => 'سرعت';

  @override
  String srvInfoSpeedHint(Object size) {
    return 'کاوشگر $size دانلود می‌کند و از ترافیک اشتراک شما مصرف می‌کند. اندازه را می‌توان در تنظیمات تغییر داد.';
  }

  @override
  String get srvInfoViaServer => 'از طریق سرور';

  @override
  String get srvInfoWithoutVpn => 'بدون VPN';

  @override
  String get srvInfoMeasuring => 'در حال سنجش…';

  @override
  String get srvInfoMeasureSpeed => 'سنجش سرعت';

  @override
  String get srvInfoSectionParams => 'پارامترهای اتصال';

  @override
  String get srvInfoParamAddress => 'آدرس';

  @override
  String get srvInfoParamProtocol => 'پروتکل';

  @override
  String get srvInfoParamTransport => 'ترابری';

  @override
  String get srvInfoParamTlsFingerprint => 'اثر انگشت TLS';

  @override
  String get srvInfoParamType => 'نوع';

  @override
  String get srvInfoPanelAutoProfile => 'پروفایل انتخاب خودکار از پنل';

  @override
  String get srvInfoCouldNotDetermine => 'تعیین نشد';

  @override
  String get srvInfoCopy => 'کپی';

  @override
  String get editorJsonTitle => 'پیکربندی JSON';

  @override
  String get editorCopy => 'کپی';

  @override
  String get editorClose => 'بستن';

  @override
  String get editorTitle => 'ویرایش سرور';

  @override
  String get editorFieldName => 'نام';

  @override
  String get editorFieldAddress => 'آدرس';

  @override
  String get editorFieldPort => 'پورت';

  @override
  String get editorFieldUuidPassword => 'UUID / رمز عبور';

  @override
  String get editorFieldObfs => 'مبهم‌سازی (معمولاً salamander)';

  @override
  String get editorFieldObfsPassword => 'رمز عبور مبهم‌سازی';

  @override
  String get editorFieldPortHopping => 'پرش پورت (مثلاً 20000-21000)';

  @override
  String get editorAllowSelfSigned => 'اجازه گواهی خود‌امضا';

  @override
  String get editorAllowSelfSignedSub =>
      'فقط اگر سرور این‌گونه پیکربندی شده باشد لازم است';

  @override
  String get editorTransport => 'ترابری';

  @override
  String get editorSecurity => 'امنیت';

  @override
  String get editorNone => '(هیچ‌کدام)';

  @override
  String get editorCancel => 'لغو';

  @override
  String get editorSave => 'ذخیره';

  @override
  String jsonProfileServers(int count, String burst) {
    return '$count سرور$burst';
  }

  @override
  String get jsonCompositionUnknown => 'ترکیب نامشخص';

  @override
  String get jsonYourSavedOverride => 'JSON ذخیره‌شده شما (override)';

  @override
  String jsonPanelProfileApplied(Object summary) {
    return 'پروفایل انتخاب خودکار از پنل: $summary — به‌طور کامل اعمال شد';
  }

  @override
  String get jsonPanelConfig => 'پیکربندی از پنل (XRAY_JSON)';

  @override
  String get jsonBuiltFromShareLink =>
      'از روی لینک اشتراک‌گذاری ساخته شد — پنل JSON نفرستاد. اشتراک را به‌روزرسانی کنید؛ اگر کمکی نکرد، قانون Response Rules را در پنل بررسی کنید.';

  @override
  String get jsonInvalidJson => 'JSON نامعتبر';

  @override
  String get jsonSaved => 'ذخیره شد';

  @override
  String get jsonTitle => 'پیکربندی JSON';

  @override
  String get jsonFieldEditor => 'ویرایشگر فیلد';

  @override
  String get jsonCopy => 'کپی';

  @override
  String get jsonClose => 'بستن';

  @override
  String get jsonSave => 'ذخیره';

  @override
  String get srvTileEdit => 'ویرایش';

  @override
  String get srvTileNotice => 'اعلان';

  @override
  String get srvTileRefresh => 'بازخوانی';

  @override
  String get srvTileSubscriptionUpdated => 'اشتراک به‌روزرسانی شد';

  @override
  String get srvTileCopy => 'کپی';

  @override
  String get srvTileInfo => 'اطلاعات سرور';

  @override
  String get srvTilePing => 'پینگ';

  @override
  String get srvTileUnpin => 'برداشتن سنجاق';

  @override
  String get srvTilePin => 'سنجاق کردن';

  @override
  String get srvTileJsonConfig => 'پیکربندی JSON';

  @override
  String get srvTileSmart => 'تنظیم هوشمند پارامترها';

  @override
  String get srvTileDelete => 'حذف';

  @override
  String get srvTileServerDeleted => 'سرور حذف شد';

  @override
  String get srvTileSaved => 'ذخیره شد';

  @override
  String get pingNa => 'n/a';

  @override
  String get pingNaTooltip => 'پاسخ TCP نداد — سرور در دسترس نیست (مرده)';

  @override
  String get pingTimeout => 'زمان تمام شد';

  @override
  String get pingTimeoutTooltip =>
      'کاوش TCP در مهلت مقرر تکمیل نشد — سرور در دسترس نیست';

  @override
  String pingMs(Object ms) {
    return '$ms میلی‌ثانیه';
  }

  @override
  String get pingNoProxy => 'بدون پروکسی';

  @override
  String get pingNoProxyTooltip =>
      'از طریق TCP پاسخ می‌دهد (تأخیر نمایش داده شد)، اما بررسی تونل (GET/HEAD) ناموفق بود — ترافیک عبور نمی‌کند';

  @override
  String get pingOk => 'ok';

  @override
  String get pingOkTooltip =>
      'تأخیر TCP تا سرور. سرور کار می‌کند: به TCP پاسخ داد و بررسی تونل (GET/HEAD) را پشت سر گذاشت';

  @override
  String get searchHint => 'جستجو بر اساس نام، کشور، آدرس…';

  @override
  String get searchReset => 'پاک کردن';

  @override
  String get splitTitle => 'تونل تفکیکی';

  @override
  String get splitTunOnlyBanner =>
      'فقط در حالت TUN کار می‌کند. در حالت «پروکسی سیستمی» برنامه‌ها خودشان تصمیم می‌گیرند از پروکسی استفاده کنند یا نه — نمی‌توان آن‌ها را مجبور کرد.';

  @override
  String get splitProxyOnlyBanner =>
      'در حالت «فقط پروکسی» چیزی برای رهگیری نیست: قوانین برای هیچ برنامه‌ای در این رایانه اعمال نمی‌شوند. فهرست «مسدود» فقط روی درگاه‌های محلی API اعمال می‌شود، و فقط اگر کلید «اعمال قوانین تونل تفکیکی» در بخش «گرفتن ترافیک» روشن باشد. بقیهٔ قوانین را می‌توان اینجا از پیش آماده کرد: با تغییر به TUN به کار می‌افتند.';

  @override
  String get splitEnableTun => 'فعال کردن TUN';

  @override
  String get splitModeHeader => 'حالت';

  @override
  String get splitAppsHeader => 'برنامه‌ها';

  @override
  String get splitAppsHint =>
      'روی یک برنامه بزنید تا کنش آن (تونل / مستقیم / مسدود) و شیوه تطبیق را تعیین کنید. کادر سمت راست قانون را فعال/غیرفعال می‌کند.';

  @override
  String get splitByName => 'بر اساس نام';

  @override
  String get splitByPath => 'بر اساس مسیر';

  @override
  String get splitRuleDisabled => 'غیرفعال — قانون اعمال نمی‌شود';

  @override
  String get splitRemove => 'حذف';

  @override
  String get splitFromRunning => 'از میان در حال اجرا';

  @override
  String get splitPickInstalled => 'انتخاب برنامه';

  @override
  String get splitInstalledApps => 'برنامه‌های نصب‌شده';

  @override
  String get splitPickExe => 'انتخاب .exe';

  @override
  String get splitSitesHeader => 'سایت‌ها (دامنه‌ها)';

  @override
  String get splitSitesHint =>
      'روی یک سایت بزنید تا کنشی انتخاب کنید (تونل / مستقیم / مسدود). یک دامنه زیردامنه‌هایش را هم پوشش می‌دهد؛ زیردامنه‌ها به‌صورت درختی گروه‌بندی می‌شوند. می‌توانید یک پورت مشخص کنید.';

  @override
  String splitOnlyPort(Object port) {
    return 'فقط پورت $port';
  }

  @override
  String get splitProgramsFileType => 'برنامه‌ها';

  @override
  String get splitRunningApps => 'برنامه‌های در حال اجرا';

  @override
  String get splitSearchByName => 'جستجو بر اساس نام';

  @override
  String get splitNothingFound => 'چیزی یافت نشد';

  @override
  String get splitClose => 'بستن';

  @override
  String get splitPortRange => 'پورت ۱–۶۵۵۳۵';

  @override
  String get splitAction => 'کنش';

  @override
  String get splitPortOptional => 'پورت (اختیاری)';

  @override
  String get splitAnyPort => 'هر';

  @override
  String get splitPortHelper =>
      'خالی = هر پورت. در غیر این صورت قانون فقط برای این پورت اعمال می‌شود';

  @override
  String get splitMatching => 'تطبیق';

  @override
  String get splitByNameSubtitle => 'نام exe، صرف‌نظر از محل قرارگیری (مطمئن)';

  @override
  String get splitByPathSubtitle => 'مسیر کامل به exe (تطابق دقیق)';

  @override
  String get splitDone => 'انجام شد';

  @override
  String get splitEnterDomain => 'یک دامنه وارد کنید';

  @override
  String get splitAddSite => 'افزودن سایت';

  @override
  String get splitPort => 'پورت';

  @override
  String get splitAdd => 'افزودن';

  @override
  String get routeBlock => 'مسدود';

  @override
  String get routeBlocked => 'مسدود شد';

  @override
  String get routeYourPc => 'رایانه شما';

  @override
  String get routeTunnel => 'تونل';

  @override
  String get routeViaVpn => 'از طریق VPN';

  @override
  String get routeVpn => 'VPN';

  @override
  String get routeInternet => 'اینترنت';

  @override
  String get routeRest => 'بقیه موارد';

  @override
  String get routeDirectly => 'مستقیم';

  @override
  String get routeDirectPlusRest => 'مستقیم + بقیه';

  @override
  String get routeDirect => 'مستقیم';

  @override
  String get routeEmptyList => 'فهرست خالی است';

  @override
  String get trayShow => 'نمایش';

  @override
  String get trayToggle => 'اتصال / قطع';

  @override
  String get trayQuit => 'خروج';

  @override
  String get trayMinimizeTitle => 'کوچک کردن به تری';

  @override
  String get trayMinimizeBody => 'برنامه در تری به کارش ادامه می‌دهد.';

  @override
  String get trayDontAsk => 'دیگر نپرس';

  @override
  String get trayMinimizeOk => 'کوچک کن';

  @override
  String get trayVpnTitle => 'VPN متصل است';

  @override
  String get trayVpnBody => 'VPN قطع و از برنامه خارج شود؟';

  @override
  String get trayStay => 'ماندن';

  @override
  String get trayQuitVpn => 'قطع و خروج';

  @override
  String get tunTaskDone => 'انجام شد: TUN بدون درخواست UAC آغاز می‌شود';

  @override
  String get tunTaskFailed =>
      'ساخت وظیفه ناموفق بود (UAC رد شد یا با سیاست مسدود شد)';

  @override
  String get tunLogTitle => 'گزارش TUN (sing-box)';

  @override
  String get tunLogEmpty => 'گزارش خالی است — تونل هنوز آغاز نشده است.';

  @override
  String get tunCopy => 'کپی';

  @override
  String get tunClose => 'بستن';

  @override
  String get tunTitle => 'TUN و مسیریابی';

  @override
  String get tunSectionPrivilege => 'دسترسی مدیر';

  @override
  String get tunChecking => 'در حال بررسی…';

  @override
  String get tunNoUacConfigured => 'آغاز بدون UAC تنظیم شده است';

  @override
  String get tunUacEachConnect => 'UAC در هر اتصال درخواست خواهد شد';

  @override
  String get tunTaskSubtitle =>
      'یک وظیفه در زمان‌بند وظایف ویندوز با بالاترین سطح دسترسی (یک‌بار ساخته می‌شود).';

  @override
  String get tunRecreateTask => 'ساخت دوباره وظیفه';

  @override
  String get tunSetupOneUac => 'تنظیم (یک UAC)';

  @override
  String get tunRemoveTask => 'حذف وظیفه';

  @override
  String get tunSectionAdapter => 'آداپتور';

  @override
  String get tunStack => 'استک TUN';

  @override
  String get tunSectionRouting => 'مسیریابی';

  @override
  String get tunStrictRoute => 'مسیریابی سخت‌گیرانه (strict_route)';

  @override
  String get tunIpv6 => 'IPv6 در تونل';

  @override
  String get tunEndpointNat => 'Endpoint-independent NAT (UDP، بازی‌ها)';

  @override
  String get tunLanBypass => 'عبور شبکه محلی از کنار VPN';

  @override
  String get tunDnsServer => 'سرور DNS';

  @override
  String get tunDnsHijack => 'گرفتن DNS (پورت ۵۳)';

  @override
  String get tunResolveStrategy => 'راهبرد تفکیک نام';

  @override
  String get tunSectionDiagnostics => 'عیب‌یابی';

  @override
  String get tunSingboxLogLevel => 'سطح گزارش sing-box';

  @override
  String get tunShowLog => 'نمایش گزارش TUN';

  @override
  String get tunDnsVpn => 'از طریق VPN (توصیه‌شده)';

  @override
  String get tunDnsSystem => 'سیستمی';

  @override
  String get tunDnsCustom => 'سرور سفارشی';

  @override
  String get tunDnsVpnHint =>
      'پرس‌وجوها از طریق TCP وارد تونل می‌شوند — بدون نشت';

  @override
  String get tunDnsSystemHint => 'مانند ویندوز: نشت DNS ممکن است';

  @override
  String get tunDnsCustomHint => 'سرور مشخص‌شده، آن هم از طریق تونل';

  @override
  String get tunExcludeSubnets => 'زیرشبکه‌های عبورکننده از کنار VPN';

  @override
  String get tunAdd => 'افزودن';

  @override
  String get urlGroupImport => 'درون‌ریزی';

  @override
  String get urlGroupControl => 'کنترل';

  @override
  String get urlHintSubUrl => 'URL اشتراک';

  @override
  String get urlHintServerLink => 'لینک سرور';

  @override
  String get urlDescImportSub => 'درون‌ریزی یک اشتراک';

  @override
  String get urlDescImportServer =>
      'افزودن یک سرور تکی (vless / trojan / ss / hysteria2 …)';

  @override
  String get urlDescConnect => 'اتصال VPN';

  @override
  String get urlDescDisconnect => 'قطع VPN';

  @override
  String get urlDescToggle => 'تغییر وضعیت VPN';

  @override
  String get urlDescUpdate => 'به‌روزرسانی اشتراک فعال';

  @override
  String get urlSupportedImport =>
      'هنگام درون‌ریزی، برنامه این‌ها را می‌فهمد: یک URL اشتراک (http/https)، و سرورهای تکی vless:// / vmess:// / trojan:// / ss:// / hysteria2:// (hy2://).';

  @override
  String get reportTitle => 'SilentGate — گزارش پشتیبانی';

  @override
  String get reportDescribeHere =>
      '>>> مشکل را اینجا شرح دهید (پر کنید و فایل را ذخیره کنید): <<<';

  @override
  String get reportWhatDid => 'چه کاری کردید:';

  @override
  String get reportWhatExpected => 'چه انتظاری داشتید:';

  @override
  String get reportWhatHappened => 'چه اتفاقی افتاد:';

  @override
  String get reportWhenStarted => 'چه زمانی شروع شد:';

  @override
  String get reportTechNoticeLine1 =>
      'در ادامه اطلاعات فنی آمده است. پیش از ارسال آن را مرور کنید؛';

  @override
  String get reportTechNoticeLine2 =>
      'هیچ رمز عبور یا توکن اشتراکی اینجا نیست و URL اشتراک پنهان است.';

  @override
  String get noRealIpTitle => 'هرگز از IP واقعی من استفاده نکن';

  @override
  String get noRealIpSub =>
      'حتی با روشن بودن VPN، همه ترافیک «مستقیم» از VPN عبور می‌کند (سایت‌های RU هم). شبکه محلی مستقیم می‌ماند.';

  @override
  String get flagAuto => 'خودکار';

  @override
  String get autoUpdateIntervalLabel => 'فاصله به‌روزرسانی، ساعت';

  @override
  String get autoUpdatePreferSub => 'استفاده از فاصله از اشتراک';

  @override
  String get pingLegendInfo =>
      'رنگ نشان پینگ: سبز/زرد/نارنجی — سرور کار می‌کند (TCP + بررسی از تونل). خاکستری — به TCP پاسخ می‌دهد اما ترافیک را پروکسی نمی‌کند (پورت معمول Reality). قرمز «n/a» — بدون پاسخ، حذف‌شده. پینگ همیشه به‌طور مستقیم (خارج از VPN) اندازه‌گیری می‌شود.';

  @override
  String get pingUntestedHint =>
      'هنوز آزمایش نشده. در موبایل، Hysteria2 و نمایه‌های «خودکار» فقط هنگام اتصال سنجیده می‌شوند.';

  @override
  String get panelTunnelMarker => 'تونل تقسیم‌شده مخصوص خود';

  @override
  String panelInfoServers(Object n) {
    return 'سرورها در پروفایل: $n (بهترین انتخاب می‌شود)';
  }

  @override
  String get panelInfoDirect =>
      'بخشی از ترافیک (مثلاً سایت‌های محلی) مستقیم و خارج از VPN می‌رود';

  @override
  String get panelInfoBlock => 'بخشی از ترافیک مسدود می‌شود (تبلیغات/تورنت)';

  @override
  String get serviceChecksTitle => 'بررسی سرویس‌ها';

  @override
  String get serviceChecksInfo =>
      'شش سرویس پرکاربرد خودکار بررسی می‌شوند: نخست هنگام اجرای برنامه و خاموش بودن VPN، سپس بلافاصله پس از اتصال. دو نقطه «پیش ← پس» را نشان می‌دهند تا ببینید VPN واقعاً چه چیزی را تغییر داده است. برای بررسی دوباره ضربه بزنید. سبز: باز می‌شود، نارنجی: مسدودی کشوری، قرمز: در دسترس نیست.';

  @override
  String get serviceStatusOk => 'کار می‌کند';

  @override
  String get serviceStatusGeo => 'باز می‌شود اما در کشور خروجی مسدود است';

  @override
  String get serviceStatusFail => 'باز نمی‌شود';

  @override
  String get serviceStatusChecking => 'در حال بررسی…';

  @override
  String get serviceStatusTap => 'برای بررسی بزنید';

  @override
  String serviceLatencyMs(Object ms) {
    return '$ms میلی‌ثانیه';
  }

  @override
  String get homeTunAutotuneProgress => 'در حال تنظیم پارامترهای TUN…';

  @override
  String get homeTunAutotuneDone => 'پارامترهای TUN تنظیم شد';

  @override
  String get homeTunAutotuneFailed => 'تنظیم پارامترهای TUN ممکن نشد';

  @override
  String get hy2NoteTitle => 'سرورهای Hysteria2';

  @override
  String get hy2NoteBody =>
      'سرورهای Hysteria2 فقط در قالب XRAY_JSON می‌آیند — SilentGate دقیقاً همان را درخواست می‌کند و sing-box آن‌ها را خودکار بالا می‌آورد. اگر Hysteria2 در فهرست دیده نشد: (برای مالک پنل Remnawave) اینباند‌های hysteria را فعال و به اشتراک اختصاص دهید. توجه: Remnawave پیش از 2.8.0 فقط در XRAY_JSON خدمت Hysteria2 را می‌دهد — در base64/CLASH/SINGBOX نیست، بنابراین قانون Response Rules → XRAY_JSON بالا الزامی است.';

  @override
  String get enumStatusDisconnected => 'قطع شده';

  @override
  String get enumStatusConnecting => 'در حال اتصال…';

  @override
  String get enumStatusConnected => 'متصل';

  @override
  String get enumStatusDisconnecting => 'در حال قطع اتصال…';

  @override
  String get enumStatusError => 'خطا';

  @override
  String get enumVariantPlain => 'عادی';

  @override
  String get tagAutoSelect => 'خودکار';

  @override
  String get tagPanel => 'پنل';

  @override
  String get tagPortHopping => 'پرش پورت';

  @override
  String syncServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سرور',
      one: '$count سرور',
    );
    return '$_temp0';
  }

  @override
  String get syncNoChanges => 'بدون تغییر';

  @override
  String get errInvalidJson => 'JSON نامعتبر';

  @override
  String get errPickServerFirst => 'ابتدا یک سرور انتخاب کنید';

  @override
  String get errImportSubscriptionFirst => 'ابتدا یک اشتراک وارد کنید';

  @override
  String get speedSizeFull => '۲۰ مگابایت';

  @override
  String get speedSizeLight => '۵ مگابایت';

  @override
  String speedMbPerSec(String value) {
    return '$value مگابایت/ثانیه';
  }

  @override
  String speedKbPerSec(String value) {
    return '$value کیلوبایت/ثانیه';
  }

  @override
  String portBusyTitle(int port, String by) {
    return 'پورت $port از قبل توسط $by اشغال شده است.';
  }

  @override
  String get srvTileMenu => 'عملیات سرور';

  @override
  String get supportCopyReport => 'کپی گزارش';

  @override
  String get supportReportCopied =>
      'گزارش کپی شد — آن را در گفتگوی پشتیبانی بچسبانید';

  @override
  String subBarUsedOnly(String used) {
    return 'مصرف‌شده $used';
  }

  @override
  String get subBarUnlimitedTraffic => 'ترافیک نامحدود';

  @override
  String get supportDescribeLabel => 'مشکل را شرح دهید';

  @override
  String get supportDescribeHint =>
      'چه کردید، چه انتظاری داشتید، چه شد و از کی شروع شد';

  @override
  String get supportDescribeRequired =>
      'مشکل را شرح دهید — گزارش بدون شرح بی‌فایده است';

  @override
  String get supportNoScreenshots =>
      'تصاویر صفحه را اینجا نچسبانید — آن‌ها را در پیامی جداگانه در گفتگوی تلگرام بفرستید.';

  @override
  String get supportDescriptionSection => 'شرح کاربر';

  @override
  String get splitAllowRealIp => 'اجازهٔ IP واقعی برای این قانون';

  @override
  String get splitAllowRealIpOn =>
      'روشن: این استثناست و ترافیک با نشانی واقعی شما بیرون می‌رود';

  @override
  String get splitAllowRealIpOff =>
      'خاموش: قانون از راه VPN می‌رود — حفاظت بالاتر از همهٔ قوانین است';

  @override
  String get splitRealIpExposed => 'IP واقعی';

  @override
  String get splitRealIpProtected => 'از طریق VPN';

  @override
  String get vpnActiveBadge => 'VPN فعال است';

  @override
  String get splitCopyDomain => 'کپی نشانی';

  @override
  String get splitCopyPath => 'کپی مسیر';

  @override
  String get homeServerInfo => 'اطلاعات سرور';

  @override
  String get serverInfoVerifyInBrowser => 'بررسی در مرورگر';

  @override
  String get tunDnsForAll => 'DNS همه برنامه‌ها از طریق VPN';

  @override
  String get infoDnsForAll =>
      'فقط در حالت «فقط انتخاب‌شده‌ها». ⚠️ پس از اتصال مجدد اعمال می‌شود.';

  @override
  String get homeSettingsNeedReconnect =>
      'تنظیم تغییر کرد — برای اعمال دوباره وصل شوید';

  @override
  String blockPageWindowTitle(String app) {
    return 'مسدود شده — $app';
  }

  @override
  String get blockPageHeading => 'سایت مسدود است';

  @override
  String blockPageBody(String host, String app) {
    return 'نشانی $host با قانون تونل تفکیکی در $app مسدود شده است.';
  }

  @override
  String get blockPageHint =>
      'می‌توانید قانون را تغییر دهید: تنظیمات ← تونل تفکیکی ← سایت‌ها.';

  @override
  String get blockPageNote =>
      'این صفحه از خود برنامه است و خطای شبکه نیست. سایت باز نمی‌شود چون خودتان آن را به فهرست مسدودسازی افزوده‌اید.';

  @override
  String get settingsBlockPage => 'صفحهٔ اطلاع‌رسانی مسدودسازی';

  @override
  String get settingsBlockPageSub =>
      'به‌جای خطای اتصال، صفحه‌ای توضیح می‌دهد کدام قانون سایت را بسته است. فقط برای http کار می‌کند: صفحهٔ https را بدون نصب گواهی ریشهٔ خودمان در سیستم نمی‌توان جایگزین کرد، و آن گواهی امکان خواندن تمام ترافیک رمزگذاری‌شدهٔ شما را می‌دهد.';

  @override
  String get trayCloseFully => 'بستن کامل';

  @override
  String errorVpnConflictApp(String app) {
    return 'به نظر می‌رسد $app مزاحم است: تونل VPN خودش برپاست. دو تونل هم‌زمان بر سر مسیر پیش‌فرض رقابت می‌کنند.';
  }

  @override
  String errorCloseApp(String app) {
    return 'بستن $app';
  }

  @override
  String toastAppClosed(String app) {
    return '$app بسته شد';
  }

  @override
  String toastAppCloseFailed(String app) {
    return 'بستن $app ممکن نشد — دستی ببندید';
  }

  @override
  String get tunBlockQuic => 'مسدودسازی QUIC (HTTP/3)';

  @override
  String get infoBlockQuic =>
      'قواعد سایت‌ها بر پایهٔ نام کار می‌کنند و برنامه نام را فقط در TLS معمولی می‌بیند. مرورگری که به HTTP/3 می‌رود نامی نشان نمی‌دهد و قاعدهٔ دامنه بی‌صدا بی‌اثر می‌ماند. مسدودسازی مرورگر را به اتصال عادی برمی‌گرداند که نام در آن دیده می‌شود. سایت‌ها همچنان کار می‌کنند: HTTP/3 برایشان اختیاری است، هرچند ویدیو ممکن است کمی کندتر بارگذاری شود.';

  @override
  String get tunBlockEncryptedDns => 'مسدودسازی DNS رمزگذاری‌شده (DoH/DoT)';

  @override
  String get infoBlockEncryptedDns =>
      'مرورگرها و ویندوز می‌توانند نشانی‌ها را از راه HTTPS بگیرند و از سد ما بگذرند؛ آنگاه قواعد «مستقیم» و «مسدود» در سطح DNS اصلاً کار نمی‌کنند. ⚠️ اگر در مرورگر ارائه‌دهندهٔ ثابتی برای DNS رمزگذاری‌شده تعیین شده باشد، به DNS معمولی بازنمی‌گردد و فقط سایت‌ها را باز نمی‌کند. فهرست ارائه‌دهندگان شناخته‌شده ذاتاً ناقص است.';

  @override
  String get autoUseSpeed => 'در نظر گرفتن سرعت';

  @override
  String get infoAutoUseSpeed =>
      'پس از غربال بر پایهٔ سرویس‌ها و تأخیر، سه نامزد برتر با دانلود سنجیده می‌شوند و سریع‌ترینِ واقعی نخست می‌آید. سرعت با پهنای باند خودِ شما سنجیده می‌شود: سروری که تقریباً همهٔ آن را می‌دهد دیگر با مگابیت داوری نمی‌شود و تأخیر تعیین‌کننده است. ⚠️ از ترافیک اشتراک مصرف می‌کند: ۵ مگابایت برای پهنای باند شما و ۵ مگابایت برای هر نامزد، حدود ۲۰ مگابایت در هر اجرا.';

  @override
  String get autoSpeedOwn => 'سنجش سرعت خودتان…';

  @override
  String autoSpeedServer(String server, int index, int total) {
    return 'سنجش سرعت: $server ($index از $total)';
  }

  @override
  String autoSpeedShare(int percent) {
    return '$percent٪ پهنای باند شما';
  }

  @override
  String get conflictDialogTitle => 'VPN دیگری شناسایی شد';

  @override
  String conflictDialogBody(String app) {
    return 'به نظر می‌رسد $app با تونل خودش در حال اجراست. دو تونل هم‌زمان بر سر مسیر پیش‌فرض رقابت می‌کنند و ممکن است اتصال برقرار نشود یا بدون دسترسی به شبکه بالا بیاید.';
  }

  @override
  String get conflictCloseAndConnect => 'بستن و اتصال';

  @override
  String get conflictConnectAnyway => 'به‌هرحال متصل شو';

  @override
  String get serviceChecksLegendBefore => 'بدون VPN بررسی شد';

  @override
  String get serviceChecksLegendAfter => 'چپ — بدون VPN، راست — از راه VPN';

  @override
  String get serviceChecksBefore => 'بدون VPN';

  @override
  String get serviceChecksAfter => 'از راه VPN';

  @override
  String get serviceChecksNoBaseline => 'بدون VPN بررسی نشد';

  @override
  String autoSpeedValue(String value) {
    return '$value مگابیت بر ثانیه';
  }

  @override
  String get splitShowBlockPage => 'نمایش صفحهٔ مسدودسازی';

  @override
  String get splitBlockPageNeedsVpn =>
      'صفحهٔ مسدودسازی فقط با VPN روشن کار می‌کند';

  @override
  String get srvInfoNeedsConnection =>
      'اندازه‌گیری از راه سرور در این پلتفرم فقط با VPN روشن ممکن است';

  @override
  String get serviceYoutubeThrottleNote =>
      '⚠️ این بررسی کندسازی YouTube را نمی‌بیند: سرویس‌دهنده عادی پاسخ می‌دهد اما پهنای باند ویدیو را محدود می‌کند. سبز یعنی «سرویس در دسترس است»، نه «ویدیو پخش می‌شود».';

  @override
  String get urlSchemeConnectServer => 'silentgate://connect?server=<نام سرور>';

  @override
  String get urlDescConnectServer =>
      'اتصال به سرور مشخص. نام همان است که در فهرست دیده می‌شود و اشتراک می‌فرستد، مثلاً «لهستان ۱.۵». ایموجی پرچم و بزرگی حروف مهم نیست. اگر تطابق دقیق نبود جست‌وجو انجام می‌شود: بر پایهٔ کشور، نشانی یا پروتکل. با toggle هم کار می‌کند.';

  @override
  String get splitSelectAllFound => 'انتخاب همهٔ یافته‌ها';

  @override
  String splitAddSelected(int count) {
    return 'افزودن ($count)';
  }

  @override
  String get splitQuicNote =>
      'تا زمانی که دست‌کم یک قانون سایت وجود دارد، برنامه HTTP/3 (QUIC) را برای همهٔ ترافیک خاموش می‌کند. وگرنه مرورگر به HTTP/3 می‌رود، نام سایت را نمی‌گذارد و قانون بی‌صدا کار نمی‌کند. سایت‌ها خراب نمی‌شوند: به TLS معمولی برمی‌گردند، فقط اندکی کندتر.';

  @override
  String get splitNoRealIpBanner =>
      '«هرگز با IP واقعی من» روشن است: قوانین «مستقیم» بدون تیک از راه VPN می‌روند';

  @override
  String get settingsNoRealIpAffects =>
      'بر قوانین «مستقیم» اثر دارد: بدون تیک «اجازهٔ IP واقعی» از راه VPN می‌روند';

  @override
  String get splitAppOverrideSites => 'بر قوانین سایت اولویت دارد';

  @override
  String get splitAppOverrideSitesSub =>
      'همهٔ ترافیک برنامه از این قانون پیروی می‌کند، حتی اگر قانون سایتی خلافش بگوید';

  @override
  String get settingsMyRulesOverridePanel =>
      'قوانین من مهم‌تر از قوانین پنل است';

  @override
  String get settingsMyRulesOverridePanelSub =>
      'پنل مسیریابی خودش را می‌فرستد، معمولاً «سایت‌های محلی بیرون از VPN». پس از قوانین شما اعمال می‌شود، پس سایتی که «تونل» زده‌اید ممکن است مستقیم و با IP واقعی بیرون برود. روشن: تونل یعنی تونل. بها: سایت‌های محلی راه دورتر می‌روند و کندتر می‌شوند.';

  @override
  String get commonOpen => 'باز کردن';

  @override
  String get tunRouteOnlySubnets => 'فقط این زیرشبکه‌ها به تونل';

  @override
  String get infoTunRouteOnlyCidrs =>
      'تنها راه در ویندوز برای اینکه بخشی از ترافیک واقعاً مستقل از کلاینت VPN شود.\n\nبه‌طور معمول تونل مسیر پیش‌فرض را می‌گیرد و همهٔ ترافیک رایانه وارد آن می‌شود: نشان «مستقیم» همان داخل هسته بررسی می‌شود، و هسته بسته را می‌گیرد و از طرف خودش دوباره بیرون می‌فرستد. چنین ترافیکی دقیقاً تا وقتی زنده است که هسته زنده باشد، و همراه آن معلق می‌ماند.\n\nاگر این فهرست خالی نباشد، مسیر پیش‌فرض به تونل داده نمی‌شود: تونل فقط زیرشبکه‌های فهرست‌شده را برمی‌دارد و بقیه را سیستم از آداپتور معمولی می‌فرستد — کلاینت این ترافیک را اصلاً نمی‌بیند.\n\nبها: این تفکیک بر پایهٔ آدرس است، در حالی که قوانین برنامه‌ها و سایت‌ها بر پایهٔ نام کار می‌کنند. سایتی که آدرسش در فهرست نباشد، با هیچ قانونی به چشم هسته نمی‌آید. برای رفتار معمول تونل، اینجا را خالی بگذارید.';

  @override
  String get tunRouteOnlyWarning =>
      'تونل فقط زیرشبکه‌های فهرست‌شده را برمی‌دارد. قوانین برنامه‌ها و سایت‌ها فقط داخل همین‌ها کار می‌کنند: آنچه وارد تونل نشود به هسته نشان داده نمی‌شود — چنین سایتی را نه می‌توان مسدود کرد و نه به مسیر دیگری برد.';

  @override
  String get tunAlsoSystemProxy => 'پروکسی سیستمی همراه تونل';

  @override
  String get infoTunAlsoSystemProxy =>
      'حالت ترکیبی: تونل و پروکسی سیستمی هم‌زمان کار می‌کنند.\n\nبرنامه‌هایی که به پروکسی سیستمی احترام می‌گذارند (مرورگرها، تلگرام) از راه کوتاه یک‌راست به پورت محلی می‌روند، از پشتهٔ فضای کاربرِ تونل رد می‌شوند و به‌جای آدرس خام، نام دامنه را به هسته می‌دهند — قوانین سایت برایشان دقیق‌تر می‌شود و دیگر به استخراج نام از اتصال TLS وابسته نیست.\n\nبا این حال از کلاینت مستقل نمی‌شوند: باز هم از همان فرآیند عبور می‌کنند.';

  @override
  String get tunMixedModeWarning =>
      'اتصالی که از راه پروکسی سیستمی می‌آید فرآیند صاحبی ندارد — برای هسته یک اتصال محلی است. به همین دلیل قوانین برنامه‌ها برای چنین برنامه‌هایی اعمال نمی‌شوند. قوانین سایت کار می‌کنند، و حتی دقیق‌تر از حالت عادی.';

  @override
  String get tunWatchdog => 'نگهبان هستهٔ معلق';

  @override
  String get infoTunWatchdog =>
      'هستهٔ تونل چند ثانیه می‌تواند پاسخ ندهد، پیش از آنکه معلق به‌شمار آید و تونل پایین آورده شود.\n\nاگر هسته از کار بیفتد، خودِ ویندوز پس از آن پاک‌سازی می‌کند — آداپتور، مسیرها و قوانین فایروال برداشته می‌شوند و شبکه برمی‌گردد. اگر هسته معلق شود، هیچ چیزی برداشته نمی‌شود: آداپتور می‌ماند و همهٔ ترافیک رایانه، از جمله ترافیک نشان‌دار «مستقیم»، را می‌بلعد. از بیرون این یعنی «اینترنت به‌کلی قطع شد»، و خودبه‌خود هم برطرف نمی‌شود.\n\nنگهبان تنها پس از نخستین پاسخ موفق هسته مسلح می‌شود: وگرنه هر جا که پورت سرویسی بالا نمی‌آمد، اتصال را از بین می‌برد. ۰ یعنی بدون نظارت. کمینه ۱۰ ثانیه.';

  @override
  String get tunWatchdogOff => 'خاموش: معلق شدن تونل تشخیص داده نمی‌شود';

  @override
  String tunWatchdogSubtitle(int seconds) {
    return 'اگر هسته بیش از $seconds ثانیه پاسخ ندهد، تونل پایین آورده شود';
  }

  @override
  String get tunDnsForAllWarning =>
      'تفکیک نام برای کل رایانه از تونل عبور می‌کند. اگر تونل از کار بیفتد، نام‌ها حتی برای برنامه‌هایی که مستقیم می‌روند و به VPN نیازی ندارند هم تفکیک نمی‌شوند — از بیرون مثل قطع کامل اینترنت به نظر می‌رسد.';

  @override
  String get tunCidrInvalid =>
      'آدرس همراه با پیشوند لازم است، مثلاً 10.8.0.0/24';

  @override
  String get geoTitle => 'داده‌های جغرافیایی مسیریابی';

  @override
  String get geoMissing =>
      'دانلود نشده — قوانین کشور و دسته‌بندی اعمال نمی‌شوند';

  @override
  String geoPresent(String size, String date) {
    return '$size، به‌روزشده در $date';
  }

  @override
  String get geoDownload => 'دانلود';

  @override
  String get geoUpdate => 'به‌روزرسانی';

  @override
  String geoDownloading(String file) {
    return 'در حال دانلود $file…';
  }

  @override
  String get geoDone => 'داده‌های جغرافیایی به‌روزرسانی شد';

  @override
  String get geoWhy =>
      'فایل‌های geoip.dat و geosite.dat فهرست آدرس‌ها بر اساس کشور و دامنه‌ها بر اساس دسته‌بندی هستند. هسته با کمک آن‌ها قوانینی مانند geoip:ru و geosite:category-ads را که پنل اشتراک تعیین می‌کند تشخیص می‌دهد. بدون این فایل‌ها چنین قوانینی از پیکربندی حذف می‌شوند.';

  @override
  String geoFileOk(String size, String date) {
    return '$size، به‌روزشده در $date';
  }

  @override
  String get geoFileMissing => 'فایلی وجود ندارد';

  @override
  String get geoFileCorrupt => 'فایل خراب است — هسته آن را نمی‌خواند';

  @override
  String geoFolder(String path) {
    return 'پوشه: $path';
  }

  @override
  String get geoBundledWindows =>
      'روی Windows این فایل‌ها همراه هسته می‌آیند و معمولاً از پیش سر جایشان هستند. به‌روزرسانی در اینجا وقتی فهرست‌ها کهنه شوند دوباره آن‌ها را دانلود می‌کند.';

  @override
  String get geoSource =>
      'منبع همان جایی است که فایل‌ها در بستهٔ Xray از آن می‌آیند: Loyalsoldier/v2ray-rules-dat. آنچه دانلود می‌شود با جمع کنترلی منتشرشده در همان نسخه سنجیده می‌شود.';

  @override
  String get geoReplaceWarning =>
      'فایل‌های پیشین نگه داشته می‌شوند: اگر پس از جایگزینی مسیریابی بدتر شد، یک دکمه آن‌ها را برمی‌گرداند. اگر در فایل تازه دسته‌بندی‌هایی که اشتراک شما به آن‌ها ارجاع می‌دهد نباشد، به‌روزرسانی نصب نمی‌شود.';

  @override
  String geoBackupLine(String files, String size, String date) {
    return 'نسخهٔ پشتیبان موجود است: $files — $size، از $date';
  }

  @override
  String get geoRestore => 'بازگرداندن نسخهٔ پیشین';

  @override
  String get geoRestored => 'داده‌های جغرافیایی پیشین بازگردانده شد';

  @override
  String get geoRestoreTitle => 'داده‌های جغرافیایی پیشین بازگردانده شود؟';

  @override
  String get geoRestoreBody =>
      'فایل‌های کنونی با نسخه‌ای که پیش از آخرین به‌روزرسانی ذخیره شده جایگزین می‌شوند. به اینترنت نیازی نیست. پس از آن، برگرداندن فایل‌های به‌روزشده تنها با دانلود دوباره ممکن است.';

  @override
  String get geoErrorCategories =>
      'در فایل تازه دسته‌بندی‌هایی که اشتراک شما به آن‌ها ارجاع می‌دهد وجود ندارد. جایگزینی لغو شد و فایل‌های پیشین سر جایشان ماندند — مسیریابی آسیبی ندید. اینکه دقیقاً کدام دسته‌بندی‌ها کم بوده‌اند، در خط پایین دیده می‌شود.';

  @override
  String get geoNoWrite =>
      'در این پوشه نمی‌توان نوشت — دانلود به اینجا انجام نمی‌شود. معمولاً این حالت پس از نصب در Program Files پیش می‌آید: برنامه را با دسترسی مدیر اجرا کنید.';

  @override
  String get geoCheck => 'بررسی به‌روزرسانی';

  @override
  String get geoCheckAgain => 'بررسی دوباره';

  @override
  String get geoChecking => 'در حال پرس‌وجوی آخرین نسخه…';

  @override
  String geoLastCheck(String when) {
    return 'آخرین بررسی: $when';
  }

  @override
  String get geoNeverChecked => 'به‌روزرسانی هنوز هرگز بررسی نشده است';

  @override
  String geoUpdateAvailable(String files, String size) {
    return 'به‌روزرسانی موجود است: $files — $size';
  }

  @override
  String get geoSizeUnknown => 'سرور حجم را اعلام نکرد';

  @override
  String get geoUpToDate =>
      'به‌روزرسانی لازم نیست: فایل‌ها با آخرین نسخه یکسان‌اند.';

  @override
  String get geoPlanTitle => 'داده‌های جغرافیایی دانلود شود؟';

  @override
  String get geoPlanTitleUpdate => 'داده‌های جغرافیایی به‌روزرسانی شود؟';

  @override
  String geoPlanFiles(String files) {
    return 'فایل‌ها: $files';
  }

  @override
  String geoPlanSize(String size) {
    return 'حجم: $size';
  }

  @override
  String get geoPlanTraffic =>
      'فایل‌ها از راه اتصال خود شما دانلود می‌شوند. روی طرح اینترنت همراه، این حجم قابل توجهی است.';

  @override
  String geoProgressBytes(String done, String total) {
    return '$done از $total';
  }

  @override
  String get geoErrorNetwork =>
      'ارتباط با سرور به‌روزرسانی برقرار نشد. اینترنت را بررسی کنید و دوباره تلاش کنید.';

  @override
  String get geoErrorServer =>
      'سرور به‌روزرسانی درخواست را رد کرد. به احتمال زیاد موقتی است — بعداً دوباره تلاش کنید.';

  @override
  String get geoErrorWrite =>
      'نوشتن فایل ممکن نشد: دسترسی به پوشه وجود ندارد یا فضای کافی نیست.';

  @override
  String get geoErrorCorrupt =>
      'فایل دانلودشده در بررسی صحت مردود شد — دانلود خراب شده است. دوباره تلاش کنید.';

  @override
  String get geoErrorOther => 'انجام نشد. جزئیات در پایین.';

  @override
  String geoFailed(String error) {
    return 'دانلود ناموفق بود: $error';
  }

  @override
  String get infoGeoAssets =>
      'فایل‌های geoip.dat و geosite.dat فهرست‌هایی از آدرس‌ها بر اساس کشور و دامنه‌ها بر اساس دسته‌بندی هستند (برای مثال «سایت‌های روسی»، «خدمات دولتی»، «VK»). قوانین مسیریابی که پنل اشتراک تعیین می‌کند بر پایه همین فایل‌ها کار می‌کنند.\n\nآن‌ها درون برنامه جای نگرفته‌اند: روی هم حدود ۳۰ MB حجم دارند و همه به آن‌ها نیاز ندارند — یک سرور معمولی اصلاً از آن‌ها استفاده نمی‌کند.\n\nتا زمانی که این فایل‌ها نباشند، چنین قوانینی از پیکربندی حذف می‌شوند و ترافیکی که آن‌ها به‌طور مستقیم می‌فرستادند از VPN عبور می‌کند. این کار امن است اما کندتر، و ممکن است سایت‌های محلی به‌دلیل آدرس خارجی دسترسی را رد کنند. قوانینی که خودتان برای سایت‌ها و برنامه‌های مشخص تعیین کرده‌اید در هر حال کار می‌کنند — به این فایل‌ها وابسته نیستند.';

  @override
  String get supportBullet2Android =>
      '• پس از زدن دکمه، گزارش در یک فایل جمع می‌شود و پنجرهٔ سیستمی «اشتراک‌گذاری» باز می‌شود — تلگرام را انتخاب کنید تا گزارش به‌صورت یک پیوست ارسال شود. مشکل را در کادر بالا بنویسید: بدون توضیح چیزی برای بررسی نیست.';

  @override
  String get supportDoneTextAndroid =>
      'گزارش در یک فایل جمع شد. در پنجرهٔ سیستمی انتخاب کنید که آن را کجا بفرستید — در تلگرام به‌صورت پیوست ارسال می‌شود، نه متن.';

  @override
  String get exitsHeader => 'خروجی‌ها';

  @override
  String get exitsHint =>
      'یک قاعده «تونل» را می‌توان به خروجی مشخصی هدایت کرد: یک سایت از آلمان و دیگری از آمریکا. بدون خروجی، قاعده مانند گذشته از تونل اصلی عبور می‌کند.';

  @override
  String get exitsAdd => 'افزودن خروجی';

  @override
  String get exitsEmpty => 'هنوز خروجی‌ای نیست';

  @override
  String get exitsName => 'نام';

  @override
  String get exitsNameHint => 'آلمان';

  @override
  String get exitsServers => 'سرورها';

  @override
  String get exitsAutoSelect => 'انتخاب خودکار بر پایه تأخیر';

  @override
  String get exitsAutoSelectSub =>
      'هسته خودش ترافیک را روی سرور فعال نگه می‌دارد. هزینه‌اش: هر سرور هر سه دقیقه آزموده می‌شود و این رادیوی گوشی را بیدار می‌کند.';

  @override
  String get exitsAutoSelectNeedsTwo => 'دست‌کم دو سرور لازم است';

  @override
  String get exitsDelete => 'حذف خروجی';

  @override
  String get exitsNoServers => 'سروری نیست — نخست اشتراک را وارد کنید';

  @override
  String get exitsSearch => 'جست‌وجوی سرور';

  @override
  String get exitsPickAtLeastOne => 'دست‌کم یک سرور انتخاب کنید';

  @override
  String get exitsUnsupportedNote =>
      'پروفایل‌های «خودکار» پنل و hysteria2 به‌عنوان خروجی جداگانه بالا نمی‌آیند: هسته دیگری آن‌ها را اداره می‌کند. چنین سرورهایی در فهرست غیرفعال‌اند.';

  @override
  String get infoExits =>
      'خروجی مقصد قاعده «تونل» است.\n\nبه‌طور پیش‌فرض هر خروجی یک سرور است و در پس‌زمینه هیچ هزینه‌ای ندارد: پروتکل‌های معمول اتصال دائمی نگه نمی‌دارند. گروهی از چند سرور با انتخاب خودکار تنها جایی لازم است که پشتیبان در برابر افتادن گره اهمیت دارد — اندازه‌گیری دوره‌ای می‌افزاید و روی گوشی یعنی بیدار شدن رادیو.\n\nخروجی تنها با کنش «تونل» معنا دارد. «مستقیم از آلمان» تناقض است: قاعده مستقیم از همه خروجی‌ها می‌گذرد.\n\nیک سایت و زیردامنه‌اش می‌توانند به خروجی‌های متفاوت بروند — برنامه قاعده مشخص‌تر را بالاتر می‌برد، وگرنه دامنه والد زیردامنه را می‌بلعید.\n\nمهم: با پروکسی سیستمی در ویندوز خروجی‌ها اصلاً کار نمی‌کنند — در آن حالت قاعده مسیریابی ساخته نمی‌شود. حالت تونل لازم است.';

  @override
  String get ruleServer => 'از طریق سرور';

  @override
  String get ruleServerCurrent => 'مانند سرور اصلی';

  @override
  String ruleServerCurrentNamed(String server) {
    return 'مانند سرور اصلی ($server)';
  }

  @override
  String get routeMatchByName => 'تطبیق بر اساس نام فایل';

  @override
  String get routeYourApps => 'برنامه‌های شما';

  @override
  String get routeYourSites => 'سایت‌های شما';

  @override
  String get routeAppsAndSites => 'برنامه‌ها و سایت‌ها';

  @override
  String get notifCompactTitle => 'اعلان کوتاه';

  @override
  String get notifCompactSub =>
      'خاموش: اشتراک، سرور و سرعت، همراه با دکمه‌ها. روشن: در عنوان، برنامه و اشتراک و پایین‌تر سرور — بدون سرعت و بدون دکمه.';

  @override
  String get localProxyAuthTitle => 'رمز عبور برای پروکسی محلی';

  @override
  String get localProxyAuthInfo =>
      'پورت محلی هسته (127.0.0.1) یک پروکسی تمام‌عیار به VPN شماست. بدون رمز عبور، هر برنامه‌ای روی همین دستگاه می‌تواند به آن وصل شود و کل تونل شما را بگیرد: IP خروجی، سهمیهٔ اشتراک و دور زدن قوانین تونل تفکیکی خودتان — حتی برنامه‌هایی که برایشان «مسدود» گذاشته‌اید. روی Android این نکته مهم‌تر است: آنجا پورت‌های محلی را هر برنامهٔ نصب‌شده‌ای می‌بیند.\n\nتنها زمانی خاموشش کنید که آگاهانه با ابزاری به این پروکسی می‌روید که احراز هویت بلد نیست.';

  @override
  String get localProxyAuthOff =>
      'خاموش: پروکسی محلی برای هر برنامه‌ای روی دستگاه باز است';

  @override
  String get localProxyAuthSystemProxy =>
      'در حالت «پروکسی سیستمی» اعمال نمی‌شود: Windows نمی‌تواند رمز عبور را به پروکسی محلی بدهد. در حالت TUN کار می‌کند.';

  @override
  String get localProxyAuthRandom =>
      'گذرواژهٔ تصادفی تازه در هر اتصال — در تنظیمات ذخیره نمی‌شود';

  @override
  String get localProxyAuthCustom =>
      'نام کاربری و رمز خودتان (در فایل تنظیمات ذخیره می‌شود)';

  @override
  String get localProxyCredsTitle => 'نام کاربری و رمز خودتان';

  @override
  String get localProxyCredsUnset => 'تعیین نشده — رمز تصادفی به‌کار می‌رود';

  @override
  String localProxyCredsUser(String user) {
    return 'نام کاربری: $user';
  }

  @override
  String get localProxyDialogTitle => 'نام کاربری و رمز پروکسی محلی';

  @override
  String get localProxyDialogBody =>
      'تنها زمانی لازم است که خودتان پروکسی ما (127.0.0.1) را در برنامه‌ای دیگر بنویسید. کادرها را خالی بگذارید تا گذرواژه در هر اتصال تصادفی باشد: در تنظیمات ذخیره نمی‌شود و به لاگ و گزارش پشتیبانی هم نمی‌رسد. گذرواژه‌ای که دستی می‌گذارید در پروندهٔ تنظیمات به‌صورت متن ساده می‌ماند.';

  @override
  String get localProxyFieldUser => 'نام کاربری';

  @override
  String get localProxyFieldPassword => 'رمز عبور';

  @override
  String get localProxyFieldHint => 'خالی = تصادفی';

  @override
  String get lockdownOnTitle => 'محافظت در سطح سیستم روشن است';

  @override
  String get lockdownOnSub =>
      'ترافیک مسدود می‌ماند، حتی اگر برنامه بسته شود یا سیستم آن را از حافظه بیرون بیندازد. مطمئن‌ترین حالت همین است.';

  @override
  String get lockdownHalfTitle => 'محافظت نیمه‌کاره است';

  @override
  String get lockdownHalfSub =>
      '«VPN همیشه‌روشن» تنظیم شده، اما «مسدودکردن اتصال بدون VPN» خاموش است. تا وقتی برنامه زنده است ترافیک محافظت می‌شود؛ اگر سیستم آن را از حافظه بیرون بیندازد، ترافیک باز و بی‌محافظ بیرون می‌رود.';

  @override
  String get lockdownOffTitle => 'محافظت در سطح سیستم خاموش است';

  @override
  String get lockdownOffSub =>
      'کیل‌سوییچ ما تا وقتی برنامه در حال اجراست ترافیک را نگه می‌دارد. اگر سیستم آن را از حافظه بیرون بیندازد، ترافیک از کنار VPN می‌رود. «VPN همیشه‌روشن» و «مسدودکردن اتصال بدون VPN» را روشن کنید.';

  @override
  String get lockdownUnknownTitle => 'محافظت در سطح سیستم: وضعیت نامعلوم';

  @override
  String get lockdownUnknownSub =>
      'وضعیت را فقط از Android 10 به بعد و تنها با تونل برپا می‌توان خواند. دستی بررسی کنید: «VPN همیشه‌روشن» و «مسدودکردن اتصال بدون VPN».';

  @override
  String get lockdownOpenFailed =>
      'باز کردن تنظیمات VPN سیستم ممکن نشد. دستی پیدایشان کنید: تنظیمات ← شبکه و اینترنت ← VPN.';

  @override
  String get blockNoticeTitle => 'اطلاع دادن دربارهٔ سایت‌های مسدودشده';

  @override
  String get blockNoticeSub =>
      'وقتی برنامه یا مرورگر سراغ سایتی از فهرست «مسدود» می‌رود، پایین صفحه اعلانی با نام آن ظاهر می‌شود. رویش بزنید تا همین صفحه باز شود.';

  @override
  String get siteInsecureScheme =>
      'نشانی با http:// نوشته شده — اتصال رمزگذاری نمی‌شود و ISP آن را کامل می‌بیند. «http://» را بردارید تا مرورگر از https برود.';

  @override
  String get exitServerGone =>
      'سرور این قانون از اشتراک ناپدید شده — ترافیک از تونل اصلی می‌رود';

  @override
  String exitServerUnsupported(String name) {
    return '$name\n\nاین سرور را نمی‌توان به‌عنوان خروجی جداگانه بالا آورد: پروفایل‌های «خودکار» پنل و بخشی از پروتکل‌ها را تنها Xray اداره می‌کند، اما خروجی‌ها را sing-box تقسیم می‌کند. ترافیک این قانون از تونل اصلی می‌رود.';
  }

  @override
  String get noticeRulesAction => 'قوانین';

  @override
  String get geoVerdictMissingTitle => 'داده‌های جغرافیایی دانلود نشده‌اند';

  @override
  String get geoVerdictMissingSub =>
      'قوانین کشوری و دسته‌بندی اشتراک اکنون غیرفعال‌اند — این ترافیک به‌جای مسیر مستقیم از VPN می‌رود.';

  @override
  String get geoVerdictUnusableTitle => 'هسته داده‌های جغرافیایی را باز نکرد';

  @override
  String get geoVerdictUnusableSub =>
      'فایل‌ها سر جایشان هستند، اما هسته آن‌ها را نخواند. دانلود دوبارهٔ داده‌ها معمولاً کمک می‌کند.';

  @override
  String get geoOfferMissingSub =>
      'بدون آن‌ها قوانین کشوری و دسته‌بندی اشتراک کار نمی‌کنند — این ترافیک به‌جای مسیر مستقیم از VPN می‌رود.';

  @override
  String get geoOfferDismiss => 'دیگر پیشنهاد نشود';

  @override
  String get pingPendingTooltip =>
      'تأخیر TCP تا سرور. بررسی کانال هنوز ادامه دارد و معلوم نیست سرور واقعاً کار می‌کند یا نه.';

  @override
  String get pingUnverifiedTooltip =>
      'تأخیر TCP تا سرور. هیچ بررسی‌ای از راه تونل انجام نشده و تنها در دسترس بودن معلوم است.';

  @override
  String pingMeasuredAt(String time) {
    return 'زمان اندازه‌گیری: $time';
  }

  @override
  String get pingChecking => 'در حال بررسی';

  @override
  String autoTimer(String elapsed, String remaining) {
    return 'گذشته $elapsed · حدود $remaining مانده';
  }

  @override
  String autoTimerNoEstimate(String elapsed) {
    return 'گذشته $elapsed';
  }

  @override
  String autoSpeedRanking(String name) {
    return 'اندازه‌گیری سرعت: $name';
  }

  @override
  String get autoWarnNoRealIp =>
      'گزینهٔ «آی‌پی واقعی استفاده نشود» روشن است و همهٔ ترافیک از VPN می‌گذرد.';

  @override
  String get autoWarnAllVpn =>
      'حالت «همه‌چیز از راه VPN» انتخاب شده و قاعده‌های شما فعلاً اثری ندارند.';

  @override
  String get autoWarnPanelOverride =>
      'گزینهٔ «قاعده‌های من بر قاعده‌های پنل مقدم است» روشن است.';

  @override
  String get autoWarnProbesDirect =>
      'این بر خود بررسی اثری ندارد: کاوش‌ها با هر تنظیمی از کنار VPN می‌گذرند. اما در حالت TUN از فرایند هسته عبور می‌کنند؛ اگر هسته گیر کرده باشد، همهٔ نتیجه‌ها منفی کاذب خواهند بود.';

  @override
  String get autoWarnTurnOff => 'خاموش کردن';

  @override
  String get toastCollapse => 'جمع کردن';

  @override
  String get toastExpand => 'باز کردن';

  @override
  String get toastOpenAutoConfig => 'باز کردن تنظیم خودکار';

  @override
  String get splitAppAlreadyAdded => 'این برنامه از پیش در فهرست قاعده‌ها هست';

  @override
  String logsFileLine(String name, String size, int lines) {
    return '$name — $size، $lines خط';
  }

  @override
  String logsReportsLine(int count, String size) {
    return 'گزارش‌های پشتیبانی: $count، $size';
  }

  @override
  String get logsRetentionTitle => 'نگه‌داشتن گزارش‌ها و لاگ‌ها';

  @override
  String get logsRetentionDay => '۱ روز';

  @override
  String get logsRetentionTwoWeeks => '۲ هفته';

  @override
  String get logsRetentionMonth => '۱ ماه';

  @override
  String get logsRetentionNever => 'هرگز حذف نشود';

  @override
  String get logsRetentionInfo =>
      'لاگ‌ها و گزارش‌های پشتیبانی وقتی از مدت انتخاب‌شده کهنه‌تر شوند حذف می‌شوند و بررسی هنگام آغاز برنامه انجام می‌گیرد. گزینهٔ «هرگز» همه‌چیز را روی دیسک نگه می‌دارد؛ آنگاه خودتان حجم را بپایید، چون گزارش لاگ‌ها را به‌طور کامل در خود دارد و همراه آن‌ها بزرگ می‌شود.';

  @override
  String get logsCleanNow => 'حذف موارد قدیمی';

  @override
  String logsCleaned(int count, String size) {
    return 'پرونده‌های حذف‌شده: $count، آزادشده $size';
  }

  @override
  String get logsNothingToClean => 'چیزی برای حذف نیست';

  @override
  String get speedTooltip => 'سرعت دریافت از راه این سرور';

  @override
  String get speedFromAutoConfig => 'سرعت را تنظیم خودکار اندازه گرفته است';

  @override
  String get speedBlockedTooltip =>
      'سرعت اندازه‌گیری نمی‌شود: سرور بررسی کانال را نگذرانده (درخواست از راه آن نرسید)';

  @override
  String get srvTileMeasureSpeed => 'اندازه‌گیری سرعت';

  @override
  String get speedRunTooltip => 'اندازه‌گیری سرعت سرورها';

  @override
  String get speedConfirmTitle => 'سرعت اندازه گرفته شود؟';

  @override
  String speedConfirmBody(int count, String size, String total) {
    return '$count سرور بررسی می‌شود و هرکدام نمونه‌ای به حجم $size دریافت می‌کند — نزدیک $total از ترافیک اشتراک شما.';
  }

  @override
  String speedConfirmSkipped(int count) {
    return 'آنچه پیش‌تر اندازه گرفته شده رد می‌شود: $count.';
  }

  @override
  String get speedConfirmRun => 'اندازه‌گیری';

  @override
  String get speedNoTargets =>
      'چیزی برای اندازه‌گیری نیست: سرعت تنها برای سرورهایی سنجیده می‌شود که بررسی کانال را گذرانده‌اند. نخست فهرست را بیازمایید.';

  @override
  String get speedNotVerified =>
      'سرور بررسی کانال را نگذرانده — سرعت را از راه آن نمی‌سنجیم';

  @override
  String speedProgress(int done, int total) {
    return 'سرعت: $done از $total';
  }

  @override
  String get updateOnStartTitle => 'به‌روزرسانی اشتراک هنگام آغاز';

  @override
  String get updateOnStartSub =>
      'هر بار فهرست تازهٔ سرورها گرفته شود، نه فقط با زمان‌سنج';

  @override
  String get apiSectionSub =>
      '‏HTTP روی 127.0.0.1 — کنترل برنامه از راه اسکریپت';

  @override
  String get momentJustNow => 'همین الان';

  @override
  String momentMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count دقیقه پیش',
      one: '$count دقیقه پیش',
    );
    return '$_temp0';
  }

  @override
  String momentHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ساعت پیش',
      one: '$count ساعت پیش',
    );
    return '$_temp0';
  }

  @override
  String get serviceChecksMenuTitle => 'بررسی هنگام اتصال';

  @override
  String get serviceChecksMenuOff => 'هنگام اتصال بررسی نشود';

  @override
  String get serviceChecksMenuTooltip => 'چه سرویس‌هایی بررسی شوند';

  @override
  String get serviceChecksLegendOff => 'بررسی سرویس‌ها خاموش است';

  @override
  String get srvInfoAutoNever =>
      'پیکربندی خودکار هنوز این سرور را بررسی نکرده است — آن را اجرا کنید تا ببینید کدام سرویس‌ها از طریق آن کار می‌کنند.';

  @override
  String get srvInfoAutoHint =>
      'داده‌های آخرین اجرای پیکربندی خودکار. اینجا چیزی دوباره اندازه‌گیری نمی‌شود.';

  @override
  String srvInfoAutoGeoNote(Object services) {
    return '$services: از طریق این سرور باز می‌شود اما در کشور خروجی آن در دسترس نیست. خودِ سرور سالم است — فقط همین سرویس‌ها کار نمی‌کنند و برای آن‌ها به خروجی در کشور دیگری نیاز دارید.';
  }

  @override
  String get settingsSectionChecks => 'بررسی سرویس‌ها';

  @override
  String get settingsSectionAutotune => 'تنظیم خودکار';

  @override
  String get settingsSpeedRankTitle => 'در نظر گرفتن سرعت هنگام انتخاب خودکار';

  @override
  String get settingsSpeedRankSub =>
      'نامزدهایی که بررسی سرویس‌ها را رد کرده‌اند، افزون بر آن با دانلود سنجیده می‌شوند تا سروری که واقعاً سریع‌تر است نخست بایستد. از ترافیک اشتراک شما خرج می‌کند.';

  @override
  String get settingsSpeedTopNLabel => 'تعداد سرورها در سنجش سرعت';

  @override
  String get settingsSpeedTopNSub =>
      'به‌علاوهٔ یک سنجش از خط خودتان؛ بدون آن معیاری برای مقایسه نیست: ۶۰ مگابیت بر ثانیه روی خط ۶۰ عالی و روی خط ۳۰۰ ضعیف است.';

  @override
  String settingsSpeedTrafficNote(Object mb) {
    return '‏≈$mb مگابایت از ترافیک اشتراک در هر اجرا';
  }

  @override
  String get settingsSpeedWarnTitle => 'سنجش سرعت از ترافیک اشتراک خرج می‌کند';

  @override
  String settingsSpeedWarnBody(Object mb) {
    return 'هر اجرای تنظیم خودکار حدود $mb مگابایت از اشتراک شما دانلود می‌کند: یک آزمون برای هر سرور سنجیده‌شده به‌علاوهٔ یک آزمون از خط خودتان. این مگابایت‌ها از سهمیهٔ شما کم می‌شود.';
  }

  @override
  String get settingsSpeedWarnEnable => 'با این حال فعال شود';

  @override
  String get settingsConcurrencyTitle => 'شمار بررسی‌های هم‌زمان';

  @override
  String get settingsConcurrencySub =>
      '۱ همان رفتار پیشین است: نامزدها دقیقاً یکی پس از دیگری بررسی می‌شوند و اگر نتیجه‌ها عجیب شد، باید به همین مقدار بازگشت. بیشتر یعنی سریع‌تر، اما هر نامزد هستهٔ خودش را بالا می‌آورد: بار دستگاه بیشتر می‌شود و سنجش‌های تأخیر بر یکدیگر اثر می‌گذارند.';

  @override
  String get settingsConnectChecksTitle => 'بررسی سرویس‌ها هنگام اتصال';

  @override
  String get settingsConnectChecksSubOn =>
      'یک اجرا هنگام بالا آمدن تونل: نشان‌های زیر دکمه بی‌درنگ می‌گویند چه چیزی باز می‌شود و چه چیزی نه.';

  @override
  String get settingsConnectChecksSubOff =>
      'نشان‌ها خاکستری می‌مانند تا خودتان روی آن‌ها بزنید.';

  @override
  String get settingsConnectCheckServices => 'هنگام اتصال چه چیزی بررسی شود';

  @override
  String get settingsConnectCheckServicesSub =>
      'این مجموعه عمداً از تنظیم خودکار جداست: آن یکی دنبال سروری می‌گردد که کار کند و حاضر است مدت‌ها جست‌وجو کند، اما این نشان‌ها به پرسش «همین حالا کار می‌کند؟» پاسخ می‌دهند.';

  @override
  String get settingsConnectChecksEmpty =>
      'هیچ سرویسی انتخاب نشده است — چیزی برای بررسی نخواهد بود.';

  @override
  String get settingsSectionSeamless => 'بی‌وقفگی';

  @override
  String get settingsSeamlessNote =>
      'هیچ‌کدام از این گزینه‌ها اتصال‌های باز را زنده نگه نمی‌دارد: سرور دیگر یعنی IP بیرونی دیگر و طرف مقابل نشانی دیگری می‌بیند — تماس یا دانلود در هر صورت قطع می‌شود. سخن تنها بر سر آن است که شبکهٔ دستگاه چشمک نزند.';

  @override
  String get settingsSeamlessServerTitle =>
      'هنگام تعویض سرور تونل بازسازی نشود';

  @override
  String get settingsSeamlessServerSub =>
      'تنها هستهٔ پراکسی از نو راه می‌افتد: آداپتور و مسیرها سر جای خود می‌مانند و شبکهٔ دستگاه چشمک نمی‌زند. بهایش: نشانی همهٔ سرورهای اشتراک از پیش بیرون از تونل نوشته می‌شود.';

  @override
  String get settingsSeamlessNetworkTitle => 'هنگام تغییر شبکه کانال قطع نشود';

  @override
  String get settingsSeamlessNetworkSub =>
      'وای‌فای ← داده تلفنی: نخست بررسی می‌کنیم ترافیک هنوز زنده است یا نه و تنها در صورت مرگ آن هسته را از نو راه می‌اندازیم. QUIC (هیستریا۲) تغییر نشانی را خودش تاب می‌آورد. بهایش: اگر کانال واقعاً مرده باشد، بازیابی چند ثانیه دیرتر آغاز می‌شود.';

  @override
  String get settingsSeamlessKeepTunTitle => 'آداپتور میان تلاش‌ها برپا بماند';

  @override
  String get settingsSeamlessKeepTunSub =>
      'تا زمانی که بازیابی ادامه دارد، مسیر پیش‌فرض دستکاری نمی‌شود. ⚠️ این kill switch نیست: ترافیک بیرون از VPN مسدود نمی‌شود و تنها خودِ آداپتور نگه داشته می‌شود.';

  @override
  String get autoSpeedTrafficTitle => 'آزمایش سرعت ترافیک مصرف می‌کند';

  @override
  String autoSpeedTrafficBody(int servers, int mb) {
    return 'سرعت $servers سرور برتر و سرعت اینترنت خودتان اندازه‌گیری می‌شود — حدود $mb مگابایت از ترافیک اشتراک شما.\n\nمی‌توانید این آزمایش را در تنظیمات خاموش کنید.';
  }

  @override
  String get autoSpeedTrafficGo => 'شروع';

  @override
  String get splitDeadPath =>
      'فایل در این مسیر دیگر وجود ندارد — قاعده هرگز اعمال نمی‌شود';

  @override
  String get splitDeadPathFix => 'برای تطبیق بر اساس نام فایل ضربه بزنید';

  @override
  String get srvTileCopyKey => 'کپی کلید';

  @override
  String serviceChecksBypassDirect(Object rule) {
    return 'خارج از VPN: قانون تونل تفکیک‌شده «$rule» این دامنه را مستقیم می‌فرستد — سرویس با نشانی واقعی شما کار می‌کند.';
  }

  @override
  String serviceChecksBypassBlock(Object rule) {
    return 'مسدود: قانون تونل تفکیک‌شده «$rule» این دامنه را ممنوع کرده — سرویس نه با VPN باز می‌شود و نه بدون آن.';
  }

  @override
  String get subBarOpenSite => 'وب‌سایت';

  @override
  String get subBarOpenSiteHint => 'باز کردن صفحهٔ اشتراک در مرورگر';

  @override
  String subSwitcherRefreshingOne(Object name) {
    return 'در حال به‌روزرسانی «$name»…';
  }

  @override
  String subSwitcherRefreshedOne(Object name) {
    return '«$name» به‌روزرسانی شد';
  }

  @override
  String subSwitcherRefreshFailedOne(Object name) {
    return 'به‌روزرسانی «$name» ناموفق بود';
  }

  @override
  String subBarDeleteConfirmNamed(Object name) {
    return 'اشتراک «$name» حذف شود؟';
  }

  @override
  String get exitServerUnsupportedInfo =>
      'این سرور را نمی‌توان به‌عنوان خروجی جداگانه بالا آورد: پروفایل‌های «خودکار» پنل و بخشی از پروتکل‌ها را تنها Xray اداره می‌کند، اما خروجی‌ها را sing-box تقسیم می‌کند. ترافیک این قانون از تونل اصلی می‌رود.';

  @override
  String get pingBusyServiceChecks =>
      'پینگ در دسترس نیست: بررسی سرویس‌ها در جریان است';

  @override
  String get serviceChecksChannelNotReady =>
      'تونل هنوز آماده نیست — بررسی‌ها اجرا نشدند';

  @override
  String get serviceChecksRetryCheck => 'تلاش دوباره برای بررسی';

  @override
  String get serviceGroupMessengers => 'پیام‌رسان‌ها';

  @override
  String get serviceGroupAi => 'هوش مصنوعی';

  @override
  String get serviceGroupMedia => 'ویدیو و موسیقی';

  @override
  String get serviceGroupSocial => 'شبکه‌های اجتماعی';

  @override
  String get serviceGroupOther => 'سایر';

  @override
  String get apiTokenHidden => 'پنهان — «نمایش» را بزنید';

  @override
  String get apiTokenShow => 'نمایش توکن';

  @override
  String get apiTokenHide => 'پنهان کردن توکن';

  @override
  String get apiCheatSheetTitle => 'راهنمای کوتاه: نشانی، پورت‌ها، اندپوینت‌ها';

  @override
  String get apiCheatSheetBase => 'نشانی پایه';

  @override
  String get apiCheatSheetExitPorts => 'پورت‌های خروج';

  @override
  String apiCheatSheetPortDirect(Object port) {
    return '$port — «مستقیم»: بیرون از VPN، IP واقعی';
  }

  @override
  String apiCheatSheetPortServer(int port, String name) {
    return '$port — $name';
  }

  @override
  String get apiCheatSheetNoExitServers =>
      'هیچ سروری انتخاب نشده — پورت سرور وجود نخواهد داشت';

  @override
  String apiCheatSheetPortsSystemProxy(Object control) {
    return 'باز نمی‌شوند: حالت گرفتن ترافیک «پراکسی سیستمی» است. تنها پورت کنترل $control کار می‌کند';
  }

  @override
  String get apiCheatSheetTokenOff =>
      'توکن خالی است — کانال بالا نمی‌آید و هیچ پورتی گوش نمی‌دهد';

  @override
  String get apiCheatSheetPortsWhenConnected =>
      'پورت‌های خروج فقط هنگام برقراری اتصال گوش می‌دهند.';

  @override
  String get apiCheatSheetEndpoints => 'اندپوینت‌ها';

  @override
  String get apiEpStatus =>
      'وضعیت موتور، سرور انتخاب‌شده، حالت گرفتن ترافیک و در جریان بودن پینگ';

  @override
  String get apiEpServers => 'فهرست سرورها همراه با آخرین نتایج پینگ';

  @override
  String get apiEpExits => 'چیدمان پورت‌های خروج به‌همراه مدخل «مستقیم»';

  @override
  String get apiEpTraffic => 'شمارنده‌های ترافیک برای کل مدت اجرای برنامه';

  @override
  String get apiEpSubscription => 'نام اشتراک، تاریخ انقضا و ترافیک باقی‌مانده';

  @override
  String get apiEpConnect =>
      'اتصال با کلید سرور، با نام یا «خودکار»؛ روی کانال فعال سرور را عوض می‌کند';

  @override
  String get apiEpDisconnect => 'قطع اتصال؛ فراخوانی دوباره بی‌خطر است';

  @override
  String get apiEpPing =>
      'شروع پینگ همه سرورها؛ نتیجه‌ها را از ‎/v1/servers بخوانید';

  @override
  String get apiCopyCurlExample => 'کپی نمونهٔ curl';
}
