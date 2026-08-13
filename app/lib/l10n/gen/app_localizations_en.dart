// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonCheck => 'Check';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDone => 'Done';

  @override
  String get commonPathCopied => 'Path copied';

  @override
  String get languageTitle => 'Interface language';

  @override
  String get languageSubtitle => 'Choose the app language';

  @override
  String get languageSystem => 'System default';

  @override
  String get sectionAppearance => 'Appearance and behavior';

  @override
  String get sectionCapture => 'Traffic capture';

  @override
  String get sectionReliability => 'Connection reliability';

  @override
  String get sectionPing => 'Ping';

  @override
  String get sectionIdentity => 'Panel identity';

  @override
  String get sectionNetwork => 'Network';

  @override
  String get sectionAbout => 'About';

  @override
  String get sectionSupport => 'Support';

  @override
  String get settingsSearchHint => 'Search settings';

  @override
  String settingsSearchEmpty(String query) {
    return 'Nothing found for “$query”';
  }

  @override
  String get settingsExpand => 'Expand';

  @override
  String get settingsCollapse => 'Collapse';

  @override
  String get appearanceTheme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get closeToTrayTitle => 'Minimize to tray on close';

  @override
  String get closeToTraySubtitle =>
      'The close button hides the window to the tray; turn off to close the app instead';

  @override
  String get autoUpdateSubTitle => 'Auto-update subscription';

  @override
  String get autoUpdateSubText => 'Periodically refresh the server list';

  @override
  String get captureSystemProxy => 'System proxy';

  @override
  String get captureSystemProxySub => 'Works now. No administrator rights.';

  @override
  String get captureTun => 'TUN (full tunnel)';

  @override
  String get captureTunBadgeUac => 'needs UAC';

  @override
  String get captureTunSub =>
      'All traffic, including UDP and apps that ignore the proxy. Requires administrator rights.';

  @override
  String get tunProvider => 'TUN provider';

  @override
  String get tunRoutingTitle => 'TUN and routing';

  @override
  String tunRoutingSub(String stack, int mtu, String dns) {
    return 'Stack $stack · MTU $mtu · DNS $dns';
  }

  @override
  String get splitTunnelTitle => 'Split tunneling';

  @override
  String splitRulesCount(int n, int apps, int sites) {
    return '$n rules ($apps apps, $sites sites)';
  }

  @override
  String get captureTunHint =>
      'TUN, DNS and split-tunneling settings appear when TUN mode is selected — in system-proxy mode they have no effect.';

  @override
  String get captureProxyOnly => 'Proxy only';

  @override
  String get captureProxyOnlySub =>
      'The core is running and the local ports are listening, but the computer isn\'t in the tunnel: only whatever explicitly points at our proxy goes through the VPN';

  @override
  String get apiSectionTitle => 'API for automation';

  @override
  String get apiEnableTitle => 'Enable local API';

  @override
  String apiEnableSub(int port) {
    return 'HTTP on 127.0.0.1:$port — control the client from scripts';
  }

  @override
  String get apiTokenTitle => 'Token';

  @override
  String get apiTokenUnset => 'Not set — the API won\'t start';

  @override
  String get apiTokenRegenerate => 'Regenerate token';

  @override
  String get apiTokenWarning =>
      'The token sits in the settings file in plain text. It never reaches the log or the support report, but anyone who has it can switch servers and read your subscription state.';

  @override
  String get apiExitsTitle => 'Servers with a dedicated port';

  @override
  String get apiExitsSub =>
      'Each one gets its own local port — a request to it goes through that server';

  @override
  String get apiCopyPythonExample => 'Copy Python example';

  @override
  String apiPortsHint(int control, int direct, int first) {
    return 'Control — port $control. \"Direct\" — port $direct. Servers — from $first.';
  }

  @override
  String get apiRulesInProxyOnly => 'Apply split-tunneling rules';

  @override
  String get apiRulesInProxyOnlySub =>
      'In this mode the default rules don\'t apply to any program. Turn this on if you want the \"Block\" list to also cover requests made through the local ports.';

  @override
  String apiCaptureModeWarning(int control) {
    return '⚠️ Capture is set to \"System proxy\" — exit ports are not opened in this mode and connections to them are refused. The control port $control works with any capture mode. If you need exit ports, choose \"TUN (full tunnel)\" or \"Proxy only\".';
  }

  @override
  String get apiPortBusyTitle => 'The API did not start';

  @override
  String apiPortBusy(int port, String holder) {
    return 'Port $port is held by $holder. Close that program completely, including from the tray, then switch the toggle on again.';
  }

  @override
  String apiPortBusyUnknown(int port) {
    return 'Port $port is held by another program that could not be identified. Most often it is another VPN client. Close it and switch the toggle on again.';
  }

  @override
  String get apiRulesInProxyOnlyEdit =>
      'The \"Block\" list is edited on the split tunneling screen';

  @override
  String get dnsShortVpn => 'via VPN';

  @override
  String get dnsShortSystem => 'system';

  @override
  String get dnsShortCustom => 'custom';

  @override
  String get tunUacTitle => 'TUN requires administrator rights';

  @override
  String get tunUacBody =>
      'You can set it up once: the app will create a Windows Task Scheduler task with the highest privileges, and after that the tunnel will start WITHOUT a UAC prompt.\n\nOne administrator prompt will appear now. The app itself keeps running without elevated rights.';

  @override
  String get tunUacLater => 'Later (ask every time)';

  @override
  String get tunUacSetup => 'Set up';

  @override
  String get tunUacDone => 'Done: TUN will start without a UAC prompt';

  @override
  String get tunUacFail =>
      'Could not create the task — UAC will be requested on connect';

  @override
  String get autoReconnectTitle => 'Auto-reconnect';

  @override
  String get autoReconnectSub =>
      'Restore the connection on drop and network change';

  @override
  String get killSwitchTitle => 'Kill switch';

  @override
  String get alwaysOnTitle => 'System-wide leak protection';

  @override
  String get alwaysOnSub =>
      'Always-on VPN with “block connections without VPN” — keeps blocking even when the app is closed';

  @override
  String get killSwitchSubTun =>
      'Do not let traffic bypass the VPN while reconnecting';

  @override
  String get killSwitchSubProxy =>
      'In “System proxy” mode it protects only proxy-aware apps. Fully — only TUN';

  @override
  String get killSwitchSubOff => 'Requires auto-reconnect to be enabled';

  @override
  String get networkRecoverTitle => 'Recover network';

  @override
  String get networkRecoverSub =>
      'If the internet is gone after VPN. Requires administrator rights';

  @override
  String get networkRecoverConfirmTitle => 'Recover network?';

  @override
  String get networkRecoverConfirmBody =>
      'Reset of winsock, IP stack, DNS and the system proxy. Administrator rights (UAC) are required. The winsock/IP reset takes effect after a reboot.';

  @override
  String get networkRecoverConfirmOk => 'Recover';

  @override
  String get interferenceTitle => 'Check for interference (other VPNs)';

  @override
  String get interferenceDialogTitle => 'Network interference';

  @override
  String get interferenceNoneFound => 'No other VPNs or interference detected.';

  @override
  String get interferenceIgnore => 'Ignore';

  @override
  String get identityUserAgent => 'User-Agent';

  @override
  String identityUaAutoNote(String version) {
    return 'Updated automatically with the app version. Also sent: X-HWID, X-Device-OS, X-Ver-OS, X-App-Version ($version).';
  }

  @override
  String get urlSchemesTitle => 'URL schemes';

  @override
  String get urlSchemesSub =>
      'Import and control the VPN via links (connect / toggle / update)';

  @override
  String get panelOwnerTitle => 'For the panel owner';

  @override
  String get panelOwnerBody =>
      'Regular users don\'t need this — you can skip it.\n\nSo the app receives your subscription in the correct JSON format (XRAY_JSON), add this block to the Response Rules of your Remnawave panel — it matches our User-Agent:';

  @override
  String get panelOwnerCopy => 'Copy block';

  @override
  String get aboutVersion => 'SilentGate version';

  @override
  String get aboutXrayCore => 'Xray core';

  @override
  String get aboutHwid => 'Device HWID';

  @override
  String get aboutThirdPartyTitle => 'Third-party components and licenses';

  @override
  String get aboutThirdPartySub =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), Wintun — run as separate processes';

  @override
  String get aboutThirdPartySubEmbedded =>
      'Xray-core (MPL-2.0), sing-box (GPL-3.0), libXray (MIT) — built into the app';

  @override
  String get thirdPartyBodyEmbedded =>
      'On Android the cores are BUILT INTO the app (a native library inside the APK).\n\n• sing-box — GPL-3.0. The library is linked into the app, so derivatives must stay under GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nClient source code: https://github.com/Solat228/silentgate\nFull license texts — buttons below.';

  @override
  String get logsTitle => 'Logs';

  @override
  String get logsSub =>
      'App and TUN (sing-box): subscription import, ping, errors';

  @override
  String get thirdPartyTitle => 'Third-party components';

  @override
  String get thirdPartyBody =>
      'SilentGate ships together with third-party executables. They run as SEPARATE processes and are not embedded into the app.\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  TUN tunnel and proxy core for Hysteria2\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — Wintun license\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — routing data, CC-BY-SA-4.0\n\nFull license texts are in the “licenses” folder next to the app.';

  @override
  String get supportSectionNote =>
      'Tap “Contact support” — a window opens where you generate a log file yourself (versions, OS, settings, app.log + tail of singbox.log; no passwords or subscription token, URL hidden). After that a button to send it to Telegram support appears.';

  @override
  String get supportButtonTitle => 'Contact support';

  @override
  String get supportButtonSub => 'Generate a log and open the support chat';

  @override
  String get supportDialogTitle => 'Support';

  @override
  String get supportDialogTitleDone => 'Log is ready — where to send';

  @override
  String get supportWhatWillHappen => 'What will happen:';

  @override
  String get supportBullet1 =>
      '• One file will collect versions, OS, settings and logs (app.log + tail of singbox.log). It contains no passwords or subscription token, the subscription URL is hidden.';

  @override
  String get supportBullet2 =>
      '• After tapping, FIRST the folder with the file opens, then the file itself. Describe the problem at the top, save it — and a button to send it to support appears.';

  @override
  String supportError(String error) {
    return 'Failed to build the report: $error';
  }

  @override
  String get supportDoneText =>
      'The report is built and opened (folder, then file). Describe the problem at the top, save the file and send it to support — the app will help open Telegram.';

  @override
  String get supportWhoTo => 'Where to send:';

  @override
  String get supportContact => 'Contact support';

  @override
  String supportContactNamed(String name) {
    return 'Contact support ($name)';
  }

  @override
  String get supportDevServiceName => 'Client developer';

  @override
  String get supportShowOnPc => 'Show on PC';

  @override
  String get supportCopyPath => 'Copy path';

  @override
  String get supportGenerating => 'Building…';

  @override
  String get supportGenerateButton => 'Generate a support log';

  @override
  String get pingTwoPhaseTitle => 'Verify it works (through the tunnel)';

  @override
  String get pingTwoPhaseSubOn =>
      'After TCP — a request through the server: filters out non-working ones (Reality, etc.)';

  @override
  String get pingTwoPhaseSubOff =>
      'Only the single selected method (below) is used';

  @override
  String get pingMethodCheck => 'Verification method:';

  @override
  String get pingMethodPing => 'Ping method:';

  @override
  String get speedTestProbe => 'Speed test probe:';

  @override
  String get speedTestFull => '20 MB (more accurate)';

  @override
  String get speedTestLight => '5 MB (economical)';

  @override
  String get testUrlLabel => 'Test URL (via Proxy)';

  @override
  String get appUpdateServerUnavailable => 'Update server unavailable';

  @override
  String appUpdateAvailable(String version) {
    return 'Version $version available';
  }

  @override
  String get appUpdateLatest => 'You have the latest version';

  @override
  String get appUpdateDownload => 'Download';

  @override
  String get appUpdateCheckTitle => 'Check for updates on launch';

  @override
  String get appUpdateManual => 'Downloading and installing — manually';

  @override
  String get appUpdateEndpointLabel => 'Version endpoint';

  @override
  String get urlSchemeSilentgateTitle => 'silentgate:// links';

  @override
  String get urlSchemeSilentgateSub =>
      'Import and control the VPN via links. Enabled by default';

  @override
  String get urlSchemeDisableTitle => 'Disable silentgate:// links?';

  @override
  String get urlSchemeDisableBody =>
      'Import via link and control schemes (connect / disconnect / toggle / update) will stop working. Leave it on if unsure.';

  @override
  String get urlSchemeDisableOk => 'Disable';

  @override
  String get urlSchemeServerTitle => 'Open server links';

  @override
  String get urlSchemeServerSub =>
      'Intercept vless:// and others from other clients';

  @override
  String get urlSchemeServerConfirmTitle => 'Intercept server links?';

  @override
  String urlSchemeServerConfirmBody(String schemes) {
    return '$schemes\n\nThese links are usually bound to another VPN client (Happ, v2rayTun). SilentGate will take them over.';
  }

  @override
  String get urlSchemeServerConfirmOk => 'Intercept';

  @override
  String get urlSchemeAutoConnect => 'Connect after import';

  @override
  String get autoTitle => 'Auto-configuration';

  @override
  String get autoClearResults => 'Clear results';

  @override
  String autoFoundWorking(Object count) {
    return 'Working found: $count';
  }

  @override
  String get autoPinnedTop => ' — pinned to the top of the list';

  @override
  String get autoSearchContinues => ' (search continues…)';

  @override
  String get autoCheckServices => 'Check services';

  @override
  String get autoPinFoundOnTop => 'Pin found servers to the top of the list';

  @override
  String get autoTryFragment => 'Try bypass (fragment)';

  @override
  String get autoNoSubscriptionPasteKey =>
      'No subscription. Paste a single key — we\'ll find working settings:';

  @override
  String get autoTuneByKey => 'Tune by key';

  @override
  String autoTesting(int index, int total) {
    return 'Testing $index/$total: ';
  }

  @override
  String autoVariant(Object label) {
    return 'Variant: $label';
  }

  @override
  String autoServicesPassed(int ok, int total) {
    return '$ok of $total services';
  }

  @override
  String get autoConnect => 'Connect';

  @override
  String get autoStopSearch => 'Stop search';

  @override
  String get autoDoneRefreshPing => 'Done — refresh ping of found';

  @override
  String autoFoundPinnedRefreshing(Object count) {
    return 'Found $count, pinned to the top. Refreshing ping…';
  }

  @override
  String autoServersForTuning(int selected, int total) {
    return 'Servers to tune ($selected/$total)';
  }

  @override
  String get autoSelectAll => 'All';

  @override
  String get autoDeselectAll => 'Clear';

  @override
  String get autoTuneSelected => 'Tune selected';

  @override
  String autoTuned(Object label) {
    return 'Tuned: $label';
  }

  @override
  String get infoDialogTitle => 'Info';

  @override
  String get infoCopied => 'Explanation copied';

  @override
  String get commonGotIt => 'Got it';

  @override
  String get enumSplitAll => 'All — through VPN';

  @override
  String get enumSplitOnly => 'Only selected — through VPN';

  @override
  String get enumSplitExcept => 'Selected — outside VPN';

  @override
  String get enumActionTunnel => 'Tunnel';

  @override
  String get enumActionDirect => 'Direct';

  @override
  String get enumActionBlock => 'Block';

  @override
  String homeUpdateAvailable(Object version) {
    return 'Version $version available';
  }

  @override
  String get homeDownload => 'Download';

  @override
  String homeSubscriptionUpdated(Object summary) {
    return 'Subscription updated: $summary';
  }

  @override
  String get homeReconnect => 'Reconnect';

  @override
  String homePingProgress(int done, int total) {
    return 'Pinging servers: $done of $total';
  }

  @override
  String get homeAutoConfigStarting => 'Auto-configuration starting…';

  @override
  String homeAutoConfigProgress(int current, int total, String name) {
    return 'Auto-configuration: $current of $total — $name';
  }

  @override
  String get homeImport => 'Import';

  @override
  String get homeSettings => 'Settings';

  @override
  String get homeAutoBest => 'Auto (best server)';

  @override
  String get homeAutoConfig => 'Auto-configuration';

  @override
  String homeServersCount(Object count) {
    return 'Servers ($count)';
  }

  @override
  String homeFoundCount(int found, int total) {
    return 'Found $found of $total';
  }

  @override
  String get homePingServers => 'Ping servers';

  @override
  String get homePingFound => 'Ping found';

  @override
  String get homeNothingFound => 'Nothing found';

  @override
  String get homeOnboardingTitle => 'Start by importing a subscription';

  @override
  String get homeOnboardingSubtitle => 'Paste a Remnawave link or a single key';

  @override
  String get homeImportSubscription => 'Import subscription';

  @override
  String homeSessionTraffic(String down, String up) {
    return 'This session: ↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'GB';

  @override
  String subBarUsage(String used, String total) {
    return '$used of $total';
  }

  @override
  String get subBarSubscription => 'Subscription';

  @override
  String get subBarRefreshing => 'Refreshing…';

  @override
  String get subBarRefreshSubscription => 'Refresh subscription';

  @override
  String get subBarSupport => 'Support';

  @override
  String get subBarRefresh => 'Refresh';

  @override
  String get subBarAddSubscription => 'Add subscription';

  @override
  String get subBarCopyLink => 'Copy link';

  @override
  String get subBarDeleteSubscription => 'Delete subscription';

  @override
  String get subBarLinkCopied => 'Link copied';

  @override
  String get subBarDeleteConfirmTitle => 'Delete subscription?';

  @override
  String get subBarDeleteConfirmBody =>
      'Servers from this subscription will be removed from the list.';

  @override
  String subBarDeletePinned(Object count) {
    return 'Also delete pinned ($count) with their edits';
  }

  @override
  String get subBarDeletePinnedHint =>
      'Otherwise they stay in the list and survive deletion';

  @override
  String get subBarCancel => 'Cancel';

  @override
  String get subBarDelete => 'Delete';

  @override
  String get subBarSubscriptionDeleted => 'Subscription deleted';

  @override
  String subBarSubscriptionUpdated(Object summary) {
    return 'Subscription updated: $summary';
  }

  @override
  String get subBarMore => 'Details';

  @override
  String subBarAdded(Object count) {
    return 'Added ($count)';
  }

  @override
  String subBarRemoved(Object count) {
    return 'Removed ($count)';
  }

  @override
  String subBarAutoUpdate(Object hours) {
    return '· auto-update ${hours}h';
  }

  @override
  String subBarValidPerpetual(Object auto) {
    return 'Valid: unlimited  $auto';
  }

  @override
  String get subBarExpired => 'Subscription expired:';

  @override
  String get subBarValidUntil => 'Valid until:';

  @override
  String get subSwitcherPingAll => 'Ping servers of all subscriptions';

  @override
  String get subSwitcherExpired => 'Expired';

  @override
  String subSwitcherExpiredOn(String date) {
    return 'Subscription expired on $date';
  }

  @override
  String subSwitcherCountTotal(int total) {
    return 'Servers in this subscription: $total. The channel check has not run yet — start «Ping servers of all subscriptions».';
  }

  @override
  String subSwitcherCountWorking(int total, int working) {
    return 'Servers in this subscription: $total. Passed the channel check (a request through the server): $working.';
  }

  @override
  String get infoCaptureMode =>
      'How traffic is intercepted. «System proxy» sets a local proxy in the system (no administrator rights; catches browsers and most applications). «TUN» is a virtual network adapter that catches ALL traffic (including UDP and applications that ignore the proxy), but requires administrator rights.';

  @override
  String get infoSystemProxy =>
      'A local HTTP proxy in the system settings (WinINET registry). No administrator rights. Does not intercept UDP or applications that ignore the system proxy.';

  @override
  String get infoTunMode =>
      'A full tunnel through the wintun virtual adapter + sing-box. Catches all traffic, including UDP. Requests administrator rights (UAC) when enabled.';

  @override
  String get infoTunProvider =>
      'The driver for the virtual network adapter. On Windows, wintun is used (bundled with the core). No other drivers are required.';

  @override
  String get infoTunStack =>
      'The TUN network stack (sing-box).\n\n«auto» — AUTO-SELECTION: if the tunnel fails to come up, the app itself cycles through system → gvisor → mixed, and then lowers the MTU (1400, 1280). The combination that worked is remembered and tried first next time. The selection progress is shown in the status and in the log.\n\nAn explicit choice disables auto-selection: system — the OS stack, fastest, but more finicky with antiviruses; gvisor — userspace, slower, maximally compatible; mixed — TCP via system, UDP via gvisor.';

  @override
  String get infoTunMtu =>
      'The maximum packet size in the TUN adapter. Default is 1500; lower it (1400, 1280) if you get disconnects — too small a value reduces speed.\n\nWith the «auto» stack this is only the starting value: if the tunnel fails to come up, the app itself will try smaller MTUs.';

  @override
  String get infoTunStrictRoute =>
      'Strict routing in sing-box. On Windows it fixes two typical problems: DNS leaks (by default the system sends queries to all adapters at once) and «network unreachable» errors. Turn it off only if it breaks VirtualBox/Hyper-V.';

  @override
  String get infoTunIpv6 =>
      'Route IPv6 into the tunnel. If you turn it off while your ISP has IPv6 enabled, some traffic will go OUTSIDE the VPN (leaking your real address) or will hang. Turn it off only if you have IPv6 network problems.';

  @override
  String get infoTunEndpointIndependentNat =>
      'NAT mode for UDP. Needed for games, voice chats and WebRTC — without it, connections may fail to establish. Disable it only to save memory.';

  @override
  String get infoTunBypassLan =>
      'The local network (private addresses 192.168.*, 10.*, router, printers, NAS) goes around the VPN. Usually you want this on, otherwise you lose access to devices on the network.';

  @override
  String get infoTunExcludeCidrs =>
      'Additional subnets that always go around the VPN (CIDR format, e.g. 10.8.0.0/24). Useful for corporate networks and other VPNs.';

  @override
  String get infoTunPrivilege =>
      'TUN requires administrator rights. Once, we create a task in the Windows Task Scheduler with the highest privileges — after that the tunnel starts WITHOUT a UAC prompt on each connection. The task belongs to you and is removed with the button below or when the program is uninstalled.';

  @override
  String get infoAppUpdate =>
      'Once per launch, the app asks your server whether a newer version exists and shows a notification with a «Download» button.\n\nThe app downloads and runs NOTHING on its own: the installer is not signed with a certificate, and auto-running a downloaded exe runs into SmartScreen and looks to antiviruses like malware behavior. You install the update yourself.\n\nIf the server is unavailable, the app simply stays silent and writes an entry to the log. The response format and server setup are described in docs/APP_UPDATE.md.';

  @override
  String get infoSpeedTest =>
      'The amount of data downloaded when measuring speed (right-click a server → «Server info» → «Measure speed»).\n\n20 MB — the main mode: on fast links (100+ Mbps) a short probe does not have time to ramp up and underestimates the result.\n5 MB — the economical mode: noticeably cheaper on traffic, handy for running through many servers.\n\nThe measurement runs ONLY manually and consumes your subscription\'s traffic. Speed is measured twice: directly and through the selected server, so you can see exactly how much is lost on the VPN.';

  @override
  String get infoAutoReconnect =>
      'If the core crashed, the server dropped, or the network changed (Wi-Fi ↔ cable, waking from sleep, a new IP), the app brings the connection back up on its own. Pauses between attempts grow: 0.8 s → 3 s → 8 s → 20 s, up to 8 attempts, after which an error is shown. Disconnecting with the button always cancels the recovery.\n\nA network change is detected by the real addresses of other adapters: your own tunnel and service addresses (link-local) are not counted, a change is accepted only if it held for two polls in a row, and the signal is ignored for the first 15 seconds after connecting. Without these safeguards, bringing up the tunnel would itself count as a «network change» and cause endless reconnection.';

  @override
  String get infoKillSwitch =>
      'Do not let traffic out around the VPN while the connection is being restored. The capture is NOT released between attempts: in TUN mode the adapter stays up, in «System proxy» mode the proxy stays configured — applications get a connection error instead of unencrypted access to the internet.\n\nHonestly about the limits: in «System proxy» mode this protects only programs that respect the system proxy (browsers and most applications). Programs that ignore the proxy, and UDP, will go directly — full tightness is provided only by TUN mode. Requires auto-reconnect enabled.';

  @override
  String get infoUserAgent =>
      'How the app identifies itself to the panel (the User-Agent header). It always sends «SilentGate/version (Windows)».\n\nBy this name the Remnawave panel chooses the subscription FORMAT. XRAY_JSON is needed — it delivers ready-made server configs; from a base64 list of links some settings are restored approximately, and auto-selection (burstObservatory) works worse.\n\nConfigured in the panel: Templates → Response Rules → a rule with the condition user-agent CONTAINS SilentGate and response type XRAY_JSON (place it above the Fallback Base64 rule).\n\nThe override field is needed only as a temporary workaround — if the panel does not yet know the app, you can identify as a client it does know.';

  @override
  String get infoDnsMode =>
      'Who resolves domains in TUN mode. «Through VPN» (recommended) — queries go into the tunnel over TCP, and your ISP does not see which sites you open. «System» — as in Windows: a DNS leak is possible, and if the server does not pass UDP, the internet may drop entirely. «Custom» — the server you specify, through the tunnel.';

  @override
  String get infoDnsCustomServer =>
      'The address of the DNS server for «Custom» mode (for example 9.9.9.9 or 8.8.8.8). Queries to it go through the tunnel over TCP.';

  @override
  String get infoDnsHijack =>
      'Intercept DNS queries (UDP port 53) inside the tunnel. Without this, queries slip past the rules: a leak is possible, and the domain rules of split tunneling work less precisely.';

  @override
  String get infoDnsStrategy =>
      'Which addresses to request: prefer_ipv4 (recommended) — IPv4 first, ipv4_only — IPv4 only (fixes problems with broken IPv6), prefer_ipv6/ipv6_only — for IPv6 networks.';

  @override
  String get infoSingboxLogLevel =>
      'The verbosity of the sing-box log (%APPDATA%\\SilentGate\\singbox.log). warn — normal mode. info/debug — if the tunnel does not work: the log will show the exact cause. debug noticeably increases the file size.';

  @override
  String get infoSplitMode =>
      'The base — where everything that has no manually set action goes, and which action is assigned to new entries. «All — through VPN»: by default all traffic into the tunnel. «Only selected — through VPN»: by default directly, into the tunnel only those marked «Tunnel». «Selected — around VPN»: the opposite, everything into the tunnel, and those marked «Direct» go directly.';

  @override
  String get infoSplitApps =>
      'Click an application — a window opens where you choose the action (Tunnel — through VPN, Direct — around VPN, Block — no network) and the matching method: by exe name (reliable) or by full path. You can pick from running apps or specify an .exe.';

  @override
  String get infoSplitDomains =>
      'Domains (suffixes). For example, youtube.com also covers www.youtube.com. Works by the name from the TLS connection (SNI).';

  @override
  String get infoVerifyViaProxy =>
      'First we check functionality through the proxy (the server actually returns 204), and only if the server responded do we separately measure latency with the chosen method (TCP/ICMP).';

  @override
  String get infoProxyGet =>
      'A GET request through the tunnel to the test URL. Checks that the server actually passes traffic and returns 204. The most honest functionality test; a bit slower.';

  @override
  String get infoProxyHead =>
      'Like GET, but only the headers — faster and less traffic. Some servers/CDNs may not support HEAD.';

  @override
  String get infoTcp =>
      'The time of the TCP handshake to the server address. A fast and accurate latency indicator, but it does not prove the tunnel works: a Reality server will answer TCP even if proxying is blocked. Recommended for latency.';

  @override
  String get infoIcmp =>
      'System ping. Often useless for Reality/CDN: ICMP may be blocked, or it measures the nearest CDN node. Keep it for network diagnostics.';

  @override
  String get infoTestUrl =>
      'The URL for checking functionality through the proxy. By default https://www.gstatic.com/generate_204 — it returns an empty 204 response, which is convenient and fast.';

  @override
  String get infoAutoConfig =>
      'Goes through servers and evasion variants (fragment, fingerprint) and builds a list of those where the selected services work. It does not stop at the first — you choose from the ones found. Checking is done through the proxy; the VPN is not enabled during this time.';

  @override
  String get infoAutoConfigServices =>
      'Which services must work for a server to be considered suitable. The check is resistant to ISP stub pages (the response signature is verified, not just a «200 OK»).';

  @override
  String get infoAutoPinFound =>
      'Found working combinations (server + evasion variant) are immediately pinned to the top of the common server list, so you can use them without coming back here. Turn it off if you don\'t want auto-config to change the order of your list — the results will still be visible on this screen.';

  @override
  String get infoTryFragment =>
      'Try the variant with TLS ClientHello fragmentation (DPI evasion) if the «bare» server does not work. A bit longer, but finds a working combination on throttled servers.';

  @override
  String get infoAutoStrategy =>
      '«First working» — go through everything and connect to any one found (you choose). «Best within budget» — search within a time limit and pick the fastest.';

  @override
  String get infoScheme =>
      'Registers the silentgate:// protocol in the system (for the current user, without administrator rights). After that, clicking a link silentgate://import?url=… (import) or silentgate://connect / toggle (control) in a browser opens the app and performs the action. Enabled by default.';

  @override
  String get infoAutoConnectAfterImport =>
      'Connect to the first server immediately after a successful subscription import via link.';

  @override
  String get infoNetworkRecover =>
      'Resets network parameters if the internet is gone after a crash/shutdown of the PC with the VPN enabled: winsock, the IP stack, the DNS cache, the system proxy. Requires administrator rights; resetting winsock and the IP stack takes effect after a RESTART.';

  @override
  String get infoInterference =>
      'A check for other VPNs and network interference (foreign TUN adapters, VPN processes, zapret/GoodbyeDPI) that may conflict with SilentGate. You can close them or ignore them.';

  @override
  String get pingInfoProxyGet =>
      'A GET request through the tunnel to the test URL. Checks that the server actually passes traffic and returns 204. The most honest functionality test; a bit slower due to fully downloading the response. Recommended for a functionality check.';

  @override
  String get pingInfoProxyHead =>
      'Like GET, but requests only the headers — less traffic and faster. Checks the tunnel\'s functionality; some servers/CDNs may not support HEAD.';

  @override
  String get pingInfoTcp =>
      'Measures the time of the TCP handshake to the server address. A fast and accurate indicator of endpoint latency, but it does not prove that the tunnel works: a Reality server will answer TCP even if proxying is blocked. Recommended for latency.';

  @override
  String get pingInfoIcmp =>
      'System ping (echo request). Often useless for Reality/CDN: ICMP may be blocked, or it measures the nearest CDN node rather than the server. Keep it for network diagnostics.';

  @override
  String get pingInfoTwoPhase =>
      'After the TCP check, the servers that responded are additionally checked with a request through the tunnel (GET/HEAD to the test URL). This filters out servers that keep the port open but do not proxy traffic. Latency is still shown by TCP.';

  @override
  String get pingInfoTunStage =>
      'A full tunnel (TUN) is the next stage. Right now the «System proxy» mode is in use. In TUN mode all traffic (including UDP and applications that ignore the proxy) will go through the wintun virtual adapter + tun2socks. Requires administrator rights.';

  @override
  String get pingInfoTunStack =>
      'The TUN network stack (sing-box). auto — leave it to the core\'s discretion (currently mixed). system — the OS stack: maximum speed, but more finicky with rights/antiviruses. gvisor — a userspace stack: slower, but the most compatible. mixed — TCP via system, UDP via gvisor (a balance). If TUN does not connect or drops connections — try gvisor.';

  @override
  String get pingInfoAutoConfig =>
      'When enabled, the app itself goes through servers and evasion variants (fragment, fingerprint) and connects to the first one where the selected services work (checking through the proxy, without enabling the VPN during the search).';

  @override
  String get logsTabApp => 'App';

  @override
  String get logsTabTun => 'TUN (sing-box)';

  @override
  String get logsRefresh => 'Refresh';

  @override
  String get logsCopy => 'Copy';

  @override
  String get logsClearApp => 'Clear app log';

  @override
  String get logsCopied => 'Log copied';

  @override
  String get logsLoading => 'Loading…';

  @override
  String get logsEmpty => 'Empty for now.';

  @override
  String get logsTunEmpty =>
      'Empty — TUN has not been started on this system yet.';

  @override
  String get importScrDone => 'Imported';

  @override
  String get importScrWelcome => 'Welcome to SilentGate';

  @override
  String get importScrTitle => 'Import subscription';

  @override
  String get importScrSubscriptionFallback => 'Subscription';

  @override
  String get importScrHint =>
      'Paste a subscription link (Remnawave), a silentgate:// deep link, or a single vless:// / vmess:// / trojan:// / ss:// / hysteria2:// link';

  @override
  String get importScrLoading => 'Loading…';

  @override
  String get importScrPasteImport => 'Import from clipboard';

  @override
  String get importScrImportField => 'Import from field';

  @override
  String get serversTitle => 'Servers';

  @override
  String serversFound(int found, int total) {
    return 'Servers — found $found of $total';
  }

  @override
  String get serversRefresh => 'Refresh subscription';

  @override
  String get serversPinging => 'Pinging…';

  @override
  String get serversPingAll => 'Ping all';

  @override
  String get serversPingFound => 'Ping found';

  @override
  String get serversEmpty => 'The server list is empty. Import a subscription.';

  @override
  String get serversNothingFound => 'Nothing found';

  @override
  String get toastCopied => 'Copied';

  @override
  String get toastHide => 'Hide';

  @override
  String get srvInfoTitle => 'Server information';

  @override
  String srvInfoProbeFailed(Object error) {
    return 'Failed to start test connection: $error';
  }

  @override
  String get srvInfoServerAddressFailed => 'Could not determine server address';

  @override
  String get srvInfoSectionExit => 'Where you exit';

  @override
  String get srvInfoExitHint =>
      'Determined from the server address — no tunnel is started for this.';

  @override
  String get srvInfoAddressLocation => 'Server address and location';

  @override
  String get srvInfoCheckAgain => 'Check again';

  @override
  String get srvInfoSectionSpeed => 'Speed';

  @override
  String srvInfoSpeedHint(Object size) {
    return 'The probe downloads $size and uses your subscription traffic. The size can be changed in settings.';
  }

  @override
  String get srvInfoViaServer => 'Via server';

  @override
  String get srvInfoWithoutVpn => 'Without VPN';

  @override
  String get srvInfoMeasuring => 'Measuring…';

  @override
  String get srvInfoMeasureSpeed => 'Measure speed';

  @override
  String get srvInfoSectionParams => 'Connection parameters';

  @override
  String get srvInfoParamAddress => 'Address';

  @override
  String get srvInfoParamProtocol => 'Protocol';

  @override
  String get srvInfoParamTransport => 'Transport';

  @override
  String get srvInfoParamTlsFingerprint => 'TLS fingerprint';

  @override
  String get srvInfoParamType => 'Type';

  @override
  String get srvInfoPanelAutoProfile => 'Auto-select profile from the panel';

  @override
  String get srvInfoCouldNotDetermine => 'could not determine';

  @override
  String get srvInfoCopy => 'Copy';

  @override
  String get editorJsonTitle => 'JSON config';

  @override
  String get editorCopy => 'Copy';

  @override
  String get editorClose => 'Close';

  @override
  String get editorTitle => 'Edit server';

  @override
  String get editorFieldName => 'Name';

  @override
  String get editorFieldAddress => 'Address';

  @override
  String get editorFieldPort => 'Port';

  @override
  String get editorFieldUuidPassword => 'UUID / password';

  @override
  String get editorFieldObfs => 'Obfuscation (usually salamander)';

  @override
  String get editorFieldObfsPassword => 'Obfuscation password';

  @override
  String get editorFieldPortHopping => 'Port hopping (e.g. 20000-21000)';

  @override
  String get editorAllowSelfSigned => 'Allow self-signed certificate';

  @override
  String get editorAllowSelfSignedSub =>
      'Needed only if the server is configured that way';

  @override
  String get editorTransport => 'Transport';

  @override
  String get editorSecurity => 'Security';

  @override
  String get editorNone => '(none)';

  @override
  String get editorCancel => 'Cancel';

  @override
  String get editorSave => 'Save';

  @override
  String jsonProfileServers(int count, String burst) {
    return '$count servers$burst';
  }

  @override
  String get jsonCompositionUnknown => 'composition unknown';

  @override
  String get jsonYourSavedOverride => 'Your saved JSON (override)';

  @override
  String jsonPanelProfileApplied(Object summary) {
    return 'Auto-select profile from the panel: $summary — applied in full';
  }

  @override
  String get jsonPanelConfig => 'Config from the panel (XRAY_JSON)';

  @override
  String get jsonBuiltFromShareLink =>
      'Built from the share link — the panel did not send JSON. Update the subscription; if that does not help, check the Response Rules rule in the panel.';

  @override
  String get jsonInvalidJson => 'Invalid JSON';

  @override
  String get jsonSaved => 'Saved';

  @override
  String get jsonTitle => 'JSON config';

  @override
  String get jsonFieldEditor => 'Field editor';

  @override
  String get jsonCopy => 'Copy';

  @override
  String get jsonClose => 'Close';

  @override
  String get jsonSave => 'Save';

  @override
  String get srvTileEdit => 'Edit';

  @override
  String get srvTileNotice => 'Notice';

  @override
  String get srvTileRefresh => 'Refresh';

  @override
  String get srvTileSubscriptionUpdated => 'Subscription updated';

  @override
  String get srvTileCopy => 'Copy';

  @override
  String get srvTileInfo => 'Server information';

  @override
  String get srvTilePing => 'Ping';

  @override
  String get srvTileUnpin => 'Unpin';

  @override
  String get srvTilePin => 'Pin';

  @override
  String get srvTileJsonConfig => 'JSON config';

  @override
  String get srvTileSmart => 'Smart parameter tuning';

  @override
  String get srvTileDelete => 'Delete';

  @override
  String get srvTileServerDeleted => 'Server deleted';

  @override
  String get srvTileSaved => 'Saved';

  @override
  String get pingNa => 'n/a';

  @override
  String get pingNaTooltip => 'No TCP response — server unavailable (dead)';

  @override
  String get pingTimeout => 'timeout';

  @override
  String get pingTimeoutTooltip =>
      'TCP probe did not complete within the timeout — server unavailable';

  @override
  String pingMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get pingNoProxy => 'no proxy';

  @override
  String get pingNoProxyTooltip =>
      'Responds over TCP (latency shown), but the tunnel check (GET/HEAD) failed — traffic is not passing';

  @override
  String get pingOk => 'ok';

  @override
  String get pingOkTooltip =>
      'TCP latency to the server. Server is working: it responded over TCP and passed the tunnel check (GET/HEAD)';

  @override
  String get searchHint => 'Search by name, country, address…';

  @override
  String get searchReset => 'Clear';

  @override
  String get splitTitle => 'Split tunneling';

  @override
  String get splitTunOnlyBanner =>
      'Works only in TUN mode. In \"System proxy\" mode, apps decide for themselves whether to use the proxy — they can\'t be forced.';

  @override
  String get splitProxyOnlyBanner =>
      'In \"Proxy only\" mode there is nothing to intercept: the rules apply to no program on this computer. The \"Block\" list applies only to the local API ports, and only if \"Apply split-tunneling rules\" is switched on in the \"Traffic capture\" section. The other rules can be prepared here in advance: they start working once you switch to TUN.';

  @override
  String get splitEnableTun => 'Enable TUN';

  @override
  String get splitModeHeader => 'Mode';

  @override
  String get splitAppsHeader => 'Applications';

  @override
  String get splitAppsHint =>
      'Tap an app to set its action (Tunnel / Direct / Block) and matching method. The checkbox on the left enables/disables the rule.';

  @override
  String get splitByName => 'By name';

  @override
  String get splitByPath => 'By path';

  @override
  String get splitRuleDisabled => 'Disabled — rule is not applied';

  @override
  String get splitRemove => 'Remove';

  @override
  String get splitFromRunning => 'From running';

  @override
  String get splitPickInstalled => 'Choose app';

  @override
  String get splitInstalledApps => 'Installed applications';

  @override
  String get splitPickExe => 'Choose .exe';

  @override
  String get splitSitesHeader => 'Sites (domains)';

  @override
  String get splitSitesHint =>
      'Tap a site to choose an action (Tunnel / Direct / Block). A domain also covers its subdomains; subdomains are grouped into a tree. You can specify a port.';

  @override
  String splitOnlyPort(Object port) {
    return 'port $port only';
  }

  @override
  String get splitProgramsFileType => 'Programs';

  @override
  String get splitRunningApps => 'Running applications';

  @override
  String get splitSearchByName => 'Search by name';

  @override
  String get splitNothingFound => 'Nothing found';

  @override
  String get splitClose => 'Close';

  @override
  String get splitPortRange => 'Port 1–65535';

  @override
  String get splitAction => 'Action';

  @override
  String get splitPortOptional => 'Port (optional)';

  @override
  String get splitAnyPort => 'any';

  @override
  String get splitPortHelper =>
      'Empty = any port. Otherwise the rule applies only to this port';

  @override
  String get splitMatching => 'Matching';

  @override
  String get splitByNameSubtitle =>
      'Exe name, regardless of location (reliable)';

  @override
  String get splitByPathSubtitle => 'Full path to the exe (exact match)';

  @override
  String get splitDone => 'Done';

  @override
  String get splitEnterDomain => 'Enter a domain';

  @override
  String get splitAddSite => 'Add site';

  @override
  String get splitPort => 'Port';

  @override
  String get splitAdd => 'Add';

  @override
  String get routeBlock => 'Block';

  @override
  String get routeBlocked => 'Blocked';

  @override
  String get routeYourPc => 'Your PC';

  @override
  String get routeTunnel => 'Tunnel';

  @override
  String get routeViaVpn => 'Via VPN';

  @override
  String get routeVpn => 'VPN';

  @override
  String get routeInternet => 'Internet';

  @override
  String get routeRest => 'Everything else';

  @override
  String get routeDirectly => 'Directly';

  @override
  String get routeDirectPlusRest => 'Direct + rest';

  @override
  String get routeDirect => 'Direct';

  @override
  String get routeEmptyList => 'list is empty';

  @override
  String get trayShow => 'Show';

  @override
  String get trayToggle => 'Connect / Disconnect';

  @override
  String get trayQuit => 'Quit';

  @override
  String get trayMinimizeTitle => 'Minimize to tray';

  @override
  String get trayMinimizeBody => 'The app will keep running in the tray.';

  @override
  String get trayDontAsk => 'Don\'t ask again';

  @override
  String get trayMinimizeOk => 'Minimize';

  @override
  String get trayVpnTitle => 'VPN connected';

  @override
  String get trayVpnBody => 'Disconnect the VPN and quit the app?';

  @override
  String get trayStay => 'Stay';

  @override
  String get trayQuitVpn => 'Disconnect and quit';

  @override
  String get tunTaskDone => 'Done: TUN will start without a UAC prompt';

  @override
  String get tunTaskFailed =>
      'Failed to create task (UAC declined or blocked by policy)';

  @override
  String get tunLogTitle => 'TUN log (sing-box)';

  @override
  String get tunLogEmpty => 'Log is empty — the tunnel has not started yet.';

  @override
  String get tunCopy => 'Copy';

  @override
  String get tunClose => 'Close';

  @override
  String get tunTitle => 'TUN and routing';

  @override
  String get tunSectionPrivilege => 'Administrator rights';

  @override
  String get tunChecking => 'Checking…';

  @override
  String get tunNoUacConfigured => 'Start without UAC is configured';

  @override
  String get tunUacEachConnect => 'UAC will be requested on every connection';

  @override
  String get tunTaskSubtitle =>
      'A Windows Task Scheduler task with highest privileges (created once).';

  @override
  String get tunRecreateTask => 'Recreate task';

  @override
  String get tunSetupOneUac => 'Set up (one UAC)';

  @override
  String get tunRemoveTask => 'Remove task';

  @override
  String get tunSectionAdapter => 'Adapter';

  @override
  String get tunStack => 'TUN stack';

  @override
  String get tunSectionRouting => 'Routing';

  @override
  String get tunStrictRoute => 'Strict routing (strict_route)';

  @override
  String get tunIpv6 => 'IPv6 in the tunnel';

  @override
  String get tunEndpointNat => 'Endpoint-independent NAT (UDP, games)';

  @override
  String get tunLanBypass => 'Local network bypasses VPN';

  @override
  String get tunDnsServer => 'DNS server';

  @override
  String get tunDnsHijack => 'Intercept DNS (port 53)';

  @override
  String get tunResolveStrategy => 'Resolve strategy';

  @override
  String get tunSectionDiagnostics => 'Diagnostics';

  @override
  String get tunSingboxLogLevel => 'sing-box log level';

  @override
  String get tunShowLog => 'Show TUN log';

  @override
  String get tunDnsVpn => 'Through VPN (recommended)';

  @override
  String get tunDnsSystem => 'System';

  @override
  String get tunDnsCustom => 'Custom server';

  @override
  String get tunDnsVpnHint => 'Requests go into the tunnel over TCP — no leaks';

  @override
  String get tunDnsSystemHint => 'Same as Windows: DNS leak possible';

  @override
  String get tunDnsCustomHint =>
      'The specified server, also through the tunnel';

  @override
  String get tunExcludeSubnets => 'Subnets bypassing VPN';

  @override
  String get tunAdd => 'Add';

  @override
  String get urlGroupImport => 'Import';

  @override
  String get urlGroupControl => 'Control';

  @override
  String get urlHintSubUrl => 'subscription URL';

  @override
  String get urlHintServerLink => 'server link';

  @override
  String get urlDescImportSub => 'Import a subscription';

  @override
  String get urlDescImportServer =>
      'Add a single server (vless / trojan / ss / hysteria2 …)';

  @override
  String get urlDescConnect => 'Connect the VPN';

  @override
  String get urlDescDisconnect => 'Disconnect the VPN';

  @override
  String get urlDescToggle => 'Toggle the VPN';

  @override
  String get urlDescUpdate => 'Refresh the active subscription';

  @override
  String get urlSupportedImport =>
      'On import the app understands: a subscription URL (http/https), and single servers vless:// / vmess:// / trojan:// / ss:// / hysteria2:// (hy2://).';

  @override
  String get reportTitle => 'SilentGate — support report';

  @override
  String get reportDescribeHere =>
      '>>> DESCRIBE THE PROBLEM HERE (fill in and save the file): <<<';

  @override
  String get reportWhatDid => 'What you did:';

  @override
  String get reportWhatExpected => 'What you expected:';

  @override
  String get reportWhatHappened => 'What happened:';

  @override
  String get reportWhenStarted => 'When it started:';

  @override
  String get reportTechNoticeLine1 =>
      'Below is technical information. Review it before sending;';

  @override
  String get reportTechNoticeLine2 =>
      'there are no passwords or subscription token here, the subscription URL is hidden.';

  @override
  String get noRealIpTitle => 'Never use my real IP';

  @override
  String get noRealIpSub =>
      'Even with the VPN up, all “direct” traffic goes through the VPN (RU sites too). The local network stays direct.';

  @override
  String get flagAuto => 'AUTO';

  @override
  String get autoUpdateIntervalLabel => 'Update interval, h';

  @override
  String get autoUpdatePreferSub => 'Use the interval from the subscription';

  @override
  String get pingLegendInfo =>
      'Ping badge color: green/yellow/orange — server works (TCP + a check through the tunnel). Grey — responds over TCP but does not proxy traffic (a typical Reality port). Red “n/a” — no response, excluded. Ping is always measured DIRECTLY (outside the VPN).';

  @override
  String get pingUntestedHint =>
      'Not tested yet. On mobile, Hysteria2 and “Auto” profiles are measured only while connected.';

  @override
  String get panelTunnelMarker => 'Has its own split tunneling';

  @override
  String panelInfoServers(Object n) {
    return 'Servers in the profile: $n (the best is chosen)';
  }

  @override
  String get panelInfoDirect =>
      'Some traffic (e.g. local sites) goes directly, outside the VPN';

  @override
  String get panelInfoBlock => 'Some traffic is blocked (ads/torrents)';

  @override
  String get serviceChecksTitle => 'Service check';

  @override
  String get serviceChecksInfo =>
      'Six popular services are checked automatically: first at app start while the VPN is off, then again right after connecting. The two dots show \"before → after\", so you can see what the VPN actually changed. Tap to re-check. Green — opens, orange — blocked by region, red — unreachable.';

  @override
  String get serviceStatusOk => 'Works';

  @override
  String get serviceStatusGeo => 'Opens, but blocked in the exit country';

  @override
  String get serviceStatusFail => 'Does not open';

  @override
  String get serviceStatusChecking => 'Checking…';

  @override
  String get serviceStatusTap => 'Tap to check';

  @override
  String serviceLatencyMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get homeTunAutotuneProgress => 'Tuning TUN parameters…';

  @override
  String get homeTunAutotuneDone => 'TUN parameters tuned';

  @override
  String get homeTunAutotuneFailed => 'Could not tune TUN parameters';

  @override
  String get hy2NoteTitle => 'Hysteria2 servers';

  @override
  String get hy2NoteBody =>
      'Hysteria2 servers arrive only in the XRAY_JSON format — SilentGate requests exactly that, and sing-box runs them automatically. If Hysteria2 doesn\'t appear in the list: (for the Remnawave panel owner) enable the hysteria inbounds and assign them to the subscription. Note: Remnawave before 2.8.0 serves Hysteria2 ONLY in XRAY_JSON — it is absent from base64/CLASH/SINGBOX, so the Response Rules → XRAY_JSON rule above is required.';

  @override
  String get enumStatusDisconnected => 'Disconnected';

  @override
  String get enumStatusConnecting => 'Connecting…';

  @override
  String get enumStatusConnected => 'Connected';

  @override
  String get enumStatusDisconnecting => 'Disconnecting…';

  @override
  String get enumStatusError => 'Error';

  @override
  String get enumVariantPlain => 'default';

  @override
  String get tagAutoSelect => 'AUTO';

  @override
  String get tagPanel => 'PANEL';

  @override
  String get tagPortHopping => 'PORT HOPPING';

  @override
  String syncServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count servers',
      one: '$count server',
    );
    return '$_temp0';
  }

  @override
  String get syncNoChanges => 'no changes';

  @override
  String get errInvalidJson => 'Invalid JSON';

  @override
  String get errPickServerFirst => 'Select a server first';

  @override
  String get errImportSubscriptionFirst => 'Import a subscription first';

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
    return 'Port $port is already in use by $by.';
  }

  @override
  String get srvTileMenu => 'Server actions';

  @override
  String get supportCopyReport => 'Copy report';

  @override
  String get supportReportCopied =>
      'Report copied — paste it into the support chat';

  @override
  String subBarUsedOnly(String used) {
    return 'Used $used';
  }

  @override
  String get subBarUnlimitedTraffic => 'unlimited traffic';

  @override
  String get supportDescribeLabel => 'Describe the problem';

  @override
  String get supportDescribeHint =>
      'What you did, what you expected, what happened and when it started';

  @override
  String get supportDescribeRequired =>
      'Describe the problem — a report without it is useless';

  @override
  String get supportNoScreenshots =>
      'Do not paste screenshots here — send them as a separate message in the Telegram chat.';

  @override
  String get supportDescriptionSection => 'USER DESCRIPTION';

  @override
  String get splitAllowRealIp => 'Allow real IP for this rule';

  @override
  String get splitAllowRealIpOn =>
      'On: this is an exception, traffic leaves under your real address';

  @override
  String get splitAllowRealIpOff =>
      'Off: the rule goes through the VPN — protection outranks all rules';

  @override
  String get splitRealIpExposed => 'real IP';

  @override
  String get splitRealIpProtected => 'via VPN';

  @override
  String get vpnActiveBadge => 'VPN is active';

  @override
  String get splitCopyDomain => 'Copy address';

  @override
  String get splitCopyPath => 'Copy path';

  @override
  String get homeServerInfo => 'Server info';

  @override
  String get serverInfoVerifyInBrowser => 'Verify in browser';

  @override
  String get tunDnsForAll => 'Route all apps’ DNS through VPN';

  @override
  String get infoDnsForAll =>
      'Only affects “Selected only” mode. On: no DNS query reaches your ISP, but unselected apps resolve through the tunnel and get CDN addresses in the exit country — they connect directly to a distant server and feel slower. Off: unselected apps get nearby CDNs, but your ISP sees where every app goes, including protected ones. ⚠️ Applies after reconnecting.';

  @override
  String get homeSettingsNeedReconnect =>
      'Setting changed — reconnect to apply';

  @override
  String blockPageWindowTitle(String app) {
    return 'Blocked — $app';
  }

  @override
  String get blockPageHeading => 'Site blocked';

  @override
  String blockPageBody(String host, String app) {
    return '$host is blocked by a split tunnelling rule in $app.';
  }

  @override
  String get blockPageHint =>
      'You can change the rule: Settings → Split tunnelling → Sites.';

  @override
  String get blockPageNote =>
      'This page comes from the app itself, not from a network error. The site does not open because you added it to the block list.';

  @override
  String get settingsBlockPage => 'Block notice page';

  @override
  String get settingsBlockPageSub =>
      'Instead of a connection error, a page explains which rule closed the site. Works for http only: an https page cannot be replaced without installing our own root certificate into the system, and that certificate would let anyone read all of your encrypted traffic.';

  @override
  String get trayCloseFully => 'Close completely';

  @override
  String errorVpnConflictApp(String app) {
    return '$app appears to be in the way: it has its own VPN tunnel up. Two tunnels at once fight over the default route.';
  }

  @override
  String errorCloseApp(String app) {
    return 'Close $app';
  }

  @override
  String toastAppClosed(String app) {
    return '$app closed';
  }

  @override
  String toastAppCloseFailed(String app) {
    return 'Could not close $app — close it manually';
  }

  @override
  String get tunBlockQuic => 'Block QUIC (HTTP/3)';

  @override
  String get infoBlockQuic =>
      'Site rules match the NAME, and the app only sees the name in ordinary TLS. A browser that switched to HTTP/3 shows no name, so the domain rule silently does nothing. Blocking sends the browser back to a normal connection where the name is visible. Sites keep working: HTTP/3 is optional for them, though video may load a little slower. Turn this on if your site rules have no effect.';

  @override
  String get tunBlockEncryptedDns => 'Block encrypted DNS (DoH/DoT)';

  @override
  String get infoBlockEncryptedDns =>
      'Browsers and Windows can look up addresses over HTTPS, bypassing our interception. Then \"Direct\" and \"Block\" rules do not work at the DNS level at all. Blocking brings lookups back under our control. ⚠️ If your browser has a fixed encrypted-DNS provider, it will not fall back to plain DNS — it will simply stop opening sites; turn this off or remove the provider in the browser. The list of known providers is inherently incomplete: anyone can run their own.';

  @override
  String get autoUseSpeed => 'Take speed into account';

  @override
  String get infoAutoUseSpeed =>
      'After filtering by services and latency, the three best candidates are checked by download and the genuinely faster one goes first. Speed is compared with YOUR channel: a server that already delivers almost all of it is no longer judged by megabits — latency decides, because speed beyond your channel never reaches you. ⚠️ Uses subscription traffic: 5 MB for your channel plus 5 MB per candidate, about 20 MB per run.';

  @override
  String get autoSpeedOwn => 'Measuring your own speed…';

  @override
  String autoSpeedServer(String server, int index, int total) {
    return 'Measuring speed: $server ($index of $total)';
  }

  @override
  String autoSpeedShare(int percent) {
    return '$percent% of your channel';
  }

  @override
  String get conflictDialogTitle => 'Another VPN detected';

  @override
  String conflictDialogBody(String app) {
    return '$app appears to be running with its own tunnel up. Two tunnels at once fight over the default route, so the connection may fail or come up without network access.';
  }

  @override
  String get conflictCloseAndConnect => 'Close and connect';

  @override
  String get conflictConnectAnyway => 'Connect anyway';

  @override
  String get serviceChecksLegendBefore =>
      'Service availability checked without VPN';

  @override
  String get serviceChecksLegendAfter =>
      'Left — without VPN, right — through VPN';

  @override
  String get serviceChecksBefore => 'Without VPN';

  @override
  String get serviceChecksAfter => 'Through VPN';

  @override
  String get serviceChecksNoBaseline => 'Not checked without VPN';

  @override
  String autoSpeedValue(String value) {
    return '$value Mbps';
  }

  @override
  String get splitShowBlockPage => 'Show the block page';

  @override
  String get splitBlockPageNeedsVpn =>
      'The block page only works while the VPN is on';

  @override
  String get srvInfoNeedsConnection =>
      'Measuring through the server on this platform requires the VPN to be on';

  @override
  String get serviceYoutubeThrottleNote =>
      '⚠️ This check cannot see YouTube throttling: the provider answers normally but limits video bandwidth. Green here means “service reachable”, not “video plays”.';

  @override
  String get urlSchemeConnectServer =>
      'silentgate://connect?server=<server name>';

  @override
  String get urlDescConnectServer =>
      'Connect to a SPECIFIC server. The name is the one shown in the list and sent by the subscription, e.g. “Poland 1.5”. Flag emoji and case may be omitted. With no exact match, search kicks in: by country, address or protocol. Works with toggle too.';

  @override
  String get splitSelectAllFound => 'Select all found';

  @override
  String splitAddSelected(int count) {
    return 'Add ($count)';
  }

  @override
  String get splitQuicNote =>
      'While at least one site rule exists, the app disables HTTP/3 (QUIC) for all traffic. Otherwise the browser switches to HTTP/3, leaves no site name, and the rule silently fails — traffic bypasses it. Sites keep working: they fall back to regular TLS, just slightly slower.';

  @override
  String get splitNoRealIpBanner =>
      '“Never use my real IP” is on: “Direct” rules without the real-IP checkbox go through the VPN';

  @override
  String get settingsNoRealIpAffects =>
      'Affects “Direct” rules: without the “allow real IP” checkbox they go through the VPN';

  @override
  String get splitAppOverrideSites => 'Takes priority over site rules';

  @override
  String get splitAppOverrideSitesSub =>
      'All app traffic follows this rule even if a site rule says otherwise';

  @override
  String get settingsMyRulesOverridePanel =>
      'My rules take priority over panel rules';

  @override
  String get settingsMyRulesOverridePanelSub =>
      'The panel ships its own routing — usually “local sites bypass the VPN”. It applies after your rules, so a site you marked “Tunnel” may still exit directly under your real IP. On: tunnel means tunnel. Cost: local sites take the long way and get slower.';

  @override
  String get commonOpen => 'Open';

  @override
  String get tunRouteOnlySubnets => 'Tunnel ONLY these subnets';

  @override
  String get infoTunRouteOnlyCidrs =>
      'The only way on Windows to make part of your traffic genuinely independent of the VPN client.\n\nNormally the tunnel takes the default route, so ALL traffic on the machine enters it: a «Direct» rule is applied inside the core, which accepts the packet and re-sends it under its own name. That traffic lives exactly as long as the core does, and hangs together with it.\n\nWhen this list is not empty, the tunnel does not get the default route: it claims only the listed subnets, and the system sends everything else through the normal adapter — the client never sees it.\n\nThe price: the split is by address, while app and site rules match by name. A site whose address is not in the list is invisible to every rule. Leave empty for the usual behaviour.';

  @override
  String get tunRouteOnlyWarning =>
      'The tunnel claims only the listed subnets. App and site rules apply ONLY inside them: whatever does not enter the tunnel is never shown to the core, so it cannot be blocked or redirected.';

  @override
  String get tunAlsoSystemProxy => 'System proxy alongside the tunnel';

  @override
  String get infoTunAlsoSystemProxy =>
      'Mixed mode: the tunnel and the system proxy both run at once.\n\nApps that honour the system proxy (browsers, Telegram) take the short path straight to the local port, bypassing the tunnel\'s user-space stack, and hand the core a domain name instead of a bare address — site rules become more precise and stop depending on TLS sniffing.\n\nThey do NOT become independent of the client: they still go through the same process.';

  @override
  String get tunMixedModeWarning =>
      'A connection arriving through the system proxy has no owning process — to the core it is a local connection. APP rules therefore do not match for such programs. Site rules do work, and more precisely than usual.';

  @override
  String get tunWatchdog => 'Hung-core watchdog';

  @override
  String get infoTunWatchdog =>
      'How many seconds the tunnel core may stay silent before it is treated as hung and the tunnel is torn down.\n\nIf the core crashes, Windows cleans up by itself — the adapter, routes and firewall rules are removed and the network comes back. If the core hangs, nothing is removed: the adapter stays and swallows all traffic on the machine, including traffic marked «Direct». From the outside this is «the internet is gone», and it never recovers on its own.\n\nThe watchdog arms itself only after the core\'s first successful reply: otherwise it would kill the connection wherever the service port failed to open. 0 disables it. Minimum 10 seconds.';

  @override
  String get tunWatchdogOff => 'Off: a hung tunnel will not be detected';

  @override
  String tunWatchdogSubtitle(int seconds) {
    return 'Tear down the tunnel if the core is silent for over ${seconds}s';
  }

  @override
  String get tunDnsForAllWarning =>
      'Name resolution for the WHOLE machine will go through the tunnel. If the tunnel stalls, names stop resolving even for apps that go direct and do not need the VPN — which looks like a total loss of internet.';

  @override
  String get tunCidrInvalid =>
      'Needs an address with a prefix, e.g. 10.8.0.0/24';

  @override
  String get geoTitle => 'Routing geo databases';

  @override
  String get geoMissing =>
      'Not downloaded — country and category rules do not apply';

  @override
  String geoPresent(String size, String date) {
    return '$size, updated $date';
  }

  @override
  String get geoDownload => 'Download';

  @override
  String get geoUpdate => 'Update';

  @override
  String geoDownloading(String file) {
    return 'Downloading $file…';
  }

  @override
  String get geoDone => 'Geo databases updated';

  @override
  String geoFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get infoGeoAssets =>
      'The geoip.dat and geosite.dat files are lists of addresses by country and domains by category (for example «Russian sites», «government services», «VK»). The routing rules your subscription panel defines rely on them.\n\nThey are not bundled into the app: together they weigh about 30 MB and are not needed by everyone — a plain server does not use them at all.\n\nWhile the files are missing, such rules are stripped from the config and the traffic they used to send directly goes through the VPN instead. That is safe but slower, and local sites may refuse access from a foreign address. Your own per-site and per-app rules work regardless — they do not depend on these files.';

  @override
  String get supportBullet2Android =>
      '• After you tap, the report is collected into a single file and the system «Share» sheet opens — pick Telegram and it goes as one attachment. Describe the problem in the field above: without a description there is nothing to work from.';

  @override
  String get supportDoneTextAndroid =>
      'The report is collected into a single file. Choose where to send it in the system sheet — in Telegram it goes as an attachment, not as text.';

  @override
  String get exitsHeader => 'Exits';

  @override
  String get exitsHint =>
      'A \"Tunnel\" rule can be routed to a specific exit: one site through Germany, another through the USA. Without an exit the rule uses the main tunnel, as before.';

  @override
  String get exitsAdd => 'Add exit';

  @override
  String get exitsEmpty => 'No exits yet';

  @override
  String get exitsName => 'Name';

  @override
  String get exitsNameHint => 'Germany';

  @override
  String get exitsServers => 'Servers';

  @override
  String get exitsAutoSelect => 'Auto-select by latency';

  @override
  String get exitsAutoSelectSub =>
      'The core keeps traffic on a working server by itself. The cost: each server is probed every three minutes, which wakes the radio on a phone.';

  @override
  String get exitsAutoSelectNeedsTwo => 'At least two servers required';

  @override
  String get exitsDelete => 'Delete exit';

  @override
  String get exitsNoServers => 'No servers — import a subscription first';

  @override
  String get exitsSearch => 'Search server';

  @override
  String get exitsPickAtLeastOne => 'Select at least one server';

  @override
  String get exitsUnsupportedNote =>
      'Panel \"Auto\" profiles and hysteria2 cannot run as a separate exit: they are handled by the other core. Such servers are disabled in the list.';

  @override
  String get infoExits =>
      'An exit is the destination of a \"Tunnel\" rule.\n\nBy default an exit is a SINGLE server and costs nothing in the background: ordinary protocols hold no persistent connection. A group of several servers with auto-select is only needed where insurance against a node failure matters — it adds periodic probes, and on a phone those are radio wake-ups.\n\nAn exit only makes sense for the \"Tunnel\" action. \"Direct via Germany\" is a contradiction: a direct rule bypasses all exits.\n\nA site and its subdomain may go to DIFFERENT exits — the app raises the more specific rule above, otherwise the parent would swallow the subdomain.\n\nIMPORTANT: with the system proxy on Windows exits do not work at all — no routing rules are built in that mode. Tunnel mode is required.';

  @override
  String get ruleServer => 'Via server';

  @override
  String get ruleServerCurrent => 'Same as main';

  @override
  String ruleServerCurrentNamed(String server) {
    return 'Same as main ($server)';
  }

  @override
  String get routeMatchByName => 'Matched by file name';

  @override
  String get routeYourApps => 'Your apps';

  @override
  String get routeYourSites => 'Your sites';

  @override
  String get routeAppsAndSites => 'Apps and sites';

  @override
  String get notifCompactTitle => 'Compact notification';

  @override
  String get notifCompactSub =>
      'Off — subscription, server and speed, with buttons. On — the app and subscription in the title, server below, no speed and no buttons.';

  @override
  String get localProxyAuthTitle => 'Password for the local proxy';

  @override
  String get localProxyAuthInfo =>
      'The core\'s local port (127.0.0.1) is a full proxy into your VPN. Without a password any program on this device can connect to it and get your whole tunnel: the exit IP, your subscription quota and a way around your own split tunneling rules — including apps you marked “Block”. On Android this matters even more: there any installed app can see local ports.\n\nTurn it off only if you deliberately use this proxy from something that cannot authenticate.';

  @override
  String get localProxyAuthOff =>
      'Off: the local proxy is open to any program on the device';

  @override
  String get localProxyAuthSystemProxy =>
      'Not used in system proxy mode: Windows cannot pass a password to a local proxy. Applies in TUN mode.';

  @override
  String get localProxyAuthRandom =>
      'A new random password for every connection — not kept in the settings';

  @override
  String get localProxyAuthCustom =>
      'Your own username and password (kept in the settings file)';

  @override
  String get localProxyCredsTitle => 'Your own username and password';

  @override
  String get localProxyCredsUnset => 'Not set — a random password is used';

  @override
  String localProxyCredsUser(String user) {
    return 'Username: $user';
  }

  @override
  String get localProxyDialogTitle => 'Local proxy username and password';

  @override
  String get localProxyDialogBody =>
      'Needed only if you point a third-party program at our proxy (127.0.0.1) yourself. Leave the fields empty and the password will be random for every connection: it is not kept in the settings and never reaches the log or the support report. A password you set by hand stays in the settings file in plain text.';

  @override
  String get localProxyFieldUser => 'Username';

  @override
  String get localProxyFieldPassword => 'Password';

  @override
  String get localProxyFieldHint => 'empty — random';

  @override
  String get lockdownOnTitle => 'System-wide protection is on';

  @override
  String get lockdownOnSub =>
      'Traffic is blocked even if the app closes or the system kills it. This is the most reliable mode.';

  @override
  String get lockdownHalfTitle => 'Protection is only half on';

  @override
  String get lockdownHalfSub =>
      'Always-on VPN is set, but “Block connections without VPN” is off. While the app is alive traffic is protected; if the system kills it, traffic goes out in the clear.';

  @override
  String get lockdownOffTitle => 'System-wide protection is off';

  @override
  String get lockdownOffSub =>
      'Our kill switch holds traffic while the app is running. If the system kills it, traffic will bypass the VPN. Turn on “Always-on VPN” and “Block connections without VPN”.';

  @override
  String get lockdownUnknownTitle => 'System-wide protection: state unknown';

  @override
  String get lockdownUnknownSub =>
      'The state can be read on Android 10 and up, and only while the tunnel is up. Check manually: “Always-on VPN” and “Block connections without VPN”.';

  @override
  String get lockdownOpenFailed =>
      'Could not open the system VPN settings. Find them manually: Settings → Network & internet → VPN.';

  @override
  String get blockNoticeTitle => 'Notify about blocked sites';

  @override
  String get blockNoticeSub =>
      'When an app or browser reaches a site from the “Block” list, a notification with its name appears at the bottom. Tap it to open this screen.';

  @override
  String get siteInsecureScheme =>
      'The address is set as http:// — the connection is not encrypted and your ISP sees all of it. Remove “http://” so the browser uses https.';

  @override
  String get exitServerGone =>
      'The server for this rule is gone from the subscription — its traffic uses the main tunnel';

  @override
  String exitServerUnsupported(String name) {
    return '$name\n\nThis server cannot run as a separate exit: panel “Auto” profiles and some protocols are handled by Xray only, while exits are routed by sing-box. Traffic for this rule uses the main tunnel.';
  }

  @override
  String get noticeRulesAction => 'Rules';

  @override
  String get geoVerdictMissingTitle => 'Geo databases not downloaded';

  @override
  String get geoVerdictMissingSub =>
      'Subscription rules by country and category are off right now — this traffic goes through the VPN instead of direct.';

  @override
  String get geoVerdictUnusableTitle =>
      'The core could not open the geo databases';

  @override
  String get geoVerdictUnusableSub =>
      'The files are there, but the core did not read them. Re-downloading the databases usually helps.';

  @override
  String get pingPendingTooltip =>
      'TCP latency to the server. The channel check is still running — whether the server actually works is not known yet.';

  @override
  String get pingUnverifiedTooltip =>
      'TCP latency to the server. No check through the tunnel was made — only reachability is known.';

  @override
  String pingMeasuredAt(String time) {
    return 'Measured: $time';
  }

  @override
  String get pingChecking => 'checking';

  @override
  String autoTimer(String elapsed, String remaining) {
    return 'Elapsed $elapsed · about $remaining left';
  }

  @override
  String autoTimerNoEstimate(String elapsed) {
    return 'Elapsed $elapsed';
  }

  @override
  String autoSpeedRanking(String name) {
    return 'Measuring speed: $name';
  }

  @override
  String get autoWarnNoRealIp =>
      '“Never use the real IP” is on — all traffic goes through the VPN.';

  @override
  String get autoWarnAllVpn =>
      '“Everything through VPN” mode is selected — your rules are not in effect right now.';

  @override
  String get autoWarnPanelOverride =>
      '“My rules override the panel\'s rules” is on.';

  @override
  String get autoWarnProbesDirect =>
      'This does not affect the check itself: probes bypass the VPN under any settings. But in TUN mode they still go through the core process — if the core has hung, every result will be a false negative.';

  @override
  String get autoWarnTurnOff => 'Turn off';

  @override
  String get toastCollapse => 'Collapse';

  @override
  String get toastExpand => 'Expand';

  @override
  String get toastOpenAutoConfig => 'Open auto-tuning';

  @override
  String get splitAppAlreadyAdded => 'This app is already in the rules list';

  @override
  String logsFileLine(String name, String size, int lines) {
    return '$name — $size, $lines lines';
  }

  @override
  String logsReportsLine(int count, String size) {
    return 'Support reports: $count, $size';
  }

  @override
  String get logsRetentionTitle => 'Keep logs and reports';

  @override
  String get logsRetentionDay => '1 day';

  @override
  String get logsRetentionTwoWeeks => '2 weeks';

  @override
  String get logsRetentionMonth => '1 month';

  @override
  String get logsRetentionNever => 'Never delete';

  @override
  String get logsRetentionInfo =>
      'Logs and support reports are deleted once they are older than the selected period. The check runs when the app starts. “Never” keeps everything on disk — then watch the size yourself: a report embeds the logs in full and grows along with them.';

  @override
  String get logsCleanNow => 'Delete old ones now';

  @override
  String logsCleaned(int count, String size) {
    return 'Files deleted: $count, freed $size';
  }

  @override
  String get logsNothingToClean => 'Nothing to delete';

  @override
  String get speedTooltip => 'Download speed through this server';

  @override
  String get speedFromAutoConfig => 'Speed measured by auto-tuning';

  @override
  String get speedBlockedTooltip =>
      'Speed is not measured: the server failed the channel check (a request through it did not go through)';

  @override
  String get srvTileMeasureSpeed => 'Measure speed';

  @override
  String get speedRunTooltip => 'Measure server speed';

  @override
  String get speedConfirmTitle => 'Measure speed?';

  @override
  String speedConfirmBody(int count, String size, String total) {
    return 'Servers to check: $count. Each downloads a $size sample — about $total of your subscription traffic.';
  }

  @override
  String speedConfirmSkipped(int count) {
    return 'Already measured, skipping: $count.';
  }

  @override
  String get speedConfirmRun => 'Measure';

  @override
  String get speedNoTargets =>
      'Nothing to measure: speed is only checked for servers that passed the channel check. Ping the list first.';

  @override
  String get speedNotVerified =>
      'The server failed the channel check — speed through it is not measured';

  @override
  String speedProgress(int done, int total) {
    return 'Speed: $done of $total';
  }

  @override
  String get updateOnStartTitle => 'Refresh subscription on launch';

  @override
  String get updateOnStartSub =>
      'Fetch a fresh server list every time, not only on the timer';

  @override
  String get apiSectionSub =>
      'HTTP on 127.0.0.1 — control the client from scripts';
}
