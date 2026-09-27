// B6 (doc/reference/MOBILE_DEVICE_FEATURES.md): the conversation open when
// the OS reclaimed the app comes back — through Flutter's restoration data,
// which the OS returns only after a system kill.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/home/master_detail_transition.dart';
import 'package:toxee/ui/home/open_chat_restoration.dart';

void main() {
  const peer = ChatTarget(userID: 'PEER');
  const group = ChatTarget(groupID: 'GROUP');

  Future<void> pumpRoot(WidgetTester tester) => tester.pumpWidget(
    const RootRestorationScope(restorationId: 'root', child: SizedBox()),
  );

  testWidgets('a saved chat survives a system kill, for its account only', (
    tester,
  ) async {
    await pumpRoot(tester);
    final before = OpenChatRestoration();
    expect(await before.readSaved('ALICE'), isNull, reason: 'fresh launch');
    before.save('ALICE', peer);
    await tester.pump();

    // The OS kills the process and hands the saved state back.
    final data = await tester.getRestorationData();
    await tester.restoreFrom(data);

    final after = OpenChatRestoration();
    expect(await after.readSaved('ALICE'), peer);
    expect(await after.readSaved('BOB'), isNull);
  });

  testWidgets('groups too; nothing open clears the marker', (tester) async {
    await pumpRoot(tester);
    final restoration = OpenChatRestoration();
    await restoration.readSaved('ALICE');
    restoration.save('ALICE', group);
    await tester.pump();
    await tester.restoreFrom(await tester.getRestorationData());
    expect(await OpenChatRestoration().readSaved('ALICE'), group);

    final again = OpenChatRestoration();
    await again.readSaved('ALICE');
    again.save('ALICE', null);
    await tester.pump();
    await tester.restoreFrom(await tester.getRestorationData());
    expect(await OpenChatRestoration().readSaved('ALICE'), isNull);
  });

  testWidgets('nothing is written before the saved marker was read', (
    tester,
  ) async {
    await pumpRoot(tester);
    final first = OpenChatRestoration();
    await first.readSaved('ALICE');
    first.save('ALICE', peer);
    await tester.pump();
    await tester.restoreFrom(await tester.getRestorationData());

    // A fresh instance that has not read yet has no bucket: a snapshot taken
    // too early cannot erase the marker.
    OpenChatRestoration().save('ALICE', null);
    await tester.pump();
    expect(await OpenChatRestoration().readSaved('ALICE'), peer);
  });
}
