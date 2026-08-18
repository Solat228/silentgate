import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_nav.dart';
import 'core/settings/app_settings.dart';
import 'l10n/gen/app_localizations.dart';
import 'state/settings_controller.dart';
import 'ui/home_screen.dart';
import 'ui/widgets/vpn_active_badge.dart';

/// Затравка фирменной палитры — одна на светлую и тёмную тему.
const _seed = Color(0xFF3B82F6);

/// Тема приложения. Вынесена отдельной функцией НЕ ради красоты: так её
/// проверяет тест, не поднимая всё дерево виджетов (`app.dart` тянет за собой
/// главный экран и все провайдеры).
///
/// ⚠️ `tooltipTheme` ЗДЕСЬ — ЛЕЧЕНИЕ НАСТОЯЩЕГО ДЕФЕКТА, А НЕ КОСМЕТИКА.
/// Всплывающая подсказка Flutter по умолчанию не ограничена ни по ширине
/// (`constraints` = только `minHeight`), ни по отступам (`margin` = ноль).
/// Подсказка с абзацем текста разворачивалась во всю ширину окна и рисовалась
/// ПОД строкой списка (`preferBelow` по умолчанию `true`), накрывая соседнюю
/// строку — владелец прислал скриншот раздельного туннелирования, где
/// пояснение к серверу правила легло поверх следующего правила.
/// Длинные тексты мы переносим в `InfoTooltip` (диалог), но ограничение
/// задаётся ещё и в ТЕМЕ — чтобы дефект не вернулся через новую подсказку,
/// написанную где-нибудь ещё.
ThemeData buildAppTheme(Brightness brightness) {
  // Минимальная высота — та же, что подставляет сам Flutter по платформе
  // (`_getDefaultTooltipHeight`): задав `constraints`, мы отменяем его
  // умолчание целиком, и без этой строки подсказки на телефоне стали бы
  // ниже штатных.
  final touch = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
    scaffoldBackgroundColor:
        brightness == Brightness.dark ? const Color(0xFF0F1420) : null,
    tooltipTheme: TooltipThemeData(
      // 320 dp — ширина, на которой длинная подсказка переносится по строкам
      // вместо того, чтобы растянуться на всё окно.
      constraints: BoxConstraints(maxWidth: 320, minHeight: touch ? 32 : 24),
      // Отступ от краёв экрана: без него подсказка прилипает к границе окна и
      // у крайних строк списка обрезается.
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
  );
}

class SilentGateApp extends StatelessWidget {
  const SilentGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;

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
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: _mode(settings.themeMode),
      // Индикатор «VPN активен» живёт над всем деревом: так он работает на любом
      // экране, включая те, что появятся позже, и его не нужно вставлять в
      // каждый Scaffold по отдельности.
      // Именно общий экземпляр: MaterialApp пересобирается на смену темы и
      // языка, а новый наблюдатель начал бы счёт с нуля и потерял глубину.
      navigatorObservers: [NavDepthObserver.instance],
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
