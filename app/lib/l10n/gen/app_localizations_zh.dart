// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get settingsTitle => '设置';

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '关闭';

  @override
  String get commonCopy => '复制';

  @override
  String get commonCopied => '已复制';

  @override
  String get commonRefresh => '刷新';

  @override
  String get commonCheck => '检查';

  @override
  String get commonOk => '确定';

  @override
  String get commonDone => '完成';

  @override
  String get commonPathCopied => '路径已复制';

  @override
  String get languageTitle => '界面语言';

  @override
  String get languageSubtitle => '选择应用语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get sectionAppearance => '外观与行为';

  @override
  String get sectionCapture => '流量捕获';

  @override
  String get sectionReliability => '连接可靠性';

  @override
  String get sectionPing => '延迟测试';

  @override
  String get sectionIdentity => '面板标识';

  @override
  String get sectionNetwork => '网络';

  @override
  String get sectionAbout => '关于';

  @override
  String get sectionSupport => '支持';

  @override
  String get appearanceTheme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get closeToTrayTitle => '关闭时最小化到托盘';

  @override
  String get closeToTraySubtitle => '关闭按钮会将窗口隐藏到托盘；关闭此项则改为退出应用';

  @override
  String get autoUpdateSubTitle => '自动更新订阅';

  @override
  String get autoUpdateSubText => '定期刷新服务器列表';

  @override
  String get captureSystemProxy => '系统代理';

  @override
  String get captureSystemProxySub => '立即可用，无需管理员权限。';

  @override
  String get captureTun => 'TUN（全局隧道）';

  @override
  String get captureTunBadgeUac => '需要 UAC';

  @override
  String get captureTunSub => '捕获全部流量，包括 UDP 和忽略代理的应用。需要管理员权限。';

  @override
  String get tunProvider => 'TUN 提供程序';

  @override
  String get tunRoutingTitle => 'TUN 与路由';

  @override
  String tunRoutingSub(String stack, int mtu, String dns) {
    return '栈 $stack · MTU $mtu · DNS $dns';
  }

  @override
  String get splitTunnelTitle => '分应用代理';

  @override
  String splitRulesCount(int n, int apps, int sites) {
    return '$n 条规则（应用 $apps 个，站点 $sites 个）';
  }

  @override
  String get captureTunHint =>
      '选择 TUN 模式后才会显示 TUN、DNS 和分应用代理设置——在系统代理模式下它们不生效。';

  @override
  String get dnsShortVpn => '经由 VPN';

  @override
  String get dnsShortSystem => '系统';

  @override
  String get dnsShortCustom => '自定义';

  @override
  String get tunUacTitle => 'TUN 需要管理员权限';

  @override
  String get tunUacBody =>
      '可以只设置一次：应用会在 Windows 任务计划程序中创建一个最高权限的任务，之后隧道启动将不再弹出 UAC 提示。\n\n现在会出现一次管理员权限请求。应用本身仍以普通权限运行。';

  @override
  String get tunUacLater => '以后（每次询问）';

  @override
  String get tunUacSetup => '设置';

  @override
  String get tunUacDone => '完成：TUN 启动将不再弹出 UAC 提示';

  @override
  String get tunUacFail => '无法创建任务——连接时将请求 UAC';

  @override
  String get autoReconnectTitle => '自动重连';

  @override
  String get autoReconnectSub => '掉线和网络切换时恢复连接';

  @override
  String get killSwitchTitle => '断网保护（Kill switch）';

  @override
  String get killSwitchSubTun => '重连期间不让流量绕过 VPN';

  @override
  String get killSwitchSubProxy => '在“系统代理”模式下仅保护支持代理的应用。完全保护——只有 TUN';

  @override
  String get killSwitchSubOff => '需要先启用自动重连';

  @override
  String get networkRecoverTitle => '恢复网络';

  @override
  String get networkRecoverSub => '如果 VPN 后无法上网。需要管理员权限';

  @override
  String get networkRecoverConfirmTitle => '恢复网络？';

  @override
  String get networkRecoverConfirmBody =>
      '将重置 winsock、IP 栈、DNS 和系统代理。需要管理员权限（UAC）。winsock/IP 重置在重启后生效。';

  @override
  String get networkRecoverConfirmOk => '恢复';

  @override
  String get interferenceTitle => '检查干扰（其他 VPN）';

  @override
  String get interferenceDialogTitle => '网络干扰';

  @override
  String get interferenceNoneFound => '未检测到其他 VPN 或干扰。';

  @override
  String get interferenceIgnore => '忽略';

  @override
  String get identityUserAgent => 'User-Agent';

  @override
  String identityUaAutoNote(String version) {
    return '随应用版本自动更新。同时发送：X-HWID、X-Device-OS、X-Ver-OS、X-App-Version（$version）。';
  }

  @override
  String get urlSchemesTitle => 'URL 方案';

  @override
  String get urlSchemesSub => '通过链接导入和控制 VPN（connect / toggle / update）';

  @override
  String get panelOwnerTitle => '面向面板所有者';

  @override
  String get panelOwnerBody =>
      '普通用户无需此项——可以跳过。\n\n为了让应用以正确的 JSON 格式（XRAY_JSON）接收您的订阅，请将以下代码块添加到 Remnawave 面板的 Response Rules 中——它会匹配我们的 User-Agent：';

  @override
  String get panelOwnerCopy => '复制代码块';

  @override
  String get aboutVersion => 'SilentGate 版本';

  @override
  String get aboutXrayCore => 'Xray 核心';

  @override
  String get aboutHwid => '设备 HWID';

  @override
  String get aboutThirdPartyTitle => '第三方组件与许可';

  @override
  String get aboutThirdPartySub =>
      'Xray-core（MPL-2.0）、sing-box（GPL-3.0）、Wintun——作为独立进程运行';

  @override
  String get logsTitle => '日志';

  @override
  String get logsSub => '应用和 TUN（sing-box）：订阅导入、延迟测试、错误';

  @override
  String get thirdPartyTitle => '第三方组件';

  @override
  String get thirdPartyBody =>
      'SilentGate 随附第三方可执行文件。它们作为独立进程运行，并未嵌入应用中。\n\n• Xray-core (xray.exe) — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• sing-box (sing-box.exe) — GPL-3.0-or-later\n  TUN 隧道及 Hysteria2 的代理核心\n  https://github.com/SagerNet/sing-box\n\n• Wintun (wintun.dll) — Wintun 许可\n  https://www.wintun.net/\n\n• geoip.dat / geosite.dat — 路由数据，CC-BY-SA-4.0\n\n完整的许可文本位于应用旁边的“licenses”文件夹中。';

  @override
  String get supportSectionNote =>
      '点击“联系支持”——将打开一个窗口，您可以自行生成日志文件（版本、系统、设置、app.log + singbox.log 尾部；不含密码或订阅令牌，URL 已隐藏）。之后会出现将其发送到 Telegram 支持的按钮。';

  @override
  String get supportButtonTitle => '联系支持';

  @override
  String get supportButtonSub => '生成日志并打开支持聊天';

  @override
  String get supportDialogTitle => '支持';

  @override
  String get supportDialogTitleDone => '日志已就绪——发送给谁';

  @override
  String get supportWhatWillHappen => '将会发生什么：';

  @override
  String get supportBullet1 =>
      '• 一个文件将汇集版本、系统、设置和日志（app.log + singbox.log 尾部）。其中不含密码或订阅令牌，订阅 URL 已隐藏。';

  @override
  String get supportBullet2 =>
      '• 点击后，会先打开包含该文件的文件夹，然后打开文件本身。请在顶部描述问题并保存——之后会出现将其发送到支持的按钮。';

  @override
  String supportError(String error) {
    return '无法生成报告：$error';
  }

  @override
  String get supportDoneText =>
      '报告已生成并打开（先文件夹，后文件）。请在顶部描述问题，保存文件并发送给支持——应用会帮助打开 Telegram。';

  @override
  String get supportWhoTo => '发送给谁：';

  @override
  String get supportContact => '联系支持';

  @override
  String supportContactNamed(String name) {
    return '联系支持（$name）';
  }

  @override
  String get supportDevServiceName => '客户端开发者';

  @override
  String get supportShowOnPc => '在电脑上显示';

  @override
  String get supportCopyPath => '复制路径';

  @override
  String get supportGenerating => '生成中…';

  @override
  String get supportGenerateButton => '生成支持日志';

  @override
  String get pingTwoPhaseTitle => '验证是否可用（经由隧道）';

  @override
  String get pingTwoPhaseSubOn => 'TCP 之后——通过服务器发起请求：过滤掉无法工作的（Reality 等）';

  @override
  String get pingTwoPhaseSubOff => '仅使用下方选定的单一方法';

  @override
  String get pingMethodCheck => '验证方法：';

  @override
  String get pingMethodPing => '延迟测试方法：';

  @override
  String get speedTestProbe => '测速探测：';

  @override
  String get speedTestFull => '20 MB（更精确）';

  @override
  String get speedTestLight => '5 MB（更省流量）';

  @override
  String get testUrlLabel => '测试 URL（经由代理）';

  @override
  String get appUpdateServerUnavailable => '更新服务器不可用';

  @override
  String appUpdateAvailable(String version) {
    return '有可用版本 $version';
  }

  @override
  String get appUpdateLatest => '您已是最新版本';

  @override
  String get appUpdateDownload => '下载';

  @override
  String get appUpdateCheckTitle => '启动时检查更新';

  @override
  String get appUpdateManual => '下载与安装——手动进行';

  @override
  String get appUpdateEndpointLabel => '版本端点';

  @override
  String get urlSchemeSilentgateTitle => 'silentgate:// 链接';

  @override
  String get urlSchemeSilentgateSub => '通过链接导入和控制 VPN。默认启用';

  @override
  String get urlSchemeDisableTitle => '禁用 silentgate:// 链接？';

  @override
  String get urlSchemeDisableBody =>
      '通过链接导入以及控制方案（connect / disconnect / toggle / update）将停止工作。如不确定，请保持启用。';

  @override
  String get urlSchemeDisableOk => '禁用';

  @override
  String get urlSchemeServerTitle => '打开服务器链接';

  @override
  String get urlSchemeServerSub => '接管来自其他客户端的 vless:// 等链接';

  @override
  String get urlSchemeServerConfirmTitle => '接管服务器链接？';

  @override
  String urlSchemeServerConfirmBody(String schemes) {
    return '$schemes\n\n这些链接通常绑定到其他 VPN 客户端（Happ、v2rayTun）。SilentGate 将接管它们。';
  }

  @override
  String get urlSchemeServerConfirmOk => '接管';

  @override
  String get urlSchemeAutoConnect => '导入后连接';

  @override
  String get autoTitle => '自动配置';

  @override
  String get autoClearResults => '清除结果';

  @override
  String autoFoundWorking(Object count) {
    return '找到可用：$count';
  }

  @override
  String get autoPinnedTop => ' — 已置顶到列表';

  @override
  String get autoSearchContinues => ' （搜索继续中…）';

  @override
  String get autoCheckServices => '检查服务';

  @override
  String get autoPinFoundOnTop => '将找到的服务器置顶到列表';

  @override
  String get autoTryFragment => '尝试绕过（fragment）';

  @override
  String get autoNoSubscriptionPasteKey => '没有订阅。粘贴单个密钥——我们将为您找出可用设置：';

  @override
  String get autoTuneByKey => '按密钥配置';

  @override
  String autoTesting(Object index, Object total) {
    return '正在测试 $index/$total：';
  }

  @override
  String autoVariant(Object label) {
    return '变体：$label';
  }

  @override
  String autoServicesPassed(Object ok, Object total) {
    return '$total 个服务中通过 $ok 个';
  }

  @override
  String get autoConnect => '连接';

  @override
  String get autoStopSearch => '停止搜索';

  @override
  String get autoDoneRefreshPing => '完成——刷新已找到项的延迟';

  @override
  String autoFoundPinnedRefreshing(Object count) {
    return '找到 $count 个，已置顶。正在刷新延迟…';
  }

  @override
  String autoServersForTuning(Object selected, Object total) {
    return '待配置的服务器（$selected/$total）';
  }

  @override
  String get autoSelectAll => '全选';

  @override
  String get autoDeselectAll => '清除';

  @override
  String get autoTuneSelected => '配置所选';

  @override
  String autoTuned(Object label) {
    return '已配置：$label';
  }

  @override
  String get infoDialogTitle => '说明';

  @override
  String get infoCopied => '说明已复制';

  @override
  String get commonGotIt => '知道了';

  @override
  String get enumSplitAll => '全部——经由 VPN';

  @override
  String get enumSplitOnly => '仅所选——经由 VPN';

  @override
  String get enumSplitExcept => '所选——绕过 VPN';

  @override
  String get enumActionTunnel => '隧道';

  @override
  String get enumActionDirect => '直连';

  @override
  String get enumActionBlock => '阻止';

  @override
  String homeUpdateAvailable(Object version) {
    return '有可用版本 $version';
  }

  @override
  String get homeDownload => '下载';

  @override
  String homeSubscriptionUpdated(Object summary) {
    return '订阅已更新：$summary';
  }

  @override
  String get homeReconnect => '重新连接';

  @override
  String homePingProgress(Object done, Object total) {
    return '正在测试服务器延迟：$total 中的 $done';
  }

  @override
  String get homeAutoConfigStarting => '自动配置正在启动…';

  @override
  String homeAutoConfigProgress(Object current, Object name, Object total) {
    return '自动配置：$total 中的 $current — $name';
  }

  @override
  String get homeImport => '导入';

  @override
  String get homeSettings => '设置';

  @override
  String get homeAutoBest => '自动（最佳服务器）';

  @override
  String get homeAutoConfig => '自动配置';

  @override
  String homeServersCount(Object count) {
    return '服务器（$count）';
  }

  @override
  String homeFoundCount(Object found, Object total) {
    return '已找到 $total 中的 $found';
  }

  @override
  String get homePingServers => '测试服务器延迟';

  @override
  String get homePingFound => '测试已找到项延迟';

  @override
  String get homeNothingFound => '未找到任何内容';

  @override
  String get homeOnboardingTitle => '从导入订阅开始';

  @override
  String get homeOnboardingSubtitle => '粘贴 Remnawave 链接或单个密钥';

  @override
  String get homeImportSubscription => '导入订阅';

  @override
  String homeSessionTraffic(Object down, Object up) {
    return '本次会话：↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'GB';

  @override
  String subBarUsage(Object total, Object used) {
    return '$total 中的 $used';
  }

  @override
  String get subBarSubscription => '订阅';

  @override
  String get subBarRefreshing => '刷新中…';

  @override
  String get subBarRefreshSubscription => '刷新订阅';

  @override
  String get subBarSupport => '支持';

  @override
  String get subBarRefresh => '刷新';

  @override
  String get subBarAddSubscription => '添加订阅';

  @override
  String get subBarCopyLink => '复制链接';

  @override
  String get subBarDeleteSubscription => '删除订阅';

  @override
  String get subBarLinkCopied => '链接已复制';

  @override
  String get subBarDeleteConfirmTitle => '删除订阅？';

  @override
  String get subBarDeleteConfirmBody => '该订阅中的服务器将从列表中移除。';

  @override
  String subBarDeletePinned(Object count) {
    return '同时删除已置顶的（$count）及其修改';
  }

  @override
  String get subBarDeletePinnedHint => '否则它们会保留在列表中并在删除后保留';

  @override
  String get subBarCancel => '取消';

  @override
  String get subBarDelete => '删除';

  @override
  String get subBarSubscriptionDeleted => '订阅已删除';

  @override
  String subBarSubscriptionUpdated(Object summary) {
    return '订阅已更新：$summary';
  }

  @override
  String get subBarMore => '详情';

  @override
  String subBarAdded(Object count) {
    return '已添加（$count）';
  }

  @override
  String subBarRemoved(Object count) {
    return '已移除（$count）';
  }

  @override
  String subBarAutoUpdate(Object hours) {
    return '· 自动更新 $hours 小时';
  }

  @override
  String subBarValidPerpetual(Object auto) {
    return '有效期：无限期  $auto';
  }

  @override
  String get subBarExpired => '订阅已过期：';

  @override
  String get subBarValidUntil => '有效期至：';

  @override
  String get infoCaptureMode =>
      '如何拦截流量。“系统代理”会在系统中设置一个本地代理（无需管理员权限；可捕获浏览器和大多数应用）。“TUN”是一个虚拟网络适配器，可捕获全部流量（包括 UDP 和忽略代理的应用），但需要管理员权限。';

  @override
  String get infoSystemProxy =>
      '系统设置中的本地 HTTP 代理（WinINET 注册表）。无需管理员权限。不拦截 UDP 或忽略系统代理的应用。';

  @override
  String get infoTunMode =>
      '通过 wintun 虚拟适配器 + sing-box 建立的全局隧道。捕获包括 UDP 在内的全部流量。启用时请求管理员权限（UAC）。';

  @override
  String get infoTunProvider =>
      '虚拟网络适配器的驱动。在 Windows 上使用 wintun（随核心一同分发）。无需其他驱动。';

  @override
  String get infoTunStack =>
      'TUN 网络栈（sing-box）。\n\n“auto”——自动选择：如果隧道未能建立，应用会自行依次尝试 system → gvisor → mixed，然后降低 MTU（1400、1280）。成功的组合会被记住，下次优先尝试。选择过程会显示在状态和日志中。\n\n显式选择将禁用自动选择：system——操作系统栈，速度最快，但对杀毒软件更敏感；gvisor——用户态，较慢，兼容性最强；mixed——TCP 走 system，UDP 走 gvisor。';

  @override
  String get infoTunMtu =>
      'TUN 适配器中的最大数据包大小。默认 1500；如果出现掉线，请降低（1400、1280）——数值过小会降低速度。\n\n使用“auto”栈时，这只是起始值：如果隧道未能建立，应用会自行尝试更小的 MTU。';

  @override
  String get infoTunStrictRoute =>
      'sing-box 中的严格路由。在 Windows 上可修复两个常见问题：DNS 泄漏（系统默认会同时向所有适配器发送查询）和“网络不可达”错误。仅在它导致 VirtualBox/Hyper-V 故障时才关闭。';

  @override
  String get infoTunIpv6 =>
      '将 IPv6 路由进隧道。如果在运营商已启用 IPv6 的情况下关闭它，部分流量将绕过 VPN（泄漏您的真实地址）或卡住。仅在您遇到 IPv6 网络问题时才关闭。';

  @override
  String get infoTunEndpointIndependentNat =>
      'UDP 的 NAT 模式。游戏、语音聊天和 WebRTC 需要它——否则连接可能无法建立。仅为节省内存才禁用。';

  @override
  String get infoTunBypassLan =>
      '本地网络（私有地址 192.168.*、10.*、路由器、打印机、NAS）绕过 VPN。通常应保持开启，否则会失去对网络中设备的访问。';

  @override
  String get infoTunExcludeCidrs =>
      '始终绕过 VPN 的额外子网（CIDR 格式，例如 10.8.0.0/24）。适用于企业网络和其他 VPN。';

  @override
  String get infoTunPrivilege =>
      'TUN 需要管理员权限。我们会一次性在 Windows 任务计划程序中创建一个最高权限的任务——之后每次连接时隧道启动将不再弹出 UAC 提示。该任务属于您，可通过下方按钮删除，或在卸载程序时删除。';

  @override
  String get infoAppUpdate =>
      '每次启动时，应用会向您的服务器询问是否有更新版本，并显示带有“下载”按钮的通知。\n\n应用不会自行下载或运行任何内容：安装程序未使用证书签名，自动运行下载的 exe 会触发 SmartScreen，并在杀毒软件看来像恶意行为。更新由您自行安装。\n\n如果服务器不可用，应用只会保持静默并向日志写入一条记录。响应格式和服务器配置详见 docs/APP_UPDATE.md。';

  @override
  String get infoSpeedTest =>
      '测速时下载的数据量（右键点击服务器 →“服务器信息”→“测量速度”）。\n\n20 MB——主要模式：在高速链路（100+ Mbps）上，过短的探测来不及加速，会低估结果。\n5 MB——省流量模式：流量消耗明显更少，便于批量测试多个服务器。\n\n测量仅手动进行，会消耗您订阅的流量。速度会测量两次：直连和经由所选服务器，以便您准确看到 VPN 上损失了多少。';

  @override
  String get infoAutoReconnect =>
      '如果核心崩溃、服务器掉线或网络切换（Wi-Fi ↔ 有线、从睡眠唤醒、新 IP），应用会自行重新建立连接。重试间隔逐渐增大：0.8 秒 → 3 秒 → 8 秒 → 20 秒，最多 8 次，之后显示错误。用按钮断开始终会取消恢复。\n\n网络切换通过其他适配器的真实地址检测：不计入自身隧道和服务地址（link-local），只有连续两次轮询保持一致才视为切换，并且连接后的前 15 秒会忽略该信号。没有这些防护，建立隧道本身就会被当作“网络切换”并导致无休止的重连。';

  @override
  String get infoKillSwitch =>
      '在连接恢复期间，不让流量绕过 VPN 泄漏出去。重试之间不会释放捕获：在 TUN 模式下适配器保持启用，在“系统代理”模式下代理保持配置——应用得到的是连接错误，而不是未加密地访问互联网。\n\n关于限制，如实说明：在“系统代理”模式下，这只保护尊重系统代理的程序（浏览器和大多数应用）。忽略代理的程序以及 UDP 会直连——完全的密封性只有 TUN 模式才能提供。需要启用自动重连。';

  @override
  String get infoUserAgent =>
      '应用如何向面板标识自己（User-Agent 头）。它始终发送“SilentGate/版本 (Windows)”。\n\n Remnawave 面板依据此名称选择订阅格式。需要 XRAY_JSON——它提供现成的服务器配置；而从 base64 链接列表中，部分设置只能近似还原，自动选择（burstObservatory）的效果会更差。\n\n在面板中配置：Templates → Response Rules → 一条条件为 user-agent CONTAINS SilentGate、响应类型为 XRAY_JSON 的规则（将其放在 Fallback Base64 规则之上）。\n\n覆盖字段仅作为临时变通方法——如果面板尚不识别该应用，您可以伪装成它已识别的客户端。';

  @override
  String get infoDnsMode =>
      '在 TUN 模式下由谁解析域名。“经由 VPN”（推荐）——查询经 TCP 进入隧道，运营商看不到您打开哪些网站。“系统”——与 Windows 一致：可能发生 DNS 泄漏，而如果服务器不放行 UDP，可能会完全断网。“自定义”——您指定的服务器，经由隧道。';

  @override
  String get infoDnsCustomServer =>
      '“自定义”模式下 DNS 服务器的地址（例如 9.9.9.9 或 8.8.8.8）。对它的查询经 TCP 通过隧道。';

  @override
  String get infoDnsHijack =>
      '在隧道内拦截 DNS 查询（UDP 53 端口）。否则查询会绕过规则：可能发生泄漏，且分应用代理的域名规则会不够精确。';

  @override
  String get infoDnsStrategy =>
      '请求哪些地址：prefer_ipv4（推荐）——优先 IPv4，ipv4_only——仅 IPv4（修复 IPv6 异常导致的问题），prefer_ipv6/ipv6_only——用于 IPv6 网络。';

  @override
  String get infoSingboxLogLevel =>
      'sing-box 日志的详细程度（%APPDATA%\\SilentGate\\singbox.log）。warn——常规模式。info/debug——当隧道无法工作时：日志会显示确切原因。debug 会明显增大文件体积。';

  @override
  String get infoSplitMode =>
      '基准——一切未手动设定动作的流量归往何处，以及为新条目分配何种动作。“全部——经由 VPN”：默认所有流量进入隧道。“仅所选——经由 VPN”：默认直连，仅标记为“隧道”的进入隧道。“所选——绕过 VPN”：相反，全部进入隧道，而标记为“直连”的走直连。';

  @override
  String get infoSplitApps =>
      '点击某个应用——将打开一个窗口，可在其中选择动作（隧道——经由 VPN，直连——绕过 VPN，阻止——无网络）和匹配方式：按 exe 名称（可靠）或按完整路径。可从运行中的应用选取或指定 .exe。';

  @override
  String get infoSplitDomains =>
      '域名（后缀）。例如 youtube.com 也涵盖 www.youtube.com。依据 TLS 连接中的名称（SNI）工作。';

  @override
  String get infoVerifyViaProxy =>
      '先通过代理检查可用性（服务器确实返回 204），只有服务器响应后，才用所选方法（TCP/ICMP）单独测量延迟。';

  @override
  String get infoProxyGet =>
      '通过隧道向测试 URL 发起 GET 请求。检查服务器是否确实放行流量并返回 204。最诚实的可用性测试；略慢。';

  @override
  String get infoProxyHead => '与 GET 类似，但只请求头部——更快、流量更少。部分服务器/CDN 可能不支持 HEAD。';

  @override
  String get infoTcp =>
      '到服务器地址的 TCP 握手时间。快速而准确的延迟指标，但不能证明隧道可用：即使代理被阻止，Reality 服务器也会响应 TCP。推荐用于延迟。';

  @override
  String get infoIcmp =>
      '系统 ping。对 Reality/CDN 通常无用：ICMP 可能被阻止，或它测量的是最近的 CDN 节点。保留用于网络诊断。';

  @override
  String get infoTestUrl =>
      '通过代理检查可用性所用的 URL。默认 https://www.gstatic.com/generate_204——它返回空的 204 响应，方便又快速。';

  @override
  String get infoAutoConfig =>
      '遍历服务器和绕过变体（fragment、fingerprint），并汇集出所选服务可用的那些。它不会在第一个就停止——由您从找到的项中选择。检查通过代理进行，其间不启用 VPN。';

  @override
  String get infoAutoConfigServices =>
      '为使服务器被视为合适，必须能正常工作的服务。该检查能抵御运营商的占位页面（校验的是响应特征，而不仅仅是“200 OK”）。';

  @override
  String get infoAutoPinFound =>
      '找到的可用组合（服务器 + 绕过变体）会立即置顶到公共服务器列表，以便无需返回此处即可使用。如果您不希望自动配置改变列表顺序，请关闭它——结果仍会显示在本界面上。';

  @override
  String get infoTryFragment =>
      '当“裸”服务器不可用时，尝试对 TLS ClientHello 进行分片的变体（绕过 DPI）。稍慢，但能在受限服务器上找到可用组合。';

  @override
  String get infoAutoStrategy =>
      '“第一个可用”——遍历全部并连接到找到的任意一个（由您选择）。“预算内最佳”——在时限内搜索并选出最快的。';

  @override
  String get infoScheme =>
      '在系统中注册 silentgate:// 协议（针对当前用户，无需管理员权限）。之后，在浏览器中点击链接 silentgate://import?url=…（导入）或 silentgate://connect / toggle（控制）会打开应用并执行操作。默认启用。';

  @override
  String get infoAutoConnectAfterImport => '通过链接成功导入订阅后，立即连接到第一个服务器。';

  @override
  String get infoNetworkRecover =>
      '如果在启用 VPN 的电脑崩溃/关机后无法上网，则重置网络参数：winsock、IP 栈、DNS 缓存、系统代理。需要管理员权限；winsock 和 IP 栈的重置在重启后生效。';

  @override
  String get infoInterference =>
      '检查其他 VPN 和网络干扰（外来的 TUN 适配器、VPN 进程、zapret/GoodbyeDPI），它们可能与 SilentGate 冲突。您可以关闭它们或忽略。';

  @override
  String get pingInfoProxyGet =>
      '通过隧道向测试 URL 发起 GET 请求。检查服务器是否确实放行流量并返回 204。最诚实的可用性测试；由于要完整下载响应而略慢。推荐用于可用性检查。';

  @override
  String get pingInfoProxyHead =>
      '与 GET 类似，但只请求头部——流量更少、更快。检查隧道的可用性；部分服务器/CDN 可能不支持 HEAD。';

  @override
  String get pingInfoTcp =>
      '测量到服务器地址的 TCP 握手时间。快速而准确的端点延迟指标，但不能证明隧道可用：即使代理被阻止，Reality 服务器也会响应 TCP。推荐用于延迟。';

  @override
  String get pingInfoIcmp =>
      '系统 ping（回显请求）。对 Reality/CDN 通常无用：ICMP 可能被阻止，或它测量的是最近的 CDN 节点而非服务器。保留用于网络诊断。';

  @override
  String get pingInfoTwoPhase =>
      'TCP 检查之后，已响应的服务器会额外通过隧道发起请求（对测试 URL 的 GET/HEAD）进行检查。这样可过滤掉那些保持端口开放但不代理流量的服务器。延迟仍按 TCP 显示。';

  @override
  String get pingInfoTunStage =>
      '全局隧道（TUN）是下一阶段。当前使用的是“系统代理”模式。在 TUN 模式下，全部流量（包括 UDP 和忽略代理的应用）将通过 wintun 虚拟适配器 + tun2socks。需要管理员权限。';

  @override
  String get pingInfoTunStack =>
      'TUN 网络栈（sing-box）。auto——交由核心决定（当前为 mixed）。system——操作系统栈：速度最快，但对权限/杀毒软件更敏感。gvisor——用户态栈：较慢，但兼容性最强。mixed——TCP 走 system，UDP 走 gvisor（折中）。如果 TUN 无法连接或频繁断线——试试 gvisor。';

  @override
  String get pingInfoAutoConfig =>
      '启用后，应用会自行遍历服务器和绕过变体（fragment、fingerprint），并连接到所选服务可用的第一个（通过代理检查，遍历期间不启用 VPN）。';

  @override
  String get logsTabApp => '应用';

  @override
  String get logsTabTun => 'TUN (sing-box)';

  @override
  String get logsRefresh => '刷新';

  @override
  String get logsCopy => '复制';

  @override
  String get logsClearApp => '清除应用日志';

  @override
  String get logsCopied => '日志已复制';

  @override
  String get logsLoading => '加载中…';

  @override
  String get logsEmpty => '暂时为空。';

  @override
  String get logsTunEmpty => '为空——本系统上 TUN 尚未启动过。';

  @override
  String get importScrDone => '已导入';

  @override
  String get importScrWelcome => '欢迎使用 SilentGate';

  @override
  String get importScrTitle => '导入订阅';

  @override
  String get importScrSubscriptionFallback => '订阅';

  @override
  String get importScrHint =>
      '粘贴订阅链接（Remnawave）、silentgate:// 深层链接，或单个 vless:// / vmess:// / trojan:// / ss:// / hysteria2:// 链接';

  @override
  String get importScrLoading => '加载中…';

  @override
  String get importScrPasteImport => '从剪贴板导入';

  @override
  String get importScrImportField => '从字段导入';

  @override
  String get serversTitle => '服务器';

  @override
  String serversFound(Object found, Object total) {
    return '服务器——已找到 $total 中的 $found';
  }

  @override
  String get serversRefresh => '刷新订阅';

  @override
  String get serversPinging => '延迟测试中…';

  @override
  String get serversPingAll => '全部测试延迟';

  @override
  String get serversPingFound => '测试已找到项延迟';

  @override
  String get serversEmpty => '服务器列表为空。请导入订阅。';

  @override
  String get serversNothingFound => '未找到任何内容';

  @override
  String get toastCopied => '已复制';

  @override
  String get toastHide => '隐藏';

  @override
  String get srvInfoTitle => '服务器信息';

  @override
  String srvInfoProbeFailed(Object error) {
    return '无法建立测试连接：$error';
  }

  @override
  String get srvInfoServerAddressFailed => '无法确定服务器地址';

  @override
  String get srvInfoSectionExit => '出口位置';

  @override
  String get srvInfoExitHint => '根据服务器地址确定——为此不会建立隧道。';

  @override
  String get srvInfoAddressLocation => '服务器地址与位置';

  @override
  String get srvInfoCheckAgain => '重新检查';

  @override
  String get srvInfoSectionSpeed => '速度';

  @override
  String srvInfoSpeedHint(Object size) {
    return '探测会下载 $size 并消耗订阅流量。大小可在设置中更改。';
  }

  @override
  String get srvInfoViaServer => '经由服务器';

  @override
  String get srvInfoWithoutVpn => '不经 VPN';

  @override
  String get srvInfoMeasuring => '测量中…';

  @override
  String get srvInfoMeasureSpeed => '测量速度';

  @override
  String get srvInfoSectionParams => '连接参数';

  @override
  String get srvInfoParamAddress => '地址';

  @override
  String get srvInfoParamProtocol => '协议';

  @override
  String get srvInfoParamTransport => '传输';

  @override
  String get srvInfoParamTlsFingerprint => 'TLS 指纹';

  @override
  String get srvInfoParamType => '类型';

  @override
  String get srvInfoPanelAutoProfile => '面板的自动选择配置';

  @override
  String get srvInfoCouldNotDetermine => '无法确定';

  @override
  String get srvInfoCopy => '复制';

  @override
  String get editorJsonTitle => 'JSON 配置';

  @override
  String get editorCopy => '复制';

  @override
  String get editorClose => '关闭';

  @override
  String get editorTitle => '编辑服务器';

  @override
  String get editorFieldName => '名称';

  @override
  String get editorFieldAddress => '地址';

  @override
  String get editorFieldPort => '端口';

  @override
  String get editorFieldUuidPassword => 'UUID / 密码';

  @override
  String get editorFieldObfs => '混淆（通常为 salamander）';

  @override
  String get editorFieldObfsPassword => '混淆密码';

  @override
  String get editorFieldPortHopping => '端口跳跃（例如 20000-21000）';

  @override
  String get editorAllowSelfSigned => '允许自签名证书';

  @override
  String get editorAllowSelfSignedSub => '仅在服务器如此配置时才需要';

  @override
  String get editorTransport => '传输';

  @override
  String get editorSecurity => '安全';

  @override
  String get editorNone => '（无）';

  @override
  String get editorCancel => '取消';

  @override
  String get editorSave => '保存';

  @override
  String jsonProfileServers(Object burst, Object count) {
    return '$count 个服务器$burst';
  }

  @override
  String get jsonCompositionUnknown => '构成未知';

  @override
  String get jsonYourSavedOverride => '您保存的 JSON（覆盖）';

  @override
  String jsonPanelProfileApplied(Object summary) {
    return '面板的自动选择配置：$summary — 完整应用';
  }

  @override
  String get jsonPanelConfig => '面板的配置（XRAY_JSON）';

  @override
  String get jsonBuiltFromShareLink =>
      '根据分享链接构建——面板未发送 JSON。请刷新订阅；若无效，请检查面板中的 Response Rules 规则。';

  @override
  String get jsonInvalidJson => 'JSON 无效';

  @override
  String get jsonSaved => '已保存';

  @override
  String get jsonTitle => 'JSON 配置';

  @override
  String get jsonFieldEditor => '字段编辑器';

  @override
  String get jsonCopy => '复制';

  @override
  String get jsonClose => '关闭';

  @override
  String get jsonSave => '保存';

  @override
  String get srvTileEdit => '编辑';

  @override
  String get srvTileNotice => '通知';

  @override
  String get srvTileRefresh => '刷新';

  @override
  String get srvTileSubscriptionUpdated => '订阅已更新';

  @override
  String get srvTileCopy => '复制';

  @override
  String get srvTileInfo => '服务器信息';

  @override
  String get srvTilePing => '测试延迟';

  @override
  String get srvTileUnpin => '取消置顶';

  @override
  String get srvTilePin => '置顶';

  @override
  String get srvTileJsonConfig => 'JSON 配置';

  @override
  String get srvTileSmart => '智能参数配置';

  @override
  String get srvTileDelete => '删除';

  @override
  String get srvTileServerDeleted => '服务器已删除';

  @override
  String get srvTileSaved => '已保存';

  @override
  String get pingNa => 'n/a';

  @override
  String get pingNaTooltip => '无 TCP 响应——服务器不可用（已失效）';

  @override
  String get pingTimeout => '超时';

  @override
  String get pingTimeoutTooltip => 'TCP 探测未在超时内完成——服务器不可用';

  @override
  String pingMs(Object ms) {
    return '$ms 毫秒';
  }

  @override
  String get pingNoProxy => '无代理';

  @override
  String get pingNoProxyTooltip => 'TCP 有响应（已显示延迟），但隧道检查（GET/HEAD）失败——流量未通过';

  @override
  String get pingOk => 'ok';

  @override
  String get pingOkTooltip => '到服务器的 TCP 延迟。服务器可用：TCP 有响应且通过了隧道检查（GET/HEAD）';

  @override
  String get searchHint => '按名称、国家、地址搜索…';

  @override
  String get searchReset => '清除';

  @override
  String get splitTitle => '分应用代理';

  @override
  String get splitTunOnlyBanner =>
      '仅在 TUN 模式下工作。在“系统代理”模式下，应用自行决定是否使用代理——无法强制。';

  @override
  String get splitEnableTun => '启用 TUN';

  @override
  String get splitModeHeader => '模式';

  @override
  String get splitAppsHeader => '应用';

  @override
  String get splitAppsHint => '点击某个应用以设置其动作（隧道 / 直连 / 阻止）和匹配方式。左侧复选框可启用/禁用规则。';

  @override
  String get splitByName => '按名称';

  @override
  String get splitByPath => '按路径';

  @override
  String get splitRuleDisabled => '已禁用——规则不生效';

  @override
  String get splitRemove => '移除';

  @override
  String get splitFromRunning => '从运行中选取';

  @override
  String get splitPickExe => '选择 .exe';

  @override
  String get splitSitesHeader => '站点（域名）';

  @override
  String get splitSitesHint =>
      '点击某个站点以选择动作（隧道 / 直连 / 阻止）。域名同时涵盖其子域名；子域名以树形分组。可指定端口。';

  @override
  String splitOnlyPort(Object port) {
    return '仅端口 $port';
  }

  @override
  String get splitProgramsFileType => '程序';

  @override
  String get splitRunningApps => '运行中的应用';

  @override
  String get splitSearchByName => '按名称搜索';

  @override
  String get splitNothingFound => '未找到任何内容';

  @override
  String get splitClose => '关闭';

  @override
  String get splitPortRange => '端口 1–65535';

  @override
  String get splitAction => '动作';

  @override
  String get splitPortOptional => '端口（可选）';

  @override
  String get splitAnyPort => '任意';

  @override
  String get splitPortHelper => '留空 = 任意端口。否则规则仅对此端口生效';

  @override
  String get splitMatching => '匹配';

  @override
  String get splitByNameSubtitle => 'exe 名称，与位置无关（可靠）';

  @override
  String get splitByPathSubtitle => 'exe 的完整路径（精确匹配）';

  @override
  String get splitDone => '完成';

  @override
  String get splitEnterDomain => '输入域名';

  @override
  String get splitAddSite => '添加站点';

  @override
  String get splitPort => '端口';

  @override
  String get splitAdd => '添加';

  @override
  String get routeBlock => '阻止';

  @override
  String get routeBlocked => '已阻止';

  @override
  String get routeYourPc => '您的电脑';

  @override
  String get routeTunnel => '隧道';

  @override
  String get routeViaVpn => '经由 VPN';

  @override
  String get routeVpn => 'VPN';

  @override
  String get routeInternet => '互联网';

  @override
  String get routeRest => '其余全部';

  @override
  String get routeDirectly => '直接';

  @override
  String get routeDirectPlusRest => '直连 + 其余';

  @override
  String get routeDirect => '直连';

  @override
  String get routeEmptyList => '列表为空';

  @override
  String get trayShow => '显示';

  @override
  String get trayToggle => '连接 / 断开';

  @override
  String get trayQuit => '退出';

  @override
  String get trayMinimizeTitle => '最小化到托盘';

  @override
  String get trayMinimizeBody => '应用将继续在托盘中运行。';

  @override
  String get trayDontAsk => '不再询问';

  @override
  String get trayMinimizeOk => '最小化';

  @override
  String get trayVpnTitle => 'VPN 已连接';

  @override
  String get trayVpnBody => '断开 VPN 并退出应用？';

  @override
  String get trayStay => '留下';

  @override
  String get trayQuitVpn => '断开并退出';

  @override
  String get tunTaskDone => '完成：TUN 启动将不再弹出 UAC 提示';

  @override
  String get tunTaskFailed => '无法创建任务（UAC 被拒绝或被策略阻止）';

  @override
  String get tunLogTitle => 'TUN 日志 (sing-box)';

  @override
  String get tunLogEmpty => '日志为空——隧道尚未启动。';

  @override
  String get tunCopy => '复制';

  @override
  String get tunClose => '关闭';

  @override
  String get tunTitle => 'TUN 与路由';

  @override
  String get tunSectionPrivilege => '管理员权限';

  @override
  String get tunChecking => '检查中…';

  @override
  String get tunNoUacConfigured => '已配置为无需 UAC 启动';

  @override
  String get tunUacEachConnect => '每次连接都将请求 UAC';

  @override
  String get tunTaskSubtitle => '一个最高权限的 Windows 任务计划程序任务（仅创建一次）。';

  @override
  String get tunRecreateTask => '重新创建任务';

  @override
  String get tunSetupOneUac => '设置（一次 UAC）';

  @override
  String get tunRemoveTask => '删除任务';

  @override
  String get tunSectionAdapter => '适配器';

  @override
  String get tunStack => 'TUN 栈';

  @override
  String get tunSectionRouting => '路由';

  @override
  String get tunStrictRoute => '严格路由（strict_route）';

  @override
  String get tunIpv6 => '隧道中的 IPv6';

  @override
  String get tunEndpointNat => '端点无关 NAT（UDP、游戏）';

  @override
  String get tunLanBypass => '本地网络绕过 VPN';

  @override
  String get tunDnsServer => 'DNS 服务器';

  @override
  String get tunDnsHijack => '拦截 DNS（53 端口）';

  @override
  String get tunResolveStrategy => '解析策略';

  @override
  String get tunSectionDiagnostics => '诊断';

  @override
  String get tunSingboxLogLevel => 'sing-box 日志级别';

  @override
  String get tunShowLog => '显示 TUN 日志';

  @override
  String get tunDnsVpn => '经由 VPN（推荐）';

  @override
  String get tunDnsSystem => '系统';

  @override
  String get tunDnsCustom => '自定义服务器';

  @override
  String get tunDnsVpnHint => '请求经 TCP 进入隧道——无泄漏';

  @override
  String get tunDnsSystemHint => '与 Windows 一致：可能发生 DNS 泄漏';

  @override
  String get tunDnsCustomHint => '指定的服务器，同样经由隧道';

  @override
  String get tunExcludeSubnets => '绕过 VPN 的子网';

  @override
  String get tunAdd => '添加';

  @override
  String get urlGroupImport => '导入';

  @override
  String get urlGroupControl => '控制';

  @override
  String get urlHintSubUrl => '订阅 URL';

  @override
  String get urlHintServerLink => '服务器链接';

  @override
  String get urlDescImportSub => '导入订阅';

  @override
  String get urlDescImportServer =>
      '添加单个服务器（vless / trojan / ss / hysteria2 …）';

  @override
  String get urlDescConnect => '连接 VPN';

  @override
  String get urlDescDisconnect => '断开 VPN';

  @override
  String get urlDescToggle => '切换 VPN';

  @override
  String get urlDescUpdate => '刷新当前订阅';

  @override
  String get urlSupportedImport =>
      '导入时应用可识别：订阅 URL（http/https），以及单个服务器 vless:// / vmess:// / trojan:// / ss:// / hysteria2://（hy2://）。';

  @override
  String get reportTitle => 'SilentGate — 支持报告';

  @override
  String get reportDescribeHere => '>>> 请在此描述问题（填写并保存文件）： <<<';

  @override
  String get reportWhatDid => '您做了什么：';

  @override
  String get reportWhatExpected => '您期望什么：';

  @override
  String get reportWhatHappened => '发生了什么：';

  @override
  String get reportWhenStarted => '何时开始：';

  @override
  String get reportTechNoticeLine1 => '以下是技术信息。发送前请查看；';

  @override
  String get reportTechNoticeLine2 => '此处不含密码或订阅令牌，订阅 URL 已隐藏。';

  @override
  String get noRealIpTitle => '绝不使用真实 IP';

  @override
  String get noRealIpSub => '即使 VPN 已连接，所有“直连”流量也走 VPN（包括 RU 网站）。本地网络保持直连。';

  @override
  String get flagAuto => '自动';

  @override
  String get autoUpdateIntervalLabel => '更新间隔（小时）';

  @override
  String get autoUpdatePreferSub => '使用订阅中的间隔';

  @override
  String get pingLegendInfo =>
      'Ping 徽章颜色：绿/黄/橙 — 服务器可用（TCP + 通过隧道验证）。灰色 — TCP 有响应但不代理流量（典型 Reality 端口）。红色“n/a” — 无响应，已排除。Ping 始终直接测量（在 VPN 之外）。';

  @override
  String get panelTunnelMarker => '自带分流规则';

  @override
  String panelInfoServers(Object n) {
    return '配置中的服务器：$n（自动选择最优）';
  }

  @override
  String get panelInfoDirect => '部分流量（如本地网站）直连，绕过 VPN';

  @override
  String get panelInfoBlock => '部分流量被阻止（广告/种子）';

  @override
  String get serviceChecksTitle => '服务检测';

  @override
  String get serviceChecksInfo =>
      '点按某个服务，检测它能否通过当前 VPN 连接打开。检测为手动操作——不会自动检测。对于 AI 服务，还会检测出口国家/地区的封锁。';

  @override
  String get serviceStatusOk => '可用';

  @override
  String get serviceStatusGeo => '能打开，但在出口国家/地区被封锁';

  @override
  String get serviceStatusFail => '无法打开';

  @override
  String get serviceStatusChecking => '检测中…';

  @override
  String get serviceStatusTap => '点按以检测';

  @override
  String serviceLatencyMs(Object ms) {
    return '$ms 毫秒';
  }

  @override
  String get homeTunAutotuneProgress => '正在调整 TUN 参数…';

  @override
  String get homeTunAutotuneDone => 'TUN 参数已调整';

  @override
  String get homeTunAutotuneFailed => '无法调整 TUN 参数';

  @override
  String get hy2NoteTitle => 'Hysteria2 服务器';

  @override
  String get hy2NoteBody =>
      'Hysteria2 服务器仅以 XRAY_JSON 格式返回——SilentGate 正是请求该格式，sing-box 会自动启动它们。若列表中未出现 Hysteria2：（面板 Remnawave 所有者）请启用 hysteria 入站并将其分配给订阅。注意：2.8.0 之前的 Remnawave 仅在 XRAY_JSON 中提供 Hysteria2——base64/CLASH/SINGBOX 中没有，因此上面的 Response Rules → XRAY_JSON 规则是必需的。';
}
