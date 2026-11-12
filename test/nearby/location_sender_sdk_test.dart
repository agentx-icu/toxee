import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:toxee/nearby/location_sender.dart';
import 'package:toxee/nearby/location_source.dart';
import 'package:toxee/util/prefs.dart';

import 'nearby_service_test.dart' show FakeLocation;

/// The SDK message constructor loads native bindings. This data-only message
/// lets the real UIKit send helper run against a fake SDK without native code.
class _Message implements V2TimMessage {
  @override
  String? faceUrl, nickName, sender, id, msgID;
  @override
  int? timestamp, status;
  @override
  bool? isSelf, needReadReceipt;
  @override
  OfflinePushInfo? offlinePushInfo = OfflinePushInfo(desc: 'Location');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MessageManager implements V2TIMMessageManager {
  Completer<void>? creationGate;
  int creations = 0;
  int sends = 0;

  @override
  Future<V2TimValueCallback<V2TimMsgCreateInfoResult>> createLocationMessage({
    required String desc,
    required double longitude,
    required double latitude,
  }) async {
    creations++;
    await creationGate?.future;
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMsgCreateInfoResult(id: 'location', messageInfo: _Message()),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sendMessage) {
      sends++;
      return Future.value(
        V2TimValueCallback<V2TimMessage>(code: 0, desc: 'ok'),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class _Manager implements V2TIMManager {
  final messages = _MessageManager();
  late Completer<V2TimValueCallback<List<V2TimUserFullInfo>>> profileGate;
  int profileReads = 0;

  @override
  V2TIMMessageManager getMessageManager() => messages;

  @override
  Future<V2TimValueCallback<List<V2TimUserFullInfo>>> getUsersInfo({
    required List<String> userIDList,
  }) {
    profileReads++;
    return profileGate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final oldManager = TencentImSDKPlugin.v2TIMManager;
  final manager = _Manager();
  // UIKit captures its manager at first access. Keep one fake for this isolate.
  TencentImSDKPlugin.v2TIMManager = manager;
  final toxId = 'A' * 64;
  const target = 'location-sdk-test-peer';
  late bool sessionCurrent;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocationPrefs.setLocationEnabled(true, toxId);
    sessionCurrent = true;
    manager.messages.creationGate = null;
    manager.messages.creations = 0;
    manager.messages.sends = 0;
    manager.profileReads = 0;
    manager.profileGate = Completer();
    TencentCloudChat.instance.dataInstance.basic.updateCurrentUserInfo(
      userFullInfo: V2TimUserFullInfo(userID: toxId, faceUrl: ''),
    );
  });

  tearDown(() => TencentCloudChat.instance.dataInstance.basic.clear());
  tearDownAll(() => TencentImSDKPlugin.v2TIMManager = oldManager);

  Future<BuildContext> mount(WidgetTester tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return pageContext;
  }

  LocationSender sender() => LocationSender(
    source: FakeLocation(
      LocationFix(latitude: 1, longitude: 2, accuracyM: 5, at: DateTime.now()),
    ),
    currentToxId: () async => toxId,
    isSessionCurrent: () => sessionCurrent,
  );

  testWidgets('session teardown during SDK message creation cancels dispatch', (
    tester,
  ) async {
    manager.messages.creationGate = Completer();
    final context = await mount(tester);
    final pending = sender().send(context, userID: target);
    await tester.pump();
    expect(manager.messages.creations, 1);
    sessionCurrent = false;
    manager.messages.creationGate!.complete();
    await tester.pump();

    expect(manager.profileReads, 0);
    expect(manager.messages.sends, 0);
    expect(await pending, LocationSendOutcome.failed);
  });

  testWidgets(
    'session teardown during UIKit profile lookup inserts and sends nothing',
    (tester) async {
      // Complete in the same FakeAsync zone that pumps the send continuation.
      manager.profileGate = Completer();
      final context = await mount(tester);
      final pending = sender().send(context, userID: target);
      await tester.pump();
      expect(manager.profileReads, 1);
      sessionCurrent = false;
      manager.profileGate.complete(
        V2TimValueCallback(code: 0, desc: 'ok', data: []),
      );
      await tester.pump();

      expect(manager.messages.sends, 0);
      expect(
        TencentCloudChat.instance.dataInstance.messageData.getMessageList(
          key: target,
        ),
        isEmpty,
      );
      expect(await pending, LocationSendOutcome.failed);
    },
  );
}
