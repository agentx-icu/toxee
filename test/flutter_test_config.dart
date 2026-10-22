import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Plugin 19+ registers Dart platform implementations in the generated app
/// registrant. Unit tests do not run that registrant; their default target is
/// Android and the existing method-channel fakes exercise that implementation.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  await testMain();
}
