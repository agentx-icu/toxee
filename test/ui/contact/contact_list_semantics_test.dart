// I5 (doc/reference/MOBILE_DEVICE_FEATURES.md): the contacts list gives a
// screen reader no unnamed actionable node. AzListView's A-Z bar (a
// GestureDetector: vertical drag + tap) annotates the node around the list;
// in the wide layout that was the Contacts tab page — an unnamed focus stop.
// Rows are their own nodes (the section header above one is not part of its
// label) and not "images".
//
// ignore_for_file: depend_on_referenced_packages
import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact_builders.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_azlist.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

const _actionable = [
  SemanticsAction.tap,
  SemanticsAction.longPress,
  SemanticsAction.scrollUp,
  SemanticsAction.scrollDown,
];

/// Every node offering an action has something to announce.
List<String> _unnamedActionable(WidgetTester tester) {
  final unnamed = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    final acts = _actionable.any(data.hasAction);
    final named =
        data.label.trim().isNotEmpty ||
        data.value.trim().isNotEmpty ||
        data.tooltip.trim().isNotEmpty;
    if (acts && !named) unnamed.add('$node');
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.semantics.find(find.byType(Scaffold)).owner!.rootSemanticsNode!);
  return unnamed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  Future<void> pumpList(WidgetTester tester, List<String> names) async {
    final contact = TencentCloudChat.instance.dataInstance.contact;
    contact.contactBuilder = TencentCloudChatContactBuilders();
    addTearDown(() => contact.contactBuilder = null);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          TencentCloudChatLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) {
              TencentCloudChatIntl().init(context);
              return TencentCloudChatContactAzlist(
                contactList: [
                  for (final name in names)
                    V2TimFriendInfo(userID: name, friendRemark: name),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a short list has no A-Z bar and no unnamed node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpList(tester, ['Alice', 'Bob']);
    expect(find.byType(IndexBar), findsNothing);
    expect(_unnamedActionable(tester), isEmpty);

    final row = tester.getSemantics(find.text('Alice'));
    expect(row.label, isNot(startsWith('A\n')), reason: 'header not merged');
    expect(row.label, contains('Alice'));
    handle.dispose();
  });

  testWidgets('with the A-Z bar, its gestures land on a named node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpList(tester, ['Alice', 'Bob', 'Carol', 'Dave', 'Erin', 'Frank']);
    expect(find.byType(IndexBar), findsOneWidget);
    expect(_unnamedActionable(tester), isEmpty);
    handle.dispose();
  });
}
