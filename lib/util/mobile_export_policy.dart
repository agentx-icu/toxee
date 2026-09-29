import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    this.cancelledCopyInFiles = false,
  });

  final MobileExportSaveDisposition disposition;
  final String internalFilePath;
  final String? userSelectedPath;

  /// Cancelled, and the staging copy was kept where the user can reach it
  /// (iOS: Files › Toxee › Downloads). The UI says so instead of a bare
  /// "Cancelled".
  final bool cancelledCopyInFiles;

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
  @visibleForTesting bool? pickerIsSaf,
  @visibleForTesting bool? stagingVisibleInFiles,
}) async {
  final bytes = await File(internalFilePath).readAsBytes();
  final userSelectedPath = await saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: bytes,
  );
  // Android's save sheet is the Storage Access Framework: it writes through a
  // content:// URI and file_picker then returns a path it MADE UP
  // (`<public Downloads>/<display name>`, whatever folder or provider the user
  // picked). That path usually doesn't exist, so the same-file check below
  // could not resolve it and kept the staging copy — a second copy of the
  // private key — after every save outside Downloads. SAF cannot write into
  // the app's private storage where the staging copy lives, so on Android a
  // successful save can never BE the staging file.
  final safSave = pickerIsSaf ?? Platform.isAndroid;
  // iOS: the export sheet returns the destination's plain path, usually in a
  // file provider or another container we cannot stat, where [_isSameFile]
  // answers "same" (keep) — so every such save kept the Files-visible
  // staging copy. Saving onto the staging file itself yields a path in our
  // own container, which plain path equality recognises.
  final visibleInFiles = stagingVisibleInFiles ?? Platform.isIOS;
  final savedOntoStaging = userSelectedPath != null &&
      (visibleInFiles
          ? _samePath(internalFilePath, userSelectedPath)
          : await _isSameFile(internalFilePath, userSelectedPath));
  if (userSelectedPath != null && (safSave || !savedOntoStaging)) {
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
    // A CANCELLED save keeps it where the user can reach it (below): the user
    // asked for a backup and that copy is the only one they can get to.
    await _deleteQuietly(internalFilePath);
  }
  // Cancelled. On iOS the staging copy is in the Files-visible
  // `Documents/Downloads`: keep it and tell the user where it is. On Android
  // it is in app-private storage no one can open — keeping it only leaves
  // another copy of the private key behind (the account itself is not lost
  // by a cancel), so remove it.
  var cancelledCopyInFiles = false;
  if (userSelectedPath == null) {
    if (safSave) {
      await _deleteQuietly(internalFilePath);
    } else {
      cancelledCopyInFiles = visibleInFiles;
    }
  }
  return MobileExportSaveResult(
    disposition: userSelectedPath == null
        ? MobileExportSaveDisposition.cancelled
        : MobileExportSaveDisposition.exported,
    internalFilePath: internalFilePath,
    userSelectedPath: userSelectedPath,
    cancelledCopyInFiles: cancelledCopyInFiles,
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

/// The production save sheet: `FilePicker.saveFile` plus cleanup of what the
/// plugin itself leaves behind, and an honest result on Android.
///
/// iOS: file_picker writes the bytes to `<Documents>/<fileName>` and hands
/// THAT file to the export sheet (FilePickerPlugin.m `saveFileWithName`), and
/// never removes it — saved, cancelled or failed. With `UIFileSharingEnabled`
/// the Documents root is visible in the Files app, so every export left a copy
/// of the account file (the private key) there. It is removed afterwards. A
/// file already at that path (e.g. a backup the user saved into Toxee's own
/// Files folder earlier) would be DELETED by the plugin before it writes, so it
/// is moved aside first and put back afterwards — unless the user just saved
/// onto that very path, choosing to replace it.
///
/// Android: the Storage Access Framework writes through a content:// URI and
/// file_picker returns a path it made up (`<public Downloads>/<name>`,
/// whatever folder or provider the user picked; FilePickerDelegate.java). Only
/// the name in it is real, so only the name is returned — it is what the
/// success message shows.
Future<String?> saveWithSystemSaveSheet({
  required String dialogTitle,
  required String fileName,
  required Uint8List bytes,
}) async {
  String? sourceCopy;
  String? aside;
  if (Platform.isIOS) {
    // No try/catch on purpose: if an existing file there cannot be moved
    // aside, the plugin would delete it — fail the export instead (callers
    // report it as an export error).
    final documents = await getApplicationDocumentsDirectory();
    sourceCopy = p.join(documents.path, fileName);
    aside = await moveAsideBeforeSaveSheet(sourceCopy);
  }
  String? picked;
  try {
    picked = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
    );
  } finally {
    // Also on a failed save: the plugin may have written the copy already.
    if (sourceCopy != null) {
      await restoreAfterSaveSheet(
        sourceCopyPath: sourceCopy,
        asidePath: aside,
        userSelectedPath: picked,
      );
    }
  }
  if (Platform.isAndroid && picked != null) return p.basename(picked);
  return picked;
}

/// Moves whatever is at [path] — a file, or a folder the user named that way
/// — out of the save sheet's way (the plugin deletes any object there);
/// returns where it went, or null if nothing was there. The name stays
/// visible in Files, so a crash mid-sheet can't hide it, and is never an
/// existing one: a leftover from an interrupted earlier export must not be
/// overwritten (rename replaces its destination).
@visibleForTesting
Future<String?> moveAsideBeforeSaveSheet(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return null;
  var aside = '$path.toxee-previous';
  for (
    var n = 2;
    await FileSystemEntity.type(aside, followLinks: false) !=
        FileSystemEntityType.notFound;
    n++
  ) {
    aside = '$path.toxee-previous-$n';
  }
  await _entity(path, type).rename(aside);
  return aside;
}

FileSystemEntity _entity(String path, FileSystemEntityType type) =>
    switch (type) {
      FileSystemEntityType.directory => Directory(path),
      FileSystemEntityType.link => Link(path),
      _ => File(path),
    };

/// After the save sheet: deletes its source copy at [sourceCopyPath] unless
/// the user saved onto that very file, and puts a moved-aside file
/// ([asidePath]) back — or drops it when the user just replaced it.
@visibleForTesting
Future<void> restoreAfterSaveSheet({
  required String sourceCopyPath,
  required String? asidePath,
  required String? userSelectedPath,
}) async {
  final savedOnto =
      userSelectedPath != null && _samePath(sourceCopyPath, userSelectedPath);
  if (!savedOnto) await _deleteQuietly(sourceCopyPath);
  if (asidePath == null) return;
  final asideType = await FileSystemEntity.type(asidePath, followLinks: false);
  if (savedOnto) {
    // The user replaced that file with the new export. (Never delete a
    // moved-aside folder; it just keeps its `.toxee-previous` name.)
    if (asideType == FileSystemEntityType.file) await _deleteQuietly(asidePath);
    return;
  }
  try {
    await _entity(asidePath, asideType).rename(sourceCopyPath);
  } catch (_) {
    // Left under its visible `.toxee-previous` name rather than lost.
  }
}

/// Path equality for the iOS sandbox, where the same file shows up with and
/// without the `/private` prefix. Unlike [_isSameFile] this does not need to
/// stat [b]: the picked destination is usually in another app's container or
/// a file provider we can't resolve, and "can't tell" must not mean "same"
/// here — that would keep the private-key copy every time.
bool _samePath(String a, String b) {
  String norm(String path) {
    final n = p.normalize(path);
    return n.startsWith('/private/') ? n.substring('/private'.length) : n;
  }

  return norm(a) == norm(b);
}
