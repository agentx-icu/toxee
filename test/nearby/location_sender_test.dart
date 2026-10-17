import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/nearby/location_permission_helper.dart';
import 'package:toxee/nearby/location_sender.dart';
import 'package:toxee/nearby/location_source.dart';
import 'package:toxee/util/prefs.dart';

class _Source implements LocationSource {
  _Source({required this.state, this.fix, this.onRead});
  LocationPermissionState state;
  LocationFix? fix;
  final Future<void> Function()? onRead;
  int reads = 0;
  int prompts = 0;
  @override
  Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 15)}) async {
    reads++;
    await onRead?.call();
    return fix;
  }

  @override
  Future<bool> openSettings() async => true;
  @override
  Future<LocationPermissionState> permissionState() async => state;
  @override
  Future<LocationPermissionState> requestPermission() async {
    prompts++;
    return state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final toxId = 'A' * 64;
  final fix = LocationFix(latitude: 1, longitude: 2, accuracyM: 5, at: DateTime(2026));

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<LocationSendOutcome> run(WidgetTester tester, _Source source,
      {String? userID = 'peer', String? groupID, void Function(LocationFix)? onDispatch}) async {
    late LocationSendOutcome outcome;
    final sender = LocationSender(
      source: source,
      currentToxId: () async => toxId,
      permissions: LocationPermissionHelper(source),
      dispatch: (f, u, g) async {
        onDispatch?.call(f);
        return LocationSendOutcome.sent;
      },
    );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(
        onPressed: () async => outcome = await sender.send(context, userID: userID, groupID: groupID),
        child: const Text('go'),
      );
    })));
    await tester.tap(find.text('go'));
    await tester.pump();
    return outcome;
  }

  testWidgets('with the Location switch off nothing is prompted or read', (tester) async {
    final source = _Source(state: LocationPermissionState.granted, fix: fix);
    expect(await run(tester, source), LocationSendOutcome.disabled);
    expect(source.prompts, 0);
    expect(source.reads, 0);
  });

  testWidgets('with the switch on: permission, one fix, dispatch for C2C and groups', (tester) async {
    await LocationPrefs.setLocationEnabled(true, toxId);
    final source = _Source(state: LocationPermissionState.granted, fix: fix);
    LocationFix? dispatched;
    expect(await run(tester, source, onDispatch: (f) => dispatched = f), LocationSendOutcome.sent);
    expect(dispatched, same(fix));
    expect(source.reads, 1);
    expect(await run(tester, source, userID: null, groupID: 'tox_group_1'), LocationSendOutcome.sent);
    expect(await run(tester, source, userID: null, groupID: null), LocationSendOutcome.failed);
  });

  testWidgets('a denied permission is reported and no fix is read', (tester) async {
    await LocationPrefs.setLocationEnabled(true, toxId);
    final source = _Source(state: LocationPermissionState.denied, fix: fix);
    late LocationSendOutcome outcome;
    final sender = LocationSender(
      source: source,
      currentToxId: () async => toxId,
      permissions: _DenyingPermissions(source),
      dispatch: (f, u, g) async => LocationSendOutcome.sent,
    );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(
        onPressed: () async => outcome = await sender.send(context, userID: 'peer'),
        child: const Text('go'),
      );
    })));
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(outcome, LocationSendOutcome.permissionDenied);
    expect(source.reads, 0);
  });

  testWidgets('the switch turned off during the permission prompt wins', (tester) async {
    await LocationPrefs.setLocationEnabled(true, toxId);
    final source = _Source(state: LocationPermissionState.granted, fix: fix);
    late LocationSendOutcome outcome;
    final sender = LocationSender(
      source: source,
      currentToxId: () async => toxId,
      permissions: _FlippingPermissions(source, toxId),
      dispatch: (f, u, g) async => LocationSendOutcome.sent,
    );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(
        onPressed: () async => outcome = await sender.send(context, userID: 'peer'),
        child: const Text('go'),
      );
    })));
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(outcome, LocationSendOutcome.disabled);
    expect(source.reads, 0);
  });

  testWidgets('the switch turned off while the fix was being read wins too', (tester) async {
    await LocationPrefs.setLocationEnabled(true, toxId);
    final source = _Source(
        state: LocationPermissionState.granted,
        fix: fix,
        onRead: () => LocationPrefs.setLocationEnabled(false, toxId));
    var dispatched = false;
    expect(await run(tester, source, onDispatch: (_) => dispatched = true), LocationSendOutcome.disabled);
    expect(dispatched, isFalse);
  });

  testWidgets('no fix is a soft failure', (tester) async {
    await LocationPrefs.setLocationEnabled(true, toxId);
    final source = _Source(state: LocationPermissionState.granted, fix: null);
    expect(await run(tester, source), LocationSendOutcome.noFix);
  });
}

/// The OS said no: `ensure` would show the explain dialog; here it just
/// reports the refusal.
class _DenyingPermissions extends LocationPermissionHelper {
  _DenyingPermissions(super.source);
  @override
  Future<bool> ensure(BuildContext context) async => false;
}

/// Grants, but the user turned the Location switch off while the prompt was up.
class _FlippingPermissions extends LocationPermissionHelper {
  _FlippingPermissions(super.source, this.toxId);
  final String toxId;
  @override
  Future<bool> ensure(BuildContext context) async {
    await LocationPrefs.setLocationEnabled(false, toxId);
    return true;
  }
}
