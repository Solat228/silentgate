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
  String get commonClear => 'Löschen';

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
  String get settingsSearchHint => 'In den Einstellungen suchen';

  @override
  String settingsSearchEmpty(String query) {
    return 'Nichts gefunden: „$query“';
  }

  @override
  String get settingsExpand => 'Ausklappen';

  @override
  String get settingsCollapse => 'Einklappen';

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
  String get captureProxyOnly => 'Nur Proxy';

  @override
  String get captureProxyOnlySub =>
      'Der Kern läuft, die lokalen Ports lauschen, aber der Computer ist nicht im Tunnel: über das VPN läuft nur, was ausdrücklich auf unseren Proxy zeigt';

  @override
  String get apiSectionTitle => 'API für Automatisierung';

  @override
  String get apiEnableTitle => 'Lokale API aktivieren';

  @override
  String apiEnableSub(int port) {
    return 'HTTP auf 127.0.0.1:$port — den Client per Skript steuern';
  }

  @override
  String get apiTokenTitle => 'Token';

  @override
  String get apiTokenUnset => 'Nicht festgelegt — die API startet nicht';

  @override
  String get apiTokenRegenerate => 'Token erneuern';

  @override
  String get apiTokenWarning =>
      'Das Token liegt im Klartext in der Einstellungsdatei. Es gelangt weder ins Protokoll noch in den Support-Bericht, aber wer es hat, kann den Server wechseln und den Zustand Ihres Abonnements lesen.';

  @override
  String get apiExitsTitle => 'Server mit eigenem Port';

  @override
  String get apiExitsSub =>
      'Jeder erhält einen eigenen lokalen Port — eine Anfrage dorthin läuft über diesen Server';

  @override
  String get apiCopyPythonExample => 'Python-Beispiel kopieren';

  @override
  String apiPortsHint(int control, int direct, int first) {
    return 'Steuerung — Port $control. „Direkt“ — Port $direct. Server — ab $first.';
  }

  @override
  String get apiRulesInProxyOnly => 'Split-Tunneling-Regeln anwenden';

  @override
  String get apiRulesInProxyOnlySub =>
      'In diesem Modus gelten die Standardregeln für kein Programm. Aktivieren Sie dies, wenn die Liste „Blockieren“ auch für Anfragen über die lokalen Ports gelten soll.';

  @override
  String apiCaptureModeWarning(int control) {
    return '⚠️ Als Erfassung ist „Systemproxy“ gewählt – Ausgangsports werden dabei nicht geöffnet, Verbindungen dorthin werden abgewiesen. Der Steuerport $control funktioniert bei jeder Erfassung. Wenn Sie Ausgangsports brauchen, wählen Sie „TUN (vollständiger Tunnel)“ oder „Nur Proxy“.';
  }

  @override
  String get apiPortBusyTitle => 'Die API wurde nicht gestartet';

  @override
  String apiPortBusy(int port, String holder) {
    return 'Port $port wird von $holder belegt. Schließen Sie das Programm vollständig, auch aus dem Infobereich, und schalten Sie den Schalter erneut ein.';
  }

  @override
  String apiPortBusyUnknown(int port) {
    return 'Port $port wird von einem anderen Programm belegt, das sich nicht ermitteln ließ. Meist ist es ein anderer VPN-Client. Schließen Sie ihn und schalten Sie den Schalter erneut ein.';
  }

  @override
  String get apiRulesInProxyOnlyEdit =>
      'Die Liste „Blockieren“ wird im Bildschirm für Split-Tunneling bearbeitet';

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
  String get subSwitcherPingAll => 'Server aller Abos testen';

  @override
  String get subSwitcherPingBusySpeed =>
      'Ping nicht verfügbar: Es läuft gerade eine Geschwindigkeitsmessung';

  @override
  String get subSwitcherExpired => 'Abgelaufen';

  @override
  String subSwitcherExpiredOn(String date) {
    return 'Abo am $date abgelaufen';
  }

  @override
  String subSwitcherCountTotal(int total) {
    return 'Server im Abo: $total. Der Kanal wurde noch nicht geprüft – starten Sie „Server aller Abos testen“.';
  }

  @override
  String subSwitcherCountWorking(int total, int working) {
    return 'Server im Abo: $total. Davon haben die Kanalprüfung (Anfrage über den Server) bestanden: $working.';
  }

  @override
  String subSwitcherCountChecking(int total) {
    return 'Server im Abonnement: $total. Die Prüfung läuft gerade — die Anzahl der funktionierenden Server erscheint, sobald sie abgeschlossen ist.';
  }

  @override
  String subSwitcherCountPartial(int total, int working) {
    return 'Server im Abonnement: $total. Der Durchlauf wurde nicht beendet (abgebrochen oder unterbrochen), daher ist die Zahl unvollständig: $working haben die Kanalprüfung bestanden — von denen, die erreicht wurden.';
  }

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
      'Wenn der Kern abgestürzt ist, der Server weggefallen ist oder sich das Netzwerk geändert hat (WLAN ↔ Kabel, Aufwachen aus dem Ruhezustand, neue IP), baut die App die Verbindung von selbst wieder auf. Die Pausen zwischen den Versuchen wachsen: 0,8 s → 3 s → 8 s → 20 s und bleiben danach bei 20 s. Es gibt acht Versuche, danach gibt die App auf und zeigt einen Fehler. Trennen per Schaltfläche bricht die Wiederherstellung immer ab.\n\n⚠️ Bei aktiviertem Kill Switch GEHEN DIE VERSUCHE NIE AUS. Solange sie laufen, bleibt der Verkehr blockiert, und sie zu stoppen hieße, ihn am VPN vorbei hinauszulassen — deshalb versucht es die App weiter alle 20 Sekunden, bis Sie das VPN selbst ausschalten, und erinnert höchstens alle 15 Minuten an den Fehlschlag. Ein Server, der eine Stunde später zurückkommt, wird von selbst wieder übernommen.\n\nIm Modus «Auto (bester Server)» verschwendet die App den letzten Versuch nicht an einen toten Server: schon beim siebten von acht wechselt sie zum nächsten Kandidaten, und dort beginnt die Zählung von vorn.\n\nEin Netzwerkwechsel wird an den echten Adressen der anderen Adapter erkannt: der eigene Tunnel und Dienstadressen (Link-Local) zählen nicht, eine Änderung wird nur akzeptiert, wenn sie zwei Abfragen in Folge hielt, und in den ersten 15 Sekunden nach dem Verbinden wird das Signal ignoriert. Ohne diese Sicherungen würde das Aufbauen des Tunnels selbst als «Netzwerkwechsel» zählen und endloses Neuverbinden auslösen.';

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
  String get splitProxyOnlyBanner =>
      'Im Modus „Nur Proxy“ gibt es nichts abzufangen: Die Regeln gelten für kein Programm dieses Rechners. Die Liste „Blockieren“ gilt nur für die lokalen API-Ports und nur, wenn im Abschnitt „Verkehrserfassung“ der Schalter „Split-Tunneling-Regeln anwenden“ eingeschaltet ist. Die übrigen Regeln lassen sich hier vorab anlegen: Sie greifen, sobald Sie auf TUN wechseln.';

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
  String get splitAllowRealIp => 'Echte IP für diese Regel erlauben';

  @override
  String get splitAllowRealIpOn =>
      'An: Das ist eine Ausnahme, der Verkehr geht mit Ihrer echten Adresse hinaus';

  @override
  String get splitAllowRealIpOff =>
      'Aus: Die Regel läuft über das VPN – der Schutz steht über allen Regeln';

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
    return '$value MB/s';
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

  @override
  String get splitNoRealIpBanner =>
      '„Nie mit echter IP“ ist aktiv: „Direkt“-Regeln ohne Häkchen laufen über das VPN';

  @override
  String get settingsNoRealIpAffects =>
      'Betrifft „Direkt“-Regeln: ohne Häkchen „echte IP erlauben“ laufen sie über das VPN';

  @override
  String get splitAppOverrideSites => 'Hat Vorrang vor Site-Regeln';

  @override
  String get splitAppOverrideSitesSub =>
      'Der gesamte App-Verkehr folgt dieser Regel, auch wenn eine Site-Regel anderes sagt';

  @override
  String get settingsMyRulesOverridePanel =>
      'Meine Regeln haben Vorrang vor Panel-Regeln';

  @override
  String get settingsMyRulesOverridePanelSub =>
      'Das Panel liefert eigenes Routing – meist „lokale Seiten am VPN vorbei“. Es greift nach Ihren Regeln, daher kann eine als „Tunnel“ markierte Seite doch direkt mit Ihrer echten IP hinausgehen. Aktiv: Tunnel heißt Tunnel. Preis: lokale Seiten nehmen den Umweg und werden langsamer.';

  @override
  String get commonOpen => 'Öffnen';

  @override
  String get tunRouteOnlySubnets => 'NUR diese Subnetze in den Tunnel';

  @override
  String get infoTunRouteOnlyCidrs =>
      'Der einzige Weg unter Windows, einen Teil des Verkehrs wirklich unabhängig vom VPN-Client zu machen.\n\nNormalerweise übernimmt der Tunnel die Standardroute, und der GESAMTE Verkehr des Rechners läuft hinein: Die Markierung „Direkt“ wird erst im Kern ausgewertet, der das Paket annimmt und unter eigenem Namen wieder nach draußen schickt. Solcher Verkehr lebt genau so lange wie der Kern und hängt mit ihm zusammen fest.\n\nIst die Liste nicht leer, bekommt der Tunnel die Standardroute nicht: Er übernimmt nur die aufgeführten Subnetze, alles Übrige schickt das System über den normalen Adapter — der Client sieht diesen Verkehr überhaupt nicht.\n\nDer Preis: Die Aufteilung erfolgt nach Adresse, App- und Website-Regeln greifen dagegen über den Namen. Eine Website, deren Adresse nicht in der Liste steht, sieht der Kern durch keine einzige Regel. Leer lassen, damit der Tunnel wie gewohnt arbeitet.';

  @override
  String get tunRouteOnlyWarning =>
      'Der Tunnel übernimmt nur die aufgeführten Subnetze. App- und Website-Regeln gelten NUR innerhalb dieser Subnetze: Was nicht in den Tunnel gelangt, bekommt der Kern nie zu sehen — eine solche Website lässt sich weder blockieren noch umleiten.';

  @override
  String get tunAlsoSystemProxy => 'Systemproxy zusätzlich zum Tunnel';

  @override
  String get infoTunAlsoSystemProxy =>
      'Gemischter Modus: Tunnel und Systemproxy laufen gleichzeitig.\n\nApps, die den Systemproxy respektieren (Browser, Telegram), nehmen den kurzen Weg direkt zum lokalen Port, umgehen den Userspace-Stack des Tunnels und übergeben dem Kern den Domainnamen statt einer nackten Adresse — Website-Regeln greifen für sie genauer und hängen nicht mehr von der TLS-Auswertung ab.\n\nUnabhängig vom Client werden sie dadurch NICHT: Sie laufen weiterhin über denselben Prozess.';

  @override
  String get tunMixedModeWarning =>
      'Eine Verbindung, die über den Systemproxy hereinkommt, hat keinen besitzenden Prozess — für den Kern ist sie eine lokale Verbindung. APP-Regeln greifen für solche Programme deshalb nicht. Website-Regeln funktionieren, sogar genauer als sonst.';

  @override
  String get tunWatchdog => 'Wächter für hängenden Kern';

  @override
  String get infoTunWatchdog =>
      'Wie viele Sekunden der Tunnel-Kern schweigen darf, bevor er als hängend gilt und der Tunnel abgebaut wird.\n\nStürzt der Kern ab, räumt Windows selbst auf — Adapter, Routen und Firewall-Regeln verschwinden, das Netzwerk kommt zurück. Hängt der Kern dagegen, wird nichts entfernt: Der Adapter bleibt bestehen und verschluckt den gesamten Verkehr des Rechners, auch den als „Direkt“ markierten. Von außen sieht das aus wie „das Internet ist komplett weg“, und von allein geht es nicht vorbei.\n\nDer Wächter wird erst nach der ersten erfolgreichen Antwort des Kerns scharf: Sonst würde er die Verbindung auch dort beenden, wo sich lediglich der Dienstport nicht öffnen ließ. 0 — nicht überwachen. Mindestens 10 Sekunden.';

  @override
  String get tunWatchdogOff => 'Aus: Ein hängender Tunnel wird nicht erkannt';

  @override
  String tunWatchdogSubtitle(int seconds) {
    return 'Tunnel abbauen, wenn der Kern länger als $seconds s schweigt';
  }

  @override
  String get tunDnsForAllWarning =>
      'Die Namensauflösung des GESAMTEN Rechners läuft über den Tunnel. Bleibt der Tunnel stehen, werden Namen auch für Apps nicht mehr aufgelöst, die direkt gehen und gar kein VPN brauchen — von außen wirkt das wie ein kompletter Internetausfall.';

  @override
  String get tunCidrInvalid =>
      'Adresse mit Präfix erforderlich, z. B. 10.8.0.0/24';

  @override
  String get geoTitle => 'Routing-Geodatenbanken';

  @override
  String get geoMissing =>
      'Nicht heruntergeladen — Regeln nach Land und Kategorie greifen nicht';

  @override
  String geoPresent(String size, String date) {
    return '$size, Stand $date';
  }

  @override
  String get geoDownload => 'Herunterladen';

  @override
  String get geoUpdate => 'Aktualisieren';

  @override
  String geoDownloading(String file) {
    return '$file wird heruntergeladen…';
  }

  @override
  String get geoDone => 'Geodatenbanken aktualisiert';

  @override
  String get geoWhy =>
      'Die Dateien geoip.dat und geosite.dat enthalten Adresslisten nach Ländern und Domainlisten nach Kategorien. Auf ihrer Grundlage wertet der Kern Regeln wie geoip:ru und geosite:category-ads aus, die das Panel Ihres Abonnements vorgibt. Ohne die Dateien werden solche Regeln aus der Konfiguration entfernt.';

  @override
  String geoFileOk(String size, String date) {
    return '$size, Stand $date';
  }

  @override
  String get geoFileMissing => 'Datei fehlt';

  @override
  String get geoFileCorrupt =>
      'Datei beschädigt — der Kern kann sie nicht lesen';

  @override
  String geoFolder(String path) {
    return 'Ordner: $path';
  }

  @override
  String get geoBundledWindows =>
      'Unter Windows werden die Dateien mit dem Kern ausgeliefert und liegen meist schon an Ort und Stelle. Die Aktualisierung hier lädt sie neu herunter, wenn die Listen veraltet sind.';

  @override
  String get geoSource =>
      'Die Quelle ist dieselbe, aus der die Dateien auch mit Xray ausgeliefert werden: Loyalsoldier/v2ray-rules-dat. Der Download wird mit der Prüfsumme aus demselben Release abgeglichen.';

  @override
  String get geoReplaceWarning =>
      'Die bisherigen Dateien bleiben erhalten: Wird das Routing nach dem Austausch schlechter, holt eine Schaltfläche sie zurück. Ein Update wird nicht eingespielt, wenn in der neuen Datei die Kategorien fehlen, auf die sich Ihr Abonnement bezieht.';

  @override
  String geoBackupLine(String files, String size, String date) {
    return 'Sicherungskopie vorhanden: $files — $size, Stand $date';
  }

  @override
  String get geoRestore => 'Vorherige wiederherstellen';

  @override
  String get geoRestored => 'Vorherige Geodatenbanken wiederhergestellt';

  @override
  String get geoRestoreTitle => 'Vorherige Geodatenbanken wiederherstellen?';

  @override
  String get geoRestoreBody =>
      'Die aktuellen Dateien werden durch die Kopie ersetzt, die vor dem letzten Update gesichert wurde. Dafür ist keine Internetverbindung nötig. Die aktualisierten Dateien lassen sich danach nur durch erneutes Herunterladen zurückholen.';

  @override
  String get geoErrorCategories =>
      'In der neuen Datei fehlen Kategorien, auf die sich Ihr Abonnement bezieht. Der Austausch wurde abgebrochen, die bisherigen Dateien liegen unverändert an Ort und Stelle — am Routing hat sich nichts geändert. Welche Kategorien genau gefehlt haben, steht in der Zeile darunter.';

  @override
  String get geoNoWrite =>
      'In diesen Ordner kann nicht geschrieben werden — das Herunterladen schlägt hier fehl. Das kommt meist bei einer Installation in Program Files vor: Starten Sie die App als Administrator.';

  @override
  String get geoCheck => 'Auf Update prüfen';

  @override
  String get geoCheckAgain => 'Erneut prüfen';

  @override
  String get geoChecking => 'Release wird abgefragt…';

  @override
  String geoLastCheck(String when) {
    return 'Zuletzt geprüft: $when';
  }

  @override
  String get geoNeverChecked => 'Noch nie auf ein Update geprüft';

  @override
  String geoUpdateAvailable(String files, String size) {
    return 'Update verfügbar: $files — $size';
  }

  @override
  String get geoSizeUnknown => 'vom Server nicht angegeben';

  @override
  String get geoUpToDate =>
      'Kein Update nötig: Die Dateien entsprechen dem neuesten Release.';

  @override
  String get geoPlanTitle => 'Geodatenbanken herunterladen?';

  @override
  String get geoPlanTitleUpdate => 'Geodatenbanken aktualisieren?';

  @override
  String geoPlanFiles(String files) {
    return 'Dateien: $files';
  }

  @override
  String geoPlanSize(String size) {
    return 'Größe: $size';
  }

  @override
  String get geoPlanTraffic =>
      'Die Dateien laufen über Ihre eigene Verbindung. In einem Mobilfunktarif ist das spürbarer Datenverkehr.';

  @override
  String geoProgressBytes(String done, String total) {
    return '$done von $total';
  }

  @override
  String get geoErrorNetwork =>
      'Der Update-Server war nicht erreichbar. Prüfen Sie Ihre Internetverbindung und versuchen Sie es erneut.';

  @override
  String get geoErrorServer =>
      'Der Update-Server hat die Anfrage abgelehnt. Das ist meist vorübergehend — versuchen Sie es später erneut.';

  @override
  String get geoErrorWrite =>
      'Die Datei konnte nicht geschrieben werden: keine Rechte für den Ordner oder zu wenig Speicherplatz.';

  @override
  String get geoErrorCorrupt =>
      'Die heruntergeladene Datei hat die Prüfung nicht bestanden — der Download ist beschädigt. Versuchen Sie es erneut.';

  @override
  String get geoErrorOther => 'Es hat nicht geklappt. Details unten.';

  @override
  String geoFailed(String error) {
    return 'Herunterladen fehlgeschlagen: $error';
  }

  @override
  String get infoGeoAssets =>
      'Die Dateien geoip.dat und geosite.dat enthalten Adresslisten nach Ländern und Domainlisten nach Kategorien (zum Beispiel „russische Websites“, „Behördenportale“, „VK“). Auf ihnen beruhen die Routing-Regeln, die das Panel Ihres Abonnements vorgibt.\n\nIn der App sind sie nicht enthalten: Zusammen sind sie rund 30 MB groß und werden nicht von jedem gebraucht — ein gewöhnlicher Server kommt ganz ohne sie aus.\n\nSolange die Dateien fehlen, werden solche Regeln aus der Konfiguration entfernt, und der Verkehr, den sie bisher direkt geleitet haben, läuft stattdessen über das VPN. Das ist sicher, aber langsamer, und lokale Websites verweigern den Zugriff möglicherweise, weil die Adresse im Ausland liegt. Ihre eigenen Regeln für einzelne Websites und Anwendungen gelten unabhängig davon — sie hängen nicht von diesen Dateien ab.';

  @override
  String get supportBullet2Android =>
      '• Nach dem Tippen wird der Bericht in einer einzigen Datei gesammelt und das Systemfenster „Teilen“ öffnet sich — wählen Sie Telegram, und er geht als ein einziger Anhang hinaus. Beschreiben Sie das Problem im Feld oben: ohne Beschreibung gibt es nichts zu analysieren.';

  @override
  String get supportDoneTextAndroid =>
      'Der Bericht wurde in einer einzigen Datei gesammelt. Wählen Sie im Systemfenster aus, wohin Sie ihn senden — in Telegram geht er als Anhang, nicht als Text.';

  @override
  String get exitsHeader => 'Ausgänge';

  @override
  String get exitsHint =>
      'Eine „Tunnel“-Regel kann an einen bestimmten Ausgang geleitet werden: eine Seite über Deutschland, eine andere über die USA. Ohne Ausgang nutzt die Regel den Haupttunnel wie bisher.';

  @override
  String get exitsAdd => 'Ausgang hinzufügen';

  @override
  String get exitsEmpty => 'Noch keine Ausgänge';

  @override
  String get exitsName => 'Name';

  @override
  String get exitsNameHint => 'Deutschland';

  @override
  String get exitsServers => 'Server';

  @override
  String get exitsAutoSelect => 'Automatische Auswahl nach Latenz';

  @override
  String get exitsAutoSelectSub =>
      'Der Kern hält den Verkehr selbst auf einem funktionierenden Server. Der Preis: Jeder Server wird alle drei Minuten geprüft, was auf dem Telefon den Funk weckt.';

  @override
  String get exitsAutoSelectNeedsTwo => 'Mindestens zwei Server erforderlich';

  @override
  String get exitsDelete => 'Ausgang löschen';

  @override
  String get exitsNoServers =>
      'Keine Server – importieren Sie zuerst ein Abonnement';

  @override
  String get exitsSearch => 'Server suchen';

  @override
  String get exitsPickAtLeastOne => 'Wählen Sie mindestens einen Server';

  @override
  String get exitsUnsupportedNote =>
      'Panel-Profile „Auto“ und hysteria2 können nicht als eigener Ausgang laufen: Sie werden vom anderen Kern bedient. Solche Server sind in der Liste deaktiviert.';

  @override
  String get infoExits =>
      'Ein Ausgang ist das Ziel einer „Tunnel“-Regel.\n\nStandardmäßig besteht ein Ausgang aus EINEM Server und kostet im Hintergrund nichts: Gewöhnliche Protokolle halten keine dauerhafte Verbindung. Eine Gruppe mehrerer Server mit Auto-Auswahl wird nur gebraucht, wenn Absicherung gegen Knotenausfall zählt — sie fügt regelmäßige Messungen hinzu, auf dem Telefon sind das Funk-Weckvorgänge.\n\nEin Ausgang ergibt NUR bei der Aktion „Tunnel“ Sinn. „Direkt über Deutschland“ ist ein Widerspruch: Eine direkte Regel umgeht alle Ausgänge.\n\nEine Seite und ihre Subdomain dürfen in VERSCHIEDENE Ausgänge gehen — die App stellt die konkretere Regel nach oben, sonst würde der Elternteil die Subdomain verschlucken.\n\nWICHTIG: Mit dem Systemproxy unter Windows funktionieren Ausgänge gar nicht — in diesem Modus werden keine Routing-Regeln gebaut. Der Tunnelmodus ist nötig.';

  @override
  String get ruleServer => 'Über Server';

  @override
  String get ruleServerCurrent => 'Wie der Hauptserver';

  @override
  String ruleServerCurrentNamed(String server) {
    return 'Wie der Hauptserver ($server)';
  }

  @override
  String get routeMatchByName => 'Abgleich über den Dateinamen';

  @override
  String get routeYourApps => 'Ihre Apps';

  @override
  String get routeYourSites => 'Ihre Websites';

  @override
  String get routeAppsAndSites => 'Apps und Websites';

  @override
  String get notifCompactTitle => 'Kompakte Benachrichtigung';

  @override
  String get notifCompactSub =>
      'Aus: Abonnement, Server und Geschwindigkeit, mit Schaltflächen. Ein: in der Kopfzeile App und Abonnement, darunter der Server — ohne Geschwindigkeit und ohne Schaltflächen.';

  @override
  String get localProxyAuthTitle => 'Passwort für den lokalen Proxy';

  @override
  String get localProxyAuthInfo =>
      'Der lokale Port des Kerns (127.0.0.1) ist ein vollwertiger Proxy in Ihr VPN. Ohne Passwort verbindet sich jedes Programm auf demselben Gerät damit und bekommt Ihren Tunnel komplett: die Ausgangs-IP, das Kontingent Ihres Abonnements und die Umgehung Ihrer eigenen Split-Tunneling-Regeln — auch für Apps, die Sie auf „Blockieren“ gesetzt haben. Unter Android ist das besonders wichtig: Dort sieht jede installierte App die lokalen Ports.\n\nSchalten Sie es nur aus, wenn Sie diesen Proxy bewusst mit etwas nutzen, das keine Authentifizierung beherrscht.';

  @override
  String get localProxyAuthOff =>
      'Aus: Der lokale Proxy steht jedem Programm auf dem Gerät offen';

  @override
  String get localProxyAuthSystemProxy =>
      'Im Modus „Systemproxy“ wirkungslos: Windows kann dem lokalen Proxy kein Passwort übergeben. Gilt im TUN-Modus.';

  @override
  String get localProxyAuthRandom =>
      'Bei jeder Verbindung ein neues Zufallspasswort – wird nicht in den Einstellungen gespeichert';

  @override
  String get localProxyAuthCustom =>
      'Eigener Benutzername und eigenes Passwort (in der Einstellungsdatei gespeichert)';

  @override
  String get localProxyCredsTitle => 'Eigener Benutzername und Passwort';

  @override
  String get localProxyCredsUnset =>
      'Nicht festgelegt — es wird ein Zufallspasswort verwendet';

  @override
  String localProxyCredsUser(String user) {
    return 'Benutzername: $user';
  }

  @override
  String get localProxyDialogTitle =>
      'Benutzername und Passwort des lokalen Proxys';

  @override
  String get localProxyDialogBody =>
      'Nur nötig, wenn Sie unseren Proxy (127.0.0.1) selbst in einem anderen Programm eintragen. Lassen Sie die Felder leer, dann ist das Passwort bei jeder Verbindung zufällig: Es wird nicht in den Einstellungen gespeichert und gelangt weder ins Protokoll noch in den Support-Bericht. Ein selbst gesetztes Passwort bleibt im Klartext in der Einstellungsdatei.';

  @override
  String get localProxyFieldUser => 'Benutzername';

  @override
  String get localProxyFieldPassword => 'Passwort';

  @override
  String get localProxyFieldHint => 'leer — zufällig';

  @override
  String get lockdownOnTitle => 'Systemweiter Schutz ist aktiv';

  @override
  String get lockdownOnSub =>
      'Der Verkehr ist blockiert, selbst wenn die App geschlossen oder vom System beendet wird. Das ist der zuverlässigste Modus.';

  @override
  String get lockdownHalfTitle => 'Schutz nur zur Hälfte aktiv';

  @override
  String get lockdownHalfSub =>
      '„Immer aktives VPN“ ist eingerichtet, aber „Verbindungen ohne VPN blockieren“ ist aus. Solange die App läuft, ist der Verkehr geschützt; beendet das System sie, geht er ungeschützt hinaus.';

  @override
  String get lockdownOffTitle => 'Systemweiter Schutz ist aus';

  @override
  String get lockdownOffSub =>
      'Unser Kill-Switch hält den Verkehr, solange die App läuft. Beendet das System sie, geht der Verkehr am VPN vorbei. Aktivieren Sie „Immer aktives VPN“ und „Verbindungen ohne VPN blockieren“.';

  @override
  String get lockdownUnknownTitle => 'Systemweiter Schutz: Zustand unbekannt';

  @override
  String get lockdownUnknownSub =>
      'Der Zustand lässt sich erst ab Android 10 und nur bei aktivem Tunnel abfragen. Prüfen Sie es von Hand: „Immer aktives VPN“ und „Verbindungen ohne VPN blockieren“.';

  @override
  String get lockdownOpenFailed =>
      'Die VPN-Systemeinstellungen ließen sich nicht öffnen. Suchen Sie sie von Hand: Einstellungen → Netzwerk und Internet → VPN.';

  @override
  String get blockNoticeTitle => 'Über blockierte Websites informieren';

  @override
  String get blockNoticeSub =>
      'Wenn eine App oder der Browser eine Website aus der Sperrliste anfragt, erscheint unten eine Benachrichtigung mit ihrem Namen. Ein Tippen öffnet diesen Bildschirm.';

  @override
  String get siteInsecureScheme =>
      'Die Adresse ist als http:// angegeben — die Verbindung ist unverschlüsselt und der Anbieter sieht sie vollständig. Entfernen Sie „http://“, damit der Browser https verwendet.';

  @override
  String get exitServerGone =>
      'Der Server dieser Regel ist aus dem Abonnement verschwunden — der Verkehr läuft über den Haupttunnel';

  @override
  String exitServerUnsupported(String name) {
    return '$name\n\nDieser Server kann nicht als eigener Ausgang laufen: Panel-Profile „Auto“ und einen Teil der Protokolle beherrscht nur Xray, die Ausgänge verteilt aber sing-box. Der Verkehr dieser Regel läuft über den Haupttunnel.';
  }

  @override
  String get noticeRulesAction => 'Regeln';

  @override
  String get geoVerdictMissingTitle => 'Geodatenbanken nicht heruntergeladen';

  @override
  String get geoVerdictMissingSub =>
      'Die Abonnement-Regeln nach Land und Kategorie sind derzeit deaktiviert — dieser Verkehr läuft über das VPN statt direkt.';

  @override
  String get geoVerdictUnusableTitle =>
      'Der Kern konnte die Geodatenbanken nicht öffnen';

  @override
  String get geoVerdictUnusableSub =>
      'Die Dateien sind vorhanden, aber der Kern hat sie nicht gelesen. Ein erneutes Herunterladen hilft.';

  @override
  String get geoOfferMissingSub =>
      'Ohne sie funktionieren die Abonnement-Regeln nach Land und Kategorie nicht — dieser Verkehr läuft dann über das VPN statt direkt.';

  @override
  String get geoOfferDismiss => 'Nicht mehr anbieten';

  @override
  String get pingPendingTooltip =>
      'TCP-Latenz zum Server. Die Kanalprüfung läuft noch – ob der Server wirklich funktioniert, ist noch nicht bekannt.';

  @override
  String get pingUnverifiedTooltip =>
      'TCP-Latenz zum Server. Es wurde keine Prüfung durch den Tunnel durchgeführt – bekannt ist nur die Erreichbarkeit.';

  @override
  String pingMeasuredAt(String time) {
    return 'Gemessen: $time';
  }

  @override
  String get pingChecking => 'wird geprüft';

  @override
  String autoTimer(String elapsed, String remaining) {
    return 'Vergangen $elapsed · noch etwa $remaining';
  }

  @override
  String autoTimerNoEstimate(String elapsed) {
    return 'Vergangen $elapsed';
  }

  @override
  String autoSpeedRanking(String name) {
    return 'Geschwindigkeit wird gemessen: $name';
  }

  @override
  String get autoWarnNoRealIp =>
      '„Echte IP nie verwenden“ ist aktiv – der gesamte Verkehr läuft über das VPN.';

  @override
  String get autoWarnAllVpn =>
      'Der Modus „Alles über VPN“ ist gewählt – Ihre Regeln greifen im Moment nicht.';

  @override
  String get autoWarnPanelOverride =>
      '„Meine Regeln haben Vorrang vor den Panel-Regeln“ ist aktiv.';

  @override
  String get autoWarnProbesDirect =>
      'Auf die Prüfung selbst hat das keinen Einfluss: Die Tests laufen bei jeder Einstellung am VPN vorbei. Im TUN-Modus laufen sie jedoch über den Kernprozess – hängt der Kern, sind alle Ergebnisse falsch negativ.';

  @override
  String get autoWarnTurnOff => 'Ausschalten';

  @override
  String get toastCollapse => 'Einklappen';

  @override
  String get toastExpand => 'Ausklappen';

  @override
  String get toastOpenAutoConfig => 'Automatische Einrichtung öffnen';

  @override
  String get splitAppAlreadyAdded =>
      'Diese App steht bereits in der Regelliste';

  @override
  String logsFileLine(String name, String size, int lines) {
    return '$name – $size, $lines Zeilen';
  }

  @override
  String logsReportsLine(int count, String size) {
    return 'Support-Berichte: $count, $size';
  }

  @override
  String get logsRetentionTitle => 'Protokolle und Berichte aufbewahren';

  @override
  String get logsRetentionDay => '1 Tag';

  @override
  String get logsRetentionTwoWeeks => '2 Wochen';

  @override
  String get logsRetentionMonth => '1 Monat';

  @override
  String get logsRetentionNever => 'Nie löschen';

  @override
  String get logsRetentionInfo =>
      'Protokolle und Support-Berichte werden gelöscht, sobald sie älter als der gewählte Zeitraum sind. Geprüft wird beim Start der App. „Nie“ behält alles auf der Festplatte – dann behalten Sie die Größe selbst im Auge: Ein Bericht enthält die Protokolle vollständig und wächst mit ihnen.';

  @override
  String get logsCleanNow => 'Alte jetzt löschen';

  @override
  String logsCleaned(int count, String size) {
    return 'Gelöschte Dateien: $count, $size freigegeben';
  }

  @override
  String get logsNothingToClean => 'Es gibt nichts zu löschen';

  @override
  String get speedTooltip => 'Downloadgeschwindigkeit über diesen Server';

  @override
  String get speedFromAutoConfig =>
      'Geschwindigkeit von der automatischen Einrichtung gemessen';

  @override
  String get speedBlockedTooltip =>
      'Geschwindigkeit wird nicht gemessen: Der Server hat die Kanalprüfung nicht bestanden (die Anfrage kam nicht durch)';

  @override
  String get srvTileMeasureSpeed => 'Geschwindigkeit messen';

  @override
  String get speedRunTooltip => 'Geschwindigkeit der Server messen';

  @override
  String get speedConfirmTitle => 'Geschwindigkeit messen?';

  @override
  String speedConfirmBody(int count, String size, String total) {
    return 'Es werden $count Server geprüft. Jeder lädt eine Probe von $size – etwa $total vom Datenvolumen Ihres Abos.';
  }

  @override
  String speedConfirmSkipped(int count) {
    return 'Bereits gemessene werden übersprungen: $count.';
  }

  @override
  String get speedConfirmRun => 'Messen';

  @override
  String get speedNoTargets =>
      'Nichts zu messen: Die Geschwindigkeit wird nur bei Servern geprüft, die die Kanalprüfung bestanden haben. Testen Sie zuerst die Liste.';

  @override
  String get speedNotVerified =>
      'Der Server hat die Kanalprüfung nicht bestanden – wir messen die Geschwindigkeit darüber nicht';

  @override
  String speedProgress(int done, int total) {
    return 'Geschwindigkeit: $done von $total';
  }

  @override
  String get updateOnStartTitle => 'Abo beim Start aktualisieren';

  @override
  String get updateOnStartSub =>
      'Jedes Mal eine frische Serverliste holen, nicht nur per Timer';

  @override
  String get apiSectionSub =>
      'HTTP auf 127.0.0.1 – den Client aus Skripten steuern';

  @override
  String get momentJustNow => 'gerade eben';

  @override
  String momentMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Minuten',
      one: 'vor $count Minute',
    );
    return '$_temp0';
  }

  @override
  String momentHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Stunden',
      one: 'vor $count Stunde',
    );
    return '$_temp0';
  }

  @override
  String get serviceChecksMenuTitle => 'Beim Verbinden prüfen';

  @override
  String get serviceChecksMenuOff => 'Beim Verbinden nicht prüfen';

  @override
  String get serviceChecksMenuTooltip => 'Welche Dienste prüfen';

  @override
  String get serviceChecksLegendOff => 'Dienstprüfung ist aus';

  @override
  String get srvInfoAutoNever =>
      'Die automatische Einrichtung hat diesen Server noch nicht geprüft – starten Sie sie, um zu sehen, welche Dienste darüber funktionieren.';

  @override
  String get srvInfoAutoHint =>
      'Daten des letzten Durchlaufs der automatischen Einrichtung. Hier wird nichts erneut gemessen.';

  @override
  String srvInfoAutoGeoNote(Object services) {
    return '$services: über diesen Server erreichbar, im Ausgangsland aber nicht verfügbar. Der Server selbst ist in Ordnung – nur diese Dienste funktionieren nicht; dafür brauchen Sie einen Ausgang in einem anderen Land.';
  }

  @override
  String get settingsSectionChecks => 'Dienstprüfung';

  @override
  String get settingsSectionAutotune => 'Automatische Einrichtung';

  @override
  String get settingsSpeedRankTitle =>
      'Geschwindigkeit bei der Auto-Auswahl berücksichtigen';

  @override
  String get settingsSpeedRankSub =>
      'Kandidaten, welche die Dienstprüfung bestanden haben, werden zusätzlich per Download gemessen — ganz vorn landet der wirklich schnellere. Verbraucht Traffic deines Abos.';

  @override
  String get settingsSpeedTopNLabel => 'Server in der Geschwindigkeitsmessung';

  @override
  String get settingsSpeedTopNSub =>
      'Plus eine Messung der eigenen Leitung — ohne sie fehlt der Vergleich: 60 Mbit/s sind auf einer 60er-Leitung ausgezeichnet und auf einer 300er schlecht.';

  @override
  String settingsSpeedTrafficNote(Object mb) {
    return '≈$mb MB Abo-Traffic pro Durchlauf';
  }

  @override
  String get settingsSpeedWarnTitle =>
      'Die Geschwindigkeitsmessung verbraucht Abo-Traffic';

  @override
  String settingsSpeedWarnBody(Object mb) {
    return 'Jeder Durchlauf der automatischen Einrichtung lädt rund $mb MB über dein Abo: eine Messung je geprüftem Server plus eine Messung der eigenen Leitung. Diese Megabyte gehen von deinem Kontingent ab.';
  }

  @override
  String get settingsSpeedWarnEnable => 'Trotzdem aktivieren';

  @override
  String get settingsConcurrencyTitle => 'Gleichzeitige Prüfungen';

  @override
  String get settingsConcurrencySub =>
      '1 ist das bisherige Verhalten: Kandidaten werden streng nacheinander geprüft — hierher zurück, wenn die Ergebnisse seltsam werden. Mehr ist schneller, aber jeder Kandidat startet seinen eigenen Kern: Die Maschine wird stärker belastet und die Latenzmessungen beeinflussen sich gegenseitig.';

  @override
  String get settingsConnectChecksTitle => 'Dienste beim Verbinden prüfen';

  @override
  String get settingsConnectChecksSubOn =>
      'Ein Durchlauf, sobald der Tunnel steht: Die Chips unter der Schaltfläche zeigen sofort, was sich öffnet und was nicht.';

  @override
  String get settingsConnectChecksSubOff =>
      'Die Chips bleiben grau, bis du sie selbst antippst.';

  @override
  String get settingsConnectCheckServices => 'Was beim Verbinden geprüft wird';

  @override
  String get settingsConnectCheckServicesSub =>
      'Bewusst ein anderer Satz als bei der automatischen Einrichtung: Diese sucht einen funktionierenden Server und darf dafür lange brauchen, während diese Chips die Frage „geht es gerade jetzt?“ beantworten.';

  @override
  String get settingsConnectChecksEmpty =>
      'Kein Dienst ausgewählt — es gibt nichts zu prüfen.';

  @override
  String get settingsSectionSeamless => 'Nahtlosigkeit';

  @override
  String get settingsSeamlessNote =>
      'Keine dieser Optionen hält offene Verbindungen am Leben: Ein anderer Server bedeutet eine andere externe IP, und die Gegenseite sieht eine andere Adresse — ein Anruf oder ein Download reißt so oder so ab. Es geht nur darum, dass das Netzwerk der Maschine nicht flackert.';

  @override
  String get settingsSeamlessServerTitle =>
      'Den Tunnel bei einem Serverwechsel nicht neu aufbauen';

  @override
  String get settingsSeamlessServerSub =>
      'Nur der Proxy-Kern startet neu: Adapter und Routen bleiben bestehen, das Netzwerk der Maschine flackert nicht. Der Preis: Die Adressen aller Server des Abos werden vorab am Tunnel vorbei eingetragen.';

  @override
  String get settingsSeamlessNetworkTitle =>
      'Die Verbindung bei Netzwechsel nicht abreißen';

  @override
  String get settingsSeamlessNetworkSub =>
      'WLAN → Mobilfunk: Zuerst prüfen wir, ob der Verkehr noch lebt, und starten den Kern nur neu, wenn er tot ist. QUIC (hysteria2) übersteht einen Adresswechsel von selbst. Der Preis: Ist die Verbindung doch tot, beginnt die Wiederherstellung einige Sekunden später.';

  @override
  String get settingsSeamlessKeepTunTitle =>
      'Den Adapter zwischen den Versuchen oben halten';

  @override
  String get settingsSeamlessKeepTunSub =>
      'Die Standardroute wird während der Wiederherstellung nicht hin- und hergerissen. ⚠️ Das ist KEIN Kill Switch: Verkehr außerhalb des VPN wird nicht blockiert — gehalten wird nur der Adapter selbst.';

  @override
  String get autoSpeedTrafficTitle =>
      'Der Geschwindigkeitstest verbraucht Datenvolumen';

  @override
  String autoSpeedTrafficBody(int servers, int mb) {
    return 'Gemessen werden die $servers besten Server und Ihre eigene Verbindung — etwa $mb MB Ihres Abo-Datenvolumens.\n\nSie können den Test in den Einstellungen abschalten.';
  }

  @override
  String get autoSpeedTrafficGo => 'Starten';

  @override
  String get splitDeadPath =>
      'Die Datei unter diesem Pfad existiert nicht mehr — die Regel greift nie';

  @override
  String get splitDeadPathFix => 'Tippen, um nach Dateinamen abzugleichen';

  @override
  String get srvTileCopyKey => 'Schlüssel kopieren';

  @override
  String serviceChecksBypassDirect(Object rule) {
    return 'Am VPN vorbei: Die Split-Tunneling-Regel „$rule“ leitet diese Domain direkt — der Dienst nutzt Ihre echte Adresse.';
  }

  @override
  String serviceChecksBypassBlock(Object rule) {
    return 'Blockiert: Die Split-Tunneling-Regel „$rule“ verbietet diese Domain — der Dienst öffnet sich weder mit noch ohne VPN.';
  }

  @override
  String get subBarOpenSite => 'Website';

  @override
  String get subBarOpenSiteHint => 'Abonnementseite im Browser öffnen';

  @override
  String subSwitcherRefreshingOne(Object name) {
    return '„$name“ wird aktualisiert…';
  }

  @override
  String subSwitcherRefreshedOne(Object name) {
    return '„$name“ aktualisiert';
  }

  @override
  String subSwitcherRefreshFailedOne(Object name) {
    return '„$name“ konnte nicht aktualisiert werden';
  }

  @override
  String subBarDeleteConfirmNamed(Object name) {
    return 'Abonnement „$name“ löschen?';
  }

  @override
  String get exitServerUnsupportedInfo =>
      'Dieser Server kann nicht als eigener Ausgang laufen: Panel-Profile „Auto“ und einen Teil der Protokolle beherrscht nur Xray, die Ausgänge verteilt aber sing-box. Der Verkehr dieser Regel läuft über den Haupttunnel.';

  @override
  String get pingBusyServiceChecks =>
      'Ping nicht verfügbar: Dienstprüfung läuft';

  @override
  String get serviceChecksChannelNotReady =>
      'Der Tunnel ist noch nicht bereit – die Prüfungen wurden nicht ausgeführt';

  @override
  String get serviceChecksRetryCheck => 'Prüfung wiederholen';

  @override
  String get serviceGroupMessengers => 'Messenger';

  @override
  String get serviceGroupAi => 'KI';

  @override
  String get serviceGroupMedia => 'Video und Musik';

  @override
  String get serviceGroupSocial => 'Soziale Netzwerke';

  @override
  String get serviceGroupOther => 'Sonstiges';

  @override
  String get apiTokenHidden => 'verborgen – auf „anzeigen“ klicken';

  @override
  String get apiTokenShow => 'Token anzeigen';

  @override
  String get apiTokenHide => 'Token verbergen';

  @override
  String get apiCheatSheetTitle => 'Spickzettel: Adresse, Ports, Endpunkte';

  @override
  String get apiCheatSheetBase => 'Basisadresse';

  @override
  String get apiCheatSheetExitPorts => 'Ausgangs-Ports';

  @override
  String apiCheatSheetPortDirect(Object port) {
    return '$port – „Direkt“: am VPN vorbei, echte IP';
  }

  @override
  String apiCheatSheetPortServer(int port, String name) {
    return '$port – $name';
  }

  @override
  String get apiCheatSheetNoExitServers =>
      'kein Server ausgewählt – es gibt keine Server-Ports';

  @override
  String apiCheatSheetPortsSystemProxy(Object control) {
    return 'werden nicht geöffnet: Erfassung „Systemproxy“. Nur der Steuerport $control funktioniert';
  }

  @override
  String get apiCheatSheetTokenOff =>
      'Token ist leer – der Kanal startet nicht, kein Port lauscht';

  @override
  String get apiCheatSheetPortsWhenConnected =>
      'Ausgangs-Ports lauschen nur bei bestehender Verbindung.';

  @override
  String get apiCheatSheetEndpoints => 'Endpunkte';

  @override
  String get apiEpStatus =>
      'Engine-Status, gewählter Server, Erfassungsmodus, läuft ein Ping';

  @override
  String get apiEpServers => 'Serverliste mit den letzten Ping-Ergebnissen';

  @override
  String get apiEpExits => 'Belegung der Ausgangs-Ports samt Eintrag „Direkt“';

  @override
  String get apiEpTraffic => 'Traffic-Zähler seit dem Start der Anwendung';

  @override
  String get apiEpSubscription =>
      'Name, Ablaufdatum und Restvolumen des Abonnements';

  @override
  String get apiEpConnect =>
      'Verbinden per Serverschlüssel, Name oder „Auto“; bei aktiver Verbindung wird der Server gewechselt';

  @override
  String get apiEpDisconnect => 'Trennen; ein erneuter Aufruf ist unbedenklich';

  @override
  String get apiEpPing =>
      'Ping-Lauf über alle Server starten; Ergebnisse aus /v1/servers lesen';

  @override
  String get apiCopyCurlExample => 'curl-Beispiel kopieren';

  @override
  String get noRealIpSubRulesOnly =>
      'Schreibt nur Ihre „Direkt“-Regeln um: Sie laufen durch den Tunnel (auch RU-Seiten). Die Standardroute bleibt unverändert, das lokale Netz bleibt direkt.';

  @override
  String get noRealIpOnlySelectedNote =>
      'Im Modus „Nur ausgewählte“ geht alles Nicht-Ausgewählte weiterhin mit Ihrer echten IP hinaus – diese Einstellung ändert daran nichts.';

  @override
  String get infoNoRealIp =>
      'Gilt NUR für ausdrückliche „Direkt“-Regeln (Programme und Websites) und für direkte Regeln aus der Panel-Konfiguration: Sie werden in den Tunnel geholt. Eine Regel mit gesetztem Haken „Echte IP erlauben“ bleibt direkt.\n\nWas sie NICHT tut: Sie ändert die Standardroute nicht. Im Modus „Nur ausgewählte“ bleibt die Standardroute direkt, deshalb verlässt der gesamte nicht ausgewählte Verkehr das Gerät mit Ihrer echten Adresse – unabhängig von dieser Einstellung. Wenn alles abgedeckt sein muss, nutzen Sie „Alles über VPN“.\n\nDas lokale Netz bleibt immer direkt.';

  @override
  String get killSwitchSubProxyNoAdmin =>
      'Das ist keine echte Sperre: Im Modus „Systemproxy“ werden keine Administratorrechte genommen, gehalten wird nur dadurch, dass der Proxy eingetragen bleibt. Programme, die ihn ignorieren, und sämtliches UDP gehen direkt hinaus. Vollständig hält nur TUN.';

  @override
  String get killSwitchOfferTun =>
      'Eine vollständige Sperre während eines Ausfalls gibt es nur im TUN-Modus.';

  @override
  String get splitOnlySelectedWarnTitle =>
      'Alles Nicht-Ausgewählte geht mit Ihrer echten IP hinaus';

  @override
  String get splitOnlySelectedWarnBody =>
      'In den Tunnel geht nur, was die Aktion „Tunnel“ hat. Der übrige Verkehr – auch von Programmen, von denen Sie nichts wissen – geht direkt hinaus, mit Ihrer echten Adresse. Soll das ganze Gerät verborgen sein, wählen Sie „Alles über VPN“.';

  @override
  String get splitOnlySelectedNoRealIp =>
      'Die Einstellung „Nicht mit der echten IP hinausgehen“ ändert daran nichts: Sie schreibt nur die „Direkt“-Regeln um, nicht die Standardroute.';

  @override
  String get splitKillSwitchIsPerApp =>
      'Der Kill Switch hält den Verkehr programmweise, nicht domainweise: Während der Kern wiederhergestellt wird, gibt es niemanden, der Website-Namen auswertet – Website-Regeln gelten in dieser Zeit nicht.';
}
