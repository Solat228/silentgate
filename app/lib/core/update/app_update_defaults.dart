/// Адрес проверки обновлений по умолчанию.
///
/// ⚠️ Вынесен в отдельный файл БЕЗ единого импорта намеренно. `AppSettings`
/// нужна отсюда ровно одна константа, но импорт всего `app_update.dart` тянул
/// за собой цепочку
/// `app_update → app_log → app_paths → package:path_provider → package:flutter
/// → dart:ui`,
/// из-за чего консольные генераторы конфигов (`dart run tool/emit_*.dart`)
/// падали с «Dart library 'dart:ui' is not available on this platform» и
/// валидировать конфиги ядром было нечем.
///
/// Поэтому: сюда можно класть только то, что не требует импортов.
const kDefaultAppUpdateEndpoint = 'https://silentgate.lol/api/app-version';
