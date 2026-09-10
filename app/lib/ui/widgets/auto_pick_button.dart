import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import 'connect_guard.dart';

/// Кнопка «Подобрать сервер» — ОДНА на все три места, где она стоит.
///
/// ⚠️ ОДИН ВИДЖЕТ, А НЕ ТРИ КОПИИ, И ЭТО СУТЬ ПРАВКИ. Правило владельца:
/// кнопка живёт над списком серверов, где бы этот список ни рисовался, — а
/// рисуется он в двух разных местах (правая панель широкого окна и отдельный
/// экран `ServersScreen` на узком), плюс на узком окне кнопка остаётся внизу
/// главного экрана запасной. Человек никогда не видит два места сразу, так что
/// это не дубликаты, а одно правило. Разъехавшиеся копии одной кнопки в этом
/// проекте уже давали расхождение поведения (гейт пинга закрывал две точки
/// входа из четырёх, и кнопка на главном молча не работала), поэтому здесь в
/// одном месте собраны и вид, и действие, и правило «когда кнопки нет вовсе».
class AutoPickServerButton extends StatelessWidget {
  const AutoPickServerButton({super.key, this.wide = false});

  /// Кнопка НАД СПИСКОМ: во всю ширину панели и с поясняющей строкой справа.
  ///
  /// Внизу главного экрана она стоит рядом с «Подобрать настройки» в `Wrap`,
  /// и там пояснение не показывается: две подписи в строку на узком окне с
  /// крупным системным шрифтом уже не помещаются.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    // ⚠️ ПРАВИЛО «КНОПКИ НЕТ» — ЗДЕСЬ, А НЕ У КАЖДОГО МЕСТА ВЫЗОВА. Подбирать
    // не из чего, пока подписка не импортирована; кнопка, которая ничего не
    // делает, хуже отсутствующей.
    if (!state.hasServers) return const SizedBox.shrink();

    final button = FilledButton.tonalIcon(
      icon: const Icon(Icons.bolt),
      label: wide
          // ⚠️ ПОЯСНЕНИЕ ПОД ПОДПИСЬЮ, А НЕ СПРАВА ОТ НЕЁ.
          //
          // Живой прогон в VM 10.09.2026, минимальное окно 980×800: панель
          // списка там 380 px, и в строку «Подобрать сервер» + пояснение не
          // помещались — многоточие съедало ровно то, ради чего размещение и
          // выбирали («текст не особо понятен», требование владельца). Две
          // строки стоят ~18 px высоты панели и ничего больше не двигают,
          // а обрезанное пояснение бесполезно целиком.
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.homeAutoBest,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  l.homeAutoBestHint(state.servers.length),
                  // Две строки: на турецком и немецком подпись длиннее русской,
                  // и в одну она не укладывается даже на своей строке.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline),
                ),
              ],
            )
          : Text(l.homeAutoBest),
      onPressed: () => connectWithConflictCheck(
        context,
        state,
        // Настройки читаем в момент нажатия: между построением кнопки и
        // нажатием пользователь успевает их поменять.
        () => state.connectAuto(context.read<SettingsController>().settings),
      ),
    );
    // Над списком кнопка занимает всю ширину панели — иначе она теряется
    // между строкой поиска и списком, ради близости к которому и переехала.
    return wide ? SizedBox(width: double.infinity, child: button) : button;
  }
}
