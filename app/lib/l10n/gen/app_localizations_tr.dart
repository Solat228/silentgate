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
      'Çekirdek çöktüyse, sunucu düştüyse veya ağ değiştiyse (Wi-Fi ↔ kablo, uykudan uyanma, yeni bir IP), uygulama bağlantıyı kendisi geri getirir. Denemeler arası duraklamalar artar: 0,8 sn → 3 sn → 8 sn → 20 sn, en fazla 8 deneme, ardından bir hata gösterilir. Düğmeyle bağlantı kesmek kurtarmayı her zaman iptal eder.\n\nAğ değişikliği diğer bağdaştırıcıların gerçek adreslerinden tespit edilir: kendi tünel ve hizmet adresleriniz (link-local) sayılmaz, değişiklik yalnızca üst üste iki ölçümde tutunursa kabul edilir ve sinyal, bağlandıktan sonraki ilk 15 saniye boyunca yok sayılır. Bu önlemler olmadan tüneli kurmanın kendisi bir «ağ değişikliği» sayılır ve sonsuz yeniden bağlanmaya neden olur.';

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
      'Bir servisin etkin VPN bağlantısı üzerinden açılıp açılmadığını denetlemek için ona dokunun. Denetim elle yapılır — hiçbir şey otomatik denetlenmez. Yapay zekâ servisleri için çıkış ülkesindeki bölge engeli de saptanır.';

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
  String get splitAllowRealIp => 'Gerçek IP’ye izin ver';

  @override
  String get splitAllowRealIpOn =>
      'Bu kural VPN’i atlar — site gerçek adresinizi görür';

  @override
  String get splitAllowRealIpOff => 'Bu kural korumada — VPN üzerinden gider';

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
}
