import 'package:flutter/widgets.dart';

/// Один поддерживаемый язык интерфейса.
class AppLanguage {
  /// Код локали: `ru` / `en` / `es`.
  final String code;

  /// Самоназвание языка (endonym): «Русский», «English», «Español».
  final String endonym;

  /// Английское название языка — по нему сортируется меню (алфавит по-английски).
  final String englishName;

  /// ISO 3166-1 alpha-2 код страны для флага (пакет country_flags).
  final String flag;

  const AppLanguage(this.code, this.endonym, this.englishName, this.flag);

  Locale get locale => Locale(code);
}

/// Поддерживаемые языки. Русский — база.
/// ДОБАВЛЕНИЕ языка: строчка сюда + файл `lib/l10n/app_<code>.arb`, затем
/// `flutter gen-l10n`. Порядок в этом списке НЕ важен (меню сортируется по
/// [languagesSortedByName]); первый — русский как база/фолбэк логики.
const supportedLanguages = <AppLanguage>[
  AppLanguage('ru', 'Русский', 'Russian', 'RU'),
  AppLanguage('en', 'English', 'English', 'US'),
  AppLanguage('es', 'Español', 'Spanish', 'ES'),
  AppLanguage('fr', 'Français', 'French', 'FR'),
  AppLanguage('de', 'Deutsch', 'German', 'DE'),
  AppLanguage('pt', 'Português', 'Portuguese', 'PT'),
  AppLanguage('tr', 'Türkçe', 'Turkish', 'TR'),
  AppLanguage('ar', 'العربية', 'Arabic', 'SA'), // RTL
  AppLanguage('fa', 'فارسی', 'Persian', 'IR'), // RTL
  AppLanguage('zh', '中文', 'Chinese', 'CN'),
];

/// Языки для меню — по алфавиту (английские названия).
List<AppLanguage> get languagesSortedByName {
  final list = [...supportedLanguages];
  list.sort((a, b) => a.englishName.compareTo(b.englishName));
  return list;
}

/// Язык по коду (или null, если не поддерживается).
AppLanguage? languageByCode(String code) {
  for (final l in supportedLanguages) {
    if (l.code == code) return l;
  }
  return null;
}
