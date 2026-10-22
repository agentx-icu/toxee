import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('system picker does not declare broad media access', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    for (final name in [
      'READ_MEDIA_IMAGES',
      'READ_MEDIA_VIDEO',
      'READ_MEDIA_AUDIO',
    ]) {
      expect(manifest, isNot(contains('android.permission.$name')));
    }
    expect(manifest, contains('android.permission.MANAGE_OWN_CALLS'));
  });
  test('camera microphone and location are optional install capabilities', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    for (final name in [
      'camera',
      'camera.autofocus',
      'microphone',
      'location',
      'location.gps',
      'location.network',
    ]) {
      expect(
        manifest,
        contains('android.hardware.$name" android:required="false"'),
      );
    }
  });
  test('Linux package installs the desktop file for its GApplication ID', () {
    final cmake = File(
      'tool/ci/linux-installer/CMakeLists.txt',
    ).readAsStringSync();
    expect(cmake, contains('RENAME "com.toxee.app.desktop"'));
    expect(cmake, contains('CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON'));
  });
}
