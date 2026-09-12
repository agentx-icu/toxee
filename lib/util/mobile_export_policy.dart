import 'dart:io';
import 'dart:typed_data';

typedef MobileExportSaveFile =
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
      required Uint8List bytes,
    });

typedef SaveMobileExportCopyFn =
    Future<MobileExportSaveResult> Function({
      required String internalFilePath,
      required String dialogTitle,
      required String fileName,
      required MobileExportSaveFile saveFile,
    });

typedef CreateAndSaveMobileExportCopyFn =
    Future<MobileExportSaveResult> Function({
      required Future<String> Function() createInternalExport,
      required String dialogTitle,
      required String fileName,
      required MobileExportSaveFile saveFile,
    });

enum MobileExportSaveDisposition { exported, cancelled }

class MobileExportSaveResult {
  const MobileExportSaveResult({
    required this.disposition,
    required this.internalFilePath,
    required this.userSelectedPath,
  });

  final MobileExportSaveDisposition disposition;
  final String internalFilePath;
  final String? userSelectedPath;

  String get cancellationNotice =>
      'Save cancelled. A private in-app copy was kept at: $internalFilePath';
}

bool isDesktopExportPlatform({bool? override}) {
  return override ??
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
}

bool shouldContinueAccountExport({
  required bool isDesktopPlatform,
  required String? outputPath,
}) => !isDesktopPlatform || outputPath != null;

String buildAccountExportFileName({
  required String toxId,
  required String nickname,
  required String suffix,
}) {
  final toxIdPrefix = toxId.length >= 8 ? toxId.substring(0, 8) : toxId;
  final safeNickname = (nickname.isEmpty ? 'account' : nickname).replaceAll(
    RegExp(r'[<>:"/\\|?*]'),
    '_',
  );
  return '${safeNickname}_$toxIdPrefix$suffix';
}

String buildFullBackupExportFileName({DateTime? timestamp}) {
  final value = (timestamp ?? DateTime.now()).millisecondsSinceEpoch;
  return 'toxee_full_backup_$value.zip';
}

Future<MobileExportSaveResult> saveMobileExportCopy({
  required String internalFilePath,
  required String dialogTitle,
  required String fileName,
  required MobileExportSaveFile saveFile,
}) async {
  final bytes = await File(internalFilePath).readAsBytes();
  final userSelectedPath = await saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: bytes,
  );
  if (userSelectedPath != null &&
      !await _isSameFile(internalFilePath, userSelectedPath)) {
    // The internal copy was STAGING for the save sheet, and the user now has
    // their own. Keeping it left a second copy of the account's Tox profile —
    // its private key — inside app storage indefinitely, and on iOS that
    // directory is exposed by `UIFileSharingEnabled`. Nothing reads it after
    // this point, so remove it.
    //
    // UNLESS THE USER SAVED OVER IT. The internal copy lives under
    // `AppPaths.getDownloadsPath()`, which on iOS is the same Files-visible
    // `toxee/Downloads` directory the save sheet can browse to — so the user can
    // pick that directory and that filename, the picker replaces the staging
    // file, and the "staging" path now names the backup they just kept.
    // Deleting it then destroys the backup while reporting success.
    //
    // A CANCELLED save also keeps it (see
    // [MobileExportSaveResult.cancellationNotice]): the user asked for a backup
    // and that copy is the only one that exists.
    await _deleteQuietly(internalFilePath);
  }
  return MobileExportSaveResult(
    disposition: userSelectedPath == null
        ? MobileExportSaveDisposition.cancelled
        : MobileExportSaveDisposition.exported,
    internalFilePath: internalFilePath,
    userSelectedPath: userSelectedPath,
  );
}

/// Whether two paths name the same file on disk.
///
/// String comparison is not enough: the picker may return a path that differs
/// textually (a symlinked container, `/private` on iOS/macOS, a normalised
/// form) while resolving to the staging file. Resolving both through
/// `resolveSymbolicLinks` catches those aliases.
///
/// Errs on the side of "same file" when it cannot tell, because the cost of a
/// false negative is deleting the user's only backup, while the cost of a false
/// positive is a leftover staging file.
Future<bool> _isSameFile(String a, String b) async {
  if (a == b) return true;
  try {
    final resolvedA = await File(a).resolveSymbolicLinks();
    final resolvedB = await File(b).resolveSymbolicLinks();
    return resolvedA == resolvedB;
  } catch (_) {
    // One of them may not exist (a picker path we cannot stat, a SAF/content
    // URI on Android). Undecidable, so keep the staging file.
    return true;
  }
}

/// Remove a staging file, ignoring failures.
///
/// The export already succeeded from the user's point of view; failing it now
/// over a leftover temp file would be worse than the leftover.
Future<void> _deleteQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Best effort.
  }
}

Future<MobileExportSaveResult> createAndSaveMobileExportCopy({
  required Future<String> Function() createInternalExport,
  required String dialogTitle,
  required String fileName,
  required MobileExportSaveFile saveFile,
}) async {
  final internalFilePath = await createInternalExport();
  return saveMobileExportCopy(
    internalFilePath: internalFilePath,
    dialogTitle: dialogTitle,
    fileName: fileName,
    saveFile: saveFile,
  );
}
