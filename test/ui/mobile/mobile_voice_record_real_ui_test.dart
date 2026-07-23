// Real-UI widget tests for the MOBILE voice-record surface — the fork
// `TencentCloudChatMessageInputRecording` widget (the S78 record UI) and its
// press-and-hold affordance inside `TencentCloudChatMessageInputMobile`.
//
// Mobile parity is hard policy and the suite is desktop-leaning. This file
// gates the production voice-record state machine directly, with the `record`
// plugin's MethodChannel (`com.llfbandit.record/messages`) and `path_provider`
// stubbed so start/stop are captured and NO real microphone or native recorder
// is touched:
//
//   1. startRecording() flips the production UI into the recording state (the
//      elapsed counter renders) and drives the real recorder `start` over the
//      stubbed channel.
//   2. Slide-to-cancel — stopRecording(cancel: true) — returns to idle and does
//      NOT fire the onRecordFinish (voice-message) callback.
//   3. Normal release — stopRecording(cancel: false) — drives the production
//      voice-message path: onRecordFinish fires with a RecordInfo (path +
//      whole-seconds duration), exactly what the mobile input forwards to
//      sendVoiceMessage.
//   4. Press-and-hold on the REAL mic affordance in the mobile composer starts
//      the recording state through the production _onStartRecording handler
//      (the platform-mobile gate is injected via the canonical optional-ctor
//      seam so the host-OS check does not suppress it under `flutter test`).
//
// startRecording does real filesystem IO (getTemporaryDirectory + mkdir) and
// real timers, so the recorder-driving bodies run inside tester.runAsync (the
// repo's canonical pattern for real IO/crypto under testWidgets).
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_controller.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_mobile.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_recording.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

// Localization harness (copied from chat_core_real_ui_test.dart per the harness
// rule; the fork record widget reads `tL10n` during build).
Widget _localized({required Widget child}) {
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

/// Captures the calls the `record` plugin sends to its MethodChannel so the
/// test can assert the production recorder was driven without a native plugin.
class _FakeRecorderChannel {
  final List<String> methods = [];
  bool permission = true;
  Completer<bool>? permissionCompleter;
  // When set, `stop` returns this exact path (a test asserting the path). When
  // null, `stop` creates a fresh REAL temp file and returns its path, so the
  // production cancel branch (which deletes the recorded file) never trips a
  // PathNotFoundException.
  String? stopPath;
  final List<File> _createdFiles = [];
  final List<EventChannel> _eventChannels = [];

  void _registerEventChannel(
    TestDefaultBinaryMessenger messenger,
    String name,
  ) {
    final channel = EventChannel(name);
    _eventChannels.add(channel);
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(onListen: (args, sink) {}, onCancel: (args) {}),
    );
  }

  String _freshRealRecording() {
    final f = File(
      '${Directory.systemTemp.path}/rec-${DateTime.now().microsecondsSinceEpoch}-${_createdFiles.length}.m4a',
    );
    f.createSync();
    _createdFiles.add(f);
    return f.path;
  }

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // The `record` plugin routes every recorder op through this one channel.
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async {
        methods.add(call.method);
        switch (call.method) {
          case 'create':
            // The plugin subscribes to a per-recorder state EventChannel
            // (`com.llfbandit.record/events/<recorderId>`) immediately after
            // create(). The recorderId is only known here, so register a no-op
            // stream handler now to keep the subscribe/cancel from raising a
            // MissingPluginException during stream (de)activation.
            final id = (call.arguments as Map)['recorderId'] as String;
            _registerEventChannel(messenger, 'com.llfbandit.record/events/$id');
            _registerEventChannel(
              messenger,
              'com.llfbandit.record/eventsRecord/$id',
            );
            return null;
          case 'hasPermission':
            final completer = permissionCompleter;
            if (completer != null) return completer.future;
            return permission;
          case 'isEncoderSupported':
            return true;
          case 'listInputDevices':
            return <Map<dynamic, dynamic>>[];
          case 'getAmplitude':
            return <String, dynamic>{'current': -30.0, 'max': -20.0};
          case 'stop':
            return stopPath ?? _freshRealRecording();
          case 'start':
          case 'cancel':
          case 'dispose':
          case 'pause':
          case 'resume':
            return null;
          default:
            return null;
        }
      },
    );
    // path_provider: startRecording() resolves a temp dir before recording.
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      },
    );
  }

  void remove() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    for (final ch in _eventChannels) {
      messenger.setMockStreamHandler(ch, null);
    }
    _eventChannels.clear();
    for (final f in _createdFiles) {
      if (f.existsSync()) f.deleteSync();
    }
    _createdFiles.clear();
  }
}

class _FakeHapticChannel {
  final List<String?> feedbackTypes = [];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            feedbackTypes.add(call.arguments as String?);
          }
          return null;
        });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

// Permission_handler stub so the mobile composer's microphone permission gate
// (TencentCloudChatPermissionHandler.checkPermission) reports granted.
// PermissionStatus.granted == index 1 (denied == 0). requestPermissions returns
// a Map<permission.value, status.index>; we echo every requested permission
// back as granted so the gate passes regardless of which value is asked.
void _installGrantedMicPermission() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    (call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
          return 1; // granted
        case 'requestPermissions':
          final requested = (call.arguments as List).cast<int>();
          return <int, int>{for (final v in requested) v: 1};
        default:
          return 1;
      }
    },
  );
}

void _removeMicPermission() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        null,
      );
}

MessageInputBuilderMethods _methods({
  required void Function(RecordInfo) onVoice,
}) {
  return MessageInputBuilderMethods(
    sendTextMessage: ({required String text, List<String>? mentionedUsers}) {},
    sendImageMessage:
        ({String? imagePath, String? imageName, dynamic inputElement}) {},
    sendVideoMessage: ({String? videoPath, dynamic inputElement}) {},
    sendFileMessage:
        ({String? filePath, String? fileName, dynamic inputElement}) {},
    sendVoiceMessage: ({required String voicePath, required int duration}) {
      onVoice(RecordInfo(path: voicePath, duration: duration));
    },
    onChooseGroupMembers: () async => <V2TimGroupMemberFullInfo>[],
    controller: TencentCloudChatMessageControllerGenerator.getInstance(),
    clearRepliedMessage: () {},
    setDesktopMentionBoxPositionX: (_) {},
    setDesktopMentionBoxPositionY: (_) {},
    setActiveMentionIndex: (_) {},
    setCurrentFilteredMembersListForMention: (_) {},
    desktopInputMemberSelectionPanelScroll: AutoScrollController(),
    messageAttachmentOptionsBuilder: Object(),
    closeSticker: () {},
  );
}

MessageInputBuilderData _data() {
  return MessageInputBuilderData(
    userID: null,
    groupID: null,
    attachmentOptions: const [],
    inSelectMode: false,
    enableReplyWithMention: false,
    status: TencentCloudChatMessageInputStatus.canSendMessage,
    selectedMessages: const [],
    desktopMentionBoxPositionX: 0,
    desktopMentionBoxPositionY: 0,
    isGroupAdmin: false,
    activeMentionIndex: -1,
    currentFilteredMembersListForMention: const [],
    groupMemberList: const [],
    currentConversationShowName: 'Friend One',
    hasStickerPlugin: false,
    stickerPluginInstance: null,
  );
}

// The `record` plugin's AudioRecorder subscribes to a per-recorder state
// EventChannel (`com.llfbandit.record/events/<uuid>`) inside _create(). The uuid
// is generated INSIDE the plugin, so the channel can't be pre-mocked; on
// subscribe/cancel it raises a benign MissingPluginException during stream
// (de)activation. Swallow exactly that (and only that) so it doesn't fail the
// gate, forwarding every other error to the real handler. Returns a restore fn.
VoidCallback _suppressRecordEventChannelErrors() {
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final ex = details.exception;
    if (ex is MissingPluginException &&
        (details.toString().contains('com.llfbandit.record/events') ||
            (details.context?.toString().contains('platform stream') ??
                false))) {
      return; // benign: unmockable per-recorder EventChannel
    }
    (previous ?? FlutterError.presentError)(details);
  };
  return () => FlutterError.onError = previous;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  void useMobileSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('voice record UI (TencentCloudChatMessageInputRecording)', () {
    late _FakeRecorderChannel recorder;
    late _FakeHapticChannel haptics;
    late VoidCallback restoreErrors;

    setUp(() {
      recorder = _FakeRecorderChannel();
      recorder.install();
      haptics = _FakeHapticChannel();
      haptics.install();
      restoreErrors = _suppressRecordEventChannelErrors();
    });
    tearDown(() {
      recorder.remove();
      haptics.remove();
      restoreErrors();
    });

    testWidgets(
      'startRecording flips into recording state and drives the recorder start',
      (tester) async {
        useMobileSurface(tester);
        final key = GlobalKey<TencentCloudChatMessageInputRecordingState>();
        var finishCount = 0;

        await tester.pumpWidget(
          _localized(
            child: TencentCloudChatMessageInputRecording(
              key: key,
              isRecording: false,
              onRecordFinish: (_) => finishCount++,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          await key.currentState!.startRecording();
        });
        // While recording, the production widget runs a 10ms periodic timer
        // (setState every tick), so the tree never quiesces — use a single
        // pump() to render the recording state instead of pumpAndSettle().
        await tester.pump();

        // Recorder was driven over the stubbed channel (real production calls).
        expect(recorder.methods, contains('hasPermission'));
        expect(
          recorder.methods,
          contains('start'),
          reason: 'startRecording must call the real recorder start',
        );
        expect(
          haptics.feedbackTypes,
          ['HapticFeedbackType.mediumImpact'],
          reason: 'successful recording start needs tactile confirmation',
        );
        // Production recording UI is live: the elapsed counter (mm:ss) renders.
        expect(
          find.textContaining(RegExp(r'^\d{2}:\d{2}$')),
          findsOneWidget,
          reason: 'recording state should render the elapsed counter',
        );
        expect(finishCount, 0, reason: 'no send while still recording');

        // Stop so no timers/recorder leak past the test.
        await tester.runAsync(() async {
          await key.currentState!.stopRecording(cancel: true);
        });
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'slide-to-cancel (stopRecording cancel:true) returns to idle with no send',
      (tester) async {
        useMobileSurface(tester);
        // stopPath left null: the fake returns a fresh REAL temp file on stop,
        // so the production cancel branch can delete it without throwing.
        final key = GlobalKey<TencentCloudChatMessageInputRecordingState>();
        final finished = <RecordInfo>[];

        await tester.pumpWidget(
          _localized(
            child: TencentCloudChatMessageInputRecording(
              key: key,
              isRecording: false,
              onRecordFinish: finished.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          await key.currentState!.startRecording();
          await key.currentState!.stopRecording(cancel: true);
        });
        await tester.pumpAndSettle();

        expect(recorder.methods, contains('start'));
        expect(recorder.methods, contains('stop'));
        // Cancel path: the voice-message callback must NOT fire.
        expect(
          finished,
          isEmpty,
          reason: 'slide-to-cancel must not emit a voice message',
        );
        expect(
          haptics.feedbackTypes,
          ['HapticFeedbackType.mediumImpact', 'HapticFeedbackType.heavyImpact'],
          reason: 'cancel must feel distinct from normal completion',
        );
      },
    );

    testWidgets(
      'normal release (stopRecording cancel:false) drives the voice-message path',
      (tester) async {
        useMobileSurface(tester);
        recorder.stopPath = '/tmp/voice-real-ui.m4a';
        final key = GlobalKey<TencentCloudChatMessageInputRecordingState>();
        final finished = <RecordInfo>[];

        await tester.pumpWidget(
          _localized(
            child: TencentCloudChatMessageInputRecording(
              key: key,
              isRecording: false,
              onRecordFinish: finished.add,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          await key.currentState!.startRecording();
          await key.currentState!.stopRecording(cancel: false);
        });
        await tester.pumpAndSettle();

        // The production onRecordFinish fires with the recorded path; duration
        // is whole seconds (recorder ceils _recordingDuration/1000).
        expect(
          finished,
          hasLength(1),
          reason: 'normal release should emit exactly one voice message',
        );
        expect(finished.single.path, '/tmp/voice-real-ui.m4a');
        expect(finished.single.duration, greaterThanOrEqualTo(0));
        expect(recorder.methods, contains('stop'));
        expect(
          haptics.feedbackTypes,
          ['HapticFeedbackType.mediumImpact', 'HapticFeedbackType.lightImpact'],
          reason: 'normal completion needs a light tactile confirmation',
        );
      },
    );

    testWidgets('dispose while recording removes the global pointer route', (
      tester,
    ) async {
      useMobileSurface(tester);
      final key = GlobalKey<TencentCloudChatMessageInputRecordingState>();

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputRecording(
            key: key,
            isRecording: false,
            onRecordFinish: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await key.currentState!.startRecording();
      });
      await tester.pump();

      await tester.pumpWidget(_localized(child: const SizedBox.shrink()));
      await tester.pump();

      tester.binding.handlePointerEvent(
        const PointerMoveEvent(position: Offset(1, 1)),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'disposed recording widgets must not leave a global route that reads a stale trashIconKey context',
      );
    });

    testWidgets('startRecording abandons native continuation after dispose', (
      tester,
    ) async {
      useMobileSurface(tester);
      recorder.permissionCompleter = Completer<bool>();
      final key = GlobalKey<TencentCloudChatMessageInputRecordingState>();

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputRecording(
            key: key,
            isRecording: false,
            onRecordFinish: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final startFuture = key.currentState!.startRecording();
      await tester.pump();

      await tester.pumpWidget(_localized(child: const SizedBox.shrink()));
      await tester.pump();

      Object? startError;
      await tester.runAsync(() async {
        recorder.permissionCompleter!.complete(true);
        try {
          await startFuture;
        } catch (e) {
          startError = e;
        }
      });
      await tester.pump();

      expect(
        startError,
        isNull,
        reason: 'startRecording must stop quietly if its State was disposed',
      );
      expect(tester.takeException(), isNull);
      expect(
        recorder.methods,
        isNot(contains('start')),
        reason: 'a disposed recorder widget must not start native capture',
      );
    });
  });

  group('press-and-hold mic affordance (mobile composer)', () {
    late _FakeRecorderChannel recorder;
    late _FakeHapticChannel haptics;
    late VoidCallback restoreErrors;

    setUp(() {
      recorder = _FakeRecorderChannel();
      recorder.install();
      haptics = _FakeHapticChannel();
      haptics.install();
      _installGrantedMicPermission();
      restoreErrors = _suppressRecordEventChannelErrors();
    });
    tearDown(() {
      recorder.remove();
      haptics.remove();
      _removeMicPermission();
      restoreErrors();
    });

    test('mobile composer dispose cancels a pending recording starter', () async {
      final source = await File(
        'third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_mobile.dart',
      ).readAsString();

      expect(source, contains('_cancelPendingRecordingStarter();'));
      expect(source, contains('_recordingStarter?.cancel();'));
    });

    testWidgets('press-and-hold the mic starts the production recording state', (
      tester,
    ) async {
      useMobileSurface(tester);
      final finished = <RecordInfo>[];

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputMobile(
            // Inject the platform-mobile gate so _onStartRecording is
            // reachable under `flutter test` (host OS is macOS, where the
            // production TencentCloudChatPlatformAdapter().isMobile is
            // false). Defaults to the real adapter in production.
            debugIsMobile: () => true,
            inputData: _data(),
            inputMethods: _methods(onVoice: finished.add),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Empty field -> the trailing affordance is the press-to-record mic.
      final mic = find.byIcon(Icons.mic);
      expect(mic, findsOneWidget);

      // Press and hold the REAL mic affordance. PointerDown -> the production
      // _onStartRecording: it awaits the (mocked) permission gate, then arms a
      // 100ms timer that calls startRecording() which does real
      // getTemporaryDirectory + mkdir IO. Driving the gesture INSIDE runAsync
      // makes that 100ms timer a real timer, so a real delay fires the whole
      // chain. pumps stay OUTSIDE runAsync.
      late TestGesture gesture;
      await tester.runAsync(() async {
        gesture = await tester.startGesture(tester.getCenter(mic));
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      // Render the recording state with a single pump() (recording runs a
      // 10ms periodic timer, so the tree never settles).
      await tester.pump();

      // The production recorder was started via _recordingWidgetKey.
      expect(
        recorder.methods,
        contains('start'),
        reason: 'holding the mic should start the real recorder',
      );
      // The composer swapped to the recording widget (IndexedStack index 1):
      // the elapsed counter is visible.
      expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsOneWidget);

      // Release away from the trash icon -> normal-release stop (stopRecording
      // does real recorder IO, so let it complete under runAsync too).
      await tester.runAsync(() async {
        await gesture.up();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(
        recorder.methods,
        contains('stop'),
        reason: 'releasing the mic should stop the real recorder',
      );
    });
  });
}
