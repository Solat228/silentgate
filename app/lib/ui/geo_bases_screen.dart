import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import 'widgets/geo_bases_section.dart';

/// Гео-базы маршрутизации — отдельным экраном.
///
/// ⚠️ ПОЧЕМУ НЕ ПРЯМО В НАСТРОЙКАХ, КАК БЫЛО. Раздел занимал полэкрана: четыре
/// абзаца пояснений, две строки о файлах, путь к каталогу, дата проверки,
/// сведения о резервной копии и две кнопки. Всё это лежало между выбором режима
/// захвата и настройками туннеля — то есть между двумя вещами, которые
/// пользователь меняет часто, вклинивалось то, что трогают раз в полгода.
/// Просьба владельца 20.08.2026: «спрячь геобазы под отдельное подменю».
///
/// Содержимое не переписано, а перенесено целиком: [GeoBasesSection] — тот же
/// виджет, и его тесты (`test/geo_bases_ui_test.dart`) продолжают проверять
/// ровно то, что видит человек.
class GeoBasesScreen extends StatelessWidget {
  const GeoBasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.geoTitle)),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: GeoBasesSection(),
      ),
    );
  }
}
