import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

import '../../core/util/country_flag.dart';
import '../../l10n/gen/app_localizations.dart';

/// Ячейка с флагом страны по имени сервера (эмодзи-флаги не рендерятся на Windows,
/// поэтому вытаскиваем ISO-код и рисуем картинку). Без флага — плейсхолдер:
/// у обычного сервера 🌐 глобус, у сервера с АВТОВЫБОРОМ — надпись «АВТО» (#11).
///
/// Мост (сервер с отдельными странами входа и выхода) несёт в имени ДВА
/// флаг-эмодзи подряд — тогда ячейка шире ([kFlagPairWidthFactor]) и флаги
/// идут друг за другом через косой разрез: каждый показан С НАЧАЛА.
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
    final pair = isoCodes.length > 1;
    return Container(
      width: pair ? width * kFlagPairWidthFactor : width,
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
              : _FlagPair(
                  first: isoCodes[0],
                  second: isoCodes[1],
                  flagWidth: width,
                  height: height,
                ),
    );
  }
}

/// ⚠️ КАК РИСУЕТСЯ ПАРА ФЛАГОВ — РЕШЕНИЕ ВЛАДЕЛЬЦА 25.09.2026.
///
/// Раньше оба флага лежали в ОДНОМ прямоугольнике, разрезанном из угла в
/// угол, и второй флаг показывал свою ПРАВУЮ половину. У США уникальное —
/// звёзды в левом верхнем углу — вторым флагом не было видно вовсе: оставались
/// полосы, неотличимые от чужих. Владелец: «флаг страны показывать ВСЕГДА
/// сначала». Теперь:
///  * ячейка шире одного флага в [kFlagPairWidthFactor] раз (1.15 — выбор
///    владельца по листу превью);
///  * первый флаг — от своего левого края до разреза;
///  * второй — тоже от СВОЕГО левого края, который стоит в нижней точке
///    разреза, и до правой грани ячейки;
///  * наклон разреза — как у прежних 25 % ([kFlagPairCutOffset]).
///
/// ⚠️ НЕ ДЕЛАТЬ разрез круче: в превью наклон был меньше, и владелец прочёл это
/// как «увеличил процент разреза» — «НЕ УВЕЛИЧИВАЙ».
/// ⚠️ НЕ ВСТАВЛЯТЬ зазор между флагами: «между разрезом НЕ ВСТАВЛЯЙ ПУСТОЕ
/// ПРОСТРАНСТВО». Обе фигуры строятся по одной линии — ни щели, ни нахлёста.
///
/// ⚠️ ИСТОРИЯ, чтобы не повторить: доли 0.75 и 0.5 (03.09) делали верхний флаг
/// клином; «из угла в угол» (1.0) прятало начало второго флага.
const double kFlagPairWidthFactor = 1.15;

/// Отступ линии разреза от углов ОДНОГО флага: снизу — от левого края, сверху —
/// от правого, в долях ширины флага. Наклон линии = (1 − 2·отступ)·ширина.
const double kFlagPairCutOffset = 0.25;

/// Геометрия пары: всё в пикселях ячейки. Вынесено ради теста — картинку
/// тест не сравнит, а числа сравнит.
class FlagPairGeometry {
  /// Ширина ячейки.
  final double cellWidth;

  /// Разрез: нижняя и верхняя точки по горизонтали.
  final double cutBottom, cutTop;

  /// Левый край второго флага — нижняя точка разреза: левее нельзя (второй
  /// флаг прятал бы начало), правее — появился бы зазор.
  double get secondLeft => cutBottom;

  const FlagPairGeometry._(this.cellWidth, this.cutBottom, this.cutTop);

  factory FlagPairGeometry.of(double flagWidth) {
    final cell = flagWidth * kFlagPairWidthFactor;
    final slant = (1 - 2 * kFlagPairCutOffset) * flagWidth;
    final bottom = (cell - slant) / 2; // линия по центру ячейки
    return FlagPairGeometry._(cell, bottom, bottom + slant);
  }
}

class _FlagPair extends StatelessWidget {
  final String first;
  final String second;
  final double flagWidth;
  final double height;

  const _FlagPair({
    required this.first,
    required this.second,
    required this.flagWidth,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final g = FlagPairGeometry.of(flagWidth);
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: g.cellWidth,
          height: height,
          child: ClipPath(
            clipper: _CutClipper(g, first: true),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CountryFlag.fromCountryCode(first,
                  height: height, width: flagWidth),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: g.cellWidth,
          height: height,
          child: ClipPath(
            clipper: _CutClipper(g, first: false),
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              Positioned(
                left: g.secondLeft,
                top: 0,
                width: flagWidth,
                height: height,
                child: CountryFlag.fromCountryCode(second,
                    height: height, width: flagWidth),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Левая ([first]) или правая часть ячейки по линии разреза.
class _CutClipper extends CustomClipper<Path> {
  final FlagPairGeometry g;
  final bool first;
  const _CutClipper(this.g, {required this.first});

  @override
  Path getClip(Size size) => first
      ? (Path()
        ..moveTo(0, 0)
        ..lineTo(g.cutTop, 0)
        ..lineTo(g.cutBottom, size.height)
        ..lineTo(0, size.height)
        ..close())
      : (Path()
        ..moveTo(g.cutTop, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(g.cutBottom, size.height)
        ..close());

  @override
  bool shouldReclip(covariant _CutClipper old) =>
      old.g.cellWidth != g.cellWidth || old.first != first;
}
