import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';

/// Считает глубину стека навигации, чтобы индикатор VPN показывался только
/// ПОВЕРХ вложенных экранов (настройки, логи, раздельное туннелирование…).
///
/// На главном экране он не нужен: там состояние и так видно по кнопке Connect,
/// а лишняя плашка только загораживала бы обзор.
class NavDepthObserver extends NavigatorObserver {
  static final depth = ValueNotifier<int>(0);

  void _set(int d) {
    // Уведомление во время построения кадра роняет дерево: навигация приходит
    // как раз в момент build родителя.
    WidgetsBinding.instance.addPostFrameCallback((_) => depth.value = d);
  }

  int _current = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(++_current);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(--_current);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(--_current);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _set(_current);
}

/// Ненавязчивая плашка «VPN активен» поверх любого вложенного экрана.
///
/// Живёт в `MaterialApp.builder`, поэтому автоматически работает и на экранах,
/// которые появятся позже — их не нужно дорабатывать по одному. Плашка
/// обёрнута в [IgnorePointer]: она НИКОГДА не перехватывает нажатия, что бы под
/// ней ни оказалось.
class VpnActiveBadge extends StatelessWidget {
  final Widget child;
  const VpnActiveBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          child: ValueListenableBuilder<int>(
            valueListenable: NavDepthObserver.depth,
            builder: (context, depth, _) => _Badge(visible: depth > 1),
          ),
        ),
      ),
    ]);
  }
}

class _Badge extends StatelessWidget {
  final bool visible;
  const _Badge({required this.visible});

  @override
  Widget build(BuildContext context) {
    // select, а не watch: перерисовка только при смене состояния подключения,
    // а не на каждое обновление статистики/пинга.
    final connected =
        context.select<AppState, bool>((s) => s.status.isConnected);
    final server = context.select<AppState, String?>((s) {
      if (!s.status.isConnected) return null;
      return s.selectedServer?.displayName;
    });

    final show = visible && connected;
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return IgnorePointer(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        offset: show ? Offset.zero : const Offset(0, -1.4),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: show ? 1 : 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    // Слегка прозрачный фон: под плашкой остаётся видно контент.
                    color: scheme.inverseSurface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        server == null || server.isEmpty
                            ? l.vpnActiveBadge
                            : '${l.vpnActiveBadge} · $server',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: scheme.onInverseSurface),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
