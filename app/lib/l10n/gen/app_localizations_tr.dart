// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get settingsTitle => 'Ayarlar';

  @override
  String get commonCancel => 'İptal';

  @override
  String get commonClose => 'Kapat';

  @override
  String get commonCopy => 'Kopyala';

  @override
  String get commonClear => 'Temizle';

  @override
  String get commonCopied => 'Kopyalandı';

  @override
  String get commonRefresh => 'Yenile';

  @override
  String get commonCheck => 'Kontrol et';

  @override
  String get commonOk => 'Tamam';

  @override
  String get commonDone => 'Bitti';

  @override
  String get commonPathCopied => 'Yol kopyalandı';

  @override
  String get languageTitle => 'Arayüz dili';

  @override
  String get languageSubtitle => 'Uygulama dilini seçin';

  @override
  String get languageSystem => 'Sistem varsayılanı';

  @override
  String get sectionAppearance => 'Görünüm ve davranış';

  @override
  String get sectionCapture => 'Trafik yakalama';

  @override
  String get sectionReliability => 'Bağlantı güvenilirliği';

  @override
  String get sectionPing => 'Ping';

  @override
  String get sectionIdentity => 'Panel kimliği';

  @override
  String get sectionNetwork => 'Ağ';

  @override
  String get sectionAbout => 'Hakkında';

  @override
  String get sectionSupport => 'Destek';

  @override
  String get settingsSearchHint => 'Ayarlarda ara';

  @override
  String settingsSearchEmpty(String query) {
    return 'Hiçbir şey bulunamadı: «$query»';
  }

  @override
  String get settingsExpand => 'Genişlet';

  @override
  String get settingsCollapse => 'Daralt';

  @override
  String get appearanceTheme => 'Tema';

  @override
  String get themeSystem => 'Sistem';

  @override
  String get themeLight => 'Açık';

  @override
  String get themeDark => 'Koyu';

  @override
  String get closeToTrayTitle => 'Kapatınca sistem tepsisine küçült';

  @override
  String get closeToTraySubtitle =>
      'Kapat düğmesi pencereyi tepsiye gizler; uygulamayı tamamen kapatmak için bunu kapatın';

  @override
  String get autoUpdateSubTitle => 'Aboneliği otomatik güncelle';

  @override
  String get autoUpdateSubText => 'Sunucu listesini düzenli olarak yenile';

  @override
  String get captureSystemProxy => 'Sistem proxy\'si';

  @override
  String get captureSystemProxySub =>
      'Hemen çalışır. Yönetici hakları gerektirmez.';

  @override
  String get captureTun => 'TUN (tam tünel)';

  @override
  String get captureTunBadgeUac => 'UAC gerekir';

  @override
  String get captureTunSub =>
      'UDP ve proxy\'yi yok sayan uygulamalar dâhil tüm trafik. Yönetici hakları gerektirir.';

  @override
  String get tunProvider => 'TUN sağlayıcı';

  @override
  String get tunRoutingTitle => 'TUN ve yönlendirme';

  @override
  String tunRoutingSub(String stack, int mtu, String dns) {
    return 'Yığın $stack · MTU $mtu · DNS $dns';
  }

  @override
  String get splitTunnelTitle => 'Ayrık tünelleme';

  @override
  String splitRulesCount(int n, int apps, int sites) {
    return '$n kural ($apps uygulama, $sites site)';
  }

  @override
  String get captureTunHint =>
      'TUN, DNS ve ayrık tünelleme ayarları yalnızca TUN modu seçildiğinde görünür — sistem proxy modunda etkisizdir.';

  @override
  String get captureProxyOnly => 'Yalnızca proxy';

  @override
  String get captureProxyOnlySub =>
      'Çekirdek çalışıyor ve yerel bağlantı noktaları dinliyor, ancak bilgisayar tünelde değil: VPN üzerinden yalnızca proxy\'mizi açıkça belirten trafik gider';

  @override
  String get apiSectionTitle => 'Otomasyon için API';

  @override
  String get apiEnableTitle => 'Yerel API\'yi etkinleştir';

  @override
  String apiEnableSub(int port) {
    return '127.0.0.1:$port üzerinde HTTP — istemciyi betiklerden yönetin';
  }

  @override
  String get apiTokenTitle => 'Belirteç';

  @override
  String get apiTokenUnset => 'Ayarlanmadı — API başlamaz';

  @override
  String get apiTokenRegenerate => 'Belirteci yenile';

  @override
  String get apiTokenWarning =>
      'Belirteç, ayar dosyasında düz metin olarak durur. Günlüğe ve destek raporuna girmez, ama elinde olan kişi sunucu değiştirebilir ve abonelik durumunuzu okuyabilir.';

  @override
  String get apiExitsTitle => 'Ayrı bağlantı noktalı sunucular';

  @override
  String get apiExitsSub =>
      'Her birine kendi yerel bağlantı noktası verilir — o noktaya gelen istek o sunucu üzerinden gider';

  @override
  String get apiCopyPythonExample => 'Python örneğini kopyala';

  @override
  String apiPortsHint(int control, int direct, int first) {
    return 'Kontrol — bağlantı noktası $control. «Doğrudan» — bağlantı noktası $direct. Sunucular — $first itibarıyla.';
  }

  @override
  String get apiRulesInProxyOnly => 'Ayrık tünelleme kurallarını uygula';

  @override
  String get apiRulesInProxyOnlySub =>
      'Bu modda varsayılan kurallar hiçbir program için geçerli değildir. \"Engelle\" listesinin yerel bağlantı noktaları üzerinden yapılan istekleri de kapsamasını istiyorsanız bunu açın.';

  @override
  String apiCaptureModeWarning(int control) {
    return '⚠️ Yakalama «Sistem proxy\'si» olarak seçili — bu modda çıkış portları açılmaz ve onlara yapılan bağlantılar reddedilir. Kontrol portu $control her yakalama modunda çalışır. Çıkış portları gerekiyorsa «TUN (tam tünel)» ya da «Yalnızca proxy» seçin.';
  }

  @override
  String get apiPortBusyTitle => 'API başlatılamadı';

  @override
  String apiPortBusy(int port, String holder) {
    return '$port portunu $holder tutuyor. Bu programı sistem tepsisi dahil tamamen kapatın ve anahtarı yeniden açın.';
  }

  @override
  String apiPortBusyUnknown(int port) {
    return '$port portunu, tanımlanamayan başka bir program tutuyor. Genellikle bu başka bir VPN istemcisidir. Onu kapatın ve anahtarı yeniden açın.';
  }

  @override
  String get apiRulesInProxyOnlyEdit =>
      '«Engelle» listesi ayrık tünelleme ekranında düzenlenir';

  @override
  String get dnsShortVpn => 'VPN üzerinden';

  @override
  String get dnsShortSystem => 'sistem';

  @override
  String get dnsShortCustom => 'özel';

  @override
  String get tunUacTitle => 'TUN yönetici hakları gerektirir';

  @override
  String get tunUacBody =>
      'Bir kez ayarlayabilirsiniz: uygulama, en yüksek ayrıcalıklarla bir Windows Görev Zamanlayıcı görevi oluşturur ve bundan sonra tünel UAC istemi OLMADAN başlar.\n\nŞimdi bir yönetici istemi görünecek. Uygulamanın kendisi yükseltilmiş haklar olmadan çalışmaya devam eder.';

  @override
  String get tunUacLater => 'Sonra (her seferinde sor)';

  @override
  String get tunUacSetup => 'Ayarla';

  @override
  String get tunUacDone => 'Bitti: TUN, UAC istemi olmadan başlayacak';

  @override
  String get tunUacFail => 'Görev oluşturulamadı — bağlanırken UAC istenecek';

  @override
  String get autoReconnectTitle => 'Otomatik yeniden bağlan';

  @override
  String get autoReconnectSub =>
      'Bağlantı koptuğunda ve ağ değiştiğinde bağlantıyı geri getir';

  @override
  String get killSwitchTitle => 'Kill switch';

  @override
  String get alwaysOnTitle => 'Sistem düzeyinde koruma';

  @override
  String get alwaysOnSub =>
      'Her zaman açık VPN ve «VPN olmadan bağlantıları engelle» — uygulama kapalıyken de çalışır';

  @override
  String get killSwitchSubTun =>
      'Yeniden bağlanırken trafiğin VPN\'i atlamasına izin verme';

  @override
  String get killSwitchSubProxy =>
      '«Sistem proxy\'si» modunda yalnızca proxy\'yi tanıyan uygulamaları korur. Tam koruma — yalnızca TUN';

  @override
  String get killSwitchSubOff =>
      'Otomatik yeniden bağlanmanın etkin olması gerekir';

  @override
  String get networkRecoverTitle => 'Ağı kurtar';

  @override
  String get networkRecoverSub =>
      'VPN\'den sonra internet gittiyse. Yönetici hakları gerektirir';

  @override
  String get networkRecoverConfirmTitle => 'Ağ kurtarılsın mı?';

  @override
  String get networkRecoverConfirmBody =>
      'Winsock, IP yığını, DNS ve sistem proxy\'sinin sıfırlanması. Yönetici hakları (UAC) gereklidir. Winsock/IP sıfırlaması yeniden başlatmadan sonra etkinleşir.';

  @override
  String get networkRecoverConfirmOk => 'Kurtar';

  @override
  String get interferenceTitle => 'Girişim kontrolü (diğer VPN\'ler)';

  @override
  String get interferenceDialogTitle => 'Ağ girişimi';

  @override
  String get interferenceNoneFound => 'Başka VPN veya girişim tespit edilmedi.';

  @override
  String get interferenceIgnore => 'Yok say';

  @override
  String get identityUserAgent => 'User-Agent';

  @override
  String identityUaAutoNote(String version) {
    return 'Uygulama sürümüyle birlikte otomatik güncellenir. Ayrıca gönderilir: X-HWID, X-Device-OS, X-Ver-OS, X-App-Version ($version).';
  }

  @override
  String get urlSchemesTitle => 'URL şemaları';

  @override
  String get urlSchemesSub =>
      'VPN\'i bağlantılar aracılığıyla içe aktar ve kontrol et (bağlan / değiştir / güncelle)';

  @override
  String get panelOwnerTitle => 'Panel sahibi için';

  @override
  String get panelOwnerBody =>
      'Sıradan kullanıcıların buna ihtiyacı yok — atlayabilirsiniz.\n\nUygulamanın aboneliğinizi doğru JSON biçiminde (XRAY_JSON) alması için, bu bloğu Remnawave panelinizin Response Rules bölümüne ekleyin — User-Agent\'ımızla eşleşir:';

  @override
  String get panelOwnerCopy => 'Bloğu kopyala';

  @override
  String get aboutVersion => 'SilentGate sürümü';

  @override
  String get aboutXrayCore => 'Xray çekirdeği';

  @override
  String get aboutHwid => 'Cihaz HWID';

  @override
  String get aboutThirdPartyTitle => 'Üçüncü taraf bileşenler ve lisanslar';

  @override
  String get aboutThirdPartySub =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), Wintun — ayrı süreçler olarak çalışır';

  @override
  String get aboutThirdPartySubEmbedded =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), libXray (MIT) — uygulamaya gömülü';

  @override
  String get thirdPartyBodyEmbedded =>
      'On Android the cores are BUILT INTO the app (a native library inside the APK).\n\n• sing-box — GPL-3.0. The library is linked into the app, so derivatives must stay under GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nClient source code: https://github.com/Solat228/silentgate\nFull license texts — buttons below.';

  @override
  String get logsTitle => 'Günlükler';

  @override
  String get logsSub =>
      'Uygulama ve TUN (sing-box): abonelik içe aktarma, ping, hatalar';

  @override
  String get thirdPartyTitle => 'Üçüncü taraf bileşenler';

  @override
  String get thirdPartyBody =>
      'SilentGate, üçüncü taraf yürütülebilir dosyalarla birlikte gelir. Bunlar AYRI süreçler olarak çalışır ve uygulamaya gömülü değildir.\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  Hysteria2 için TUN tüneli ve proxy çekirdeği\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — Wintun lisansı\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — yönlendirme verileri, CC-BY-SA-4.0\n\nTam lisans metinleri uygulamanın yanındaki «licenses» klasöründedir.';

  @override
  String get supportSectionNote =>
      '«Desteğe başvur»a dokunun — kendi başınıza bir günlük dosyası oluşturduğunuz bir pencere açılır (sürümler, işletim sistemi, ayarlar, app.log + singbox.log kuyruğu; parola veya abonelik jetonu yok, URL gizli). Ardından bunu Telegram desteğine gönderme düğmesi görünür.';

  @override
  String get supportButtonTitle => 'Desteğe başvur';

  @override
  String get supportButtonSub => 'Bir günlük oluştur ve destek sohbetini aç';

  @override
  String get supportDialogTitle => 'Destek';

  @override
  String get supportDialogTitleDone => 'Günlük hazır — nereye gönderilecek';

  @override
  String get supportWhatWillHappen => 'Ne olacak:';

  @override
  String get supportBullet1 =>
      '• Tek bir dosya sürümleri, işletim sistemini, ayarları ve günlükleri (app.log + singbox.log kuyruğu) toplar. İçinde parola veya abonelik jetonu yoktur, abonelik URL\'si gizlidir.';

  @override
  String get supportBullet2 =>
      '• Dokunduktan sonra ÖNCE dosyanın bulunduğu klasör, ardından dosyanın kendisi açılır. Sorunu en üste yazın, kaydedin — ve destek gönderme düğmesi görünür.';

  @override
  String supportError(String error) {
    return 'Rapor oluşturulamadı: $error';
  }

  @override
  String get supportDoneText =>
      'Rapor oluşturuldu ve açıldı (önce klasör, sonra dosya). Sorunu en üste yazın, dosyayı kaydedin ve desteğe gönderin — uygulama Telegram\'ı açmaya yardımcı olacaktır.';

  @override
  String get supportWhoTo => 'Nereye gönderilecek:';

  @override
  String get supportContact => 'Desteğe başvur';

  @override
  String supportContactNamed(String name) {
    return 'Desteğe başvur ($name)';
  }

  @override
  String get supportDevServiceName => 'İstemci geliştiricisi';

  @override
  String get supportShowOnPc => 'Bilgisayarda göster';

  @override
  String get supportCopyPath => 'Yolu kopyala';

  @override
  String get supportGenerating => 'Oluşturuluyor…';

  @override
  String get supportGenerateButton => 'Destek günlüğü oluştur';

  @override
  String get pingTwoPhaseTitle => 'Çalıştığını doğrula (tünel üzerinden)';

  @override
  String get pingTwoPhaseSubOn =>
      'TCP\'den sonra — sunucu üzerinden bir istek: çalışmayanları eler (Reality vb.)';

  @override
  String get pingTwoPhaseSubOff =>
      'Yalnızca seçili tek yöntem (aşağıda) kullanılır';

  @override
  String get pingMethodCheck => 'Doğrulama yöntemi:';

  @override
  String get pingMethodPing => 'Ping yöntemi:';

  @override
  String get speedTestProbe => 'Hız testi ölçümü:';

  @override
  String get speedTestFull => '20 MB (daha doğru)';

  @override
  String get speedTestLight => '5 MB (ekonomik)';

  @override
  String get testUrlLabel => 'Test URL\'si (Proxy üzerinden)';

  @override
  String get appUpdateServerUnavailable => 'Güncelleme sunucusu erişilemez';

  @override
  String appUpdateAvailable(String version) {
    return '$version sürümü mevcut';
  }

  @override
  String get appUpdateLatest => 'En son sürüme sahipsiniz';

  @override
  String get appUpdateDownload => 'İndir';

  @override
  String get appUpdateCheckTitle => 'Açılışta güncellemeleri kontrol et';

  @override
  String get appUpdateManual => 'İndirme ve kurulum — el ile';

  @override
  String get appUpdateEndpointLabel => 'Sürüm uç noktası';

  @override
  String get urlSchemeSilentgateTitle => 'silentgate:// bağlantıları';

  @override
  String get urlSchemeSilentgateSub =>
      'VPN\'i bağlantılar aracılığıyla içe aktar ve kontrol et. Varsayılan olarak etkin';

  @override
  String get urlSchemeDisableTitle =>
      'silentgate:// bağlantıları devre dışı bırakılsın mı?';

  @override
  String get urlSchemeDisableBody =>
      'Bağlantıyla içe aktarma ve kontrol şemaları (bağlan / bağlantıyı kes / değiştir / güncelle) çalışmayı durduracak. Emin değilseniz açık bırakın.';

  @override
  String get urlSchemeDisableOk => 'Devre dışı bırak';

  @override
  String get urlSchemeServerTitle => 'Sunucu bağlantılarını aç';

  @override
  String get urlSchemeServerSub =>
      'Diğer istemcilerden vless:// ve benzerlerini yakala';

  @override
  String get urlSchemeServerConfirmTitle =>
      'Sunucu bağlantıları yakalansın mı?';

  @override
  String urlSchemeServerConfirmBody(String schemes) {
    return '$schemes\n\nBu bağlantılar genellikle başka bir VPN istemcisine (Happ, v2rayTun) bağlıdır. SilentGate bunları devralacaktır.';
  }

  @override
  String get urlSchemeServerConfirmOk => 'Yakala';

  @override
  String get urlSchemeAutoConnect => 'İçe aktardıktan sonra bağlan';

  @override
  String get autoTitle => 'Otomatik yapılandırma';

  @override
  String get autoClearResults => 'Sonuçları temizle';

  @override
  String autoFoundWorking(Object count) {
    return 'Çalışan bulundu: $count';
  }

  @override
  String get autoPinnedTop => ' — listenin en üstüne sabitlendi';

  @override
  String get autoSearchContinues => ' (arama devam ediyor…)';

  @override
  String get autoCheckServices => 'Hizmetleri kontrol et';

  @override
  String get autoPinFoundOnTop =>
      'Bulunan sunucuları listenin en üstüne sabitle';

  @override
  String get autoTryFragment => 'Atlatmayı dene (fragment)';

  @override
  String get autoNoSubscriptionPasteKey =>
      'Abonelik yok. Tek bir anahtar yapıştırın — çalışan ayarları bulalım:';

  @override
  String get autoTuneByKey => 'Anahtara göre ayarla';

  @override
  String autoTesting(int index, int total) {
    return 'Test ediliyor $index/$total: ';
  }

  @override
  String autoVariant(Object label) {
    return 'Varyant: $label';
  }

  @override
  String autoServicesPassed(int ok, int total) {
    return '$total hizmetten $ok tanesi';
  }

  @override
  String get autoConnect => 'Bağlan';

  @override
  String get autoStopSearch => 'Aramayı durdur';

  @override
  String get autoDoneRefreshPing => 'Bitti — bulunanların pingini yenile';

  @override
  String autoFoundPinnedRefreshing(Object count) {
    return '$count bulundu, en üste sabitlendi. Ping yenileniyor…';
  }

  @override
  String autoServersForTuning(int selected, int total) {
    return 'Ayarlanacak sunucular ($selected/$total)';
  }

  @override
  String get autoSelectAll => 'Tümü';

  @override
  String get autoDeselectAll => 'Temizle';

  @override
  String get autoTuneSelected => 'Seçilenleri ayarla';

  @override
  String autoTuned(Object label) {
    return 'Ayarlandı: $label';
  }

  @override
  String get infoDialogTitle => 'Bilgi';

  @override
  String get infoCopied => 'Açıklama kopyalandı';

  @override
  String get commonGotIt => 'Anladım';

  @override
  String get enumSplitAll => 'Tümü — VPN üzerinden';

  @override
  String get enumSplitOnly => 'Yalnızca seçilenler — VPN üzerinden';

  @override
  String get enumSplitExcept => 'Seçilenler — VPN dışında';

  @override
  String get enumActionTunnel => 'Tünel';

  @override
  String get enumActionDirect => 'Doğrudan';

  @override
  String get enumActionBlock => 'Engelle';

  @override
  String homeUpdateAvailable(Object version) {
    return '$version sürümü mevcut';
  }

  @override
  String get homeDownload => 'İndir';

  @override
  String homeSubscriptionUpdated(Object summary) {
    return 'Abonelik güncellendi: $summary';
  }

  @override
  String get homeReconnect => 'Yeniden bağlan';

  @override
  String homePingProgress(int done, int total) {
    return 'Sunucular pingleniyor: $total sunucudan $done tanesi';
  }

  @override
  String get homeAutoConfigStarting => 'Otomatik yapılandırma başlıyor…';

  @override
  String homeAutoConfigProgress(int current, int total, String name) {
    return 'Otomatik yapılandırma: $total sunucudan $current tanesi — $name';
  }

  @override
  String get homeImport => 'İçe aktar';

  @override
  String get homeSettings => 'Ayarlar';

  @override
  String get homeAutoBest => 'Otomatik (en iyi sunucu)';

  @override
  String get homeAutoConfig => 'Otomatik yapılandırma';

  @override
  String homeServersCount(Object count) {
    return 'Sunucular ($count)';
  }

  @override
  String homeFoundCount(int found, int total) {
    return '$total sunucudan $found tanesi bulundu';
  }

  @override
  String get homePingServers => 'Sunucuları pingle';

  @override
  String get homePingFound => 'Bulunanları pingle';

  @override
  String get homeNothingFound => 'Hiçbir şey bulunamadı';

  @override
  String get homeOnboardingTitle => 'Bir abonelik içe aktararak başlayın';

  @override
  String get homeOnboardingSubtitle =>
      'Bir Remnawave bağlantısı veya tek bir anahtar yapıştırın';

  @override
  String get homeImportSubscription => 'Aboneliği içe aktar';

  @override
  String homeSessionTraffic(String down, String up) {
    return 'Bu oturum: ↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'GB';

  @override
  String subBarUsage(String used, String total) {
    return '$used / $total';
  }

  @override
  String get subBarSubscription => 'Abonelik';

  @override
  String get subBarRefreshing => 'Yenileniyor…';

  @override
  String get subBarRefreshSubscription => 'Aboneliği yenile';

  @override
  String get subBarSupport => 'Destek';

  @override
  String get subBarRefresh => 'Yenile';

  @override
  String get subBarAddSubscription => 'Abonelik ekle';

  @override
  String get subBarCopyLink => 'Bağlantıyı kopyala';

  @override
  String get subBarDeleteSubscription => 'Aboneliği sil';

  @override
  String get subBarLinkCopied => 'Bağlantı kopyalandı';

  @override
  String get subBarDeleteConfirmTitle => 'Abonelik silinsin mi?';

  @override
  String get subBarDeleteConfirmBody =>
      'Bu abonelikteki sunucular listeden kaldırılacak.';

  @override
  String subBarDeletePinned(Object count) {
    return 'Sabitlenmiş ($count) sunucuları düzenlemeleriyle birlikte sil';
  }

  @override
  String get subBarDeletePinnedHint =>
      'Aksi hâlde listede kalır ve silme işleminden sonra da korunurlar';

  @override
  String get subBarCancel => 'İptal';

  @override
  String get subBarDelete => 'Sil';

  @override
  String get subBarSubscriptionDeleted => 'Abonelik silindi';

  @override
  String subBarSubscriptionUpdated(Object summary) {
    return 'Abonelik güncellendi: $summary';
  }

  @override
  String get subBarMore => 'Ayrıntılar';

  @override
  String subBarAdded(Object count) {
    return 'Eklendi ($count)';
  }

  @override
  String subBarRemoved(Object count) {
    return 'Kaldırıldı ($count)';
  }

  @override
  String subBarAutoUpdate(Object hours) {
    return '· otomatik güncelleme $hours sa';
  }

  @override
  String subBarValidPerpetual(Object auto) {
    return 'Geçerli: sınırsız  $auto';
  }

  @override
  String get subBarExpired => 'Aboneliğin süresi doldu:';

  @override
  String get subBarValidUntil => 'Geçerlilik tarihi:';

  @override
  String get subSwitcherPingAll => 'Tüm aboneliklerin sunucularını sına';

  @override
  String get subSwitcherPingBusySpeed =>
      'Ping kullanılamıyor: hız ölçümü sürüyor';

  @override
  String get subSwitcherExpired => 'Süresi doldu';

  @override
  String subSwitcherExpiredOn(String date) {
    return 'Abonelik $date tarihinde sona erdi';
  }

  @override
  String subSwitcherCountTotal(int total) {
    return 'Abonelikteki sunucu: $total. Kanal henüz denetlenmedi — «Tüm aboneliklerin sunucularını sına» komutunu çalıştırın.';
  }

  @override
  String subSwitcherCountWorking(int total, int working) {
    return 'Abonelikteki sunucu: $total. Bunlardan kanal denetimini (sunucu üzerinden istek) geçen: $working.';
  }

  @override
  String subSwitcherCountChecking(int total) {
    return 'Abonelikteki sunucu sayısı: $total. Denetim şu anda sürüyor — çalışan sunucu sayısı, tarama bittiğinde görünecek.';
  }

  @override
  String subSwitcherCountPartial(int total, int working) {
    return 'Abonelikteki sunucu sayısı: $total. Tarama tamamlanmadı (iptal edildi ya da kesildi), bu yüzden sayı eksik: ulaşılabilenler arasından $working tanesi kanal denetimini geçti.';
  }

  @override
  String get infoCaptureMode =>
      'Trafiğin nasıl yakalandığı. «Sistem proxy\'si» sistemde yerel bir proxy ayarlar (yönetici hakları gerekmez; tarayıcıları ve çoğu uygulamayı yakalar). «TUN», TÜM trafiği yakalayan sanal bir ağ bağdaştırıcısıdır (UDP ve proxy\'yi yok sayan uygulamalar dâhil), ancak yönetici hakları gerektirir.';

  @override
  String get infoSystemProxy =>
      'Sistem ayarlarında (WinINET kaydı) yerel bir HTTP proxy\'si. Yönetici hakları gerekmez. UDP\'yi veya sistem proxy\'sini yok sayan uygulamaları yakalamaz.';

  @override
  String get infoTunMode =>
      'Wintun sanal bağdaştırıcısı + sing-box üzerinden tam tünel. UDP dâhil tüm trafiği yakalar. Etkinleştirildiğinde yönetici hakları (UAC) ister.';

  @override
  String get infoTunProvider =>
      'Sanal ağ bağdaştırıcısının sürücüsü. Windows\'ta wintun kullanılır (çekirdekle birlikte gelir). Başka sürücü gerekmez.';

  @override
  String get infoTunStack =>
      'TUN ağ yığını (sing-box).\n\n«auto» — OTOMATİK SEÇİM: tünel kurulamazsa uygulama kendisi system → gvisor → mixed sırasını dener, ardından MTU\'yu düşürür (1400, 1280). Çalışan kombinasyon hatırlanır ve bir sonraki sefer ilk olarak denenir. Seçim ilerlemesi durumda ve günlükte gösterilir.\n\nAçık bir seçim otomatik seçimi devre dışı bırakır: system — işletim sistemi yığını, en hızlı ama antivirüslerle daha zorlu; gvisor — kullanıcı alanı, daha yavaş, maksimum uyumlu; mixed — TCP system üzerinden, UDP gvisor üzerinden.';

  @override
  String get infoTunMtu =>
      'TUN bağdaştırıcısındaki maksimum paket boyutu. Varsayılan 1500\'dür; bağlantı kopmaları yaşarsanız düşürün (1400, 1280) — çok küçük bir değer hızı azaltır.\n\n«auto» yığınında bu yalnızca başlangıç değeridir: tünel kurulamazsa uygulama daha küçük MTU\'ları kendisi deneyecektir.';

  @override
  String get infoTunStrictRoute =>
      'sing-box\'ta katı yönlendirme. Windows\'ta iki tipik sorunu giderir: DNS sızıntıları (varsayılan olarak sistem sorguları tüm bağdaştırıcılara aynı anda gönderir) ve «ağ erişilemez» hataları. Yalnızca VirtualBox/Hyper-V\'yi bozuyorsa kapatın.';

  @override
  String get infoTunIpv6 =>
      'IPv6\'yı tünele yönlendir. İnternet sağlayıcınızda IPv6 etkinken bunu kapatırsanız, bir kısım trafik VPN DIŞINA çıkar (gerçek adresinizi sızdırır) veya takılır. Yalnızca IPv6 ağ sorunlarınız varsa kapatın.';

  @override
  String get infoTunEndpointIndependentNat =>
      'UDP için NAT modu. Oyunlar, sesli sohbetler ve WebRTC için gereklidir — olmadan bağlantılar kurulamayabilir. Yalnızca bellek tasarrufu için devre dışı bırakın.';

  @override
  String get infoTunBypassLan =>
      'Yerel ağ (özel adresler 192.168.*, 10.*, yönlendirici, yazıcılar, NAS) VPN\'i atlar. Genellikle bunu açık istersiniz, aksi hâlde ağdaki cihazlara erişimi kaybedersiniz.';

  @override
  String get infoTunExcludeCidrs =>
      'Her zaman VPN\'i atlayan ek alt ağlar (CIDR biçimi, örn. 10.8.0.0/24). Kurumsal ağlar ve diğer VPN\'ler için kullanışlıdır.';

  @override
  String get infoTunPrivilege =>
      'TUN yönetici hakları gerektirir. Bir kez, en yüksek ayrıcalıklarla Windows Görev Zamanlayıcı\'da bir görev oluştururuz — bundan sonra tünel her bağlantıda UAC istemi OLMADAN başlar. Görev size aittir ve aşağıdaki düğmeyle veya program kaldırıldığında silinir.';

  @override
  String get infoAppUpdate =>
      'Uygulama, her açılışta bir kez sunucunuza daha yeni bir sürümün olup olmadığını sorar ve bir «İndir» düğmesiyle bildirim gösterir.\n\nUygulama kendi başına HİÇBİR ŞEY indirmez ve çalıştırmaz: kurulum sertifikayla imzalanmamıştır ve indirilen bir exe\'yi otomatik çalıştırmak SmartScreen\'e takılır ve antivirüslere kötü amaçlı yazılım davranışı gibi görünür. Güncellemeyi kendiniz kurarsınız.\n\nSunucu erişilemezse uygulama sessiz kalır ve günlüğe bir kayıt yazar. Yanıt biçimi ve sunucu kurulumu docs/APP_UPDATE.md içinde açıklanmıştır.';

  @override
  String get infoSpeedTest =>
      'Hız ölçülürken indirilen veri miktarı (bir sunucuya sağ tık → «Sunucu bilgisi» → «Hızı ölç»).\n\n20 MB — ana mod: hızlı bağlantılarda (100+ Mbps) kısa bir ölçüm hızlanmaya vakit bulamaz ve sonucu olduğundan düşük gösterir.\n5 MB — ekonomik mod: trafik açısından belirgin şekilde daha ucuz, birçok sunucuyu taramak için kullanışlı.\n\nÖlçüm YALNIZCA el ile çalışır ve aboneliğinizin trafiğini tüketir. Hız iki kez ölçülür: doğrudan ve seçili sunucu üzerinden, böylece VPN\'de tam olarak ne kadar kaybedildiğini görebilirsiniz.';

  @override
  String get infoAutoReconnect =>
      'Çekirdek çöktüyse, sunucu düştüyse veya ağ değiştiyse (Wi-Fi ↔ kablo, uykudan çıkma, yeni IP), uygulama bağlantıyı kendi başına yeniden kurar. Denemeler arasındaki bekleme süresi artar: 0,8 sn → 3 sn → 8 sn → 20 sn ve sonrasında 20 sn\'de kalır. Sekiz deneme yapılır, ardından uygulama pes eder ve bir hata gösterir. Düğmeyle bağlantıyı kesmek kurtarmayı her zaman iptal eder.\n\n⚠️ Kill switch açıkken denemeler BİTMEZ. Denemeler sürerken trafik engelli kalır ve onları durdurmak trafiği VPN\'in dışına salıvermek olurdu — bu yüzden uygulama, VPN\'i siz kapatana kadar 20 saniyede bir denemeyi sürdürür ve başarısızlığı en fazla 15 dakikada bir hatırlatır. Bir saat sonra geri gelen sunucu kendiliğinden yeniden yakalanır.\n\n«Otomatik (en iyi sunucu)» kipinde uygulama son denemeyi ölü bir sunucuya harcamaz: daha sekizde yedincide bir sonraki adaya geçer ve sayım orada baştan başlar.\n\nAğ değişikliği, diğer bağdaştırıcıların gerçek adreslerinden saptanır: kendi tünelimiz ve hizmet adresleri (link-local) sayılmaz, bir değişiklik ancak üst üste iki yoklamada sürdüyse kabul edilir ve bağlantıdan sonraki ilk 15 saniye boyunca sinyal yok sayılır. Bu emniyetler olmadan tünelin kurulması kendisi «ağ değişikliği» sayılır ve sonsuz yeniden bağlanmaya yol açardı.';

  @override
  String get infoKillSwitch =>
      'Bağlantı geri getirilirken trafiğin VPN etrafından çıkmasına izin verme. Yakalama denemeler arasında BIRAKILMAZ: TUN modunda bağdaştırıcı açık kalır, «Sistem proxy\'si» modunda proxy yapılandırılmış kalır — uygulamalar internete şifrelenmemiş erişim yerine bir bağlantı hatası alır.\n\nSınırlar hakkında dürüstçe: «Sistem proxy\'si» modunda bu yalnızca sistem proxy\'sine saygı duyan programları (tarayıcılar ve çoğu uygulama) korur. Proxy\'yi yok sayan programlar ve UDP doğrudan çıkar — tam sızdırmazlık yalnızca TUN moduyla sağlanır. Otomatik yeniden bağlanmanın etkin olmasını gerektirir.';

  @override
  String get infoUserAgent =>
      'Uygulamanın panele kendini nasıl tanıttığı (User-Agent başlığı). Her zaman «SilentGate/sürüm (Windows)» gönderir.\n\nBu ada göre Remnawave paneli abonelik BİÇİMİNİ seçer. XRAY_JSON gereklidir — hazır sunucu yapılandırmaları sunar; bağlantıların base64 listesinden bazı ayarlar yaklaşık olarak geri getirilir ve otomatik seçim (burstObservatory) daha kötü çalışır.\n\nPanelde yapılandırılır: Templates → Response Rules → koşulu user-agent CONTAINS SilentGate ve yanıt türü XRAY_JSON olan bir kural (Fallback Base64 kuralının üstüne yerleştirin).\n\nGeçersiz kılma alanı yalnızca geçici bir geçici çözüm olarak gereklidir — panel uygulamayı henüz tanımıyorsa, tanıdığı bir istemci olarak kimlik verebilirsiniz.';

  @override
  String get infoDnsMode =>
      'TUN modunda alan adlarını kimin çözdüğü. «VPN üzerinden» (önerilir) — sorgular TCP üzerinden tünele girer ve internet sağlayıcınız hangi siteleri açtığınızı görmez. «Sistem» — Windows\'taki gibi: DNS sızıntısı olasıdır ve sunucu UDP\'yi geçirmezse internet tamamen kesilebilir. «Özel» — belirttiğiniz sunucu, tünel üzerinden.';

  @override
  String get infoDnsCustomServer =>
      '«Özel» modu için DNS sunucusunun adresi (örneğin 9.9.9.9 veya 8.8.8.8). Ona giden sorgular TCP üzerinden tünelden geçer.';

  @override
  String get infoDnsHijack =>
      'DNS sorgularını (UDP 53 numaralı bağlantı noktası) tünel içinde yakala. Bunsuz sorgular kuralları atlar: sızıntı olasıdır ve ayrık tünellemenin alan adı kuralları daha az kesin çalışır.';

  @override
  String get infoDnsStrategy =>
      'Hangi adreslerin isteneceği: prefer_ipv4 (önerilir) — önce IPv4, ipv4_only — yalnızca IPv4 (bozuk IPv6 sorunlarını giderir), prefer_ipv6/ipv6_only — IPv6 ağları için.';

  @override
  String get infoSingboxLogLevel =>
      'sing-box günlüğünün ayrıntı düzeyi (%APPDATA%\\SilentGate\\singbox.log). warn — normal mod. info/debug — tünel çalışmıyorsa: günlük tam nedeni gösterir. debug dosya boyutunu belirgin şekilde artırır.';

  @override
  String get infoSplitMode =>
      'Temel — el ile ayarlanmış eylemi olmayan her şeyin nereye gideceği ve yeni girdilere hangi eylemin atanacağı. «Tümü — VPN üzerinden»: varsayılan olarak tüm trafik tünele. «Yalnızca seçilenler — VPN üzerinden»: varsayılan olarak doğrudan, tünele yalnızca «Tünel» olarak işaretlenenler. «Seçilenler — VPN etrafından»: tam tersi, her şey tünele ve «Doğrudan» olarak işaretlenenler doğrudan gider.';

  @override
  String get infoSplitApps =>
      'Bir uygulamaya tıklayın — eylemi (Tünel — VPN üzerinden, Doğrudan — VPN etrafından, Engelle — ağ yok) ve eşleştirme yöntemini seçtiğiniz bir pencere açılır: exe adına göre (güvenilir) veya tam yola göre. Çalışan uygulamalardan seçebilir veya bir .exe belirtebilirsiniz.';

  @override
  String get infoSplitDomains =>
      'Alan adları (son ekler). Örneğin youtube.com aynı zamanda www.youtube.com\'u da kapsar. TLS bağlantısındaki ada (SNI) göre çalışır.';

  @override
  String get infoVerifyViaProxy =>
      'Önce proxy üzerinden işlevselliği kontrol ederiz (sunucu gerçekten 204 döndürür) ve yalnızca sunucu yanıt verdiyse seçili yöntemle (TCP/ICMP) gecikmeyi ayrıca ölçeriz.';

  @override
  String get infoProxyGet =>
      'Test URL\'sine tünel üzerinden bir GET isteği. Sunucunun trafiği gerçekten geçirdiğini ve 204 döndürdüğünü kontrol eder. En dürüst işlevsellik testi; biraz daha yavaş.';

  @override
  String get infoProxyHead =>
      'GET gibi, ancak yalnızca başlıklar — daha hızlı ve daha az trafik. Bazı sunucular/CDN\'ler HEAD\'i desteklemeyebilir.';

  @override
  String get infoTcp =>
      'Sunucu adresine TCP el sıkışması süresi. Hızlı ve doğru bir gecikme göstergesi, ancak tünelin çalıştığını kanıtlamaz: bir Reality sunucusu, proxy engellenmiş olsa bile TCP\'ye yanıt verir. Gecikme için önerilir.';

  @override
  String get infoIcmp =>
      'Sistem ping\'i. Reality/CDN için genellikle işe yaramaz: ICMP engellenmiş olabilir veya en yakın CDN düğümünü ölçer. Ağ tanılaması için tutun.';

  @override
  String get infoTestUrl =>
      'Proxy üzerinden işlevselliği kontrol etmek için URL. Varsayılan olarak https://www.gstatic.com/generate_204 — boş bir 204 yanıtı döndürür, bu da kullanışlı ve hızlıdır.';

  @override
  String get infoAutoConfig =>
      'Sunucuları ve atlatma varyantlarını (fragment, fingerprint) tarar ve seçili hizmetlerin çalıştığı sunucuların bir listesini oluşturur. İlkinde durmaz — bulunanlar arasından siz seçersiniz. Kontrol proxy üzerinden yapılır; bu sırada VPN etkinleştirilmez.';

  @override
  String get infoAutoConfigServices =>
      'Bir sunucunun uygun sayılması için hangi hizmetlerin çalışması gerektiği. Kontrol, internet sağlayıcının yer tutucu sayfalarına karşı dayanıklıdır (yalnızca bir «200 OK» değil, yanıt imzası doğrulanır).';

  @override
  String get infoAutoPinFound =>
      'Bulunan çalışan kombinasyonlar (sunucu + atlatma varyantı) hemen ortak sunucu listesinin en üstüne sabitlenir, böylece buraya geri dönmeden kullanabilirsiniz. Otomatik yapılandırmanın listenizin sırasını değiştirmesini istemiyorsanız kapatın — sonuçlar yine bu ekranda görünür.';

  @override
  String get infoTryFragment =>
      '«Çıplak» sunucu çalışmıyorsa TLS ClientHello parçalama (DPI atlatma) varyantını deneyin. Biraz daha uzun sürer, ama kısıtlanmış sunucularda çalışan bir kombinasyon bulur.';

  @override
  String get infoAutoStrategy =>
      '«İlk çalışan» — her şeyi tara ve bulunan herhangi birine bağlan (siz seçersiniz). «Bütçe dâhilinde en iyi» — bir zaman sınırı içinde ara ve en hızlısını seç.';

  @override
  String get infoScheme =>
      'silentgate:// protokolünü sistemde kaydeder (geçerli kullanıcı için, yönetici hakları gerekmez). Bundan sonra bir tarayıcıda silentgate://import?url=… (içe aktar) veya silentgate://connect / toggle (kontrol) bağlantısına tıklamak uygulamayı açar ve eylemi gerçekleştirir. Varsayılan olarak etkin.';

  @override
  String get infoAutoConnectAfterImport =>
      'Bağlantı aracılığıyla başarılı bir abonelik içe aktarmasından hemen sonra ilk sunucuya bağlan.';

  @override
  String get infoNetworkRecover =>
      'VPN etkinken bilgisayarın çökmesi/kapanmasının ardından internet gittiyse ağ parametrelerini sıfırlar: winsock, IP yığını, DNS önbelleği, sistem proxy\'si. Yönetici hakları gerektirir; winsock ve IP yığınının sıfırlanması YENİDEN BAŞLATMADAN sonra etkinleşir.';

  @override
  String get infoInterference =>
      'SilentGate ile çakışabilecek diğer VPN\'ler ve ağ girişimleri (yabancı TUN bağdaştırıcıları, VPN süreçleri, zapret/GoodbyeDPI) için bir kontrol. Bunları kapatabilir veya yok sayabilirsiniz.';

  @override
  String get pingInfoProxyGet =>
      'Test URL\'sine tünel üzerinden bir GET isteği. Sunucunun trafiği gerçekten geçirdiğini ve 204 döndürdüğünü kontrol eder. En dürüst işlevsellik testi; yanıtı tamamen indirdiği için biraz daha yavaş. İşlevsellik kontrolü için önerilir.';

  @override
  String get pingInfoProxyHead =>
      'GET gibi, ancak yalnızca başlıkları ister — daha az trafik ve daha hızlı. Tünelin işlevselliğini kontrol eder; bazı sunucular/CDN\'ler HEAD\'i desteklemeyebilir.';

  @override
  String get pingInfoTcp =>
      'Sunucu adresine TCP el sıkışması süresini ölçer. Uç nokta gecikmesinin hızlı ve doğru bir göstergesi, ancak tünelin çalıştığını kanıtlamaz: bir Reality sunucusu, proxy engellenmiş olsa bile TCP\'ye yanıt verir. Gecikme için önerilir.';

  @override
  String get pingInfoIcmp =>
      'Sistem ping\'i (echo request). Reality/CDN için genellikle işe yaramaz: ICMP engellenmiş olabilir veya sunucu yerine en yakın CDN düğümünü ölçer. Ağ tanılaması için tutun.';

  @override
  String get pingInfoTwoPhase =>
      'TCP kontrolünden sonra, yanıt veren sunucular ayrıca tünel üzerinden bir istekle (test URL\'sine GET/HEAD) kontrol edilir. Bu, bağlantı noktasını açık tutan ancak trafiği proxy\'lemeyen sunucuları eler. Gecikme yine de TCP ile gösterilir.';

  @override
  String get pingInfoTunStage =>
      'Tam tünel (TUN) bir sonraki aşamadır. Şu anda «Sistem proxy\'si» modu kullanılıyor. TUN modunda tüm trafik (UDP ve proxy\'yi yok sayan uygulamalar dâhil) wintun sanal bağdaştırıcısı + tun2socks üzerinden geçer. Yönetici hakları gerektirir.';

  @override
  String get pingInfoTunStack =>
      'TUN ağ yığını (sing-box). auto — çekirdeğin takdirine bırakın (şu anda mixed). system — işletim sistemi yığını: maksimum hız, ama haklar/antivirüslerle daha zorlu. gvisor — kullanıcı alanı yığını: daha yavaş, ama en uyumlu. mixed — TCP system üzerinden, UDP gvisor üzerinden (bir denge). TUN bağlanmıyor veya bağlantıları düşürüyorsa — gvisor\'u deneyin.';

  @override
  String get pingInfoAutoConfig =>
      'Etkinleştirildiğinde uygulama kendisi sunucuları ve atlatma varyantlarını (fragment, fingerprint) tarar ve seçili hizmetlerin çalıştığı ilk sunucuya bağlanır (arama sırasında VPN\'i etkinleştirmeden proxy üzerinden kontrol ederek).';

  @override
  String get logsTabApp => 'Uygulama';

  @override
  String get logsTabTun => 'TUN (sing-box)';

  @override
  String get logsRefresh => 'Yenile';

  @override
  String get logsCopy => 'Kopyala';

  @override
  String get logsClearApp => 'Uygulama günlüğünü temizle';

  @override
  String get logsCopied => 'Günlük kopyalandı';

  @override
  String get logsLoading => 'Yükleniyor…';

  @override
  String get logsEmpty => 'Şimdilik boş.';

  @override
  String get logsTunEmpty => 'Boş — TUN bu sistemde henüz başlatılmadı.';

  @override
  String get importScrDone => 'İçe aktarıldı';

  @override
  String get importScrWelcome => 'SilentGate\'e hoş geldiniz';

  @override
  String get importScrTitle => 'Aboneliği içe aktar';

  @override
  String get importScrSubscriptionFallback => 'Abonelik';

  @override
  String get importScrHint =>
      'Bir abonelik bağlantısı (Remnawave), bir silentgate:// derin bağlantısı veya tek bir vless:// / vmess:// / trojan:// / ss:// / hysteria2:// bağlantısı yapıştırın';

  @override
  String get importScrLoading => 'Yükleniyor…';

  @override
  String get importScrPasteImport => 'Panodan içe aktar';

  @override
  String get importScrImportField => 'Alandan içe aktar';

  @override
  String get serversTitle => 'Sunucular';

  @override
  String serversFound(int found, int total) {
    return 'Sunucular — $total sunucudan $found tanesi bulundu';
  }

  @override
  String get serversRefresh => 'Aboneliği yenile';

  @override
  String get serversPinging => 'Pingleniyor…';

  @override
  String get serversPingAll => 'Tümünü pingle';

  @override
  String get serversPingFound => 'Bulunanları pingle';

  @override
  String get serversEmpty => 'Sunucu listesi boş. Bir abonelik içe aktarın.';

  @override
  String get serversNothingFound => 'Hiçbir şey bulunamadı';

  @override
  String get toastCopied => 'Kopyalandı';

  @override
  String get toastHide => 'Gizle';

  @override
  String get srvInfoTitle => 'Sunucu bilgisi';

  @override
  String srvInfoProbeFailed(Object error) {
    return 'Test bağlantısı başlatılamadı: $error';
  }

  @override
  String get srvInfoServerAddressFailed => 'Sunucu adresi belirlenemedi';

  @override
  String get srvInfoSectionExit => 'Nereden çıkıyorsunuz';

  @override
  String get srvInfoExitHint =>
      'Sunucu adresinden belirlenir — bunun için tünel başlatılmaz.';

  @override
  String get srvInfoAddressLocation => 'Sunucu adresi ve konumu';

  @override
  String get srvInfoCheckAgain => 'Tekrar kontrol et';

  @override
  String get srvInfoSectionSpeed => 'Hız';

  @override
  String srvInfoSpeedHint(Object size) {
    return 'Ölçüm $size indirir ve abonelik trafiğinizi kullanır. Boyut ayarlardan değiştirilebilir.';
  }

  @override
  String get srvInfoViaServer => 'Sunucu üzerinden';

  @override
  String get srvInfoWithoutVpn => 'VPN\'siz';

  @override
  String get srvInfoMeasuring => 'Ölçülüyor…';

  @override
  String get srvInfoMeasureSpeed => 'Hızı ölç';

  @override
  String get srvInfoSectionParams => 'Bağlantı parametreleri';

  @override
  String get srvInfoParamAddress => 'Adres';

  @override
  String get srvInfoParamProtocol => 'Protokol';

  @override
  String get srvInfoParamTransport => 'Taşıma';

  @override
  String get srvInfoParamTlsFingerprint => 'TLS fingerprint';

  @override
  String get srvInfoParamType => 'Tür';

  @override
  String get srvInfoPanelAutoProfile => 'Panelden otomatik seçim profili';

  @override
  String get srvInfoCouldNotDetermine => 'belirlenemedi';

  @override
  String get srvInfoCopy => 'Kopyala';

  @override
  String get editorJsonTitle => 'JSON yapılandırması';

  @override
  String get editorCopy => 'Kopyala';

  @override
  String get editorClose => 'Kapat';

  @override
  String get editorTitle => 'Sunucuyu düzenle';

  @override
  String get editorFieldName => 'Ad';

  @override
  String get editorFieldAddress => 'Adres';

  @override
  String get editorFieldPort => 'Bağlantı noktası';

  @override
  String get editorFieldUuidPassword => 'UUID / parola';

  @override
  String get editorFieldObfs => 'Gizleme (genellikle salamander)';

  @override
  String get editorFieldObfsPassword => 'Gizleme parolası';

  @override
  String get editorFieldPortHopping =>
      'Bağlantı noktası atlama (örn. 20000-21000)';

  @override
  String get editorAllowSelfSigned => 'Kendinden imzalı sertifikaya izin ver';

  @override
  String get editorAllowSelfSignedSub =>
      'Yalnızca sunucu bu şekilde yapılandırıldıysa gereklidir';

  @override
  String get editorTransport => 'Taşıma';

  @override
  String get editorSecurity => 'Güvenlik';

  @override
  String get editorNone => '(yok)';

  @override
  String get editorCancel => 'İptal';

  @override
  String get editorSave => 'Kaydet';

  @override
  String jsonProfileServers(int count, String burst) {
    return '$count sunucu$burst';
  }

  @override
  String get jsonCompositionUnknown => 'içerik bilinmiyor';

  @override
  String get jsonYourSavedOverride => 'Kaydettiğiniz JSON (geçersiz kılma)';

  @override
  String jsonPanelProfileApplied(Object summary) {
    return 'Panelden otomatik seçim profili: $summary — tamamen uygulandı';
  }

  @override
  String get jsonPanelConfig => 'Panelden yapılandırma (XRAY_JSON)';

  @override
  String get jsonBuiltFromShareLink =>
      'Paylaşım bağlantısından oluşturuldu — panel JSON göndermedi. Aboneliği güncelleyin; bu yardımcı olmazsa paneldeki Response Rules kuralını kontrol edin.';

  @override
  String get jsonInvalidJson => 'Geçersiz JSON';

  @override
  String get jsonSaved => 'Kaydedildi';

  @override
  String get jsonTitle => 'JSON yapılandırması';

  @override
  String get jsonFieldEditor => 'Alan düzenleyici';

  @override
  String get jsonCopy => 'Kopyala';

  @override
  String get jsonClose => 'Kapat';

  @override
  String get jsonSave => 'Kaydet';

  @override
  String get srvTileEdit => 'Düzenle';

  @override
  String get srvTileNotice => 'Bildirim';

  @override
  String get srvTileRefresh => 'Yenile';

  @override
  String get srvTileSubscriptionUpdated => 'Abonelik güncellendi';

  @override
  String get srvTileCopy => 'Kopyala';

  @override
  String get srvTileInfo => 'Sunucu bilgisi';

  @override
  String get srvTilePing => 'Ping';

  @override
  String get srvTileUnpin => 'Sabitlemeyi kaldır';

  @override
  String get srvTilePin => 'Sabitle';

  @override
  String get srvTileJsonConfig => 'JSON yapılandırması';

  @override
  String get srvTileSmart => 'Akıllı parametre ayarlama';

  @override
  String get srvTileDelete => 'Sil';

  @override
  String get srvTileServerDeleted => 'Sunucu silindi';

  @override
  String get srvTileSaved => 'Kaydedildi';

  @override
  String get pingNa => 'yok';

  @override
  String get pingNaTooltip => 'TCP yanıtı yok — sunucu erişilemez (ölü)';

  @override
  String get pingTimeout => 'zaman aşımı';

  @override
  String get pingTimeoutTooltip =>
      'TCP ölçümü zaman aşımı içinde tamamlanmadı — sunucu erişilemez';

  @override
  String pingMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get pingNoProxy => 'proxy yok';

  @override
  String get pingNoProxyTooltip =>
      'TCP üzerinden yanıt veriyor (gecikme gösteriliyor), ancak tünel kontrolü (GET/HEAD) başarısız oldu — trafik geçmiyor';

  @override
  String get pingOk => 'tamam';

  @override
  String get pingOkTooltip =>
      'Sunucuya TCP gecikmesi. Sunucu çalışıyor: TCP üzerinden yanıt verdi ve tünel kontrolünü (GET/HEAD) geçti';

  @override
  String get searchHint => 'Ada, ülkeye, adrese göre ara…';

  @override
  String get searchReset => 'Temizle';

  @override
  String get splitTitle => 'Ayrık tünelleme';

  @override
  String get splitTunOnlyBanner =>
      'Yalnızca TUN modunda çalışır. «Sistem proxy\'si» modunda uygulamalar proxy\'yi kullanıp kullanmayacaklarına kendileri karar verir — zorlanamazlar.';

  @override
  String get splitProxyOnlyBanner =>
      '«Yalnızca proxy» modunda yakalanacak bir şey yoktur: kurallar bu bilgisayardaki hiçbir programa uygulanmaz. «Engelle» listesi yalnızca yerel API portlarına ve yalnızca «Trafik yakalama» bölümündeki «Ayrık tünelleme kurallarını uygula» anahtarı açıksa uygulanır. Diğer kuralları burada önceden hazırlayabilirsiniz: TUN\'a geçince çalışmaya başlarlar.';

  @override
  String get splitEnableTun => 'TUN\'u etkinleştir';

  @override
  String get splitModeHeader => 'Mod';

  @override
  String get splitAppsHeader => 'Uygulamalar';

  @override
  String get splitAppsHint =>
      'Bir uygulamaya dokunarak eylemini (Tünel / Doğrudan / Engelle) ve eşleştirme yöntemini ayarlayın. Soldaki onay kutusu kuralı etkinleştirir/devre dışı bırakır.';

  @override
  String get splitByName => 'Ada göre';

  @override
  String get splitByPath => 'Yola göre';

  @override
  String get splitRuleDisabled => 'Devre dışı — kural uygulanmıyor';

  @override
  String get splitRemove => 'Kaldır';

  @override
  String get splitFromRunning => 'Çalışanlardan';

  @override
  String get splitPickInstalled => 'Uygulama seç';

  @override
  String get splitInstalledApps => 'Yüklü uygulamalar';

  @override
  String get splitPickExe => '.exe seç';

  @override
  String get splitSitesHeader => 'Siteler (alan adları)';

  @override
  String get splitSitesHint =>
      'Bir eylem (Tünel / Doğrudan / Engelle) seçmek için bir siteye dokunun. Bir alan adı alt alan adlarını da kapsar; alt alan adları bir ağaçta gruplanır. Bir bağlantı noktası belirtebilirsiniz.';

  @override
  String splitOnlyPort(Object port) {
    return 'yalnızca $port bağlantı noktası';
  }

  @override
  String get splitProgramsFileType => 'Programlar';

  @override
  String get splitRunningApps => 'Çalışan uygulamalar';

  @override
  String get splitSearchByName => 'Ada göre ara';

  @override
  String get splitNothingFound => 'Hiçbir şey bulunamadı';

  @override
  String get splitClose => 'Kapat';

  @override
  String get splitPortRange => 'Bağlantı noktası 1–65535';

  @override
  String get splitAction => 'Eylem';

  @override
  String get splitPortOptional => 'Bağlantı noktası (isteğe bağlı)';

  @override
  String get splitAnyPort => 'herhangi';

  @override
  String get splitPortHelper =>
      'Boş = herhangi bir bağlantı noktası. Aksi hâlde kural yalnızca bu bağlantı noktasına uygulanır';

  @override
  String get splitMatching => 'Eşleştirme';

  @override
  String get splitByNameSubtitle => 'Konumdan bağımsız exe adı (güvenilir)';

  @override
  String get splitByPathSubtitle => 'Exe\'nin tam yolu (tam eşleşme)';

  @override
  String get splitDone => 'Bitti';

  @override
  String get splitEnterDomain => 'Bir alan adı girin';

  @override
  String get splitAddSite => 'Site ekle';

  @override
  String get splitPort => 'Bağlantı noktası';

  @override
  String get splitAdd => 'Ekle';

  @override
  String get routeBlock => 'Engelle';

  @override
  String get routeBlocked => 'Engellendi';

  @override
  String get routeYourPc => 'Bilgisayarınız';

  @override
  String get routeTunnel => 'Tünel';

  @override
  String get routeViaVpn => 'VPN üzerinden';

  @override
  String get routeVpn => 'VPN';

  @override
  String get routeInternet => 'İnternet';

  @override
  String get routeRest => 'Diğer her şey';

  @override
  String get routeDirectly => 'Doğrudan';

  @override
  String get routeDirectPlusRest => 'Doğrudan + kalan';

  @override
  String get routeDirect => 'Doğrudan';

  @override
  String get routeEmptyList => 'liste boş';

  @override
  String get trayShow => 'Göster';

  @override
  String get trayToggle => 'Bağlan / Bağlantıyı kes';

  @override
  String get trayQuit => 'Çık';

  @override
  String get trayMinimizeTitle => 'Sistem tepsisine küçült';

  @override
  String get trayMinimizeBody =>
      'Uygulama sistem tepsisinde çalışmaya devam edecek.';

  @override
  String get trayDontAsk => 'Tekrar sorma';

  @override
  String get trayMinimizeOk => 'Küçült';

  @override
  String get trayVpnTitle => 'VPN bağlı';

  @override
  String get trayVpnBody =>
      'VPN bağlantısı kesilsin ve uygulamadan çıkılsın mı?';

  @override
  String get trayStay => 'Kal';

  @override
  String get trayQuitVpn => 'Bağlantıyı kes ve çık';

  @override
  String get tunTaskDone => 'Bitti: TUN, UAC istemi olmadan başlayacak';

  @override
  String get tunTaskFailed =>
      'Görev oluşturulamadı (UAC reddedildi veya ilke tarafından engellendi)';

  @override
  String get tunLogTitle => 'TUN günlüğü (sing-box)';

  @override
  String get tunLogEmpty => 'Günlük boş — tünel henüz başlatılmadı.';

  @override
  String get tunCopy => 'Kopyala';

  @override
  String get tunClose => 'Kapat';

  @override
  String get tunTitle => 'TUN ve yönlendirme';

  @override
  String get tunSectionPrivilege => 'Yönetici hakları';

  @override
  String get tunChecking => 'Kontrol ediliyor…';

  @override
  String get tunNoUacConfigured => 'UAC olmadan başlatma yapılandırıldı';

  @override
  String get tunUacEachConnect => 'Her bağlantıda UAC istenecek';

  @override
  String get tunTaskSubtitle =>
      'En yüksek ayrıcalıklara sahip bir Windows Görev Zamanlayıcı görevi (bir kez oluşturulur).';

  @override
  String get tunRecreateTask => 'Görevi yeniden oluştur';

  @override
  String get tunSetupOneUac => 'Ayarla (tek UAC)';

  @override
  String get tunRemoveTask => 'Görevi kaldır';

  @override
  String get tunSectionAdapter => 'Bağdaştırıcı';

  @override
  String get tunStack => 'TUN yığını';

  @override
  String get tunSectionRouting => 'Yönlendirme';

  @override
  String get tunStrictRoute => 'Katı yönlendirme (strict_route)';

  @override
  String get tunIpv6 => 'Tünelde IPv6';

  @override
  String get tunEndpointNat => 'Uç noktadan bağımsız NAT (UDP, oyunlar)';

  @override
  String get tunLanBypass => 'Yerel ağ VPN\'i atlar';

  @override
  String get tunDnsServer => 'DNS sunucusu';

  @override
  String get tunDnsHijack => 'DNS\'i yakala (bağlantı noktası 53)';

  @override
  String get tunResolveStrategy => 'Çözümleme stratejisi';

  @override
  String get tunSectionDiagnostics => 'Tanılama';

  @override
  String get tunSingboxLogLevel => 'sing-box günlük düzeyi';

  @override
  String get tunShowLog => 'TUN günlüğünü göster';

  @override
  String get tunDnsVpn => 'VPN üzerinden (önerilir)';

  @override
  String get tunDnsSystem => 'Sistem';

  @override
  String get tunDnsCustom => 'Özel sunucu';

  @override
  String get tunDnsVpnHint =>
      'İstekler TCP üzerinden tünele girer — sızıntı yok';

  @override
  String get tunDnsSystemHint => 'Windows\'taki gibi: DNS sızıntısı olası';

  @override
  String get tunDnsCustomHint => 'Belirtilen sunucu, yine tünel üzerinden';

  @override
  String get tunExcludeSubnets => 'VPN\'i atlayan alt ağlar';

  @override
  String get tunAdd => 'Ekle';

  @override
  String get urlGroupImport => 'İçe aktar';

  @override
  String get urlGroupControl => 'Kontrol';

  @override
  String get urlHintSubUrl => 'abonelik URL\'si';

  @override
  String get urlHintServerLink => 'sunucu bağlantısı';

  @override
  String get urlDescImportSub => 'Bir abonelik içe aktar';

  @override
  String get urlDescImportServer =>
      'Tek bir sunucu ekle (vless / trojan / ss / hysteria2 …)';

  @override
  String get urlDescConnect => 'VPN\'i bağla';

  @override
  String get urlDescDisconnect => 'VPN bağlantısını kes';

  @override
  String get urlDescToggle => 'VPN\'i değiştir';

  @override
  String get urlDescUpdate => 'Etkin aboneliği yenile';

  @override
  String get urlSupportedImport =>
      'İçe aktarırken uygulama şunları anlar: bir abonelik URL\'si (http/https) ve tek sunucular vless:// / vmess:// / trojan:// / ss:// / hysteria2:// (hy2://).';

  @override
  String get reportTitle => 'SilentGate — destek raporu';

  @override
  String get reportDescribeHere =>
      '>>> SORUNU BURADA AÇIKLAYIN (doldurun ve dosyayı kaydedin): <<<';

  @override
  String get reportWhatDid => 'Ne yaptınız:';

  @override
  String get reportWhatExpected => 'Ne bekliyordunuz:';

  @override
  String get reportWhatHappened => 'Ne oldu:';

  @override
  String get reportWhenStarted => 'Ne zaman başladı:';

  @override
  String get reportTechNoticeLine1 =>
      'Aşağıda teknik bilgiler var. Göndermeden önce gözden geçirin;';

  @override
  String get reportTechNoticeLine2 =>
      'burada parola veya abonelik jetonu yoktur, abonelik URL\'si gizlidir.';

  @override
  String get noRealIpTitle => 'Gerçek IP\'mi asla kullanma';

  @override
  String get noRealIpSub =>
      'VPN açıkken bile tüm «doğrudan» trafik VPN üzerinden gider (RU siteleri dahil). Yerel ağ doğrudan kalır.';

  @override
  String get flagAuto => 'AUTO';

  @override
  String get autoUpdateIntervalLabel => 'Güncelleme aralığı, sa';

  @override
  String get autoUpdatePreferSub => 'Aralığı abonelikten al';

  @override
  String get pingLegendInfo =>
      'Ping etiketi rengi: yeşil/sarı/turuncu — sunucu çalışıyor (TCP + tünelden kontrol). Gri — TCP\'ye yanıt veriyor ama trafiği proxylemiyor (tipik Reality portu). Kırmızı «n/a» — yanıt yok, hariç. Ping her zaman DOĞRUDAN ölçülür (VPN dışında).';

  @override
  String get pingUntestedHint =>
      'Henüz test edilmedi. Mobilde Hysteria2 ve “Oto” profilleri yalnızca bağlıyken ölçülür.';

  @override
  String get panelTunnelMarker => 'Kendi bölünmüş tüneli var';

  @override
  String panelInfoServers(Object n) {
    return 'Profildeki sunucular: $n (en iyisi seçilir)';
  }

  @override
  String get panelInfoDirect =>
      'Bazı trafik (ör. yerel siteler) doğrudan, VPN dışından gider';

  @override
  String get panelInfoBlock => 'Bazı trafik engellenir (reklamlar/torrentler)';

  @override
  String get serviceChecksTitle => 'Servisleri denetle';

  @override
  String get serviceChecksInfo =>
      'Altı popüler servis kendiliğinden sınanır: önce uygulama açılırken VPN kapalıyken, sonra bağlantı kurulur kurulmaz yeniden. İki nokta «önce → sonra» gösterir; böylece VPN’in neyi değiştirdiği görünür. Dokunmak yeniden sınar. Yeşil: açılıyor, turuncu: ülke engeli, kırmızı: erişilemiyor.';

  @override
  String get serviceStatusOk => 'Çalışıyor';

  @override
  String get serviceStatusGeo => 'Açılıyor ama çıkış ülkesinde engelli';

  @override
  String get serviceStatusFail => 'Açılmıyor';

  @override
  String get serviceStatusChecking => 'Denetleniyor…';

  @override
  String get serviceStatusTap => 'Denetlemek için dokunun';

  @override
  String serviceLatencyMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get homeTunAutotuneProgress => 'TUN parametreleri ayarlanıyor…';

  @override
  String get homeTunAutotuneDone => 'TUN parametreleri ayarlandı';

  @override
  String get homeTunAutotuneFailed => 'TUN parametreleri ayarlanamadı';

  @override
  String get hy2NoteTitle => 'Hysteria2 sunucuları';

  @override
  String get hy2NoteBody =>
      'Hysteria2 sunucuları yalnızca XRAY_JSON biçiminde gelir — SilentGate tam da bunu ister ve sing-box onları otomatik olarak çalıştırır. Hysteria2 listede görünmüyorsa: (Remnawave panel sahibi için) hysteria inbound\'larını etkinleştirin ve aboneliğe atayın. Not: 2.8.0 öncesi Remnawave, Hysteria2\'yi YALNIZCA XRAY_JSON\'da verir — base64/CLASH/SINGBOX\'ta yoktur, bu yüzden yukarıdaki Response Rules → XRAY_JSON kuralı zorunludur.';

  @override
  String get enumStatusDisconnected => 'Bağlantı kesildi';

  @override
  String get enumStatusConnecting => 'Bağlanıyor…';

  @override
  String get enumStatusConnected => 'Bağlandı';

  @override
  String get enumStatusDisconnecting => 'Bağlantı kesiliyor…';

  @override
  String get enumStatusError => 'Hata';

  @override
  String get enumVariantPlain => 'standart';

  @override
  String get tagAutoSelect => 'OTOMATİK';

  @override
  String get tagPanel => 'PANEL';

  @override
  String get tagPortHopping => 'PORT ATLAMA';

  @override
  String syncServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sunucu',
      one: '$count sunucu',
    );
    return '$_temp0';
  }

  @override
  String get syncNoChanges => 'değişiklik yok';

  @override
  String get errInvalidJson => 'Geçersiz JSON';

  @override
  String get errPickServerFirst => 'Önce bir sunucu seçin';

  @override
  String get errImportSubscriptionFirst => 'Önce bir abonelik içe aktarın';

  @override
  String get speedSizeFull => '20 MB';

  @override
  String get speedSizeLight => '5 MB';

  @override
  String speedMbPerSec(String value) {
    return '$value MB/sn';
  }

  @override
  String speedKbPerSec(String value) {
    return '$value KB/sn';
  }

  @override
  String portBusyTitle(int port, String by) {
    return '$port numaralı bağlantı noktası zaten $by tarafından kullanılıyor.';
  }

  @override
  String get srvTileMenu => 'Sunucu işlemleri';

  @override
  String get supportCopyReport => 'Raporu kopyala';

  @override
  String get supportReportCopied =>
      'Rapor kopyalandı — destek sohbetine yapıştırın';

  @override
  String subBarUsedOnly(String used) {
    return 'Kullanılan $used';
  }

  @override
  String get subBarUnlimitedTraffic => 'sınırsız trafik';

  @override
  String get supportDescribeLabel => 'Sorunu açıklayın';

  @override
  String get supportDescribeHint =>
      'Ne yaptınız, ne bekliyordunuz, ne oldu ve ne zaman başladı';

  @override
  String get supportDescribeRequired =>
      'Sorunu açıklayın — açıklama olmadan rapor işe yaramaz';

  @override
  String get supportNoScreenshots =>
      'Ekran görüntülerini buraya yapıştırmayın — Telegram sohbetinde ayrı mesaj olarak gönderin.';

  @override
  String get supportDescriptionSection => 'KULLANICI AÇIKLAMASI';

  @override
  String get splitAllowRealIp => 'Bu kural için gerçek IP’ye izin ver';

  @override
  String get splitAllowRealIpOn =>
      'Açık: bu bir istisnadır, trafik gerçek adresinizle çıkar';

  @override
  String get splitAllowRealIpOff =>
      'Kapalı: kural VPN üzerinden gider — koruma tüm kuralların üstündedir';

  @override
  String get splitRealIpExposed => 'gerçek IP';

  @override
  String get splitRealIpProtected => 'VPN üzerinden';

  @override
  String get vpnActiveBadge => 'VPN etkin';

  @override
  String get splitCopyDomain => 'Adresi kopyala';

  @override
  String get splitCopyPath => 'Yolu kopyala';

  @override
  String get homeServerInfo => 'Sunucu bilgisi';

  @override
  String get serverInfoVerifyInBrowser => 'Tarayıcıda doğrula';

  @override
  String get tunDnsForAll => 'Tüm uygulamaların DNS’i VPN üzerinden';

  @override
  String get infoDnsForAll =>
      'Yalnızca “Sadece seçilenler” modunda. ⚠️ Yeniden bağlandıktan sonra geçerli olur.';

  @override
  String get homeSettingsNeedReconnect =>
      'Ayar değişti — uygulamak için yeniden bağlanın';

  @override
  String blockPageWindowTitle(String app) {
    return 'Engellendi — $app';
  }

  @override
  String get blockPageHeading => 'Site engellendi';

  @override
  String blockPageBody(String host, String app) {
    return '$host adresi $app uygulamasındaki bölünmüş tünel kuralıyla engellendi.';
  }

  @override
  String get blockPageHint =>
      'Kuralı değiştirebilirsiniz: Ayarlar → Bölünmüş tünel → Siteler.';

  @override
  String get blockPageNote =>
      'Bu sayfa uygulamanın kendisinden gelir, bir ağ hatası değildir. Site açılmıyor çünkü onu engelleme listesine siz eklediniz.';

  @override
  String get settingsBlockPage => 'Engelleme bilgi sayfası';

  @override
  String get settingsBlockPageSub =>
      'Bağlantı hatası yerine, siteyi hangi kuralın kapattığını açıklayan bir sayfa açılır. Yalnızca http için çalışır: https sayfası, sisteme kendi kök sertifikamızı kurmadan değiştirilemez ve bu sertifika şifreli trafiğinizin tamamının okunmasına izin verirdi.';

  @override
  String get trayCloseFully => 'Tamamen kapat';

  @override
  String errorVpnConflictApp(String app) {
    return '$app engel oluyor gibi görünüyor: kendi VPN tüneli açık. Aynı anda iki tünel varsayılan rota için çekişir.';
  }

  @override
  String errorCloseApp(String app) {
    return '$app uygulamasını kapat';
  }

  @override
  String toastAppClosed(String app) {
    return '$app kapatıldı';
  }

  @override
  String toastAppCloseFailed(String app) {
    return '$app kapatılamadı — elle kapatın';
  }

  @override
  String get tunBlockQuic => 'QUIC (HTTP/3) engelle';

  @override
  String get infoBlockQuic =>
      'Site kuralları ADA göre eşleşir ve uygulama adı yalnızca sıradan TLS içinde görür. HTTP/3’e geçen tarayıcı ad göstermez; alan adı kuralı sessizce hiçbir şey yapmaz. Engelleme, tarayıcıyı adın görüldüğü normal bağlantıya döndürür. Siteler çalışmayı sürdürür: HTTP/3 onlar için zorunlu değildir, yalnızca video biraz daha yavaş yüklenebilir.';

  @override
  String get tunBlockEncryptedDns => 'Şifreli DNS’i (DoH/DoT) engelle';

  @override
  String get infoBlockEncryptedDns =>
      'Tarayıcılar ve Windows adresleri HTTPS üzerinden çözerek yakalamamızı atlayabilir. O zaman «Doğrudan» ve «Engelle» kuralları DNS düzeyinde hiç çalışmaz. ⚠️ Tarayıcıda sabit bir şifreli DNS sağlayıcısı seçiliyse normal DNS’e dönmez, siteleri açmayı bırakır. Bilinen sağlayıcı listesi doğası gereği eksiktir.';

  @override
  String get autoUseSpeed => 'Hızı hesaba kat';

  @override
  String get infoAutoUseSpeed =>
      'Servisler ve gecikmeye göre elemeden sonra en iyi üç aday indirmeyle sınanır ve gerçekten hızlı olan başa geçer. Hız SİZİN hattınızla karşılaştırılır: hattınızın neredeyse tamamını veren sunucu artık megabitle değil gecikmeyle değerlendirilir. ⚠️ Abonelik trafiği harcar: hattınız için 5 MB, her aday için 5 MB, tur başına yaklaşık 20 MB.';

  @override
  String get autoSpeedOwn => 'Kendi hızınız ölçülüyor…';

  @override
  String autoSpeedServer(String server, int index, int total) {
    return 'Hız ölçülüyor: $server ($index/$total)';
  }

  @override
  String autoSpeedShare(int percent) {
    return 'hattınızın %$percent kadarı';
  }

  @override
  String get conflictDialogTitle => 'Başka bir VPN bulundu';

  @override
  String conflictDialogBody(String app) {
    return 'Görünüşe göre $app kendi tüneliyle çalışıyor. Aynı anda iki tünel varsayılan rota için çekişir; bağlantı kurulamayabilir ya da ağ erişimi olmadan kurulabilir.';
  }

  @override
  String get conflictCloseAndConnect => 'Kapat ve bağlan';

  @override
  String get conflictConnectAnyway => 'Yine de bağlan';

  @override
  String get serviceChecksLegendBefore => 'Erişilebilirlik VPN olmadan ölçüldü';

  @override
  String get serviceChecksLegendAfter =>
      'Solda — VPN yokken, sağda — VPN üzerinden';

  @override
  String get serviceChecksBefore => 'VPN yokken';

  @override
  String get serviceChecksAfter => 'VPN üzerinden';

  @override
  String get serviceChecksNoBaseline => 'VPN yokken ölçülmedi';

  @override
  String autoSpeedValue(String value) {
    return '$value Mbit/sn';
  }

  @override
  String get splitShowBlockPage => 'Engelleme sayfasını göster';

  @override
  String get splitBlockPageNeedsVpn =>
      'Engelleme sayfası yalnızca VPN açıkken çalışır';

  @override
  String get srvInfoNeedsConnection =>
      'Bu platformda sunucu üzerinden ölçüm yalnızca VPN açıkken yapılabilir';

  @override
  String get serviceYoutubeThrottleNote =>
      '⚠️ Bu sınama YouTube kısıtlamasını göremez: sağlayıcı normal yanıt verir ama video hızını düşürür. Yeşil «servise erişilebiliyor» demektir, «video oynuyor» değil.';

  @override
  String get urlSchemeConnectServer =>
      'silentgate://connect?server=<sunucu adı>';

  @override
  String get urlDescConnectServer =>
      'BELİRLİ bir sunucuya bağlan. Ad, listede görünen ve aboneliğin gönderdiği addır, örn. «Polonya 1.5». Bayrak emojisi ve büyük/küçük harf önemsiz. Tam eşleşme yoksa arama devreye girer: ülke, adres veya protokol. toggle ile de çalışır.';

  @override
  String get splitSelectAllFound => 'Bulunanların tümünü seç';

  @override
  String splitAddSelected(int count) {
    return 'Ekle ($count)';
  }

  @override
  String get splitQuicNote =>
      'En az bir site kuralı varken uygulama tüm trafik için HTTP/3 (QUIC) kapatır. Aksi hâlde tarayıcı HTTP/3’e geçer, site adını bırakmaz ve kural sessizce çalışmaz. Siteler bozulmaz: sıradan TLS’e döner, yalnızca biraz yavaşlar.';

  @override
  String get splitNoRealIpBanner =>
      '«Gerçek IP’mi asla kullanma» açık: kutusu işaretsiz «Doğrudan» kuralları VPN üzerinden gider';

  @override
  String get settingsNoRealIpAffects =>
      '«Doğrudan» kurallarını etkiler: «gerçek IP’ye izin ver» kutusu işaretsizse VPN üzerinden giderler';

  @override
  String get splitAppOverrideSites => 'Site kurallarından önceliklidir';

  @override
  String get splitAppOverrideSitesSub =>
      'Bir site kuralı aksini söylese bile uygulamanın tüm trafiği bu kurala uyar';

  @override
  String get settingsMyRulesOverridePanel =>
      'Kurallarım panel kurallarından öncelikli';

  @override
  String get settingsMyRulesOverridePanelSub =>
      'Panel kendi yönlendirmesini gönderir, genelde «yerel siteler VPN’siz». Bu, sizin kurallarınızdan sonra uygulanır; «Tünel» işaretli bir site yine de gerçek IP’nizle doğrudan çıkabilir. Açık: tünel tüneldir. Bedeli: yerel siteler dolaşır ve yavaşlar.';

  @override
  String get commonOpen => 'Aç';

  @override
  String get tunRouteOnlySubnets => 'Tünele YALNIZCA bu alt ağlar';

  @override
  String get infoTunRouteOnlyCidrs =>
      'Windows\'ta trafiğinizin bir bölümünü VPN istemcisinden gerçekten bağımsız kılmanın tek yolu.\n\nNormalde tünel varsayılan rotayı üstlenir ve makinenin TÜM trafiği içine girer: «Doğrudan» işareti çekirdeğin içinde ele alınır — paketi çekirdek alır ve dışarıya kendi adına gönderir. Bu trafik tam olarak çekirdek yaşadığı sürece yaşar ve çekirdekle birlikte takılıp kalır.\n\nListe boş değilse varsayılan rota tünele verilmez: tünel yalnızca listelenen alt ağları üstlenir, geri kalan her şeyi sistem sıradan bağdaştırıcı üzerinden gönderir — istemci bu trafiği hiç görmez.\n\nBedeli: bölme adrese göre yapılır, uygulama ve site kuralları ise ada göre eşleşir. Adresi listeye girmeyen bir siteyi çekirdek hiçbir kuralla göremez. Tünelin her zamanki gibi çalışması için boş bırakın.';

  @override
  String get tunRouteOnlyWarning =>
      'Tünel yalnızca listelenen alt ağları üstlenir. Uygulama ve site kuralları YALNIZCA bunların içinde geçerlidir: tünele girmeyen trafik çekirdeğe hiç gösterilmez — böyle bir siteyi engellemek ya da başka yöne çevirmek mümkün değildir.';

  @override
  String get tunAlsoSystemProxy => 'Tünelle birlikte sistem proxy\'si';

  @override
  String get infoTunAlsoSystemProxy =>
      'Karma mod: tünel ve sistem proxy\'si aynı anda çalışır.\n\nSistem proxy\'sini dikkate alan uygulamalar (tarayıcılar, Telegram) kısa yoldan doğrudan yerel bağlantı noktasına gider, tünelin kullanıcı alanı yığınını atlar ve çekirdeğe çıplak adres yerine alan adını verir — bu uygulamalar için site kuralları daha kesin çalışır ve TLS çözümlemesine bağlı olmaktan çıkar.\n\nAncak bu, onları istemciden bağımsız YAPMAZ: yine aynı süreç üzerinden geçerler.';

  @override
  String get tunMixedModeWarning =>
      'Sistem proxy\'si üzerinden gelen bir bağlantının sahibi süreç yoktur — çekirdek için bu, yerel bir bağlantıdır. Bu yüzden böyle programlarda UYGULAMA kuralları çalışmaz. Site kuralları çalışır, hatta her zamankinden daha kesin.';

  @override
  String get tunWatchdog => 'Takılan çekirdek bekçisi';

  @override
  String get infoTunWatchdog =>
      'Tünel çekirdeğinin, takılmış sayılıp tünelin kaldırılmasına kadar kaç saniye yanıtsız kalabileceği.\n\nÇekirdek çökerse Windows arkasını kendisi toplar — bağdaştırıcı, rotalar ve güvenlik duvarı kuralları kaldırılır, ağ geri gelir. Çekirdek takılırsa hiçbir şey kaldırılmaz: bağdaştırıcı yerinde kalır ve «Doğrudan» işaretliler dâhil makinenin tüm trafiğini yutar. Dışarıdan bu «internet tamamen gitti» gibi görünür ve kendiliğinden düzelmez.\n\nBekçi ancak çekirdekten ilk başarılı yanıt geldikten sonra devreye girer: aksi hâlde hizmet bağlantı noktasının açılamadığı durumlarda bağlantıyı öldürürdü. 0 — izleme yok. En az 10 saniye.';

  @override
  String get tunWatchdogOff => 'Kapalı: tünelin takılması izlenmeyecek';

  @override
  String tunWatchdogSubtitle(int seconds) {
    return 'Çekirdek $seconds sn\'den uzun susarsa tüneli kaldır';
  }

  @override
  String get tunDnsForAllWarning =>
      'TÜM makinenin ad çözümlemesi tünelden geçecek. Tünel takılırsa, doğrudan çıkan ve VPN\'e ihtiyaç duymayan uygulamalarda bile adlar çözülemez olur — dışarıdan bu, internetin tamamen kesilmesi gibi görünür.';

  @override
  String get tunCidrInvalid => 'Ön ekli bir adres gerekir, örn. 10.8.0.0/24';

  @override
  String get geoTitle => 'Yönlendirme geo verileri';

  @override
  String get geoMissing =>
      'İndirilmedi — ülke ve kategori kuralları çalışmıyor';

  @override
  String geoPresent(String size, String date) {
    return '$size, son güncelleme $date';
  }

  @override
  String get geoDownload => 'İndir';

  @override
  String get geoUpdate => 'Güncelle';

  @override
  String geoDownloading(String file) {
    return '$file indiriliyor…';
  }

  @override
  String get geoDone => 'Geo verileri güncellendi';

  @override
  String get geoWhy =>
      'geoip.dat ve geosite.dat dosyaları, ülkelere göre adres ve kategorilere göre alan adı listeleridir. Çekirdek, abonelik panelinizin tanımladığı geoip:ru ve geosite:category-ads gibi kuralları bunlara göre çözer. Dosyalar olmadan bu tür kurallar yapılandırmadan çıkarılır.';

  @override
  String geoFileOk(String size, String date) {
    return '$size, son güncelleme $date';
  }

  @override
  String get geoFileMissing => 'dosya yok';

  @override
  String get geoFileCorrupt => 'dosya bozuk — çekirdek onu okuyamaz';

  @override
  String geoFolder(String path) {
    return 'Klasör: $path';
  }

  @override
  String get geoBundledWindows =>
      'Windows\'ta dosyalar çekirdekle birlikte gelir ve genellikle zaten yerindedir. Buradaki güncelleme, listeler eskidiğinde onları yeniden indirir.';

  @override
  String get geoSource =>
      'Kaynak, dosyaların Xray dağıtımıyla birlikte geldiği kaynağın aynısı: Loyalsoldier/v2ray-rules-dat. İndirilen dosya, aynı sürümle birlikte yayımlanan sağlama toplamıyla doğrulanır.';

  @override
  String get geoReplaceWarning =>
      'Önceki dosyalar saklanır: dosyalar değiştirildikten sonra yönlendirme kötüleşirse tek bir düğmeyle geri getirilebilirler. Aboneliğinizin kullandığı kategoriler yeni dosyada yoksa güncelleme uygulanmaz.';

  @override
  String geoBackupLine(String files, String size, String date) {
    return 'Yedek kopya var: $files — $size, $date tarihli';
  }

  @override
  String get geoRestore => 'Öncekileri geri yükle';

  @override
  String get geoRestored => 'Önceki geo verileri geri yüklendi';

  @override
  String get geoRestoreTitle => 'Önceki geo verileri geri yüklensin mi?';

  @override
  String get geoRestoreBody =>
      'Mevcut dosyalar, son güncellemeden önce kaydedilen kopyayla değiştirilecek. İnternet bağlantısı gerekmez. Bundan sonra güncel dosyaları yalnızca yeniden indirerek geri alabilirsiniz.';

  @override
  String get geoErrorCategories =>
      'Aboneliğinizin kullandığı kategoriler yeni dosyada yok. Değiştirme iptal edildi, önceki dosyalar yerinde kaldı — yönlendirme etkilenmedi. Tam olarak hangi kategorilerin eksik olduğu aşağıdaki satırda görünüyor.';

  @override
  String get geoNoWrite =>
      'Bu klasöre yazılamıyor — buraya indirme yapılamaz. Bu genellikle Program Files içine kurulumda olur: uygulamayı yönetici olarak çalıştırın.';

  @override
  String get geoCheck => 'Güncellemeyi kontrol et';

  @override
  String get geoCheckAgain => 'Tekrar kontrol et';

  @override
  String get geoChecking => 'Sürüm sorgulanıyor…';

  @override
  String geoLastCheck(String when) {
    return 'Son kontrol: $when';
  }

  @override
  String get geoNeverChecked => 'Güncelleme hiç kontrol edilmedi';

  @override
  String geoUpdateAvailable(String files, String size) {
    return 'Güncelleme mevcut: $files — $size';
  }

  @override
  String get geoSizeUnknown => 'sunucu boyutu bildirmedi';

  @override
  String get geoUpToDate => 'Güncelleme gerekmiyor: dosyalar son sürümle aynı.';

  @override
  String get geoPlanTitle => 'Geo verileri indirilsin mi?';

  @override
  String get geoPlanTitleUpdate => 'Geo verileri güncellensin mi?';

  @override
  String geoPlanFiles(String files) {
    return 'Dosyalar: $files';
  }

  @override
  String geoPlanSize(String size) {
    return 'Boyut: $size';
  }

  @override
  String get geoPlanTraffic =>
      'Dosyalar sizin bağlantınız üzerinden inecek. Mobil tarifede bu, göze çarpan bir trafik demektir.';

  @override
  String geoProgressBytes(String done, String total) {
    return '$total içinden $done';
  }

  @override
  String get geoErrorNetwork =>
      'Güncelleme sunucusuna ulaşılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';

  @override
  String get geoErrorServer =>
      'Güncelleme sunucusu isteği geri çevirdi. Büyük olasılıkla geçicidir — daha sonra tekrar deneyin.';

  @override
  String get geoErrorWrite =>
      'Dosya yazılamadı: klasör için izin yok ya da yer yetersiz.';

  @override
  String get geoErrorCorrupt =>
      'İndirilen dosya doğrulamayı geçemedi — indirme bozulmuş. Tekrar deneyin.';

  @override
  String get geoErrorOther => 'Olmadı. Ayrıntılar aşağıda.';

  @override
  String geoFailed(String error) {
    return 'İndirme başarısız: $error';
  }

  @override
  String get infoGeoAssets =>
      'geoip.dat ve geosite.dat dosyaları, ülkelere göre adres ve kategorilere göre alan adı listeleridir (örneğin «Rus siteleri», «devlet hizmetleri», «VKontakte»). Abonelik panelinizin tanımladığı yönlendirme kuralları bunlara dayanır.\n\nUygulamaya gömülü değildir: ikisi birlikte yaklaşık 30 MB tutar ve herkese gerekmez — sıradan bir sunucu bunları hiç kullanmaz.\n\nDosyalar yokken bu tür kurallar yapılandırmadan çıkarılır ve daha önce doğrudan gönderdikleri trafik VPN üzerinden gider. Bu güvenlidir ama daha yavaştır; ayrıca yerel siteler yabancı bir adresten gelen erişimi reddedebilir. Sizin belirlediğiniz site ve uygulama kuralları her durumda çalışır — bu dosyalara bağlı değildir.';

  @override
  String get supportBullet2Android =>
      '• Dokunduktan sonra rapor tek bir dosyada toplanır ve sistemin «Paylaş» penceresi açılır — Telegram\'ı seçin, rapor tek bir ek olarak gider. Sorunu yukarıdaki alana yazın: açıklama olmadan incelenecek bir şey olmaz.';

  @override
  String get supportDoneTextAndroid =>
      'Rapor tek bir dosyada toplandı. Sistem penceresinden nereye göndereceğinizi seçin — Telegram\'a metin olarak değil, ek olarak gider.';

  @override
  String get exitsHeader => 'Çıkışlar';

  @override
  String get exitsHint =>
      'Bir «Tünel» kuralı belirli bir çıkışa yönlendirilebilir: bir site Almanya üzerinden, diğeri ABD üzerinden. Çıkış seçilmezse kural eskisi gibi ana tüneli kullanır.';

  @override
  String get exitsAdd => 'Çıkış ekle';

  @override
  String get exitsEmpty => 'Henüz çıkış yok';

  @override
  String get exitsName => 'Ad';

  @override
  String get exitsNameHint => 'Almanya';

  @override
  String get exitsServers => 'Sunucular';

  @override
  String get exitsAutoSelect => 'Gecikmeye göre otomatik seçim';

  @override
  String get exitsAutoSelectSub =>
      'Çekirdek trafiği kendiliğinden çalışan bir sunucuda tutar. Bedeli: her sunucu üç dakikada bir yoklanır ve bu telefonda radyoyu uyandırır.';

  @override
  String get exitsAutoSelectNeedsTwo => 'En az iki sunucu gerekir';

  @override
  String get exitsDelete => 'Çıkışı sil';

  @override
  String get exitsNoServers => 'Sunucu yok — önce bir abonelik içe aktarın';

  @override
  String get exitsSearch => 'Sunucu ara';

  @override
  String get exitsPickAtLeastOne => 'En az bir sunucu seçin';

  @override
  String get exitsUnsupportedNote =>
      'Panelin «Oto» profilleri ve hysteria2 ayrı bir çıkış olarak çalışmaz: bunları diğer çekirdek yürütür. Bu sunucular listede devre dışıdır.';

  @override
  String get infoExits =>
      'Çıkış, «Tünel» kuralının hedefidir.\n\nVarsayılan olarak bir çıkış TEK bir sunucudur ve arka planda hiçbir maliyeti yoktur: sıradan protokoller kalıcı bağlantı tutmaz. Otomatik seçimli çok sunuculu grup yalnızca düğüm arızasına karşı güvence önemliyse gerekir — düzenli ölçümler ekler, telefonda bunlar radyo uyandırmalarıdır.\n\nÇıkış YALNIZCA «Tünel» eyleminde anlamlıdır. «Almanya üzerinden doğrudan» bir çelişkidir: doğrudan kural tüm çıkışları atlar.\n\nBir site ile alt alan adı FARKLI çıkışlara gidebilir — uygulama daha özel kuralı yukarı alır, aksi hâlde üst alan adı alt alanı yutardı.\n\nÖNEMLİ: Windows’ta sistem proxy’siyle çıkışlar hiç çalışmaz — o kipte yönlendirme kuralları oluşturulmaz. Tünel kipi gerekir.';

  @override
  String get ruleServer => 'Sunucu üzerinden';

  @override
  String get ruleServerCurrent => 'Ana sunucu ile aynı';

  @override
  String ruleServerCurrentNamed(String server) {
    return 'Ana sunucu ile aynı ($server)';
  }

  @override
  String get routeMatchByName => 'Dosya adına göre eşleştirme';

  @override
  String get routeYourApps => 'Uygulamalarınız';

  @override
  String get routeYourSites => 'Siteleriniz';

  @override
  String get routeAppsAndSites => 'Uygulamalar ve siteler';

  @override
  String get notifCompactTitle => 'Kısa bildirim';

  @override
  String get notifCompactSub =>
      'Kapalı — abonelik, sunucu ve hız, düğmelerle birlikte. Açık — başlıkta uygulama ve abonelik, altında sunucu; hız ve düğme yok.';

  @override
  String get localProxyAuthTitle => 'Yerel proxy parolası';

  @override
  String get localProxyAuthInfo =>
      'Çekirdeğin yerel bağlantı noktası (127.0.0.1) VPN\'inize açılan tam bir proxy\'dir. Parola olmadan aynı cihazdaki her program ona bağlanır ve tünelinizi olduğu gibi kullanır: çıkış IP\'niz, abonelik kotanız ve kendi ayrık tünelleme kurallarınızın atlanması — «Engelle» dediğiniz uygulamalar dâhil. Android\'de bu özellikle önemlidir: orada yerel bağlantı noktalarını yüklü her uygulama görür.\n\nYalnızca bu proxy\'ye bilerek kimlik doğrulamayı desteklemeyen bir şeyle bağlanıyorsanız kapatın.';

  @override
  String get localProxyAuthOff =>
      'Kapalı: yerel proxy cihazdaki her programa açık';

  @override
  String get localProxyAuthSystemProxy =>
      '«Sistem proxy\'si» modunda geçerli değildir: Windows yerel proxy\'ye parola iletemez. TUN modunda çalışır.';

  @override
  String get localProxyAuthRandom =>
      'Her bağlantıda yeni rastgele parola — ayarlarda saklanmaz';

  @override
  String get localProxyAuthCustom =>
      'Kendi kullanıcı adınız ve parolanız (ayar dosyasında saklanır)';

  @override
  String get localProxyCredsTitle => 'Kendi kullanıcı adınız ve parolanız';

  @override
  String get localProxyCredsUnset =>
      'Belirtilmedi — rastgele parola kullanılıyor';

  @override
  String localProxyCredsUser(String user) {
    return 'Kullanıcı adı: $user';
  }

  @override
  String get localProxyDialogTitle => 'Yerel proxy kullanıcı adı ve parolası';

  @override
  String get localProxyDialogBody =>
      'Yalnızca proxy\'mizi (127.0.0.1) başka bir programa kendiniz yazarsanız gerekir. Alanları boş bırakın, parola her bağlantıda rastgele olsun: ayarlarda saklanmaz, günlüğe ve destek raporuna da girmez. Elle belirlediğiniz parola ise ayar dosyasında düz metin olarak kalır.';

  @override
  String get localProxyFieldUser => 'Kullanıcı adı';

  @override
  String get localProxyFieldPassword => 'Parola';

  @override
  String get localProxyFieldHint => 'boş — rastgele';

  @override
  String get lockdownOnTitle => 'Sistem düzeyinde koruma açık';

  @override
  String get lockdownOnSub =>
      'Uygulama kapansa da sistem onu bellekten atsa da trafik engellenir. En güvenilir mod budur.';

  @override
  String get lockdownHalfTitle => 'Koruma yarım açık';

  @override
  String get lockdownHalfSub =>
      '«Her zaman açık VPN» seçili, ama «VPN olmadan bağlantıları engelle» kapalı. Uygulama çalıştığı sürece trafik korunur; sistem onu bellekten atarsa trafik açıktan gider.';

  @override
  String get lockdownOffTitle => 'Sistem düzeyinde koruma kapalı';

  @override
  String get lockdownOffSub =>
      'Kill switch\'imiz, uygulama çalıştığı sürece trafiği tutar. Sistem uygulamayı bellekten atarsa trafik VPN\'i atlar. «Her zaman açık VPN» ve «VPN olmadan bağlantıları engelle» seçeneklerini açın.';

  @override
  String get lockdownUnknownTitle =>
      'Sistem düzeyinde koruma: durum bilinmiyor';

  @override
  String get lockdownUnknownSub =>
      'Durum yalnızca Android 10\'dan itibaren ve tünel açıkken öğrenilebilir. El ile denetleyin: «Her zaman açık VPN» ve «VPN olmadan bağlantıları engelle».';

  @override
  String get lockdownOpenFailed =>
      'Sistemin VPN ayarları açılamadı. El ile bulun: Ayarlar → Ağ ve internet → VPN.';

  @override
  String get blockNoticeTitle => 'Engellenen siteleri bildir';

  @override
  String get blockNoticeSub =>
      'Bir uygulama ya da tarayıcı «Engelle» listesindeki bir siteye ulaşmaya çalıştığında, altta site adıyla bir bildirim çıkar. Dokunun — bu ekran açılır.';

  @override
  String get siteInsecureScheme =>
      'Adres http:// olarak yazılmış — bağlantı şifrelenmez ve sağlayıcı her şeyi görür. Tarayıcının https kullanması için «http://» kısmını silin.';

  @override
  String get exitServerGone =>
      'Bu kuralın sunucusu abonelikten kayboldu — trafik ana tünelden gidiyor';

  @override
  String exitServerUnsupported(String name) {
    return '$name\n\nBu sunucu ayrı bir çıkış olarak çalıştırılamaz: panelin «Oto» profillerini ve bazı protokolleri yalnızca Xray yürütür, çıkışları ise sing-box dağıtır. Kuralın trafiği ana tünelden gider.';
  }

  @override
  String get noticeRulesAction => 'Kurallar';

  @override
  String get geoVerdictMissingTitle => 'Geo verileri indirilmedi';

  @override
  String get geoVerdictMissingSub =>
      'Aboneliğin ülke ve kategori kuralları şu anda devre dışı — bu trafik doğrudan değil, VPN üzerinden gidiyor.';

  @override
  String get geoVerdictUnusableTitle => 'Çekirdek geo verilerini açamadı';

  @override
  String get geoVerdictUnusableSub =>
      'Dosyalar yerinde ama çekirdek onları okuyamadı. Verileri yeniden indirmek işe yarar.';

  @override
  String get geoOfferMissingSub =>
      'Onlar olmadan aboneliğin ülke ve kategori kuralları çalışmaz — bu trafik doğrudan değil, VPN üzerinden gidecek.';

  @override
  String get geoOfferDismiss => 'Bir daha önerme';

  @override
  String get pingPendingTooltip =>
      'Sunucuya TCP gecikmesi. Kanal denetimi hâlâ sürüyor — sunucunun gerçekten çalışıp çalışmadığı henüz bilinmiyor.';

  @override
  String get pingUnverifiedTooltip =>
      'Sunucuya TCP gecikmesi. Tünel üzerinden denetim yapılmadı — yalnızca erişilebilirlik biliniyor.';

  @override
  String pingMeasuredAt(String time) {
    return 'Ölçüm: $time';
  }

  @override
  String get pingChecking => 'denetleniyor';

  @override
  String autoTimer(String elapsed, String remaining) {
    return 'Geçen süre $elapsed · yaklaşık $remaining kaldı';
  }

  @override
  String autoTimerNoEstimate(String elapsed) {
    return 'Geçen süre $elapsed';
  }

  @override
  String autoSpeedRanking(String name) {
    return 'Hız ölçülüyor: $name';
  }

  @override
  String get autoWarnNoRealIp =>
      '«Gerçek IP kullanılmasın» açık — tüm trafik VPN üzerinden gidiyor.';

  @override
  String get autoWarnAllVpn =>
      '«Her şey VPN üzerinden» kipi seçili — kurallarınız şu anda geçerli değil.';

  @override
  String get autoWarnPanelOverride =>
      '«Kurallarım panel kurallarından önceliklidir» açık.';

  @override
  String get autoWarnProbesDirect =>
      'Bu, denetimin kendisini etkilemez: yoklamalar hangi ayarda olursa olsun VPN\'i atlar. Ancak TUN kipinde çekirdek süreci üzerinden geçerler — çekirdek takıldıysa tüm sonuçlar yanlış olumsuz olur.';

  @override
  String get autoWarnTurnOff => 'Kapat';

  @override
  String get toastCollapse => 'Daralt';

  @override
  String get toastExpand => 'Genişlet';

  @override
  String get toastOpenAutoConfig => 'Otomatik ayarı aç';

  @override
  String get splitAppAlreadyAdded => 'Bu uygulama zaten kural listesinde';

  @override
  String logsFileLine(String name, String size, int lines) {
    return '$name — $size, $lines satır';
  }

  @override
  String logsReportsLine(int count, String size) {
    return 'Destek raporları: $count, $size';
  }

  @override
  String get logsRetentionTitle => 'Günlükleri ve raporları sakla';

  @override
  String get logsRetentionDay => '1 gün';

  @override
  String get logsRetentionTwoWeeks => '2 hafta';

  @override
  String get logsRetentionMonth => '1 ay';

  @override
  String get logsRetentionNever => 'Hiç silme';

  @override
  String get logsRetentionInfo =>
      'Günlükler ve destek raporları, seçilen süreden eskidiklerinde silinir. Denetim uygulama açılırken yapılır. «Hiç» seçeneği her şeyi diskte bırakır — o zaman boyutu kendiniz izleyin: rapor günlükleri olduğu gibi içerir ve onlarla birlikte büyür.';

  @override
  String get logsCleanNow => 'Eskileri şimdi sil';

  @override
  String logsCleaned(int count, String size) {
    return 'Silinen dosya: $count, boşaltılan $size';
  }

  @override
  String get logsNothingToClean => 'Silinecek bir şey yok';

  @override
  String get speedTooltip => 'Bu sunucu üzerinden indirme hızı';

  @override
  String get speedFromAutoConfig => 'Hız, otomatik ayar tarafından ölçüldü';

  @override
  String get speedBlockedTooltip =>
      'Hız ölçülmüyor: sunucu kanal denetimini geçemedi (istek üzerinden geçmedi)';

  @override
  String get srvTileMeasureSpeed => 'Hızı ölç';

  @override
  String get speedRunTooltip => 'Sunucuların hızını ölç';

  @override
  String get speedConfirmTitle => 'Hız ölçülsün mü?';

  @override
  String speedConfirmBody(int count, String size, String total) {
    return '$count sunucu denetlenecek. Her biri $size boyutunda örnek indirir — aboneliğinizin trafiğinden yaklaşık $total.';
  }

  @override
  String speedConfirmSkipped(int count) {
    return 'Zaten ölçülenler atlanıyor: $count.';
  }

  @override
  String get speedConfirmRun => 'Ölç';

  @override
  String get speedNoTargets =>
      'Ölçülecek bir şey yok: hız yalnızca kanal denetimini geçen sunucularda sınanır. Önce listeyi sınayın.';

  @override
  String get speedNotVerified =>
      'Sunucu kanal denetimini geçemedi — üzerinden hız ölçmüyoruz';

  @override
  String speedProgress(int done, int total) {
    return 'Hız: $total sunucudan $done';
  }

  @override
  String get updateOnStartTitle => 'Açılışta aboneliği yenile';

  @override
  String get updateOnStartSub =>
      'Yalnızca zamanlayıcıyla değil, her seferinde taze sunucu listesi çek';

  @override
  String get apiSectionSub =>
      '127.0.0.1 üzerinde HTTP — istemciyi betiklerden yönetin';

  @override
  String get momentJustNow => 'az önce';

  @override
  String momentMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dakika önce',
      one: '$count dakika önce',
    );
    return '$_temp0';
  }

  @override
  String momentHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saat önce',
      one: '$count saat önce',
    );
    return '$_temp0';
  }

  @override
  String get serviceChecksMenuTitle => 'Bağlanınca kontrol et';

  @override
  String get serviceChecksMenuOff => 'Bağlanınca kontrol etme';

  @override
  String get serviceChecksMenuTooltip => 'Hangi servisler kontrol edilsin';

  @override
  String get serviceChecksLegendOff => 'Servis kontrolü kapalı';

  @override
  String get srvInfoAutoNever =>
      'Otomatik ayar bu sunucuyu henüz denemedi — hangi servislerin bu sunucu üzerinden çalıştığını görmek için çalıştırın.';

  @override
  String get srvInfoAutoHint =>
      'Son otomatik ayar taramasının verileri. Burada yeniden ölçüm yapılmaz.';

  @override
  String srvInfoAutoGeoNote(Object services) {
    return '$services: bu sunucu üzerinden açılıyor ama çıkış ülkesinde kullanılamıyor. Sunucunun kendisi sağlam — yalnızca bu servisler çalışmaz, onlar için başka ülkede bir çıkış gerekir.';
  }

  @override
  String get settingsSectionChecks => 'Servis kontrolü';

  @override
  String get settingsSectionAutotune => 'Otomatik ayar';

  @override
  String get settingsSpeedRankTitle => 'Otomatik seçimde hızı da dikkate al';

  @override
  String get settingsSpeedRankSub =>
      'Servis kontrolünü geçen adaylar ayrıca indirme ile ölçülür; başa gerçekten daha hızlı olan geçer. Aboneliğinizin trafiğini harcar.';

  @override
  String get settingsSpeedTopNLabel => 'Hız ölçümüne alınacak sunucu sayısı';

  @override
  String get settingsSpeedTopNSub =>
      'Artı kendi hattınızın bir ölçümü — onsuz karşılaştıracak bir şey yok: 60 Mbit/sn, 60\'lık hatta mükemmel, 300\'lük hatta kötüdür.';

  @override
  String settingsSpeedTrafficNote(Object mb) {
    return 'Her turda ≈$mb MB abonelik trafiği';
  }

  @override
  String get settingsSpeedWarnTitle => 'Hız ölçümü abonelik trafiği harcar';

  @override
  String settingsSpeedWarnBody(Object mb) {
    return 'Otomatik ayarın her turu aboneliğiniz üzerinden yaklaşık $mb MB indirir: ölçülen her sunucu için bir yoklama, artı kendi hattınız için bir yoklama. Bu megabaytlar kotanızdan düşer.';
  }

  @override
  String get settingsSpeedWarnEnable => 'Yine de aç';

  @override
  String get settingsConcurrencyTitle => 'Aynı anda yapılan kontrol sayısı';

  @override
  String get settingsConcurrencySub =>
      '1, eski davranıştır: adaylar kesinlikle sırayla kontrol edilir; sonuçlar tuhaflaşırsa dönülecek değer budur. Daha fazlası daha hızlıdır, ancak her aday kendi çekirdeğini başlatır: makine daha çok yüklenir ve gecikme ölçümleri birbirini etkilemeye başlar.';

  @override
  String get settingsConnectChecksTitle => 'Bağlanınca servisleri kontrol et';

  @override
  String get settingsConnectChecksSubOn =>
      'Tünel kalkarken tek bir tur: düğmenin altındaki rozetler neyin açıldığını, neyin açılmadığını hemen gösterir.';

  @override
  String get settingsConnectChecksSubOff =>
      'Rozetler siz dokunana kadar gri kalır.';

  @override
  String get settingsConnectCheckServices => 'Bağlanınca ne kontrol edilsin';

  @override
  String get settingsConnectCheckServicesSub =>
      'Bilerek otomatik ayardan ayrı bir küme: otomatik ayar çalışan bir sunucu arar ve uzun uğraşmaya hazırdır; bu rozetler ise “şu anda çalışıyor mu?” sorusunu yanıtlar.';

  @override
  String get settingsConnectChecksEmpty =>
      'Hiçbir servis seçilmedi — kontrol edilecek bir şey olmayacak.';

  @override
  String get settingsSectionSeamless => 'Kesintisizlik';

  @override
  String get settingsSeamlessNote =>
      'Bu seçeneklerin hiçbiri açık bağlantıları korumaz: başka sunucu, başka dış IP demektir ve karşı taraf farklı bir adres görür — görüşme ya da indirme her hâlükârda kopar. Mesele yalnızca makinenin ağının kesilip yanmaması.';

  @override
  String get settingsSeamlessServerTitle =>
      'Yalnızca sunucu değişince tüneli yeniden kurma';

  @override
  String get settingsSeamlessServerSub =>
      'Yalnızca proxy çekirdeği yeniden başlar: bağdaştırıcı ve yönlendirmeler yerinde kalır, makinenin ağı kesilip yanmaz. Bedeli: aboneliğin tüm sunucu adresleri önceden tünel dışına yazılır.';

  @override
  String get settingsSeamlessNetworkTitle => 'Ağ değişince bağlantıyı koparma';

  @override
  String get settingsSeamlessNetworkSub =>
      'Wi-Fi → mobil: önce trafiğin hâlâ canlı olup olmadığına bakarız, çekirdeği ancak ölmüşse yeniden başlatırız. QUIC (hysteria2) adres değişimini kendi başına atlatır. Bedeli: bağlantı gerçekten öldüyse kurtarma birkaç saniye geç başlar.';

  @override
  String get settingsSeamlessKeepTunTitle =>
      'Denemeler arasında bağdaştırıcıyı ayakta tut';

  @override
  String get settingsSeamlessKeepTunSub =>
      'Kurtarma sürerken varsayılan yönlendirme oynatılmaz. ⚠️ Bu bir kill switch DEĞİLDİR: VPN dışındaki trafik engellenmez, yalnızca bağdaştırıcının kendisi ayakta tutulur.';

  @override
  String get autoSpeedTrafficTitle => 'Hız ölçümü veri harcayacak';

  @override
  String autoSpeedTrafficBody(int servers, int mb) {
    return 'En iyi $servers sunucunun ve kendi bağlantınızın hızı ölçülecek — aboneliğinizin yaklaşık $mb MB trafiği.\n\nÖlçümü ayarlardan kapatabilirsiniz.';
  }

  @override
  String get autoSpeedTrafficGo => 'Başlat';

  @override
  String get splitDeadPath =>
      'Bu yoldaki dosya artık yok — kural hiç eşleşmiyor';

  @override
  String get splitDeadPathFix => 'Dosya adına göre eşleştirmek için dokunun';

  @override
  String get srvTileCopyKey => 'Anahtarı kopyala';

  @override
  String serviceChecksBypassDirect(Object rule) {
    return 'VPN dışında: bölünmüş tünel kuralı “$rule” bu alan adını doğrudan gönderiyor — servis gerçek adresinizle çalışacak.';
  }

  @override
  String serviceChecksBypassBlock(Object rule) {
    return 'Engelli: bölünmüş tünel kuralı “$rule” bu alan adını yasaklıyor — servis VPN ile de VPN’siz de açılmaz.';
  }

  @override
  String get subBarOpenSite => 'Web sitesi';

  @override
  String get subBarOpenSiteHint => 'Abonelik sayfasını tarayıcıda aç';

  @override
  String subSwitcherRefreshingOne(Object name) {
    return '\"$name\" yenileniyor…';
  }

  @override
  String subSwitcherRefreshedOne(Object name) {
    return '\"$name\" güncellendi';
  }

  @override
  String subSwitcherRefreshFailedOne(Object name) {
    return '\"$name\" güncellenemedi';
  }

  @override
  String subBarDeleteConfirmNamed(Object name) {
    return '\"$name\" aboneliği silinsin mi?';
  }
}
