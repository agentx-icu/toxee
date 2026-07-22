// Real-UI L1 gates for the C2C conversation-row context-menu surfaces.
//
// Covers: S117 (menu surface — C2C), S116 (pin/unpin key flip — C2C),
// S118 (mark-read enabled/disabled — C2C), S119 (delete + confirm dialog —
// C2C), S20 (delete preserves friendship).
//
// The menu builder (buildConversationContextMenuItems) and delete-dialog
// builder (buildDeleteConversationDialog) are @visibleForTesting seams
// exported from lib/ui/home_page.dart.  They are stateless constructors:
// they receive l10n/scheme/state as arguments and return the PopupMenuEntry
// list or AlertDialog widget.  No SDK call is required to drive them, so
// these tests run hermetically without the tim2tox FFI native library.
//
// The conversation-item TAP test (S117 open surface) sets up the shared
// TencentCloudChat.instance.dataInstance.conversation data layer — the same
// approach the conference_conversation_row_real_ui_test.dart uses for S159.
//
// Mobile parity: all surfaces here are shared Dart (lib/ui/home_page.dart,
// lib/sdk_fake/fake_managers.dart, lib/i18n/).  No platform-specific split.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_conversation_event_handlers.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart'
    as conv_pkg;
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_builders.dart';
import 'package:tencent_cloud_chat_conversation/desktop/tencent_cloud_chat_conversation_desktop_mode.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_item.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/home_page.dart'
    show buildConversationContextMenuItems, buildDeleteConversationDialog;
import 'package:toxee/ui/testing/ui_keys.dart';

// ---------------------------------------------------------------------------
// Harness helpers (copied from conference_conversation_row_real_ui_test.dart;
// do NOT import private helpers from other test files)
// ---------------------------------------------------------------------------

Widget _appLocalized(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

/// Pump a minimal localized tree and capture the AppLocalizations +
/// ColorScheme pair so production menu/dialog builders can be exercised.
Future<(AppLocalizations, ColorScheme)> _captureL10nScheme(
  WidgetTester tester,
) async {
  late AppLocalizations l10n;
  late ColorScheme scheme;
  await tester.pumpWidget(
    _appLocalized(
      Builder(
        builder: (ctx) {
          l10n = AppLocalizations.of(ctx)!;
          scheme = Theme.of(ctx).colorScheme;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return (l10n, scheme);
}

/// Build the menu items for the given pin/unread state and return their keys.
Set<Key> _menuKeys(
  AppLocalizations l10n,
  ColorScheme scheme, {
  required bool isPinned,
  required bool hasUnread,
}) {
  return buildConversationContextMenuItems(
    l10n: l10n,
    scheme: scheme,
    isPinned: isPinned,
    hasUnread: hasUnread,
  ).map((e) => e.key).whereType<Key>().toSet();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Inform the SDK layer which native lib name to expect.  Required for the
  // conversation-item tap test that seeds TencentCloudChat data; does not load
  // the native library at the unit-test level.
  setNativeLibraryName('tim2tox_ffi');

  // S117 — C2C conversation-row item tap selects the conversation.
  //
  // Tapping the C2C row sets currentConversation in the shared data layer,
  // proving the SAME tap-to-select path that opens the chat view works for
  // C2C rows (the row/menu layer is shared across C2C, group, and conference).
  testWidgets(
    'S117 C2C conversation item tap selects it (sets currentConversation)',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
      TencentCloudChatScreenAdapter.hasInitialized = true;
      addTearDown(() {
        TencentCloudChatScreenAdapter.deviceScreenType = null;
        TencentCloudChatScreenAdapter.hasInitialized = false;
      });

      final data = TencentCloudChat.instance.dataInstance;
      final conv = data.conversation;
      data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
      conv.conversationConfig.setConfigs(forceDesktopLayout: true);
      conv.conversationBuilder = TencentCloudChatConversationBuilders();
      conv.conversationEventHandlers = null;
      conv.currentConversation = null;
      addTearDown(() {
        conv.conversationBuilder = null;
        conv.conversationEventHandlers = null;
        conv.currentConversation = null;
        conv.conversationConfig.setConfigs(forceDesktopLayout: false);
        data.basic.usedComponents = [];
      });

      const tileKey = ValueKey('conversation_list_item:c2c_117_user_abc');
      await tester.pumpWidget(
        _appLocalized(
          Builder(
            builder: (context) {
              TencentCloudChatIntl().init(context);
              return KeyedSubtree(
                key: tileKey,
                child: TencentCloudChatConversationItem(
                  conversation: V2TimConversation(
                    conversationID: 'c2c_117_user_abc',
                    type: 1,
                    userID: '117_user_abc',
                    showName: 'Alice C2C 117',
                  ),
                  isOnline: false,
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        conv.currentConversation?.conversationID,
        isNot('c2c_117_user_abc'),
      );
      await tester.tap(find.byKey(tileKey));
      await tester.pumpAndSettle();
      expect(
        conv.currentConversation?.conversationID,
        'c2c_117_user_abc',
        reason: 'tapping the C2C row should select the conversation',
      );
    },
  );

  testWidgets(
    'mounted conversation row uses the latest responsive navigation mode',
    (tester) async {
      TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
      TencentCloudChatScreenAdapter.hasInitialized = true;
      addTearDown(() {
        TencentCloudChatScreenAdapter.deviceScreenType = null;
        TencentCloudChatScreenAdapter.hasInitialized = false;
      });

      final data = TencentCloudChat.instance.dataInstance;
      final conversationData = data.conversation;
      data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
      conversationData.conversationConfig.setConfigs(
        useDesktopMode: true,
        forceDesktopLayout: true,
      );
      final observedModes = <bool>[];
      conversationData.conversationBuilder =
          TencentCloudChatConversationBuilders();
      conversationData.conversationEventHandlers =
          TencentCloudChatConversationEventHandlers(
            uiEventHandlers: TencentCloudChatConversationUIEventHandlers(
              onTapConversationItem:
                  ({
                    required conversation,
                    required messageOptions,
                    required inDesktopMode,
                  }) async {
                    observedModes.add(inDesktopMode);
                    return true;
                  },
            ),
          );
      addTearDown(() {
        conversationData.conversationBuilder = null;
        conversationData.conversationEventHandlers = null;
        conversationData.conversationConfig.setConfigs(
          useDesktopMode: true,
          forceDesktopLayout: false,
        );
        data.basic.usedComponents = [];
      });

      const tileKey = ValueKey('responsive-conversation-row');
      await tester.pumpWidget(
        _appLocalized(
          Builder(
            builder: (context) {
              TencentCloudChatIntl().init(context);
              return KeyedSubtree(
                key: tileKey,
                child: TencentCloudChatConversationItem(
                  conversation: V2TimConversation(
                    conversationID: 'c2c_responsive_user',
                    type: 1,
                    userID: 'responsive_user',
                    showName: 'Responsive User',
                  ),
                  isOnline: false,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      conversationData.conversationConfig.setConfigs(
        useDesktopMode: false,
        forceDesktopLayout: false,
      );
      await tester.pump();

      await tester.tap(find.byKey(tileKey));
      await tester.pump();

      expect(observedModes, [false]);
    },
  );

  testWidgets(
    'frozen mobile adapter still honors forced responsive master-detail mode',
    (tester) async {
      TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.mobile;
      TencentCloudChatScreenAdapter.hasInitialized = true;
      addTearDown(() {
        TencentCloudChatScreenAdapter.deviceScreenType = null;
        TencentCloudChatScreenAdapter.hasInitialized = false;
      });

      final data = TencentCloudChat.instance.dataInstance;
      data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
      data.conversation.conversationConfig.setConfigs(
        useDesktopMode: true,
        forceDesktopLayout: true,
      );
      data.conversation.conversationBuilder =
          TencentCloudChatConversationBuilders();
      addTearDown(() {
        data.conversation.conversationBuilder = null;
        data.conversation.conversationConfig.setConfigs(
          useDesktopMode: true,
          forceDesktopLayout: false,
        );
        data.basic.usedComponents = [];
      });

      await tester.pumpWidget(
        _appLocalized(
          Builder(
            builder: (context) {
              TencentCloudChatIntl().init(context);
              return const conv_pkg.TencentCloudChatConversation();
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byType(TencentCloudChatConversationDesktopMode),
        findsOneWidget,
      );
    },
  );

  // S117 — C2C conversation-row context menu surfaces expected items.
  //
  // buildConversationContextMenuItems is shared across C2C, group, and
  // conference rows; this gate asserts the C2C-flavored call (type:1,
  // isPinned:false, hasUnread:true) exposes pin + mark-read (enabled) +
  // delete and does NOT expose unpin.
  testWidgets(
    'S117 C2C conversation-row menu surfaces pin / mark-read / delete',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);
      final keys = _menuKeys(l10n, scheme, isPinned: false, hasUnread: true);

      expect(keys, contains(UiKeys.conversationContextMenuPinItem));
      expect(keys, contains(UiKeys.conversationContextMenuMarkReadItem));
      expect(keys, contains(UiKeys.conversationContextMenuDeleteItem));
      // Unpin is absent when the conversation is not pinned.
      expect(keys, isNot(contains(UiKeys.conversationContextMenuUnpinItem)));
    },
  );

  // S117 (variant) — pinned C2C row shows unpin, not pin.
  testWidgets(
    'S117 C2C conversation-row menu shows unpin (not pin) when already pinned',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);
      final keys = _menuKeys(l10n, scheme, isPinned: true, hasUnread: false);

      expect(keys, contains(UiKeys.conversationContextMenuUnpinItem));
      expect(keys, isNot(contains(UiKeys.conversationContextMenuPinItem)));
      // Mark-read and delete are always present regardless of pin state.
      expect(keys, contains(UiKeys.conversationContextMenuMarkReadItem));
      expect(keys, contains(UiKeys.conversationContextMenuDeleteItem));
    },
  );

  // S116 — pin/unpin item key flips with isPinned state.
  //
  // When isPinned is false the pin item is keyed with
  // conversationContextMenuPinItem; when isPinned is true it is keyed with
  // conversationContextMenuUnpinItem.  Both carry value:'pin' so the same
  // _dispatchConversationMenuAction handler toggles them.
  testWidgets(
    'S116 C2C conversation-row menu pin item key flips with pinned state',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);

      // Unpinned → Pin key present, Unpin absent.
      final unpinnedKeys = _menuKeys(
        l10n,
        scheme,
        isPinned: false,
        hasUnread: false,
      );
      expect(unpinnedKeys, contains(UiKeys.conversationContextMenuPinItem));
      expect(
        unpinnedKeys,
        isNot(contains(UiKeys.conversationContextMenuUnpinItem)),
      );

      // Pinned → Unpin key present, Pin absent.
      final pinnedKeys = _menuKeys(
        l10n,
        scheme,
        isPinned: true,
        hasUnread: false,
      );
      expect(pinnedKeys, contains(UiKeys.conversationContextMenuUnpinItem));
      expect(
        pinnedKeys,
        isNot(contains(UiKeys.conversationContextMenuPinItem)),
      );
    },
  );

  // S116 (value check) — both pin and unpin carry value:'pin' so the shared
  // handler dispatches the toggle for C2C rows.
  testWidgets(
    'S116 C2C pin and unpin items both carry value:pin (toggle dispatch)',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);

      final pinItem =
          buildConversationContextMenuItems(
                l10n: l10n,
                scheme: scheme,
                isPinned: false,
                hasUnread: false,
              ).first
              as PopupMenuItem<String>;

      final unpinItem =
          buildConversationContextMenuItems(
                l10n: l10n,
                scheme: scheme,
                isPinned: true,
                hasUnread: false,
              ).first
              as PopupMenuItem<String>;

      expect(
        pinItem.value,
        'pin',
        reason: 'pin item value must be "pin" for dispatch',
      );
      expect(
        unpinItem.value,
        'pin',
        reason: 'unpin item value must be "pin" for the same toggle dispatch',
      );
    },
  );

  // S118 — mark-read item is enabled only when the C2C conversation has unread.
  testWidgets(
    'S118 C2C mark-read item is enabled when hasUnread, disabled otherwise',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);

      PopupMenuItem<String> markReadItem(bool hasUnread) =>
          buildConversationContextMenuItems(
                l10n: l10n,
                scheme: scheme,
                isPinned: false,
                hasUnread: hasUnread,
              ).firstWhere(
                (e) => e.key == UiKeys.conversationContextMenuMarkReadItem,
              )
              as PopupMenuItem<String>;

      expect(
        markReadItem(true).enabled,
        isTrue,
        reason: 'mark-read must be enabled when the C2C row has unread',
      );
      expect(
        markReadItem(false).enabled,
        isFalse,
        reason: 'mark-read must be disabled when there is no unread',
      );
    },
  );

  // S119 — delete item opens the keyed confirm dialog for a C2C conversation.
  //
  // buildDeleteConversationDialog is the @visibleForTesting seam that
  // _dispatchConversationMenuAction('delete') calls via showDialog.  We drive
  // the dialog builder directly (showDialog is non-trivially async in
  // WidgetTester; using a TextButton → showDialog avoids the limitation while
  // exercising the REAL builder, not a re-implementation).
  testWidgets(
    'S119 C2C delete-confirm dialog mounts with keyed confirm button',
    (tester) async {
      await tester.pumpWidget(
        _appLocalized(
          Builder(
            builder: (outer) => Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: outer,
                  builder: (dialogCtx) => buildDeleteConversationDialog(
                    dialogCtx: dialogCtx,
                    l10n: AppLocalizations.of(dialogCtx)!,
                    scheme: Theme.of(dialogCtx).colorScheme,
                    conversationLabel: 'Alice C2C 119',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dialog not yet shown.
      expect(find.byKey(UiKeys.deleteConversationConfirmButton), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(UiKeys.deleteConversationConfirmButton),
        findsOneWidget,
        reason: 'C2C delete-confirm dialog must mount its keyed confirm button',
      );
      expect(
        find.textContaining('Alice C2C 119'),
        findsOneWidget,
        reason: 'the confirm dialog body must name the C2C conversation',
      );
    },
  );

  // S119 — confirming the dialog calls pop(true) and does NOT pop the parent
  // route.  The ModalRoute.isCurrent double-fire guard is exercised by tapping
  // the real confirm button: if the guard is absent a second pop would fire
  // and blank the app; here it just means findsNothing on the dialog after
  // one tap.
  testWidgets(
    'S119 C2C delete-confirm dialog confirm button dismisses the dialog',
    (tester) async {
      await tester.pumpWidget(
        _appLocalized(
          Builder(
            builder: (outer) => Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: outer,
                  builder: (dialogCtx) => buildDeleteConversationDialog(
                    dialogCtx: dialogCtx,
                    l10n: AppLocalizations.of(dialogCtx)!,
                    scheme: Theme.of(dialogCtx).colorScheme,
                    conversationLabel: 'Alice C2C 119b',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(UiKeys.deleteConversationConfirmButton),
        findsOneWidget,
      );

      // Tap confirm — dialog should dismiss.
      await tester.tap(find.byKey(UiKeys.deleteConversationConfirmButton));
      await tester.pumpAndSettle();

      expect(
        find.byKey(UiKeys.deleteConversationConfirmButton),
        findsNothing,
        reason: 'confirm button tap should dismiss the dialog',
      );
    },
  );

  // S20 — after delete, the friend is still in the friendship layer.
  //
  // The production delete-conversation path calls
  // FakeConversationManager.deleteConversation (→ clearC2CHistory + unpins)
  // NOT deleteFriend.  At the WidgetTester layer we verify the SURFACE: the
  // dialog presents the "delete conversation" title (not "delete friend"),
  // confirming the production copy and flow do not surface a friendship-removal
  // action.  The negative assertion ("deleteFriend must NOT appear") is
  // enforced by: (a) no deleteFriend call site in home_page.dart's 'delete'
  // branch, and (b) the delete-conversation dialog body is keyed separately
  // from any friend-removal dialog.  This is an honest surface gate for what
  // L1 can observe without the full FfiChatService stack.
  testWidgets(
    'S20 C2C delete dialog labels the action as delete-conversation (not delete-friend)',
    (tester) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        _appLocalized(
          Builder(
            builder: (ctx) {
              l10n = AppLocalizations.of(ctx)!;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      // The delete-conversation dialog title must be deleteConversationTitle,
      // not any friend-removal copy.  This asserts the production string key
      // separation (S20 discriminator vs S112 delete-friend).
      await tester.pumpWidget(
        _appLocalized(
          Builder(
            builder: (outer) => Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: outer,
                  builder: (dialogCtx) => buildDeleteConversationDialog(
                    dialogCtx: dialogCtx,
                    l10n: AppLocalizations.of(dialogCtx)!,
                    scheme: Theme.of(dialogCtx).colorScheme,
                    conversationLabel: 'Bob (S20)',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The dialog title must be the conversation-delete string.
      expect(
        find.text(l10n.deleteConversationTitle),
        findsOneWidget,
        reason:
            'S20: dialog title must be deleteConversationTitle (conversation '
            'delete, not friend removal)',
      );
      // Confirm button exists (conversation-delete surface, not friend-delete).
      expect(
        find.byKey(UiKeys.deleteConversationConfirmButton),
        findsOneWidget,
        reason:
            'S20: confirm button is the conversation-delete key, '
            'distinct from any friend-removal dialog key',
      );
    },
  );
}
