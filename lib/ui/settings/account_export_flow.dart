import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../util/mobile_export_policy.dart';
import '../testing/l3_debug_tools.dart';

/// Produces the export file. [filePath] is the destination the user picked on
/// desktop; on mobile it is omitted and the exporter writes an internal copy
/// that the flow then offers to save.
typedef AccountExportFn = Future<String> Function({String? filePath});

/// Where the export ended up, plus the mobile save disposition so the caller
/// can distinguish "saved" from "cancelled, internal copy kept".
final class AccountExportFlowResult {
  const AccountExportFlowResult({
    required this.filePath,
    required this.mobileSaveResult,
  });

  final String filePath;
  final MobileExportSaveResult? mobileSaveResult;
}

/// The desktop-picker / mobile-share dance shared by the `.tox` and full-backup
/// export actions.
///
/// Extracted because `SettingsPage._exportAccount` and `_exportFullBackup` each
/// carried their own copy of these ~45 lines, differing only in which exporter
/// they call — so a fix to one (or a new platform branch) had to be remembered
/// twice.
///
/// Takes no `BuildContext`: everything here is file-picker and filesystem work.
/// The caller owns the snackbars, the password gate, and its own `mounted`
/// checks, which keeps the async-gap rules where the State can see them.
///
/// Returns null when the user cancelled the desktop save dialog — nothing was
/// written and the caller should stay silent.
Future<AccountExportFlowResult?> runAccountExportFlow({
  required String dialogTitle,
  required String defaultFileName,
  required AccountExportFn export,
}) async {
  final isDesktopPlatform = isDesktopExportPlatform();

  String? outputPath;
  if (isDesktopPlatform) {
    outputPath = await runL3AwareExportSaveFilePicker(
      dialogTitle: dialogTitle,
      fileName: defaultFileName,
      saveFile: (title, fileName) =>
          FilePicker.platform.saveFile(dialogTitle: title, fileName: fileName),
    );
  }
  if (!shouldContinueAccountExport(
    isDesktopPlatform: isDesktopPlatform,
    outputPath: outputPath,
  )) {
    return null;
  }

  if (isDesktopPlatform) {
    return AccountExportFlowResult(
      filePath: await export(filePath: outputPath),
      mobileSaveResult: null,
    );
  }

  // Mobile: write an internal copy first, then hand its bytes to the system
  // save sheet. A cancelled sheet still leaves that internal copy — see
  // `MobileExportSaveResult.cancellationNotice`.
  final mobileSaveResult = await createAndSaveMobileExportCopy(
    createInternalExport: () => export(),
    dialogTitle: dialogTitle,
    fileName: defaultFileName,
    saveFile:
        ({
          required String dialogTitle,
          required String fileName,
          required Uint8List bytes,
        }) => FilePicker.platform.saveFile(
          dialogTitle: dialogTitle,
          fileName: fileName,
          bytes: bytes,
        ),
  );
  return AccountExportFlowResult(
    filePath:
        mobileSaveResult.userSelectedPath ?? mobileSaveResult.internalFilePath,
    mobileSaveResult: mobileSaveResult,
  );
}
