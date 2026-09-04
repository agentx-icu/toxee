// Regression guard for the shared self-avatar widget.
//
// Before `UserAvatarCircle` every self-avatar surface had its own "no avatar"
// fallback — the sidebar rail even showed the UIKit's stock "hand holding a
// phone" photo while the profile page showed an initial letter — so one
// account rendered three different avatars on a single screen. These tests
// pin the contract every surface now shares: a readable avatar file renders
// as an image, anything else renders the initial.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/widgets/user_avatar_circle.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

// 1x1 opaque PNG.
const List<int> _kPngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, //
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, //
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00, //
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
];

void main() {
  group('UserAvatarCircle.initialFor', () {
    test('upper-cases the first character of the trimmed name', () {
      expect(UserAvatarCircle.initialFor('  recovered 7C99'), 'R');
      expect(UserAvatarCircle.initialFor('ünïcode'), 'Ü');
    });

    test('falls back when the name is blank', () {
      expect(UserAvatarCircle.initialFor(null), '?');
      expect(UserAvatarCircle.initialFor('   '), '?');
      expect(UserAvatarCircle.initialFor('', fallback: 'A'), 'A');
    });
  });

  group('UserAvatarCircle', () {
    testWidgets('renders the initial when there is no avatar path', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const UserAvatarCircle(
            size: 44,
            initial: 'R',
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      );
      expect(find.text('R'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets(
      'renders the initial, not the image, when the file is flagged missing',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const UserAvatarCircle(
              size: 44,
              initial: 'R',
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              avatarPath: '/nonexistent/avatar.png',
              avatarFileExists: false,
            ),
          ),
        );
        expect(find.text('R'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
      },
    );

    // The two file-backed cases do real filesystem IO (temp file + image
    // decode), which never completes inside the fake-async test zone — so
    // they run under `tester.runAsync`.
    testWidgets('renders the avatar file when it exists', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('toxee_avatar_test_');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/avatar.png');
        await file.writeAsBytes(_kPngBytes, flush: true);

        await tester.pumpWidget(
          _host(
            UserAvatarCircle(
              size: 44,
              initial: 'R',
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              avatarPath: file.path,
              avatarFileExists: true,
            ),
          ),
        );
        // Let the file read + decode complete, then rebuild.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
      });
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('R'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a file that fails to decode degrades to the initial', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('toxee_avatar_test_');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/garbage.png');
        await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);

        await tester.pumpWidget(
          _host(
            UserAvatarCircle(
              size: 44,
              initial: 'R',
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              avatarPath: file.path,
              avatarFileExists: true,
            ),
          ),
        );
        // Let the failed decode report through the error builder.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
      });
      expect(find.text('R'), findsOneWidget);
      // The decode failure is reported through Image.errorBuilder, not as an
      // uncaught framework error.
      expect(tester.takeException(), isNull);
    });
  });
}
