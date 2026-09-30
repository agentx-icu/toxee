// I3 (doc/reference/MOBILE_DEVICE_FEATURES.md): the mobile composer decides a
// hardware Enter's send/newline when the platform's `\n` arrives, not at key
// time. Unit-level edges of that formatter; the composer-level behaviour is in
// mobile_composer_real_ui_test.dart.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/hardware_enter_to_send.dart';

TextEditingValue _v(String text, [int? caret]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late List<String> sent;
  late HardwareEnterToSend enter;
  var accept = true;

  setUp(() {
    now = DateTime(2026, 9, 29, 12);
    sent = [];
    accept = true;
    enter = HardwareEnterToSend(
      canSend: (text) => accept && text.isNotEmpty,
      send: sent.add,
      platformInsertsAltNewline: false, // Android
      clock: () => now,
    );
  });

  KeyEventResult press({bool composing = false}) => enter.handleKeyEvent(
    const KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    ),
    composing: composing,
    insertNewline: () => fail('plain Enter must not insert from the framework'),
  );

  Future<KeyEventResult> pressWith(
    LogicalKeyboardKey modifier, {
    required VoidCallback insertNewline,
  }) async {
    final physical = {
      LogicalKeyboardKey.shiftLeft: PhysicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.controlLeft: PhysicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft: PhysicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.altLeft: PhysicalKeyboardKey.altLeft,
    }[modifier]!;
    HardwareKeyboard.instance.handleKeyEvent(
      KeyDownEvent(
        physicalKey: physical,
        logicalKey: modifier,
        timeStamp: Duration.zero,
      ),
    );
    try {
      return enter.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
        composing: false,
        insertNewline: insertNewline,
      );
    } finally {
      HardwareKeyboard.instance.handleKeyEvent(
        KeyUpEvent(
          physicalKey: physical,
          logicalKey: modifier,
          timeStamp: Duration.zero,
        ),
      );
    }
  }

  TextEditingValue format(TextEditingValue oldValue, TextEditingValue value) =>
      enter.formatter.formatEditUpdate(oldValue, value);

  test('no intent: a newline (soft keyboard Return, paste) passes through',
      () async {
    expect(format(_v('a'), _v('a\n')).text, 'a\n');
    await pumpEventQueue();
    expect(sent, isEmpty);
  });

  test('send intent waits through in-flight characters, then strips its newline',
      () async {
    expect(press(), KeyEventResult.ignored);
    expect(format(_v('qw'), _v('qwe')).text, 'qwe', reason: 'late char');
    expect(enter.pendingIntents, [HardwareEnterIntent.send]);
    final out = format(_v('qwe'), _v('qwe\n'));
    expect(out.text, 'qwe');
    expect(out.selection, const TextSelection.collapsed(offset: 3));
    expect(enter.pendingIntents, isEmpty);
    expect(sent, isEmpty, reason: 'sent after the formatted value is stored');
    // The next platform update lands before the send runs ...
    format(_v('qwe'), _v('qwe\nh'));
    await pumpEventQueue();
    expect(sent, ['qwe'], reason: '... so the send uses the captured text');
  });

  test('autocorrect rewriting the word in the same update still sends', () async {
    press();
    final out = format(_v('teh'), _v('the\n'));
    expect(out.text, 'the');
    await pumpEventQueue();
    expect(sent, hasLength(1));
  });

  test('Enter right before an existing newline is still recognised', () async {
    press();
    // old "x\nz" caret 1 -> platform inserts at the caret: "x\n\nz" caret 2.
    final out = format(_v('x\nz', 1), _v('x\n\nz', 2));
    expect(out.text, 'x\nz');
    expect(out.selection, const TextSelection.collapsed(offset: 1));
    await pumpEventQueue();
    expect(sent, hasLength(1));
  });

  test('a key typed before the Enter\'s newline arrives keeps the send',
      () async {
    press();
    // The next letter's KeyDown reaches the framework first (ignored, no
    // effect on the intent) ...
    enter.handleKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyH,
        logicalKey: LogicalKeyboardKey.keyH,
        timeStamp: Duration.zero,
      ),
      composing: false,
      insertNewline: () => fail('not an Enter'),
    );
    expect(enter.pendingIntents, [HardwareEnterIntent.send]);
    // ... then the Enter's newline, then the letter.
    expect(format(_v('hi'), _v('hi\n')).text, 'hi');
    await pumpEventQueue();
    expect(sent, hasLength(1));
  });

  test('a newline in the middle of the text is not the Enter', () async {
    press();
    // caret is not right after the new newline
    final out = format(_v('ab'), _v('a\nb', 3));
    expect(out.text, 'a\nb');
    expect(enter.pendingIntents, [HardwareEnterIntent.send]);
  });

  test('a stale intent (IME ate the Enter) does not hijack a later newline',
      () async {
    press();
    now = now.add(const Duration(seconds: 2));
    expect(format(_v('a'), _v('a\n')).text, 'a\n');
    await pumpEventQueue();
    expect(sent, isEmpty);
    expect(enter.pendingIntents, isEmpty);
  });

  test('Enter confirming an IME composition records nothing', () {
    expect(press(composing: true), KeyEventResult.ignored);
    expect(enter.pendingIntents, isEmpty);
  });

  test('a key typed right after Enter is rebased off the sent text', () async {
    press();
    expect(format(_v('abc'), _v('abc\n')).text, 'abc');
    await pumpEventQueue();
    expect(sent, hasLength(1));
    // The platform still had "abc\n" when it inserted the next letter.
    final out = format(_v('abc'), _v('abc\nh'));
    expect(out.text, 'h');
    expect(out.selection, const TextSelection.collapsed(offset: 1));
    // Once the platform has caught up, updates pass through again.
    expect(format(_v('h'), _v('hi')).text, 'hi');
    expect(format(_v('hi'), _v('abc\nhi')).text, 'abc\nhi');
  });

  test('no rebase when the send was refused (empty / over limit)', () async {
    accept = false;
    press();
    expect(format(_v('abc'), _v('abc\n')).text, 'abc');
    await pumpEventQueue();
    expect(format(_v('abc'), _v('abc\nh')).text, 'abc\nh');
  });

  test('Shift+Enter then Enter, both before their newlines, apply in order',
      () async {
    await pressWith(
      LogicalKeyboardKey.shiftLeft,
      insertNewline: () => fail('Shift+Enter goes through the platform'),
    );
    press();
    expect(enter.pendingIntents, [
      HardwareEnterIntent.newline,
      HardwareEnterIntent.send,
    ]);
    expect(format(_v('a'), _v('a\n')).text, 'a\n', reason: 'first: newline');
    final out = format(_v('a\n'), _v('a\n\n'));
    expect(out.text, 'a\n', reason: 'second: send strips its own newline');
    await pumpEventQueue();
    expect(sent, ['a\n']);
  });

  test('Enter replacing a selection that contains a newline sends the draft',
      () async {
    press();
    // "a\nxb", selection over "\nx" -> platform replaces it with "\n".
    const old = TextEditingValue(
      text: 'a\nxb',
      selection: TextSelection(baseOffset: 1, extentOffset: 3),
    );
    expect(format(old, _v('a\nb', 2)), old);
    await pumpEventQueue();
    expect(sent, ['a\nxb']);
  });

  test('a deletion that leaves a newline before the caret is not an Enter',
      () async {
    press();
    // backspace over "h" in "abc\nh"
    expect(format(_v('abc\nh'), _v('abc\n')).text, 'abc\n');
    expect(enter.pendingIntents, [HardwareEnterIntent.send]);
  });

  test('Ctrl/Cmd+Enter: framework inserts; Alt goes through the platform on iOS',
      () async {
    var inserted = 0;
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.altLeft,
    ]) {
      expect(
        await pressWith(modifier, insertNewline: () => inserted++),
        KeyEventResult.handled,
        reason: '$modifier on Android',
      );
    }
    expect(inserted, 3);
    expect(enter.pendingIntents, isEmpty);

    enter = HardwareEnterToSend(
      canSend: (text) => text.isNotEmpty,
      send: sent.add,
      platformInsertsAltNewline: true, // iOS
      clock: () => now,
    );
    expect(
      await pressWith(LogicalKeyboardKey.metaLeft, insertNewline: () => inserted++),
      KeyEventResult.handled,
      reason: 'UIKit does not insert for Command+Return',
    );
    expect(inserted, 4);
    expect(
      await pressWith(
        LogicalKeyboardKey.altLeft,
        insertNewline: () => fail('UIKit inserts Option+Return'),
      ),
      KeyEventResult.ignored,
    );
    expect(enter.pendingIntents, [HardwareEnterIntent.newline]);
    expect(format(_v('x'), _v('x\n')).text, 'x\n');
    await pumpEventQueue();
    expect(sent, isEmpty);
  });

  test('a second quick Enter while the first send is still echoed also sends',
      () async {
    press();
    expect(format(_v('abc'), _v('abc\n')).text, 'abc');
    await pumpEventQueue();
    press(); // typed "h" then Enter before the platform caught up
    expect(format(_v('abc'), _v('abc\nh')).text, 'h');
    final out = format(_v('h'), _v('abc\nh\n'));
    expect(out.text, 'h', reason: 'its newline stripped; the composer clears after the send');
    await pumpEventQueue();
    expect(sent, ['abc', 'h']);
  });

  test('second Enter in the same stale update as the first rebase', () async {
    press();
    expect(format(_v('abc'), _v('abc\n')).text, 'abc');
    await pumpEventQueue();
    press();
    // field still shows "abc" (clear pending); platform: "abc\nh\n"
    final out = format(_v('abc'), _v('abc\nh\n'));
    expect(out.text, 'h');
    await pumpEventQueue();
    expect(sent, ['abc', 'h']);
  });

  test('after a second send the platform base is the full echoed text',
      () async {
    press();
    format(_v('abc'), _v('abc\n'));
    press();
    format(_v('abc'), _v('abc\nh\n')); // sends "h"
    await pumpEventQueue();
    expect(sent, ['abc', 'h']);
    // The platform still echoes both messages when the next letter arrives.
    expect(format(_v('h'), _v('abc\nh\nx')).text, 'x');
  });

  test('an autocorrect that shortens the word in the Enter update still sends',
      () async {
    press();
    final out = format(_v('helllo'), _v('hello\n'));
    expect(out.text, 'hello');
    await pumpEventQueue();
    expect(sent, ['hello']);
  });

  test('Enter over a selection (Cmd+A) sends the whole draft, never erases it',
      () async {
    press();
    const old = TextEditingValue(
      text: 'draft',
      selection: TextSelection(baseOffset: 0, extentOffset: 5),
    );
    final out = format(old, _v('\n'));
    expect(out, old, reason: 'the draft stays until the send clears it');
    await pumpEventQueue();
    expect(sent, ['draft']);

    now = now.add(const Duration(seconds: 2)); // the first send is history
    accept = false; // over the limit: nothing sent, draft kept
    press();
    expect(format(old, _v('\n')), old);
  });
}
