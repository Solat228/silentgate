import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';
import 'app_locales.dart';

/// Переводы там, где нет `BuildContext`.
///
/// Движок работает вне дерева виджетов, но текст, который он отдаёт наружу
/// (страница «сайт заблокирован»), пользователь читает — и читает на своём
/// языке. Захардкоженный русский в приложении с десятью локалями — это регресс,
/// который не видно из кода: он проявляется только у того, кто выбрал другой
/// язык.
///
/// [languageCode] — значение `AppSettings.languageCode`; пусто = язык системы,
/// как и в `MaterialApp` (см. `app.dart`).
Future<AppLocalizations> localizationsFor(String languageCode) {
  return AppLocalizations.delegate.load(_localeFor(languageCode));
}

Locale _localeFor(String languageCode) {
  final code = languageCode.isNotEmpty
      ? languageCode
      // `Platform.localeName` — это `ru_RU.UTF-8`/`ru-RU`; нужен только язык.
      : Platform.localeName.split(RegExp('[_.-]')).first;

  for (final s in supportedLanguages) {
    if (s.code == code) return Locale(s.code);
  }
  // Тот же фолбэк, что и у `localeResolutionCallback`: английский, а не первый
  // язык списка (там русский — он не был бы понятнее случайному пользователю).
  return const Locale('en');
}
