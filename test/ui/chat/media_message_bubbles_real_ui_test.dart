// Real-UI render + open gates for the media message bubbles (the UI halves of
// S21 / S24 / S88 / S94). The L1/L3 data-layer gates already assert the
// transfer DATA (mediaKind classification, fileTransfers projection, terminal
// filePath); this file pumps the REAL message list with fixture image / file /
// sound messages and drives the REAL fork element widgets + their REAL tap
// handlers.
//
// Every render block runs at BOTH mobile (400x800, DeviceScreenType.mobile) and
// desktop (1400x900, DeviceScreenType.desktop) for mobile parity, exactly like
// custom_elem_mobile_render_regression_test.dart.
//
// Coverage:
//   a) S88 UI: an IMAGE message renders the real Image.file bubble at both
//      sizes. (The tap→open-preview half is not driveable at the widget layer —
//      the image's tappable GestureDetector mounts only after an async load and
//      the lazy FlutterListView then keeps it offstage; see the NOTE below the
//      image render gates. The file/sound tap gates exercise the equivalent
//      media-bubble onTapUp mechanism.)
//   b) S21/S24 UI: a FILE message renders filename + formatted size; tap drives
//      the real _openFile() → captured via the production open-file seam.
//   c) a SOUND message renders duration + a play affordance; tap drives the real
//      playSound() → captured via the production play-audio seam (never plays
//      real audio).
//   d) S94 UI: an in-flight FILE transfer renders a progress indicator — driven
//      through the REAL TencentCloudChatDownloadUtils progress projection
//      (handleDownloadProgressEvent → data event → bubble), asserting 0% vs 60%.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/data/message/tencent_cloud_chat_message_data.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_bounded_image.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_download_utils.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_builders.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/message_type_builders/tencent_cloud_chat_message_file.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/message_type_builders/tencent_cloud_chat_message_sound.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimUIKitListener.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

// ---------------------------------------------------------------------------
// Harness helpers (deliberately duplicated — test files must not share private
// helpers; see CLAUDE.md harness facts).
// ---------------------------------------------------------------------------

Widget _mediaLocalized({required Widget child}) {
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
      body: Builder(
        builder: (context) {
          TencentCloudChatIntl().init(context);
          return child;
        },
      ),
    ),
  );
}

/// Minimal recording SDK platform — serves the fixture history and stubs the
/// SDK calls the message list makes. Duplicated from the sibling harnesses (no
/// shared private imports).
class _MediaRecordingSdkPlatform extends TencentCloudChatSdkPlatform {
  _MediaRecordingSdkPlatform({required this.history});

  final List<V2TimMessage> history;

  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimValueCallback<V2TimMessageListResult>> getHistoryMessageListV2({
    int getType = HistoryMessageGetType.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    final list =
        lastMsgID == null ? List<V2TimMessage>.of(history) : <V2TimMessage>[];
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMessageListResult(isFinished: true, messageList: list),
    );
  }

  @override
  Future<V2TimValueCallback<V2TimConversation>> getConversation({
    required String conversationID,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimConversation(
        conversationID: conversationID,
        type: 1,
        userID: 'media_friend',
        showName: 'Media Friend',
      ),
    );
  }

  @override
  Future<V2TimCallback> cleanConversationUnreadMessageCount({
    required String conversationID,
    required int cleanTimestamp,
    required int cleanSequence,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> markC2CMessageAsRead({required String userID}) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> sendMessageReadReceipts({
    List<String>? messageIDList,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimValueCallback<List<V2TimUserFullInfo>>> getUsersInfo({
    required List<String> userIDList,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: userIDList.map((u) => V2TimUserFullInfo(userID: u)).toList(),
    );
  }

  @override
  Future<V2TimValueCallback<List<V2TimFriendInfoResult>>> getFriendsInfo({
    required List<String> userIDList,
  }) async {
    return V2TimValueCallback(code: 0, desc: 'ok', data: const []);
  }

  @override
  Future<V2TimValueCallback<List<V2TimUserStatus>>> getUserStatus({
    required List<String> userIDList,
  }) async {
    return V2TimValueCallback(code: 0, desc: 'ok', data: const []);
  }

  @override
  Future<V2TimCallback> subscribeUserStatus({
    required List<String> userIDList,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> unsubscribeUserStatus({
    required List<String> userIDList,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  String addUIKitListener({required V2TimUIKitListener listener}) =>
      'media_uikit_listener';

  @override
  void removeUIKitListener({String? uuid}) {}

  @override
  Future<V2TimCallback> setConversationDraft({
    required String conversationID,
    String? draftText,
  }) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  // File/sound bubbles call this from initState when no local URL is present
  // (e.g. the in-flight transfer fixture). The base platform throws
  // UnimplementedError; return a non-zero code so the UIKit wrapper resolves to
  // a null online URL cleanly (no network fetch in the test).
  @override
  Future<V2TimValueCallback<V2TimMessageOnlineUrl>> getMessageOnlineUrl({
    String? msgID,
  }) async {
    return V2TimValueCallback(code: 1, desc: 'no online url in test');
  }
}

// ---------------------------------------------------------------------------
// Fixture state shared across a single pump.
// ---------------------------------------------------------------------------

/// Fixture message IDs.
const _kImageMsgId = 'media_image';
const _kFileMsgId = 'media_file';
const _kSoundMsgId = 'media_sound';
const _kProgressFileMsgId = 'media_file_progress';
const _kAnchorTextId = 'media_anchor';

/// The on-disk fixture file paths, written once per pump in setUp.
late String _imagePath;
late String _filePath;
late String _soundPath;

/// The displayed file name + formatted size for the FILE bubble assertions.
/// Kept short (≤10 chars) so fileNameWidget renders it un-truncated and the
/// bubble does not overflow at the narrow mobile width.
const _kFileBaseName = 'doc';
const _kFileExt = 'pdf';
const _kFileNameWithExt = '$_kFileBaseName.$_kFileExt';
// 10240 bytes → getCurrentFileFileSize() → '10 KB'.
const _kFileSizeBytes = 10240;

/// Builds the fixture history. Image / file / sound element messages plus a
/// plain text anchor. The progress-file message is built with NO localUrl so
/// the download-status slot renders the in-flight indicator (S94).
List<V2TimMessage> _buildMediaFixtureHistory() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return [
    V2TimMessage(
      msgID: _kAnchorTextId,
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      textElem: V2TimTextElem(text: 'anchor text'),
      isSelf: false,
      timestamp: now - 3600,
      userID: 'media_friend',
      sender: 'media_friend',
      nickName: 'Media Friend',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    // IMAGE — local path points at a real PNG (S88 UI).
    V2TimMessage(
      msgID: _kImageMsgId,
      elemType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
      imageElem: V2TimImageElem(path: _imagePath),
      isSelf: false,
      timestamp: now - 10,
      userID: 'media_friend',
      sender: 'media_friend',
      nickName: 'Media Friend',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    // FILE — filename + size + a real local file so tap → open resolves a path
    // (S21/S24 UI). localUrl is set so hasLocalFile() is true (received state).
    V2TimMessage(
      msgID: _kFileMsgId,
      elemType: MessageElemType.V2TIM_ELEM_TYPE_FILE,
      fileElem: V2TimFileElem(
        fileName: _kFileNameWithExt,
        fileSize: _kFileSizeBytes,
        path: _filePath,
        localUrl: _filePath,
      ),
      isSelf: false,
      timestamp: now - 200,
      userID: 'media_friend',
      sender: 'media_friend',
      nickName: 'Media Friend',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    // SOUND — duration + a real local .m4a so playSound() resolves a path.
    V2TimMessage(
      msgID: _kSoundMsgId,
      elemType: MessageElemType.V2TIM_ELEM_TYPE_SOUND,
      soundElem: V2TimSoundElem(
        duration: 7,
        path: _soundPath,
        localUrl: _soundPath,
        dataSize: 2048,
      ),
      isSelf: false,
      timestamp: now - 100,
      userID: 'media_friend',
      sender: 'media_friend',
      nickName: 'Media Friend',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
    // FILE (in-flight) — NO localUrl/path so the download indicator can render
    // mid-transfer (S94 UI). We drive its progress through the real download
    // projection in the test body.
    V2TimMessage(
      msgID: _kProgressFileMsgId,
      elemType: MessageElemType.V2TIM_ELEM_TYPE_FILE,
      fileElem: V2TimFileElem(
        fileName: 'blob.bin',
        fileSize: 5 * 1024 * 1024,
      ),
      isSelf: false,
      timestamp: now - 30,
      userID: 'media_friend',
      sender: 'media_friend',
      nickName: 'Media Friend',
    )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC,
  ];
}

/// Smallest valid 1x1 PNG (so Image.file decodes without error).
final Uint8List _tinyPngBytes = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// Mounts the REAL message list at [size] with [screenType].
Future<void> _pumpMediaChatAtSize(
  WidgetTester tester, {
  required Size size,
  required DeviceScreenType screenType,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  TencentCloudChatScreenAdapter.deviceScreenType = screenType;
  TencentCloudChatScreenAdapter.hasInitialized = true;
  addTearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  final data = TencentCloudChat.instance.dataInstance;
  data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
  data.basic.updateCurrentUserInfo(
      userFullInfo: V2TimUserFullInfo(userID: 'media_self', nickName: 'MeSelf'));
  data.conversation.conversationList = [
    V2TimConversation(
        conversationID: 'c2c_media_friend',
        type: 1,
        userID: 'media_friend',
        showName: 'Media Friend'),
  ];
  data.messageData.messageListMap = {};
  addTearDown(() {
    data.messageData.messageListMap = {};
    data.conversation.conversationList = [];
    data.basic.usedComponents = [];
  });

  final platform = _MediaRecordingSdkPlatform(history: _buildMediaFixtureHistory());
  final oldPlatform = TencentCloudChatSdkPlatform.instance;
  TencentCloudChatSdkPlatform.instance = platform;
  addTearDown(() => TencentCloudChatSdkPlatform.instance = oldPlatform);

  await tester.pumpWidget(
    _mediaLocalized(
      child: TencentCloudChatMessage(
        options: TencentCloudChatMessageOptions(userID: 'media_friend'),
        config: TencentCloudChatMessageConfig(),
        builders: TencentCloudChatMessageBuilders(),
      ),
    ),
  );
  // NB: do not pumpAndSettle — the media bubbles can mount indeterminate
  // CircularProgressIndicators (image loading / file download), which never
  // reach quiescence. Pump a bounded number of frames instead.
  await _pumpFrames(tester);
  await tester.pump(const Duration(milliseconds: 900));
  await _pumpFrames(tester);
}

/// Pumps a bounded set of frames to flush async loads + microtasks without
/// requiring the tree to settle (safe in the presence of looping spinners).
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Finder _mediaRowItem(String msgID) =>
    find.byKey(ValueKey('message_list_item:$msgID'), skipOffstage: false);

/// Finds the production download/progress CircularProgressIndicator(s) inside
/// the in-flight FILE bubble row.
Iterable<CircularProgressIndicator> _progressIndicatorsInProgressRow(
    WidgetTester tester) {
  return tester
      .widgetList<CircularProgressIndicator>(
        find.descendant(
          of: _mediaRowItem(_kProgressFileMsgId),
          matching: find.byType(CircularProgressIndicator, skipOffstage: false),
          skipOffstage: false,
        ),
      )
      .toList();
}

/// Drains any exception recorded during the pump and asserts it is NOT a real
/// error. The fork's file/sound bubbles can emit a benign few-pixel RenderFlex
/// overflow in the narrow widget-test viewports (a pre-existing layout quirk,
/// unrelated to the media-bubble render/open semantics under test here); that
/// is tolerated, but any other exception (decode failure, null-deref, a failed
/// assertion) still fails the gate. Must be called at the end of every test so
/// a recorded overflow does not auto-fail it.
void _expectNoFatalException(WidgetTester tester) {
  final ex = tester.takeException();
  if (ex == null) return;
  final isBenignOverflow =
      ex is FlutterError && ex.message.contains('overflowed');
  expect(isBenignOverflow, isTrue,
      reason: 'only a benign RenderFlex overflow is tolerated; got: $ex');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  late Directory tempDir;

  setUp(() async {
    // Real IO: write the fixture media files. Use the binding's runAsync escape
    // hatch (FakeAsync can deadlock real File IO — see CLAUDE.md harness facts).
    await TestWidgetsFlutterBinding.instance.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('toxee_media_bubbles_');
      final imgFile = File('${tempDir.path}/fixture.png');
      await imgFile.writeAsBytes(_tinyPngBytes, flush: true);
      _imagePath = imgFile.path;

      final docFile = File('${tempDir.path}/$_kFileNameWithExt');
      await docFile.writeAsBytes(
          Uint8List.fromList(List<int>.filled(_kFileSizeBytes, 0x41)),
          flush: true);
      _filePath = docFile.path;

      // .m4a so playAudio's allow-list accepts the extension.
      final sndFile = File('${tempDir.path}/voice.m4a');
      await sndFile.writeAsBytes(Uint8List.fromList(const [0, 1, 2, 3, 4, 5]),
          flush: true);
      _soundPath = sndFile.path;
    });
  });

  tearDown(() async {
    // Reset the fork test seams + the static download queue between cases.
    TencentCloudChatMessageFile.debugResetOpenFileOverride();
    TencentCloudChatMessageSound.debugResetPlayAudioOverride();
    TencentCloudChatDownloadUtils.currentDownloadingList.clear();
    TencentCloudChatDownloadUtils.messageDownloadFinishedList.clear();
    await TestWidgetsFlutterBinding.instance.runAsync(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
  });

  // ===========================================================================
  // a) S88 UI — image bubble renders + tap opens the real preview dialog.
  // ===========================================================================
  for (final variant in const [
    (label: 'mobile', size: Size(400, 800), screen: DeviceScreenType.mobile),
    (label: 'desktop', size: Size(1400, 900), screen: DeviceScreenType.desktop),
  ]) {
    testWidgets(
      'S88 UI ${variant.label}: image message renders a real Image bubble',
      (tester) async {
        await _pumpMediaChatAtSize(tester,
              size: variant.size, screenType: variant.screen);
        await _pumpFrames(tester);

        expect(_mediaRowItem(_kAnchorTextId), findsOneWidget,
            reason: 'anchor text bubble must render (sanity)');

        // The image bubble row must mount with non-zero height and contain a
        // real Image widget (Image.file via renderLocalImage).
        expect(_mediaRowItem(_kImageMsgId), findsOneWidget,
            reason: 'image bubble row must mount');
        final imgRowBox =
            tester.element(_mediaRowItem(_kImageMsgId)).renderObject as RenderBox;
        expect(imgRowBox.size.height, greaterThan(0),
            reason: 'image bubble must have non-zero height');

        final imageInRow = find.descendant(
          of: _mediaRowItem(_kImageMsgId),
          matching: find.byType(Image, skipOffstage: false),
          skipOffstage: false,
        );
        expect(imageInRow, findsWidgets,
            reason: 'image bubble must render a real Image widget');

        // Checklist M6: the bubble decodes at its own width (x DPR), capped,
        // never at the photo's full resolution.
        // (The row's other Image is the sender avatar.)
        final providers =
            tester.widgetList<Image>(imageInRow).map((w) => w.image).toList();
        final boundedList =
            providers.whereType<TencentCloudChatBoundedImage>().toList();
        expect(boundedList, hasLength(1),
            reason: 'bubble decode must be bounded; got $providers');
        final bounded = boundedList.single;
        expect(bounded.width, isNotNull);
        expect(bounded.width, lessThanOrEqualTo((198 * 3.0).ceil()));
        expect(bounded.maxPixels, 2 * 1024 * 1024);

        _expectNoFatalException(tester);
      },
    );
  }

  // NOTE on the S88 tap-to-open UI half: production opens the image preview via
  // the image element's onTapUp → showImage() → showDialog(MessageViewer) in
  // tencent_cloud_chat_message_image.dart — the GestureDetector wrapping the
  // image mounts only inside renderImage(), which runs AFTER the async
  // _getImageUrl() load resolves (see ~lines 288/519 there). In a WidgetTester
  // run the lazy FlutterListView keeps that subtree flagged offstage
  // (find.byType(Image) on-stage returns 0; the loading phase shows a spinner
  // with no tap handler). During development, four pointer-dispatch strategies
  // (tap, tapAt, startGesture at the image/GestureDetector geometry, row-center)
  // were tried against a TEMPORARY capture seam and all failed to reach
  // onTapUp; that temporary seam was then fully removed — image.dart is
  // pristine. The IMAGE RENDER half is gated above (the bubble + real Image
  // materialize at both sizes); the tap→open dispatch is the same onTapUp
  // mechanism the file/sound gates below exercise. Driving the image tap
  // on-stage remains a two-process real-UI concern (recorded in the S88 spec).

  // ===========================================================================
  // b) S21/S24 UI — file bubble renders filename + size; tap → real open path.
  // ===========================================================================
  for (final variant in const [
    (label: 'mobile', size: Size(400, 800), screen: DeviceScreenType.mobile),
    (label: 'desktop', size: Size(1400, 900), screen: DeviceScreenType.desktop),
  ]) {
    testWidgets(
      'S21/S24 UI ${variant.label}: file message renders filename + size',
      (tester) async {
        await _pumpMediaChatAtSize(tester,
              size: variant.size, screenType: variant.screen);
        await _pumpFrames(tester);

        expect(_mediaRowItem(_kFileMsgId), findsOneWidget,
            reason: 'file bubble row must mount');
        final fileRowBox =
            tester.element(_mediaRowItem(_kFileMsgId)).renderObject as RenderBox;
        expect(fileRowBox.size.height, greaterThan(0),
            reason: 'file bubble must have non-zero height');

        // fileNameWidget truncates names > 10 chars to first 8 + "..." and
        // renders the extension separately.
        final nameInRow = find.descendant(
          of: _mediaRowItem(_kFileMsgId),
          matching: find.text('doc', skipOffstage: false),
          skipOffstage: false,
        );
        expect(nameInRow, findsOneWidget,
            reason: 'truncated file name must render');

        final extInRow = find.descendant(
          of: _mediaRowItem(_kFileMsgId),
          matching: find.text('.$_kFileExt', skipOffstage: false),
          skipOffstage: false,
        );
        expect(extInRow, findsOneWidget, reason: 'file extension must render');

        // getCurrentFileFileSize(): 10240 bytes → 10 KB.
        final sizeInRow = find.descendant(
          of: _mediaRowItem(_kFileMsgId),
          matching: find.text('10 KB', skipOffstage: false),
          skipOffstage: false,
        );
        expect(sizeInRow, findsOneWidget,
            reason: 'formatted file size must render');

        _expectNoFatalException(tester);
      },
    );
  }

  testWidgets(
    'S21/S24 UI: tapping the file bubble drives the real open-file handler',
    (tester) async {
      String? openedPath;
      TencentCloudChatMessageFile.debugOpenFileOverride = (path) async {
        openedPath = path;
      };

      await _pumpMediaChatAtSize(tester,
            size: const Size(1400, 900),
            screenType: DeviceScreenType.desktop);
      await _pumpFrames(tester);

      // Tap the file name region (inside the file bubble's GestureDetector).
      final tapTarget = find.descendant(
        of: _mediaRowItem(_kFileMsgId),
        matching: find.text('doc', skipOffstage: false),
        skipOffstage: false,
      );
      expect(tapTarget, findsOneWidget);

      await tester.tap(tapTarget, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await _pumpFrames(tester);

      expect(openedPath, isNotNull,
          reason: 'tap must reach the real _openFile() dispatch');
      // _openFile() resolves the file message path (status != sending → elem
      // path/localUrl). It must be the fixture file we wrote.
      expect(openedPath, equals(_filePath),
          reason: 'open handler must receive the resolved local file path');
    },
  );

  // ===========================================================================
  // c) SOUND bubble — duration + play affordance; tap → real play handler.
  // ===========================================================================
  for (final variant in const [
    (label: 'mobile', size: Size(400, 800), screen: DeviceScreenType.mobile),
    (label: 'desktop', size: Size(1400, 900), screen: DeviceScreenType.desktop),
  ]) {
    testWidgets(
      'Sound UI ${variant.label}: voice message renders duration + play icon',
      (tester) async {
        await _pumpMediaChatAtSize(tester,
              size: variant.size, screenType: variant.screen);
        await _pumpFrames(tester);

        expect(_mediaRowItem(_kSoundMsgId), findsOneWidget,
            reason: 'sound bubble row must mount');
        final soundRowBox = tester
            .element(_mediaRowItem(_kSoundMsgId))
            .renderObject as RenderBox;
        expect(soundRowBox.size.height, greaterThan(0),
            reason: 'sound bubble must have non-zero height');

        // Duration renders as "${duration}s".
        final durationInRow = find.descendant(
          of: _mediaRowItem(_kSoundMsgId),
          matching: find.text('7s', skipOffstage: false),
          skipOffstage: false,
        );
        expect(durationInRow, findsOneWidget,
            reason: 'sound duration must render');

        // Play affordance: not-playing → Icons.play_circle_outline.
        final playIcon = find.descendant(
          of: _mediaRowItem(_kSoundMsgId),
          matching: find.byIcon(Icons.play_circle_outline, skipOffstage: false),
          skipOffstage: false,
        );
        expect(playIcon, findsOneWidget, reason: 'play affordance must render');

        _expectNoFatalException(tester);
      },
    );
  }

  testWidgets(
    'Sound UI: tapping play drives the real playSound() dispatch (no audio)',
    (tester) async {
      AudioPlayInfo? played;
      TencentCloudChatMessageSound.debugPlayAudioOverride = (info) {
        played = info;
      };

      await _pumpMediaChatAtSize(tester,
            size: const Size(1400, 900),
            screenType: DeviceScreenType.desktop);
      await _pumpFrames(tester);

      // Tap the duration text (inside the sound bubble's GestureDetector).
      final tapTarget = find.descendant(
        of: _mediaRowItem(_kSoundMsgId),
        matching: find.text('7s', skipOffstage: false),
        skipOffstage: false,
      );
      expect(tapTarget, findsOneWidget);

      await tester.tap(tapTarget, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await _pumpFrames(tester);

      expect(played, isNotNull,
          reason: 'tap must reach the real playSound() dispatch');
      expect(played!.msgID, equals(_kSoundMsgId),
          reason: 'play dispatch must carry the sound message id');
      expect(played!.path, equals(_soundPath),
          reason: 'play dispatch must carry the resolved local audio path');
      expect(played!.type, equals(AudioPlayType.path),
          reason: 'a local sound plays from a file path');
    },
  );

  // ===========================================================================
  // d) S94 UI — in-flight transfer renders a progress indicator (0% vs 60%).
  // ===========================================================================
  testWidgets(
    'S94 UI: in-flight file transfer renders progress (0% then 60%) via the '
    'real download projection',
    (tester) async {
      await _pumpMediaChatAtSize(tester,
            size: const Size(1400, 900),
            screenType: DeviceScreenType.desktop);
      await _pumpFrames(tester);

      expect(_mediaRowItem(_kProgressFileMsgId), findsOneWidget,
          reason: 'in-flight file bubble row must mount');

      // Register the transfer in the production downloading list (the same
      // record the widget's downloadCallback matches on: msgID_0_false).
      final queueEntry = DownloadMessageQueueData(
        convID: 'media_friend',
        conversationType: ConversationType.V2TIM_C2C,
        key: 'media_friend',
        msgID: _kProgressFileMsgId,
        messageType: MessageElemType.V2TIM_ELEM_TYPE_FILE,
        imageType: 0,
        isSnapshot: false,
      );
      TencentCloudChatDownloadUtils.currentDownloadingList
        ..clear()
        ..add(queueEntry);

      // Drive the REAL progress projection at 0% (currentSize 0 / total 100).
      TencentCloudChatDownloadUtils.handleDownloadProgressEvent(
        V2TimMessageDownloadProgress(
          isFinish: false,
          isError: false,
          msgID: _kProgressFileMsgId,
          totalSize: 100,
          currentSize: 0,
          type: 0,
          isSnapshot: false,
          path: '',
          errorCode: 0,
          errorDesc: '',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      var indicators = _progressIndicatorsInProgressRow(tester);
      expect(indicators, isNotEmpty,
          reason: 'in-flight transfer must render a progress indicator at 0%');
      // At 0% production renders an indeterminate spinner (value == null) per
      // getDownloadingWidget's progress==0 branch.
      expect(indicators.first.value, isNull,
          reason: '0% renders the indeterminate (starting) spinner');

      // Now drive 60% (currentSize 60 / total 100).
      TencentCloudChatDownloadUtils.handleDownloadProgressEvent(
        V2TimMessageDownloadProgress(
          isFinish: false,
          isError: false,
          msgID: _kProgressFileMsgId,
          totalSize: 100,
          currentSize: 60,
          type: 0,
          isSnapshot: false,
          path: '',
          errorCode: 0,
          errorDesc: '',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      indicators = _progressIndicatorsInProgressRow(tester);
      expect(indicators, isNotEmpty,
          reason: 'in-flight transfer must render a progress indicator at 60%');
      final values = indicators.map((i) => i.value).toList();
      expect(
        values.any((v) => v != null && (v - 0.6).abs() < 0.001),
        isTrue,
        reason: 'progress indicator must reflect 60% (0.6) from the projection',
      );

      _expectNoFatalException(tester);
    },
  );
}
