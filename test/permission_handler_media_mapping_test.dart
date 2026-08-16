import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_permission_handlers.dart';

/// REGRESSION GUARD for the iOS permission mapping.
///
/// THE DEFECT THIS PINS DOWN. `Permission.videos` (index 32) and
/// `Permission.audio` (index 33) are ANDROID-ONLY permissions —
/// `READ_MEDIA_VIDEO` / `READ_MEDIA_AUDIO`, Android 13+. Those indices are
/// forwarded verbatim to the iOS plugin as `PermissiongroupVideos` /
/// `PermissionGroupAudio`, and `permission_handler_apple`'s
/// `PermissionManager.createPermissionStrategy:` has NO case for either, so
/// both fall through to `default: return [UnknownPermissionStrategy new]`.
/// `UnknownPermissionStrategy` never asks iOS anything: `checkPermissionStatus:`
/// hardcodes `PermissionStatusDenied` and `requestPermission:` hardcodes
/// `PermissionStatusPermanentlyDenied`. So on iOS those two permissions can
/// NEVER be granted, and `TencentCloudChatPermissionHandler.checkPermission`
/// would push the user into its "go to Settings" dialog for a toggle that does
/// not exist.
///
/// Unlike the microphone/camera/photos breakage, this is NOT fixable from
/// `ios/Podfile` (there is no `PERMISSION_VIDEOS` / `PERMISSION_AUDIO` opt-in
/// macro — the strategy class does not exist) and NOT fixable from `Info.plist`
/// (there is no usage-description key for an Android media-read permission).
/// The fix is the mapping itself, in the fork's permission handler.
///
/// Runs on the host VM only: `getPermissionEnum` takes its non-Android branch
/// there (`TencentCloudChatPlatformAdapter().isAndroid` is false) and that
/// branch touches no platform channel, so this is a genuine unit test of the
/// mapping rather than a source scrape. The Android branch is unreachable from
/// a desktop test VM and is covered by the manifest instead
/// (`READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` / `READ_MEDIA_AUDIO` are all
/// declared in `android/app/src/main/AndroidManifest.xml`).
void main() {
  group('non-Android permission mapping never uses Android-only media groups', () {
    for (final key in const ['video', 'videos']) {
      test("'$key' maps to the photo library, not Permission.videos", () async {
        final permission = await TencentCloudChatPermissionHandler
            .getPermissionEnum(key);
        expect(
          permission,
          isNot(Permission.videos),
          reason:
              'Permission.videos resolves to UnknownPermissionStrategy on iOS, '
              'which answers permanentlyDenied without ever asking the OS.',
        );
        expect(
          permission,
          Permission.photos,
          reason:
              'on iOS a video IS a Photos-library asset, gated by the same '
              'NSPhotoLibraryUsageDescription / PHPhotoLibrary authorisation '
              'as an image (PERMISSION_PHOTOS=1 is set in ios/Podfile).',
        );
      });
    }

    for (final key in const ['audio', 'audios']) {
      test("'$key' requires no runtime permission", () async {
        final permission = await TencentCloudChatPermissionHandler
            .getPermissionEnum(key);
        expect(
          permission,
          isNot(Permission.audio),
          reason:
              'Permission.audio resolves to UnknownPermissionStrategy on iOS, '
              'which answers permanentlyDenied without ever asking the OS.',
        );
        expect(
          permission,
          isNot(Permission.mediaLibrary),
          reason:
              'Permission.mediaLibrary is the APPLE MUSIC library '
              '(NSAppleMusicUsageDescription) — a corpus this app never reads, '
              'and requesting it without that usage string terminates the app.',
        );
        expect(
          permission,
          isNull,
          reason:
              'reading an audio FILE on iOS goes through UIDocumentPicker, '
              'which grants per-file access out of process and needs no '
              'runtime permission; null makes checkPermission report success.',
        );
      });
    }

    test("'photos' and 'storage' still map to the photo library", () async {
      for (final key in const ['photo', 'photos', 'storage']) {
        expect(
          await TencentCloudChatPermissionHandler.getPermissionEnum(key),
          Permission.photos,
          reason: "'$key' regressed",
        );
      }
    });

    test('camera and microphone are untouched', () async {
      expect(
        await TencentCloudChatPermissionHandler.getPermissionEnum('camera'),
        Permission.camera,
      );
      expect(
        await TencentCloudChatPermissionHandler.getPermissionEnum('microphone'),
        Permission.microphone,
      );
    });
  });

  test('ios/Podfile keeps the permission_handler_apple opt-in macros', () async {
    final podfile = await File(
      '${Directory.current.path}/ios/Podfile',
    ).readAsString();
    // Without these, permission_handler_apple compiles the strategies out and
    // AudioVideoPermissionStrategy / PhotoPermissionStrategy degrade to
    // UnknownPermissionStrategy — every call preflight would report
    // permanentlyDenied. Each one has a matching Info.plist usage string
    // (asserted by ios_media_permission_descriptions_test.dart); do not add a
    // macro here without adding its usage string, or iOS terminates the app on
    // first request.
    for (final macro in const [
      'PERMISSION_MICROPHONE=1',
      'PERMISSION_CAMERA=1',
      'PERMISSION_PHOTOS=1',
    ]) {
      expect(podfile, contains(macro), reason: '$macro was dropped');
    }
    expect(
      podfile,
      isNot(contains('PERMISSION_MEDIA_LIBRARY=1')),
      reason:
          'enabling the Apple Music library group without '
          'NSAppleMusicUsageDescription is an immediate iOS termination on '
          'request, and nothing in toxee reads that library.',
    );
  });
}
