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
  String get captureProxyOnly => 'بروكسي فقط';

  @override
  String get captureProxyOnlySub =>
      'المحرك يعمل والمنافذ المحلية تستمع، لكن الحاسوب ليس داخل النفق: لا يمر عبر الـVPN إلا ما يشير صراحةً إلى بروكسينا';

  @override
  String get apiSectionTitle => 'واجهة برمجية للأتمتة';

  @override
  String get apiEnableTitle => 'تفعيل الواجهة البرمجية المحلية';

  @override
  String apiEnableSub(int port) {
    return 'HTTP على 127.0.0.1:$port — التحكم بالعميل من نصوص برمجية';
  }

  @override
  String get apiTokenTitle => 'الرمز المميز';

  @override
  String get apiTokenUnset => 'غير مضبوط — لن تعمل الواجهة البرمجية';

  @override
  String get apiTokenRegenerate => 'تجديد الرمز';

  @override
  String get apiTokenWarning =>
      'يُخزَّن الرمز في ملف الإعدادات كنص عادي وينتهي به المطاف في النسخ الاحتياطية. من يملكه يمكنه تبديل الخادم وقراءة حالة الاشتراك.';

  @override
  String get apiExitsTitle => 'خوادم بمنفذ مخصص';

  @override
  String get apiExitsSub =>
      'يحصل كل خادم على منفذ محلي خاص به — يمر الطلب الموجَّه إليه عبر هذا الخادم';

  @override
  String get apiCopyPythonExample => 'نسخ مثال بايثون';

  @override
  String apiPortsHint(int control, int direct, int first) {
    return 'التحكم — المنفذ $control. «مباشر» — المنفذ $direct. الخوادم — بدءًا من $first.';
  }

  @override
  String get apiRulesInProxyOnly => 'تطبيق قواعد تقسيم النفق';

  @override
  String get apiRulesInProxyOnlySub =>
      'في هذا الوضع لا تُطبَّق القواعد الافتراضية على أي برنامج. فعّل هذا إذا أردت أن تشمل قائمة «حظر» الطلبات المرسلة عبر المنافذ المحلية أيضًا.';

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
      'تُفحص ست خدمات شائعة تلقائيًا: أولًا عند تشغيل التطبيق وVPN مُطفأ، ثم مرة أخرى فور الاتصال. النقطتان تُظهران «قبل ← بعد» لترى ما غيّره VPN فعلًا. اضغط لإعادة الفحص. أخضر: يفتح، برتقالي: حجب حسب الدولة، أحمر: غير متاح.';

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
  String get splitAllowRealIp => 'السماح بالعنوان الحقيقي لهذه القاعدة';

  @override
  String get splitAllowRealIpOn =>
      'مُفعَّل: هذا استثناء، وستخرج الحركة بعنوانك الحقيقي';

  @override
  String get splitAllowRealIpOff =>
      'مُطفأ: تمر القاعدة عبر VPN — الحماية فوق كل القواعد';

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

  @override
  String get tunDnsForAll => 'DNS لكل التطبيقات عبر VPN';

  @override
  String get infoDnsForAll =>
      'يعمل فقط في وضع «المحددة فقط». ⚠️ يُطبَّق بعد إعادة الاتصال.';

  @override
  String get homeSettingsNeedReconnect => 'تغيّر الإعداد — أعد الاتصال للتطبيق';

  @override
  String blockPageWindowTitle(String app) {
    return 'محظور — $app';
  }

  @override
  String get blockPageHeading => 'الموقع محظور';

  @override
  String blockPageBody(String host, String app) {
    return 'العنوان $host محظور بقاعدة النفق المقسّم في $app.';
  }

  @override
  String get blockPageHint =>
      'يمكنك تغيير القاعدة: الإعدادات ← النفق المقسّم ← المواقع.';

  @override
  String get blockPageNote =>
      'هذه الصفحة من التطبيق نفسه وليست خطأ في الشبكة. الموقع لا يفتح لأنك أضفته بنفسك إلى قائمة الحظر.';

  @override
  String get settingsBlockPage => 'صفحة إشعار الحظر';

  @override
  String get settingsBlockPageSub =>
      'بدلاً من خطأ الاتصال، تُفتح صفحة تشرح أي قاعدة أغلقت الموقع. تعمل مع http فقط: لا يمكن استبدال صفحة https دون تثبيت شهادة جذر خاصة بنا في النظام، وهذه الشهادة ستتيح قراءة كل حركة مرورك المشفّرة.';

  @override
  String get trayCloseFully => 'إغلاق كامل';

  @override
  String errorVpnConflictApp(String app) {
    return 'يبدو أن $app يعترض الطريق: لديه نفق VPN خاص به قيد التشغيل. نفقان في وقت واحد يتنازعان على المسار الافتراضي.';
  }

  @override
  String errorCloseApp(String app) {
    return 'إغلاق $app';
  }

  @override
  String toastAppClosed(String app) {
    return 'تم إغلاق $app';
  }

  @override
  String toastAppCloseFailed(String app) {
    return 'تعذّر إغلاق $app — أغلقه يدويًا';
  }

  @override
  String get tunBlockQuic => 'حظر QUIC (HTTP/3)';

  @override
  String get infoBlockQuic =>
      'قواعد المواقع تعتمد على الاسم، والتطبيق لا يرى الاسم إلا في TLS العادي. المتصفح الذي ينتقل إلى HTTP/3 لا يُظهر الاسم، فلا تعمل قاعدة النطاق بصمت. الحظر يعيد المتصفح إلى اتصال عادي يظهر فيه الاسم. المواقع تبقى تعمل: HTTP/3 اختياري لها، وإن كان الفيديو قد يُحمَّل أبطأ قليلاً.';

  @override
  String get tunBlockEncryptedDns => 'حظر DNS المشفّر (DoH/DoT)';

  @override
  String get infoBlockEncryptedDns =>
      'تستطيع المتصفحات وويندوز تحويل العناوين عبر HTTPS متجاوزةً اعتراضنا، فلا تعمل قواعد «مباشر» و«حظر» على مستوى DNS إطلاقًا. ⚠️ إذا كان المتصفح مضبوطًا على مزوّد DNS مشفّر ثابت، فلن يعود إلى DNS العادي بل سيتوقف عن فتح المواقع. قائمة المزوّدين المعروفين ناقصة بطبيعتها.';

  @override
  String get autoUseSpeed => 'مراعاة السرعة';

  @override
  String get infoAutoUseSpeed =>
      'بعد الفرز حسب الخدمات وزمن الاستجابة، تُختبر أفضل ثلاثة مرشحين بالتنزيل ويتصدّر الأسرع فعليًا. تُقارن السرعة بقناتك أنت: الخادم الذي يمنحك معظمها لا يُقيَّم بعدها بالميغابت، بل يحسم زمن الاستجابة. ⚠️ يستهلك من حصة الاشتراك: 5 ميغابايت لقناتك و5 لكل مرشح، نحو 20 ميغابايت للجولة.';

  @override
  String get autoSpeedOwn => 'أقيس سرعة قناتك…';

  @override
  String autoSpeedServer(String server, int index, int total) {
    return 'قياس السرعة: $server ($index من $total)';
  }

  @override
  String autoSpeedShare(int percent) {
    return '$percent٪ من قناتك';
  }

  @override
  String get conflictDialogTitle => 'تم اكتشاف VPN آخر';

  @override
  String conflictDialogBody(String app) {
    return 'يبدو أن $app يعمل بنفق خاص به. نفقان في وقت واحد يتنازعان على المسار الافتراضي، وقد يفشل الاتصال أو يعمل دون وصول إلى الشبكة.';
  }

  @override
  String get conflictCloseAndConnect => 'إغلاقه والاتصال';

  @override
  String get conflictConnectAnyway => 'الاتصال على أي حال';

  @override
  String get serviceChecksLegendBefore => 'جرى الفحص من دون VPN';

  @override
  String get serviceChecksLegendAfter => 'يسارًا — دون VPN، يمينًا — عبر VPN';

  @override
  String get serviceChecksBefore => 'دون VPN';

  @override
  String get serviceChecksAfter => 'عبر VPN';

  @override
  String get serviceChecksNoBaseline => 'لم يُفحص دون VPN';

  @override
  String autoSpeedValue(String value) {
    return '$value ميغابت/ث';
  }

  @override
  String get splitShowBlockPage => 'عرض صفحة الحظر';

  @override
  String get splitBlockPageNeedsVpn =>
      'صفحة الحظر تعمل فقط عندما يكون VPN مُفعّلًا';

  @override
  String get srvInfoNeedsConnection =>
      'القياس عبر الخادم على هذه المنصة يتطلب تشغيل VPN';

  @override
  String get serviceYoutubeThrottleNote =>
      '⚠️ لا يكشف هذا الفحص إبطاء YouTube: المزوّد يستجيب بشكل طبيعي لكنه يحدّ من سرعة الفيديو. الأخضر يعني «الخدمة متاحة» لا «الفيديو يعمل».';

  @override
  String get urlSchemeConnectServer =>
      'silentgate://connect?server=<اسم الخادم>';

  @override
  String get urlDescConnectServer =>
      'الاتصال بخادم محدَّد. الاسم هو الظاهر في القائمة والذي يرسله الاشتراك، مثل «بولندا 1.5». يمكن حذف رموز العلم وحالة الأحرف. إن لم يوجد تطابق تام يعمل البحث: حسب البلد أو العنوان أو البروتوكول. يعمل مع toggle أيضًا.';

  @override
  String get splitSelectAllFound => 'تحديد كل ما وُجد';

  @override
  String splitAddSelected(int count) {
    return 'إضافة ($count)';
  }

  @override
  String get splitQuicNote =>
      'ما دامت هناك قاعدة موقع واحدة على الأقل، يعطّل التطبيق HTTP/3 (QUIC) لكل حركة المرور. وإلا ينتقل المتصفح إلى HTTP/3 ولا يترك اسم الموقع، فتفشل القاعدة بصمت. المواقع تظل تعمل: تعود إلى TLS العادي، أبطأ قليلًا فقط.';

  @override
  String get splitNoRealIpBanner =>
      '«لا تستخدم عنواني الحقيقي» مُفعَّل: قواعد «مباشر» بلا علامة تمر عبر VPN';

  @override
  String get settingsNoRealIpAffects =>
      'يؤثر على قواعد «مباشر»: بدون خيار «السماح بالعنوان الحقيقي» ستمر عبر VPN';

  @override
  String get splitAppOverrideSites => 'أولوية على قواعد المواقع';

  @override
  String get splitAppOverrideSitesSub =>
      'كل حركة التطبيق تتبع هذه القاعدة حتى لو قال موقع غير ذلك';

  @override
  String get settingsMyRulesOverridePanel => 'قواعدي أهم من قواعد اللوحة';

  @override
  String get settingsMyRulesOverridePanelSub =>
      'ترسل اللوحة توجيهها الخاص، عادةً «المواقع المحلية خارج VPN». يُطبَّق بعد قواعدك، لذا قد يخرج موقع وسمته «نفق» مباشرةً بعنوانك الحقيقي. مُفعَّل: النفق يعني النفق. الثمن: المواقع المحلية تسلك طريقًا أطول وتبطؤ.';

  @override
  String get commonOpen => 'فتح';

  @override
  String get tunRouteOnlySubnets => 'إلى النفق هذه الشبكات الفرعية فقط';

  @override
  String get infoTunRouteOnlyCidrs =>
      'الطريقة الوحيدة على Windows لجعل جزء من حركة المرور مستقلاً فعلياً عن عميل VPN.\n\nعادةً يستحوذ النفق على المسار الافتراضي، فتدخل إليه كل حركة مرور الجهاز: تُعالَج علامة «مباشر» داخل النواة نفسها، فهي تستقبل الحزمة ثم تُخرجها إلى الشبكة باسمها هي. تعيش هذه الحركة بقدر ما تعيش النواة، وتتعلّق معها إذا تعلّقت.\n\nإذا لم تكن القائمة فارغة، فلن يحصل النفق على المسار الافتراضي: يأخذ الشبكات الفرعية المذكورة فقط، ويرسل النظام كل ما عداها عبر المحوّل العادي — ولا يرى التطبيق هذه الحركة إطلاقاً.\n\nالثمن: التقسيم هنا يجري بالعنوان، بينما تعمل قواعد التطبيقات والمواقع بالاسم. الموقع الذي لا يقع عنوانه ضمن القائمة لن تراه النواة بأي قاعدة. اتركه فارغاً ليعمل النفق كالمعتاد.';

  @override
  String get tunRouteOnlyWarning =>
      'يأخذ النفق الشبكات الفرعية المذكورة فقط. وقواعد التطبيقات والمواقع تسري داخلها فقط: ما لم يدخل النفق لا يصل إلى النواة أصلاً — فلا يمكن حظر مثل هذا الموقع ولا تحويله.';

  @override
  String get tunAlsoSystemProxy => 'بروكسي النظام مع النفق';

  @override
  String get infoTunAlsoSystemProxy =>
      'وضع مختلط: يعمل النفق وبروكسي النظام معاً في وقت واحد.\n\nالتطبيقات التي تحترم بروكسي النظام (المتصفحات، Telegram) تسلك الطريق القصير مباشرةً إلى المنفذ المحلي، متجاوزةً حزمة النفق في مساحة المستخدم، وتُعطي النواة اسم النطاق بدل العنوان المجرّد — فتصبح قواعد المواقع لها أدقّ ولا تعود تعتمد على تحليل TLS.\n\nلكنها لا تصبح بذلك مستقلة عن التطبيق: فهي تمرّ عبر العملية نفسها.';

  @override
  String get tunMixedModeWarning =>
      'الاتصال القادم عبر بروكسي النظام بلا عملية مالكة — فهو بالنسبة إلى النواة اتصال محلي. لذلك لا تعمل قواعد التطبيقات مع هذه البرامج. أما قواعد المواقع فتعمل، وبدقة أعلى من المعتاد.';

  @override
  String get tunWatchdog => 'مراقب تعلّق النواة';

  @override
  String get infoTunWatchdog =>
      'كم ثانية يُسمح لنواة النفق بألا تستجيب قبل اعتبارها متعلّقة وإسقاط النفق.\n\nإذا تعطّلت النواة، ينظّف Windows بعدها بنفسه — يُزال المحوّل والمسارات وقواعد جدار الحماية، وتعود الشبكة. أما إذا تعلّقت النواة فلا يُزال شيء: يبقى المحوّل قائماً ويبتلع كل حركة مرور الجهاز، بما فيها المُعلَّمة بـ «مباشر». من الخارج يبدو الأمر وكأن «الإنترنت اختفى تماماً»، وهو لا يزول من تلقاء نفسه.\n\nلا يتسلّح المراقب إلا بعد أول استجابة ناجحة من النواة: وإلا لقطع الاتصال في كل حالة يتعذّر فيها فتح منفذ الخدمة. 0 — بلا مراقبة. الحد الأدنى 10 ثوانٍ.';

  @override
  String get tunWatchdogOff => 'مُطفأ: لن يُكتشف تعلّق النفق';

  @override
  String tunWatchdogSubtitle(int seconds) {
    return 'إسقاط النفق إذا صمتت النواة أكثر من $seconds ث';
  }

  @override
  String get tunDnsForAllWarning =>
      'سيمرّ تحليل الأسماء للجهاز بأكمله عبر النفق. وإذا تعطّل النفق، تتوقف الأسماء عن التحليل حتى للتطبيقات التي تمرّ مباشرةً ولا تحتاج إلى VPN — ويبدو الأمر من الخارج فقداناً كاملاً للإنترنت.';

  @override
  String get tunCidrInvalid => 'يلزم عنوان مع بادئة، مثل 10.8.0.0/24';

  @override
  String get geoTitle => 'بيانات التوجيه الجغرافية';

  @override
  String get geoMissing => 'غير مُنزَّلة — قواعد البلدان والفئات لا تعمل';

  @override
  String geoPresent(String size, String date) {
    return '$size، آخر تحديث $date';
  }

  @override
  String get geoDownload => 'تنزيل';

  @override
  String get geoUpdate => 'تحديث';

  @override
  String geoDownloading(String file) {
    return 'جارٍ تنزيل $file…';
  }

  @override
  String get geoDone => 'تم تحديث بيانات التوجيه الجغرافية';

  @override
  String geoFailed(String error) {
    return 'فشل التنزيل: $error';
  }

  @override
  String get infoGeoAssets =>
      'ملفّا geoip.dat وgeosite.dat قائمتان: عناوين مُصنَّفة حسب البلد ونطاقات مُصنَّفة حسب الفئة (مثلاً «المواقع الروسية»، «الخدمات الحكومية»، «VK»). وعليهما تعتمد قواعد التوجيه التي تحدّدها لوحة الاشتراك.\n\nوهما غير مُضمَّنين في التطبيق: يبلغ حجمهما معاً نحو 30 MB، ولا يحتاجهما الجميع — فالخادم العادي لا يستخدمهما إطلاقاً.\n\nوما دام الملفّان غير موجودين، تُحذَف هذه القواعد من التكوين، وحركة المرور التي كانت توجّهها مباشرةً تمرّ الآن عبر VPN. هذا آمن لكنه أبطأ، وقد ترفض المواقع المحلية الوصول بسبب العنوان الأجنبي. أمّا قواعدك الخاصة بمواقع وتطبيقات محدَّدة فتعمل في كل الأحوال — فهي لا تعتمد على هذين الملفّين.';

  @override
  String get supportBullet2Android =>
      '• بعد النقر، يُجمع التقرير في ملف واحد وتُفتح نافذة النظام «مشاركة» — اختر Telegram وسيُرسَل كمرفق واحد. صِف المشكلة في الحقل أعلاه: بدون وصف لا يوجد ما يمكن تحليله.';

  @override
  String get supportDoneTextAndroid =>
      'تم جمع التقرير في ملف واحد. اختر من نافذة النظام إلى أين ترسله — في Telegram يُرسَل كمرفق، وليس كنص.';

  @override
  String get exitsHeader => 'المخارج';

  @override
  String get exitsHint =>
      'يمكن توجيه قاعدة «النفق» إلى مخرج محدد: موقع عبر ألمانيا وآخر عبر الولايات المتحدة. بدون مخرج تستخدم القاعدة النفق الرئيسي كما في السابق.';

  @override
  String get exitsAdd => 'إضافة مخرج';

  @override
  String get exitsEmpty => 'لا توجد مخارج بعد';

  @override
  String get exitsName => 'الاسم';

  @override
  String get exitsNameHint => 'ألمانيا';

  @override
  String get exitsServers => 'الخوادم';

  @override
  String get exitsAutoSelect => 'اختيار تلقائي حسب زمن الاستجابة';

  @override
  String get exitsAutoSelectSub =>
      'تُبقي النواة حركة البيانات على خادم عامل تلقائيًا. الثمن: يُختبر كل خادم كل ثلاث دقائق، ما يوقظ الراديو في الهاتف.';

  @override
  String get exitsAutoSelectNeedsTwo => 'يلزم خادمان على الأقل';

  @override
  String get exitsDelete => 'حذف المخرج';

  @override
  String get exitsNoServers => 'لا توجد خوادم — استورد اشتراكًا أولًا';

  @override
  String get exitsSearch => 'البحث عن خادم';

  @override
  String get exitsPickAtLeastOne => 'اختر خادمًا واحدًا على الأقل';

  @override
  String get exitsUnsupportedNote =>
      'ملفات «تلقائي» من اللوحة وhysteria2 لا تعمل كمخرج منفصل: تتولاها النواة الأخرى. هذه الخوادم معطّلة في القائمة.';

  @override
  String get infoExits =>
      'المخرج هو وجهة قاعدة «النفق».\n\nافتراضيًا يتكوّن المخرج من خادم واحد ولا يكلّف شيئًا في الخلفية: البروتوكولات المعتادة لا تُبقي اتصالًا دائمًا. مجموعة من عدة خوادم مع الاختيار التلقائي تلزم فقط حين يهمّ التأمين ضد سقوط العقدة، وهي تضيف اختبارات دورية، وفي الهاتف تعني إيقاظ الراديو.\n\nللمخرج معنى فقط مع إجراء «النفق». «مباشر عبر ألمانيا» تناقض: القاعدة المباشرة تتجاوز كل المخارج.\n\nيمكن إرسال موقع ونطاقه الفرعي إلى مخرجين مختلفين — يرفع التطبيق القاعدة الأكثر تحديدًا للأعلى، وإلا ابتلع النطاق الأب النطاق الفرعي.\n\nمهم: مع وكيل النظام في ويندوز لا تعمل المخارج إطلاقًا — لا تُبنى في هذا الوضع قواعد توجيه. يلزم وضع النفق.';

  @override
  String get ruleServer => 'عبر الخادم';

  @override
  String get ruleServerCurrent => 'مثل الخادم الرئيسي';

  @override
  String ruleServerCurrentNamed(String server) {
    return 'مثل الخادم الرئيسي ($server)';
  }

  @override
  String get routeMatchByName => 'المطابقة حسب اسم الملف';

  @override
  String get routeYourApps => 'تطبيقاتك';

  @override
  String get routeYourSites => 'مواقعك';

  @override
  String get routeAppsAndSites => 'التطبيقات والمواقع';

  @override
  String get notifCompactTitle => 'إشعار مختصر';

  @override
  String get notifCompactSub =>
      'مُطفأ: الاشتراك والخادم والسرعة مع الأزرار. مُفعَّل: التطبيق والاشتراك في العنوان، والخادم تحته، بلا سرعة وبلا أزرار.';

  @override
  String get localProxyAuthTitle => 'كلمة مرور البروكسي المحلي';

  @override
  String get localProxyAuthInfo =>
      'المنفذ المحلي للنواة (127.0.0.1) بروكسي كامل إلى VPN الخاص بك. وبدون كلمة مرور يتصل به أي برنامج على الجهاز نفسه فيحصل على نفقك بالكامل: عنوان IP الخارجي، وحصة اشتراكك، وتجاوز قواعد تقسيم النفق التي وضعتها أنت — بما في ذلك التطبيقات التي منحتها «حظر». وهذا مهم بوجه خاص على Android: فالمنافذ المحلية هناك يراها أي تطبيق مثبَّت.\n\nلا تُطفئها إلا إذا كنت تقصد الدخول إلى هذا البروكسي ببرنامج لا يدعم المصادقة.';

  @override
  String get localProxyAuthOff =>
      'مُطفأ: البروكسي المحلي مفتوح لأي برنامج على الجهاز';

  @override
  String get localProxyAuthSystemProxy =>
      'لا يُطبَّق في وضع «بروكسي النظام»: لا يستطيع Windows تمرير كلمة المرور إلى البروكسي المحلي. يعمل في وضع TUN.';

  @override
  String get localProxyAuthRandom =>
      'كلمة مرور عشوائية جديدة عند كل اتصال — لا تُحفظ في أي مكان';

  @override
  String get localProxyAuthCustom =>
      'اسم مستخدم وكلمة مرور خاصان بك (يُحفظان في ملف الإعدادات)';

  @override
  String get localProxyCredsTitle => 'اسم مستخدم وكلمة مرور خاصان بك';

  @override
  String get localProxyCredsUnset => 'غير محدَّدين — تُستخدم كلمة مرور عشوائية';

  @override
  String localProxyCredsUser(String user) {
    return 'اسم المستخدم: $user';
  }

  @override
  String get localProxyDialogTitle => 'اسم المستخدم وكلمة مرور البروكسي المحلي';

  @override
  String get localProxyDialogBody =>
      'لا يلزمان إلا إذا كنت تُدخل بروكسينا (127.0.0.1) بنفسك في برنامج آخر. اترك الحقول فارغة وستكون كلمة المرور عشوائية عند كل اتصال: لا تُحفظ في أي مكان ولا تدخل في النسخ الاحتياطية.';

  @override
  String get localProxyFieldUser => 'اسم المستخدم';

  @override
  String get localProxyFieldPassword => 'كلمة المرور';

  @override
  String get localProxyFieldHint => 'فارغ — عشوائية';

  @override
  String get lockdownOnTitle => 'حماية النظام مُفعَّلة';

  @override
  String get lockdownOnSub =>
      'حركة المرور محظورة حتى لو أُغلق التطبيق أو أزاله النظام من الذاكرة. هذا هو الوضع الأكثر أمانًا.';

  @override
  String get lockdownHalfTitle => 'الحماية مُفعَّلة نصفيًا';

  @override
  String get lockdownHalfSub =>
      '«شبكة VPN دائمة التفعيل» مُعيَّنة، لكن «حظر الاتصالات بدون شبكة VPN» مُطفأ. ما دام التطبيق يعمل فحركة المرور محمية؛ وإذا أزاله النظام من الذاكرة فستمر بلا حماية.';

  @override
  String get lockdownOffTitle => 'حماية النظام مُطفأة';

  @override
  String get lockdownOffSub =>
      'يمسك مفتاح الإيقاف (Kill switch) لدينا حركة المرور ما دام التطبيق يعمل. وإذا أزاله النظام من الذاكرة فستمر الحركة خارج VPN. فعِّل «شبكة VPN دائمة التفعيل» و«حظر الاتصالات بدون شبكة VPN».';

  @override
  String get lockdownUnknownTitle => 'حماية النظام: الحالة غير معروفة';

  @override
  String get lockdownUnknownSub =>
      'لا يمكن معرفة الحالة إلا من Android 10 وأثناء عمل النفق فقط. تحقّق يدويًا: «شبكة VPN دائمة التفعيل» و«حظر الاتصالات بدون شبكة VPN».';

  @override
  String get lockdownOpenFailed =>
      'تعذّر فتح إعدادات VPN في النظام. ابحث عنها يدويًا: الإعدادات ← الشبكة والإنترنت ← VPN.';

  @override
  String get blockNoticeTitle => 'التنبيه إلى المواقع المحظورة';

  @override
  String get blockNoticeSub =>
      'عندما يطرق تطبيق أو متصفح موقعًا من قائمة «حظر»، يظهر في الأسفل إشعار باسمه. انقر عليه لتُفتح هذه الشاشة.';

  @override
  String get siteInsecureScheme =>
      'العنوان مكتوب بصيغة http:// — الاتصال غير مشفَّر ومزوّد الخدمة يراه بالكامل. احذف «http://» ليذهب المتصفح عبر https.';

  @override
  String get exitServerGone =>
      'اختفى خادم هذه القاعدة من الاشتراك — تمر حركة المرور عبر النفق الرئيسي';

  @override
  String exitServerUnsupported(String name) {
    return '$name\n\nلا يمكن رفع هذا الخادم كمخرج منفصل: ملفات «تلقائي» من اللوحة وبعض البروتوكولات لا يتولاها إلا Xray، بينما يوزّع المخارج sing-box. تمر حركة مرور القاعدة عبر النفق الرئيسي.';
  }

  @override
  String get noticeRulesAction => 'القواعد';

  @override
  String get geoVerdictMissingTitle => 'بيانات التوجيه الجغرافية غير مُنزَّلة';

  @override
  String get geoVerdictMissingSub =>
      'قواعد الاشتراك حسب البلدان والفئات معطّلة الآن — تمر هذه الحركة عبر VPN لا مباشرةً.';

  @override
  String get geoVerdictUnusableTitle =>
      'النواة لم تفتح بيانات التوجيه الجغرافية';

  @override
  String get geoVerdictUnusableSub =>
      'الملفات موجودة، لكن النواة لم تقرأها. يساعد عادةً تنزيل البيانات من جديد.';
}
