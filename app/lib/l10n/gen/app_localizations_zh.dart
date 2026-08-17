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
  String get commonClear => '清除';

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
  String get settingsSearchHint => '在设置中搜索';

  @override
  String settingsSearchEmpty(String query) {
    return '未找到任何内容：“$query”';
  }

  @override
  String get settingsExpand => '展开';

  @override
  String get settingsCollapse => '收起';

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
  String get captureProxyOnly => '仅代理';

  @override
  String get captureProxyOnlySub =>
      '内核已启动，本地端口在监听，但电脑并未进入隧道：只有明确指向我们代理的流量才会走 VPN';

  @override
  String get apiSectionTitle => '自动化 API';

  @override
  String get apiEnableTitle => '启用本地 API';

  @override
  String apiEnableSub(int port) {
    return '在 127.0.0.1:$port 上提供 HTTP —— 通过脚本控制客户端';
  }

  @override
  String get apiTokenTitle => '令牌';

  @override
  String get apiTokenUnset => '未设置 —— API 不会启动';

  @override
  String get apiTokenRegenerate => '重新生成令牌';

  @override
  String get apiTokenWarning =>
      '令牌以明文保存在设置文件中。它不会出现在日志或支持报告里，但拿到它的人可以切换服务器并读取您的订阅状态。';

  @override
  String get apiExitsTitle => '拥有独立端口的服务器';

  @override
  String get apiExitsSub => '每个服务器获得自己的本地端口 —— 发往该端口的请求都经过这台服务器';

  @override
  String get apiCopyPythonExample => '复制 Python 示例';

  @override
  String apiPortsHint(int control, int direct, int first) {
    return '控制 —— 端口 $control。「直连」—— 端口 $direct。服务器 —— 从 $first 起。';
  }

  @override
  String get apiRulesInProxyOnly => '应用分应用代理规则';

  @override
  String get apiRulesInProxyOnlySub =>
      '在此模式下，默认规则对任何程序都不生效。若希望「阻止」名单也覆盖经本地端口发出的请求，请开启此项。';

  @override
  String apiCaptureModeWarning(int control) {
    return '⚠️ 当前捕获方式为“系统代理”——该模式下不会开启出口端口，连接这些端口会被拒绝。控制端口 $control 在任何捕获方式下都可用。需要出口端口请选择“TUN（全局隧道）”或“仅代理”。';
  }

  @override
  String get apiPortBusyTitle => 'API 未能启动';

  @override
  String apiPortBusy(int port, String holder) {
    return '端口 $port 被 $holder 占用。请彻底关闭该程序（包括托盘图标），然后重新打开开关。';
  }

  @override
  String apiPortBusyUnknown(int port) {
    return '端口 $port 被另一个无法识别的程序占用，通常是另一个 VPN 客户端。请关闭它，然后重新打开开关。';
  }

  @override
  String get apiRulesInProxyOnlyEdit => '“阻止”列表在分应用代理页面中编辑';

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
  String get alwaysOnTitle => '系统级防泄漏';

  @override
  String get alwaysOnSub => '始终开启的 VPN 与「阻止不使用 VPN 的连接」——应用关闭时依然生效';

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
  String get aboutThirdPartySubEmbedded =>
      'Xray-core (MPL-2.0)、sing-box (GPL-3.0)、libXray (MIT) — 已内置于应用中';

  @override
  String get thirdPartyBodyEmbedded =>
      'On Android the cores are BUILT INTO the app (a native library inside the APK).\n\n• sing-box — GPL-3.0. The library is linked into the app, so derivatives must stay under GPL-3.0.\n  https://github.com/SagerNet/sing-box\n\n• Xray-core — MPL-2.0\n  https://github.com/XTLS/Xray-core\n\n• libXray — MIT\n  https://github.com/XTLS/libXray\n\nClient source code: https://github.com/Solat228/silentgate\nFull license texts — buttons below.';

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
  String autoTesting(int index, int total) {
    return '正在测试 $index/$total：';
  }

  @override
  String autoVariant(Object label) {
    return '变体：$label';
  }

  @override
  String autoServicesPassed(int ok, int total) {
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
  String autoServersForTuning(int selected, int total) {
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
  String homePingProgress(int done, int total) {
    return '正在测试服务器延迟：$total 中的 $done';
  }

  @override
  String get homeAutoConfigStarting => '自动配置正在启动…';

  @override
  String homeAutoConfigProgress(int current, int total, String name) {
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
  String homeFoundCount(int found, int total) {
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
  String homeSessionTraffic(String down, String up) {
    return '本次会话：↓ $down   ↑ $up';
  }

  @override
  String get subBarGbUnit => 'GB';

  @override
  String subBarUsage(String used, String total) {
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
  String get subSwitcherPingAll => '测试全部订阅的服务器';

  @override
  String get subSwitcherPingBusySpeed => '无法测延迟：正在进行测速';

  @override
  String get subSwitcherExpired => '已过期';

  @override
  String subSwitcherExpiredOn(String date) {
    return '订阅已于 $date 过期';
  }

  @override
  String subSwitcherCountTotal(int total) {
    return '订阅中的服务器：$total 个。尚未做过通道检查，请运行“测试全部订阅的服务器”。';
  }

  @override
  String subSwitcherCountWorking(int total, int working) {
    return '订阅中的服务器：$total 个，其中通过通道检查（经服务器发起请求）的有 $working 个。';
  }

  @override
  String subSwitcherCountChecking(int total) {
    return '该订阅共有 $total 个服务器。检测正在进行中——可用数量将在检测结束后显示。';
  }

  @override
  String subSwitcherCountPartial(int total, int working) {
    return '该订阅共有 $total 个服务器。本次检测未完成（已取消或中断），因此数字不完整：在已检测到的服务器中，有 $working 个通过了通道检查。';
  }

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
      '如果内核崩溃、服务器掉线或网络发生变化（Wi-Fi ↔ 网线、从睡眠中唤醒、新的 IP），应用会自行重新建立连接。重试间隔逐渐拉长：0.8 秒 → 3 秒 → 8 秒 → 20 秒，之后保持在 20 秒。共八次重试，之后应用放弃并显示错误。用按钮断开连接始终会取消恢复。\n\n⚠️ 开启断网保护时，重试永不耗尽。只要重试还在继续，流量就保持被拦截；停止重试就意味着放它绕过 VPN 出去——因此应用会每 20 秒继续尝试，直到你自己关闭 VPN，并且最多每 15 分钟提醒一次失败。一小时后恢复的服务器会被自动接上。\n\n在「自动（最佳服务器）」模式下，应用不会把最后一次重试浪费在已经失效的服务器上：在第八次中的第七次时就切换到下一个候选，并在那里重新开始计数。\n\n网络变化依据其他网卡的真实地址判定：本机隧道和服务地址（link-local）不计入，只有连续两次轮询都保持的变化才被接受，且连接后的头 15 秒忽略该信号。没有这些防护，隧道建立本身就会被算作「网络变化」，从而引发无休止的重连。';

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
  String serversFound(int found, int total) {
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
  String jsonProfileServers(int count, String burst) {
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
  String get splitProxyOnlyBanner =>
      '在“仅代理”模式下没有可拦截的流量：规则对本机任何程序都不生效。“阻止”列表仅作用于本地 API 端口，且仅当“流量捕获”一节中的“应用分应用代理规则”开关打开时才生效。其余规则可以在此预先配置：切换到 TUN 后即会生效。';

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
  String get splitPickInstalled => '选择应用';

  @override
  String get splitInstalledApps => '已安装的应用';

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
  String get pingUntestedHint => '尚未测试。在移动端，Hysteria2 和“自动”配置仅在已连接时测量。';

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
      '六个常用服务会自动检测：第一次在应用启动、VPN 尚未开启时，第二次在连接成功后立即进行。两个圆点表示“之前 → 之后”，让你看清究竟是不是 VPN 起了作用。点按可重新检测。绿色表示可访问，橙色表示地区限制，红色表示不可达。';

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

  @override
  String get enumStatusDisconnected => '已断开';

  @override
  String get enumStatusConnecting => '连接中…';

  @override
  String get enumStatusConnected => '已连接';

  @override
  String get enumStatusDisconnecting => '断开中…';

  @override
  String get enumStatusError => '错误';

  @override
  String get enumVariantPlain => '默认';

  @override
  String get tagAutoSelect => '自动';

  @override
  String get tagPanel => '面板';

  @override
  String get tagPortHopping => '端口跳跃';

  @override
  String syncServersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个服务器',
    );
    return '$_temp0';
  }

  @override
  String get syncNoChanges => '无变化';

  @override
  String get errInvalidJson => 'JSON 无效';

  @override
  String get errPickServerFirst => '请先选择服务器';

  @override
  String get errImportSubscriptionFirst => '请先导入订阅';

  @override
  String get speedSizeFull => '20 MB';

  @override
  String get speedSizeLight => '5 MB';

  @override
  String speedMbPerSec(String value) {
    return '$value MB/秒';
  }

  @override
  String speedKbPerSec(String value) {
    return '$value KB/秒';
  }

  @override
  String portBusyTitle(int port, String by) {
    return '端口 $port 已被 $by 占用。';
  }

  @override
  String get srvTileMenu => '服务器操作';

  @override
  String get supportCopyReport => '复制报告';

  @override
  String get supportReportCopied => '报告已复制 — 请粘贴到支持聊天中';

  @override
  String subBarUsedOnly(String used) {
    return '已用 $used';
  }

  @override
  String get subBarUnlimitedTraffic => '流量不限';

  @override
  String get supportDescribeLabel => '描述问题';

  @override
  String get supportDescribeHint => '您做了什么、期望什么、发生了什么以及何时开始';

  @override
  String get supportDescribeRequired => '请描述问题 — 没有描述的报告没有用';

  @override
  String get supportNoScreenshots => '请勿在此粘贴截图 — 请在 Telegram 聊天中单独发送。';

  @override
  String get supportDescriptionSection => '用户描述';

  @override
  String get splitAllowRealIp => '允许此规则使用真实 IP';

  @override
  String get splitAllowRealIpOn => '已勾选：这是例外，流量将以你的真实地址外发';

  @override
  String get splitAllowRealIpOff => '未勾选：该规则走 VPN —— 保护优先于所有规则';

  @override
  String get splitRealIpExposed => '真实 IP';

  @override
  String get splitRealIpProtected => '经由 VPN';

  @override
  String get vpnActiveBadge => 'VPN 已启用';

  @override
  String get splitCopyDomain => '复制地址';

  @override
  String get splitCopyPath => '复制路径';

  @override
  String get homeServerInfo => '服务器信息';

  @override
  String get serverInfoVerifyInBrowser => '在浏览器中核对';

  @override
  String get tunDnsForAll => '所有应用的 DNS 走 VPN';

  @override
  String get infoDnsForAll => '仅在“仅选定应用”模式下生效。⚠️ 重新连接后才会应用。';

  @override
  String get homeSettingsNeedReconnect => '设置已更改 — 重新连接后生效';

  @override
  String blockPageWindowTitle(String app) {
    return '已拦截 — $app';
  }

  @override
  String get blockPageHeading => '网站已被拦截';

  @override
  String blockPageBody(String host, String app) {
    return '$host 被 $app 中的分应用代理规则拦截。';
  }

  @override
  String get blockPageHint => '你可以修改规则：设置 → 分应用代理 → 网站。';

  @override
  String get blockPageNote => '此页面来自应用本身，并非网络错误。网站打不开是因为你自己把它加入了拦截列表。';

  @override
  String get settingsBlockPage => '拦截提示页';

  @override
  String get settingsBlockPageSub =>
      '不再显示连接错误，而是打开一个页面说明是哪条规则拦截了该网站。仅对 http 有效：若不在系统中安装我们自己的根证书，就无法替换 https 页面，而该证书会使你全部的加密流量都可被读取。';

  @override
  String get trayCloseFully => '完全退出';

  @override
  String errorVpnConflictApp(String app) {
    return '看起来是 $app 在干扰：它自己的 VPN 隧道正在运行。两条隧道会同时争抢默认路由。';
  }

  @override
  String errorCloseApp(String app) {
    return '关闭 $app';
  }

  @override
  String toastAppClosed(String app) {
    return '已关闭 $app';
  }

  @override
  String toastAppCloseFailed(String app) {
    return '无法关闭 $app — 请手动关闭';
  }

  @override
  String get tunBlockQuic => '阻止 QUIC（HTTP/3）';

  @override
  String get infoBlockQuic =>
      '网站规则按域名匹配，而应用只能在普通 TLS 中看到域名。改用 HTTP/3 的浏览器不暴露域名，域名规则就会悄无声息地失效。阻止后浏览器回退到普通连接，域名重新可见。网站仍可正常访问：HTTP/3 对它们并非必需，只是视频加载可能略慢。';

  @override
  String get tunBlockEncryptedDns => '阻止加密 DNS（DoH/DoT）';

  @override
  String get infoBlockEncryptedDns =>
      '浏览器和 Windows 可以通过 HTTPS 解析地址，从而绕过我们的拦截，此时「直连」和「拦截」规则在 DNS 层面完全失效。⚠️ 如果浏览器中固定指定了加密 DNS 提供商，它不会回退到普通 DNS，而是直接打不开网站。已知提供商名单天然不完整。';

  @override
  String get autoUseSpeed => '将速度纳入考量';

  @override
  String get infoAutoUseSpeed =>
      '在按服务和延迟筛选之后，对最优的三个候选做下载实测，真正更快的排在最前。速度与你自己的带宽相比：已经能跑满你带宽的服务器不再比拼兆比特，改由延迟决定——超出带宽的速度你本来也用不上。⚠️ 会消耗订阅流量：测你自己的带宽 5 MB，每个候选再 5 MB，一轮约 20 MB。';

  @override
  String get autoSpeedOwn => '正在测量你自己的带宽…';

  @override
  String autoSpeedServer(String server, int index, int total) {
    return '测速：$server（第 $index / 共 $total）';
  }

  @override
  String autoSpeedShare(int percent) {
    return '你带宽的 $percent%';
  }

  @override
  String get conflictDialogTitle => '检测到其他 VPN';

  @override
  String conflictDialogBody(String app) {
    return '看起来 $app 正在运行，并已建立自己的隧道。两条隧道会同时争抢默认路由，连接可能失败，或者连上却无法访问网络。';
  }

  @override
  String get conflictCloseAndConnect => '关闭它并连接';

  @override
  String get conflictConnectAnyway => '仍然连接';

  @override
  String get serviceChecksLegendBefore => '已在未开 VPN 时检测';

  @override
  String get serviceChecksLegendAfter => '左侧为未开 VPN，右侧为经由 VPN';

  @override
  String get serviceChecksBefore => '未开 VPN';

  @override
  String get serviceChecksAfter => '经由 VPN';

  @override
  String get serviceChecksNoBaseline => '未在无 VPN 时检测';

  @override
  String autoSpeedValue(String value) {
    return '$value Mbps';
  }

  @override
  String get splitShowBlockPage => '显示拦截页面';

  @override
  String get splitBlockPageNeedsVpn => '拦截页面仅在 VPN 开启时可用';

  @override
  String get srvInfoNeedsConnection => '在此平台上，经由服务器的测速需要先开启 VPN';

  @override
  String get serviceYoutubeThrottleNote =>
      '⚠️ 此检测看不出 YouTube 被限速：运营商正常应答，却把视频带宽压低。绿色表示“服务可达”，不代表“视频能播”。';

  @override
  String get urlSchemeConnectServer => 'silentgate://connect?server=<服务器名称>';

  @override
  String get urlDescConnectServer =>
      '连接到指定服务器。名称即列表中显示、由订阅下发的名称，例如“波兰 1.5”。可省略旗帜表情与大小写。没有精确匹配时会转为搜索：按国家、地址或协议。toggle 同样适用。';

  @override
  String get splitSelectAllFound => '全选搜索结果';

  @override
  String splitAddSelected(int count) {
    return '添加（$count）';
  }

  @override
  String get splitQuicNote =>
      '只要存在至少一条网站规则，应用就会为所有流量关闭 HTTP/3（QUIC）。否则浏览器会改用 HTTP/3，不留下网站名称，规则便会悄无声息地失效。网站仍可访问：会回退到普通 TLS，只是稍慢一些。';

  @override
  String get splitNoRealIpBanner => '“绝不使用真实 IP”已开启：未勾选的“直连”规则将走 VPN';

  @override
  String get settingsNoRealIpAffects => '影响“直连”规则：未勾选“允许真实 IP”时它们会走 VPN';

  @override
  String get splitAppOverrideSites => '优先于网站规则';

  @override
  String get splitAppOverrideSitesSub => '该应用的全部流量都按此规则走，即使某个网站规则另有规定';

  @override
  String get settingsMyRulesOverridePanel => '我的规则优先于面板规则';

  @override
  String get settingsMyRulesOverridePanelSub =>
      '面板会下发自己的分流，通常是“本地站点绕过 VPN”。它在你的规则之后生效，因此被你标为“隧道”的网站仍可能以真实 IP 直连出去。开启后：写了隧道就是隧道。代价：本地站点绕远，速度变慢。';

  @override
  String get commonOpen => '打开';

  @override
  String get tunRouteOnlySubnets => '仅这些子网走隧道';

  @override
  String get infoTunRouteOnlyCidrs =>
      '在 Windows 上，这是让一部分流量真正独立于 VPN 客户端的唯一办法。\n\n通常隧道会接管默认路由，本机的全部流量都会进入隧道：“直连”标记是在核心内部才处理的——核心先收下数据包，再以自己的名义把它发出去。这类流量的寿命完全取决于核心，核心卡死，它也跟着卡死。\n\n只要列表不为空，隧道就拿不到默认路由：它只接管列出的子网，其余流量由系统经普通适配器发出——客户端根本看不到这部分流量。\n\n代价：这里的划分按地址进行，而应用规则和网站规则按名称匹配。若某个网站的地址不在列表中，核心便看不到它，任何规则都对它无效。留空即为隧道的常规工作方式。';

  @override
  String get tunRouteOnlyWarning =>
      '隧道只接管列出的子网。应用规则和网站规则仅在这些子网内生效：没有进入隧道的流量不会送到核心面前——这样的网站既无法阻止，也无法改变其去向。';

  @override
  String get tunAlsoSystemProxy => '系统代理与隧道并用';

  @override
  String get infoTunAlsoSystemProxy =>
      '混合模式：隧道和系统代理同时工作。\n\n尊重系统代理的应用（浏览器、Telegram）会走捷径直接连到本地端口，绕过隧道的用户态栈，并把域名而不是裸地址交给核心——对它们而言，网站规则会更准确，也不再依赖对 TLS 的解析。\n\n但它们并不会因此独立于客户端：走的仍是同一个进程。';

  @override
  String get tunMixedModeWarning =>
      '经系统代理进来的连接没有归属进程——在核心看来这是一个本地连接。因此对这些程序来说，应用规则不会生效。网站规则照常工作，而且比平时更准确。';

  @override
  String get tunWatchdog => '核心卡死看门狗';

  @override
  String get infoTunWatchdog =>
      '允许隧道核心保持无响应的秒数，超过后即视为卡死并关闭隧道。\n\n如果核心崩溃，Windows 会自行善后——适配器、路由和防火墙规则都会被撤下，网络随之恢复。但如果核心只是卡死，则什么都不会被撤下：适配器仍在，并吞掉本机的全部流量，连标记为“直连”的也不例外。在用户看来这就是“完全断网”，而且不会自行恢复。\n\n看门狗只在核心第一次成功应答之后才启用：否则，凡是服务端口没能启动的场合，它都会直接掐断连接。0 表示不监控。最小 10 秒。';

  @override
  String get tunWatchdogOff => '已关闭：不会检测隧道卡死';

  @override
  String tunWatchdogSubtitle(int seconds) {
    return '若核心无响应超过 $seconds 秒则关闭隧道';
  }

  @override
  String get tunDnsForAllWarning =>
      '本机的全部域名解析都将经过隧道。一旦隧道卡住，即使是直连、根本不需要 VPN 的应用也无法解析域名——在用户看来就是彻底断网。';

  @override
  String get tunCidrInvalid => '需要带前缀的地址，例如 10.8.0.0/24';

  @override
  String get geoTitle => '路由地理数据库';

  @override
  String get geoMissing => '尚未下载——按国家和类别的规则不会生效';

  @override
  String geoPresent(String size, String date) {
    return '$size，更新于 $date';
  }

  @override
  String get geoDownload => '下载';

  @override
  String get geoUpdate => '更新';

  @override
  String geoDownloading(String file) {
    return '正在下载 $file…';
  }

  @override
  String get geoDone => '地理数据库已更新';

  @override
  String get geoWhy =>
      'geoip.dat 和 geosite.dat 是按国家整理的地址清单和按类别整理的域名清单。核心依靠它们解析订阅面板下发的 geoip:ru、geosite:category-ads 这类规则。文件缺失时，这类规则会从配置中移除。';

  @override
  String geoFileOk(String size, String date) {
    return '$size，更新于 $date';
  }

  @override
  String get geoFileMissing => '文件缺失';

  @override
  String get geoFileCorrupt => '文件已损坏——核心无法读取';

  @override
  String geoFolder(String path) {
    return '文件夹：$path';
  }

  @override
  String get geoBundledWindows =>
      '在 Windows 上，这些文件随核心一同发布，通常已经就位。清单过时后，这里的更新会重新下载它们。';

  @override
  String get geoSource =>
      '来源与 Xray 发行包中那些文件的来源相同：Loyalsoldier/v2ray-rules-dat。下载下来的文件，会用同一发布版本给出的校验和进行核对。';

  @override
  String get geoReplaceWarning =>
      '旧文件会保留下来：万一替换后路由变差，一个按钮就能把它们换回来。如果新文件里没有订阅所引用的类别，更新不会被安装。';

  @override
  String geoBackupLine(String files, String size, String date) {
    return '已有备份：$files — $size，保存于 $date';
  }

  @override
  String get geoRestore => '恢复旧版';

  @override
  String get geoRestored => '旧版地理数据库已恢复';

  @override
  String get geoRestoreTitle => '要恢复旧版地理数据库吗？';

  @override
  String get geoRestoreBody =>
      '当前文件将被上次更新前保存的那份备份替换。此操作不需要联网。此后若还想用更新后的文件，只能重新下载一次。';

  @override
  String get geoErrorCategories =>
      '新文件里没有订阅所引用的类别。替换已取消，旧文件原样留在原处——路由没有受到影响。具体缺少哪些类别，见下方一行。';

  @override
  String get geoNoWrite =>
      '该文件夹不可写入——无法下载到这里。通常是因为安装在了 Program Files：请以管理员身份运行应用。';

  @override
  String get geoCheck => '检查更新';

  @override
  String get geoCheckAgain => '再检查一次';

  @override
  String get geoChecking => '正在查询发布版本…';

  @override
  String geoLastCheck(String when) {
    return '上次检查：$when';
  }

  @override
  String get geoNeverChecked => '还没有检查过更新';

  @override
  String geoUpdateAvailable(String files, String size) {
    return '有可用更新：$files（$size）';
  }

  @override
  String get geoSizeUnknown => '服务器未告知';

  @override
  String get geoUpToDate => '无需更新：文件与最新发布一致。';

  @override
  String get geoPlanTitle => '要下载地理数据库吗？';

  @override
  String get geoPlanTitleUpdate => '要更新地理数据库吗？';

  @override
  String geoPlanFiles(String files) {
    return '文件：$files';
  }

  @override
  String geoPlanSize(String size) {
    return '大小：$size';
  }

  @override
  String get geoPlanTraffic => '文件会通过您当前的网络下载。使用移动数据时，这笔流量并不算小。';

  @override
  String geoProgressBytes(String done, String total) {
    return '$done / $total';
  }

  @override
  String get geoErrorNetwork => '无法连接更新服务器。请检查网络后重试。';

  @override
  String get geoErrorServer => '更新服务器拒绝了请求。多半是暂时的，请稍后再试。';

  @override
  String get geoErrorWrite => '无法写入文件：没有该文件夹的权限，或磁盘空间不足。';

  @override
  String get geoErrorCorrupt => '下载的文件未通过校验——传输过程中损坏了。请重试。';

  @override
  String get geoErrorOther => '没有成功。详情见下方。';

  @override
  String geoFailed(String error) {
    return '下载失败：$error';
  }

  @override
  String get infoGeoAssets =>
      'geoip.dat 和 geosite.dat 是按国家整理的地址清单和按类别整理的域名清单（例如“俄罗斯网站”“政务服务”“VKontakte”）。订阅面板下发的路由规则正是依靠它们工作。\n\n它们没有打包进应用：两个加起来约 30 MB，而且并非人人都需要——普通服务器完全用不到。\n\n文件缺失期间，这类规则会从配置中移除，原本被它们放行直连的流量改走 VPN。这样是安全的，只是更慢，而且本地站点可能因为来自国外的地址而拒绝访问。你自己设定的网站和应用规则照常生效——它们不依赖这些文件。';

  @override
  String get supportBullet2Android =>
      '• 点击后，报告会汇集为一个文件，并打开系统的“分享”窗口——选择 Telegram，它会作为一个附件发送。请在上方的输入框中描述问题：没有描述就无从分析。';

  @override
  String get supportDoneTextAndroid =>
      '报告已汇集为一个文件。请在系统窗口中选择发送目标——发送到 Telegram 时它会作为附件，而不是文本。';

  @override
  String get exitsHeader => '出口';

  @override
  String get exitsHint => '“隧道”规则可指向特定出口：一个网站走德国，另一个走美国。未选出口时，规则照旧走主隧道。';

  @override
  String get exitsAdd => '添加出口';

  @override
  String get exitsEmpty => '尚无出口';

  @override
  String get exitsName => '名称';

  @override
  String get exitsNameHint => '德国';

  @override
  String get exitsServers => '服务器';

  @override
  String get exitsAutoSelect => '按延迟自动选择';

  @override
  String get exitsAutoSelectSub =>
      '内核会自行把流量保持在可用服务器上。代价是每三分钟探测一次各服务器，在手机上会唤醒射频。';

  @override
  String get exitsAutoSelectNeedsTwo => '至少需要两台服务器';

  @override
  String get exitsDelete => '删除出口';

  @override
  String get exitsNoServers => '没有服务器 — 请先导入订阅';

  @override
  String get exitsSearch => '搜索服务器';

  @override
  String get exitsPickAtLeastOne => '请至少选择一台服务器';

  @override
  String get exitsUnsupportedNote =>
      '面板的“自动”配置和 hysteria2 无法作为独立出口运行：它们由另一个内核处理。此类服务器在列表中不可选。';

  @override
  String get infoExits =>
      '出口是“隧道”规则的目的地。\n\n默认一个出口只含一台服务器，后台开销为零：普通协议不保持长连接。只有在需要防止节点故障时才用多服务器自动选择组，它会带来周期性探测，在手机上就是唤醒射频。\n\n出口只对“隧道”动作有意义。“经德国直连”是自相矛盾的：直连规则绕过所有出口。\n\n站点与其子域可以分配到不同出口——应用会把更具体的规则排在上面，否则父域会吞掉子域。\n\n重要：在 Windows 的系统代理模式下出口完全不起作用——该模式不构建路由规则，需要隧道模式。';

  @override
  String get ruleServer => '通过服务器';

  @override
  String get ruleServerCurrent => '与主服务器相同';

  @override
  String ruleServerCurrentNamed(String server) {
    return '与主服务器相同（$server）';
  }

  @override
  String get routeMatchByName => '按文件名匹配';

  @override
  String get routeYourApps => '你的应用';

  @override
  String get routeYourSites => '你的网站';

  @override
  String get routeAppsAndSites => '应用和网站';

  @override
  String get notifCompactTitle => '精简通知';

  @override
  String get notifCompactSub =>
      '关闭时——显示订阅、服务器和速度，并带操作按钮。开启时——标题里是应用和订阅，下方是服务器，不显示速度，也没有按钮。';

  @override
  String get localProxyAuthTitle => '本地代理密码';

  @override
  String get localProxyAuthInfo =>
      '核心的本地端口（127.0.0.1）就是一个通往你 VPN 的完整代理。没有密码时，本机上任何程序都能连上它，并拿走你的整条隧道：出口 IP、订阅流量额度，还能绕开你自己设的分应用代理规则——包括那些被你标记为“阻止”的应用。在 Android 上这一点尤其重要：本地端口对任何已安装的应用都是可见的。\n\n只有当你确实要用不支持认证的程序连这个代理时，才关掉它。';

  @override
  String get localProxyAuthOff => '已关闭：本机任何程序都能使用这个本地代理';

  @override
  String get localProxyAuthSystemProxy =>
      '在系统代理模式下不生效：Windows 无法把密码传给本地代理。仅在 TUN 模式下有效。';

  @override
  String get localProxyAuthRandom => '每次连接都使用新的随机密码——不保存在设置中';

  @override
  String get localProxyAuthCustom => '自定义用户名和密码（保存在设置文件中）';

  @override
  String get localProxyCredsTitle => '自定义用户名和密码';

  @override
  String get localProxyCredsUnset => '未设置——使用随机密码';

  @override
  String localProxyCredsUser(String user) {
    return '用户名：$user';
  }

  @override
  String get localProxyDialogTitle => '本地代理的用户名和密码';

  @override
  String get localProxyDialogBody =>
      '只有当您自己在第三方程序里填写我们的代理（127.0.0.1）时才需要。留空则每次连接都使用随机密码：它不会保存在设置中，也不会出现在日志或支持报告里。手动设置的密码会以明文留在设置文件中。';

  @override
  String get localProxyFieldUser => '用户名';

  @override
  String get localProxyFieldPassword => '密码';

  @override
  String get localProxyFieldHint => '留空 = 随机';

  @override
  String get lockdownOnTitle => '系统级防泄漏已开启';

  @override
  String get lockdownOnSub => '即使应用被关闭或被系统清理，流量也会被阻断。这是最可靠的模式。';

  @override
  String get lockdownHalfTitle => '防护只开了一半';

  @override
  String get lockdownHalfSub =>
      '已指定“始终开启的 VPN”，但“阻止不使用 VPN 的连接”没有打开。应用还活着时流量是受保护的；一旦被系统清理，流量就会明文发出去。';

  @override
  String get lockdownOffTitle => '系统级防泄漏已关闭';

  @override
  String get lockdownOffSub =>
      '只要应用还在运行，我们的断网保护就能拦住流量。一旦被系统清理，流量就会绕过 VPN。请开启“始终开启的 VPN”和“阻止不使用 VPN 的连接”。';

  @override
  String get lockdownUnknownTitle => '系统级防泄漏：状态未知';

  @override
  String get lockdownUnknownSub =>
      '只有 Android 10 及以上、且隧道已建立时才能读到状态。请手动检查：“始终开启的 VPN”和“阻止不使用 VPN 的连接”。';

  @override
  String get lockdownOpenFailed => '无法打开系统 VPN 设置。请手动找到：设置 → 网络和互联网 → VPN。';

  @override
  String get blockNoticeTitle => '提示被拦截的网站';

  @override
  String get blockNoticeSub => '当应用或浏览器访问“阻止”列表中的网站时，底部会出现一条带网站名的提示。点击即可打开本界面。';

  @override
  String get siteInsecureScheme =>
      '地址写成了 http://——连接不加密，运营商能看到全部内容。去掉“http://”，浏览器就会走 https。';

  @override
  String get exitServerGone => '该规则的服务器已从订阅中消失——流量改走主隧道';

  @override
  String exitServerUnsupported(String name) {
    return '$name\n\n这台服务器无法作为独立出口运行：面板的“自动”配置和部分协议只有 Xray 支持，而出口由 sing-box 分流。该规则的流量改走主隧道。';
  }

  @override
  String get noticeRulesAction => '规则';

  @override
  String get geoVerdictMissingTitle => '地理数据库尚未下载';

  @override
  String get geoVerdictMissingSub => '订阅中按国家和类别的规则当前已停用——这部分流量走 VPN，而不是直连。';

  @override
  String get geoVerdictUnusableTitle => '核心未能打开地理数据库';

  @override
  String get geoVerdictUnusableSub => '文件都在，但核心没有读取它们。重新下载数据库通常可以解决。';

  @override
  String get geoOfferMissingSub => '缺少它们，订阅中按国家和类别的规则就无法工作——这部分流量会走 VPN，而不是直连。';

  @override
  String get geoOfferDismiss => '不再提示';

  @override
  String get pingPendingTooltip => '到服务器的 TCP 延迟。通道检查仍在进行，服务器是否真正可用尚不清楚。';

  @override
  String get pingUnverifiedTooltip => '到服务器的 TCP 延迟。未经过隧道检查，只知道是否可达。';

  @override
  String pingMeasuredAt(String time) {
    return '测量时间：$time';
  }

  @override
  String get pingChecking => '检查中';

  @override
  String autoTimer(String elapsed, String remaining) {
    return '已用 $elapsed · 约剩 $remaining';
  }

  @override
  String autoTimerNoEstimate(String elapsed) {
    return '已用 $elapsed';
  }

  @override
  String autoSpeedRanking(String name) {
    return '正在测速：$name';
  }

  @override
  String get autoWarnNoRealIp => '已开启“不暴露真实 IP”，全部流量都走 VPN。';

  @override
  String get autoWarnAllVpn => '当前为“全部走 VPN”模式，您的规则暂时不生效。';

  @override
  String get autoWarnPanelOverride => '已开启“我的规则优先于面板规则”。';

  @override
  String get autoWarnProbesDirect =>
      '这不影响检查本身：无论怎样设置，探测都绕过 VPN。但在 TUN 模式下探测会经过内核进程——若内核卡死，所有结果都会是假阴性。';

  @override
  String get autoWarnTurnOff => '关闭';

  @override
  String get toastCollapse => '收起';

  @override
  String get toastExpand => '展开';

  @override
  String get toastOpenAutoConfig => '打开自动配置';

  @override
  String get splitAppAlreadyAdded => '该应用已在规则列表中';

  @override
  String logsFileLine(String name, String size, int lines) {
    return '$name — $size，$lines 行';
  }

  @override
  String logsReportsLine(int count, String size) {
    return '支持报告：$count 个，$size';
  }

  @override
  String get logsRetentionTitle => '保留日志与报告';

  @override
  String get logsRetentionDay => '1 天';

  @override
  String get logsRetentionTwoWeeks => '2 周';

  @override
  String get logsRetentionMonth => '1 个月';

  @override
  String get logsRetentionNever => '永不删除';

  @override
  String get logsRetentionInfo =>
      '日志和支持报告超过所选期限后会被删除，检查在应用启动时进行。选择“永不”会把全部内容留在磁盘上——那就请自己留意占用：报告会完整包含日志，并随之增大。';

  @override
  String get logsCleanNow => '立即删除旧文件';

  @override
  String logsCleaned(int count, String size) {
    return '已删除 $count 个文件，释放 $size';
  }

  @override
  String get logsNothingToClean => '没有可删除的内容';

  @override
  String get speedTooltip => '经此服务器的下载速度';

  @override
  String get speedFromAutoConfig => '速度由自动配置测得';

  @override
  String get speedBlockedTooltip => '不测速：该服务器未通过通道检查（请求没能经它送达）';

  @override
  String get srvTileMeasureSpeed => '测速';

  @override
  String get speedRunTooltip => '测试各服务器速度';

  @override
  String get speedConfirmTitle => '要测速吗？';

  @override
  String speedConfirmBody(int count, String size, String total) {
    return '将检查 $count 个服务器，每个下载 $size 的样本——约占用订阅流量 $total。';
  }

  @override
  String speedConfirmSkipped(int count) {
    return '已测过的将跳过：$count 个。';
  }

  @override
  String get speedConfirmRun => '测速';

  @override
  String get speedNoTargets => '没有可测的：只对通过通道检查的服务器测速。请先测试列表。';

  @override
  String get speedNotVerified => '该服务器未通过通道检查——不经它测速';

  @override
  String speedProgress(int done, int total) {
    return '速度：$total 个中的 $done 个';
  }

  @override
  String get updateOnStartTitle => '启动时刷新订阅';

  @override
  String get updateOnStartSub => '每次都拉取最新服务器列表，而不只按计时器';

  @override
  String get apiSectionSub => '127.0.0.1 上的 HTTP——从脚本控制客户端';

  @override
  String get momentJustNow => '刚刚';

  @override
  String momentMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 分钟前',
    );
    return '$_temp0';
  }

  @override
  String momentHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 小时前',
    );
    return '$_temp0';
  }

  @override
  String get serviceChecksMenuTitle => '连接时检测';

  @override
  String get serviceChecksMenuOff => '连接时不检测';

  @override
  String get serviceChecksMenuTooltip => '检测哪些服务';

  @override
  String get serviceChecksLegendOff => '服务检测已关闭';

  @override
  String get srvInfoAutoNever => '自动配置尚未检测过该服务器——运行一次即可看到哪些服务能通过它使用。';

  @override
  String get srvInfoAutoHint => '上次自动配置运行时的数据。此处不会重新测量。';

  @override
  String srvInfoAutoGeoNote(Object services) {
    return '$services：可以通过该服务器访问，但在它的出口国家/地区不可用。服务器本身正常，只是这些服务用不了——需要换到其他国家的出口。';
  }

  @override
  String get settingsSectionChecks => '服务检测';

  @override
  String get settingsSectionAutotune => '自动调优';

  @override
  String get settingsSpeedRankTitle => '自动选择时参考速度';

  @override
  String get settingsSpeedRankSub => '通过服务检测的候选服务器还会用下载实测一次，真正更快的排在最前。会消耗订阅流量。';

  @override
  String get settingsSpeedTopNLabel => '参与测速的服务器数';

  @override
  String get settingsSpeedTopNSub =>
      '外加一次本地线路的测量——没有它就无从比较：60 Mbit/s 在 60 兆线路上很好，在 300 兆线路上很差。';

  @override
  String settingsSpeedTrafficNote(Object mb) {
    return '每轮约消耗 $mb MB 订阅流量';
  }

  @override
  String get settingsSpeedWarnTitle => '测速会消耗订阅流量';

  @override
  String settingsSpeedWarnBody(Object mb) {
    return '自动调优每运行一次，会通过你的订阅下载约 $mb MB：每台被测服务器一次探测，再加一次本地线路探测。这些流量从你的配额中扣除。';
  }

  @override
  String get settingsSpeedWarnEnable => '仍然开启';

  @override
  String get settingsConcurrencyTitle => '同时进行的检测数';

  @override
  String get settingsConcurrencySub =>
      '1 就是原来的行为：候选服务器严格逐个检测，结果一旦变得奇怪就退回这里。数值越大越快，但每个候选都会启动自己的内核：机器负载更高，延迟测量之间也会互相干扰。';

  @override
  String get settingsConnectChecksTitle => '连接后检测服务';

  @override
  String get settingsConnectChecksSubOn => '隧道建立时运行一次：按钮下方的标签立刻显示哪些能打开、哪些不能。';

  @override
  String get settingsConnectChecksSubOff => '在你自己点击之前，这些标签会一直是灰色的。';

  @override
  String get settingsConnectCheckServices => '连接后检测哪些服务';

  @override
  String get settingsConnectCheckServicesSub =>
      '这组服务刻意与自动调优分开：自动调优是在找一台可用服务器，可以慢慢试；而这些标签回答的是“现在能不能用”。';

  @override
  String get settingsConnectChecksEmpty => '未选择任何服务——将无可检测。';

  @override
  String get settingsSectionSeamless => '无缝切换';

  @override
  String get settingsSeamlessNote =>
      '以下选项都不能保住已建立的连接：换服务器就是换出口 IP，对端看到的是另一个地址，通话或下载无论如何都会断。这里只是让本机的网络不要闪断。';

  @override
  String get settingsSeamlessServerTitle => '仅更换服务器时不重建隧道';

  @override
  String get settingsSeamlessServerSub =>
      '只重启代理内核：网卡和路由原地不动，本机网络不会闪断。代价是订阅中所有服务器的地址都要提前写成绕过隧道。';

  @override
  String get settingsSeamlessNetworkTitle => '网络切换时不切断通道';

  @override
  String get settingsSeamlessNetworkSub =>
      'Wi-Fi → 移动网络：先看流量是否还通，只有确实断了才重启内核。QUIC（hysteria2）本身就能扛住地址变化。代价是：若通道确实已断，恢复会晚几秒开始。';

  @override
  String get settingsSeamlessKeepTunTitle => '重试之间保持网卡不下线';

  @override
  String get settingsSeamlessKeepTunSub =>
      '恢复期间不去反复改动默认路由。⚠️ 这不是 kill switch：不会阻断绕过 VPN 的流量，只是保持网卡本身不下线。';

  @override
  String get autoSpeedTrafficTitle => '测速会消耗流量';

  @override
  String autoSpeedTrafficBody(int servers, int mb) {
    return '将测量 $servers 个最佳服务器以及你自己线路的速度，约消耗订阅流量 $mb MB。\n\n可在设置中关闭测速。';
  }

  @override
  String get autoSpeedTrafficGo => '开始';

  @override
  String get splitDeadPath => '该路径下的文件已不存在——规则永远不会匹配';

  @override
  String get splitDeadPathFix => '点按改为按文件名匹配';
}
