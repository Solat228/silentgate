import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Класс экрана по ШИРИНЕ. Пороги Material 3, а не свои: под них размечены
/// готовые виджеты Flutter, и когда понадобится `NavigationRail` или
/// адаптивные компоненты, они лягут без переходников.
enum SgWidth { compact, medium, expanded }

/// Класс экрана по ВЫСОТЕ.
///
/// ⚠️ Отдельная ось нужна не для красоты. Открытая клавиатура забирает ~280 dp,
/// и телефон 360×800 превращается в 360×520 — по ширине он всё ещё «телефон», а
/// по высоте становится тем же, чем телефон в ландшафте. Одной ширины для
/// решения «влезет ли диалог» не хватает.
enum SgHeight { short, tall }

/// Размеры и признаки текущего экрана.
///
/// ⚠️ РАЗДЕЛЕНИЕ ОТВЕТСТВЕННОСТИ, которое нельзя смешивать:
///   `Platform.is*` и `PlatformServices` отвечают «**умеет ли** платформа» —
///   есть ли UAC, есть ли always-on VPN, можно ли показать файл в проводнике.
///   `SgLayout` отвечает «**влезает ли** на экран».
/// Решать компоновку по `Platform.*` нельзя (планшет 900 dp — не телефон), и
/// доступность функции по ширине — тоже (узкое окно на Windows не теряет UAC).
class SgLayout {
  const SgLayout({required this.width, required this.height});

  final SgWidth width;
  final SgHeight height;

  bool get isCompact => width == SgWidth.compact;
  bool get isShort => height == SgHeight.short;

  /// Отступ страницы: на телефоне 24 dp с каждой стороны — это 13 % ширины,
  /// которых не хватает спискам правил.
  double get pagePadding => isCompact ? 16 : 24;

  /// Высота строки списка. 56 dp — запас над порогом удобного нажатия (48) без
  /// зажатости; 48 дало бы на строку больше ценой промахов по чекбоксу.
  double get rowHeight => isCompact ? 56 : 64;

  double get listIconSize => isCompact ? 24 : 28;

  static SgLayout of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    return SgLayout(
      width: size.width < 600
          ? SgWidth.compact
          : (size.width < 840 ? SgWidth.medium : SgWidth.expanded),
      // Высоту считаем ЗА ВЫЧЕТОМ клавиатуры — иначе признак `short` не
      // сработал бы там, ради чего и заводился.
      height: (size.height - insets.bottom) < 600 ? SgHeight.short : SgHeight.tall,
    );
  }
}

extension SgLayoutContext on BuildContext {
  SgLayout get sg => SgLayout.of(this);
}

/// Размер тела диалога, который ВЛЕЗАЕТ.
///
/// ⚠️ ЭТО ЗАМЕНА `SizedBox(width: W, height: H)` В ДИАЛОГАХ, И ВОТ ПОЧЕМУ.
/// `Dialog` во Flutter сам ужимается под клавиатуру, добавляя `viewInsets` к
/// отступам. Ломает всё именно ФИКСИРОВАННАЯ высота: коробка требует 480 dp в
/// слоте на 356 и даёт `RenderFlex overflowed` — те самые жёлто-чёрные полосы,
/// которые видно при вводе в отчёте поддержки.
///
/// ⚠️ ДЕСКТОП НЕ МЕНЯЕТСЯ, и это проверяется арифметикой, а не надеждой: окно
/// Windows не меньше 980×800 (`TrayWindow.minimumSize`), доступная высота там
/// 800 − 48 (инсеты) − 64 (заголовок) − 52 (кнопки) = 636 dp, а самый большой
/// запрос в проекте — 480. `min(480, 636) = 480`, то есть ровно прежнее число.
/// Пока `minimumSize` не опускают ниже 840×600, эта функция физически не может
/// изменить десктоп.
Widget adaptiveDialogBody(
  BuildContext context, {
  required double width,
  double? height,
  required Widget child,
}) {
  final size = MediaQuery.sizeOf(context);
  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
  // 80 = боковые отступы диалога (40+40). Запрошенная ширина на телефоне
  // недостижима в принципе, и настаивать на ней бессмысленно.
  final w = math.min(width, size.width - 80);
  if (height == null) return SizedBox(width: w, child: child);
  const chrome = 48.0 + 64.0 + 52.0; // инсеты + заголовок + кнопки
  final avail = size.height - keyboard - chrome;
  return SizedBox(
    width: w,
    height: math.max(120, math.min(height, avail)),
    child: child,
  );
}
