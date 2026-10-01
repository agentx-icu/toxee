// The one place the account-file dialogs (.tox profile / .zip full backup)
// open the system picker.
//
// file_picker expresses `FileType.custom` + `allowedExtensions` through the
// platform's type registry. Android has no MIME type for `.tox`, so the
// plugin drops that extension ("FileUtils: Custom file type tox is
// unsupported and will be ignored"): with `['tox']` alone nothing is left and
// pickFiles throws `PlatformException(FilePicker, Unsupported filter…)` — the
// login page's "Restore from .tox file" could never open a picker on Android —
// and with `['tox', 'zip']` the dialog opens but every .tox file is greyed
// out. iOS derives a dynamic UTType from an unknown extension and the desktop
// dialogs filter on the raw extension, so only Android needs the fallback:
// open the picker on any file there and let the caller check the extension
// (each import path already refuses anything but .tox / .zip).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Picks one account file. [extensions] are lower-case without the dot.
/// Returns the picked path, or null when the user cancelled.
Future<String?> pickAccountImportFile(
  List<String> extensions, {
  @visibleForTesting bool? useUnfilteredPickerOverride,
}) async {
  final unfiltered =
      useUnfilteredPickerOverride ?? (!kIsWeb && Platform.isAndroid);
  final picked = await FilePicker.platform.pickFiles(
    type: unfiltered ? FileType.any : FileType.custom,
    allowedExtensions: unfiltered ? null : extensions,
  );
  return picked?.files.single.path;
}

/// Whether [path] carries one of [extensions] (case-insensitive). The
/// unfiltered Android picker makes this the only guard.
bool hasAccountImportExtension(String path, List<String> extensions) {
  final lower = path.toLowerCase();
  return extensions.any((e) => lower.endsWith('.$e'));
}
