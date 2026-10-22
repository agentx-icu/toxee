import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/home/desktop_shortcut.dart';

void main() {
  for (final mac in [true, false]) {
    for (final key in [
      LogicalKeyboardKey.comma,
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyF,
    ]) {
      testWidgets('${mac ? 'Cmd' : 'Ctrl'} + $key invokes exactly once', (
        tester,
      ) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Shortcuts(
              shortcuts: {
                desktopShortcut(key, isMacOS: mac): const ActivateIntent(),
              },
              child: Actions(
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      calls++;
                      return null;
                    },
                  ),
                },
                child: const Focus(autofocus: true, child: SizedBox()),
              ),
            ),
          ),
        );
        await tester.pump();
        final modifier = mac
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        final wrong = mac
            ? LogicalKeyboardKey.controlLeft
            : LogicalKeyboardKey.metaLeft;
        await tester.sendKeyDownEvent(wrong);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(wrong);
        expect(calls, 0);
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(modifier);
        expect(calls, 1);
      });
    }
  }
}
