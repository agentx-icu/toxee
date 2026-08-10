// WHAT THIS IS: a source-text contract over Kotlin, not a behaviour test.
// See the header of `test/android_call_audio_channel_source_test.dart` for the
// full rationale.
//
// Short version: it greps `android/app/.../MainActivity.kt` for the legacy
// (API <= 28) WRITE_EXTERNAL_STORAGE permission dance around QR gallery saves.
// That path only exists in Kotlin and only runs on a pre-Android-10 device, so
// it can be neither executed nor rendered from `flutter test`; the grep is the
// only automated guard we have that the permission request and the
// resume-after-grant bookkeeping were not deleted.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sourceFile = File(
    '${Directory.current.path}/android/app/src/main/kotlin/com/toxee/app/MainActivity.kt',
  );

  test('legacy Android QR gallery save requests storage permission', () async {
    final source = await sourceFile.readAsString();

    expect(source, contains('Manifest.permission.WRITE_EXTERNAL_STORAGE'));
    expect(source, contains('Build.VERSION.SDK_INT <= Build.VERSION_CODES.P'));
    expect(source, contains('requestPermissions('));
    expect(source, contains('onRequestPermissionsResult'));
    expect(source, contains('QR_SAVE_PERMISSION_REQUEST'));
    expect(source, contains('PERMISSION_DENIED'));
  });

  test(
    'legacy QR permission flow keeps one pending result and resumes save',
    () async {
      final source = await sourceFile.readAsString();

      expect(source, contains('pendingQrSaveResult'));
      expect(source, contains('pendingQrSavePath'));
      expect(source, contains('SAVE_IN_PROGRESS'));
      expect(source, contains('saveImageToGallery(path, result)'));
    },
  );
}
