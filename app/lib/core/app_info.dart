import 'dart:io';

/// Идентификация приложения в сети. Держать версию синхронно с `pubspec.yaml`
/// (и с `versionName` в Gradle, когда появится Android-сборка) — паритет
/// стережёт тест `test/app_info_test.dart`.
class AppInfo {
  static const name = 'SilentGate';
  static const version = '1.18.0';

  /// Номер сборки/патча после `+` в `pubspec.yaml` (`version: X.Y.Z+N`).
  /// Держится синхронно с `pubspec.yaml` и проверяется `test/app_info_test.dart`:
  /// на Android при `--split-per-abi` системный `versionCode` сдвинут на ABI
  /// (`2000 + N` для arm64, `4000 + N` для x86_64), поэтому честный номер `+N`
  /// для «О программе» и сравнения сборок хранится здесь.
  static const buildNumber = 91;

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

  /// Сводка патчей, вошедших в текущую сборку `1.18.0+91` (показывается по нажатию
  /// на строку версии в «О программе» вместе с ревизией Git).
  static const List<String> builtInPatchesRu = [
    '+91 · Отображение полного номера сборки (+N), суффиксов и ревизии Git в «О программе», окне и обновлениях',
    '+90 · Монитор открытых соединений в реальном времени (VPN / Блокируются / Прямые) и детектор расхождения маршрутов',
    '+90 · Живой поиск сайтов в раздельном туннелировании, подсветка дублей и виртуальная группировка поддоменов',
    '+90 · Сохранение скачанного обновления между перезапусками, зеркало silentgate.lol и предупреждение о трафике VPN',
    '+90 · Мгновенная отмена подключения, сквозная проверка HTTP 204 при старте и жёсткие таймауты шагов Connect',
    '+90 · Поддержка расширенного буфера обмена Windows (Win+V) и истории буфера Android во всех полях ввода',
    '+90 · Движок обхода белых списков (WebRTC relay: VK, Telemost, WB Stream, DION, Bitrix24, Blink)',
  ];

  static const List<String> builtInPatchesEn = [
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
