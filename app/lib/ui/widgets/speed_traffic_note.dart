import 'package:flutter/material.dart';

/// Заметное сообщение о трафике, который съедает замер скорости.
///
/// ⚠️ ПОЧЕМУ ЭТО ОТДЕЛЬНЫЙ ВИДЖЕТ, А НЕ СЕРАЯ ПОДПИСЬ ПОД ПЕРЕКЛЮЧАТЕЛЕМ.
/// Прямое требование владельца: замер тратит трафик ПОДПИСКИ, за который он
/// платит, и узнавать об этом из мелкого шрифта — почти то же самое, что не
/// узнать вовсе. Поэтому у сообщения есть значок, своя заливка и число
/// мегабайт, а не обтекаемое «расходует трафик».
///
/// ⚠️ ЧИСЛО СЮДА ПРИХОДИТ ГОТОВЫМ и считается ровно в одном месте —
/// `AppSettings.speedTestTrafficMb`. Мест показа три (переключатель, поле
/// «сколько серверов», диалог подтверждения), и своя арифметика в виджете
/// означала бы, что стоит поменять формулу — и они начнут показывать разные
/// цифры за один и тот же прогон. Локализация тоже снаружи: виджету незачем
/// знать про `AppLocalizations`, его показывают и в диалоге, и в списке.
class SpeedTrafficNote extends StatelessWidget {
  const SpeedTrafficNote({super.key, required this.text, this.dense = false});

  /// Готовая строка с числом («≈55 МБ трафика подписки за прогон»).
  final String text;

  /// Компактный вид — для диалога, где вокруг и так есть объясняющий абзац.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 10),
      decoration: BoxDecoration(
        // Не красный: это не ошибка и не запрет, а цена, которую надо знать
        // до нажатия. Красным здесь пугали бы на ровном месте.
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.data_usage,
              size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
