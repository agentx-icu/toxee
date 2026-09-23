// GF-4 — forwarding must not fail silently.
//
//   * `sendForwardIndividuallyMessage` fired `sendMessageFinalPhase` inside a
//     `Future.delayed` and dropped the result: a failed forward — and every
//     forward to a conversation other than the open one has no bubble to turn
//     red — was never reported. It now awaits each send and reports failures
//     through `callbacks.onSDKFailed("sendMessage", …)`, which toxee renders
//     (SendFailureNotifier).
//   * Media into a group is unsupported by design (Tox file transfer is
//     friend-only). The forward picker now asks the host's media-send guard
//     per GROUP target (the same guard hold-to-record / drag-drop / paste use,
//     which explains the refusal) and does not send media there; text still
//     goes.
//
// Shared UIKit-fork Dart: the forward picker/data layer is the same on desktop
// (popup) and phone/tablet (sheet) — mobile covered.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_callbacks.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/common/media_send_guard.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

class _ForwardPlatform extends TencentCloudChatSdkPlatform {
  _ForwardPlatform(this.sources);

  final Map<String, V2TimMessage> sources;
  final Set<String> failReceivers = {};
  final List<({String receiver, String groupID})> sends = [];
  int _seq = 0;

  @override
  bool get isCustomPlatform => true;

  @override
  void removeUIKitListener({String? uuid}) {}

  @override
  Future<V2TimValueCallback<V2TimMsgCreateInfoResult>> createForwardMessage({
    String? msgID,
    String? webMessageInstance,
  }) async {
    final src = sources[msgID]!;
    final msg = V2TimMessage(
      elemType: src.elemType,
      textElem: src.textElem,
      imageElem: src.imageElem,
      isSelf: true,
    );
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMsgCreateInfoResult(id: 'fwd_${_seq++}', messageInfo: msg),
    );
  }

  @override
  Future<V2TimValueCallback<V2TimMessage>> sendMessage({
    String? id,
    required String receiver,
    required String groupID,
    int priority = 0,
    bool onlineUserOnly = false,
    bool? needReadReceipt,
    bool? isExcludedFromUnreadCount,
    bool? isExcludedFromLastMessage,
    bool? isSupportMessageExtension,
    bool? isExcludedFromContentModeration,
    Map<String, dynamic>? offlinePushInfo,
    String? cloudCustomData,
    String? localCustomData,
  }) async {
    sends.add((receiver: receiver, groupID: groupID));
    if (failReceivers.contains(receiver)) {
      return V2TimValueCallback(code: -1, desc: 'Friend is offline');
    }
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT, msgID: id),
    );
  }
}

final _text = V2TimMessage(
  msgID: 'src_text',
  elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
  textElem: V2TimTextElem(text: 'hello'),
);
final _image = V2TimMessage(
  msgID: 'src_image',
  elemType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
  imageElem: V2TimImageElem(path: '/tmp/x.png'),
);

/// The data layer reads `tL10n` (message summaries, error texts): mount a
/// localized tree first so the fork's i18n singleton is initialized.
Future<void> _initIntl(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
    localizationsDelegates: const [
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(builder: (context) {
      TencentCloudChatIntl().init(context);
      return const SizedBox();
    }),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  late _ForwardPlatform platform;
  late TencentCloudChatSdkPlatform oldPlatform;
  late List<({String api, int code, String desc})> failures;
  late TencentCloudChatCallbacks sink;

  setUp(() {
    platform = _ForwardPlatform({'src_text': _text, 'src_image': _image});
    oldPlatform = TencentCloudChatSdkPlatform.instance;
    TencentCloudChatSdkPlatform.instance = platform;
    failures = [];
    sink = TencentCloudChatCallbacks(
      onTencentCloudChatSDKFailedCallback: (api, code, desc) =>
          failures.add((api: api, code: code, desc: desc)),
    );
    TencentCloudChat.instance.callbacks.addCallback(sink);
  });

  tearDown(() {
    TencentCloudChat.instance.callbacks.removeCallback(sink);
    TencentCloudChatSdkPlatform.instance = oldPlatform;
    TencentCloudChat.instance.dataInstance.messageData.messageConfig =
        TencentCloudChatMessageConfig();
  });

  testWidgets('a failed forward is awaited and reported through onSDKFailed',
      (tester) async {
    await _initIntl(tester);
    platform.failReceivers.add('friend2');
    final provider = TencentCloudChatMessageSeparateDataProvider();
    final ok = await tester.runAsync(() => provider.sendForwardIndividuallyMessage(
      ['src_text'],
      [(userID: 'friend2', groupID: null), (userID: 'friend3', groupID: null)],
    ));
    expect(platform.sends.map((s) => s.receiver), ['friend2', 'friend3']);
    expect(ok, isFalse);
    expect(failures, hasLength(1));
    expect(failures.single.api, 'sendMessage');
    expect(failures.single.desc, contains('offline'));
    provider.dispose();
  });

  testWidgets('media is not sent to a refused group; text still is',
      (tester) async {
    await _initIntl(tester);
    final provider = TencentCloudChatMessageSeparateDataProvider();
    await tester.runAsync(() => provider.sendForwardIndividuallyMessage(
      ['src_image', 'src_text'],
      [(userID: null, groupID: 'tox_group_1'), (userID: 'friend2', groupID: null)],
      mediaRefusedGroupIDs: {mediaRefusalKey('tox_group_1', 'image')},
    ));
    expect(platform.sends, [
      (receiver: 'friend2', groupID: ''),
      (receiver: '', groupID: 'tox_group_1'),
      (receiver: 'friend2', groupID: ''),
    ]);
    expect(failures, isEmpty);
    provider.dispose();
  });

  testWidgets('the picker asks the host guard once per group, only for media', (
    tester,
  ) async {
    final asked = <({String kind, String? groupID})>[];
    TencentCloudChat.instance.dataInstance.messageData.messageConfig =
        TencentCloudChatMessageConfig(
      attachmentConfig: ({userID, groupID, topicID}) =>
          TencentCloudChatMessageAttachmentConfig(
        mediaSendGuard: (context, {required kind, userID, groupID}) {
          asked.add((kind: kind, groupID: groupID));
          return groupID == null || groupID.isEmpty;
        },
      ),
    );
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final chats = [
      (userID: null, groupID: 'tox_group_1'),
      (userID: 'friend2', groupID: null),
      (userID: null, groupID: 'tox_group_2'),
      (userID: null, groupID: 'tox_group_1'),
    ];

    expect(tencentCloudChatMediaRefusedGroupTargets(ctx, [_text], chats),
        isEmpty);
    expect(asked, isEmpty, reason: 'text-only forwards never ask');

    expect(
      tencentCloudChatMediaRefusedGroupTargets(ctx, [_text, _image], chats),
      {
        mediaRefusalKey('tox_group_1', 'image'),
        mediaRefusalKey('tox_group_2', 'image'),
      },
    );
    expect(asked, [
      (kind: 'image', groupID: 'tox_group_1'),
      (kind: 'image', groupID: 'tox_group_2'),
    ]);
  });

  // An INCOMING media message that is not downloaded yet carries no media elem
  // (Tim2Tox builds one only once a local path exists) — only its elemType
  // says what it is. Deciding by elem presence called it "not media", so
  // forwarding it into a group skipped the refusal.
  test('media kind is decided by elemType, not by a downloaded elem', () {
    V2TimMessage bare(int elemType) => V2TimMessage(elemType: elemType);
    expect(tencentCloudChatMediaKindOf(
            bare(MessageElemType.V2TIM_ELEM_TYPE_IMAGE)),
        'image');
    expect(tencentCloudChatMediaKindOf(
            bare(MessageElemType.V2TIM_ELEM_TYPE_SOUND)),
        'voice');
    expect(tencentCloudChatMediaKindOf(
            bare(MessageElemType.V2TIM_ELEM_TYPE_VIDEO)),
        'file');
    expect(tencentCloudChatMediaKindOf(
            bare(MessageElemType.V2TIM_ELEM_TYPE_FILE)),
        'file');
    expect(tencentCloudChatMediaKindOf(_text), isNull);
    expect(tencentCloudChatMediaKindOf(
            bare(MessageElemType.V2TIM_ELEM_TYPE_CUSTOM)),
        isNull);
    // No elemType at all: the elem is still honoured.
    expect(
        tencentCloudChatMediaKindOf(V2TimMessage(
            elemType: MessageElemType.V2TIM_ELEM_TYPE_NONE,
            fileElem: V2TimFileElem(path: '/tmp/f.bin'))),
        'file');
  });

  testWidgets('an undownloaded incoming file is refused for a group target', (
    tester,
  ) async {
    TencentCloudChat.instance.dataInstance.messageData.messageConfig =
        TencentCloudChatMessageConfig(
      attachmentConfig: ({userID, groupID, topicID}) =>
          TencentCloudChatMessageAttachmentConfig(
        mediaSendGuard: (context, {required kind, userID, groupID}) =>
            groupID == null || groupID.isEmpty,
      ),
    );
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final incomingFile = V2TimMessage(
      msgID: 'incoming_file',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_FILE,
      isSelf: false,
    );
    expect(
      tencentCloudChatMediaRefusedGroupTargets(ctx, [incomingFile], [
        (userID: null, groupID: 'tox_group_1'),
        (userID: 'friend2', groupID: null),
      ]),
      {mediaRefusalKey('tox_group_1', 'file')},
    );
  });

  // A group that refuses one kind must still receive the kinds it allows.
  testWidgets('a refusal applies only to its own media kind', (tester) async {
    TencentCloudChat.instance.dataInstance.messageData.messageConfig =
        TencentCloudChatMessageConfig(
      attachmentConfig: ({userID, groupID, topicID}) =>
          TencentCloudChatMessageAttachmentConfig(
        mediaSendGuard: (context, {required kind, userID, groupID}) =>
            kind != 'image', // images refused, everything else allowed
      ),
    );
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final voice = V2TimMessage(
      msgID: 'src_voice',
      elemType: MessageElemType.V2TIM_ELEM_TYPE_SOUND,
      soundElem: V2TimSoundElem(path: '/tmp/a.m4a'),
    );
    expect(
      tencentCloudChatMediaRefusedGroupTargets(ctx, [_image, voice], [
        (userID: null, groupID: 'tox_group_1'),
      ]),
      {mediaRefusalKey('tox_group_1', 'image')},
      reason: 'the voice message is allowed and must not be refused with it',
    );
  });
}
