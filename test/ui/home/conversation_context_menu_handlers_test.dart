import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_conversation_event_handlers.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:toxee/ui/home/conversation_context_menu_handlers.dart';

/// Pins the identity guard: a HomePage remount via `pushAndRemoveUntil`
/// installs the NEW handlers before the OLD State disposes, and the old
/// teardown must not clobber them (live 2026-08-23: every mobile long-press on
/// a conversation row fell back to UIKit's upstream action sheet after a
/// forceHomeRoot remount).
void main() {
  // A bare registry: the live UIKit accessor needs an initialized
  // TencentCloudChat.instance, which this hermetic test does not have.
  final uiHandlers = TencentCloudChatConversationUIEventHandlers();
  final conversation = V2TimConversation(conversationID: 'c2c_test');

  Future<bool> fire() async =>
      await uiHandlers.onLongPressConversationItem?.call(
        conversation: conversation,
        position: Offset.zero,
      ) ??
      false;

  Future<bool> fireSecondary() async =>
      await uiHandlers.onSecondaryTapConversationItem?.call(
        conversation: conversation,
        position: Offset.zero,
      ) ??
      false;

  test('installed handlers route to the menu and report handled', () async {
    var shown = 0;
    final teardown = installConversationContextMenuHandlers(
      isMounted: () => true,
      showMenu: (_, _) async => shown++,
      handlers: uiHandlers,
    );
    expect(await fire(), isTrue);
    expect(await fireSecondary(), isTrue);
    expect(shown, 2);
    teardown();
    expect(await fire(), isFalse, reason: 'retired handler must decline');
    expect(await fireSecondary(), isFalse);
  });

  test('an unmounted State declines so UIKit falls back', () async {
    var mounted = true;
    final teardown = installConversationContextMenuHandlers(
      isMounted: () => mounted,
      showMenu: (_, _) async {},
      handlers: uiHandlers,
    );
    mounted = false;
    expect(await fire(), isFalse);
    teardown();
  });

  test('the OLD HomePage\'s teardown does not clobber the NEW one', () async {
    var oldShown = 0;
    var newShown = 0;
    final teardownOld = installConversationContextMenuHandlers(
      isMounted: () => true,
      showMenu: (_, _) async => oldShown++,
      handlers: uiHandlers,
    );
    // Remount: the new HomePage registers while the old one is still alive.
    final teardownNew = installConversationContextMenuHandlers(
      isMounted: () => true,
      showMenu: (_, _) async => newShown++,
      handlers: uiHandlers,
    );
    // The old route is disposed AFTER the new one's first frame.
    teardownOld();
    expect(
      await fire(),
      isTrue,
      reason: 'the new handler must survive the old teardown',
    );
    expect(await fireSecondary(), isTrue);
    expect(newShown, 2);
    expect(oldShown, 0);
    teardownNew();
    expect(await fire(), isFalse);
  });
}
