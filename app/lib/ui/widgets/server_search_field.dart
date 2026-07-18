import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

/// Поле поиска по серверам: свободный текст, крестик для сброса.
class ServerSearchField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  const ServerSearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  @override
  State<ServerSearchField> createState() => _ServerSearchFieldState();
}

class _ServerSearchFieldState extends State<ServerSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: widget.hint ?? l.searchHint,
        isDense: true,
        border: const OutlineInputBorder(),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: l.searchReset,
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
      onChanged: (v) {
        widget.onChanged(v);
        setState(() {}); // показать/скрыть крестик
      },
    );
  }
}
