// Concurrency regression tests for SessionRuntimeCoordinator's init/dispose
// serialization (#3 and #4 from the lifecycle hardening review).
//
// The real init/dispose BODIES (FakeUIKit / platform / callServiceManager /
// badge / hook) aren't safe to bring up in a pure-Dart test, so we replace
// them with controllable async via the coordinator's `debugInitBodyOverride` /
// `debugTeardownBodyOverride` test seams. The SERIALIZATION logic under test —
// the ensureInitialized loop, the `_disposing` gate, the generation guard, and
// the `started` commit — still runs for real. Gates (Completers) let us pin
// down the exact interleavings that the two bugs needed.
//
// Constructing FfiChatService calls Tim2ToxFfi.open(); if the native dylib
// isn't loadable the tests skip (same convention as
// session_runtime_lifecycle_test.dart). The service is never exercised here —
// the overrides stand in for everything that would touch it.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/runtime/session_runtime_coordinator.dart';

bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('SessionRuntimeCoordinator init/dispose serialization', () {
    late SessionRuntimeCoordinator coord;

    setUp(() {
      SessionRuntimeCoordinator.debugReset();
      if (ffiAvailable) {
        coord = SessionRuntimeCoordinator(service: FfiChatService());
      }
    });

    tearDown(() {
      SessionRuntimeCoordinator.debugReset();
    });

    test('#4: a re-init started during teardown blocks until teardown fully '
        'completes (no interleave with the teardown tail)', () async {
      // Bring the runtime to `started` via an immediate init body.
      SessionRuntimeCoordinator.debugInitBodyOverride = (_) async {};
      await coord.ensureInitialized();
      expect(SessionRuntimeCoordinator.state, SessionRuntimeState.started);

      final order = <String>[];
      final teardownGate = Completer<void>();
      SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {
        order.add('teardown-start');
        await teardownGate.future;
        order.add('teardown-end');
      };
      SessionRuntimeCoordinator.debugInitBodyOverride = (_) async {
        order.add('init-run');
      };

      // Start teardown: it publishes tearingDown, then hangs in the override
      // while still holding [_disposing].
      final disposeFuture = SessionRuntimeCoordinator.disposeRuntime();
      await Future<void>.delayed(Duration.zero);
      expect(order, ['teardown-start']);
      expect(SessionRuntimeCoordinator.state, SessionRuntimeState.tearingDown);

      // Start a re-init: it must block at the top on [_disposing] and NOT run
      // its body while teardown is in flight (#4).
      final initFuture = coord.ensureInitialized();
      await Future<void>.delayed(Duration.zero);
      expect(
        order,
        ['teardown-start'],
        reason:
            're-init must not run its body while teardown is in flight (#4)',
      );

      // Release teardown → it finishes → re-init unblocks and runs its body.
      teardownGate.complete();
      await disposeFuture;
      await initFuture;

      expect(order, [
        'teardown-start',
        'teardown-end',
        'init-run',
      ], reason: 'init body must run strictly after teardown completes');
      expect(SessionRuntimeCoordinator.state, SessionRuntimeState.started);
    }, skip: skipReason);

    test('#3: an init superseded by a concurrent dispose does not report a '
        'false success — it re-inits and ends started', () async {
      var initCalls = 0;
      final firstInitGate = Completer<void>();
      SessionRuntimeCoordinator.debugInitBodyOverride = (_) async {
        initCalls++;
        if (initCalls == 1) {
          // First init hangs mid-body so a dispose can supersede it.
          await firstInitGate.future;
        }
        // The re-init (call #2) completes immediately.
      };
      SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {};

      // Init A claims the section and hangs in init body #1.
      final initFuture = coord.ensureInitialized();
      await Future<void>.delayed(Duration.zero);
      expect(SessionRuntimeCoordinator.state, SessionRuntimeState.starting);
      expect(initCalls, 1);

      // Concurrently dispose: it bumps the generation and awaits A's init.
      final disposeFuture = SessionRuntimeCoordinator.disposeRuntime();
      await Future<void>.delayed(Duration.zero);

      // Release A's first init body. A hits the generation guard (superseded),
      // does NOT publish `started`, completes its completer (unblocking
      // dispose), then loops — waits out the dispose and re-inits.
      firstInitGate.complete();
      await disposeFuture;
      await initFuture;

      expect(
        initCalls,
        2,
        reason:
            'the superseded init must loop and re-run the init body, not '
            'return a false success after one superseded attempt (#3)',
      );
      expect(
        SessionRuntimeCoordinator.state,
        SessionRuntimeState.started,
        reason: 'ensureInitialized must end with the runtime actually up',
      );
    }, skip: skipReason);

    test('a joiner of a superseded init does not report false success either '
        '(#3, join path)', () async {
      var initCalls = 0;
      final firstInitGate = Completer<void>();
      SessionRuntimeCoordinator.debugInitBodyOverride = (_) async {
        initCalls++;
        if (initCalls == 1) {
          await firstInitGate.future;
        }
      };
      SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {};

      // Initiator A claims and hangs.
      final initiator = coord.ensureInitialized();
      await Future<void>.delayed(Duration.zero);
      expect(SessionRuntimeCoordinator.state, SessionRuntimeState.starting);

      // Joiner B joins the in-flight init (await inFlight path).
      final joiner = coord.ensureInitialized();
      await Future<void>.delayed(Duration.zero);

      // Dispose supersedes the in-flight init.
      final disposeFuture = SessionRuntimeCoordinator.disposeRuntime();
      await Future<void>.delayed(Duration.zero);

      firstInitGate.complete();
      await Future.wait([initiator, joiner, disposeFuture]);

      // Both the initiator and the joiner must end with the runtime genuinely
      // `started` (re-init happened), not a false success against a disposed
      // runtime.
      expect(SessionRuntimeCoordinator.state, SessionRuntimeState.started);
      expect(
        initCalls,
        2,
        reason:
            'exactly one re-init after supersede; the join must not '
            'trigger an extra independent init',
      );
    }, skip: skipReason);
  });
}
