import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Расширенная таблица горячих клавиш для [MaterialApp.shortcuts], чтобы
/// вставка из системной истории буфера обмена (`Win+V` на Windows, где клавиша
/// `Win`/`Meta` может оставаться зажатой в момент прихода `Ctrl+V` или
/// `Shift+Insert`) срабатывала в любом текстовом поле приложения.
Map<ShortcutActivator, Intent> buildExtendedPasteShortcuts() {
  return <ShortcutActivator, Intent>{
    ...WidgetsApp.defaultShortcuts,
    const SingleActivator(
      LogicalKeyboardKey.keyV,
      control: true,
      meta: true,
    ): const PasteTextIntent(SelectionChangedCause.keyboard),
    const SingleActivator(
      LogicalKeyboardKey.insert,
      shift: true,
      meta: true,
    ): const PasteTextIntent(SelectionChangedCause.keyboard),
  };
}

/// Конфигурация приёма расширенного буфера обмена клавиатуры (Android Gboard /
/// Samsung / MIUI / SwiftKey `InputConnection.commitContent` с MIME-типами
/// `text/plain`, `text/html`, `text/uri-list`, `text/*`).
///
/// Без [ContentInsertionConfiguration] мобильные менеджеры буфера обмена не
/// могут вставить карточку из истории буфера или отдают отказ «приложение не
/// поддерживает вставку этого содержимого».
ContentInsertionConfiguration buildExtendedContentInsertion(
  TextEditingController controller, {
  ValueChanged<String>? onInserted,
}) {
  return ContentInsertionConfiguration(
    allowedMimeTypes: const <String>[
      'text/plain',
      'text/html',
      'text/uri-list',
      'text/*',
    ],
    onContentInserted: (KeyboardInsertedContent content) {
      final extracted = extractClipboardCommittedText(
        mimeType: content.mimeType,
        data: content.data,
        uri: content.uri,
      );
      if (extracted == null || extracted.isEmpty) return;
      insertTextIntoController(controller, extracted);
      onInserted?.call(controller.text);
    },
  );
}

ContentInsertionConfiguration buildFocusedExtendedContentInsertion({
  ValueChanged<String>? onInserted,
}) {
  return ContentInsertionConfiguration(
    allowedMimeTypes: const <String>[
      'text/plain',
      'text/html',
      'text/uri-list',
      'text/*',
    ],
    onContentInserted: (KeyboardInsertedContent content) {
      final extracted = extractClipboardCommittedText(
        mimeType: content.mimeType,
        data: content.data,
        uri: content.uri,
      );
      if (extracted == null || extracted.isEmpty) return;
      final focusCtx = FocusManager.instance.primaryFocus?.context;
      EditableTextState? editable;
      if (focusCtx is StatefulElement && focusCtx.state is EditableTextState) {
        editable = focusCtx.state as EditableTextState;
      } else {
        editable = focusCtx?.findAncestorStateOfType<EditableTextState>();
      }
      if (editable != null) {
        final temp = TextEditingController.fromValue(editable.textEditingValue);
        insertTextIntoController(temp, extracted);
        editable.userUpdateTextEditingValue(
          temp.value,
          SelectionChangedCause.keyboard,
        );
        onInserted?.call(temp.text);
        temp.dispose();
      }
    },
  );
}

/// Извлекает чистый текст из пакета `KeyboardInsertedContent`.
@visibleForTesting
String? extractClipboardCommittedText({
  required String mimeType,
  required Uint8List? data,
  required String uri,
}) {
  String? raw;
  if (data != null && data.isNotEmpty) {
    raw = utf8.decode(data, allowMalformed: true);
  } else if (uri.isNotEmpty && !uri.startsWith('content://')) {
    raw = uri;
  }
  if (raw == null) return null;
  if (mimeType.toLowerCase().contains('html')) {
    raw = _stripHtml(raw);
  }
  // Убираем нулевые байты, которые иногда дописывают сторонние буферы.
  raw = raw.replaceAll('\u0000', '');
  return raw.isEmpty ? null : raw;
}

/// Вставляет [inserted] в текущую позицию курсора/выделения [controller].
@visibleForTesting
void insertTextIntoController(
    TextEditingController controller, String inserted) {
  final value = controller.value;
  final text = value.text;
  final sel = value.selection;
  if (sel.isValid) {
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    final low = start <= end ? start : end;
    final high = start <= end ? end : start;
    final nextText = text.replaceRange(low, high, inserted);
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: low + inserted.length),
    );
  } else {
    final nextText = '$text$inserted';
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }
}

String _stripHtml(String html) {
  var s = html
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*(p|div|li)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
  return s.trim();
}

