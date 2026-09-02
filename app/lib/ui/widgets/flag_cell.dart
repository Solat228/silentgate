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

/// ⚠️ ГДЕ ПРОХОДИТ ЛИНИЯ РАЗДЕЛА — РЕШЕНИЕ ВЛАДЕЛЬЦА (28.08.2026, уточнено
/// 02.09.2026: «флаги с большим углом»).
///
/// Первая редакция резала строго из угла в угол: у ячейки 34×24 это ≈35°, и
/// верхний флаг терял почти всю правую половину — от «мост Россия → Германия»
/// оставалась полоска, по которой страну не узнать.
///
/// ⚠️ ВТОРАЯ РЕДАКЦИЯ ОБЕЩАЛА 50–60°, А ДАВАЛА 43°. Доля 0.75 при 34×24 —
/// это atan(24 / 34·0.75) ≈ 43°, то есть на восемь градусов круче прежнего.
/// Владелец правку не заметил и попросил снова — справедливо. Считать угол
/// надо, а не прикидывать: чем МЕНЬШЕ доля, тем КРУЧЕ разрез.
///
/// Сейчас 0.5 → atan(24 / 17) ≈ 55°, середина запрошенного диапазона. Это
/// проверяется тестом В ГРАДУСАХ (`flag_cell_test.dart`), а не сверкой
/// константы: иначе следующая правка снова разойдётся с обещанием.
///
/// ⚠️ ДОЛЯ, А НЕ ПИКСЕЛИ. Ячейка рисуется в разных размерах (34×24 в списке,
/// крупнее на экране сервера), и зашитый отступ дал бы разный наклон на
/// разных экранах — то есть «съехавшую» линию там, где её никто не менял.
const double splitTopFraction = 0.5;

/// Верхняя левая часть: от левого верхнего угла до точки на верхней грани,
/// затем в левый нижний угол.
class _TopLeftTriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * splitTopFraction, 0)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Нижняя правая часть — дополнение к [_TopLeftTriangleClipper] по той же
/// линии раздела. ⚠️ Обе фигуры обязаны опираться на одну константу: разойдись
/// они, между половинами появилась бы щель или нахлёст.
class _BottomRightTriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * splitTopFraction, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
