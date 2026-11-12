// ignore_for_file: avoid_print
@Tags(['needs-native', 'network'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as memory;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_friendship_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/rendezvous_transport.dart';
import 'package:toxee/nearby/geohash.dart';
import 'package:toxee/nearby/location_sender.dart';
import 'package:toxee/nearby/location_source.dart';
import 'package:toxee/nearby/nearby_service.dart';
import 'package:toxee/nearby/nearby_transport.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';
import 'package:toxee/util/prefs.dart';

import '../../third_party/tim2tox/auto_tests/test/test_fixtures.dart';
import '../../third_party/tim2tox/auto_tests/test/test_helper.dart';

/// A single real native peer. The runner starts this test in two independent
/// flutter_tester processes. Files coordinate phases and exchange endpoints;
/// presence, intents, friend requests and location messages use native sockets.
class _Exchange {
  _Exchange(this.directory, this.role);
  final Directory directory;
  final String role;
  String get other => role == 'alice' ? 'bob' : 'alice';

  Future<void> write(
    String step, [
    Map<String, Object?> data = const {},
  ]) async {
    final file = File('${directory.path}/$role.$step.json');
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(data), flush: true);
    await pending.rename(file.path);
    print('[VERIFY] $role: $step ${jsonEncode(data)}');
  }

  Future<Map<String, dynamic>> readOther(String step) async {
    final file = File('${directory.path}/$other.$step.json');
    await _until(() => file.existsSync(), 'waiting for $other/$step');
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }
}

Future<void> _until(
  bool Function() ready,
  String description, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    if (elapsed.elapsed >= timeout) {
      throw TimeoutException(description, timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

class _Position implements LocationSource {
  _Position(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 15),
  }) async => LocationFix(
    latitude: latitude,
    longitude: longitude,
    accuracyM: 5,
    at: DateTime.now(),
  );
  @override
  Future<LocationPermissionState> permissionState() async =>
      LocationPermissionState.granted;
  @override
  Future<LocationPermissionState> requestPermission() async =>
      LocationPermissionState.granted;
  @override
  Future<bool> openSettings() async => true;
}

class _NativeTransport implements NearbyTransport {
  _NativeTransport(this.node, this.raw, Stream<RendezvousEvent> events)
    : events = events.where(
        (event) => event.instanceId == node.testInstanceHandle,
      );
  final TestNode node;
  final RendezvousTransport raw;
  @override
  final Stream<RendezvousEvent> events;
  @override
  int join(Uint8List seed, {required String name, required String nick}) =>
      node.runWithInstance(() => raw.join(seed, name: name, nick: nick));
  @override
  bool leave(String chatIdHex) =>
      node.runWithInstance(() => raw.leave(chatIdHex));
  @override
  int leaveAll() => node.runWithInstance(raw.leaveAll);
  @override
  int send(String chatIdHex, Uint8List payload, {String? peerPkHex}) =>
      node.runWithInstance(
        () => raw.send(chatIdHex, payload, peerPkHex: peerPkHex),
      );
  @override
  int peerCount(String chatIdHex) =>
      node.runWithInstance(() => raw.peerCount(chatIdHex));
  @override
  int dhtAnnounceCapableCount() =>
      node.runWithInstance(raw.dhtAnnounceCapableCount);
}

String? _groupIdentity(Tim2ToxFfi native, TestNode node, String groupId) =>
    node.runWithInstance(() {
      final id = groupId.toNativeUtf8();
      final output = memory.malloc.allocate<ffi.Int8>(65);
      try {
        if (native.getGroupChatIdNative(
              node.testInstanceHandle!,
              id,
              output,
              65,
            ) !=
            1) {
          return null;
        }
        return output.cast<memory.Utf8>().toDartString().toLowerCase();
      } finally {
        memory.malloc.free(id);
        memory.malloc.free(output);
      }
    });

void main() {
  final role = Platform.environment['TOXEE_LOCATION_PEER_ROLE'];
  final exchangePath = Platform.environment['TOXEE_LOCATION_PEER_EXCHANGE'];
  final enabled = (role == 'alice' || role == 'bob') && exchangePath != null;

  testWidgets(
    'native nearby handshake and bidirectional C2C/group location messages',
    (tester) async {
      final exchange = _Exchange(Directory(exchangePath!), role!);
      late BuildContext pageContext;
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
          home: Builder(
            builder: (context) {
              pageContext = context;
              TencentCloudChatIntl().init(context);
              return const Scaffold(body: Text('Native location verification'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        TestScenario? scenario;
        NearbyService? nearby;
        StreamSubscription<RendezvousEvent>? packetSubscription;
        V2TimAdvancedMsgListener? messageListener;
        V2TimFriendshipListener? friendListener;
        V2TimGroupListener? groupListener;
        TestNode? self;
        var sessionCurrent = true;
        final receivedMessages = <V2TimMessage>[];
        final applications = <V2TimFriendApplication>[];
        final invitedGroups = <String>[];
        var nativePackets = 0;
        try {
          final requestedLibrary =
              Platform.environment['TOXEE_LOCATION_NATIVE_LIB'];
          if (requestedLibrary != null) {
            final selectedLibrary = resolveTim2ToxLibraryPath();
            expect(
              selectedLibrary,
              isNotNull,
              reason: 'prepare the native library in the isolated harness',
            );
            expect(
              File(selectedLibrary!).resolveSymbolicLinksSync(),
              File(requestedLibrary).resolveSymbolicLinksSync(),
            );
          }
          await setupTestEnvironment();
          // FakeUIKit also creates its ringtone player. Audio is unrelated to
          // this test; keep its platform channels inert while Tox stays real.
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          for (final channel in [
            'xyz.luan/audioplayers',
            'xyz.luan/audioplayers.global',
          ]) {
            messenger.setMockMethodCallHandler(MethodChannel(channel), (
              call,
            ) async {
              if (call.method == 'create') {
                final player = (call.arguments as Map)['playerId'] as String;
                messenger.setMockMethodCallHandler(
                  MethodChannel('xyz.luan/audioplayers/events/$player'),
                  (_) async => null,
                );
              }
              return null;
            });
          }
          SharedPreferences.setMockInitialValues({});
          scenario = await createTestScenario([role]);
          self = scenario.getNode(role)!;
          final node = self;
          await scenario.initAllNodes(
            localDiscoveryEnabled: false,
            ipv6Enabled: false,
          );
          await node.login(timeout: const Duration(milliseconds: 500));
          node.disableAutoAccept();
          final native = Tim2ToxFfi.open();
          final address = node.getToxId();
          final endpoint = node.runWithInstance(() {
            final buffer = memory.malloc.allocate<ffi.Int8>(65);
            try {
              final length = native.getDhtIdNative(buffer, 65);
              return <String, Object?>{
                'port': native.getUdpPort(node.testInstanceHandle!),
                'dht': buffer.cast<memory.Utf8>().toDartString(length: length),
                'address': address,
                'pid': pid,
              };
            } finally {
              memory.malloc.free(buffer);
            }
          });
          expect(endpoint['port'] as int, greaterThan(0));
          await exchange.write('endpoint', endpoint);
          final remote = await exchange.readOther('endpoint');
          final remoteAddress = remote['address'] as String;
          final host = '127.0.0.1'.toNativeUtf8();
          final remoteDht = (remote['dht'] as String).toNativeUtf8();
          try {
            node.runWithInstance(
              () => native.addBootstrapNode(
                node.testInstanceHandle!,
                host,
                remote['port'] as int,
                remoteDht,
              ),
            );
          } finally {
            memory.malloc.free(host);
            memory.malloc.free(remoteDht);
          }
          await node.waitForConnection(timeout: const Duration(seconds: 45));
          await exchange.write('connected', {
            'status': node.runWithInstance(native.getSelfConnectionStatus),
          });

          final platform =
              TencentCloudChatSdkPlatform.instance as Tim2ToxSdkPlatform;
          await FakeUIKit.instance.startWithFfi(platform.ffiService);
          ChatMessageProviderRegistry.provider =
              FakeUIKit.instance.messageProvider;
          final transport = _NativeTransport(
            node,
            RendezvousTransport(native),
            platform.ffiService.rendezvous.events,
          );
          packetSubscription = transport.events.listen((event) {
            if (event is RendezvousPacket) nativePackets++;
            if (event is RendezvousJoined || event is RendezvousLeft) {
              print(
                '[VERIFY] $role: native ${event.runtimeType} ${event.chatIdHex}',
              );
            }
          });
          // Fixed synthetic positions in the Pacific, near a geohash boundary.
          // Both peers join two real groups, each with its own NGC peer key.
          final cell = Geohash.encode(0.0, -140.0, 5);
          final bounds = Geohash.bounds(cell);
          final center = Geohash.decode(cell);
          final position = _Position(
            bounds.latMax - 0.0005 + (role == 'alice' ? 0.00005 : -0.00005),
            center.longitude,
          );
          await LocationPrefs.setLocationEnabled(true, address);
          await LocationPrefs.setNearbyVisible(true, address);
          final service = NearbyService(
            transport: transport,
            location: position,
            selfAddress: () async => address,
            displayName: () => 'verify-$role',
            canRun: () async =>
                await LocationPrefs.getLocationEnabled(address) &&
                await LocationPrefs.getNearbyVisible(address),
          );
          nearby = service;
          friendListener = V2TimFriendshipListener(
            onFriendApplicationListAdded: applications.addAll,
          );
          messageListener = V2TimAdvancedMsgListener(
            onRecvNewMessage: (message) {
              if (message.isSelf != true) receivedMessages.add(message);
            },
          );
          node.runWithInstance(() {
            TIMFriendshipManager.instance.addFriendListener(
              listener: friendListener!,
            );
          });
          await node.runWithInstanceAsync(
            () => TencentImSDKPlugin.v2TIMManager
                .getMessageManager()
                .addAdvancedMsgListener(listener: messageListener!),
          );
          groupListener = V2TimGroupListener(
            onMemberInvited: (groupId, operator, members) {
              if (members.any(
                (m) =>
                    m.userID?.toLowerCase() ==
                    address.substring(0, 64).toLowerCase(),
              )) {
                invitedGroups.add(groupId);
              }
            },
          );
          await node.runWithInstanceAsync(
            () => TencentImSDKPlugin.v2TIMManager.addGroupListener(
              listener: groupListener!,
            ),
          );
          if (role == 'bob') await exchange.readOther('founded');
          await service.start();
          await exchange.write('session', {'sk': service.sessionKeys!.skHex});
          if (role == 'alice') {
            await _until(
              () => service.joinedCells.length >= 2,
              'Alice founds both cells',
            );
            await exchange.write('founded');
          }
          final remoteSession = await exchange.readOther('session');
          NearbyPeer? peer() => service.peers
              .where((p) => p.skHex == remoteSession['sk'])
              .firstOrNull;
          await _until(
            () => (peer()?.cells.length ?? 0) >= 2,
            'both native cell routes discovered',
          );
          final discovered = peer()!;
          expect(
            discovered.cells.map(discovered.peerKeyForCell).toSet().length,
            2,
          );
          expect(service.distanceTo(discovered)!, lessThan(200));
          await exchange.write('discovered', {
            'routes': discovered.cells.length,
            'packets': nativePackets,
          });
          await exchange.readOther('discovered');

          if (role == 'alice') {
            final leaving = peer()!.cellChatIdHex!;
            expect(transport.leave(leaving), isTrue);
            await _until(
              () => peer()?.cells.length == 1,
              'local native cell route fallback',
            );
            await exchange.write('fallback');
            await exchange.readOther('fallback-observed');
            final result = await service.sendIntent(
              peer()!,
              'Native nearby hello',
            );
            expect(result, isA<PendingIntent>());
            final pending = result as PendingIntent;
            await exchange.write('intent-sent', {'nonce': pending.nonceHex});
            await _until(
              () => applications.isNotEmpty,
              'native friend application reply',
            );
            final app = applications.firstWhere(
              (a) =>
                  a.userID.toLowerCase() ==
                  remoteAddress.substring(0, 64).toLowerCase(),
            );
            final matched = service.matchFriendApplication(app.addWording);
            expect(matched?.nonceHex, pending.nonceHex);
            final accepted = await node.runWithInstanceAsync(
              () => TIMFriendshipManager.instance.acceptFriendApplication(
                responseType:
                    FriendResponseTypeEnum.V2TIM_FRIEND_ACCEPT_AGREE_AND_ADD,
                userID: app.userID,
              ),
            );
            expect(accepted.code, 0);
            await exchange.write('friend-confirmed');
          } else {
            await exchange.readOther('fallback');
            await _until(
              () => peer()?.cells.length == 1,
              'remote native cell route fallback',
            );
            await exchange.write('fallback-observed');
            await _until(
              () => service.incomingIntents.isNotEmpty,
              'encrypted native nearby intent',
            );
            final incoming = service.incomingIntents.single;
            expect(incoming.address, remoteAddress.toLowerCase());
            expect(incoming.message, 'Native nearby hello');
            final sent = await exchange.readOther('intent-sent');
            expect(incoming.nonceHex, sent['nonce']);
            final added = await node.runWithInstanceAsync(
              () => TIMFriendshipManager.instance.addFriend(
                userID: incoming.address,
                addType: FriendTypeEnum.V2TIM_FRIEND_TYPE_BOTH,
                addWording: incoming.requestWording,
              ),
            );
            expect(added.code, 0);
            service.dismissIncoming(incoming);
            await exchange.readOther('friend-confirmed');
          }
          await node.waitForFriendConnection(
            remoteAddress,
            timeout: const Duration(seconds: 60),
          );
          await exchange.write('friend-connected');
          await exchange.readOther('friend-connected');

          TencentCloudChat.instance.dataInstance.basic.updateCurrentUserInfo(
            userFullInfo: V2TimUserFullInfo(
              userID: address.substring(0, 64),
              nickName: 'verify-$role',
              faceUrl: 'test://avatar',
            ),
          );
          final sender = LocationSender(
            source: position,
            currentToxId: () async => address,
            isSessionCurrent: () => sessionCurrent && node.loggedIn,
          );
          final outcome = await node.runWithInstanceAsync(
            () => sender.send(pageContext, userID: remoteAddress),
          );
          expect(outcome, LocationSendOutcome.sent);
          await exchange.write('location-sent');
          await _until(
            () => receivedMessages.any(
              (m) => m.locationElem != null && (m.groupID ?? '').isEmpty,
            ),
            'native location message received',
            timeout: const Duration(seconds: 45),
          );
          final message = receivedMessages.firstWhere(
            (m) => m.locationElem != null && (m.groupID ?? '').isEmpty,
          );
          final expectedRemoteLatitude =
              bounds.latMax - 0.0005 + (role == 'alice' ? -0.00005 : 0.00005);
          expect(
            message.locationElem!.latitude,
            closeTo(expectedRemoteLatitude, 0.000001),
          );
          expect(
            message.locationElem!.longitude,
            closeTo(position.longitude, 0.000001),
          );
          expect(
            (message.sender ?? '').toLowerCase(),
            startsWith(remoteAddress.substring(0, 64).toLowerCase()),
          );
          expect(nativePackets, greaterThan(0));
          await exchange.write('location-received', {
            'latitude': message.locationElem!.latitude,
            'longitude': message.locationElem!.longitude,
            'elemType': message.elemType,
            'nativePackets': nativePackets,
          });
          await exchange.readOther('location-received');

          // Create/join through the production SDK, then resolve each side's
          // local group ID by immutable native chat identity (not group index).
          late Map<String, dynamic> groupCreated;
          if (role == 'alice') {
            final created = await node.runWithInstanceAsync(
              () =>
                  TencentImSDKPlugin.v2TIMManager.getGroupManager().createGroup(
                    groupType: 'Private',
                    groupName: 'Native location verification',
                  ),
            );
            expect(created.code, 0, reason: created.desc);
            expect(created.data, isNotEmpty);
            final groupId = created.data!;
            final chatId = _groupIdentity(native, node, groupId);
            expect(chatId, matches(RegExp(r'^[0-9a-f]{64}$')));
            groupCreated = {'groupId': groupId, 'chatId': chatId};
            await exchange.write('group-created', groupCreated);
            final invited = await node.runWithInstanceAsync(
              () => TencentImSDKPlugin.v2TIMManager
                  .getGroupManager()
                  .inviteUserToGroup(
                    groupID: groupId,
                    userList: [remoteAddress.substring(0, 64)],
                  ),
            );
            expect(invited.code, 0, reason: invited.desc);
            await exchange.readOther('group-joined');
          } else {
            groupCreated = await exchange.readOther('group-created');
            await _until(
              () => invitedGroups.isNotEmpty,
              'native group invitation arrives through SDK',
            );
            final joined = await node.runWithInstanceAsync(
              () => TencentImSDKPlugin.v2TIMManager.joinGroup(
                groupID: invitedGroups.single,
                message: '',
              ),
            );
            expect(joined.code, 0, reason: joined.desc);
            await exchange.write('group-joined', {
              'inviteId': invitedGroups.single,
            });
          }
          final expectedChatId = groupCreated['chatId'] as String;
          String? localGroupId;
          await _until(
            () {
              localGroupId = platform.ffiService.knownGroups
                  .where(
                    (id) => _groupIdentity(native, node, id) == expectedChatId,
                  )
                  .firstOrNull;
              if (localGroupId == null) return false;
              final id = localGroupId!.toNativeUtf8();
              try {
                return node.runWithInstance(() => native.groupWireReady(id)) ==
                    1;
              } finally {
                memory.malloc.free(id);
              }
            },
            'native group has a confirmed peer on $role',
            timeout: const Duration(seconds: 60),
          );
          await exchange.write('group-ready', {
            'groupId': localGroupId,
            'chatId': expectedChatId,
          });
          await exchange.readOther('group-ready');
          final groupOutcome = await node.runWithInstanceAsync(
            () => sender.send(pageContext, groupID: localGroupId),
          );
          expect(groupOutcome, LocationSendOutcome.sent);
          final authorKey = node.runWithInstance(
            () => native.lastGroupSendSelfKey().toDartString().toLowerCase(),
          );
          expect(authorKey, matches(RegExp(r'^[0-9a-f]{64}$')));
          await exchange.write('group-location-sent', {'authorKey': authorKey});
          final remoteGroupSend = await exchange.readOther(
            'group-location-sent',
          );
          await _until(
            () => receivedMessages.any(
              (m) => m.locationElem != null && (m.groupID ?? '').isNotEmpty,
            ),
            'native group location received on $role',
            timeout: const Duration(seconds: 45),
          );
          final groupMessage = receivedMessages.firstWhere(
            (m) => m.locationElem != null && (m.groupID ?? '').isNotEmpty,
          );
          expect(
            _groupIdentity(native, node, groupMessage.groupID!),
            expectedChatId,
          );
          expect(groupMessage.elemType, 7);
          expect(groupMessage.isSelf, isFalse);
          expect(
            groupMessage.sender?.toLowerCase(),
            remoteGroupSend['authorKey'],
          );
          expect(
            groupMessage.locationElem!.latitude,
            closeTo(expectedRemoteLatitude, 0.000001),
          );
          expect(
            groupMessage.locationElem!.longitude,
            closeTo(position.longitude, 0.000001),
          );
          expect(
            groupMessage.locationElem!.desc,
            '${expectedRemoteLatitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
          );
          await exchange.write('group-location-received', {
            'groupId': groupMessage.groupID,
            'chatId': expectedChatId,
            'sender': groupMessage.sender,
            'latitude': groupMessage.locationElem!.latitude,
            'longitude': groupMessage.locationElem!.longitude,
            'desc': groupMessage.locationElem!.desc,
            'elemType': groupMessage.elemType,
          });
          await exchange.readOther('group-location-received');
          if (role == 'alice') {
            await LocationPrefs.setNearbyVisible(false, address);
            await service.refresh();
            expect(service.running, isFalse);
            expect(service.joinedCells, isEmpty);
            await exchange.write('nearby-stopped');
            await exchange.readOther('stop-observed');
          } else {
            await exchange.readOther('nearby-stopped');
            await _until(
              () => peer() == null,
              'peer disappears after visibility is disabled',
            );
            await exchange.write('stop-observed');
          }
          await exchange.write('passed', {
            'pid': pid,
            'nativePackets': nativePackets,
          });
        } catch (error, stack) {
          await exchange.write('failed', {
            'error': error.toString(),
            'stack': stack.toString(),
            'nearbyStatus': nearby?.status.name,
            'joinedCells': nearby?.joinedCells.toList(),
            'nativePackets': nativePackets,
            'messages': receivedMessages
                .map(
                  (m) => {
                    'type': m.elemType,
                    'sender': m.sender,
                    'groupId': m.groupID,
                    'text': m.textElem?.text,
                  },
                )
                .toList(),
          });
          rethrow;
        } finally {
          sessionCurrent = false;
          await nearby?.stop();
          nearby?.dispose();
          await packetSubscription?.cancel();
          if (self != null) {
            self.runWithInstance(() {
              if (friendListener != null) {
                TIMFriendshipManager.instance.removeFriendListener(
                  listener: friendListener,
                );
              }
            });
            if (messageListener != null) {
              await self.runWithInstanceAsync(
                () => TencentImSDKPlugin.v2TIMManager
                    .getMessageManager()
                    .removeAdvancedMsgListener(listener: messageListener),
              );
            }
            if (groupListener != null) {
              await self.runWithInstanceAsync(
                () => TencentImSDKPlugin.v2TIMManager.removeGroupListener(
                  listener: groupListener,
                ),
              );
            }
          }
          ChatMessageProviderRegistry.provider = null;
          await FakeUIKit.instance.dispose();
          await scenario?.dispose();
          await teardownTestEnvironment();
        }
      });
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
