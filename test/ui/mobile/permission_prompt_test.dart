// P1b (doc/reference/MOBILE_DEVICE_FEATURES.md): a refused permission is
// explained with the go-to-Settings dialog exactly when the OS did not ask —
// never silently, and never on top of the system prompt the user just
// answered.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_permission_handlers.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';

// permission_handler PermissionStatus indices.
const _denied = 0;
const _granted = 1;
const _restricted = 2;
const _permanentlyDenied = 4;

const _channel = MethodChannel('flutter.baseflow.com/permissions/methods');

/// The platform side of permission_handler. The Android rationale flag is
/// true after exactly one refusal in a prompt.
class _FakePlatform {
  _FakePlatform(this.tester);

  final WidgetTester tester;
  int status = _denied;
  int answer = _denied;
  bool rationaleBefore = false;
  bool rationaleAfter = false;
  int requests = 0;

  void install() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      switch (call.method) {
        case 'checkPermissionStatus':
          return status;
        case 'shouldShowRequestPermissionRationale':
          return requests == 0 ? rationaleBefore : rationaleAfter;
        case 'requestPermissions':
          requests++;
          final requested = (call.arguments as List).cast<int>();
          return <int, int>{for (final v in requested) v: answer};
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      ),
    );
  }
}

void main() {
  late BuildContext context;

  Future<_FakePlatform> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          TencentCloudChatLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (c) {
            TencentCloudChatIntl().init(c);
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return _FakePlatform(tester)..install();
  }

  Future<({bool granted, bool prompted})> request(WidgetTester tester) async {
    final result = await TencentCloudChatPermissionHandler.requestPermission(
      'camera',
      context,
    );
    await tester.pumpAndSettle();
    return result;
  }

  final settingsDialog = find.text('Go to Settings');

  group('Android', () {
    testWidgets('a blocked permission is explained, the first time too', (
      tester,
    ) async {
      final platform = await pump(tester)
        ..status = _permanentlyDenied
        ..answer = _permanentlyDenied;
      expect(await request(tester), (granted: false, prompted: false));
      expect(settingsDialog, findsOneWidget);
      expect(platform.requests, 1);
    });

    testWidgets('a refusal the OS makes on its own is explained', (
      tester,
    ) async {
      // "Don't ask again" set outside the app: the status still reads denied,
      // the OS refuses without a prompt and no rationale appears.
      (await pump(tester)).answer = _permanentlyDenied;
      expect(await request(tester), (granted: false, prompted: false));
      expect(settingsDialog, findsOneWidget);
    });

    testWidgets('a first refusal in the prompt gets no second dialog', (
      tester,
    ) async {
      await pump(tester)
        ..answer = _denied
        ..rationaleAfter = true;
      expect(await request(tester), (granted: false, prompted: true));
      expect(settingsDialog, findsNothing);
    });

    testWidgets('a second refusal in the prompt gets no second dialog', (
      tester,
    ) async {
      await pump(tester)
        ..rationaleBefore = true
        ..answer = _permanentlyDenied;
      expect(await request(tester), (granted: false, prompted: true));
      expect(settingsDialog, findsNothing);
    });

    testWidgets('a grant in the prompt reports the consumed press', (
      tester,
    ) async {
      (await pump(tester)).answer = _granted;
      expect(await request(tester), (granted: true, prompted: true));
      expect(settingsDialog, findsNothing);
    });

    testWidgets('an existing grant asks nothing', (tester) async {
      final platform = await pump(tester)
        ..status = _granted;
      expect(await request(tester), (granted: true, prompted: false));
      expect(platform.requests, 0);
      expect(
        await TencentCloudChatPermissionHandler.checkPermission(
          'camera',
          context,
        ),
        isTrue,
      );
    });
  });

  group('iOS', () {
    final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

    testWidgets('not determined: the refusal was made in the alert', (
      tester,
    ) async {
      (await pump(tester)).answer = _permanentlyDenied;
      expect(await request(tester), (granted: false, prompted: true));
      expect(settingsDialog, findsNothing);
    }, variant: iOS);

    testWidgets('turned off in Settings is explained', (tester) async {
      await pump(tester)
        ..status = _permanentlyDenied
        ..answer = _permanentlyDenied;
      expect(await request(tester), (granted: false, prompted: false));
      expect(settingsDialog, findsOneWidget);
    }, variant: iOS);

    testWidgets('restricted is not a grant', (tester) async {
      await pump(tester)
        ..status = _restricted
        ..answer = _restricted;
      expect((await request(tester)).granted, isFalse);
      expect(settingsDialog, findsOneWidget);
    }, variant: iOS);
  });
}
