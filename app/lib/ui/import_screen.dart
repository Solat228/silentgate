import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../core/i18n/text_direction.dart';
import '../l10n/gen/app_localizations.dart';
import 'widgets/subscription_avatar.dart';
import 'widgets/app_toast.dart';

class ImportScreen extends StatefulWidget {
  /// Первый запуск: показывается на весь экран, вернуться некуда — в приложении
  /// ещё нет ни подписки, ни закреплённых серверов (#1.2).
  final bool initialSetup;
  const ImportScreen({super.key, this.initialSetup = false});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  // Поле НЕ заполняем прежней ссылкой: пользователь вставляет её сам (или жмёт
  // «Импорт из буфера»). Старая ссылка в поле сбивала — легко импортировать не то.
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final state = context.read<AppState>();
    await state.importSource(_controller.text);
    if (!mounted) return;
    if (state.error == null && state.hasServers) {
      final l = AppLocalizations.of(context);
      AppToast.show(context, l.importScrDone, kind: ToastKind.success);
      // При первом запуске этот экран НЕ проталкивался в навигатор — он
      // возвращается прямо из build главного экрана. Безусловный pop() снимал
      // бы корневой маршрут, и приложение уходило в чёрный экран до
      // перезапуска. Закрывать нужно только то, что действительно открыли;
      // в первичном сценарии главный экран перестроится сам, как только
      // появятся серверы.
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();
    }
  }

  Future<void> _pasteImport() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _controller.text = text;
    await _import();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialSetup
            ? l.importScrWelcome
            : l.importScrTitle),
        automaticallyImplyLeading: !widget.initialSetup,
      ),
      // ⚠️ Прокрутка обязательна: это экран ПЕРВОГО ЗАПУСКА с полем URL.
      // Без неё он переполняется при открытой клавиатуре, а с текстом ошибки
      // (ограничен 220 dp) — вообще всегда.
      body: SingleChildScrollView(
        child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // #2 — логотип провайдера, если подписка уже импортирована.
                if (state.logoPath != null) ...[
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SubscriptionAvatar(path: state.logoPath, label: state.info.title, size: 40),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(state.info.title ?? l.importScrSubscriptionFallback,
                          // Название подписки — направление по содержимому.
                          textDirection: autoTextDirection(state.info.title),
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  const SizedBox(height: 16),
                ],
                Text(l.importScrHint),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'https://sub.silentgate.lol/sub/…',
                  ),
                ),
                const SizedBox(height: 12),
                // #1.2 — «из буфера» ВЫШЕ ручного подтверждения: обычно ссылка уже
                // скопирована, и вставлять её в поле руками не нужно.
                FilledButton.icon(
                  onPressed: state.loading ? null : _pasteImport,
                  icon: state.loading
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.content_paste),
                  label: Text(state.loading
                      ? l.importScrLoading
                      : l.importScrPasteImport),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: state.loading ? null : _import,
                  icon: const Icon(Icons.download),
                  label: Text(l.importScrImportField),
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 16),
                  // #7 — длинная ошибка не выталкивает кнопки: ограничиваем и скроллим.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Text(
                        state.error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      )),
    );
  }
}
