// L1 gate for the Dart half of S47 — the auto-accept-group-invites bootstrap
// push. The scoped Pref round-trip is already covered
// (test/account_toggle_persistence_test.dart); this covers the OTHER Dart half
// codex flagged: at HomePage bootstrap the persisted toggle is READ and PUSHED
// into the native gate via `FfiChatService.setAutoAcceptGroupInvites`. The C++
// gate behaviour (`g_auto_accept_group_invites` + `tox_group_invite_accept`) is
// the remaining native residual, exercised by the live two-process group flows.
//
// `loadAndApplyAutoAcceptGroupInvites` was extracted from the bootstrap so this
// is testable without pumping the (un-pumpable) HomePage.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/ui/home/auto_accept_apply.dart';
import 'package:toxee/util/prefs.dart';

// 64-char id → Prefs scopes on the first 16 hex (account-scoped key).
final String _toxId = 'A' * 64;

class _CaptureService extends FfiChatService {
  _CaptureService() : super();

  /// Records the values pushed to the native gate. Overridden so the test never
  /// reaches the real FFI `setAutoAcceptGroupInvitesNative`.
  final List<bool> pushed = <bool>[];

  @override
  void setAutoAcceptGroupInvites(bool enabled) => pushed.add(enabled);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
      'S47: a mounted bootstrap mirrors then pushes the scoped pref (true and '
      'false), in that order', () async {
    await Prefs.setAutoAcceptGroupInvites(true, _toxId);
    final svc = _CaptureService();
    final events = <String>[]; // ordered log to prove mirror-before-push
    final returned = await loadAndApplyAutoAcceptGroupInvites(
      svc,
      _toxId,
      isStillMounted: () => true,
      mirrorToUi: (v) => events.add('mirror:$v'),
    );
    for (var v in svc.pushed) {
      events.add('push:$v');
    }
    expect(returned, isTrue);
    expect(svc.pushed, <bool>[true],
        reason: 'the persisted ON toggle must reach setAutoAcceptGroupInvites');
    // mirror must precede push so a throwing FFI setter cannot drop the UI
    // mirror (codex IMPORTANT).
    expect(events, <String>['mirror:true', 'push:true']);

    await Prefs.setAutoAcceptGroupInvites(false, _toxId);
    final svc2 = _CaptureService();
    final mirrored2 = <bool>[];
    final returned2 = await loadAndApplyAutoAcceptGroupInvites(
      svc2,
      _toxId,
      isStillMounted: () => true,
      mirrorToUi: mirrored2.add,
    );
    expect(returned2, isFalse);
    expect(mirrored2, <bool>[false]);
    expect(svc2.pushed, <bool>[false],
        reason: 'the persisted OFF toggle must reach the gate too');
  });

  test(
      'S47: an UNMOUNTED bootstrap still loads the value but does NOT mirror or '
      'push a stale setting', () async {
    await Prefs.setAutoAcceptGroupInvites(true, _toxId);
    final svc = _CaptureService();
    final mirrored = <bool>[];
    final returned = await loadAndApplyAutoAcceptGroupInvites(
      svc,
      _toxId,
      isStillMounted: () => false,
      mirrorToUi: mirrored.add,
    );
    expect(returned, isTrue, reason: 'the value is still read + returned');
    expect(svc.pushed, isEmpty,
        reason:
            'an account switch that unmounts HomePage must not push a stale '
            'auto-accept value into a service re-initialising for another '
            'account');
    expect(mirrored, isEmpty, reason: 'an unmounted bootstrap must not mirror');
  });
}
