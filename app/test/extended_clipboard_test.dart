import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentgate/ui/widgets/extended_clipboard.dart';

void main() {
  group('Extended clipboard content extraction & insertion', () {
    test('extracts plain text, strips HTML tags/entities, and handles URI fallback', () {
      expect(
        extractClipboardCommittedText(
          mimeType: 'text/plain',
          data: Uint8List.fromList(utf8.encode('vless://abc\u0000')),
          uri: '',
        ),
        'vless://abc',
      );

      expect(
        extractClipboardCommittedText(
          mimeType: 'text/html',
          data: Uint8List.fromList(
            utf8.encode('<div>https://sub.silentgate.lol/a&amp;b=1</div>'),
          ),
          uri: '',
        ),
        'https://sub.silentgate.lol/a&b=1',
      );

      expect(
        extractClipboardCommittedText(
          mimeType: 'text/uri-list',
          data: null,
          uri: 'https://silentgate.lol/sub',
        ),
        'https://silentgate.lol/sub',
      );

      expect(
        extractClipboardCommittedText(
          mimeType: 'image/png',
          data: null,
          uri: 'content://com.google.android.inputmethod.latin/clip/1',
        ),
        isNull,
      );
    });

    test('inserts at cursor or replaces active selection cleanly', () {
      final c = TextEditingController(text: 'hello world');
      c.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
      insertTextIntoController(c, 'SilentGate');
      expect(c.text, 'hello SilentGate');
      expect(c.selection.baseOffset, 'hello SilentGate'.length);
      c.dispose();
    });

    test('registers Meta+Ctrl+V and Meta+Shift+Insert paste shortcuts for Win+V', () {
      final shortcuts = buildExtendedPasteShortcuts();
      const winCtrlV = SingleActivator(
        LogicalKeyboardKey.keyV,
        control: true,
        meta: true,
      );
      const winShiftIns = SingleActivator(
        LogicalKeyboardKey.insert,
        shift: true,
        meta: true,
      );
      expect(shortcuts[winCtrlV], isA<PasteTextIntent>());
      expect(shortcuts[winShiftIns], isA<PasteTextIntent>());
    });

    testWidgets('TextField and TextFormField accept committed keyboard clipboard items',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? insertedCallbackValue;
      String? formChangedValue;

      final fieldConfig = buildExtendedContentInsertion(
        controller,
        onInserted: (v) => insertedCallbackValue = v,
      );
      final formConfig = buildFocusedExtendedContentInsertion(
        onInserted: (v) => formChangedValue = v,
      );

      await tester.pumpWidget(
        MaterialApp(
          shortcuts: buildExtendedPasteShortcuts(),
          home: Scaffold(
            body: Column(
              children: [
                TextField(
                  key: const Key('plainField'),
                  controller: controller,
                  contentInsertionConfiguration: fieldConfig,
                ),
                TextFormField(
                  key: const Key('formField'),
                  initialValue: '',
                  contentInsertionConfiguration: formConfig,
                  onChanged: (v) => formChangedValue = v,
                ),
              ],
            ),
          ),
        ),
      );

      fieldConfig.onContentInserted(
        KeyboardInsertedContent(
          mimeType: 'text/plain',
          uri: '',
          data: Uint8List.fromList(utf8.encode('anthropic.com')),
        ),
      );
      expect(controller.text, 'anthropic.com');
      expect(insertedCallbackValue, 'anthropic.com');

      await tester.tap(find.byKey(const Key('formField')));
      await tester.pump();
      formConfig.onContentInserted(
        KeyboardInsertedContent(
          mimeType: 'text/plain',
          uri: '',
          data: Uint8List.fromList(utf8.encode('1.1.1.1')),
        ),
      );
      await tester.pump();
      expect(formChangedValue, '1.1.1.1');
    });
  });
}

