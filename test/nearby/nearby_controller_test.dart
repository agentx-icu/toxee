import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/service/rendezvous_transport.dart';
import 'package:toxee/nearby/location_source.dart';
import 'package:toxee/nearby/nearby_controller.dart';
import 'package:toxee/nearby/nearby_transport.dart';
import 'package:toxee/util/prefs.dart';

/// Lifecycle rules of plan §4.6 / checklist B1, B8, P2: the controller owns
/// one session, stops on pause and on the switches, tears the previous
/// session down on re-attach, and never reads the OS position while either
/// switch is off.
final class _FakeService implements FfiChatService {
  _FakeService(this._toxId);
  final String _toxId;
  @override
  String? getSelfToxId() => _toxId;
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWire implements NearbyTransport {
  final StreamController<RendezvousEvent> _events = StreamController.broadcast();
  int joins = 0;
  int leaveAlls = 0;
  Future<void> close() => _events.close();
  @override
  Stream<RendezvousEvent> get events => _events.stream;
  @override
  int join(Uint8List seed, {required String name, required String nick}) {
    joins++;
    return 1;
  }

  @override
  bool leave(String chatIdHex) => true;
  @override
  int leaveAll() {
    leaveAlls++;
    return 0;
  }

  @override
  int send(String chatIdHex, Uint8List payload, {String? peerPkHex}) => 1;
  @override
  int peerCount(String chatIdHex) => 0;
  @override
  int dhtAnnounceCapableCount() => 8;
}

class _FakeLocation implements LocationSource {
  int reads = 0;
  @override
  Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 15)}) async {
    reads++;
    return LocationFix(latitude: 39.9, longitude: 116.4, accuracyM: 20, at: DateTime.now());
  }

  @override
  Future<bool> openSettings() async => true;
  @override
  Future<LocationPermissionState> permissionState() async => LocationPermissionState.granted;
  @override
  Future<LocationPermissionState> requestPermission() async => LocationPermissionState.granted;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final toxA = 'A' * 76;
  final toxB = 'B' * 76;
  late _FakeWire wire;
  late _FakeLocation location;
  final controller = NearbyController.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    wire = _FakeWire();
    location = _FakeLocation();
    NearbyController.transportOverride = (_) => wire;
    NearbyController.locationSourceOverride = location;
  });

  tearDown(() async {
    final s = controller.service;
    if (s != null) await controller.shutdownSession(s);
    NearbyController.transportOverride = null;
    NearbyController.locationSourceOverride = null;
    await wire.close();
  });

  Future<void> switchesOn(String toxId) async {
    await LocationPrefs.setLocationEnabled(true, toxId);
    await LocationPrefs.setNearbyVisible(true, toxId);
  }

  test('both switches off: startIfEnabled refuses and the OS is never read', () async {
    final service = _FakeService(toxA);
    controller.attach(service, displayName: () => 'A');
    expect(await controller.startIfEnabled(), isFalse);
    expect(location.reads, 0);
    await LocationPrefs.setLocationEnabled(true, toxA); // nearby still hidden
    expect(await controller.startIfEnabled(), isFalse);
    expect(location.reads, 0);
  });

  test('switches on: starts, joins; pause stops; switch off mid-session stops before a read', () async {
    final service = _FakeService(toxA);
    controller.attach(service, displayName: () => 'A');
    await switchesOn(toxA);
    expect(await controller.startIfEnabled(), isTrue);
    expect(location.reads, 1);
    expect(wire.joins, greaterThan(0));
    // Background: foreground-only feature.
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(controller.nearby!.running, isFalse);
    expect(wire.leaveAlls, greaterThanOrEqualTo(1));
    // Resume + reopen starts again; then the user flips a switch off.
    expect(await controller.startIfEnabled(), isTrue);
    expect(location.reads, 2);
    await LocationPrefs.setNearbyVisible(false, toxA);
    await controller.nearby!.refresh();
    expect(controller.nearby!.running, isFalse);
    expect(location.reads, 2, reason: 'the switch is re-read before every position read');
  });

  test('attaching another account tears the previous session down', () async {
    final a = _FakeService(toxA);
    controller.attach(a, displayName: () => 'A');
    await switchesOn(toxA);
    expect(await controller.startIfEnabled(), isTrue);
    final previous = controller.nearby!;
    final b = _FakeService(toxB);
    controller.attach(b, displayName: () => 'B');
    await Future<void>.delayed(Duration.zero);
    expect(previous.running, isFalse);
    expect(wire.leaveAlls, greaterThanOrEqualTo(1));
    expect(identical(controller.service, b), isTrue);
    expect(controller.nearby, isNot(same(previous)));
    // Re-attaching the live service is a no-op.
    final current = controller.nearby;
    controller.attach(b, displayName: () => 'B');
    expect(controller.nearby, same(current));
  });

  test('shutdownSession only acts on the live service and detaches', () async {
    final a = _FakeService(toxA);
    controller.attach(a, displayName: () => 'A');
    await switchesOn(toxA);
    expect(await controller.startIfEnabled(), isTrue);
    await controller.shutdownSession(_FakeService(toxB)); // not ours
    expect(controller.attached, isTrue);
    expect(controller.nearby!.running, isTrue);
    await controller.shutdownSession(a);
    expect(controller.attached, isFalse);
    expect(controller.nearby, isNull);
    expect(wire.leaveAlls, greaterThanOrEqualTo(1));
    expect(await controller.startIfEnabled(), isFalse);
  });

  test('re-attach over the same transport: the old session is down before the new one starts', () async {
    final a = _FakeService(toxA);
    controller.attach(a, displayName: () => 'A');
    await switchesOn(toxA);
    await switchesOn(toxB);
    expect(await controller.startIfEnabled(), isTrue);
    final old = controller.nearby!;
    final joinsBefore = wire.joins;
    // Attach B without waiting; its start must wait for A's teardown.
    controller.attach(_FakeService(toxB), displayName: () => 'B');
    expect(await controller.startIfEnabled(), isTrue);
    expect(old.running, isFalse);
    expect(wire.leaveAlls, greaterThanOrEqualTo(1));
    expect(controller.nearby!.running, isTrue);
    expect(wire.joins, greaterThan(joinsBefore));
    // The old session's late work does nothing on the shared wire.
    final joinsAfter = wire.joins;
    await old.refresh();
    expect(wire.joins, joinsAfter);
  });

  test('resume restarts only while a nearby page is open', () async {
    final a = _FakeService(toxA);
    controller.attach(a, displayName: () => 'A');
    await switchesOn(toxA);
    expect(await controller.startIfEnabled(), isTrue);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(controller.nearby!.running, isFalse);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(controller.nearby!.running, isFalse, reason: 'no page open');
    controller.pageOpened();
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    for (var i = 0; i < 20 && !controller.nearby!.running; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.nearby!.running, isTrue);
    controller.pageClosed();
  });

  test('a stop that lands while a start is queued behind a teardown wins', () async {
    final a = _FakeService(toxA);
    controller.attach(a, displayName: () => 'A');
    await switchesOn(toxA);
    await switchesOn(toxB);
    expect(await controller.startIfEnabled(), isTrue);
    // Re-attach queues a teardown; a start queued behind it, then a stop.
    controller.attach(_FakeService(toxB), displayName: () => 'B');
    final queued = controller.startIfEnabled();
    await controller.stop();
    expect(await queued, isFalse);
    expect(controller.nearby!.running, isFalse);
    expect(location.reads, 1, reason: 'only the first session read the OS');
  });
}
