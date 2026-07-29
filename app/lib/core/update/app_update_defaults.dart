import 'dart:io' show Platform;

/// Адрес проверки обновлений — РАЗНЫЙ для платформ.
///
/// ⚠️ Файл намеренно почти без импортов (только `Platform` из `dart:io`).
/// `AppSettings` нужна отсюда одна константа, а импорт всего `app_update.dart`
/// тянул за собой цепочку
/// `app_update → app_log → app_paths → package:path_provider → package:flutter
/// → dart:ui`, из-за чего консольные генераторы конфигов
/// (`dart run tool/emit_*.dart`) падали с «Dart library 'dart:ui' is not
/// available on this platform». `dart:io` этой проблемы не создаёт.
///
/// ⚠️ Почему адреса разные. Один эндпоинт на все платформы отдавал ссылку на
/// Windows-установщик (`SilentGateSetup.exe`), и Android предлагал скачать
/// `.exe` — установить его на телефоне нельзя в принципе. Теперь у платформ
/// свои пути, и ответ каждого содержит подходящий артефакт.
///
/// Панель (`silentgate.lol`) — основной источник: она знает про подписки и
/// может отдавать разные версии разным пользователям. GitHub Releases —
/// запасной: работает, даже когда панель недоступна, и не требует от неё
/// раздавать 76-мегабайтные файлы.
const _panelBase = 'https://silentgate.lol/api';

/// Проверка обновлений на панели. Путь зависит от платформы.
String get kDefaultAppUpdateEndpoint =>
    Platform.isAndroid ? '$_panelBase/app-version-android' : '$_panelBase/app-version';

/// Запасной источник — релизы GitHub.
///
/// Отдаёт `tag_name` и список файлов; клиент выбирает свой по имени
/// (`*-arm64-v8a.apk` для Android, `SilentGateSetup.exe` для Windows).
const kGithubReleasesApi =
    'https://api.github.com/repos/Solat228/silentgate/releases/latest';

/// Страница релизов для человека — её открывает кнопка «Скачать».
const kGithubReleasesPage =
    'https://github.com/Solat228/silentgate/releases/latest';

/// Имя артефакта текущей платформы в релизе GitHub.
///
/// Android-сборки разделены по ABI: на телефон нужен `arm64-v8a`
/// (`armeabi-v7a` мы не выпускаем — под него не собрано ядро, см.
/// `android/app/build.gradle.kts`).
String get kPlatformAssetHint =>
    Platform.isAndroid ? 'arm64-v8a.apk' : 'Setup.exe';
