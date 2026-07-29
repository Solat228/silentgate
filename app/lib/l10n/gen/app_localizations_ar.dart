// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonCopy => 'نسخ';

  @override
  String get commonCopied => 'تم النسخ';

  @override
  String get commonRefresh => 'تحديث';

  @override
  String get commonCheck => 'فحص';

  @override
  String get commonOk => 'موافق';

  @override
  String get commonDone => 'تم';

  @override
  String get commonPathCopied => 'تم نسخ المسار';

  @override
  String get languageTitle => 'لغة الواجهة';

  @override
  String get languageSubtitle => 'اختر لغة التطبيق';

  @override
  String get languageSystem => 'افتراضي النظام';

  @override
  String get sectionAppearance => 'المظهر والسلوك';

  @override
  String get sectionCapture => 'التقاط حركة المرور';

  @override
  String get sectionReliability => 'موثوقية الاتصال';

  @override
  String get sectionPing => 'Ping';

  @override
  String get sectionIdentity => 'هوية اللوحة';

  @override
  String get sectionNetwork => 'الشبكة';

  @override
  String get sectionAbout => 'حول';

  @override
  String get sectionSupport => 'الدعم';

  @override
  String get appearanceTheme => 'السمة';

  @override
  String get themeSystem => 'النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get closeToTrayTitle => 'التصغير إلى شريط المهام عند الإغلاق';

  @override
  String get closeToTraySubtitle =>
      'زر الإغلاق يخفي النافذة إلى شريط المهام؛ أوقفه ليُغلق التطبيق بدلاً من ذلك';

  @override
  String get autoUpdateSubTitle => 'التحديث التلقائي للاشتراك';

  @override
  String get autoUpdateSubText => 'تحديث قائمة الخوادم دورياً';

  @override
  String get captureSystemProxy => 'بروكسي النظام';

  @override
  String get captureSystemProxySub => 'يعمل الآن. بدون صلاحيات المسؤول.';

  @override
  String get captureTun => 'TUN (نفق كامل)';

  @override
  String get captureTunBadgeUac => 'يتطلب UAC';

  @override
  String get captureTunSub =>
      'كل حركة المرور، بما في ذلك UDP والتطبيقات التي تتجاهل البروكسي. يتطلب صلاحيات المسؤول.';

  @override
  String get tunProvider => 'مزوّد TUN';

  @override
  String get tunRoutingTitle => 'TUN والتوجيه';

  @override
  String tunRoutingSub(String stack, int mtu, String dns) {
    return 'الحزمة $stack · MTU $mtu · DNS $dns';
  }

  @override
  String get splitTunnelTitle => 'تقسيم النفق';

  @override
  String splitRulesCount(int n, int apps, int sites) {
    return '$n قاعدة ($apps تطبيقات، $sites مواقع)';
  }

  @override
  String get captureTunHint =>
      'تظهر إعدادات TUN وDNS وتقسيم النفق عند اختيار وضع TUN — أما في وضع بروكسي النظام فلا أثر لها.';

  @override
  String get dnsShortVpn => 'عبر VPN';

  @override
  String get dnsShortSystem => 'النظام';

  @override
  String get dnsShortCustom => 'مخصّص';

  @override
  String get tunUacTitle => 'يتطلب TUN صلاحيات المسؤول';

  @override
  String get tunUacBody =>
      'يمكنك إعداده مرة واحدة: سيُنشئ التطبيق مهمة في Windows Task Scheduler بأعلى الصلاحيات، وبعدها سيبدأ النفق دون طلب UAC.\n\nسيظهر طلب مسؤول واحد الآن. أما التطبيق نفسه فيستمر في العمل دون صلاحيات مرتفعة.';

  @override
  String get tunUacLater => 'لاحقاً (اسأل في كل مرة)';

  @override
  String get tunUacSetup => 'إعداد';

  @override
  String get tunUacDone => 'تم: سيبدأ TUN دون طلب UAC';

  @override
  String get tunUacFail => 'تعذّر إنشاء المهمة — سيُطلب UAC عند الاتصال';

  @override
  String get autoReconnectTitle => 'إعادة الاتصال التلقائية';

  @override
  String get autoReconnectSub =>
      'استعادة الاتصال عند انقطاعه وعند تغيّر الشبكة';

  @override
  String get killSwitchTitle => 'مفتاح الإيقاف (Kill switch)';

  @override
  String get alwaysOnTitle => 'حماية على مستوى النظام';

  @override
  String get alwaysOnSub =>
      'VPN دائم التشغيل مع «حظر الاتصالات بدون VPN» — يعمل حتى عند إغلاق التطبيق';

  @override
  String get killSwitchSubTun =>
      'لا تسمح لحركة المرور بتجاوز VPN أثناء إعادة الاتصال';

  @override
  String get killSwitchSubProxy =>
      'في وضع «بروكسي النظام» يحمي التطبيقات الداعمة للبروكسي فقط. بالكامل — عبر TUN فقط';

  @override
  String get killSwitchSubOff => 'يتطلب تفعيل إعادة الاتصال التلقائية';

  @override
  String get networkRecoverTitle => 'استعادة الشبكة';

  @override
  String get networkRecoverSub =>
      'إذا اختفى الإنترنت بعد VPN. يتطلب صلاحيات المسؤول';

  @override
  String get networkRecoverConfirmTitle => 'استعادة الشبكة؟';

  @override
  String get networkRecoverConfirmBody =>
      'إعادة تعيين winsock وحزمة IP وDNS وبروكسي النظام. يتطلب صلاحيات المسؤول (UAC). تسري إعادة تعيين winsock/IP بعد إعادة التشغيل.';

  @override
  String get networkRecoverConfirmOk => 'استعادة';

  @override
  String get interferenceTitle => 'التحقق من التداخل (شبكات VPN أخرى)';

  @override
  String get interferenceDialogTitle => 'تداخل الشبكة';

  @override
  String get interferenceNoneFound => 'لم يُكتشف أي VPN آخر أو تداخل.';

  @override
  String get interferenceIgnore => 'تجاهل';

  @override
  String get identityUserAgent => 'User-Agent';

  @override
  String identityUaAutoNote(String version) {
    return 'يُحدَّث تلقائياً مع إصدار التطبيق. تُرسَل أيضاً: X-HWID، X-Device-OS، X-Ver-OS، X-App-Version ($version).';
  }

  @override
  String get urlSchemesTitle => 'مخططات URL';

  @override
  String get urlSchemesSub =>
      'الاستيراد والتحكم في VPN عبر الروابط (اتصال / تبديل / تحديث)';

  @override
  String get panelOwnerTitle => 'لمالك اللوحة';

  @override
  String get panelOwnerBody =>
      'لا يحتاج المستخدمون العاديون إلى هذا — يمكنك تخطّيه.\n\nلكي يستقبل التطبيق اشتراكك بتنسيق JSON الصحيح (XRAY_JSON)، أضِف هذا المقطع إلى Response Rules في لوحة Remnawave الخاصة بك — فهو يطابق User-Agent الخاص بنا:';

  @override
  String get panelOwnerCopy => 'نسخ المقطع';

  @override
  String get aboutVersion => 'إصدار SilentGate';

  @override
  String get aboutXrayCore => 'نواة Xray';

  @override
  String get aboutHwid => 'HWID الجهاز';

  @override
  String get aboutThirdPartyTitle => 'مكوّنات وتراخيص أطراف ثالثة';

  @override
  String get aboutThirdPartySub =>
      'Xray-core (MPL-2.0)، sing-box (GPL-3.0)، Wintun — تعمل كعمليات منفصلة';

  @override
  String get aboutThirdPartySubEmbedded =>
      'Xray-core (MPL-2.0)‏، sing-box (GPL-3.0)‏، libXray (MIT) — مضمّنة في التطبيق';

  @override
  String get thirdPartyBodyEmbedded =>
      'On Android the cores are BUILT INTO the app (a native library inside the APK).\n\n• sing-box — GPL-3.0. The library is linked into the app, so derivatives must stay under GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nClient source code: https://github.com/Solat228/silentgate\nFull license texts — buttons below.';

  @override
  String get logsTitle => 'السجلات';

  @override
  String get logsSub =>
      'التطبيق وTUN (sing-box): استيراد الاشتراك، Ping، الأخطاء';

  @override
  String get thirdPartyTitle => 'مكوّنات أطراف ثالثة';

  @override
  String get thirdPartyBody =>
      'يُشحن SilentGate مع ملفات تنفيذية من أطراف ثالثة. تعمل كعمليات منفصلة ولا تُدمج داخل التطبيق.\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  نفق TUN ونواة البروكسي لـ Hysteria2\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — ترخيص Wintun\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — بيانات التوجيه، CC-BY-SA-4.0\n\nنصوص التراخيص الكاملة موجودة في مجلد «licenses» بجوار التطبيق.';

  @override
  String get supportSectionNote =>
      'انقر «التواصل مع الدعم» — تُفتح نافذة تُنشئ فيها ملف سجل بنفسك (الإصدارات، نظام التشغيل، الإعدادات، app.log + نهاية singbox.log؛ بدون كلمات مرور أو رمز اشتراك، وURL مخفي). بعد ذلك يظهر زر لإرساله إلى دعم Telegram.';

  @override
  String get supportButtonTitle => 'التواصل مع الدعم';

  @override
  String get supportButtonSub => 'أنشئ سجلاً وافتح محادثة الدعم';

  @override
  String get supportDialogTitle => 'الدعم';

  @override
  String get supportDialogTitleDone => 'السجل جاهز — إلى أين تُرسله';

  @override
  String get supportWhatWillHappen => 'ما الذي سيحدث:';

  @override
  String get supportBullet1 =>
      '• سيجمع ملف واحد الإصدارات ونظام التشغيل والإعدادات والسجلات (app.log + نهاية singbox.log). لا يحتوي على كلمات مرور أو رمز اشتراك، وURL الاشتراك مخفي.';

  @override
  String get supportBullet2 =>
      '• بعد النقر، يُفتح أولاً المجلد الذي يحتوي على الملف، ثم الملف نفسه. صِف المشكلة في الأعلى، احفظه — ويظهر زر لإرساله إلى الدعم.';

  @override
  String supportError(String error) {
    return 'فشل بناء التقرير: $error';
  }

  @override
  String get supportDoneText =>
      'تم بناء التقرير وفتحه (المجلد، ثم الملف). صِف المشكلة في الأعلى، واحفظ الملف وأرسله إلى الدعم — سيساعدك التطبيق على فتح Telegram.';

  @override
  String get supportWhoTo => 'إلى أين تُرسله:';

  @override
  String get supportContact => 'التواصل مع الدعم';

  @override
  String supportContactNamed(String name) {
    return 'التواصل مع الدعم ($name)';
  }

  @override
  String get supportDevServiceName => 'مطوّر العميل';

  @override
  String get supportShowOnPc => 'عرض على الكمبيوتر';

  @override
  String get supportCopyPath => 'نسخ المسار';

  @override
  String get supportGenerating => 'جارٍ البناء…';

  @override
  String get supportGenerateButton => 'إنشاء سجل للدعم';

  @override
  String get pingTwoPhaseTitle => 'التحقق من أنه يعمل (عبر النفق)';

  @override
  String get pingTwoPhaseSubOn =>
      'بعد TCP — طلب عبر الخادم: يستبعد غير العاملة (Reality وغيرها)';

  @override
  String get pingTwoPhaseSubOff =>
      'تُستخدم الطريقة الواحدة المحددة (أدناه) فقط';

  @override
  String get pingMethodCheck => 'طريقة التحقق:';

  @override
  String get pingMethodPing => 'طريقة Ping:';

  @override
  String get speedTestProbe => 'مسبار اختبار السرعة:';

  @override
  String get speedTestFull => '20 MB (أكثر دقة)';

  @override
  String get speedTestLight => '5 MB (اقتصادي)';

  @override
  String get testUrlLabel => 'URL الاختبار (عبر البروكسي)';

  @override
  String get appUpdateServerUnavailable => 'خادم التحديث غير متاح';

  @override
  String appUpdateAvailable(String version) {
    return 'الإصدار $version متاح';
  }

  @override
  String get appUpdateLatest => 'لديك أحدث إصدار';

  @override
  String get appUpdateDownload => 'تنزيل';

  @override
  String get appUpdateCheckTitle => 'التحقق من التحديثات عند التشغيل';

  @override
  String get appUpdateManual => 'التنزيل والتثبيت — يدوياً';

  @override
  String get appUpdateEndpointLabel => 'نقطة نهاية الإصدار';

  @override
  String get urlSchemeSilentgateTitle => 'روابط silentgate://';

  @override
  String get urlSchemeSilentgateSub =>
      'الاستيراد والتحكم في VPN عبر الروابط. مُفعَّل افتراضياً';

  @override
  String get urlSchemeDisableTitle => 'تعطيل روابط silentgate://؟';

  @override
  String get urlSchemeDisableBody =>
      'سيتوقف الاستيراد عبر الرابط ومخططات التحكم (اتصال / قطع الاتصال / تبديل / تحديث) عن العمل. اتركه مُفعَّلاً إذا لم تكن متأكداً.';

  @override
  String get urlSchemeDisableOk => 'تعطيل';

  @override
  String get urlSchemeServerTitle => 'فتح روابط الخوادم';

  @override
  String get urlSchemeServerSub => 'اعتراض vless:// وغيرها من العملاء الآخرين';

  @override
  String get urlSchemeServerConfirmTitle => 'اعتراض روابط الخوادم؟';

  @override
  String urlSchemeServerConfirmBody(String schemes) {
    return '$schemes\n\nترتبط هذه الروابط عادةً بعميل VPN آخر (Happ، v2rayTun). سيستولي SilentGate عليها.';
  }

  @override
  String get urlSchemeServerConfirmOk => 'اعتراض';

  @override
  String get urlSchemeAutoConnect => 'الاتصال بعد الاستيراد';

  @override
  String get autoTitle => 'التهيئة التلقائية';

  @override
  String get autoClearResults => 'مسح النتائج';

  @override
  String autoFoundWorking(Object count) {
    return 'العاملة المُكتشَفة: $count';
  }

  @override
  String get autoPinnedTop => ' — مُثبَّتة في أعلى القائمة';

  @override
  String get autoSearchContinues => ' (يستمر البحث…)';

  @override
  String get autoCheckServices => 'فحص الخدمات';

  @override
  String get autoPinFoundOnTop => 'تثبيت الخوادم المُكتشَفة في أعلى القائمة';

  @override
  String get autoTryFragment => 'تجربة التجاوز (fragment)';

  @override
  String get autoNoSubscriptionPasteKey =>
      'لا يوجد اشتراك. الصِق مفتاحاً واحداً — سنعثر على الإعدادات العاملة:';

  @override
  String get autoTuneByKey => 'التهيئة بالمفتاح';

  @override
  String autoTesting(int index, int total) {
    return 'جارٍ الاختبار $index/$total: ';
  }

  @override
  String autoVariant(Object label) {
    return 'المتغيّر: $label';
  }

  @override
  String autoServicesPassed(int ok, int total) {
    return '$ok من $total خدمات';
  }

  @override
  String get autoConnect => 'اتصال';

  @override
  String get autoStopSearch => 'إيقاف البحث';

  @override
  String get autoDoneRefreshPing => 'تم — حدّث Ping المُكتشَفة';

  @override
  String autoFoundPinnedRefreshing(Object count) {
    return 'عُثر على $count، مُثبَّتة في الأعلى. جارٍ تحديث Ping…';
  }

  @override
  String autoServersForTuning(int selected, int total) {
    return 'خوادم للتهيئة ($selected/$total)';
  }

  @override
  String get autoSelectAll => 'الكل';

  @override
  String get autoDeselectAll => 'مسح';

  @override
  String get autoTuneSelected => 'تهيئة المحدَّدة';

  @override
  String autoTuned(Object label) {
    return 'مُهيَّأ: $label';
  }

  @override
  String get infoDialogTitle => 'معلومات';

  @override
  String get infoCopied => 'تم نسخ الشرح';

  @override
  String get commonGotIt => 'فهمت';

  @override
  String get enumSplitAll => 'الكل — عبر VPN';

  @override
  String get enumSplitOnly => 'المحدَّدة فقط — عبر VPN';

  @override
  String get enumSplitExcept => 'المحدَّدة — خارج VPN';

  @override
  String get enumActionTunnel => 'نفق';

  @override
  String get enumActionDirect => 'مباشر';

  @override
  String get enumActionBlock => 'حظر';

  @override
  String homeUpdateAvailable(Object version) {
    return 'الإصدار $version متاح';
  }

  @override
  String get homeDownload => 'تنزيل';

  @override
  String homeSubscriptionUpdated(Object summary) {
    return 'تم تحديث الاشتراك: $summary';
  }

  @override
  String get homeReconnect => 'إعادة الاتصال';

  @override
  String homePingProgress(int done, int total) {
    return 'جارٍ Ping الخوادم: $done من $total';
  }

  @override
  String get homeAutoConfigStarting => 'بدء التهيئة التلقائية…';

  @override
  String homeAutoConfigProgress(int current, int total, String name) {
    return 'التهيئة التلقائية: $current من $total — $name';
  }

  @override
  String get homeImport => 'استيراد';

  @override
  String get homeSettings => 'الإعدادات';

  @override
  String get homeAutoBest => 'تلقائي (أفضل خادم)';

  @override
  String get homeAutoConfig => 'التهيئة التلقائية';

  @override
  String homeServersCount(Object count) {
    return 'الخوادم ($count)';
  }

  @override
  String homeFoundCount(int found, int total) {
    return 'عُثر على $found من $total';
  }

  @override
  String get homePingServers => 'Ping الخوادم';

  @override
  String get homePingFound => 'Ping المُكتشَفة';

  @override
  String get homeNothingFound => 'لم يُعثر على شيء';

  @override
  String get homeOnboardingTitle => 'ابدأ باستيراد اشتراك';

  @override
  String get homeOnboardingSubtitle => 'الصِق رابط Remnawave أو مفتاحاً واحداً';

  @override
  String get homeImportSubscription => 'استيراد اشتراك';

  @override
  String homeSessionTraffic(String down, String up) {
    return 'هذه الجلسة: ↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'GB';

  @override
  String subBarUsage(String used, String total) {
    return '$used من $total';
  }

  @override
  String get subBarSubscription => 'الاشتراك';

  @override
  String get subBarRefreshing => 'جارٍ التحديث…';

  @override
  String get subBarRefreshSubscription => 'تحديث الاشتراك';

  @override
  String get subBarSupport => 'الدعم';

  @override
  String get subBarRefresh => 'تحديث';

  @override
  String get subBarAddSubscription => 'إضافة اشتراك';

  @override
  String get subBarCopyLink => 'نسخ الرابط';

  @override
  String get subBarDeleteSubscription => 'حذف الاشتراك';

  @override
  String get subBarLinkCopied => 'تم نسخ الرابط';

  @override
  String get subBarDeleteConfirmTitle => 'حذف الاشتراك؟';

  @override
  String get subBarDeleteConfirmBody => 'ستُزال خوادم هذا الاشتراك من القائمة.';

  @override
  String subBarDeletePinned(Object count) {
    return 'احذف أيضاً المُثبَّتة ($count) مع تعديلاتها';
  }

  @override
  String get subBarDeletePinnedHint => 'وإلا فستبقى في القائمة وتنجو من الحذف';

  @override
  String get subBarCancel => 'إلغاء';

  @override
  String get subBarDelete => 'حذف';

  @override
  String get subBarSubscriptionDeleted => 'تم حذف الاشتراك';

  @override
  String subBarSubscriptionUpdated(Object summary) {
    return 'تم تحديث الاشتراك: $summary';
  }

  @override
  String get subBarMore => 'التفاصيل';

  @override
  String subBarAdded(Object count) {
    return 'أُضيف ($count)';
  }

  @override
  String subBarRemoved(Object count) {
    return 'أُزيل ($count)';
  }

  @override
  String subBarAutoUpdate(Object hours) {
    return '· تحديث تلقائي $hoursس';
  }

  @override
  String subBarValidPerpetual(Object auto) {
    return 'صالح: غير محدود  $auto';
  }

  @override
  String get subBarExpired => 'انتهى الاشتراك:';

  @override
  String get subBarValidUntil => 'صالح حتى:';

  @override
  String get infoCaptureMode =>
      'كيفية اعتراض حركة المرور. «بروكسي النظام» يضبط بروكسي محلياً في النظام (بدون صلاحيات المسؤول؛ يلتقط المتصفحات ومعظم التطبيقات). «TUN» محوّل شبكة افتراضي يلتقط كل حركة المرور (بما في ذلك UDP والتطبيقات التي تتجاهل البروكسي)، لكنه يتطلب صلاحيات المسؤول.';

  @override
  String get infoSystemProxy =>
      'بروكسي HTTP محلي في إعدادات النظام (سجل WinINET). بدون صلاحيات المسؤول. لا يعترض UDP ولا التطبيقات التي تتجاهل بروكسي النظام.';

  @override
  String get infoTunMode =>
      'نفق كامل عبر محوّل wintun الافتراضي + sing-box. يلتقط كل حركة المرور، بما في ذلك UDP. يطلب صلاحيات المسؤول (UAC) عند التفعيل.';

  @override
  String get infoTunProvider =>
      'برنامج تشغيل محوّل الشبكة الافتراضي. على Windows يُستخدم wintun (مُرفَق مع النواة). لا حاجة إلى برامج تشغيل أخرى.';

  @override
  String get infoTunStack =>
      'حزمة شبكة TUN (sing-box).\n\n«auto» — الاختيار التلقائي: إذا فشل النفق في العمل، يتنقّل التطبيق نفسه عبر system → gvisor → mixed، ثم يخفض MTU (1400، 1280). يُحفظ التركيب الذي نجح ويُجرَّب أولاً في المرة التالية. يظهر تقدّم الاختيار في الحالة وفي السجل.\n\nالاختيار الصريح يعطّل الاختيار التلقائي: system — حزمة نظام التشغيل، الأسرع، لكنها أكثر حساسية مع برامج مكافحة الفيروسات؛ gvisor — في مساحة المستخدم، أبطأ، بأقصى توافق؛ mixed — TCP عبر system، UDP عبر gvisor.';

  @override
  String get infoTunMtu =>
      'الحد الأقصى لحجم الحزمة في محوّل TUN. الافتراضي 1500؛ اخفضه (1400، 1280) إذا واجهت انقطاعات — القيمة الصغيرة جداً تقلّل السرعة.\n\nمع حزمة «auto» هذه مجرد قيمة بداية: إذا فشل النفق في العمل، فسيجرّب التطبيق نفسه قيم MTU أصغر.';

  @override
  String get infoTunStrictRoute =>
      'التوجيه الصارم في sing-box. على Windows يعالج مشكلتين نمطيتين: تسرّبات DNS (يرسل النظام افتراضياً الاستعلامات إلى جميع المحوّلات دفعة واحدة) وأخطاء «الشبكة غير قابلة للوصول». أوقفه فقط إذا كان يعطّل VirtualBox/Hyper-V.';

  @override
  String get infoTunIpv6 =>
      'توجيه IPv6 إلى داخل النفق. إذا أوقفته بينما IPv6 مُفعَّل لدى مزوّد خدمتك، فسيخرج بعض حركة المرور خارج VPN (كاشفاً عنوانك الحقيقي) أو سيتعلّق. أوقفه فقط إذا كانت لديك مشكلات في شبكة IPv6.';

  @override
  String get infoTunEndpointIndependentNat =>
      'وضع NAT لـ UDP. لازم للألعاب والدردشات الصوتية وWebRTC — دونه قد تفشل الاتصالات في التأسيس. عطّله فقط لتوفير الذاكرة.';

  @override
  String get infoTunBypassLan =>
      'الشبكة المحلية (العناوين الخاصة 192.168.*، 10.*، الراوتر، الطابعات، NAS) تلتفّ حول VPN. عادةً تريد هذا مُفعَّلاً، وإلا فقدت الوصول إلى الأجهزة على الشبكة.';

  @override
  String get infoTunExcludeCidrs =>
      'شبكات فرعية إضافية تلتفّ دائماً حول VPN (بتنسيق CIDR، مثل 10.8.0.0/24). مفيدة للشبكات المؤسسية وشبكات VPN الأخرى.';

  @override
  String get infoTunPrivilege =>
      'يتطلب TUN صلاحيات المسؤول. مرة واحدة، نُنشئ مهمة في Windows Task Scheduler بأعلى الصلاحيات — بعدها يبدأ النفق دون طلب UAC في كل اتصال. المهمة ملكك وتُزال بالزر أدناه أو عند إلغاء تثبيت البرنامج.';

  @override
  String get infoAppUpdate =>
      'مرة واحدة في كل تشغيل، يسأل التطبيق خادمك عمّا إذا كان هناك إصدار أحدث ويعرض إشعاراً بزر «تنزيل».\n\nلا ينزّل التطبيق ولا يشغّل أي شيء بنفسه: المُثبِّت غير موقَّع بشهادة، وتشغيل ملف exe مُنزَّل تلقائياً يصطدم بـ SmartScreen ويبدو لبرامج مكافحة الفيروسات كسلوك برمجية خبيثة. تثبّت التحديث بنفسك.\n\nإذا كان الخادم غير متاح، يظل التطبيق صامتاً ويكتب إدخالاً في السجل. تنسيق الاستجابة وإعداد الخادم موصوفان في docs/APP_UPDATE.md.';

  @override
  String get infoSpeedTest =>
      'كمية البيانات المُنزَّلة عند قياس السرعة (انقر بزر الفأرة الأيمن على خادم ← «معلومات الخادم» ← «قياس السرعة»).\n\n20 MB — الوضع الرئيسي: على الوصلات السريعة (100+ ميغابت/ث) لا يجد المسبار القصير وقتاً كافياً لبلوغ الذروة فيقلّل تقدير النتيجة.\n5 MB — الوضع الاقتصادي: أرخص بوضوح على حركة المرور، ومفيد للمرور عبر عدة خوادم.\n\nيُجرى القياس يدوياً فقط ويستهلك حركة مرور اشتراكك. تُقاس السرعة مرتين: مباشرة وعبر الخادم المحدَّد، لترى بالضبط كم يُفقد على VPN.';

  @override
  String get infoAutoReconnect =>
      'إذا تعطّلت النواة، أو سقط الخادم، أو تغيّرت الشبكة (Wi-Fi ↔ كابل، الاستيقاظ من السكون، عنوان IP جديد)، يعيد التطبيق تشغيل الاتصال بنفسه. تتزايد فترات التوقف بين المحاولات: 0.8 ث ← 3 ث ← 8 ث ← 20 ث، حتى 8 محاولات، وبعدها يُعرض خطأ. قطع الاتصال بالزر يلغي الاستعادة دائماً.\n\nيُكتشف تغيّر الشبكة من العناوين الحقيقية للمحوّلات الأخرى: نفقك الخاص وعناوين الخدمة (link-local) لا تُحتسب، ويُقبل التغيّر فقط إذا استمر عبر استطلاعين متتاليين، وتُتجاهل الإشارة في أول 15 ثانية بعد الاتصال. دون هذه الضمانات، سيُحتسب رفع النفق نفسه كـ «تغيّر شبكة» ويسبّب إعادة اتصال لا نهائية.';

  @override
  String get infoKillSwitch =>
      'لا تسمح لحركة المرور بالخروج حول VPN أثناء استعادة الاتصال. لا يُحرَّر الالتقاط بين المحاولات: في وضع TUN يبقى المحوّل قائماً، وفي وضع «بروكسي النظام» يبقى البروكسي مُهيَّأً — فتحصل التطبيقات على خطأ اتصال بدلاً من وصول غير مُشفَّر إلى الإنترنت.\n\nبصراحة عن الحدود: في وضع «بروكسي النظام» يحمي هذا البرامج التي تحترم بروكسي النظام فقط (المتصفحات ومعظم التطبيقات). أما البرامج التي تتجاهل البروكسي، وUDP، فستذهب مباشرة — والإحكام الكامل لا يوفّره إلا وضع TUN. يتطلب تفعيل إعادة الاتصال التلقائية.';

  @override
  String get infoUserAgent =>
      'كيف يعرّف التطبيق نفسه للوحة (ترويسة User-Agent). يرسل دائماً «SilentGate/version (Windows)».\n\nبهذا الاسم تختار لوحة Remnawave تنسيق الاشتراك. XRAY_JSON مطلوب — فهو يسلّم تكوينات خوادم جاهزة؛ أما من قائمة روابط base64 فتُستعاد بعض الإعدادات تقريبياً، ويعمل الاختيار التلقائي (burstObservatory) بشكل أسوأ.\n\nيُهيَّأ في اللوحة: Templates ← Response Rules ← قاعدة بشرط user-agent CONTAINS SilentGate ونوع الاستجابة XRAY_JSON (ضعها فوق قاعدة Fallback Base64).\n\nحقل التجاوز لازم فقط كحل مؤقت — إذا كانت اللوحة لا تعرف التطبيق بعد، يمكنك التعريف كعميل تعرفه.';

  @override
  String get infoDnsMode =>
      'من يحلّ النطاقات في وضع TUN. «عبر VPN» (مُوصى به) — تذهب الاستعلامات إلى النفق عبر TCP، ولا يرى مزوّد خدمتك المواقع التي تفتحها. «النظام» — كما في Windows: تسرّب DNS ممكن، وإذا لم يمرّر الخادم UDP فقد ينقطع الإنترنت كلياً. «مخصّص» — الخادم الذي تحدّده، عبر النفق.';

  @override
  String get infoDnsCustomServer =>
      'عنوان خادم DNS لوضع «مخصّص» (مثلاً 9.9.9.9 أو 8.8.8.8). تذهب الاستعلامات إليه عبر النفق باستخدام TCP.';

  @override
  String get infoDnsHijack =>
      'اعتراض استعلامات DNS (منفذ UDP 53) داخل النفق. دون هذا، تتسلّل الاستعلامات متجاوزةً القواعد: تسرّب ممكن، وتعمل قواعد النطاقات في تقسيم النفق بدقة أقل.';

  @override
  String get infoDnsStrategy =>
      'أي العناوين يُطلَب: prefer_ipv4 (مُوصى به) — IPv4 أولاً، ipv4_only — IPv4 فقط (يصلح مشكلات IPv6 المعطّل)، prefer_ipv6/ipv6_only — لشبكات IPv6.';

  @override
  String get infoSingboxLogLevel =>
      'مستوى تفصيل سجل sing-box (%APPDATA%\\SilentGate\\singbox.log). warn — الوضع العادي. info/debug — إذا لم يعمل النفق: سيُظهر السجل السبب الدقيق. يزيد debug حجم الملف بوضوح.';

  @override
  String get infoSplitMode =>
      'الأساس — إلى أين يذهب كل ما ليس له إجراء مضبوط يدوياً، وأي إجراء يُسنَد للإدخالات الجديدة. «الكل — عبر VPN»: افتراضياً كل حركة المرور إلى النفق. «المحدَّدة فقط — عبر VPN»: افتراضياً مباشرة، وإلى النفق فقط تلك المُعلَّمة بـ «نفق». «المحدَّدة — حول VPN»: العكس، كل شيء إلى النفق، وتذهب المُعلَّمة بـ «مباشر» مباشرة.';

  @override
  String get infoSplitApps =>
      'انقر على تطبيق — تُفتح نافذة تختار فيها الإجراء (نفق — عبر VPN، مباشر — حول VPN، حظر — بلا شبكة) وطريقة المطابقة: باسم exe (موثوق) أو بالمسار الكامل. يمكنك الاختيار من التطبيقات العاملة أو تحديد ملف ‎.exe.';

  @override
  String get infoSplitDomains =>
      'النطاقات (اللواحق). مثلاً، youtube.com يغطي أيضاً www.youtube.com. يعمل بالاسم من اتصال TLS (SNI).';

  @override
  String get infoVerifyViaProxy =>
      'أولاً نتحقق من الأداء عبر البروكسي (يعيد الخادم فعلاً 204)، وفقط إذا استجاب الخادم نقيس زمن الاستجابة بشكل منفصل بالطريقة المختارة (TCP/ICMP).';

  @override
  String get infoProxyGet =>
      'طلب GET عبر النفق إلى URL الاختبار. يتحقق من أن الخادم يمرّر فعلاً حركة المرور ويعيد 204. أصدق اختبار للأداء؛ أبطأ قليلاً.';

  @override
  String get infoProxyHead =>
      'مثل GET، لكن الترويسات فقط — أسرع وحركة مرور أقل. قد لا تدعم بعض الخوادم/شبكات CDN طريقة HEAD.';

  @override
  String get infoTcp =>
      'زمن مصافحة TCP إلى عنوان الخادم. مؤشر سريع ودقيق لزمن الاستجابة، لكنه لا يثبت عمل النفق: سيجيب خادم Reality على TCP حتى لو كان البروكسي محظوراً. مُوصى به لزمن الاستجابة.';

  @override
  String get infoIcmp =>
      'Ping النظام. غالباً غير مفيد لـ Reality/CDN: قد يكون ICMP محظوراً، أو يقيس أقرب عقدة CDN. احتفظ به لتشخيص الشبكة.';

  @override
  String get infoTestUrl =>
      'URL للتحقق من الأداء عبر البروكسي. افتراضياً https://www.gstatic.com/generate_204 — يعيد استجابة 204 فارغة، وهو أمر مريح وسريع.';

  @override
  String get infoAutoConfig =>
      'يمرّ عبر الخوادم ومتغيّرات التجاوز (fragment، fingerprint) ويبني قائمة بتلك التي تعمل فيها الخدمات المختارة. لا يتوقف عند أول واحد — بل تختار من بين المُكتشَفة. يتم الفحص عبر البروكسي؛ ولا يُفعَّل VPN خلال هذا الوقت.';

  @override
  String get infoAutoConfigServices =>
      'أي الخدمات يجب أن تعمل ليُعتبر الخادم مناسباً. الفحص مقاوم لصفحات الحجب الوسيطة لمزوّدي الخدمة (يُتحقق من بصمة الاستجابة، وليس مجرد «200 OK»).';

  @override
  String get infoAutoPinFound =>
      'تُثبَّت التركيبات العاملة المُكتشَفة (خادم + متغيّر تجاوز) فوراً في أعلى قائمة الخوادم العامة، كي تستخدمها دون العودة إلى هنا. أوقفه إذا لم ترد أن تغيّر التهيئة التلقائية ترتيب قائمتك — فستظل النتائج مرئية على هذه الشاشة.';

  @override
  String get infoTryFragment =>
      'جرّب المتغيّر مع تجزئة TLS ClientHello (تجاوز DPI) إذا لم يعمل الخادم «العاري». أطول قليلاً، لكنه يجد تركيباً عاملاً على الخوادم المُقيَّدة.';

  @override
  String get infoAutoStrategy =>
      '«أول عامل» — مرّ عبر كل شيء واتصل بأي واحد مُكتشَف (أنت تختار). «الأفضل ضمن الميزانية» — ابحث ضمن حد زمني واختر الأسرع.';

  @override
  String get infoScheme =>
      'يسجّل بروتوكول silentgate:// في النظام (للمستخدم الحالي، بدون صلاحيات المسؤول). بعد ذلك، النقر على رابط silentgate://import?url=… (استيراد) أو silentgate://connect / toggle (تحكم) في متصفح يفتح التطبيق وينفّذ الإجراء. مُفعَّل افتراضياً.';

  @override
  String get infoAutoConnectAfterImport =>
      'الاتصال بأول خادم فور استيراد الاشتراك بنجاح عبر الرابط.';

  @override
  String get infoNetworkRecover =>
      'يعيد تعيين معاملات الشبكة إذا اختفى الإنترنت بعد تعطّل/إيقاف الكمبيوتر مع تفعيل VPN: winsock، وحزمة IP، وذاكرة DNS المؤقتة، وبروكسي النظام. يتطلب صلاحيات المسؤول؛ تسري إعادة تعيين winsock وحزمة IP بعد إعادة التشغيل.';

  @override
  String get infoInterference =>
      'فحص لشبكات VPN الأخرى وتداخل الشبكة (محوّلات TUN أجنبية، عمليات VPN، zapret/GoodbyeDPI) التي قد تتعارض مع SilentGate. يمكنك إغلاقها أو تجاهلها.';

  @override
  String get pingInfoProxyGet =>
      'طلب GET عبر النفق إلى URL الاختبار. يتحقق من أن الخادم يمرّر فعلاً حركة المرور ويعيد 204. أصدق اختبار للأداء؛ أبطأ قليلاً بسبب تنزيل الاستجابة بالكامل. مُوصى به لفحص الأداء.';

  @override
  String get pingInfoProxyHead =>
      'مثل GET، لكنه يطلب الترويسات فقط — حركة مرور أقل وأسرع. يتحقق من أداء النفق؛ قد لا تدعم بعض الخوادم/شبكات CDN طريقة HEAD.';

  @override
  String get pingInfoTcp =>
      'يقيس زمن مصافحة TCP إلى عنوان الخادم. مؤشر سريع ودقيق لزمن استجابة نقطة النهاية، لكنه لا يثبت أن النفق يعمل: سيجيب خادم Reality على TCP حتى لو كان البروكسي محظوراً. مُوصى به لزمن الاستجابة.';

  @override
  String get pingInfoIcmp =>
      'Ping النظام (طلب صدى). غالباً غير مفيد لـ Reality/CDN: قد يكون ICMP محظوراً، أو يقيس أقرب عقدة CDN بدلاً من الخادم. احتفظ به لتشخيص الشبكة.';

  @override
  String get pingInfoTwoPhase =>
      'بعد فحص TCP، تُفحص الخوادم التي استجابت إضافياً بطلب عبر النفق (GET/HEAD إلى URL الاختبار). هذا يستبعد الخوادم التي تُبقي المنفذ مفتوحاً لكنها لا تمرّر حركة المرور. لا يزال زمن الاستجابة يُعرض بـ TCP.';

  @override
  String get pingInfoTunStage =>
      'النفق الكامل (TUN) هو المرحلة التالية. حالياً يُستخدم وضع «بروكسي النظام». في وضع TUN ستذهب كل حركة المرور (بما في ذلك UDP والتطبيقات التي تتجاهل البروكسي) عبر محوّل wintun الافتراضي + tun2socks. يتطلب صلاحيات المسؤول.';

  @override
  String get pingInfoTunStack =>
      'حزمة شبكة TUN (sing-box). auto — اتركها لتقدير النواة (حالياً mixed). system — حزمة نظام التشغيل: أقصى سرعة، لكنها أكثر حساسية مع الصلاحيات/برامج مكافحة الفيروسات. gvisor — حزمة في مساحة المستخدم: أبطأ، لكنها الأكثر توافقاً. mixed — TCP عبر system، UDP عبر gvisor (توازن). إذا لم يتصل TUN أو أسقط الاتصالات — جرّب gvisor.';

  @override
  String get pingInfoAutoConfig =>
      'عند التفعيل، يمرّ التطبيق نفسه عبر الخوادم ومتغيّرات التجاوز (fragment، fingerprint) ويتصل بأول واحد تعمل فيه الخدمات المختارة (الفحص عبر البروكسي، دون تفعيل VPN أثناء البحث).';

  @override
  String get logsTabApp => 'التطبيق';

  @override
  String get logsTabTun => 'TUN (sing-box)';

  @override
  String get logsRefresh => 'تحديث';

  @override
  String get logsCopy => 'نسخ';

  @override
  String get logsClearApp => 'مسح سجل التطبيق';

  @override
  String get logsCopied => 'تم نسخ السجل';

  @override
  String get logsLoading => 'جارٍ التحميل…';

  @override
  String get logsEmpty => 'فارغ حتى الآن.';

  @override
  String get logsTunEmpty => 'فارغ — لم يُبدأ TUN على هذا النظام بعد.';

  @override
  String get importScrDone => 'تم الاستيراد';

  @override
  String get importScrWelcome => 'مرحباً بك في SilentGate';

  @override
  String get importScrTitle => 'استيراد اشتراك';

  @override
  String get importScrSubscriptionFallback => 'الاشتراك';

  @override
  String get importScrHint =>
      'الصِق رابط اشتراك (Remnawave)، أو رابط silentgate:// عميق، أو رابطاً واحداً vless:// / vmess:// / trojan:// / ss:// / hysteria2://';

  @override
  String get importScrLoading => 'جارٍ التحميل…';

  @override
  String get importScrPasteImport => 'استيراد من الحافظة';

  @override
  String get importScrImportField => 'استيراد من الحقل';

  @override
  String get serversTitle => 'الخوادم';

  @override
  String serversFound(int found, int total) {
    return 'الخوادم — عُثر على $found من $total';
  }

  @override
  String get serversRefresh => 'تحديث الاشتراك';

  @override
  String get serversPinging => 'جارٍ Ping…';

  @override
  String get serversPingAll => 'Ping الكل';

  @override
  String get serversPingFound => 'Ping المُكتشَفة';

  @override
  String get serversEmpty => 'قائمة الخوادم فارغة. استورد اشتراكاً.';

  @override
  String get serversNothingFound => 'لم يُعثر على شيء';

  @override
  String get toastCopied => 'تم النسخ';

  @override
  String get toastHide => 'إخفاء';

  @override
  String get srvInfoTitle => 'معلومات الخادم';

  @override
  String srvInfoProbeFailed(Object error) {
    return 'فشل بدء اتصال الاختبار: $error';
  }

  @override
  String get srvInfoServerAddressFailed => 'تعذّر تحديد عنوان الخادم';

  @override
  String get srvInfoSectionExit => 'من أين تخرج';

  @override
  String get srvInfoExitHint => 'يُحدَّد من عنوان الخادم — ولا يُبدأ نفق لهذا.';

  @override
  String get srvInfoAddressLocation => 'عنوان الخادم وموقعه';

  @override
  String get srvInfoCheckAgain => 'فحص مجدداً';

  @override
  String get srvInfoSectionSpeed => 'السرعة';

  @override
  String srvInfoSpeedHint(Object size) {
    return 'ينزّل المسبار $size ويستخدم حركة مرور اشتراكك. يمكن تغيير الحجم في الإعدادات.';
  }

  @override
  String get srvInfoViaServer => 'عبر الخادم';

  @override
  String get srvInfoWithoutVpn => 'بدون VPN';

  @override
  String get srvInfoMeasuring => 'جارٍ القياس…';

  @override
  String get srvInfoMeasureSpeed => 'قياس السرعة';

  @override
  String get srvInfoSectionParams => 'معاملات الاتصال';

  @override
  String get srvInfoParamAddress => 'العنوان';

  @override
  String get srvInfoParamProtocol => 'البروتوكول';

  @override
  String get srvInfoParamTransport => 'النقل';

  @override
  String get srvInfoParamTlsFingerprint => 'بصمة TLS';

  @override
  String get srvInfoParamType => 'النوع';

  @override
  String get srvInfoPanelAutoProfile => 'ملف الاختيار التلقائي من اللوحة';

  @override
  String get srvInfoCouldNotDetermine => 'تعذّر التحديد';

  @override
  String get srvInfoCopy => 'نسخ';

  @override
  String get editorJsonTitle => 'تكوين JSON';

  @override
  String get editorCopy => 'نسخ';

  @override
  String get editorClose => 'إغلاق';

  @override
  String get editorTitle => 'تعديل الخادم';

  @override
  String get editorFieldName => 'الاسم';

  @override
  String get editorFieldAddress => 'العنوان';

  @override
  String get editorFieldPort => 'المنفذ';

  @override
  String get editorFieldUuidPassword => 'UUID / كلمة المرور';

  @override
  String get editorFieldObfs => 'التمويه (عادةً salamander)';

  @override
  String get editorFieldObfsPassword => 'كلمة مرور التمويه';

  @override
  String get editorFieldPortHopping => 'تنقّل المنافذ (مثلاً 20000-21000)';

  @override
  String get editorAllowSelfSigned => 'السماح بشهادة موقّعة ذاتياً';

  @override
  String get editorAllowSelfSignedSub =>
      'لازم فقط إذا كان الخادم مُهيَّأً هكذا';

  @override
  String get editorTransport => 'النقل';

  @override
  String get editorSecurity => 'الأمان';

  @override
  String get editorNone => '(بلا)';

  @override
  String get editorCancel => 'إلغاء';

  @override
  String get editorSave => 'حفظ';

  @override
  String jsonProfileServers(int count, String burst) {
    return '$count خوادم$burst';
  }

  @override
  String get jsonCompositionUnknown => 'التركيب غير معروف';

  @override
  String get jsonYourSavedOverride => 'JSON المحفوظ لديك (تجاوز)';

  @override
  String jsonPanelProfileApplied(Object summary) {
    return 'ملف الاختيار التلقائي من اللوحة: $summary — مُطبَّق بالكامل';
  }

  @override
  String get jsonPanelConfig => 'تكوين من اللوحة (XRAY_JSON)';

  @override
  String get jsonBuiltFromShareLink =>
      'مبني من رابط المشاركة — لم ترسل اللوحة JSON. حدّث الاشتراك؛ وإذا لم يساعد ذلك، فتحقق من قاعدة Response Rules في اللوحة.';

  @override
  String get jsonInvalidJson => 'JSON غير صالح';

  @override
  String get jsonSaved => 'تم الحفظ';

  @override
  String get jsonTitle => 'تكوين JSON';

  @override
  String get jsonFieldEditor => 'محرّر الحقول';

  @override
  String get jsonCopy => 'نسخ';

  @override
  String get jsonClose => 'إغلاق';

  @override
  String get jsonSave => 'حفظ';

  @override
  String get srvTileEdit => 'تعديل';

  @override
  String get srvTileNotice => 'إشعار';

  @override
  String get srvTileRefresh => 'تحديث';

  @override
  String get srvTileSubscriptionUpdated => 'تم تحديث الاشتراك';

  @override
  String get srvTileCopy => 'نسخ';

  @override
  String get srvTileInfo => 'معلومات الخادم';

  @override
  String get srvTilePing => 'Ping';

  @override
  String get srvTileUnpin => 'إلغاء التثبيت';

  @override
  String get srvTilePin => 'تثبيت';

  @override
  String get srvTileJsonConfig => 'تكوين JSON';

  @override
  String get srvTileSmart => 'تهيئة ذكية للمعاملات';

  @override
  String get srvTileDelete => 'حذف';

  @override
  String get srvTileServerDeleted => 'تم حذف الخادم';

  @override
  String get srvTileSaved => 'تم الحفظ';

  @override
  String get pingNa => 'غير متاح';

  @override
  String get pingNaTooltip => 'لا استجابة TCP — الخادم غير متاح (ميت)';

  @override
  String get pingTimeout => 'انتهت المهلة';

  @override
  String get pingTimeoutTooltip =>
      'لم يكتمل مسبار TCP خلال المهلة — الخادم غير متاح';

  @override
  String pingMs(Object ms) {
    return '$ms م.ث';
  }

  @override
  String get pingNoProxy => 'لا بروكسي';

  @override
  String get pingNoProxyTooltip =>
      'يستجيب عبر TCP (زمن الاستجابة معروض)، لكن فحص النفق (GET/HEAD) فشل — حركة المرور لا تمرّ';

  @override
  String get pingOk => 'سليم';

  @override
  String get pingOkTooltip =>
      'زمن استجابة TCP إلى الخادم. الخادم يعمل: استجاب عبر TCP واجتاز فحص النفق (GET/HEAD)';

  @override
  String get searchHint => 'بحث بالاسم، البلد، العنوان…';

  @override
  String get searchReset => 'مسح';

  @override
  String get splitTitle => 'تقسيم النفق';

  @override
  String get splitTunOnlyBanner =>
      'يعمل في وضع TUN فقط. في وضع «بروكسي النظام»، تقرّر التطبيقات بنفسها ما إذا كانت ستستخدم البروكسي — ولا يمكن إجبارها.';

  @override
  String get splitEnableTun => 'تفعيل TUN';

  @override
  String get splitModeHeader => 'الوضع';

  @override
  String get splitAppsHeader => 'التطبيقات';

  @override
  String get splitAppsHint =>
      'انقر على تطبيق لضبط إجرائه (نفق / مباشر / حظر) وطريقة المطابقة. مربع الاختيار المجاور يفعّل/يعطّل القاعدة.';

  @override
  String get splitByName => 'بالاسم';

  @override
  String get splitByPath => 'بالمسار';

  @override
  String get splitRuleDisabled => 'معطّل — القاعدة غير مُطبَّقة';

  @override
  String get splitRemove => 'إزالة';

  @override
  String get splitFromRunning => 'من العاملة';

  @override
  String get splitPickInstalled => 'اختر تطبيقًا';

  @override
  String get splitInstalledApps => 'التطبيقات المثبتة';

  @override
  String get splitPickExe => 'اختيار ‎.exe';

  @override
  String get splitSitesHeader => 'المواقع (النطاقات)';

  @override
  String get splitSitesHint =>
      'انقر على موقع لاختيار إجراء (نفق / مباشر / حظر). يغطي النطاق أيضاً نطاقاته الفرعية؛ وتُجمَّع النطاقات الفرعية في شجرة. يمكنك تحديد منفذ.';

  @override
  String splitOnlyPort(Object port) {
    return 'المنفذ $port فقط';
  }

  @override
  String get splitProgramsFileType => 'البرامج';

  @override
  String get splitRunningApps => 'التطبيقات العاملة';

  @override
  String get splitSearchByName => 'بحث بالاسم';

  @override
  String get splitNothingFound => 'لم يُعثر على شيء';

  @override
  String get splitClose => 'إغلاق';

  @override
  String get splitPortRange => 'المنفذ 1–65535';

  @override
  String get splitAction => 'الإجراء';

  @override
  String get splitPortOptional => 'المنفذ (اختياري)';

  @override
  String get splitAnyPort => 'أي';

  @override
  String get splitPortHelper =>
      'فارغ = أي منفذ. وإلا تُطبَّق القاعدة على هذا المنفذ فقط';

  @override
  String get splitMatching => 'المطابقة';

  @override
  String get splitByNameSubtitle => 'اسم exe، بغض النظر عن الموقع (موثوق)';

  @override
  String get splitByPathSubtitle => 'المسار الكامل إلى exe (تطابق تام)';

  @override
  String get splitDone => 'تم';

  @override
  String get splitEnterDomain => 'أدخل نطاقاً';

  @override
  String get splitAddSite => 'إضافة موقع';

  @override
  String get splitPort => 'المنفذ';

  @override
  String get splitAdd => 'إضافة';

  @override
  String get routeBlock => 'حظر';

  @override
  String get routeBlocked => 'محظور';

  @override
  String get routeYourPc => 'جهازك';

  @override
  String get routeTunnel => 'نفق';

  @override
  String get routeViaVpn => 'عبر VPN';

  @override
  String get routeVpn => 'VPN';

  @override
  String get routeInternet => 'الإنترنت';

  @override
  String get routeRest => 'كل ما تبقّى';

  @override
  String get routeDirectly => 'مباشرة';

  @override
  String get routeDirectPlusRest => 'مباشر + الباقي';

  @override
  String get routeDirect => 'مباشر';

  @override
  String get routeEmptyList => 'القائمة فارغة';

  @override
  String get trayShow => 'عرض';

  @override
  String get trayToggle => 'اتصال / قطع الاتصال';

  @override
  String get trayQuit => 'خروج';

  @override
  String get trayMinimizeTitle => 'التصغير إلى شريط المهام';

  @override
  String get trayMinimizeBody => 'سيستمر التطبيق في العمل في شريط المهام.';

  @override
  String get trayDontAsk => 'لا تسأل مجدداً';

  @override
  String get trayMinimizeOk => 'تصغير';

  @override
  String get trayVpnTitle => 'VPN متصل';

  @override
  String get trayVpnBody => 'قطع اتصال VPN والخروج من التطبيق؟';

  @override
  String get trayStay => 'البقاء';

  @override
  String get trayQuitVpn => 'قطع الاتصال والخروج';

  @override
  String get tunTaskDone => 'تم: سيبدأ TUN دون طلب UAC';

  @override
  String get tunTaskFailed => 'فشل إنشاء المهمة (رُفض UAC أو مُنع بالسياسة)';

  @override
  String get tunLogTitle => 'سجل TUN (sing-box)';

  @override
  String get tunLogEmpty => 'السجل فارغ — لم يبدأ النفق بعد.';

  @override
  String get tunCopy => 'نسخ';

  @override
  String get tunClose => 'إغلاق';

  @override
  String get tunTitle => 'TUN والتوجيه';

  @override
  String get tunSectionPrivilege => 'صلاحيات المسؤول';

  @override
  String get tunChecking => 'جارٍ الفحص…';

  @override
  String get tunNoUacConfigured => 'البدء دون UAC مُهيَّأ';

  @override
  String get tunUacEachConnect => 'سيُطلب UAC في كل اتصال';

  @override
  String get tunTaskSubtitle =>
      'مهمة في Windows Task Scheduler بأعلى الصلاحيات (تُنشأ مرة واحدة).';

  @override
  String get tunRecreateTask => 'إعادة إنشاء المهمة';

  @override
  String get tunSetupOneUac => 'إعداد (UAC واحد)';

  @override
  String get tunRemoveTask => 'إزالة المهمة';

  @override
  String get tunSectionAdapter => 'المحوّل';

  @override
  String get tunStack => 'حزمة TUN';

  @override
  String get tunSectionRouting => 'التوجيه';

  @override
  String get tunStrictRoute => 'التوجيه الصارم (strict_route)';

  @override
  String get tunIpv6 => 'IPv6 في النفق';

  @override
  String get tunEndpointNat => 'NAT مستقل عن نقطة النهاية (UDP، الألعاب)';

  @override
  String get tunLanBypass => 'الشبكة المحلية تتجاوز VPN';

  @override
  String get tunDnsServer => 'خادم DNS';

  @override
  String get tunDnsHijack => 'اعتراض DNS (المنفذ 53)';

  @override
  String get tunResolveStrategy => 'استراتيجية التحليل';

  @override
  String get tunSectionDiagnostics => 'التشخيص';

  @override
  String get tunSingboxLogLevel => 'مستوى سجل sing-box';

  @override
  String get tunShowLog => 'عرض سجل TUN';

  @override
  String get tunDnsVpn => 'عبر VPN (مُوصى به)';

  @override
  String get tunDnsSystem => 'النظام';

  @override
  String get tunDnsCustom => 'خادم مخصّص';

  @override
  String get tunDnsVpnHint => 'تذهب الطلبات إلى النفق عبر TCP — بلا تسرّبات';

  @override
  String get tunDnsSystemHint => 'كما في Windows: تسرّب DNS ممكن';

  @override
  String get tunDnsCustomHint => 'الخادم المحدَّد، أيضاً عبر النفق';

  @override
  String get tunExcludeSubnets => 'شبكات فرعية تتجاوز VPN';

  @override
  String get tunAdd => 'إضافة';

  @override
  String get urlGroupImport => 'استيراد';

  @override
  String get urlGroupControl => 'التحكم';

  @override
  String get urlHintSubUrl => 'URL الاشتراك';

  @override
  String get urlHintServerLink => 'رابط الخادم';

  @override
  String get urlDescImportSub => 'استيراد اشتراك';

  @override
  String get urlDescImportServer =>
      'إضافة خادم واحد (vless / trojan / ss / hysteria2 …)';

  @override
  String get urlDescConnect => 'اتصال VPN';

  @override
  String get urlDescDisconnect => 'قطع اتصال VPN';

  @override
  String get urlDescToggle => 'تبديل VPN';

  @override
  String get urlDescUpdate => 'تحديث الاشتراك النشط';

  @override
  String get urlSupportedImport =>
      'عند الاستيراد يفهم التطبيق: URL اشتراك (http/https)، وخوادم مفردة vless:// / vmess:// / trojan:// / ss:// / hysteria2:// (hy2://).';

  @override
  String get reportTitle => 'SilentGate — تقرير الدعم';

  @override
  String get reportDescribeHere =>
      '>>> صِف المشكلة هنا (املأ واحفظ الملف): <<<';

  @override
  String get reportWhatDid => 'ما الذي فعلته:';

  @override
  String get reportWhatExpected => 'ما الذي توقّعته:';

  @override
  String get reportWhatHappened => 'ما الذي حدث:';

  @override
  String get reportWhenStarted => 'متى بدأت:';

  @override
  String get reportTechNoticeLine1 =>
      'أدناه معلومات تقنية. راجعها قبل الإرسال؛';

  @override
  String get reportTechNoticeLine2 =>
      'لا توجد هنا كلمات مرور أو رمز اشتراك، وURL الاشتراك مخفي.';

  @override
  String get noRealIpTitle => 'لا تستخدم عنوان IP الحقيقي أبدًا';

  @override
  String get noRealIpSub =>
      'حتى مع تشغيل VPN، تمر كل حركة المرور «المباشرة» عبر VPN (بما في ذلك مواقع RU). تبقى الشبكة المحلية مباشرة.';

  @override
  String get flagAuto => 'تلقائي';

  @override
  String get autoUpdateIntervalLabel => 'فاصل التحديث، ساعة';

  @override
  String get autoUpdatePreferSub => 'استخدام الفاصل من الاشتراك';

  @override
  String get pingLegendInfo =>
      'لون شارة ping: أخضر/أصفر/برتقالي — الخادم يعمل (TCP + فحص عبر النفق). رمادي — يستجيب عبر TCP لكنه لا يمرر حركة المرور (منفذ Reality نموذجي). أحمر «n/a» — لا استجابة، مُستبعَد. يُقاس ping دائمًا مباشرةً (خارج VPN).';

  @override
  String get pingUntestedHint =>
      'لم يُختبر بعد. على الهاتف، يُقاس Hysteria2 وملفات «تلقائي» أثناء الاتصال فقط.';

  @override
  String get panelTunnelMarker => 'له نفق مقسّم خاص به';

  @override
  String panelInfoServers(Object n) {
    return 'الخوادم في الملف: $n (يُختار الأفضل)';
  }

  @override
  String get panelInfoDirect =>
      'بعض حركة المرور (مثل المواقع المحلية) تمر مباشرة خارج VPN';

  @override
  String get panelInfoBlock => 'بعض حركة المرور محظورة (الإعلانات/التورنت)';

  @override
  String get serviceChecksTitle => 'فحص الخدمات';

  @override
  String get serviceChecksInfo =>
      'اضغط على خدمة للتحقق مما إذا كانت تُفتح عبر اتصال VPN النشط. الفحص يدوي — لا شيء يُفحص تلقائيًا. لخدمات الذكاء الاصطناعي يُكتشف أيضًا الحظر حسب بلد الخروج.';

  @override
  String get serviceStatusOk => 'تعمل';

  @override
  String get serviceStatusGeo => 'تُفتح لكنها محظورة في بلد الخروج';

  @override
  String get serviceStatusFail => 'لا تُفتح';

  @override
  String get serviceStatusChecking => 'جارٍ الفحص…';

  @override
  String get serviceStatusTap => 'اضغط للفحص';

  @override
  String serviceLatencyMs(Object ms) {
    return '$ms مللي ثانية';
  }

  @override
  String get homeTunAutotuneProgress => 'جارٍ ضبط معلمات TUN…';

  @override
  String get homeTunAutotuneDone => 'تم ضبط معلمات TUN';

  @override
  String get homeTunAutotuneFailed => 'تعذّر ضبط معلمات TUN';

  @override
  String get hy2NoteTitle => 'خوادم Hysteria2';

  @override
  String get hy2NoteBody =>
      'تصل خوادم Hysteria2 بصيغة XRAY_JSON فقط — يطلب SilentGate هذه الصيغة تحديدًا، و sing-box يشغّلها تلقائيًا. إذا لم يظهر Hysteria2 في القائمة: (لمالك لوحة Remnawave) فعّل مداخل hysteria وعيّنها للاشتراك. ملاحظة: قبل 2.8.0 يقدّم Remnawave خدمة Hysteria2 في XRAY_JSON فقط — وهي غير موجودة في base64/CLASH/SINGBOX، لذا قاعدة Response Rules → XRAY_JSON أعلاه إلزامية.';

  @override
  String get enumStatusDisconnected => 'غير متصل';

  @override
  String get enumStatusConnecting => 'جارٍ الاتصال…';

  @override
  String get enumStatusConnected => 'متصل';

  @override
  String get enumStatusDisconnecting => 'جارٍ قطع الاتصال…';

  @override
  String get enumStatusError => 'خطأ';

  @override
  String get enumVariantPlain => 'عادي';

  @override
  String get tagAutoSelect => 'تلقائي';

  @override
  String get tagPanel => 'اللوحة';

  @override
  String get tagPortHopping => 'تبديل المنافذ';

  @override
  String syncServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count خادم',
      many: '$count خادمًا',
      few: '$count خوادم',
      two: 'خادمان',
      one: 'خادم واحد',
      zero: '$count خادم',
    );
    return '$_temp0';
  }

  @override
  String get syncNoChanges => 'بدون تغييرات';

  @override
  String get errInvalidJson => 'JSON غير صالح';

  @override
  String get errPickServerFirst => 'اختر خادمًا أولاً';

  @override
  String get errImportSubscriptionFirst => 'استورد اشتراكًا أولاً';

  @override
  String get speedSizeFull => '20 ميغابايت';

  @override
  String get speedSizeLight => '5 ميغابايت';

  @override
  String speedMbPerSec(String value) {
    return '$value ميغابايت/ث';
  }

  @override
  String speedKbPerSec(String value) {
    return '$value كيلوبايت/ث';
  }

  @override
  String portBusyTitle(int port, String by) {
    return 'المنفذ $port مستخدم بالفعل بواسطة $by.';
  }

  @override
  String get srvTileMenu => 'إجراءات الخادم';

  @override
  String get supportCopyReport => 'نسخ التقرير';

  @override
  String get supportReportCopied => 'تم نسخ التقرير — الصقه في محادثة الدعم';

  @override
  String subBarUsedOnly(String used) {
    return 'المستخدم $used';
  }

  @override
  String get subBarUnlimitedTraffic => 'حركة بيانات غير محدودة';

  @override
  String get supportDescribeLabel => 'صِف المشكلة';

  @override
  String get supportDescribeHint =>
      'ما الذي فعلته، وما توقعته، وما حدث، ومتى بدأ';

  @override
  String get supportDescribeRequired =>
      'صِف المشكلة — التقرير بدون وصف عديم الفائدة';

  @override
  String get supportNoScreenshots =>
      'لا تلصق لقطات الشاشة هنا — أرسلها في رسالة منفصلة في محادثة تيليجرام.';

  @override
  String get supportDescriptionSection => 'وصف المستخدم';

  @override
  String get splitAllowRealIp => 'السماح بعنوان IP الحقيقي';

  @override
  String get splitAllowRealIpOn =>
      'تتجاوز هذه القاعدة الشبكة الافتراضية — سيرى الموقع عنوانك الحقيقي';

  @override
  String get splitAllowRealIpOff =>
      'هذه القاعدة محمية — تمر عبر الشبكة الافتراضية';

  @override
  String get splitRealIpExposed => 'IP حقيقي';

  @override
  String get splitRealIpProtected => 'عبر VPN';

  @override
  String get vpnActiveBadge => 'الشبكة الافتراضية نشطة';

  @override
  String get splitCopyDomain => 'نسخ العنوان';

  @override
  String get splitCopyPath => 'نسخ المسار';

  @override
  String get homeServerInfo => 'معلومات الخادم';

  @override
  String get serverInfoVerifyInBrowser => 'تحقق في المتصفح';
}
