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
  return MobileExportSaveResult(
    disposition: userSelectedPath == null
        ? MobileExportSaveDisposition.cancelled
        : MobileExportSaveDisposition.exported,
    internalFilePath: internalFilePath,
    userSelectedPath: userSelectedPath,
  );
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
