import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_locales.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/settings_controller.dart';

/// Кнопка выбора языка интерфейса — в духе Google Переводчика: значок перевода
/// + флаг текущего языка. Стоит ОТДЕЛЬНО (в шапке настроек), чтобы назначение
/// читалось с первого взгляда. Тап открывает список языков (флаг + самоназвание).
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final code = context.watch<SettingsController>().settings.languageCode;
    // Пусто = «как в системе»: показываем флаг фактического языка приложения.
    final activeCode =
        code.isNotEmpty ? code : Localizations.localeOf(context).languageCode;
    final lang = languageByCode(activeCode) ?? supportedLanguages.first;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Tooltip(
        message: AppLocalizations.of(context).languageTitle,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _pick(context, code),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.translate, size: 18, color: scheme.onPrimaryContainer),
              const SizedBox(width: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: CountryFlag.fromCountryCode(lang.flag,
                    height: 16, width: 22),
              ),
              Icon(Icons.arrow_drop_down,
                  size: 18, color: scheme.onPrimaryContainer),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, String currentCode) async {
    final l = AppLocalizations.of(context);
    final controller = context.read<SettingsController>();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        Widget tile(
            {required String code,
            required String title,
            required Widget leading}) {
          final selected = code == currentCode;
          return ListTile(
            leading: leading,
            title: Text(title),
            trailing: selected
                ? Icon(Icons.check,
                    color: Theme.of(ctx).colorScheme.primary)
                : null,
            onTap: () => Navigator.pop(ctx, code),
          );
        }

        return SimpleDialog(
          title: Row(children: [
            const Icon(Icons.translate, size: 20),
            const SizedBox(width: 8),
            Text(l.languageTitle),
          ]),
          children: [
            // «Как в системе» — код пустой.
            tile(
              code: '',
              title: l.languageSystem,
              leading: const Icon(Icons.public),
            ),
            const Divider(height: 8),
            // Языки — по алфавиту (английские названия).
            for (final lang in languagesSortedByName)
              tile(
                code: lang.code,
                title: lang.endonym,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: CountryFlag.fromCountryCode(lang.flag,
                      height: 20, width: 28),
                ),
              ),
          ],
        );
      },
    );
    if (picked != null && picked != currentCode) {
      await controller.update((s) => s.copyWith(languageCode: picked));
    }
  }
}
