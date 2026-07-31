// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonCopy => 'Kopieren';

  @override
  String get commonCopied => 'Kopiert';

  @override
  String get commonRefresh => 'Aktualisieren';

  @override
  String get commonCheck => 'Prüfen';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDone => 'Fertig';

  @override
  String get commonPathCopied => 'Pfad kopiert';

  @override
  String get languageTitle => 'Oberflächensprache';

  @override
  String get languageSubtitle => 'Sprache der App wählen';

  @override
  String get languageSystem => 'Systemstandard';

  @override
  String get sectionAppearance => 'Darstellung und Verhalten';

  @override
  String get sectionCapture => 'Verkehrserfassung';

  @override
  String get sectionReliability => 'Verbindungszuverlässigkeit';

  @override
  String get sectionPing => 'Ping';

  @override
  String get sectionIdentity => 'Panel-Identität';

  @override
  String get sectionNetwork => 'Netzwerk';

  @override
  String get sectionAbout => 'Über';

  @override
  String get sectionSupport => 'Support';

  @override
  String get appearanceTheme => 'Design';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get closeToTrayTitle => 'Beim Schließen in den Infobereich minimieren';

  @override
  String get closeToTraySubtitle =>
      'Die Schließen-Schaltfläche blendet das Fenster in den Infobereich aus; deaktivieren, um die App stattdessen zu beenden';

  @override
  String get autoUpdateSubTitle => 'Abonnement automatisch aktualisieren';

  @override
  String get autoUpdateSubText => 'Serverliste regelmäßig aktualisieren';

  @override
  String get captureSystemProxy => 'Systemproxy';

  @override
  String get captureSystemProxySub =>
      'Funktioniert sofort. Keine Administratorrechte.';

  @override
  String get captureTun => 'TUN (vollständiger Tunnel)';

  @override
  String get captureTunBadgeUac => 'benötigt UAC';

  @override
  String get captureTunSub =>
      'Gesamter Verkehr, einschließlich UDP und Apps, die den Proxy ignorieren. Erfordert Administratorrechte.';

  @override
  String get tunProvider => 'TUN-Anbieter';

  @override
  String get tunRoutingTitle => 'TUN und Routing';

  @override
  String tunRoutingSub(String stack, int mtu, String dns) {
    return 'Stack $stack · MTU $mtu · DNS $dns';
  }

  @override
  String get splitTunnelTitle => 'Split-Tunneling';

  @override
  String splitRulesCount(int n, int apps, int sites) {
    return '$n Regeln ($apps Apps, $sites Websites)';
  }

  @override
  String get captureTunHint =>
      'TUN-, DNS- und Split-Tunneling-Einstellungen erscheinen, wenn der TUN-Modus ausgewählt ist — im Systemproxy-Modus haben sie keine Wirkung.';

  @override
  String get dnsShortVpn => 'über VPN';

  @override
  String get dnsShortSystem => 'System';

  @override
  String get dnsShortCustom => 'benutzerdefiniert';

  @override
  String get tunUacTitle => 'TUN erfordert Administratorrechte';

  @override
  String get tunUacBody =>
      'Sie können es einmalig einrichten: Die App erstellt eine Aufgabe in der Windows-Aufgabenplanung mit höchsten Rechten, danach startet der Tunnel OHNE UAC-Abfrage.\n\nJetzt erscheint eine einzige Administrator-Abfrage. Die App selbst läuft weiterhin ohne erhöhte Rechte.';

  @override
  String get tunUacLater => 'Später (jedes Mal fragen)';

  @override
  String get tunUacSetup => 'Einrichten';

  @override
  String get tunUacDone => 'Fertig: TUN startet ohne UAC-Abfrage';

  @override
  String get tunUacFail =>
      'Aufgabe konnte nicht erstellt werden — UAC wird beim Verbinden angefordert';

  @override
  String get autoReconnectTitle => 'Automatisch neu verbinden';

  @override
  String get autoReconnectSub =>
      'Verbindung bei Abbruch und Netzwerkwechsel wiederherstellen';

  @override
  String get killSwitchTitle => 'Kill-Switch';

  @override
  String get alwaysOnTitle => 'Systemweiter Leckschutz';

  @override
  String get alwaysOnSub =>
      'Always-on-VPN mit „Verbindungen ohne VPN blockieren“ — wirkt auch bei geschlossener App';

  @override
  String get killSwitchSubTun =>
      'Lässt keinen Verkehr am VPN vorbei, während neu verbunden wird';

  @override
  String get killSwitchSubProxy =>
      'Im Modus „Systemproxy“ schützt er nur proxyfähige Apps. Vollständig — nur TUN';

  @override
  String get killSwitchSubOff =>
      'Erfordert aktiviertes automatisches Neuverbinden';

  @override
  String get networkRecoverTitle => 'Netzwerk wiederherstellen';

  @override
  String get networkRecoverSub =>
      'Falls nach dem VPN kein Internet mehr da ist. Erfordert Administratorrechte';

  @override
  String get networkRecoverConfirmTitle => 'Netzwerk wiederherstellen?';

  @override
  String get networkRecoverConfirmBody =>
      'Zurücksetzen von Winsock, IP-Stack, DNS und Systemproxy. Administratorrechte (UAC) sind erforderlich. Das Zurücksetzen von Winsock/IP wird nach einem Neustart wirksam.';

  @override
  String get networkRecoverConfirmOk => 'Wiederherstellen';

  @override
  String get interferenceTitle => 'Auf Störungen prüfen (andere VPNs)';

  @override
  String get interferenceDialogTitle => 'Netzwerkstörungen';

  @override
  String get interferenceNoneFound =>
      'Keine anderen VPNs oder Störungen erkannt.';

  @override
  String get interferenceIgnore => 'Ignorieren';

  @override
  String get identityUserAgent => 'User-Agent';

  @override
  String identityUaAutoNote(String version) {
    return 'Wird automatisch mit der App-Version aktualisiert. Ebenfalls gesendet: X-HWID, X-Device-OS, X-Ver-OS, X-App-Version ($version).';
  }

  @override
  String get urlSchemesTitle => 'URL-Schemata';

  @override
  String get urlSchemesSub =>
      'VPN über Links importieren und steuern (verbinden / umschalten / aktualisieren)';

  @override
  String get panelOwnerTitle => 'Für den Panel-Besitzer';

  @override
  String get panelOwnerBody =>
      'Normale Nutzer brauchen das nicht — Sie können es überspringen.\n\nDamit die App Ihr Abonnement im richtigen JSON-Format (XRAY_JSON) erhält, fügen Sie diesen Block zu den Response Rules Ihres Remnawave-Panels hinzu — er passt zu unserem User-Agent:';

  @override
  String get panelOwnerCopy => 'Block kopieren';

  @override
  String get aboutVersion => 'SilentGate-Version';

  @override
  String get aboutXrayCore => 'Xray-Kern';

  @override
  String get aboutHwid => 'Geräte-HWID';

  @override
  String get aboutThirdPartyTitle => 'Drittanbieter-Komponenten und Lizenzen';

  @override
  String get aboutThirdPartySub =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), Wintun — laufen als separate Prozesse';

  @override
  String get aboutThirdPartySubEmbedded =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), libXray (MIT) — in die App eingebettet';

  @override
  String get thirdPartyBodyEmbedded =>
      'On Android the cores are BUILT INTO the app (a native library inside the APK).\n\n• sing-box — GPL-3.0. The library is linked into the app, so derivatives must stay under GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nClient source code: https://github.com/Solat228/silentgate\nFull license texts — buttons below.';

  @override
  String get logsTitle => 'Protokolle';

  @override
  String get logsSub =>
      'App und TUN (sing-box): Abonnement-Import, Ping, Fehler';

  @override
  String get thirdPartyTitle => 'Drittanbieter-Komponenten';

  @override
  String get thirdPartyBody =>
      'SilentGate wird zusammen mit ausführbaren Dateien von Drittanbietern ausgeliefert. Sie laufen als SEPARATE Prozesse und sind nicht in die App eingebettet.\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  TUN-Tunnel und Proxy-Kern für Hysteria2\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — Wintun-Lizenz\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — Routing-Daten, CC-BY-SA-4.0\n\nDie vollständigen Lizenztexte befinden sich im Ordner „licenses“ neben der App.';

  @override
  String get supportSectionNote =>
      'Tippen Sie auf „Support kontaktieren“ — es öffnet sich ein Fenster, in dem Sie selbst eine Protokolldatei erzeugen (Versionen, Betriebssystem, Einstellungen, app.log + Ende von singbox.log; keine Passwörter oder Abonnement-Token, URL verborgen). Danach erscheint eine Schaltfläche, um es an den Telegram-Support zu senden.';

  @override
  String get supportButtonTitle => 'Support kontaktieren';

  @override
  String get supportButtonSub =>
      'Protokoll erzeugen und den Support-Chat öffnen';

  @override
  String get supportDialogTitle => 'Support';

  @override
  String get supportDialogTitleDone => 'Protokoll ist bereit — wohin senden';

  @override
  String get supportWhatWillHappen => 'Was passieren wird:';

  @override
  String get supportBullet1 =>
      '• Eine Datei sammelt Versionen, Betriebssystem, Einstellungen und Protokolle (app.log + Ende von singbox.log). Sie enthält keine Passwörter oder Abonnement-Token, die Abonnement-URL ist verborgen.';

  @override
  String get supportBullet2 =>
      '• Nach dem Tippen öffnet sich ZUERST der Ordner mit der Datei, dann die Datei selbst. Beschreiben Sie das Problem oben, speichern Sie — und eine Schaltfläche zum Senden an den Support erscheint.';

  @override
  String supportError(String error) {
    return 'Bericht konnte nicht erstellt werden: $error';
  }

  @override
  String get supportDoneText =>
      'Der Bericht wurde erstellt und geöffnet (Ordner, dann Datei). Beschreiben Sie das Problem oben, speichern Sie die Datei und senden Sie sie an den Support — die App hilft beim Öffnen von Telegram.';

  @override
  String get supportWhoTo => 'Wohin senden:';

  @override
  String get supportContact => 'Support kontaktieren';

  @override
  String supportContactNamed(String name) {
    return 'Support kontaktieren ($name)';
  }

  @override
  String get supportDevServiceName => 'Client-Entwickler';

  @override
  String get supportShowOnPc => 'Am PC anzeigen';

  @override
  String get supportCopyPath => 'Pfad kopieren';

  @override
  String get supportGenerating => 'Wird erstellt…';

  @override
  String get supportGenerateButton => 'Support-Protokoll erzeugen';

  @override
  String get pingTwoPhaseTitle => 'Funktionalität prüfen (durch den Tunnel)';

  @override
  String get pingTwoPhaseSubOn =>
      'Nach TCP — eine Anfrage über den Server: filtert nicht funktionierende heraus (Reality usw.)';

  @override
  String get pingTwoPhaseSubOff =>
      'Es wird nur die einzelne ausgewählte Methode (unten) verwendet';

  @override
  String get pingMethodCheck => 'Prüfmethode:';

  @override
  String get pingMethodPing => 'Ping-Methode:';

  @override
  String get speedTestProbe => 'Geschwindigkeitstest-Probe:';

  @override
  String get speedTestFull => '20 MB (genauer)';

  @override
  String get speedTestLight => '5 MB (sparsam)';

  @override
  String get testUrlLabel => 'Test-URL (über Proxy)';

  @override
  String get appUpdateServerUnavailable => 'Update-Server nicht erreichbar';

  @override
  String appUpdateAvailable(String version) {
    return 'Version $version verfügbar';
  }

  @override
  String get appUpdateLatest => 'Sie haben die neueste Version';

  @override
  String get appUpdateDownload => 'Herunterladen';

  @override
  String get appUpdateCheckTitle => 'Beim Start nach Updates suchen';

  @override
  String get appUpdateManual => 'Herunterladen und Installieren — manuell';

  @override
  String get appUpdateEndpointLabel => 'Versions-Endpunkt';

  @override
  String get urlSchemeSilentgateTitle => 'silentgate://-Links';

  @override
  String get urlSchemeSilentgateSub =>
      'VPN über Links importieren und steuern. Standardmäßig aktiviert';

  @override
  String get urlSchemeDisableTitle => 'silentgate://-Links deaktivieren?';

  @override
  String get urlSchemeDisableBody =>
      'Import über Link und Steuerungsschemata (verbinden / trennen / umschalten / aktualisieren) funktionieren nicht mehr. Lassen Sie es an, wenn Sie unsicher sind.';

  @override
  String get urlSchemeDisableOk => 'Deaktivieren';

  @override
  String get urlSchemeServerTitle => 'Server-Links öffnen';

  @override
  String get urlSchemeServerSub =>
      'vless:// und andere von anderen Clients abfangen';

  @override
  String get urlSchemeServerConfirmTitle => 'Server-Links abfangen?';

  @override
  String urlSchemeServerConfirmBody(String schemes) {
    return '$schemes\n\nDiese Links sind normalerweise an einen anderen VPN-Client (Happ, v2rayTun) gebunden. SilentGate übernimmt sie.';
  }

  @override
  String get urlSchemeServerConfirmOk => 'Abfangen';

  @override
  String get urlSchemeAutoConnect => 'Nach dem Import verbinden';

  @override
  String get autoTitle => 'Automatische Konfiguration';

  @override
  String get autoClearResults => 'Ergebnisse löschen';

  @override
  String autoFoundWorking(Object count) {
    return 'Funktionierende gefunden: $count';
  }

  @override
  String get autoPinnedTop => ' — oben an die Liste angeheftet';

  @override
  String get autoSearchContinues => ' (Suche läuft weiter…)';

  @override
  String get autoCheckServices => 'Dienste prüfen';

  @override
  String get autoPinFoundOnTop => 'Gefundene Server oben an die Liste anheften';

  @override
  String get autoTryFragment => 'Umgehung versuchen (Fragment)';

  @override
  String get autoNoSubscriptionPasteKey =>
      'Kein Abonnement. Fügen Sie einen einzelnen Schlüssel ein — wir finden funktionierende Einstellungen:';

  @override
  String get autoTuneByKey => 'Nach Schlüssel einstellen';

  @override
  String autoTesting(int index, int total) {
    return 'Test $index/$total: ';
  }

  @override
  String autoVariant(Object label) {
    return 'Variante: $label';
  }

  @override
  String autoServicesPassed(int ok, int total) {
    return '$ok von $total Diensten';
  }

  @override
  String get autoConnect => 'Verbinden';

  @override
  String get autoStopSearch => 'Suche stoppen';

  @override
  String get autoDoneRefreshPing =>
      'Fertig — Ping der gefundenen aktualisieren';

  @override
  String autoFoundPinnedRefreshing(Object count) {
    return '$count gefunden, oben angeheftet. Ping wird aktualisiert…';
  }

  @override
  String autoServersForTuning(int selected, int total) {
    return 'Server zum Einstellen ($selected/$total)';
  }

  @override
  String get autoSelectAll => 'Alle';

  @override
  String get autoDeselectAll => 'Leeren';

  @override
  String get autoTuneSelected => 'Ausgewählte einstellen';

  @override
  String autoTuned(Object label) {
    return 'Eingestellt: $label';
  }

  @override
  String get infoDialogTitle => 'Info';

  @override
  String get infoCopied => 'Erklärung kopiert';

  @override
  String get commonGotIt => 'Verstanden';

  @override
  String get enumSplitAll => 'Alles — über VPN';

  @override
  String get enumSplitOnly => 'Nur ausgewählte — über VPN';

  @override
  String get enumSplitExcept => 'Ausgewählte — außerhalb des VPN';

  @override
  String get enumActionTunnel => 'Tunnel';

  @override
  String get enumActionDirect => 'Direkt';

  @override
  String get enumActionBlock => 'Blockieren';

  @override
  String homeUpdateAvailable(Object version) {
    return 'Version $version verfügbar';
  }

  @override
  String get homeDownload => 'Herunterladen';

  @override
  String homeSubscriptionUpdated(Object summary) {
    return 'Abonnement aktualisiert: $summary';
  }

  @override
  String get homeReconnect => 'Neu verbinden';

  @override
  String homePingProgress(int done, int total) {
    return 'Server werden gepingt: $done von $total';
  }

  @override
  String get homeAutoConfigStarting =>
      'Automatische Konfiguration wird gestartet…';

  @override
  String homeAutoConfigProgress(int current, int total, String name) {
    return 'Automatische Konfiguration: $current von $total — $name';
  }

  @override
  String get homeImport => 'Importieren';

  @override
  String get homeSettings => 'Einstellungen';

  @override
  String get homeAutoBest => 'Auto (bester Server)';

  @override
  String get homeAutoConfig => 'Automatische Konfiguration';

  @override
  String homeServersCount(Object count) {
    return 'Server ($count)';
  }

  @override
  String homeFoundCount(int found, int total) {
    return '$found von $total gefunden';
  }

  @override
  String get homePingServers => 'Server pingen';

  @override
  String get homePingFound => 'Gefundene pingen';

  @override
  String get homeNothingFound => 'Nichts gefunden';

  @override
  String get homeOnboardingTitle =>
      'Beginnen Sie mit dem Import eines Abonnements';

  @override
  String get homeOnboardingSubtitle =>
      'Fügen Sie einen Remnawave-Link oder einen einzelnen Schlüssel ein';

  @override
  String get homeImportSubscription => 'Abonnement importieren';

  @override
  String homeSessionTraffic(String down, String up) {
    return 'Diese Sitzung: ↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'GB';

  @override
  String subBarUsage(String used, String total) {
    return '$used von $total';
  }

  @override
  String get subBarSubscription => 'Abonnement';

  @override
  String get subBarRefreshing => 'Wird aktualisiert…';

  @override
  String get subBarRefreshSubscription => 'Abonnement aktualisieren';

  @override
  String get subBarSupport => 'Support';

  @override
  String get subBarRefresh => 'Aktualisieren';

  @override
  String get subBarAddSubscription => 'Abonnement hinzufügen';

  @override
  String get subBarCopyLink => 'Link kopieren';

  @override
  String get subBarDeleteSubscription => 'Abonnement löschen';

  @override
  String get subBarLinkCopied => 'Link kopiert';

  @override
  String get subBarDeleteConfirmTitle => 'Abonnement löschen?';

  @override
  String get subBarDeleteConfirmBody =>
      'Server aus diesem Abonnement werden aus der Liste entfernt.';

  @override
  String subBarDeletePinned(Object count) {
    return 'Auch angeheftete ($count) mit ihren Änderungen löschen';
  }

  @override
  String get subBarDeletePinnedHint =>
      'Andernfalls bleiben sie in der Liste und überstehen das Löschen';

  @override
  String get subBarCancel => 'Abbrechen';

  @override
  String get subBarDelete => 'Löschen';

  @override
  String get subBarSubscriptionDeleted => 'Abonnement gelöscht';

  @override
  String subBarSubscriptionUpdated(Object summary) {
    return 'Abonnement aktualisiert: $summary';
  }

  @override
  String get subBarMore => 'Details';

  @override
  String subBarAdded(Object count) {
    return 'Hinzugefügt ($count)';
  }

  @override
  String subBarRemoved(Object count) {
    return 'Entfernt ($count)';
  }

  @override
  String subBarAutoUpdate(Object hours) {
    return '· Auto-Update $hours Std.';
  }

  @override
  String subBarValidPerpetual(Object auto) {
    return 'Gültig: unbegrenzt  $auto';
  }

  @override
  String get subBarExpired => 'Abonnement abgelaufen:';

  @override
  String get subBarValidUntil => 'Gültig bis:';

  @override
  String get infoCaptureMode =>
      'Wie der Verkehr abgefangen wird. „Systemproxy“ richtet einen lokalen Proxy im System ein (keine Administratorrechte; erfasst Browser und die meisten Anwendungen). „TUN“ ist ein virtueller Netzwerkadapter, der den GESAMTEN Verkehr erfasst (einschließlich UDP und Anwendungen, die den Proxy ignorieren), erfordert aber Administratorrechte.';

  @override
  String get infoSystemProxy =>
      'Ein lokaler HTTP-Proxy in den Systemeinstellungen (WinINET-Registry). Keine Administratorrechte. Fängt weder UDP noch Anwendungen ab, die den Systemproxy ignorieren.';

  @override
  String get infoTunMode =>
      'Ein vollständiger Tunnel durch den virtuellen wintun-Adapter + sing-box. Erfasst den gesamten Verkehr, einschließlich UDP. Fordert beim Aktivieren Administratorrechte (UAC) an.';

  @override
  String get infoTunProvider =>
      'Der Treiber für den virtuellen Netzwerkadapter. Unter Windows wird wintun verwendet (im Kern enthalten). Es sind keine weiteren Treiber erforderlich.';

  @override
  String get infoTunStack =>
      'Der TUN-Netzwerkstack (sing-box).\n\n„auto“ — AUTOMATISCHE AUSWAHL: Wenn der Tunnel nicht aufgebaut werden kann, durchläuft die App selbst system → gvisor → mixed und senkt anschließend die MTU (1400, 1280). Die funktionierende Kombination wird gemerkt und beim nächsten Mal zuerst versucht. Der Auswahlfortschritt wird im Status und im Protokoll angezeigt.\n\nEine explizite Auswahl deaktiviert die Auto-Auswahl: system — der Betriebssystem-Stack, am schnellsten, aber empfindlicher gegenüber Antivirenprogrammen; gvisor — im Userspace, langsamer, maximal kompatibel; mixed — TCP über system, UDP über gvisor.';

  @override
  String get infoTunMtu =>
      'Die maximale Paketgröße im TUN-Adapter. Standard ist 1500; senken Sie sie (1400, 1280) bei Verbindungsabbrüchen — ein zu kleiner Wert verringert die Geschwindigkeit.\n\nMit dem „auto“-Stack ist dies nur der Startwert: Wenn der Tunnel nicht aufgebaut werden kann, versucht die App selbst kleinere MTUs.';

  @override
  String get infoTunStrictRoute =>
      'Striktes Routing in sing-box. Unter Windows behebt es zwei typische Probleme: DNS-Leaks (standardmäßig sendet das System Anfragen an alle Adapter gleichzeitig) und „Netzwerk nicht erreichbar“-Fehler. Deaktivieren Sie es nur, wenn es VirtualBox/Hyper-V beeinträchtigt.';

  @override
  String get infoTunIpv6 =>
      'IPv6 in den Tunnel leiten. Wenn Sie es deaktivieren, während Ihr Anbieter IPv6 aktiviert hat, geht ein Teil des Verkehrs AM VPN VORBEI (und gibt Ihre echte Adresse preis) oder hängt. Deaktivieren Sie es nur bei IPv6-Netzwerkproblemen.';

  @override
  String get infoTunEndpointIndependentNat =>
      'NAT-Modus für UDP. Wird für Spiele, Sprach-Chats und WebRTC benötigt — ohne ihn lassen sich Verbindungen möglicherweise nicht aufbauen. Deaktivieren Sie ihn nur, um Speicher zu sparen.';

  @override
  String get infoTunBypassLan =>
      'Das lokale Netzwerk (private Adressen 192.168.*, 10.*, Router, Drucker, NAS) geht am VPN vorbei. Normalerweise sollte dies aktiviert sein, sonst verlieren Sie den Zugriff auf Geräte im Netzwerk.';

  @override
  String get infoTunExcludeCidrs =>
      'Zusätzliche Subnetze, die immer am VPN vorbeigehen (CIDR-Format, z. B. 10.8.0.0/24). Nützlich für Unternehmensnetzwerke und andere VPNs.';

  @override
  String get infoTunPrivilege =>
      'TUN erfordert Administratorrechte. Einmalig erstellen wir eine Aufgabe in der Windows-Aufgabenplanung mit höchsten Rechten — danach startet der Tunnel bei jeder Verbindung OHNE UAC-Abfrage. Die Aufgabe gehört Ihnen und wird mit der Schaltfläche unten oder bei der Deinstallation des Programms entfernt.';

  @override
  String get infoAppUpdate =>
      'Einmal pro Start fragt die App Ihren Server, ob eine neuere Version existiert, und zeigt eine Benachrichtigung mit einer „Herunterladen“-Schaltfläche an.\n\nDie App lädt und startet NICHTS von selbst: Der Installer ist nicht mit einem Zertifikat signiert, und das automatische Ausführen einer heruntergeladenen exe stößt auf SmartScreen und sieht für Antivirenprogramme wie Schadverhalten aus. Sie installieren das Update selbst.\n\nIst der Server nicht erreichbar, bleibt die App einfach still und schreibt einen Eintrag ins Protokoll. Das Antwortformat und die Servereinrichtung sind in docs/APP_UPDATE.md beschrieben.';

  @override
  String get infoSpeedTest =>
      'Die beim Messen der Geschwindigkeit heruntergeladene Datenmenge (Rechtsklick auf einen Server → „Serverinfo“ → „Geschwindigkeit messen“).\n\n20 MB — der Hauptmodus: Auf schnellen Verbindungen (100+ Mbit/s) kommt eine kurze Probe nicht in Fahrt und unterschätzt das Ergebnis.\n5 MB — der sparsame Modus: deutlich günstiger beim Verkehr, praktisch für den Durchlauf vieler Server.\n\nDie Messung läuft NUR manuell und verbraucht den Verkehr Ihres Abonnements. Die Geschwindigkeit wird zweimal gemessen: direkt und über den ausgewählten Server, damit Sie genau sehen, wie viel am VPN verloren geht.';

  @override
  String get infoAutoReconnect =>
      'Wenn der Kern abgestürzt ist, der Server abgebrochen ist oder sich das Netzwerk geändert hat (WLAN ↔ Kabel, Aufwachen aus dem Ruhezustand, eine neue IP), stellt die App die Verbindung selbst wieder her. Die Pausen zwischen den Versuchen wachsen: 0,8 s → 3 s → 8 s → 20 s, bis zu 8 Versuche, danach wird ein Fehler angezeigt. Das Trennen mit der Schaltfläche bricht die Wiederherstellung immer ab.\n\nEin Netzwerkwechsel wird an den echten Adressen anderer Adapter erkannt: der eigene Tunnel und Dienstadressen (link-local) zählen nicht, ein Wechsel wird nur akzeptiert, wenn er zwei Abfragen hintereinander Bestand hatte, und das Signal wird in den ersten 15 Sekunden nach dem Verbinden ignoriert. Ohne diese Sicherungen würde der Aufbau des Tunnels selbst als „Netzwerkwechsel“ zählen und endloses Neuverbinden verursachen.';

  @override
  String get infoKillSwitch =>
      'Lässt keinen Verkehr am VPN vorbei nach draußen, während die Verbindung wiederhergestellt wird. Die Erfassung wird zwischen den Versuchen NICHT freigegeben: im TUN-Modus bleibt der Adapter aktiv, im Modus „Systemproxy“ bleibt der Proxy konfiguriert — Anwendungen erhalten einen Verbindungsfehler statt unverschlüsselten Internetzugriff.\n\nEhrlich zu den Grenzen: Im Modus „Systemproxy“ schützt dies nur Programme, die den Systemproxy respektieren (Browser und die meisten Anwendungen). Programme, die den Proxy ignorieren, sowie UDP gehen direkt — vollständige Dichtheit bietet nur der TUN-Modus. Erfordert aktiviertes automatisches Neuverbinden.';

  @override
  String get infoUserAgent =>
      'Wie sich die App gegenüber dem Panel identifiziert (der User-Agent-Header). Sie sendet immer „SilentGate/Version (Windows)“.\n\nAnhand dieses Namens wählt das Remnawave-Panel das FORMAT des Abonnements. XRAY_JSON wird benötigt — es liefert fertige Serverkonfigurationen; aus einer base64-Liste von Links werden einige Einstellungen nur näherungsweise wiederhergestellt, und die automatische Auswahl (burstObservatory) funktioniert schlechter.\n\nIm Panel konfiguriert: Templates → Response Rules → eine Regel mit der Bedingung user-agent CONTAINS SilentGate und dem Antworttyp XRAY_JSON (platzieren Sie sie oberhalb der Fallback-Base64-Regel).\n\nDas Überschreibungsfeld wird nur als vorübergehende Umgehung benötigt — wenn das Panel die App noch nicht kennt, können Sie sich als ein ihm bekannter Client identifizieren.';

  @override
  String get infoDnsMode =>
      'Wer im TUN-Modus Domains auflöst. „Über VPN“ (empfohlen) — Anfragen gehen über TCP in den Tunnel, und Ihr Anbieter sieht nicht, welche Websites Sie öffnen. „System“ — wie in Windows: ein DNS-Leak ist möglich, und wenn der Server kein UDP durchlässt, kann das Internet ganz ausfallen. „Benutzerdefiniert“ — der von Ihnen angegebene Server, durch den Tunnel.';

  @override
  String get infoDnsCustomServer =>
      'Die Adresse des DNS-Servers für den Modus „Benutzerdefiniert“ (zum Beispiel 9.9.9.9 oder 8.8.8.8). Anfragen an ihn gehen über TCP durch den Tunnel.';

  @override
  String get infoDnsHijack =>
      'DNS-Anfragen (UDP-Port 53) innerhalb des Tunnels abfangen. Ohne dies umgehen Anfragen die Regeln: ein Leak ist möglich, und die Domain-Regeln des Split-Tunnelings arbeiten weniger präzise.';

  @override
  String get infoDnsStrategy =>
      'Welche Adressen abgefragt werden: prefer_ipv4 (empfohlen) — zuerst IPv4, ipv4_only — nur IPv4 (behebt Probleme mit defektem IPv6), prefer_ipv6/ipv6_only — für IPv6-Netzwerke.';

  @override
  String get infoSingboxLogLevel =>
      'Die Ausführlichkeit des sing-box-Protokolls (%APPDATA%\\SilentGate\\singbox.log). warn — Normalmodus. info/debug — wenn der Tunnel nicht funktioniert: Das Protokoll zeigt die genaue Ursache. debug vergrößert die Dateigröße merklich.';

  @override
  String get infoSplitMode =>
      'Die Basis — wohin alles geht, dem keine manuell festgelegte Aktion zugewiesen ist, und welche Aktion neuen Einträgen zugewiesen wird. „Alles — über VPN“: standardmäßig der gesamte Verkehr in den Tunnel. „Nur ausgewählte — über VPN“: standardmäßig direkt, in den Tunnel nur die als „Tunnel“ markierten. „Ausgewählte — außerhalb des VPN“: umgekehrt, alles in den Tunnel, und die als „Direkt“ markierten gehen direkt.';

  @override
  String get infoSplitApps =>
      'Klicken Sie auf eine Anwendung — es öffnet sich ein Fenster, in dem Sie die Aktion wählen (Tunnel — über VPN, Direkt — am VPN vorbei, Blockieren — kein Netzwerk) und die Zuordnungsmethode: nach exe-Name (zuverlässig) oder nach vollständigem Pfad. Sie können aus laufenden Apps wählen oder eine .exe angeben.';

  @override
  String get infoSplitDomains =>
      'Domains (Suffixe). Zum Beispiel deckt youtube.com auch www.youtube.com ab. Funktioniert anhand des Namens aus der TLS-Verbindung (SNI).';

  @override
  String get infoVerifyViaProxy =>
      'Zuerst prüfen wir die Funktionalität über den Proxy (der Server gibt tatsächlich 204 zurück), und nur wenn der Server geantwortet hat, messen wir separat die Latenz mit der gewählten Methode (TCP/ICMP).';

  @override
  String get infoProxyGet =>
      'Eine GET-Anfrage durch den Tunnel an die Test-URL. Prüft, dass der Server tatsächlich Verkehr durchlässt und 204 zurückgibt. Der ehrlichste Funktionstest; etwas langsamer.';

  @override
  String get infoProxyHead =>
      'Wie GET, aber nur die Header — schneller und weniger Verkehr. Manche Server/CDNs unterstützen HEAD möglicherweise nicht.';

  @override
  String get infoTcp =>
      'Die Zeit des TCP-Handshakes zur Serveradresse. Ein schneller und genauer Latenzindikator, der aber nicht beweist, dass der Tunnel funktioniert: Ein Reality-Server antwortet auf TCP, selbst wenn das Proxying blockiert ist. Empfohlen für die Latenz.';

  @override
  String get infoIcmp =>
      'System-Ping. Für Reality/CDN oft nutzlos: ICMP kann blockiert sein oder es misst den nächstgelegenen CDN-Knoten. Behalten Sie es für die Netzwerkdiagnose.';

  @override
  String get infoTestUrl =>
      'Die URL zur Prüfung der Funktionalität über den Proxy. Standardmäßig https://www.gstatic.com/generate_204 — sie gibt eine leere 204-Antwort zurück, was praktisch und schnell ist.';

  @override
  String get infoAutoConfig =>
      'Durchläuft Server und Umgehungsvarianten (Fragment, Fingerprint) und erstellt eine Liste derer, bei denen die ausgewählten Dienste funktionieren. Es stoppt nicht beim ersten — Sie wählen aus den gefundenen. Die Prüfung erfolgt über den Proxy; das VPN wird dabei nicht aktiviert.';

  @override
  String get infoAutoConfigServices =>
      'Welche Dienste funktionieren müssen, damit ein Server als geeignet gilt. Die Prüfung ist robust gegenüber Ersatzseiten des Anbieters (die Signatur der Antwort wird überprüft, nicht nur ein „200 OK“).';

  @override
  String get infoAutoPinFound =>
      'Gefundene funktionierende Kombinationen (Server + Umgehungsvariante) werden sofort oben an die allgemeine Serverliste angeheftet, sodass Sie sie nutzen können, ohne hierher zurückzukehren. Deaktivieren Sie es, wenn die automatische Konfiguration die Reihenfolge Ihrer Liste nicht ändern soll — die Ergebnisse bleiben auf diesem Bildschirm sichtbar.';

  @override
  String get infoTryFragment =>
      'Versuchen Sie die Variante mit TLS-ClientHello-Fragmentierung (DPI-Umgehung), wenn der „nackte“ Server nicht funktioniert. Etwas länger, findet aber auf gedrosselten Servern eine funktionierende Kombination.';

  @override
  String get infoAutoStrategy =>
      '„Erster funktionierender“ — alles durchlaufen und mit einem beliebigen gefundenen verbinden (Sie wählen). „Bester im Budget“ — innerhalb eines Zeitlimits suchen und den schnellsten wählen.';

  @override
  String get infoScheme =>
      'Registriert das silentgate://-Protokoll im System (für den aktuellen Benutzer, ohne Administratorrechte). Danach öffnet ein Klick auf einen Link silentgate://import?url=… (Import) oder silentgate://connect / toggle (Steuerung) im Browser die App und führt die Aktion aus. Standardmäßig aktiviert.';

  @override
  String get infoAutoConnectAfterImport =>
      'Unmittelbar nach einem erfolgreichen Abonnement-Import über einen Link mit dem ersten Server verbinden.';

  @override
  String get infoNetworkRecover =>
      'Setzt Netzwerkparameter zurück, falls nach einem Absturz/Herunterfahren des PCs mit aktiviertem VPN kein Internet mehr da ist: Winsock, den IP-Stack, den DNS-Cache, den Systemproxy. Erfordert Administratorrechte; das Zurücksetzen von Winsock und dem IP-Stack wird nach einem NEUSTART wirksam.';

  @override
  String get infoInterference =>
      'Eine Prüfung auf andere VPNs und Netzwerkstörungen (fremde TUN-Adapter, VPN-Prozesse, zapret/GoodbyeDPI), die mit SilentGate in Konflikt geraten können. Sie können sie schließen oder ignorieren.';

  @override
  String get pingInfoProxyGet =>
      'Eine GET-Anfrage durch den Tunnel an die Test-URL. Prüft, dass der Server tatsächlich Verkehr durchlässt und 204 zurückgibt. Der ehrlichste Funktionstest; etwas langsamer, da die Antwort vollständig heruntergeladen wird. Empfohlen für eine Funktionsprüfung.';

  @override
  String get pingInfoProxyHead =>
      'Wie GET, fragt aber nur die Header ab — weniger Verkehr und schneller. Prüft die Funktionalität des Tunnels; manche Server/CDNs unterstützen HEAD möglicherweise nicht.';

  @override
  String get pingInfoTcp =>
      'Misst die Zeit des TCP-Handshakes zur Serveradresse. Ein schneller und genauer Indikator für die Endpunkt-Latenz, der aber nicht beweist, dass der Tunnel funktioniert: Ein Reality-Server antwortet auf TCP, selbst wenn das Proxying blockiert ist. Empfohlen für die Latenz.';

  @override
  String get pingInfoIcmp =>
      'System-Ping (Echo-Anfrage). Für Reality/CDN oft nutzlos: ICMP kann blockiert sein oder es misst den nächstgelegenen CDN-Knoten statt des Servers. Behalten Sie es für die Netzwerkdiagnose.';

  @override
  String get pingInfoTwoPhase =>
      'Nach der TCP-Prüfung werden die Server, die geantwortet haben, zusätzlich mit einer Anfrage durch den Tunnel geprüft (GET/HEAD an die Test-URL). Dies filtert Server heraus, die den Port offen halten, aber keinen Verkehr proxyfähig durchleiten. Die Latenz wird weiterhin per TCP angezeigt.';

  @override
  String get pingInfoTunStage =>
      'Ein vollständiger Tunnel (TUN) ist die nächste Stufe. Derzeit wird der Modus „Systemproxy“ verwendet. Im TUN-Modus geht der gesamte Verkehr (einschließlich UDP und Anwendungen, die den Proxy ignorieren) durch den virtuellen wintun-Adapter + tun2socks. Erfordert Administratorrechte.';

  @override
  String get pingInfoTunStack =>
      'Der TUN-Netzwerkstack (sing-box). auto — dem Ermessen des Kerns überlassen (derzeit mixed). system — der Betriebssystem-Stack: maximale Geschwindigkeit, aber empfindlicher gegenüber Rechten/Antivirenprogrammen. gvisor — ein Userspace-Stack: langsamer, aber am kompatibelsten. mixed — TCP über system, UDP über gvisor (ein Ausgleich). Wenn TUN keine Verbindung herstellt oder Verbindungen abbrechen — versuchen Sie gvisor.';

  @override
  String get pingInfoAutoConfig =>
      'Wenn aktiviert, durchläuft die App selbst Server und Umgehungsvarianten (Fragment, Fingerprint) und verbindet sich mit dem ersten, bei dem die ausgewählten Dienste funktionieren (Prüfung über den Proxy, ohne das VPN während der Suche zu aktivieren).';

  @override
  String get logsTabApp => 'App';

  @override
  String get logsTabTun => 'TUN (sing-box)';

  @override
  String get logsRefresh => 'Aktualisieren';

  @override
  String get logsCopy => 'Kopieren';

  @override
  String get logsClearApp => 'App-Protokoll leeren';

  @override
  String get logsCopied => 'Protokoll kopiert';

  @override
  String get logsLoading => 'Wird geladen…';

  @override
  String get logsEmpty => 'Vorerst leer.';

  @override
  String get logsTunEmpty =>
      'Leer — TUN wurde auf diesem System noch nicht gestartet.';

  @override
  String get importScrDone => 'Importiert';

  @override
  String get importScrWelcome => 'Willkommen bei SilentGate';

  @override
  String get importScrTitle => 'Abonnement importieren';

  @override
  String get importScrSubscriptionFallback => 'Abonnement';

  @override
  String get importScrHint =>
      'Fügen Sie einen Abonnement-Link (Remnawave), einen silentgate://-Deep-Link oder einen einzelnen vless:// / vmess:// / trojan:// / ss:// / hysteria2://-Link ein';

  @override
  String get importScrLoading => 'Wird geladen…';

  @override
  String get importScrPasteImport => 'Aus Zwischenablage importieren';

  @override
  String get importScrImportField => 'Aus Feld importieren';

  @override
  String get serversTitle => 'Server';

  @override
  String serversFound(int found, int total) {
    return 'Server — $found von $total gefunden';
  }

  @override
  String get serversRefresh => 'Abonnement aktualisieren';

  @override
  String get serversPinging => 'Wird gepingt…';

  @override
  String get serversPingAll => 'Alle pingen';

  @override
  String get serversPingFound => 'Gefundene pingen';

  @override
  String get serversEmpty =>
      'Die Serverliste ist leer. Importieren Sie ein Abonnement.';

  @override
  String get serversNothingFound => 'Nichts gefunden';

  @override
  String get toastCopied => 'Kopiert';

  @override
  String get toastHide => 'Ausblenden';

  @override
  String get srvInfoTitle => 'Serverinformationen';

  @override
  String srvInfoProbeFailed(Object error) {
    return 'Testverbindung konnte nicht gestartet werden: $error';
  }

  @override
  String get srvInfoServerAddressFailed =>
      'Serveradresse konnte nicht ermittelt werden';

  @override
  String get srvInfoSectionExit => 'Wo Sie hinausgehen';

  @override
  String get srvInfoExitHint =>
      'Anhand der Serveradresse ermittelt — dafür wird kein Tunnel gestartet.';

  @override
  String get srvInfoAddressLocation => 'Serveradresse und Standort';

  @override
  String get srvInfoCheckAgain => 'Erneut prüfen';

  @override
  String get srvInfoSectionSpeed => 'Geschwindigkeit';

  @override
  String srvInfoSpeedHint(Object size) {
    return 'Die Probe lädt $size herunter und verbraucht Ihren Abonnement-Verkehr. Die Größe kann in den Einstellungen geändert werden.';
  }

  @override
  String get srvInfoViaServer => 'Über Server';

  @override
  String get srvInfoWithoutVpn => 'Ohne VPN';

  @override
  String get srvInfoMeasuring => 'Wird gemessen…';

  @override
  String get srvInfoMeasureSpeed => 'Geschwindigkeit messen';

  @override
  String get srvInfoSectionParams => 'Verbindungsparameter';

  @override
  String get srvInfoParamAddress => 'Adresse';

  @override
  String get srvInfoParamProtocol => 'Protokoll';

  @override
  String get srvInfoParamTransport => 'Transport';

  @override
  String get srvInfoParamTlsFingerprint => 'TLS-Fingerprint';

  @override
  String get srvInfoParamType => 'Typ';

  @override
  String get srvInfoPanelAutoProfile => 'Auto-Auswahl-Profil aus dem Panel';

  @override
  String get srvInfoCouldNotDetermine => 'konnte nicht ermittelt werden';

  @override
  String get srvInfoCopy => 'Kopieren';

  @override
  String get editorJsonTitle => 'JSON-Konfiguration';

  @override
  String get editorCopy => 'Kopieren';

  @override
  String get editorClose => 'Schließen';

  @override
  String get editorTitle => 'Server bearbeiten';

  @override
  String get editorFieldName => 'Name';

  @override
  String get editorFieldAddress => 'Adresse';

  @override
  String get editorFieldPort => 'Port';

  @override
  String get editorFieldUuidPassword => 'UUID / Passwort';

  @override
  String get editorFieldObfs => 'Obfuskation (meist salamander)';

  @override
  String get editorFieldObfsPassword => 'Obfuskations-Passwort';

  @override
  String get editorFieldPortHopping => 'Port-Hopping (z. B. 20000-21000)';

  @override
  String get editorAllowSelfSigned => 'Selbstsigniertes Zertifikat zulassen';

  @override
  String get editorAllowSelfSignedSub =>
      'Nur nötig, wenn der Server so konfiguriert ist';

  @override
  String get editorTransport => 'Transport';

  @override
  String get editorSecurity => 'Sicherheit';

  @override
  String get editorNone => '(keine)';

  @override
  String get editorCancel => 'Abbrechen';

  @override
  String get editorSave => 'Speichern';

  @override
  String jsonProfileServers(int count, String burst) {
    return '$count Server$burst';
  }

  @override
  String get jsonCompositionUnknown => 'Zusammensetzung unbekannt';

  @override
  String get jsonYourSavedOverride => 'Ihr gespeichertes JSON (Überschreibung)';

  @override
  String jsonPanelProfileApplied(Object summary) {
    return 'Auto-Auswahl-Profil aus dem Panel: $summary — vollständig angewendet';
  }

  @override
  String get jsonPanelConfig => 'Konfiguration aus dem Panel (XRAY_JSON)';

  @override
  String get jsonBuiltFromShareLink =>
      'Aus dem Share-Link erstellt — das Panel hat kein JSON gesendet. Aktualisieren Sie das Abonnement; falls das nicht hilft, prüfen Sie die Response-Rules-Regel im Panel.';

  @override
  String get jsonInvalidJson => 'Ungültiges JSON';

  @override
  String get jsonSaved => 'Gespeichert';

  @override
  String get jsonTitle => 'JSON-Konfiguration';

  @override
  String get jsonFieldEditor => 'Feld-Editor';

  @override
  String get jsonCopy => 'Kopieren';

  @override
  String get jsonClose => 'Schließen';

  @override
  String get jsonSave => 'Speichern';

  @override
  String get srvTileEdit => 'Bearbeiten';

  @override
  String get srvTileNotice => 'Hinweis';

  @override
  String get srvTileRefresh => 'Aktualisieren';

  @override
  String get srvTileSubscriptionUpdated => 'Abonnement aktualisiert';

  @override
  String get srvTileCopy => 'Kopieren';

  @override
  String get srvTileInfo => 'Serverinformationen';

  @override
  String get srvTilePing => 'Ping';

  @override
  String get srvTileUnpin => 'Lösen';

  @override
  String get srvTilePin => 'Anheften';

  @override
  String get srvTileJsonConfig => 'JSON-Konfiguration';

  @override
  String get srvTileSmart => 'Intelligente Parametereinstellung';

  @override
  String get srvTileDelete => 'Löschen';

  @override
  String get srvTileServerDeleted => 'Server gelöscht';

  @override
  String get srvTileSaved => 'Gespeichert';

  @override
  String get pingNa => 'n/v';

  @override
  String get pingNaTooltip =>
      'Keine TCP-Antwort — Server nicht erreichbar (tot)';

  @override
  String get pingTimeout => 'Zeitüberschreitung';

  @override
  String get pingTimeoutTooltip =>
      'TCP-Probe wurde nicht innerhalb der Zeitüberschreitung abgeschlossen — Server nicht erreichbar';

  @override
  String pingMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get pingNoProxy => 'kein Proxy';

  @override
  String get pingNoProxyTooltip =>
      'Antwortet über TCP (Latenz angezeigt), aber die Tunnelprüfung (GET/HEAD) ist fehlgeschlagen — es geht kein Verkehr durch';

  @override
  String get pingOk => 'ok';

  @override
  String get pingOkTooltip =>
      'TCP-Latenz zum Server. Server funktioniert: Er hat über TCP geantwortet und die Tunnelprüfung (GET/HEAD) bestanden';

  @override
  String get searchHint => 'Suche nach Name, Land, Adresse…';

  @override
  String get searchReset => 'Leeren';

  @override
  String get splitTitle => 'Split-Tunneling';

  @override
  String get splitTunOnlyBanner =>
      'Funktioniert nur im TUN-Modus. Im Modus „Systemproxy“ entscheiden Apps selbst, ob sie den Proxy verwenden — sie können nicht gezwungen werden.';

  @override
  String get splitEnableTun => 'TUN aktivieren';

  @override
  String get splitModeHeader => 'Modus';

  @override
  String get splitAppsHeader => 'Anwendungen';

  @override
  String get splitAppsHint =>
      'Tippen Sie auf eine App, um ihre Aktion (Tunnel / Direkt / Blockieren) und Zuordnungsmethode festzulegen. Das Kontrollkästchen links aktiviert/deaktiviert die Regel.';

  @override
  String get splitByName => 'Nach Name';

  @override
  String get splitByPath => 'Nach Pfad';

  @override
  String get splitRuleDisabled => 'Deaktiviert — Regel wird nicht angewendet';

  @override
  String get splitRemove => 'Entfernen';

  @override
  String get splitFromRunning => 'Aus laufenden';

  @override
  String get splitPickInstalled => 'App auswählen';

  @override
  String get splitInstalledApps => 'Installierte Apps';

  @override
  String get splitPickExe => '.exe wählen';

  @override
  String get splitSitesHeader => 'Websites (Domains)';

  @override
  String get splitSitesHint =>
      'Tippen Sie auf eine Website, um eine Aktion zu wählen (Tunnel / Direkt / Blockieren). Eine Domain deckt auch ihre Subdomains ab; Subdomains werden in einem Baum gruppiert. Sie können einen Port angeben.';

  @override
  String splitOnlyPort(Object port) {
    return 'nur Port $port';
  }

  @override
  String get splitProgramsFileType => 'Programme';

  @override
  String get splitRunningApps => 'Laufende Anwendungen';

  @override
  String get splitSearchByName => 'Suche nach Name';

  @override
  String get splitNothingFound => 'Nichts gefunden';

  @override
  String get splitClose => 'Schließen';

  @override
  String get splitPortRange => 'Port 1–65535';

  @override
  String get splitAction => 'Aktion';

  @override
  String get splitPortOptional => 'Port (optional)';

  @override
  String get splitAnyPort => 'beliebig';

  @override
  String get splitPortHelper =>
      'Leer = beliebiger Port. Andernfalls gilt die Regel nur für diesen Port';

  @override
  String get splitMatching => 'Zuordnung';

  @override
  String get splitByNameSubtitle =>
      'Exe-Name, unabhängig vom Speicherort (zuverlässig)';

  @override
  String get splitByPathSubtitle =>
      'Vollständiger Pfad zur exe (exakte Übereinstimmung)';

  @override
  String get splitDone => 'Fertig';

  @override
  String get splitEnterDomain => 'Domain eingeben';

  @override
  String get splitAddSite => 'Website hinzufügen';

  @override
  String get splitPort => 'Port';

  @override
  String get splitAdd => 'Hinzufügen';

  @override
  String get routeBlock => 'Blockieren';

  @override
  String get routeBlocked => 'Blockiert';

  @override
  String get routeYourPc => 'Ihr PC';

  @override
  String get routeTunnel => 'Tunnel';

  @override
  String get routeViaVpn => 'Über VPN';

  @override
  String get routeVpn => 'VPN';

  @override
  String get routeInternet => 'Internet';

  @override
  String get routeRest => 'Alles andere';

  @override
  String get routeDirectly => 'Direkt';

  @override
  String get routeDirectPlusRest => 'Direkt + Rest';

  @override
  String get routeDirect => 'Direkt';

  @override
  String get routeEmptyList => 'Liste ist leer';

  @override
  String get trayShow => 'Anzeigen';

  @override
  String get trayToggle => 'Verbinden / Trennen';

  @override
  String get trayQuit => 'Beenden';

  @override
  String get trayMinimizeTitle => 'In den Infobereich minimieren';

  @override
  String get trayMinimizeBody => 'Die App läuft im Infobereich weiter.';

  @override
  String get trayDontAsk => 'Nicht mehr fragen';

  @override
  String get trayMinimizeOk => 'Minimieren';

  @override
  String get trayVpnTitle => 'VPN verbunden';

  @override
  String get trayVpnBody => 'VPN trennen und die App beenden?';

  @override
  String get trayStay => 'Bleiben';

  @override
  String get trayQuitVpn => 'Trennen und beenden';

  @override
  String get tunTaskDone => 'Fertig: TUN startet ohne UAC-Abfrage';

  @override
  String get tunTaskFailed =>
      'Aufgabe konnte nicht erstellt werden (UAC abgelehnt oder durch Richtlinie blockiert)';

  @override
  String get tunLogTitle => 'TUN-Protokoll (sing-box)';

  @override
  String get tunLogEmpty =>
      'Protokoll ist leer — der Tunnel wurde noch nicht gestartet.';

  @override
  String get tunCopy => 'Kopieren';

  @override
  String get tunClose => 'Schließen';

  @override
  String get tunTitle => 'TUN und Routing';

  @override
  String get tunSectionPrivilege => 'Administratorrechte';

  @override
  String get tunChecking => 'Wird geprüft…';

  @override
  String get tunNoUacConfigured => 'Start ohne UAC ist konfiguriert';

  @override
  String get tunUacEachConnect => 'UAC wird bei jeder Verbindung angefordert';

  @override
  String get tunTaskSubtitle =>
      'Eine Aufgabe der Windows-Aufgabenplanung mit höchsten Rechten (einmalig erstellt).';

  @override
  String get tunRecreateTask => 'Aufgabe neu erstellen';

  @override
  String get tunSetupOneUac => 'Einrichten (ein UAC)';

  @override
  String get tunRemoveTask => 'Aufgabe entfernen';

  @override
  String get tunSectionAdapter => 'Adapter';

  @override
  String get tunStack => 'TUN-Stack';

  @override
  String get tunSectionRouting => 'Routing';

  @override
  String get tunStrictRoute => 'Striktes Routing (strict_route)';

  @override
  String get tunIpv6 => 'IPv6 im Tunnel';

  @override
  String get tunEndpointNat => 'Endpunktunabhängiges NAT (UDP, Spiele)';

  @override
  String get tunLanBypass => 'Lokales Netzwerk umgeht das VPN';

  @override
  String get tunDnsServer => 'DNS-Server';

  @override
  String get tunDnsHijack => 'DNS abfangen (Port 53)';

  @override
  String get tunResolveStrategy => 'Auflösungsstrategie';

  @override
  String get tunSectionDiagnostics => 'Diagnose';

  @override
  String get tunSingboxLogLevel => 'sing-box-Protokollstufe';

  @override
  String get tunShowLog => 'TUN-Protokoll anzeigen';

  @override
  String get tunDnsVpn => 'Über VPN (empfohlen)';

  @override
  String get tunDnsSystem => 'System';

  @override
  String get tunDnsCustom => 'Benutzerdefinierter Server';

  @override
  String get tunDnsVpnHint =>
      'Anfragen gehen über TCP in den Tunnel — keine Leaks';

  @override
  String get tunDnsSystemHint => 'Wie in Windows: DNS-Leak möglich';

  @override
  String get tunDnsCustomHint =>
      'Der angegebene Server, ebenfalls durch den Tunnel';

  @override
  String get tunExcludeSubnets => 'Subnetze, die das VPN umgehen';

  @override
  String get tunAdd => 'Hinzufügen';

  @override
  String get urlGroupImport => 'Import';

  @override
  String get urlGroupControl => 'Steuerung';

  @override
  String get urlHintSubUrl => 'Abonnement-URL';

  @override
  String get urlHintServerLink => 'Server-Link';

  @override
  String get urlDescImportSub => 'Ein Abonnement importieren';

  @override
  String get urlDescImportServer =>
      'Einen einzelnen Server hinzufügen (vless / trojan / ss / hysteria2 …)';

  @override
  String get urlDescConnect => 'Das VPN verbinden';

  @override
  String get urlDescDisconnect => 'Das VPN trennen';

  @override
  String get urlDescToggle => 'Das VPN umschalten';

  @override
  String get urlDescUpdate => 'Das aktive Abonnement aktualisieren';

  @override
  String get urlSupportedImport =>
      'Beim Import versteht die App: eine Abonnement-URL (http/https) sowie einzelne Server vless:// / vmess:// / trojan:// / ss:// / hysteria2:// (hy2://).';

  @override
  String get reportTitle => 'SilentGate — Support-Bericht';

  @override
  String get reportDescribeHere =>
      '>>> BESCHREIBEN SIE DAS PROBLEM HIER (ausfüllen und die Datei speichern): <<<';

  @override
  String get reportWhatDid => 'Was Sie getan haben:';

  @override
  String get reportWhatExpected => 'Was Sie erwartet haben:';

  @override
  String get reportWhatHappened => 'Was passiert ist:';

  @override
  String get reportWhenStarted => 'Wann es begann:';

  @override
  String get reportTechNoticeLine1 =>
      'Nachfolgend technische Informationen. Prüfen Sie sie vor dem Senden;';

  @override
  String get reportTechNoticeLine2 =>
      'hier gibt es keine Passwörter oder Abonnement-Token, die Abonnement-URL ist verborgen.';

  @override
  String get noRealIpTitle => 'Nie meine echte IP verwenden';

  @override
  String get noRealIpSub =>
      'Auch bei aktivem VPN läuft der gesamte „direkte“ Verkehr über das VPN (auch RU-Seiten). Das lokale Netzwerk bleibt direkt.';

  @override
  String get flagAuto => 'AUTO';

  @override
  String get autoUpdateIntervalLabel => 'Aktualisierungsintervall, Std.';

  @override
  String get autoUpdatePreferSub => 'Intervall aus dem Abo verwenden';

  @override
  String get pingLegendInfo =>
      'Farbe des Ping-Badges: grün/gelb/orange — Server funktioniert (TCP + Prüfung durch den Tunnel). Grau — antwortet über TCP, leitet aber keinen Verkehr weiter (typischer Reality-Port). Rot „n/a“ — keine Antwort, ausgeschlossen. Ping wird immer DIREKT gemessen (außerhalb des VPN).';

  @override
  String get pingUntestedHint =>
      'Noch nicht geprüft. Auf Mobilgeräten werden Hysteria2 und „Auto“-Profile nur bei aktiver Verbindung gemessen.';

  @override
  String get panelTunnelMarker => 'Eigenes Split-Tunneling';

  @override
  String panelInfoServers(Object n) {
    return 'Server im Profil: $n (der beste wird gewählt)';
  }

  @override
  String get panelInfoDirect =>
      'Ein Teil des Verkehrs (z. B. lokale Seiten) geht direkt, außerhalb des VPN';

  @override
  String get panelInfoBlock =>
      'Ein Teil des Verkehrs wird blockiert (Werbung/Torrents)';

  @override
  String get serviceChecksTitle => 'Dienste prüfen';

  @override
  String get serviceChecksInfo =>
      'Sechs beliebte Dienste werden automatisch geprüft: zuerst beim Start der App bei ausgeschaltetem VPN, dann noch einmal direkt nach dem Verbinden. Die zwei Punkte zeigen „vorher → nachher“, damit sichtbar wird, was das VPN tatsächlich geändert hat. Tippen prüft erneut. Grün: erreichbar, Orange: Ländersperre, Rot: nicht erreichbar.';

  @override
  String get serviceStatusOk => 'Funktioniert';

  @override
  String get serviceStatusGeo => 'Öffnet, aber im Ausgangsland gesperrt';

  @override
  String get serviceStatusFail => 'Öffnet nicht';

  @override
  String get serviceStatusChecking => 'Prüfung…';

  @override
  String get serviceStatusTap => 'Zum Prüfen tippen';

  @override
  String serviceLatencyMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get homeTunAutotuneProgress => 'TUN-Parameter werden abgestimmt…';

  @override
  String get homeTunAutotuneDone => 'TUN-Parameter abgestimmt';

  @override
  String get homeTunAutotuneFailed =>
      'TUN-Parameter konnten nicht abgestimmt werden';

  @override
  String get hy2NoteTitle => 'Hysteria2-Server';

  @override
  String get hy2NoteBody =>
      'Hysteria2-Server kommen nur im Format XRAY_JSON — SilentGate fordert genau dieses an, und sing-box startet sie automatisch. Falls Hysteria2 nicht in der Liste erscheint: (für den Remnawave-Panel-Betreiber) aktivieren Sie die Hysteria-Inbounds und weisen Sie sie dem Abo zu. Hinweis: Remnawave vor 2.8.0 liefert Hysteria2 NUR in XRAY_JSON — in base64/CLASH/SINGBOX fehlt es, daher ist die obige Regel Response Rules → XRAY_JSON erforderlich.';

  @override
  String get enumStatusDisconnected => 'Getrennt';

  @override
  String get enumStatusConnecting => 'Verbinden…';

  @override
  String get enumStatusConnected => 'Verbunden';

  @override
  String get enumStatusDisconnecting => 'Trennen…';

  @override
  String get enumStatusError => 'Fehler';

  @override
  String get enumVariantPlain => 'Standard';

  @override
  String get tagAutoSelect => 'AUTO';

  @override
  String get tagPanel => 'PANEL';

  @override
  String get tagPortHopping => 'PORT-HOPPING';

  @override
  String syncServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Server',
      one: '$count Server',
    );
    return '$_temp0';
  }

  @override
  String get syncNoChanges => 'keine Änderungen';

  @override
  String get errInvalidJson => 'Ungültiges JSON';

  @override
  String get errPickServerFirst => 'Wählen Sie zuerst einen Server';

  @override
  String get errImportSubscriptionFirst =>
      'Importieren Sie zuerst ein Abonnement';

  @override
  String get speedSizeFull => '20 MB';

  @override
  String get speedSizeLight => '5 MB';

  @override
  String speedMbPerSec(String value) {
    return '$value MB/s';
  }

  @override
  String speedKbPerSec(String value) {
    return '$value KB/s';
  }

  @override
  String portBusyTitle(int port, String by) {
    return 'Port $port wird bereits von $by belegt.';
  }

  @override
  String get srvTileMenu => 'Server-Aktionen';

  @override
  String get supportCopyReport => 'Bericht kopieren';

  @override
  String get supportReportCopied =>
      'Bericht kopiert — fügen Sie ihn im Support-Chat ein';

  @override
  String subBarUsedOnly(String used) {
    return 'Verbraucht $used';
  }

  @override
  String get subBarUnlimitedTraffic => 'unbegrenzter Traffic';

  @override
  String get supportDescribeLabel => 'Beschreiben Sie das Problem';

  @override
  String get supportDescribeHint =>
      'Was Sie taten, was Sie erwarteten, was passierte und wann es begann';

  @override
  String get supportDescribeRequired =>
      'Beschreiben Sie das Problem — ohne Beschreibung ist der Bericht nutzlos';

  @override
  String get supportNoScreenshots =>
      'Fügen Sie hier keine Screenshots ein — senden Sie sie separat im Telegram-Chat.';

  @override
  String get supportDescriptionSection => 'BESCHREIBUNG DES NUTZERS';

  @override
  String get splitAllowRealIp => 'Echte IP zulassen';

  @override
  String get splitAllowRealIpOn =>
      'Diese Regel umgeht das VPN — die Website sieht Ihre echte Adresse';

  @override
  String get splitAllowRealIpOff =>
      'Diese Regel ist geschützt — sie läuft über das VPN';

  @override
  String get splitRealIpExposed => 'echte IP';

  @override
  String get splitRealIpProtected => 'über VPN';

  @override
  String get vpnActiveBadge => 'VPN aktiv';

  @override
  String get splitCopyDomain => 'Adresse kopieren';

  @override
  String get splitCopyPath => 'Pfad kopieren';

  @override
  String get homeServerInfo => 'Server-Info';

  @override
  String get serverInfoVerifyInBrowser => 'Im Browser prüfen';

  @override
  String get tunDnsForAll => 'DNS aller Apps über VPN';

  @override
  String get infoDnsForAll =>
      'Nur im Modus „Nur ausgewählte“. ⚠️ Wird erst nach dem Neuverbinden übernommen.';

  @override
  String get homeSettingsNeedReconnect =>
      'Einstellung geändert – zum Übernehmen neu verbinden';

  @override
  String blockPageWindowTitle(String app) {
    return 'Blockiert — $app';
  }

  @override
  String get blockPageHeading => 'Website blockiert';

  @override
  String blockPageBody(String host, String app) {
    return '$host wird durch eine Split-Tunneling-Regel in $app blockiert.';
  }

  @override
  String get blockPageHint =>
      'Sie können die Regel ändern: Einstellungen → Split-Tunneling → Websites.';

  @override
  String get blockPageNote =>
      'Diese Seite stammt von der App selbst und ist kein Netzwerkfehler. Die Website öffnet sich nicht, weil Sie sie selbst zur Sperrliste hinzugefügt haben.';

  @override
  String get settingsBlockPage => 'Hinweisseite bei Blockierung';

  @override
  String get settingsBlockPageSub =>
      'Statt eines Verbindungsfehlers erklärt eine Seite, welche Regel die Website gesperrt hat. Funktioniert nur mit http: Eine https-Seite lässt sich nicht ersetzen, ohne ein eigenes Stammzertifikat im System zu installieren – und dieses Zertifikat würde das Mitlesen Ihres gesamten verschlüsselten Datenverkehrs ermöglichen.';

  @override
  String get trayCloseFully => 'Vollständig schließen';

  @override
  String errorVpnConflictApp(String app) {
    return '$app scheint zu stören: Dort läuft ein eigener VPN-Tunnel. Zwei gleichzeitige Tunnel streiten sich um die Standardroute.';
  }

  @override
  String errorCloseApp(String app) {
    return '$app schließen';
  }

  @override
  String toastAppClosed(String app) {
    return '$app geschlossen';
  }

  @override
  String toastAppCloseFailed(String app) {
    return '$app konnte nicht geschlossen werden – bitte manuell schließen';
  }

  @override
  String get tunBlockQuic => 'QUIC (HTTP/3) blockieren';

  @override
  String get infoBlockQuic =>
      'Website-Regeln greifen über den NAMEN, und den sieht die App nur bei gewöhnlichem TLS. Ein Browser, der auf HTTP/3 wechselt, zeigt keinen Namen – die Domain-Regel bleibt stillschweigend wirkungslos. Die Blockade holt den Browser zurück auf eine normale Verbindung, in der der Name sichtbar ist. Websites funktionieren weiterhin: HTTP/3 ist für sie optional, Videos laden eventuell etwas langsamer.';

  @override
  String get tunBlockEncryptedDns => 'Verschlüsseltes DNS (DoH/DoT) blockieren';

  @override
  String get infoBlockEncryptedDns =>
      'Browser und Windows können Adressen über HTTPS auflösen und unsere Erfassung umgehen. Dann wirken die Regeln „Direkt“ und „Blockieren“ auf DNS-Ebene gar nicht. ⚠️ Ist im Browser ein fester Anbieter für verschlüsseltes DNS eingetragen, fällt er nicht auf normales DNS zurück, sondern öffnet einfach keine Seiten mehr. Die Liste bekannter Anbieter ist naturgemäß unvollständig.';

  @override
  String get autoUseSpeed => 'Geschwindigkeit berücksichtigen';

  @override
  String get infoAutoUseSpeed =>
      'Nach der Auswahl über Dienste und Latenz werden die drei besten Kandidaten per Download geprüft, und der tatsächlich schnellere kommt zuerst. Die Geschwindigkeit wird mit IHRER Leitung verglichen: Ein Server, der fast alles davon liefert, wird nicht mehr nach Megabit bewertet – dann entscheidet die Latenz. ⚠️ Verbraucht Abo-Datenvolumen: 5 MB für Ihre Leitung plus 5 MB je Kandidat, rund 20 MB pro Durchlauf.';

  @override
  String get autoSpeedOwn => 'Messe Ihre eigene Geschwindigkeit…';

  @override
  String autoSpeedServer(String server, int index, int total) {
    return 'Messe Geschwindigkeit: $server ($index von $total)';
  }

  @override
  String autoSpeedShare(int percent) {
    return '$percent % Ihrer Leitung';
  }

  @override
  String get conflictDialogTitle => 'Anderes VPN erkannt';

  @override
  String conflictDialogBody(String app) {
    return 'Offenbar läuft $app mit einem eigenen Tunnel. Zwei gleichzeitige Tunnel streiten sich um die Standardroute – die Verbindung kann scheitern oder ohne Netzzugang zustande kommen.';
  }

  @override
  String get conflictCloseAndConnect => 'Schließen und verbinden';

  @override
  String get conflictConnectAnyway => 'Trotzdem verbinden';

  @override
  String get serviceChecksLegendBefore => 'Verfügbarkeit ohne VPN geprüft';

  @override
  String get serviceChecksLegendAfter => 'Links — ohne VPN, rechts — über VPN';

  @override
  String get serviceChecksBefore => 'Ohne VPN';

  @override
  String get serviceChecksAfter => 'Über VPN';

  @override
  String get serviceChecksNoBaseline => 'Ohne VPN nicht geprüft';

  @override
  String autoSpeedValue(String value) {
    return '$value Mbit/s';
  }

  @override
  String get splitShowBlockPage => 'Sperrseite anzeigen';

  @override
  String get splitBlockPageNeedsVpn =>
      'Die Sperrseite funktioniert nur bei aktivem VPN';

  @override
  String get srvInfoNeedsConnection =>
      'Auf dieser Plattform ist die Messung über den Server nur bei aktivem VPN möglich';

  @override
  String get serviceYoutubeThrottleNote =>
      '⚠️ Diese Prüfung erkennt keine YouTube-Drosselung: Der Anbieter antwortet normal, begrenzt aber die Videobandbreite. Grün bedeutet „Dienst erreichbar“, nicht „Video läuft“.';

  @override
  String get urlSchemeConnectServer =>
      'silentgate://connect?server=<Servername>';

  @override
  String get urlDescConnectServer =>
      'Mit einem BESTIMMTEN Server verbinden. Der Name ist der aus der Liste, den das Abo liefert, z. B. „Polen 1.5“. Flaggen-Emoji und Groß-/Kleinschreibung sind egal. Ohne exakte Übereinstimmung greift die Suche: Land, Adresse oder Protokoll. Gilt auch für toggle.';

  @override
  String get splitSelectAllFound => 'Alle gefundenen auswählen';

  @override
  String splitAddSelected(int count) {
    return 'Hinzufügen ($count)';
  }

  @override
  String get splitQuicNote =>
      'Solange mindestens eine Site-Regel existiert, deaktiviert die App HTTP/3 (QUIC) für den gesamten Verkehr. Sonst wechselt der Browser zu HTTP/3, hinterlässt keinen Site-Namen und die Regel greift stillschweigend nicht. Seiten funktionieren weiter: Sie fallen auf normales TLS zurück, nur etwas langsamer.';
}
