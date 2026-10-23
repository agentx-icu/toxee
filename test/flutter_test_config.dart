import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

/// Plugin 19+ registers Dart platform implementations in the generated app
/// registrant. Unit tests do not run that registrant; their default target is
/// Android and the existing method-channel fakes exercise that implementation.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Local runs can select the complete app FFI explicitly when a global SDK
  // library would shadow it. Focused log-IO runs may also select the real-source
  // log probe. Full CI leaves this unset and requires the complete app library.
  final logLibrary = Platform.environment['TOXEE_TEST_LOG_LIBRARY'];
  if (logLibrary != null) Tim2ToxFfi.setLibraryPathOverride(logLibrary);
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  await testMain();
}
