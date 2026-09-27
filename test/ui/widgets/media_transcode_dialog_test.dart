// M2: a video converted before sending shows its progress, can be
// cancelled (which stops the send quietly), and closes when it ends.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/navigation/app_navigation.dart';
import 'package:toxee/ui/widgets/media_transcode_dialog.dart';
import 'package:toxee/util/outgoing_media.dart';

void main() {
  const channel = MethodChannel('toxee/media_transcode');
  late Directory root;
  late Completer<void> gate;
  var cancelled = false;

  setUp(() {
    root = Directory.systemTemp.createTempSync('transcode-dialog-test-');
    OutgoingMedia.outputRoot = (account) async => '${root.path}/$account';
    OutgoingMedia.hasVideoConverter = () => true;
    OutgoingMedia.presenter = MediaTranscodeDialog.present;
    gate = Completer<void>();
    cancelled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map<Object?, Object?>;
      switch (call.method) {
        case 'probeVideo':
          return 'hvc1';
        case 'cancelTranscode':
          cancelled = true;
          gate.complete();
          return null;
        case 'transcodeToH264':
          await TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .handlePlatformMessage(
                channel.name,
                channel.codec.encodeMethodCall(
                  MethodCall('progress', {'id': args['id'], 'progress': 0.4}),
                ),
                (_) {},
              );
          await gate.future;
          if (cancelled) throw PlatformException(code: 'CANCELLED');
          File(args['target']! as String).writeAsBytesSync(const [0]);
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    OutgoingMedia.presenter = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    root.deleteSync(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: appNavigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(),
    ),
  );

  String clip() => (File('${root.path}/clip.mov')
        ..writeAsBytesSync([0, 0, 0, 24, ...'ftypqt  '.codeUnits, 0, 0, 0, 0]))
      .path;

  testWidgets('progress, then the dialog closes when the video is ready', (
    tester,
  ) async {
    await pumpApp(tester);
    final path = clip();
    late Future<String> result;
    await tester.runAsync(() async {
      result = OutgoingMedia.prepare(path, accountKey: 'A');
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    expect(find.text('Preparing video…'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);

    String? out;
    await tester.runAsync(() async {
      gate.complete();
      out = await result;
    });
    await tester.pumpAndSettle();
    expect(out, endsWith('.mp4'));
    expect(find.text('Preparing video…'), findsNothing);
  });

  testWidgets('Cancel stops the conversion and the send', (tester) async {
    await pumpApp(tester);
    final path = clip();
    Object? error;
    late Future<void> result;
    await tester.runAsync(() async {
      result = OutgoingMedia.prepare(path, accountKey: 'A').then<void>(
        (_) {},
        onError: (Object e) => error = e,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.tap(find.byKey(MediaTranscodeDialog.cancelKey));
    await tester.runAsync(() => result);
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(error, isA<MediaConversionCancelled>());
    expect(find.text('Preparing video…'), findsNothing);
  });

  testWidgets('two conversions at once: each closes its own dialog', (
    tester,
  ) async {
    await pumpApp(tester);
    final first = clip();
    final second = (File('${root.path}/clip2.mov')
          ..writeAsBytesSync(File(first).readAsBytesSync()))
        .path;
    late Future<String> a, b;
    await tester.runAsync(() async {
      a = OutgoingMedia.prepare(first, accountKey: 'A');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      b = OutgoingMedia.prepare(second, accountKey: 'A');
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    expect(find.text('Preparing video…'), findsNWidgets(2));

    // Both finish (the first one is under the second's dialog).
    await tester.runAsync(() async {
      gate.complete();
      await Future.wait([a, b]);
    });
    await tester.pumpAndSettle();
    expect(find.text('Preparing video…'), findsNothing);
  });
}
