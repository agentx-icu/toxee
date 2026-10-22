// Exercise the composer's transitive widget through its real keyboard actions.
// ignore: depend_on_referenced_packages
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Shift+PageDown extends and PageUp restores selection',
    (tester) async {
      final controller = TextEditingController(
        text: List.generate(60, (i) => 'Line $i of editable text').join('\n'),
      );
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 180,
              child: ExtendedTextField(
                controller: controller,
                focusNode: focus,
                minLines: null,
                maxLines: null,
                expands: true,
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, greaterThan(0));
      expect(controller.selection.isCollapsed, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );
}
