@Tags(['needs-native'])
library;

import 'dart:async';
import 'dart:io';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart' as ffi_lib;
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/lan_bootstrap_service.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appSupport;
  late ffi_lib.Tim2ToxFfi ffi;
  late int previousCurrent;
  late int defaultInitializedBefore;
  late LanBootstrapServiceManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
    appSupport = Directory.systemTemp.createTempSync(
      'toxee_lan_bootstrap_native_',
    );
    AppPaths.debugApplicationSupportOverride = appSupport.path;

    ffi = ffi_lib.Tim2ToxFfi.open();
    previousCurrent = ffi.getCurrentInstanceId();
    expect(ffi.setCurrentInstance(0), 1);
    defaultInitializedBefore = ffi.isInstanceInitialized(0);

    manager = LanBootstrapServiceManager.forTesting(
      localAddressProvider: () async => '192.168.56.10',
    );
  });

  tearDown(() async {
    await manager.stopLocalBootstrapService();
    ffi.setCurrentInstance(previousCurrent);
    AppPaths.debugApplicationSupportOverride = null;
    if (appSupport.existsSync()) {
      appSupport.deleteSync(recursive: true);
    }
  });

  test(
    'start and stop own a real native handle while restoring default instance zero',
    () async {
      expect(await manager.startLocalBootstrapService(33445), isTrue);

      final handle = manager.nativeInstanceHandle;
      final info = await manager.getBootstrapServiceInfo();
      expect(handle, isNotNull);
      expect(handle, isNot(0));
      expect(ffi.isInstanceInitialized(handle!), 1);
      expect(
        ffi.isInstanceEventLoopRunning(handle),
        1,
        reason: 'the manager-owned native instance must pump tox events',
      );
      expect(ffi.getCurrentInstanceId(), 0);
      expect(manager.isBootstrapServiceRunning(), isTrue);
      expect(info, isNotNull);
      expect(info!.ip, '192.168.56.10');
      expect(info.port, greaterThan(0));
      expect(info.pubkey, matches(RegExp(r'^[0-9A-Fa-f]{64}$')));
      expect(await Prefs.getLanBootstrapServiceRunning(), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        ffi.getCurrentInstanceId(),
        0,
        reason: 'native background work must not change ambient instance',
      );

      await manager.stopLocalBootstrapService();

      expect(ffi.getCurrentInstanceId(), 0);
      expect(ffi.isInstanceInitialized(handle), 0);
      expect(ffi.isInstanceEventLoopRunning(handle), 0);
      expect(ffi.isInstanceInitialized(0), defaultInitializedBefore);
      expect(manager.nativeInstanceHandle, isNull);
      expect(manager.isBootstrapServiceRunning(), isFalse);
      expect(await manager.getBootstrapServiceInfo(), isNull);
      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
    },
  );

  test('start and stop are idempotent for one manager-owned handle', () async {
    expect(await manager.startLocalBootstrapService(33445), isTrue);
    final firstHandle = manager.nativeInstanceHandle;
    expect(firstHandle, isNotNull);

    expect(await manager.startLocalBootstrapService(33445), isTrue);
    expect(manager.nativeInstanceHandle, firstHandle);
    expect(ffi.isInstanceInitialized(firstHandle!), 1);

    await manager.stopLocalBootstrapService();
    await manager.stopLocalBootstrapService();

    expect(ffi.isInstanceInitialized(firstHandle), 0);
    expect(ffi.getCurrentInstanceId(), 0);
    expect(manager.nativeInstanceHandle, isNull);
  });

  test(
    'a timed-out address lookup cannot publish a late native service',
    () async {
      final address = Completer<String?>();
      manager = LanBootstrapServiceManager.forTesting(
        localAddressProvider: () => address.future,
        startupTimeout: const Duration(milliseconds: 10),
      );

      expect(await manager.startLocalBootstrapService(33445), isFalse);
      address.complete('192.168.56.10');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(manager.nativeInstanceHandle, isNull);
      expect(manager.isBootstrapServiceRunning(), isFalse);
      expect(await manager.getBootstrapServiceInfo(), isNull);
      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
      expect(ffi.getCurrentInstanceId(), 0);
    },
  );

  test('concurrent starts await one shared native startup result', () async {
    final address = Completer<String?>();
    var addressLookups = 0;
    manager = LanBootstrapServiceManager.forTesting(
      localAddressProvider: () {
        addressLookups += 1;
        return address.future;
      },
    );

    final first = manager.startLocalBootstrapService(33445);
    final second = manager.startLocalBootstrapService(33445);
    address.complete('192.168.56.10');

    expect(await Future.wait([first, second]), [isTrue, isTrue]);
    expect(addressLookups, 1);
    expect(manager.nativeInstanceHandle, isNotNull);
  });

  test('stop cancels a startup still waiting for its LAN address', () async {
    final address = Completer<String?>();
    var addressLookups = 0;
    manager = LanBootstrapServiceManager.forTesting(
      localAddressProvider: () {
        addressLookups += 1;
        if (addressLookups == 1) return address.future;
        return Future<String?>.value('192.168.56.10');
      },
    );

    final pendingStart = manager.startLocalBootstrapService(33445);
    await manager.stopLocalBootstrapService();

    expect(
      await pendingStart.timeout(const Duration(milliseconds: 100)),
      isFalse,
      reason: 'stop must complete callers without waiting for address timeout',
    );

    final restarted = manager.startLocalBootstrapService(33445);
    address.complete('192.168.56.99');

    expect(await restarted, isTrue);
    expect(addressLookups, 2);
    expect(manager.nativeInstanceHandle, isNotNull);
    expect(manager.isBootstrapServiceRunning(), isTrue);
    expect(await Prefs.getLanBootstrapServiceRunning(), isTrue);
  });

  test(
    'stop clears stale Dart state when native handle was already destroyed',
    () async {
      expect(await manager.startLocalBootstrapService(33445), isTrue);
      final handle = manager.nativeInstanceHandle!;
      expect(ffi.destroyTestInstance(handle), 1);

      await manager.stopLocalBootstrapService();

      expect(manager.nativeInstanceHandle, isNull);
      expect(manager.isBootstrapServiceRunning(), isFalse);
      expect(await manager.getBootstrapServiceInfo(), isNull);
      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
      expect(ffi.getCurrentInstanceId(), 0);
    },
  );

  test('start and stop preserve a nonzero user current instance', () async {
    final userProfile = Directory('${appSupport.path}/user_instance')
      ..createSync(recursive: true);
    final profilePath = userProfile.path.toNativeUtf8();
    final int userHandle;
    try {
      userHandle = ffi.createTestInstanceExNative(profilePath, 0, 0);
    } finally {
      pkgffi.malloc.free(profilePath);
    }
    expect(userHandle, isNot(0));

    try {
      expect(ffi.setCurrentInstance(userHandle), 1);
      expect(await manager.startLocalBootstrapService(33445), isTrue);
      expect(ffi.getCurrentInstanceId(), userHandle);

      await manager.stopLocalBootstrapService();

      expect(ffi.getCurrentInstanceId(), userHandle);
      expect(ffi.isInstanceInitialized(userHandle), 1);
    } finally {
      ffi.setCurrentInstance(0);
      ffi.destroyTestInstance(userHandle);
    }
  });
}
