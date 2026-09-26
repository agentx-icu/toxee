import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';
import 'package:toxee/navigation/root_route_tracker.dart';
import 'package:toxee/ui/home/master_detail_transition.dart';

const _peer = ChatTarget(userID: 'PEER');

RouteSettings _chatSettings(ChatTarget t) => RouteSettings(
  name: TencentCloudChatRouteNames.message,
  arguments: {
    'options': TencentCloudChatMessageOptions(
      userID: t.userID,
      groupID: t.groupID,
    ),
  },
);

/// A fake shell whose every input the tests set directly.
class _Shell {
  bool mounted = true;
  bool chatsTabIdle = true;
  bool wideNow = false;
  String account = 'A';
  ChatTarget? selection;
  Route<dynamic>? home;
  NavigatorState? navigator;
  int configFailures = 0;
  final configs = <bool>[];
  final opened = <ChatTarget>[];

  MasterDetailHost get host => MasterDetailHost(
    isMounted: () => mounted,
    isChatsTabIdle: () => chatsTabIdle,
    homeRoute: () => home,
    showsMasterDetailNow: () => wideNow,
    accountKey: () => account,
    wideSelection: () => selection,
    rootNavigator: () => navigator,
    applyConfig: (wide) {
      if (configFailures > 0) {
        configFailures--;
        throw StateError('config not ready');
      }
      configs.add(wide);
    },
    openChat: opened.add,
  );
}

void main() {
  group('chatTargetOfRoute', () {
    test('reads the message route options', () {
      final route = MaterialPageRoute<void>(
        settings: _chatSettings(const ChatTarget(groupID: 'G')),
        builder: (_) => const SizedBox(),
      );
      expect(chatTargetOfRoute(route), const ChatTarget(groupID: 'G'));
    });

    test('ignores other routes', () {
      final route = MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/profile'),
        builder: (_) => const SizedBox(),
      );
      expect(chatTargetOfRoute(route), isNull);
      expect(chatTargetOfRoute(null), isNull);
    });
  });

  group('MasterDetailTransition (no navigator)', () {
    late _Shell shell;
    late RootRouteTracker tracker;
    late List<VoidCallback> frames;
    late MasterDetailTransition transition;

    void runFrames() {
      while (frames.isNotEmpty) {
        frames.removeAt(0)();
      }
    }

    setUp(() {
      shell = _Shell();
      tracker = RootRouteTracker.forTest();
      frames = <VoidCallback>[];
      transition = MasterDetailTransition(
        host: shell.host,
        tracker: tracker,
        schedule: frames.add,
      );
      shell.home = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      tracker.didPush(shell.home!, null);
    });

    test('first build only applies the layout mode', () {
      shell.wideNow = true;
      shell.selection = _peer;
      transition.onBuild(true);
      runFrames();
      expect(shell.configs, [true]);
      expect(shell.opened, isEmpty);
    });

    test('no-op while the breakpoint side is unchanged', () {
      transition.onBuild(false);
      runFrames();
      transition.onBuild(false);
      expect(frames, isEmpty);
    });

    test('wide -> compact reopens the right-pane chat as a route', () {
      shell.wideNow = true;
      transition.onBuild(true);
      runFrames();
      shell
        ..selection = _peer
        ..wideNow = false;
      transition.onBuild(false);
      runFrames();
      expect(shell.configs, [true, false]);
      expect(shell.opened, [_peer]);
    });

    test('wide -> compact leaves it when something covers the shell', () {
      shell.wideNow = true;
      transition.onBuild(true);
      runFrames();
      tracker.didPush(
        MaterialPageRoute<void>(builder: (_) => const SizedBox()),
        shell.home,
      );
      shell
        ..selection = _peer
        ..wideNow = false;
      transition.onBuild(false);
      runFrames();
      expect(shell.opened, isEmpty);
    });

    test('wide -> compact does nothing off the Chats tab', () {
      shell.wideNow = true;
      transition.onBuild(true);
      runFrames();
      shell
        ..selection = _peer
        ..chatsTabIdle = false
        ..wideNow = false;
      transition.onBuild(false);
      runFrames();
      expect(shell.opened, isEmpty);
    });

    test('a newer crossing supersedes a pending one', () {
      shell.wideNow = true;
      transition.onBuild(true);
      runFrames();
      shell.selection = _peer;
      transition.onBuild(false); // superseded before its frame runs
      transition.onBuild(true);
      runFrames();
      expect(shell.configs, [true, true]);
      expect(shell.opened, isEmpty);
    });

    test('an account switch in between cancels the move', () {
      shell.wideNow = true;
      transition.onBuild(true);
      runFrames();
      shell
        ..selection = _peer
        ..wideNow = false;
      transition.onBuild(false);
      shell.account = 'B';
      runFrames();
      expect(shell.opened, isEmpty);
    });

    test('retries the layout mode until UIKit is ready, then moves', () {
      shell.wideNow = true;
      transition.onBuild(true);
      runFrames();
      shell
        ..selection = _peer
        ..wideNow = false
        ..configFailures = 3;
      transition.onBuild(false);
      runFrames();
      expect(shell.configs, [true, false]);
      expect(shell.opened, [_peer]);
    });

    test('a move whose layout switch ran out of attempts still happens', () {
      shell.wideNow = true;
      transition.onBuild(true);
      runFrames();
      shell
        ..selection = _peer
        ..wideNow = false
        ..configFailures = 10;
      transition.onBuild(false);
      runFrames();
      expect(shell.opened, isEmpty);
      transition.onBuild(false); // next build on the same side
      runFrames();
      expect(shell.configs, [true, false]);
      expect(shell.opened, [_peer]);
    });

    test('after the retry budget the next build tries again', () {
      shell
        ..wideNow = true
        ..configFailures = 10;
      transition.onBuild(true);
      runFrames();
      expect(shell.configs, isEmpty);
      transition.onBuild(true); // same side, but nothing is applied yet
      runFrames();
      expect(shell.configs, [true]);
    });
  });

  group('MasterDetailTransition (real navigator)', () {
    testWidgets('compact -> wide pops the chat route, then selects it', (
      tester,
    ) async {
      final tracker = RootRouteTracker.forTest();
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [tracker],
          home: const SizedBox(),
        ),
      );
      final shell = _Shell()
        ..home = tracker.topRoute
        ..navigator = navKey.currentState;
      final transition = MasterDetailTransition(
        host: shell.host,
        tracker: tracker,
      );
      transition.onBuild(false);
      await tester.pump();

      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(
            settings: _chatSettings(_peer),
            builder: (_) => const Text('chat'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('chat'), findsOneWidget);

      shell.wideNow = true;
      transition.onBuild(true);
      await tester.pump();
      // Not reopened while the route is still animating out.
      expect(shell.opened, isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('chat'), findsNothing);
      expect(shell.configs, [false, true]);
      expect(shell.opened, [_peer]);
    });

    testWidgets('compact -> wide leaves a chat covered by another page', (
      tester,
    ) async {
      final tracker = RootRouteTracker.forTest();
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [tracker],
          home: const SizedBox(),
        ),
      );
      final shell = _Shell()
        ..home = tracker.topRoute
        ..navigator = navKey.currentState;
      final transition = MasterDetailTransition(
        host: shell.host,
        tracker: tracker,
      );
      transition.onBuild(false);
      await tester.pump();
      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(
            settings: _chatSettings(_peer),
            builder: (_) => const Text('chat'),
          ),
        ),
      );
      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const Text('group profile')),
        ),
      );
      await tester.pumpAndSettle();

      shell.wideNow = true;
      transition.onBuild(true);
      await tester.pumpAndSettle();
      expect(find.text('group profile'), findsOneWidget);
      expect(shell.opened, isEmpty);
    });

    testWidgets('crossing back mid-pop still reopens the chat', (tester) async {
      final tracker = RootRouteTracker.forTest();
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [tracker],
          home: const SizedBox(),
        ),
      );
      final shell = _Shell()
        ..home = tracker.topRoute
        ..navigator = navKey.currentState;
      final transition = MasterDetailTransition(
        host: shell.host,
        tracker: tracker,
      );
      transition.onBuild(false);
      await tester.pump();
      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(
            settings: _chatSettings(_peer),
            builder: (_) => const Text('chat'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      shell.wideNow = true;
      transition.onBuild(true);
      await tester.pump(); // pop started, exit animation running
      // The popped route unbinds the selection, so only the in-flight
      // target can carry the chat back to the compact layout.
      shell.wideNow = false;
      transition.onBuild(false);
      await tester.pumpAndSettle();
      expect(shell.opened, [_peer]);
    });

    Future<(_Shell, MasterDetailTransition, GlobalKey<NavigatorState>)>
    openChatThenGoWide(WidgetTester tester, RootRouteTracker tracker) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [tracker],
          home: const SizedBox(),
        ),
      );
      final shell = _Shell()
        ..home = tracker.topRoute
        ..navigator = navKey.currentState;
      final transition = MasterDetailTransition(
        host: shell.host,
        tracker: tracker,
      );
      transition.onBuild(false);
      await tester.pump();
      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(
            settings: _chatSettings(_peer),
            builder: (_) => const Text('chat'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      shell.wideNow = true;
      transition.onBuild(true);
      await tester.pump(); // pop started
      return (shell, transition, navKey);
    }

    testWidgets('a page opened during the exit animation is not overridden', (
      tester,
    ) async {
      final tracker = RootRouteTracker.forTest();
      final (shell, _, navKey) = await openChatThenGoWide(tester, tracker);
      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const Text('search')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('search'), findsOneWidget);
      expect(shell.opened, isEmpty);
    });

    testWidgets('a chat picked during the exit animation is not overridden', (
      tester,
    ) async {
      final tracker = RootRouteTracker.forTest();
      final (shell, _, _) = await openChatThenGoWide(tester, tracker);
      shell.selection = const ChatTarget(userID: 'OTHER');
      await tester.pumpAndSettle();
      expect(shell.opened, isEmpty);
    });

    testWidgets('tracker follows push / pop / pushAndRemoveUntil', (
      tester,
    ) async {
      final tracker = RootRouteTracker.forTest();
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [tracker],
          home: const SizedBox(),
        ),
      );
      final root = tracker.topRoute;
      final a = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      unawaited(navKey.currentState!.push(a));
      await tester.pumpAndSettle();
      expect(tracker.topRoute, same(a));
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tracker.topRoute, same(root));
      final b = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      unawaited(navKey.currentState!.pushAndRemoveUntil(b, (_) => false));
      await tester.pumpAndSettle();
      expect(tracker.topRoute, same(b));
    });
  });
}
