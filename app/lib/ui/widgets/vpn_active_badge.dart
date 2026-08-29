import 'package:flutter/material.dart';

/// Следит за глубиной стека навигации — полезно для индикаторов и плавающих
/// элементов, которые должны видны только на вложенных экранах, а не на
/// главном.
///
/// Считает только полноэкранные маршруты (PageRoute). Диалоги, всплывающие
/// меню и нижние листы не меняют видимость экрана, поэтому в счёт не идут.
class NavDepthObserver extends NavigatorObserver {
  static final depth = ValueNotifier<int>(0);

  /// ⚠️ ЕДИНСТВЕННЫЙ экземпляр. `MaterialApp` пересобирается на каждую смену
  /// темы/языка/настроек, и создание нового наблюдателя с нулевым счётчиком
  /// привело бы к потере предыдущих событий: старый успел бы досчитать pop'ы,
  /// которых новый не видел, и глубина уходила бы в минус.
  static final instance = NavDepthObserver._();
  NavDepthObserver._();

  int _current = 0;

  /// Только полноэкранные маршруты.
  bool _counts(Route<dynamic>? route) => route is PageRoute;

  void _set(int d) {
    _current = d < 0 ? 0 : d;
    // Уведомление во время построения кадра роняет дерево: навигация приходит
    // как раз в момент build родителя. Отложим обновление на конец кадра.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => depth.value = _current);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) _set(_current + 1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) _set(_current - 1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) _set(_current - 1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    // Замена не меняет глубину, если обе стороны — полноэкранные маршруты.
    final delta = (_counts(newRoute) ? 1 : 0) - (_counts(oldRoute) ? 1 : 0);
    if (delta != 0) _set(_current + delta);
  }
}
