// The friend-request row shows a FINGERPRINT of the requester's Tox public
// key, not the raw 64-hex string: printed raw it dominated the row and wrapped
// mid-token on phones, reading as developer output on the product page. The
// full key stays one hover/long-press away (Tooltip), and the row still keys
// its widgets by the full id for the real-UI drivers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:toxee/ui/contact/contact_application_item_content_override.dart';

const _key = 'D4A37F015C8E29B6403DA17FE8259C04B6F381DA9027E5C4136A80FB5E29D743';

void main() {
  test('abbreviateUserId keeps a short id and fingerprints a long one', () {
    expect(
      ContactApplicationItemContentOverride.abbreviateUserId('friend_123'),
      'friend_123',
    );
    expect(
      ContactApplicationItemContentOverride.abbreviateUserId(_key),
      'D4A37F01…29D743',
    );
    expect(
      ContactApplicationItemContentOverride.abbreviateUserId(_key),
      startsWith(_key.substring(0, 8)),
    );
    expect(
      ContactApplicationItemContentOverride.abbreviateUserId(_key),
      endsWith(_key.substring(_key.length - 6)),
    );
  });

  testWidgets('the row renders the fingerprint and tooltips the full key', (
    tester,
  ) async {
    final application = V2TimFriendApplication(
      userID: _key,
      nickname: 'Jordan Lee',
      addWording: 'Hey Mia!',
      type: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ContactApplicationItemContentOverride(application: application),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jordan Lee'), findsOneWidget);
    expect(
      find.text(ContactApplicationItemContentOverride.abbreviateUserId(_key)),
      findsOneWidget,
    );
    expect(find.text(_key), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == _key),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('contact_application_userid:$_key')),
      findsOneWidget,
    );
  });
}
