import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

import '../../core/util/country_flag.dart';
import '../../l10n/gen/app_localizations.dart';

/// Ячейка с флагом страны по имени сервера (эмодзи-флаги не рендерятся на Windows,
/// поэтому вытаскиваем ISO-код и рисуем картинку). Без флага — плейсхолдер:
/// у обычного сервера 🌐 глобус, у сервера с АВТОВЫБОРОМ — надпись «АВТО» (#11).
class FlagCell extends StatelessWidget {
  /// Исходное имя сервера (с флаг-эмодзи).
  final String name;

  /// Сервер с автовыбором (панельный профиль): без флага показываем «АВТО».
  final bool auto;
  final double width;
  final double height;
  const FlagCell(this.name,
      {super.key, this.auto = false, this.width = 34, this.height = 24});

  @override
  Widget build(BuildContext context) {
    final iso = FlagUtil.isoFromName(name);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: scheme.surfaceContainerHighest,
      ),
      child: iso != null
          ? CountryFlag.fromCountryCode(iso, height: height, width: width)
          : auto
              ? Text(AppLocalizations.of(context).flagAuto,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: height * 0.34,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary))
              : Icon(Icons.public,
                  size: height * 0.7, color: scheme.outline),
    );
  }
}
