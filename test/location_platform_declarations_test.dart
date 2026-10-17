// The OS-facing contracts of the location feature: the permission strings
// and entitlements the platforms require before a location may be read.
// Like android_call_manifest_test, these are files no Dart test can render,
// so the declaration itself is the thing under test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android declares coarse + fine location, no location service type', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_LOCATION')),
        reason: 'v1 is foreground-only');
  });

  test('iOS and macOS carry the usage strings in every localization', () {
    final ios = File('ios/Runner/Info.plist').readAsStringSync();
    expect(ios, contains('NSLocationWhenInUseUsageDescription'));
    final mac = File('macos/Runner/Info.plist').readAsStringSync();
    expect(mac, contains('NSLocationWhenInUseUsageDescription'));
    expect(mac, contains('NSLocationUsageDescription'));
    for (final platform in ['ios', 'macos']) {
      for (final loc in ['en', 'zh-Hans', 'zh-Hant', 'ja', 'ko', 'ar']) {
        final strings = File('$platform/Runner/$loc.lproj/InfoPlist.strings').readAsStringSync();
        expect(strings, contains('NSLocationWhenInUseUsageDescription'),
            reason: '$platform $loc');
        // Xcode's strings parser (plutil) rejects an unescaped quote inside a
        // value, which breaks the whole platform build: every entry must be
        // `"key" = "value";` with no bare quote in the value.
        final entry = RegExp(r'^"([^"\\]|\\.)*"\s*=\s*"([^"\\]|\\.)*";$');
        for (final line in strings.split('\n')) {
          final l = line.trim();
          if (l.isEmpty || l.startsWith('//') || l.startsWith('/*') || l.startsWith('*')) continue;
          expect(entry.hasMatch(l), isTrue, reason: '$platform $loc: $l');
        }
      }
    }
  });

  test('macOS entitlements allow location and the msix declares the capability', () {
    for (final f in ['macos/Runner/DebugProfile.entitlements', 'macos/Runner/Release.entitlements']) {
      expect(File(f).readAsStringSync(),
          contains('com.apple.security.personal-information.location'), reason: f);
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final msix = RegExp(r'capabilities:\s*(.+)').firstMatch(pubspec)!.group(1)!;
    expect(msix.split(',').map((s) => s.trim()), contains('location'));
  });
}
