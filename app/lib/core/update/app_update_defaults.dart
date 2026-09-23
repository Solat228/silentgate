import 'dart:io' show File, Platform;

/// Источник обновлений — GITHUB RELEASES, ОДИН НА ОБЕ ПЛАТФОРМЫ.
///
/// ⚠️ Файл намеренно почти без импортов (только `dart:io`).
/// `AppSettings` нужна отсюда одна константа, а импорт всего `app_update.dart`
/// тянул за собой цепочку
/// `app_update → app_log → app_paths → package:path_provider → package:flutter
/// → dart:ui`, из-за чего консольные генераторы конфигов
/// (`dart run tool/emit_*.dart`) падали с «Dart library 'dart:ui' is not
/// available on this platform». `dart:io` этой проблемы не создаёт.
///
/// ⚠️ ПОЧЕМУ ИМЕННО GITHUB, А НЕ ПАНЕЛЬ. Раньше основным источником была панель
/// (`silentgate.lol/api/app-version` и `…-android`), а GitHub — запасным. На
/// практике это не работало ни на одной платформе: андроидного эндпоинта на
/// панели не существует до сих пор, поэтому телефон молча не находил ничего
/// вовсе, а поле «Эндпоинт версии» в настройках предлагало пользователю
/// чинить это руками — то есть перекладывало на него задачу, которую он решить
/// не может. Один источник, одинаковый для платформ и не зависящий от
/// доступности панели, честнее двух ненастроенных.
///
/// ⚠️ ЧЕГО ЭТОТ ИСТОЧНИК НЕ УМЕЕТ: он не знает про подписки и отдаёт всем одно
/// и то же. Разные версии разным пользователям — то, ради чего заводили панель,
/// — здесь невозможны. Если это когда-нибудь понадобится, панель придётся
/// вернуть ВТОРЫМ источником, а не заменой.
const kGithubOwner = 'Solat228';
const kGithubRepo = 'silentgate';

/// База API GitHub в боевом режиме.
const kGithubApiBase = 'https://api.github.com';

/// ТЕСТОВЫЙ STAND: подмена базы API обновлений.
///
/// Нужна, чтобы прогнать самообновление целиком (проверка → закачка →
/// подпись → установка) в VM и эмуляторе на своём сервере с тестовым
/// релизом, не выкладывая его на GitHub.
///
/// * **Windows** — переменная окружения [kUpdateApiEnvVar].
/// * **Android** — файл `<filesDir>/SilentGate/`[kUpdateApiOverrideFileName]
///   (переменных окружения у приложения там нет). Читается
///   [loadUpdateApiOverrideFrom] — сам этот файл не знает, где каталог данных:
///   путь даёт `AppPaths`, а он тянет Flutter (см. предупреждение выше).
///
/// ⚠️ OVERRIDE МЕНЯЕТ ТОЛЬКО АДРЕС. Публичный ключ, которым проверяется
/// подпись манифеста, живёт в `update_pubkey.dart` константой, и отсюда до него
/// не дотянуться ничем — поэтому подменённый сервер может отдать лишь то, что
/// подписано нашим ключом. Ровно по этой же причине под override допустим
/// `http://` (см. [isUpdateUrlAllowed]): целостность держит подпись, а не TLS.
const kUpdateApiEnvVar = 'SILENTGATE_UPDATE_API';

/// Имя файла override на Android (в корне каталога данных `AppPaths`).
const kUpdateApiOverrideFileName = 'update_api.txt';

String? _apiOverride;
bool _apiOverrideResolved = false;

/// База API из тестового override (без хвостового `/`) либо `null`.
///
/// На Windows лениво читается из окружения при первом обращении; на Android
/// остаётся `null`, пока не отработал [loadUpdateApiOverrideFrom].
String? get kUpdateApiOverride {
  if (!_apiOverrideResolved) {
    _apiOverrideResolved = true;
    _apiOverride = Platform.isAndroid
        ? null
        : normalizeUpdateApiBase(Platform.environment[kUpdateApiEnvVar]);
  }
  return _apiOverride;
}

/// Включён ли тестовый override (для плашки в интерфейсе и допуска `http://`).
bool get kUpdateApiOverridden => kUpdateApiOverride != null;

/// Приводит базу к виду `scheme://host[:port][/path]` без хвостового `/`.
/// Не `http(s)` или без хоста — `null`: мусор в файле не должен уводить
/// проверку обновлений «куда-то», он просто не включает override.
String? normalizeUpdateApiBase(String? raw) {
  if (raw == null) return null;
  // Первая непустая строка: файл на Android пишут руками через adb, и хвостовой
  // перевод строки (или CRLF) там почти неизбежен.
  final line = raw
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return null;
  final uri = Uri.tryParse(line);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  var s = line;
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Android: прочитать override из `<dataDir>/`[kUpdateApiOverrideFileName].
/// [dataDir] — корень данных приложения (`AppPaths.supportDir()`), то есть
/// `<filesDir>/SilentGate`. Файла нет или он не читается — override снят.
/// Возвращает действующую базу (или `null`).
String? loadUpdateApiOverrideFrom(String dataDir) {
  String? base;
  try {
    final f = File('$dataDir${Platform.pathSeparator}$kUpdateApiOverrideFileName');
    if (f.existsSync()) base = normalizeUpdateApiBase(f.readAsStringSync());
  } catch (_) {
    base = null;
  }
  _apiOverride = base;
  _apiOverrideResolved = true;
  return base;
}

/// ТОЛЬКО ДЛЯ ТЕСТОВ: задать override напрямую (значение проходит ту же
/// нормализацию, что окружение и файл). `package:meta` сюда не импортируется
/// нарочно — см. предупреждение в начале файла.
void debugSetUpdateApiOverride(String? base) {
  _apiOverride = normalizeUpdateApiBase(base);
  _apiOverrideResolved = true;
}

/// ТОЛЬКО ДЛЯ ТЕСТОВ: вернуть ленивое чтение окружения.
void debugResetUpdateApiOverride() {
  _apiOverride = null;
  _apiOverrideResolved = false;
}

String get _apiBase => kUpdateApiOverride ?? kGithubApiBase;

/// Допустим ли адрес для закачки обновления (актив, манифест, подпись).
///
/// ⚠️ `https://` — всегда; `http://` — ТОЛЬКО под тестовым override. В боевом
/// режиме открытый канал отвергается даже при том, что подпись всё равно
/// проверяется: подмена по дороге дала бы как минимум отказ обновления вместо
/// обновления, а ради стенда TLS ослаблять незачем. Иные схемы — никогда.
bool isUpdateUrlAllowed(String? url) {
  if (url == null) return false;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  if (uri.scheme == 'https') return true;
  if (uri.scheme == 'http') return kUpdateApiOverridden;
  return false;
}

/// Последний НЕ черновиковый и НЕ предварительный релиз: `/releases/latest`
/// исключает их сам, отдельно фильтровать не нужно.
///
/// Геттер, а не константа: база меняется тестовым override.
String get kGithubReleasesApi =>
    '$_apiBase/repos/$kGithubOwner/$kGithubRepo/releases/latest';

/// ⚠️ СПИСОК релизов — отдельный адрес, и он ВКЛЮЧАЕТ пре-релизы и черновики.
/// `/releases/latest` их намеренно прячет (см. выше), а бета-каналу и списку
/// «прежних версий» нужно как раз обратное: GitHub отдаёт их в порядке ОТ
/// НОВЫХ К СТАРЫМ по дате публикации, поэтому первый элемент — это и есть
/// «новейшее, включая беты», а весь список годится для отката версии.
/// Черновики (`draft: true`) фильтруются на разборе — они не опубликованы,
/// показывать их как доступную версию нечестно.
String get kGithubReleasesListApi =>
    '$_apiBase/repos/$kGithubOwner/$kGithubRepo/releases';

/// Страница релизов для человека — её открывает кнопка «Скачать».
const kGithubReleasesPage =
    'https://github.com/$kGithubOwner/$kGithubRepo/releases/latest';

/// ЗАПАСНОЙ ИСТОЧНИК — НАШ САЙТ.
///
/// ⚠️ Заведён по живому случаю: у владельца `api.github.com` не открывается
/// вовсе — TLS-рукопожатие падает с несовпадением имени в сертификате
/// (воспроизведено в чистой VM без VPN, при живом `github.com`). Клиентом
/// пользуются ровно там, где интернет фильтруют, поэтому «основной источник
/// недоступен» здесь обычное дело.
///
/// Путь ОДИН на обе платформы: разбор ответа выбирает артефакт сам. Прежняя
/// разводка `app-version` / `app-version-android` не нужна — и андроидного
/// эндпоинта на панели так и не создали, из-за чего телефон молча не находил
/// ничего вовсе.
///
/// Что сервер обязан отдавать — `docs/APP_UPDATE_SERVER.md`.
const kPanelUpdateEndpoint = 'https://silentgate.lol/api/app-version';

/// ЗАПАСНОЙ ИСТОЧНИК БЕТА-КАНАЛА — тот же сайт, отдельный путь.
///
/// ⚠️ НЕ ПУТАТЬ с [kPanelUpdateEndpoint]: тот — стабильный канал, отдаёт то же
/// самое ВСЕМ, и заводить в нём поле «бета» означало бы, что пре-релиз уедет
/// в автообновление без спроса (прямое предупреждение сайт-агента, 1.12.0).
/// Спрашивается ТОЛЬКО когда пользователь сам включил галочку «Получать
/// бета-версии» — формат тот же, что у `app-version`, см.
/// `docs/APP_UPDATE_SERVER.md`.
const kPanelBetaUpdateEndpoint = 'https://silentgate.lol/api/app-version-beta';

/// Страница загрузок для человека — открывается, когда прямой ссылки нет.
const kPanelDownloadsPage = 'https://silentgate.lol/download';

/// Суффикс имени APK под ABI устройства; `null` — сборки под эту ABI нет
/// (armeabi-v7a, x86), и подбирать «похожую» нельзя: чужая ABI установится и
/// не запустится, а versionCode у x86_64 (4000+) больше, чем у arm64 (2000+), —
/// она выглядела бы «новее».
///
/// ⚠️ ТАБЛИЦА ОДНА: `ApkInstallerAndroid.assetHintForAbi` ссылается сюда же
/// (там Flutter-импорты, поэтому живёт она здесь, а не там).
String? androidAssetHintForAbi(String? abi) {
  switch ((abi ?? '').trim().toLowerCase()) {
    case 'arm64-v8a':
      return '-arm64-v8a.apk';
    case 'x86_64':
      return '-x86_64.apk';
    default:
      return null;
  }
}

/// Хвост имени артефакта текущей платформы в релизе GitHub.
///
/// Android-сборки разделены по ABI: на телефон нужен `arm64-v8a`
/// (`armeabi-v7a` мы не выпускаем — под него не собрано ядро, см.
/// `android/app/build.gradle.kts`), эмулятору — `x86_64` (TEST-ONLY-сборка).
/// ABI не узнали ([androidAbi] пуст) — телефонная сборка, как было всегда.
/// ABI, под которую сборки нет, получает хвост, которому не соответствует
/// ни один актив: лучше «открыть страницу», чем поставить чужую ABI.
///
/// На Windows это установщик Inno Setup (`SilentGateSetup-<версия>.exe`;
/// версия из имени перед сравнением вырезается, см. `AppUpdate`).
///
/// [android] — только для тестов (по умолчанию — текущая платформа).
String platformAssetHint({String? androidAbi, bool? android}) {
  if (!(android ?? Platform.isAndroid)) return 'Setup.exe';
  final abi = (androidAbi ?? '').trim();
  if (abi.isEmpty) return 'arm64-v8a.apk';
  return androidAssetHintForAbi(abi) ?? '-${abi.toLowerCase()}.apk';
}

/// Обёртка без ABI — для мест, где её не спрашивали.
String get kPlatformAssetHint => platformAssetHint();
