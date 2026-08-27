import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';
import 'package:toxee/navigation/active_conversation_route_observer.dart';

/// Pins the UNBIND half of the compact-shell active-conversation contract:
/// the observer must clear the active peer when the pushed chat route leaves
/// the stack by ANY exit — pop (back chevron / system back / edge swipe),
/// remove (logout's pushAndRemoveUntil, l3_pop_to_root) or replace — and must
/// NOT fire for unrelated routes. The service side is exercised through the
/// observer's own trigger plumbing rather than a live FfiChatService: what
/// this test owns is the ROUTE-NAME contract and the three NavigatorObserver
/// entry points, which is exactly the part no other test covered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Route<void> chatRoute() => MaterialPageRoute<void>(
    settings: const RouteSettings(name: TencentCloudChatRouteNames.message),
    builder: (_) => const SizedBox.shrink(),
  );
  Route<void> otherRoute([String name = '/other']) => MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: (_) => const SizedBox.shrink(),
  );

  group('ActiveConversationRouteObserver route-name contract', () {
    late List<String> triggers;
    late ActiveConversationRouteObserver observer;

    setUp(() {
      triggers = <String>[];
      observer = ActiveConversationRouteObserver.forTest(onClear: triggers.add);
    });

    test('didPop of the chat route unbinds', () {
      observer.didPop(chatRoute(), otherRoute());
      expect(triggers, ['didPop']);
    });

    test('didRemove of the chat route unbinds', () {
      observer.didRemove(chatRoute(), otherRoute());
      expect(triggers, ['didRemove']);
    });

    test('didReplace chat -> non-chat unbinds', () {
      observer.didReplace(oldRoute: chatRoute(), newRoute: otherRoute());
      expect(triggers, ['didReplace']);
    });

    test('didReplace chat -> chat does NOT unbind', () {
      observer.didReplace(oldRoute: chatRoute(), newRoute: chatRoute());
      expect(triggers, isEmpty);
    });

    test('unrelated routes never unbind', () {
      observer.didPop(otherRoute(), otherRoute('/two'));
      observer.didRemove(otherRoute(), null);
      observer.didReplace(oldRoute: otherRoute(), newRoute: chatRoute());
      expect(triggers, isEmpty);
    });
  });
}
