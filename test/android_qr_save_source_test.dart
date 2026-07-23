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
