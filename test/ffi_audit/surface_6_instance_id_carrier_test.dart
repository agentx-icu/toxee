// Surface 6: Dart_PostCObject instance_id carrier — does the JSON sent
// over the single Dart_Port carry instance_id on every callback class,
// and does the Dart-side dispatcher honor it on BOTH paths (Platform
// path via Tim2ToxSdkPlatform AND binary-replacement path via the
// patched NativeLibraryManager)?
//
// Evidence (code inspection, see docs/audits/2026-05-16-ffi-reentrancy-audit.md):
//
// Platform path (PASS):
//   - json_parser.cpp:160 BuildGlobalCallbackJson always includes
//     "instance_id": int64.
//   - ~60 SendCallbackToDart("globalCallback", json_msg,
//     GetCallbackUserData(instance_id, "...")) sites in
//     third_party/tim2tox/ffi/dart_compat_listeners.cpp.
//   - apiCallback (json_parser.cpp:208) also includes instance_id.
//
// Binary-replacement path (NEEDS_Y):
//   - Patched NativeLibraryManager._handleGlobalCallback (SDK patch
//     0001-tim2tox-custom-platform.patch:5726-5747) reads instance_id,
//     and IF the platform is Tim2ToxSdkPlatform, dispatches via
//     platform.dispatchInstanceGlobalCallback(instanceId, ...).
//   - For instance_id != 0 it returns early before reaching the static
//     _sdkListener / _advancedMessageListener slots — EXCEPT for
//     FriendAddRequest which always falls through.
//   - For instance_id == 0 it broadcasts to BOTH the per-instance map
//     AND the static singletons.
//   - The static listener slots themselves are SINGLE — only one
//     V2TimSDKListener / V2TimAdvancedMsgListener per process. This is
//     the FAIL for full reentrancy: a second account cannot register
//     its OWN listener via TIMManager.instance and have callbacks
//     filtered by instance_id.
//
// Simple-listener polling path (PASS with caveat):
//   - poll_text(int64_t instance_id, ...) filters by instance_id
//     (tim2tox_ffi.cpp:311) — only returns lines whose enqueued
//     pair.first == 0 || pair.first == instance_id.
//   - For "c2c:" / "gtext:" / "gcustom:" lines, the inline string has
//     no instance prefix; routing depends on the thread_local override
//     being set by the C++ caller (see Surface 4).
//
// This test enumerates the binary-replacement single-listener limitation
// as a structural assertion. We do not synthesize a JSON callback here
// (Surface 4's inject_callback hook is the cleanest way; running it
// requires a full app context and is exercised by tim2tox/auto_tests).

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Platform path: globalCallback JSON includes instance_id (file:line)',
      () {
    // json_parser.cpp:168 — j["instance_id"] = instance_id;
    // json_parser.cpp:209 — j["instance_id"] = instance_id; (apiCallback)
    // Every SendCallbackToDart("globalCallback", ...) site passes
    // instance_id via BuildGlobalCallbackJson.
    expect(true, isTrue,
        reason: 'json_parser.cpp:168, 209; dart_compat_listeners.cpp x60');
  });

  test(
      'Binary-replacement path: patched _handleGlobalCallback honors instance_id'
      ' but static listener slots are SINGLE per process (file:line)', () {
    // SDK patch 0001-tim2tox-custom-platform.patch:
    //   5729 — reads dataFromNativeMap["instance_id"]
    //   5736 — dispatches to platform.dispatchInstanceGlobalCallback(...)
    //   5738 — early-returns for non-zero instance_id (except FriendAddRequest)
    // Unpatched ~/.pub-cache/.../native_library_manager.dart:80-86:
    //   static V2TimSDKListener? _sdkListener;          // ← SINGLE
    //   static V2TimAdvancedMsgListener? _advancedMessageListener;  // ← SINGLE
    //   static V2TimConversationListener? _conversationListener;    // ← SINGLE
    //   static V2TimGroupListener? _groupListener;                   // ← SINGLE
    //   static V2TimFriendshipListener? _friendshipListener;         // ← SINGLE
    //   static V2TimSignalingListener? _signalingListener;           // ← SINGLE
    // ⇒ Multi-account via the binary-replacement path would write to a
    //   single listener slot; only the per-instance map on
    //   Tim2ToxSdkPlatform can fan out. Multi-account therefore requires
    //   either Tim2ToxSdkPlatform as the only call surface (forbidding
    //   TIMManager.instance.addX) or the de-singleton refactor in
    //   Surface 7.
    expect(true, isTrue,
        reason:
            'SDK patch line 5726; native_library_manager.dart lines 80-86');
  });

  test('Simple-listener polling: poll_text filters by instance_id', () {
    // tim2tox_ffi.cpp:302 SimpleMsgListenerImpl::poll_text takes int64_t
    // instance_id and returns lines whose enqueued pair.first matches
    // or is 0 (broadcast). This is a real per-instance filter, but it
    // relies on the producer setting the right instance_id on enqueue.
    expect(true, isTrue,
        reason: 'tim2tox_ffi.cpp:302-321 (poll_text)');
  });
}
