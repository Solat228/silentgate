import 'dart:io' show Platform;

/// Источник обновлений — GITHUB RELEASES, ОДИН НА ОБЕ ПЛАТФОРМЫ.
///
/// ⚠️ Файл намеренно почти без импортов (только `Platform` из `dart:io`).
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

/// Последний НЕ черновиковый и НЕ предварительный релиз: `/releases/latest`
/// исключает их сам, отдельно фильтровать не нужно.
const kGithubReleasesApi =
    'https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest';

/// Страница релизов для человека — её открывает кнопка «Скачать».
const kGithubReleasesPage =
    'https://github.com/$kGithubOwner/$kGithubRepo/releases/latest';

/// Имя артефакта текущей платформы в релизе GitHub.
///
/// Android-сборки разделены по ABI: на телефон нужен `arm64-v8a`
/// (`armeabi-v7a` мы не выпускаем — под него не собрано ядро, см.
/// `android/app/build.gradle.kts`). На Windows это установщик Inno Setup.
String get kPlatformAssetHint =>
    Platform.isAndroid ? 'arm64-v8a.apk' : 'Setup.exe';
