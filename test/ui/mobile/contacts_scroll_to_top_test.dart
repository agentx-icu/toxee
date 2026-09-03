// Contacts scroll-to-top controller (plan item L6).
//
// Re-tapping the active bottom-nav tab should send that list back to the top.
// Tab 0 already had `TencentCloudChatConversationController.instance
// .scrollToTop()`; the contacts tab had nothing, which is what the TODO at
// lib/ui/home_page.dart recorded. The fork now exposes the SAME shape on
// `TencentCloudChatContactManager.controller`, and the contacts A-Z list binds
// to that controller, so the host dispatches by tab index instead of reaching
// into widget internals with a GlobalKey.
//
// SCOPE, stated honestly: the HomePage dispatch itself is not hermetically
// pumpable from `test/` — `HomePage.build()` binds UIKit globals and builds
// every tab, which is why test/ui/mobile/home_bottom_nav_real_ui_test.dart
// routes that structure to a host bundle. What is gateable here is the new
// controller contract the dispatch depends on, driven through a real
// scrollable.
//
// Shared Dart: the controller and the contacts list are platform-agnostic, so
// this covers iOS/Android as well as desktop.
//
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list_for_us/scrollable_positioned_list_for_us.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart';

void main() {
  testWidgets('scrollToTop sends the registered list back to the first item', (
    tester,
  ) async {
    final controller = TencentCloudChatContactManager.controller;
    final positions = ItemPositionsListener.create();
    // Stand in for the contacts list's own State-owned controller, registered
    // exactly the way TencentCloudChatContactAzlistState registers it.
    final listController = ItemScrollController();
    controller.registerScrollController(listController);
    addTearDown(() => controller.unregisterScrollController(listController));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The same list type AzListView is built on.
          body: ScrollablePositionedList.builder(
            itemScrollController: listController,
            itemPositionsListener: positions,
            itemCount: 200,
            itemBuilder: (_, i) => SizedBox(height: 40, child: Text('row $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(listController.isAttached, isTrue);

    listController.jumpTo(index: 120);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(positions.itemPositions.value.first.index, greaterThan(0));

    // Drive the animation with explicit frames rather than pumpAndSettle:
    // ScrollablePositionedList's scrollTo drives its own animation controller
    // and pumpAndSettle can wait on it indefinitely in a test binding.
    final done = controller.scrollToTop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await done;
    expect(positions.itemPositions.value.first.index, 0);
  });

  testWidgets('scrollToTop is a no-op when no contacts list is mounted', (
    tester,
  ) async {
    // The bottom-nav can be re-tapped while the contacts tab has never been
    // built (IndexedStack builds lazily), so an unattached controller must not
    // throw — same guarantee the conversation controller gives.
    final controller = TencentCloudChatContactManager.controller;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump();

    await controller.scrollToTop();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a disposing older list cannot unhook the visible one', (
    tester,
  ) async {
    // Two contacts lists can exist at once (master-detail, a route pushed over
    // the tab). ItemScrollController is single-attach, so each list owns its
    // own; the newest registration wins and a late dispose of the older one
    // must not revoke it.
    final controller = TencentCloudChatContactManager.controller;
    final older = ItemScrollController();
    final newer = ItemScrollController();
    final positions = ItemPositionsListener.create();

    controller.registerScrollController(older);
    controller.registerScrollController(newer);
    controller.unregisterScrollController(older);
    addTearDown(() => controller.unregisterScrollController(newer));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedList.builder(
            itemScrollController: newer,
            itemPositionsListener: positions,
            itemCount: 200,
            itemBuilder: (_, i) => SizedBox(height: 40, child: Text('row $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    newer.jumpTo(index: 120);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(positions.itemPositions.value.first.index, greaterThan(0));

    final done = controller.scrollToTop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await done;
    expect(positions.itemPositions.value.first.index, 0,
        reason: 'the still-mounted list must remain the one scrollToTop drives');
  });

  testWidgets('a list that never unregisters cannot grow the stack forever', (
    tester,
  ) async {
    // Defensive bound: dispose normally removes the entry, but a State that
    // never runs it would otherwise leak one per mount. The visible list must
    // still win afterwards.
    final controller = TencentCloudChatContactManager.controller;
    final positions = ItemPositionsListener.create();
    for (var i = 0; i < 40; i++) {
      controller.registerScrollController(ItemScrollController());
    }
    final visible = ItemScrollController();
    controller.registerScrollController(visible);
    addTearDown(() => controller.unregisterScrollController(visible));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedList.builder(
            itemScrollController: visible,
            itemPositionsListener: positions,
            itemCount: 200,
            itemBuilder: (_, i) => SizedBox(height: 40, child: Text('row $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    visible.jumpTo(index: 120);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(positions.itemPositions.value.first.index, greaterThan(0));

    final done = controller.scrollToTop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await done;
    expect(positions.itemPositions.value.first.index, 0);
  });

  testWidgets('the older list regains the target when the newer one pops', (
    tester,
  ) async {
    // The other order, and the common one: a route pushed over the contacts
    // tab registers on top, then pops. The list underneath is on screen again
    // and must become the target once more — with a single slot cleared on
    // dispose it would be orphaned and the gesture would do nothing.
    final controller = TencentCloudChatContactManager.controller;
    final older = ItemScrollController();
    final newer = ItemScrollController();
    final positions = ItemPositionsListener.create();

    controller.registerScrollController(older);
    addTearDown(() => controller.unregisterScrollController(older));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedList.builder(
            itemScrollController: older,
            itemPositionsListener: positions,
            itemCount: 200,
            itemBuilder: (_, i) => SizedBox(height: 40, child: Text('row $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The pushed list registers, then pops.
    controller.registerScrollController(newer);
    controller.unregisterScrollController(newer);

    older.jumpTo(index: 120);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(positions.itemPositions.value.first.index, greaterThan(0));

    final done = controller.scrollToTop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await done;
    expect(positions.itemPositions.value.first.index, 0,
        reason: 'popping the newer list must hand the target back, not null it');
  });
}
