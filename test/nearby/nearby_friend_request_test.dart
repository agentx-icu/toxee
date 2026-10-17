import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_application.dart';
import 'package:tim2tox_dart/service/rendezvous_transport.dart';
import 'package:toxee/nearby/location_source.dart';
import 'package:toxee/nearby/nearby_friend_request.dart';
import 'package:toxee/nearby/nearby_service.dart';
import 'package:toxee/nearby/nearby_transport.dart';

class _NullTransport implements NearbyTransport {
  final _c = StreamController<RendezvousEvent>.broadcast();
  Future<void> close() => _c.close();
  @override
  Stream<RendezvousEvent> get events => _c.stream;
  @override
  int join(Uint8List seed, {required String name, required String nick}) => 1;
  @override
  bool leave(String chatIdHex) => true;
  @override
  int leaveAll() => 0;
  @override
  int send(String chatIdHex, Uint8List payload, {String? peerPkHex}) => 1;
  @override
  int peerCount(String chatIdHex) => 0;
  @override
  int dhtAnnounceCapableCount() => 1;
}

class _NoLocation implements LocationSource {
  @override
  Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 15)}) async => null;
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<LocationPermissionState> permissionState() async => LocationPermissionState.granted;
  @override
  Future<LocationPermissionState> requestPermission() async => LocationPermissionState.granted;
}

void main() {
  test('matcher hands each application to the service once and emits matches', () async {
    final transport = _NullTransport();
    addTearDown(transport.close);
    final service = NearbyService(
      transport: transport,
      location: _NoLocation(),
      selfAddress: () async => 'a' * 76,
      displayName: () => 'Me',
    );
    final matcher = NearbyFriendRequestMatcher(service);
    final seen = <NearbyReply>[];
    final sub = matcher.replies.listen(seen.add);
    // No pending intent: nothing matches, even with a well-formed tag.
    final apps = [
      V2TimFriendApplication(userID: 'p' * 64, addWording: 'toxee-nearby:${'1' * 32} hi', type: 1),
      V2TimFriendApplication(userID: 'q' * 64, addWording: 'hello', type: 1),
    ];
    expect(matcher.offer(apps), isEmpty);
    // The same list offered again is not re-matched.
    expect(matcher.offer(apps), isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);
    await sub.cancel();
    await matcher.dispose();
    service.dispose();
  });
}
