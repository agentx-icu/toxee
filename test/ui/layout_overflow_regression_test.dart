// Layout-overflow regression gates from the 2026-09-11 all-platform audit.
//
// Every case here reproduces a CONFIRMED overflow at the viewport / text
// scale where it happened (landscape phone with insets, 320-px phone, 1.5–2×
// accessibility text) and asserts geometry, not just `takeException()==null`:
// a Positioned child clipped by its Stack or two controls painted on top of
// each other never throws, so bounds are checked explicitly.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_list_view/message_list/default_builder.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_list_view/message_row/tencent_cloud_chat_message_row.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_list_view/message_row/tencent_cloud_chat_message_row_message_sender_name.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_header/tencent_cloud_chat_message_header_select_mode.dart';
import 'package:toxee/call/call_audio_platform.dart';
import 'package:toxee/call/call_audio_route_sheet.dart';
import 'package:toxee/call/call_floating_widget.dart';
import 'package:toxee/call/in_call_manager.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/call/call_ui_components.dart';
import 'package:toxee/call/call_ui_shell.dart';
import 'package:toxee/call/ringing_call_manager.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/app_theme_data.dart';
import 'package:toxee/ui/group/group_display_name.dart';
import 'package:toxee/ui/settings/bootstrap_node_verdict.dart';
import 'package:toxee/util/responsive_layout.dart';

class _RouteManager implements InCallManager {
  String? selected;

  @override
  final ValueNotifier<CallAudioState> audioState = ValueNotifier(
    const CallAudioState(
      sessionActive: true,
      selectedRouteId: 'earpiece',
      routes: [
        CallAudioRoute(
          id: 'earpiece',
          kind: CallAudioRouteKind.earpiece,
          label: 'Phone',
          selected: true,
        ),
        CallAudioRoute(
          id: 'speaker',
          kind: CallAudioRouteKind.speaker,
          label: 'Speaker',
          selected: false,
        ),
      ],
    ),
  );
  @override
  final ValueNotifier<ui.Image?> remoteVideo = ValueNotifier<ui.Image?>(null);
  @override
  final ValueNotifier<int> previewListenable = ValueNotifier<int>(0);
  @override
  Widget? localPreview;
  @override
  Future<void> toggleMute() async {}
  @override
  Future<void> toggleVideo() async {}
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> toggleSpeaker() async {}
  @override
  Future<void> hangUp() async {}
  @override
  Future<void> selectAudioRoute(String routeId) async => selected = routeId;
}

class _FakeRingingCallManager implements RingingCallManager {
  @override
  Future<void> acceptCall() async {}
  @override
  Future<void> rejectCall() async {}
  @override
  Future<void> hangUp() async {}
}

void _useView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The test host is a desktop OS, which pins every ResponsiveLayout tier to
/// "desktop" (64-px dock buttons, 24-px padding). Phone cases must opt out.
void _usePhonePlatform() {
  ResponsiveLayout.debugIsDesktopPlatformOverride = () => false;
  addTearDown(() => ResponsiveLayout.debugIsDesktopPlatformOverride = null);
}

void _useTextScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Production typography (line heights differ from the stock Material theme,
/// and the call shell's reserves are derived from them).
Widget _app(Widget home) {
  return MaterialApp(
    theme: buildLightTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

/// The system insets the shell must respect (iPhone 14 landscape: 21-px
/// home indicator at the bottom, 47-px notch on each side).
const _landscapeInsets = EdgeInsets.only(left: 47, right: 47, bottom: 21);

const _stageKey = ValueKey('overflow-test-stage');
const _dockKey = ValueKey('overflow-test-dock');
const _topBarKey = ValueKey('overflow-test-top-bar');

List<CallDockAction> _fiveVideoActions() => const [
      CallDockAction(key: ValueKey('a0'), icon: Icons.mic, label: 'Mute'),
      CallDockAction(key: ValueKey('a1'), icon: Icons.videocam, label: 'Video Off'),
      CallDockAction(key: ValueKey('a2'), icon: Icons.cameraswitch, label: 'Switch Camera'),
      CallDockAction(key: ValueKey('a3'), icon: Icons.route, label: 'Route Selection'),
      CallDockAction(key: ValueKey('a4'), icon: Icons.call_end, label: 'Hang up', destructive: true),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallSceneShell', () {
    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets(
          'audio stage never sits under the dock on a landscape phone (text ${scale}x)',
          (tester) async {
        _usePhonePlatform();
        _useView(tester, const Size(844, 390));
        _useTextScale(tester, scale);
        await tester.pumpWidget(_app(
          MediaQuery(
            data: MediaQueryData(
              size: const Size(844, 390),
              padding: _landscapeInsets,
              textScaler: TextScaler.linear(scale),
            ),
            child: CallSceneShell(
              topBar: const CallTopStatusBar(
                key: _topBarKey,
                title: 'Alice',
                subtitle: '00:32',
                trailingIcon: Icons.picture_in_picture_alt,
              ),
              bottomBar: CallActionDock(key: _dockKey, actions: _fiveVideoActions()),
              // The REAL identity stage (avatar 86 + title + subtitle + note):
              // ~223 px at 2×, more than the stage has on a landscape phone.
              child: CallIdentityStage(
                key: _stageKey,
                avatar: const CircleAvatar(radius: 43, child: Text('A')),
                title: 'Alice With A Rather Long Display Name',
                subtitle: '00:32',
                secondaryNote: 'Reconnecting…',
              ),
            ),
          ),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
        final stage = tester.getRect(find.byKey(_stageKey));
        final dock = tester.getRect(find.byKey(_dockKey));
        final topBar = tester.getRect(find.byKey(_topBarKey));
        expect(stage.bottom, lessThanOrEqualTo(dock.top),
            reason: 'identity block must end above the dock');
        expect(stage.top, greaterThanOrEqualTo(topBar.bottom),
            reason: 'identity block must start below the top bar');
        expect(dock.bottom, lessThanOrEqualTo(390 - _landscapeInsets.bottom),
            reason: 'dock respects the home-indicator inset');
        expect(stage.left, greaterThanOrEqualTo(_landscapeInsets.left));
        // At 1× the avatar shrinks so the whole identity block fits without
        // scrolling. At larger text the stage scrolls (and clips — nothing
        // paints under the dock); every element must be reachable inside it.
        for (final text in const ['00:32', 'Reconnecting…']) {
          // Scoped to the stage: the top bar shows the same "00:32" subtitle.
          final f = find.descendant(
            of: find.byKey(_stageKey),
            matching: find.text(text),
          );
          if (scale == 1.0) {
            expect(tester.getRect(f).bottom, lessThanOrEqualTo(stage.bottom + 0.01),
                reason: '$text must be visible at 1x without scrolling');
          }
          await tester.ensureVisible(f);
          await tester.pump();
          final r = tester.getRect(f);
          expect(r.top, greaterThanOrEqualTo(stage.top - 0.01), reason: text);
          expect(r.bottom, lessThanOrEqualTo(stage.bottom + 0.01), reason: text);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('overlay (video) mode reserves the real top-bar height', (tester) async {
      _usePhonePlatform();
      _useView(tester, const Size(390, 844));
      await tester.pumpWidget(_app(
        Builder(builder: (context) {
          return CallSceneShell(
            overlayBars: true,
            topBar: const CallTopStatusBar(
              key: _topBarKey,
              title: 'Alice',
              subtitle: '00:32',
              trailingIcon: Icons.picture_in_picture_alt,
            ),
            bottomBar: CallActionDock(key: _dockKey, actions: _fiveVideoActions(), showLabels: false),
            child: const SizedBox.expand(),
          );
        }),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final topBar = tester.getRect(find.byKey(_topBarKey));
      final reserved = CallSceneShell.topBarHeight(
        tester.element(find.byKey(_topBarKey)),
      );
      expect(topBar.height, lessThanOrEqualTo(reserved + 0.01),
          reason: 'topBarHeight() is what overlay children clear; the bar '
              'must not be taller than it (was 72 vs a 56 reserve)');
    });
  });

  group('CallActionDock', () {
    for (final width in const [320.0, 375.0]) {
      testWidgets('five icon-only actions fit one row on a $width-px phone',
          (tester) async {
        _usePhonePlatform();
        _useView(tester, Size(width, 667));
        await tester.pumpWidget(_app(Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              // Shell horizontal padding on mobile is 12 each side; use 16 to
              // leave the assertion some margin.
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CallActionDock(actions: _fiveVideoActions(), showLabels: false),
            ),
          ),
        )));
        await tester.pump();
        expect(tester.takeException(), isNull);
        final rects = [
          for (var i = 0; i < 5; i++) tester.getRect(find.byKey(ValueKey('a$i'))),
        ];
        expect(rects.map((r) => r.top).toSet(), hasLength(1),
            reason: 'all five buttons share one Wrap run');
        for (final r in rects) {
          expect(r.width, greaterThanOrEqualTo(44),
              reason: 'buttons shrink to fit but never below the 44-px target');
        }
        expect(find.text('Route Selection'), findsNothing,
            reason: 'labels are dropped in compact mode (kept as tooltips)');
        expect(find.byTooltip('Route Selection'), findsOneWidget);
      });
    }
  });

  group('CallFloatingWidget', () {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('compact card holds two text lines at text ${scale}x', (tester) async {
        _usePhonePlatform();
        _useView(tester, const Size(375, 667));
        _useTextScale(tester, scale);
        final callState = CallStateNotifier()
          ..startRinging(
            mode: CallMode.audio,
            direction: CallDirection.outgoing,
            inviteID: 'invite-overflow',
            remoteUserID: 'alice',
            remoteNickname: 'Alice With A Rather Long Display Name',
          )
          ..enterCall()
          ..minimize();
        await tester.pumpWidget(_app(Stack(children: [
          const SizedBox.expand(),
          CallFloatingWidget(callState: callState, manager: _FakeRingingCallManager()),
        ])));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'the old fixed 56-px card overflowed vertically from ~1.2x');
        // The hang-up InkWell itself is the 44-px accessibility target.
        final hangUpTarget = tester.getRect(
          find.ancestor(
            of: find.byIcon(Icons.call_end),
            matching: find.byType(InkWell),
          ).first,
        );
        expect(hangUpTarget.width, greaterThanOrEqualTo(44));
        expect(hangUpTarget.height, greaterThanOrEqualTo(44));
        final card = tester.getRect(find.byKey(const ValueKey('floating-call-card')));
        expect(card.height, greaterThanOrEqualTo(60),
            reason: '44-px hang-up hit target + 2×8 padding');
        expect(hangUpTarget.bottom, lessThanOrEqualTo(card.bottom + 0.01));
        callState.endCall();
        await tester.pump(const Duration(seconds: 3));
      });
    }
  });

  group('call audio-route sheet', () {
    testWidgets(
        'opens ABOVE an opaque call surface that has no Navigator ancestor, '
        'and closes itself when the call is minimized', (tester) async {
      // Production shape: MaterialApp.builder stacks the call's own Overlay
      // over the app Navigator, so the call view has no Navigator above it.
      late BuildContext opener;
      final manager = _RouteManager();
      final callState = CallStateNotifier()
        ..startRinging(
          mode: CallMode.audio,
          direction: CallDirection.outgoing,
          inviteID: 'invite-route',
          remoteUserID: 'alice',
          remoteNickname: 'Alice',
        )
        ..enterCall();
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox.expand(),
        builder: (context, child) => Stack(children: [
          child!,
          Overlay(initialEntries: [
            OverlayEntry(builder: (ctx) {
              opener = ctx;
              return const ColoredBox(
                color: Colors.black,
                child: SizedBox.expand(),
              );
            }),
          ]),
        ]),
      ));
      expect(Navigator.maybeOf(opener), isNull,
          reason: 'harness must reproduce the Navigator-less call surface');

      final l10n = AppLocalizations.of(opener)!;
      final speaker = find.byKey(UiKeys.callAudioRouteOption('speaker'));

      showCallAudioRouteSheet(opener, manager, l10n, callState: callState);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(speaker.hitTestable(), findsOneWidget,
          reason: 'the sheet must paint and hit-test above the call surface');
      await tester.tap(speaker);
      await tester.pump();
      expect(manager.selected, 'speaker');
      expect(speaker, findsNothing, reason: 'choosing a route closes the sheet');

      showCallAudioRouteSheet(opener, manager, l10n, callState: callState);
      await tester.pump();
      expect(speaker, findsOneWidget);
      callState.minimize();
      await tester.pump();
      await tester.pump();
      expect(speaker, findsNothing,
          reason: 'an overlay sheet is not a route; minimize must close it');

      callState.endCall();
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('StatusPill', () {
    testWidgets('long UDP verdict wraps inside a 200-px slot', (tester) async {
      // Hosted the way the settings section does (Align / Wrap = bounded).
      await tester.pumpWidget(_app(Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: const StatusPill(
                label: 'Node test needs UDP; this device is running TCP-only',
                color: Colors.orange,
              ),
            ),
          ),
        ),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'the pill\'s inner Row handed the label unbounded width');
      expect(tester.getRect(find.byType(StatusPill)).width, lessThanOrEqualTo(200));
    });
  });

  group('groupDisplayName', () {
    test('shortens the raw 64-hex ID fallback and keeps real names', () {
      final id = 'A' * 64;
      expect(groupDisplayName(null, id), 'AAAAAAAA…AAAAAAAA');
      expect(groupDisplayName(id, id), 'AAAAAAAA…AAAAAAAA');
      expect(groupDisplayName('Dev Team', id), 'Dev Team');
      expect(groupDisplayName('', 'short-id'), 'short-id');
    });
  });

  group('fork message package', () {
    setUp(() {
      TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
      TencentCloudChatScreenAdapter.hasInitialized = true;
    });
    tearDown(() {
      TencentCloudChatScreenAdapter.deviceScreenType = null;
      TencentCloudChatScreenAdapter.hasInitialized = false;
    });

    Widget forkApp(double paneWidth, Widget Function(BuildContext) build) {
      return MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          TencentCloudChatLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(builder: (context) {
            TencentCloudChatIntl().init(context);
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: paneWidth, child: build(context)),
            );
          }),
        ),
      );
    }

    testWidgets('select-mode header fits a 268-px pane at 2x text', (tester) async {
      _useView(tester, const Size(268, 600));
      _useTextScale(tester, 2.0);
      await tester.pumpWidget(forkApp(
        268,
        (c) => TencentCloudChatMessageHeaderSelectMode(
          selectAmount: 12,
          onCancelSelect: () {},
          onClearSelect: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Clear / Cancel were unbounded non-flex buttons');
      for (final key in const [
        'message_select_clear_button',
        'message_select_count_text',
        'message_select_cancel_button',
      ]) {
        final r = tester.getRect(find.byKey(ValueKey(key)));
        expect(r.left, greaterThanOrEqualTo(-0.01), reason: key);
        expect(r.right, lessThanOrEqualTo(268.01), reason: key);
      }
    });

    testWidgets('unread divider fits a 320-px pane', (tester) async {
      _useView(tester, const Size(320, 568));
      await tester.pumpWidget(forkApp(320, (c) => defaultUnreadMsgTipBuilder(c, 3)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'two fixed 100-px rules + label were ~370 px');
      expect(find.text('Unread Messages Below'), findsOneWidget);
    });

    testWidgets('desktop row: a 128-char sender name stays inside a 428-px pane',
        (tester) async {
      _useView(tester, const Size(960, 600));
      const paneWidth = 428.0;
      final longName = 'N' * 128;
      final msg = V2TimMessage.fromJson({})
        ..msgID = 'm-1'
        ..elemType = 1
        ..isSelf = false
        ..sender = 'peer'
        ..nickName = longName
        ..timestamp = 1;
      await tester.pumpWidget(forkApp(
        paneWidth,
        (c) => TencentCloudChatMessageRow(
          data: MessageRowBuilderData(
            message: msg,
            messageRowWidth: paneWidth,
            showMessageSenderName: true,
            inSelectMode: false,
            isSelected: false,
            isMergeMessage: false,
            showMessageStatusIndicator: false,
            showSelfAvatar: true,
            showOthersAvatar: true,
            showMessageTimeIndicator: false,
            hasStickerPlugin: false,
          ),
          methods: MessageRowBuilderMethods(
            onSelectCurrent: (_) {},
            loadToSpecificMessage: ({
              required bool highLightTargetMessage,
              V2TimMessage? message,
              int? timeStamp,
              int? seq,
            }) async =>
                true,
          ),
          widgets: MessageRowBuilderWidgets(
            messageRowAvatar: const SizedBox(width: 36, height: 36),
            messageRowMessageSenderName: TencentCloudChatMessageRowMessageSenderName(
              data: MessageRowMessageSenderNameBuilderData(
                message: msg,
                messageSenderName: longName,
              ),
              methods: MessageRowMessageSenderNameBuilderMethods(),
            ),
            messageRowMessageItem: const SizedBox(width: 120, height: 40),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'desktopBuilder held the name in an unbounded Column');
      final nameBox = tester.getRect(find.byType(TencentCloudChatMessageRowMessageSenderName));
      expect(nameBox.right, lessThanOrEqualTo(paneWidth + 0.01));
    });
  });
}
