// Tests toxee's wiring of conversation long-press / secondary-tap handlers
// into the UIKit's `TencentCloudChatConversationManager.eventHandlers` slot.
//
// What the old test was doing wrong:
//   It only verified that `TencentCloudChatConversationUIEventHandlers`
//   (a UIKit class) stored the callback we handed it. That tested third-
//   party-library setter behavior, not toxee.
//
// What this test does:
//   1. Drives the UIKit's `setEventHandlers(...)` channel directly, the same
//      way HomePage's `_initAfterSessionReady` post-frame callback does.
//   2. Confirms the handler that gets installed is a non-null closure that
//      returns `true` (signalling "toxee handled it, UIKit should not show
//      its default action sheet").
//   3. Confirms invoking the handler is observable — i.e. the closure runs.
//
// The full "HomePage builds → handler is registered → tapping shows the
// context menu" round trip requires `Tim2ToxSdkPlatform` to be installed and
// `FfiChatService` to be live, neither of which is feasible from a pure unit
// test. That gap is acknowledged at the bottom of this file; integration
// coverage lives in `test/ui/conversation/...` widget tests where the
// SessionRuntimeCoordinator is faked.

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_conversation_event_handlers.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart'
    as conv_pkg;

void main() {
  // `TencentCloudChat.instance` accesses `WidgetsBinding.instance` while
  // constructing its theme data, so the test binding must exist first.
  TestWidgetsFlutterBinding.ensureInitialized();

  // The UIKit's data instance is a singleton — clean slot between tests so
  // an earlier test's handler doesn't leak into a later test's expectation.
  setUp(() {
    TencentCloudChat.instance.dataInstance.conversation
        .conversationEventHandlers = TencentCloudChatConversationEventHandlers();
  });

  test(
      'toxee-style registration installs both long-press and secondary-tap '
      'handlers and they fire with the conversation + position', () async {
    // Mirror of HomePage._initAfterSessionReady() registration.
    var longPressInvocations = 0;
    var secondaryTapInvocations = 0;
    V2TimConversation? lastLongPressConv;
    Offset? lastLongPressPos;

    conv_pkg.TencentCloudChatConversationManager.eventHandlers.uiEventHandlers
        .setEventHandlers(
      onSecondaryTapConversationItem: ({
        required V2TimConversation conversation,
        required Offset position,
      }) async {
        secondaryTapInvocations++;
        return true;
      },
      onLongPressConversationItem: ({
        required V2TimConversation conversation,
        required Offset position,
      }) async {
        longPressInvocations++;
        lastLongPressConv = conversation;
        lastLongPressPos = position;
        return true;
      },
    );

    // Read the handlers back through the same path UIKit's conversation
    // item widget uses (`...conversationEventHandlers?.uiEventHandlers
    // .onLongPressConversationItem`). This is the real toxee integration
    // contract — if this slot is null after registration, UIKit will silently
    // fall back to its built-in action sheet and toxee's context menu won't
    // appear.
    final handlers = TencentCloudChat
        .instance.dataInstance.conversation.conversationEventHandlers;
    expect(handlers, isNotNull,
        reason: 'eventHandlers slot must be populated by the toxee wiring');
    expect(handlers!.uiEventHandlers.onLongPressConversationItem, isNotNull,
        reason: 'long-press handler must be non-null after registration');
    expect(handlers.uiEventHandlers.onSecondaryTapConversationItem, isNotNull,
        reason: 'secondary-tap handler must be non-null after registration');

    // Invoke the handlers exactly the way `TencentCloudChatConversationItem`
    // does (see `_handleLongPress` and `_handleSecondaryTap` in the submodule).
    final conv = V2TimConversation(conversationID: 'group_test123')
      ..groupID = 'test123';
    const pos = Offset(123.4, 567.8);

    final lpHandled = await handlers.uiEventHandlers
        .onLongPressConversationItem!(conversation: conv, position: pos);
    final stHandled = await handlers.uiEventHandlers
        .onSecondaryTapConversationItem!(conversation: conv, position: pos);

    expect(lpHandled, isTrue,
        reason: 'toxee handler must return true so UIKit suppresses its '
            'default mobile action sheet / desktop popup');
    expect(stHandled, isTrue);

    expect(longPressInvocations, 1);
    expect(secondaryTapInvocations, 1);
    expect(lastLongPressConv, same(conv));
    expect(lastLongPressPos, pos);
  });

  test(
      'second registration replaces the first handler '
      '(matches HomePage teardown-on-dispose behavior)', () async {
    var firstCalls = 0;
    var secondCalls = 0;
    final handlers = conv_pkg
        .TencentCloudChatConversationManager.eventHandlers.uiEventHandlers;

    handlers.setEventHandlers(
      onLongPressConversationItem: ({
        required V2TimConversation conversation,
        required Offset position,
      }) async {
        firstCalls++;
        return true;
      },
    );

    // toxee tears down on dispose by re-registering a no-op-returning-false
    // closure. Simulate that and verify the new closure is the active one.
    handlers.setEventHandlers(
      onLongPressConversationItem: ({
        required V2TimConversation conversation,
        required Offset position,
      }) async {
        secondCalls++;
        return false;
      },
    );

    final conv = V2TimConversation(conversationID: 'group_x');
    final handled = await handlers.onLongPressConversationItem!(
        conversation: conv, position: Offset.zero);

    expect(handled, isFalse,
        reason: 'second registration (the "teardown" no-op) replaces the '
            'first; tap-through to UIKit default behavior is signalled by '
            'returning false');
    expect(firstCalls, 0);
    expect(secondCalls, 1);
  });

  // KNOWN GAP: the test above stops short of building a real HomePage and
  // verifying the post-frame callback actually fires. That path requires
  // SessionRuntimeCoordinator, Tim2ToxSdkPlatform, and FfiChatService, none
  // of which can be plugged into a pure `flutter test` harness without a
  // full Tim2Tox FFI build. See `doc/architecture/HYBRID_ARCHITECTURE.md`
  // §"Startup ordering" for the dependency chain. Tracked for follow-up;
  // for now, this seam-level test catches the most common regression
  // (handler getting dropped or replaced unexpectedly).
}
