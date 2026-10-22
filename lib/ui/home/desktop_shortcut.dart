import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

SingleActivator desktopShortcut(LogicalKeyboardKey key, {bool? isMacOS}) {
  final mac = isMacOS ?? Platform.isMacOS;
  return SingleActivator(key, meta: mac, control: !mac);
}
