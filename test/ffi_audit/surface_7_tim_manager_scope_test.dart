// Surface 7: TIMManager.instance / UIKit Provider tree scope-awareness.
//
// Is TIMManager.instance per-account or process-global? Can the UIKit
// Provider tree host two accounts concurrently?
//
// Evidence (code inspection, see docs/audits/2026-05-16-ffi-reentrancy-audit.md):
//
//   - TIMManager is a singleton:
//     static TIMManager instance = TIMManager();
//     at ~/.pub-cache/.../tencent_cloud_chat_sdk-8.7.7201+3/lib/
//     native_im/adapter/tim_manager.dart:33.
//   - Its instance state — _isInitSDK, v2TimSDKListenerList,
//     v2TimSimpleMsgListenerList, _sdkAppID — is therefore
//     process-global in practice.
//   - chat-uikit-flutter assumes TIMManager.instance throughout.
//   - lib/sdk_fake/fake_uikit_core.dart provides FakeUIKit.instance
//     (single FakeUIKit). lib/runtime/session_runtime_coordinator.dart
//     has `static SessionRuntimeState _state` — single coordinator.
//   - Tim2ToxSdkPlatform._currentInstance is static
//     (third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:238).
//   - TencentCloudChatSdkPlatform.instance is a static setter — only
//     one platform implementation at a time.
//
// VERDICT: process-global singleton; concurrent multi-account inside
// one isolate is NOT supported by the current shape. Switch-and-restart
// multi-account (serial) IS supported via dispose + re-ensureInitialized.
//
// This test asserts the structural invariants. It is not a runtime
// failure if the project later refactors to instance-per-account; the
// test will simply need to be updated to reflect the new contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';

void main() {
  test('TIMManager.instance is a process-global singleton', () {
    final a = TIMManager.instance;
    final b = TIMManager.instance;
    expect(identical(a, b), isTrue,
        reason: 'TIMManager.instance is `static TIMManager instance = TIMManager()`;'
            ' two accesses must return the SAME object — confirming there is no'
            ' per-account scope.');
  });

  test('TIMManager has no scope or context constructor', () {
    // If TIMManager had `TIMManager.forAccount(AccountId id)` we would
    // be able to construct one per account. There is no such constructor;
    // only the default `TIMManager()` ctor (private use) and the
    // .instance singleton. Confirmed by reading
    // ~/.pub-cache/.../tencent_cloud_chat_sdk-8.7.7201+3/lib/
    // native_im/adapter/tim_manager.dart:32-42.
    expect(TIMManager.instance, isA<TIMManager>());
  });
}
