import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

import '../../core/util/country_flag.dart';
import '../../l10n/gen/app_localizations.dart';

/// Ячейка с флагом страны по имени сервера (эмодзи-флаги не рендерятся на Windows,
/// поэтому вытаскиваем ISO-код и рисуем картинку). Без флага — плейсхолдер:
/// у обычного сервера 🌐 глобус, у сервера с АВТОВЫБОРОМ — надпись «АВТО» (#11).
///
/// Мост (сервер с отдельными странами входа и выхода) несёт в имени ДВА
/// флаг-эмодзи подряд — тогда рисуем оба в одном прямоугольнике, разрезанном
/// по диагонали: страна входа сверху-слева, страна выхода снизу-справа.
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
    final isoCodes = FlagUtil.isoCodesFromName(name);
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
      child: isoCodes.isEmpty
          ? (auto
              ? Text(AppLocalizations.of(context).flagAuto,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: height * 0.34,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary))
              : Icon(Icons.public,
                  size: height * 0.7, color: scheme.outline))
          : isoCodes.length == 1
              ? CountryFlag.fromCountryCode(isoCodes[0],
                  height: height, width: width)
              : _DiagonalFlagPair(
                  first: isoCodes[0],
                  second: isoCodes[1],
                  width: width,
                  height: height,
                ),
    );
  }
}

/// Два флага в одном прямоугольнике, разрезанном по диагонали:
/// [first] (страна входа) занимает верхний левый треугольник,
/// [second] (страна выхода) — нижний правый.
class _DiagonalFlagPair extends StatelessWidget {
  final String first;
  final String second;
  final double width;
  final double height;

  const _DiagonalFlagPair({
    required this.first,
    required this.second,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipPath(
          clipper: _TopLeftTriangleClipper(),
          child: CountryFlag.fromCountryCode(first,
              height: height, width: width),
        ),
        ClipPath(
          clipper: _BottomRightTriangleClipper(),
          child: CountryFlag.fromCountryCode(second,
              height: height, width: width),
        ),
      ],
    );
  }
}

/// Верхний левый треугольник прямоугольника (диагональ из левого-нижнего
/// угла в правый-верхний).
class _TopLeftTriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Нижний правый треугольник — дополнение к [_TopLeftTriangleClipper].
class _BottomRightTriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
