import 'dart:io';

/// Идентификация приложения в сети. Держать версию синхронно с `pubspec.yaml`
/// (и с `versionName` в Gradle, когда появится Android-сборка) — паритет
/// стережёт тест `test/app_info_test.dart`.
class AppInfo {
  static const name = 'SilentGate';
  static const version = '1.18.8';

  /// Номер сборки/патча после `+` в `pubspec.yaml` (`version: X.Y.Z+N`).
  /// Держится синхронно с `pubspec.yaml` и проверяется `test/app_info_test.dart`:
  /// на Android при `--split-per-abi` системный `versionCode` сдвинут на ABI
  /// (`2000 + N` для arm64, `4000 + N` для x86_64), поэтому честный номер `+N`
  /// для «О программе» и сравнения сборок хранится здесь.
  static const buildNumber = 103;

  /// Необязательный суффикс пре-релиза/патча (`beta.1`, `rc.1`, `hotfix.2`),
  /// передаваемый при сборке (`--dart-define=SILENTGATE_PRERELEASE=...`).
  static const preRelease =
      String.fromEnvironment('SILENTGATE_PRERELEASE', defaultValue: '');

  /// Короткий хеш коммита Git (`--dart-define=SILENTGATE_GIT_SHA=...`),
  /// вшиваемый при релизной сборке для точного контроля версий в «О программе».
  static const gitCommit =
      String.fromEnvironment('SILENTGATE_GIT_SHA', defaultValue: '');

  /// Имя ветки Git (`--dart-define=SILENTGATE_GIT_BRANCH=...`), если передано.
  static const gitBranch =
      String.fromEnvironment('SILENTGATE_GIT_BRANCH', defaultValue: '');

  /// Дополнительный список патчей коммитов (`|`-разделённый), если передан при сборке.
  static const gitPatchLog =
      String.fromEnvironment('SILENTGATE_GIT_PATCHES', defaultValue: '');

  /// Сводка патчей, вошедших в текущую сборку `1.18.7+102` (показывается по нажатию
  /// на строку версии в «О программе» вместе с ревизией Git).
  static const List<String> builtInPatchesRu = [
    '+103 · Быстрые отчёты поддержки в 1 клик без обязательного описания, чипы категорий, отправка обезличенной копии разработчику с предпросмотром и кнопкой во встроенном чате поддержки; работа YouTube на узлах обхода БС (IPv4-only + отказ QUIC и DNS HTTPS/SVCB); строго клиентская сборка релея БС',
    '+102 · Вставка файлов (.txt/.json) и мульти-ссылок через Ctrl+V в отдельную локальную подписку; рабочая прослойка обхода блокировок (Zapret / DPI) мимо Wintun с проверкой и автоподбором стратегий; прокачанный API автоматизации (порт Умного Авто 10818, до 250 закреплённых портов во всех режимах захвата и при выключенном VPN, все профили Авто с дедупликацией Xray, режимы пароля, управление подписками); фикс гонки Wi-Fi/Cellular на Android 15/16 и ложных обрывов ТСПУ',
    '+101 · Сортировка и вложение серверов по флагу в страновые Авто-серверы, выбор папок стран и «🌉 Мосты» как виртуальных Авто-серверов (включая «Через сервер»), исправление падения chromehttp2 в whitelist-bypass и пересоздания TUN по domain_suffix',
    '+100 · Сохранение позиции и состояния ярлыка SilentGate на Рабочем столе Windows при обновлении и переустановке (без пересоздания .lnk поверх существующего)',
    '+99 · Реальный пинг в мс и замер скорости серверов БС через сам WebRTC-звонок, определение настоящего выходного IP ноды БС вместо домена площадки и 127.0.0.1:10855, кнопка закрытия (×) на всех уведомлениях и плашках прогресса',
    '+98 · Выбор профилей «🎬 Авто (YouTube)» / «Авто» и узлов XHTTP отдельным выходом правил («Через сервер») через изолированный мульти-мост Xray -> sing-box; исправлен клик по капче в WebView2 на русской локали Windows',
    '+97 · Единый авто-режим ссылок ВК (DataChannel с проверкой потока > 64 КБ и бесшовным откатом на Video + KCP), исправление 64 КБ буфера SCTP и многопакетного QUIC UDP в релее БС, встроенное окно капчи ВК (WebView2 / Android WebView) с фоновым автокликом чекбокса и кэшированием токена, версия в шапке Android',
    '+96 · Исправлены падение Go 1.27 HTTP/2 в релее белых списков (librelay.so и whitelist-bypass.exe), открытие капчи VK / входа Blink через штатный браузер на Android и Windows, подсети TURN VK Cloud (90.156.0.0/16) и остановка предыдущего релея при смене сервера',
    '+95 · Пауза, мультивыбор протяжкой мыши (как в Telegram), ПКМ-меню и пакетные правила маршрутизации в «Открытых соединениях» и «Раздельном туннелировании»; строгая блокировка неподдерживаемых выходных узлов («Авто», XHTTP, БС) в «Через сервер»',
    '+94 · Исправлены запуск TUN с Kill Switch на быстрых SSD при правилах приложений по имени, зависание видео и превью YouTube в TUN (откат постквантового QUIC на TCP и нормализация панельных профилей Авто), автопереподключение и очистка системного прокси при переключении в TUN',
    '+93 · Исправлены локальный DNS при строгой маршрутизации TUN, таймаут адаптера Wintun (15 с), автогруппировка «Авто Белые списки», бесшовное переиспользование форвардера DNS и лог xray.log в отчёте; добавлен быстрый выбор сервисов в раздельном туннелировании',
    '+92 · Исправлены перезапуск туннеля («Перезагрузить VPN»), ложные уведомления «Маршруты обновились» и очистка portable.txt в установщике',
    '+91 · Отображение полного номера сборки (+N), суффиксов и ревизии Git в «О программе», окне и обновлениях',
    '+90 · Монитор открытых соединений в реальном времени (VPN / Блокируются / Прямые) и детектор расхождения маршрутов',
    '+90 · Живой поиск сайтов в раздельном туннелировании, подсветка дублей и виртуальная группировка поддоменов',
    '+90 · Сохранение скачанного обновления между перезапусками, зеркало silentgate.lol и предупреждение о трафике VPN',
    '+90 · Мгновенная отмена подключения, сквозная проверка HTTP 204 при старте и жёсткие таймауты шагов Connect',
    '+90 · Поддержка расширенного буфера обмена Windows (Win+V) и истории буфера Android во всех полях ввода',
    '+90 · Движок обхода белых списков (WebRTC relay: VK, Telemost, WB Stream, DION, Bitrix24, Blink)',
  ];

  static const List<String> builtInPatchesEn = [
    '+103 · 1-click support reports without mandatory text description, quick category chips, optional anonymized developer copy with preview and in-app support chat report button; fix YouTube over Whitelist-Bypass tunnels (IPv4-only + QUIC and DNS HTTPS/SVCB suppression); strictly client-only relay binaries',
    '+102 · Clipboard file (CF_HDROP) & multi-link Ctrl+V import into dedicated local subscriptions; rewritten Zapret / DPI bypass bound to physical NIC with live verifier and auto-tuner; upgraded Automation API (Smart Auto port 10818, up to 250 sticky ports across all capture modes and when disconnected, Auto profiles with Xray outbound deduplication, proxy auth modes, subscription endpoints); Android 15/16 Wi-Fi/Cellular default interface fix and TSPU false-reconnect guard',
    '+101 · Flag-based nesting into Country Auto-servers, selectable Country and "🌉 Bridges" folders as virtual Auto-servers (including "Via server"), fix chromehttp2 nil-panic in whitelist-bypass and TUN recreation on domain_suffix update',
    '+100 · Preserve Desktop shortcut position and state during Windows updates and reinstalls without deleting/recreating existing .lnk',
    '+99 · Real call-through RTT ping (ms) and speed test for Whitelist-Bypass servers, real exit IP detection instead of platform domain and 127.0.0.1:10855, close button (×) on every toast and progress notification',
    '+98 · Support "🎬 Auto (YouTube)" / panel Auto profiles and XHTTP nodes as secondary per-rule exits ("Via server") over isolated Xray -> sing-box SOCKS5 bridges; fix WebView2 captcha click on comma-decimal Windows locales',
    '+97 · Single-link VK auto-mode (DataChannel with > 64 KB stream verification and seamless fallback to Video + KCP), SCTP 64 KB frame chunking and multi-packet QUIC UDP in whitelist-bypass, embedded in-app VK captcha WebView (WebView2 / Android WebView) with background auto-checkbox click and persistent token cache, version in Android header',
    '+96 · Fix Go 1.27 HTTP/2 crash in whitelist-bypass relay (librelay.so and whitelist-bypass.exe), native browser launch for VK captcha / Blink login on Android and Windows, VK Cloud TURN CIDRs (90.156.0.0/16), and clean relay teardown on server switch',
    '+95 · Pause freeze, Telegram-style mouse drag multi-select, right-click menu, and batch routing actions in Open Connections and Split Tunneling; strict blocking dialog for unsupported secondary exit nodes ("Auto", XHTTP, BS) in "Via server"',
    '+94 · Fix TUN + Kill Switch startup race on fast SSDs with by-name app rules, YouTube video/thumbnail stalls in TUN (post-quantum QUIC fallback to TCP and Auto panel profile normalization), and immediate reconnect + WinINET proxy cleanup on capture mode switch',
    '+93 · Fix LAN DNS under strict_route TUN, Wintun open timeout (15s), "Auto Whitelists" grouping, seamless direct-DNS port reuse, and xray.log in support reports; add quick service presets in split tunneling',
    '+92 · Fix seamless tunnel reload ("Reload VPN"), false "Routes updated" prompts, and stale portable.txt cleanup in installer',
    '+91 · Full build number (+N), pre-release suffixes, and Git revision in About, window title, and Updates',
    '+90 · Real-time open connections monitor (VPN / Blocked / Direct) and live route mismatch detector',
    '+90 · Split-tunnel site live search, duplicate highlight, and virtual subdomain grouping',
    '+90 · Persistent staged app updates across restarts, silentgate.lol mirror, and VPN traffic warning',
    '+90 · Instant connect cancel, initial HTTP 204 channel verification, and bounded Connect step timeouts',
    '+90 · Windows Clipboard History (Win+V) and Android rich clipboard support across all text fields',
    '+90 · Whitelist-bypass engine (WebRTC relay: VK, Telemost, WB Stream, DION, Bitrix24, Blink)',
  ];

  static List<String> get builtInPatches => builtInPatchesRu;

  /// Полная версия с суффиксом пре-релиза (если задан) и номером сборки `+N`,
  /// например `1.18.0+91` или `1.18.0-beta.1+91`.
  static String get fullVersion => preRelease.isEmpty
      ? '$version+$buildNumber'
      : '$version-$preRelease+$buildNumber';

  /// Полная версия для экрана «Обновления» и отчёта поддержки: включает `+N`
  /// и короткий хеш коммита Git, если он был вшит при сборке.
  static String get displayVersion =>
      gitCommit.isEmpty ? fullVersion : '$fullVersion ($gitCommit)';

  /// Приводит `PackageInfo.buildNumber` к реальному номеру `+N` из `pubspec.yaml`.
  /// На Android `--split-per-abi` прибавляет `1000 * abiIndex` (`2091`, `4091`).
  static String normalizeRuntimeBuildNumber(
    String? rawBuildNumber, {
    bool? isAndroid,
  }) {
    final trimmed = (rawBuildNumber ?? '').trim();
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed <= 0) return '$buildNumber';
    final android = isAndroid ?? Platform.isAndroid;
    if (android && parsed >= 1000) {
      final mod = parsed % 1000;
      if (mod > 0) return '$mod';
    }
    return '$parsed';
  }

  /// Форматирует строку версии для раздела «О программе»:
  /// сохраняет все суффиксы версии, обязательно добавляет `+N` и ревизию Git.
  static String formatAboutVersion({
    String? runtimeVersion,
    String? runtimeBuildNumber,
    String? preReleaseOverride,
    String? gitCommitOverride,
    bool? isAndroid,
  }) {
    var base = (runtimeVersion ?? '').trim();
    if (base.startsWith('v') || base.startsWith('V')) {
      base = base.substring(1);
    }
    if (base.isEmpty) base = version;

    // Если сам runtimeVersion уже содержит `+N`, отделяем его, чтобы не задвоить.
    String? embeddedBuild;
    final plusIdx = base.indexOf('+');
    if (plusIdx >= 0) {
      embeddedBuild = base.substring(plusIdx + 1).trim();
      base = base.substring(0, plusIdx);
    }

    final pre = (preReleaseOverride ?? preRelease).trim();
    if (pre.isNotEmpty && !base.contains('-')) {
      base = '$base-$pre';
    }

    final resolvedBuild = (embeddedBuild != null && embeddedBuild.isNotEmpty)
        ? embeddedBuild
        : normalizeRuntimeBuildNumber(
            runtimeBuildNumber,
            isAndroid: isAndroid,
          );

    final sha = (gitCommitOverride ?? gitCommit).trim();
    final withBuild = 'v$base+$resolvedBuild';
    return sha.isEmpty ? withBuild : '$withBuild ($sha)';
  }

  /// Все записи о патчах для диалога контроля версий в «О программе».
  static List<String> patchEntriesForLocale([String localeCode = 'ru']) {
    final base =
        localeCode.toLowerCase().startsWith('ru') ? builtInPatchesRu : builtInPatchesEn;
    final fromGit = gitPatchLog
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (fromGit.isEmpty) return base;
    return [...fromGit, ...base];
  }

  static List<String> get patchEntries => patchEntriesForLocale('ru');

  /// Канал СБОРКИ — свойство конкретного exe/apk, а не то, что можно
  /// прочитать из настроек или манифеста обновлений.
  ///
  /// ⚠️ ПОЧЕМУ ИМЕННО ТАК. Признак беты у уже установленной сборки нельзя
  /// решить полем ответа сервера: манифест приходит уже ПОСЛЕ того, как
  /// человек эту бету поставил, а «О программе» должно честно говорить,
  /// что у него за файл, даже без единого сетевого запроса и даже если
  /// человек ни разу не открывал раздел обновлений. Задаётся на сборке
  /// (`build-exe.bat`/`build-apk.bat` → `--dart-define=SILENTGATE_CHANNEL=beta`),
  /// обычная сборка канал не задаёт вовсе — `String.fromEnvironment` тогда
  /// даёт пустую строку, и `isBeta` остаётся `false`.
  static const channel =
      String.fromEnvironment('SILENTGATE_CHANNEL', defaultValue: '');

  /// Это бета-сборка (см. [channel]).
  static bool get isBeta => channel == 'beta';

  /// Метка платформы в User-Agent. Панель Remnawave сопоставляет только ИМЯ
  /// (правило `user-agent CONTAINS SilentGate`), поэтому суффикс на выбор
  /// формата ответа не влияет — он нужен для аналитики и отчётов поддержки.
  static String get platformTag {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// User-Agent запроса подписки: всегда «Имя/версия (платформа)».
  /// Панель (Remnawave) по нему выбирает формат ответа — правило в разделе
  /// Templates → Response Rules сопоставляет имя и отдаёт XRAY_JSON.
  ///
  /// ⚠️ Формат «Имя/версия» обязателен, сверка на панели регистрозависимая:
  /// при отклонении от него придёт base64 вместо XRAY_JSON, и клиент молча
  /// потеряет профили «Авто» и hysteria2-узлы.
  static String get userAgent => '$name/$version ($platformTag)';
}
