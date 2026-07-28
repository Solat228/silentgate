import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_nav.dart';
import 'core/settings/app_settings.dart';
import 'l10n/gen/app_localizations.dart';
import 'state/settings_controller.dart';
import 'ui/home_screen.dart';
import 'ui/widgets/vpn_active_badge.dart';

class SilentGateApp extends StatelessWidget {
  const SilentGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    const seed = Color(0xFF3B82F6);

    return MaterialApp(
      title: 'SilentGate',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      // Локализация: пустой languageCode — следовать ЯЗЫКУ СИСТЕМЫ (locale: null),
      // иначе форсируем выбранный язык.
      locale: settings.languageCode.isEmpty
          ? null
          : Locale(settings.languageCode),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Сопоставление локали: язык системы, если поддерживается, иначе —
      // английский (нейтральный фолбэк, а не первый в списке). Форс-выбор языка
      // приходит сюда как [locale] и матчится по languageCode.
      localeResolutionCallback: (locale, supported) {
        if (locale != null) {
          for (final s in supported) {
            if (s.languageCode == locale.languageCode) return s;
          }
        }
        return const Locale('en');
      },
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0F1420),
      ),
      themeMode: _mode(settings.themeMode),
      // Индикатор «VPN активен» живёт над всем деревом: так он работает на любом
      // экране, включая те, что появятся позже, и его не нужно вставлять в
      // каждый Scaffold по отдельности.
      navigatorObservers: [NavDepthObserver()],
      builder: (context, child) =>
          VpnActiveBadge(child: child ?? const SizedBox.shrink()),
      home: const HomeScreen(),
    );
  }

  ThemeMode _mode(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }
}
