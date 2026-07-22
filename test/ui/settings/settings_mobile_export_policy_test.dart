import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/mobile_export_policy.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'toxee_mobile_export_policy_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'mobile export continues with the default path when no path was picked',
    () {
      expect(
        shouldContinueAccountExport(isDesktopPlatform: false, outputPath: null),
        isTrue,
      );
    },
  );

  test('desktop export stops when the save dialog is cancelled', () {
    expect(
      shouldContinueAccountExport(isDesktopPlatform: true, outputPath: null),
      isFalse,
    );
  });

  test('desktop export continues when the save dialog returns a path', () {
    expect(
      shouldContinueAccountExport(
        isDesktopPlatform: true,
        outputPath: '/tmp/account.tox',
      ),
      isTrue,
    );
  });

  test('mobile save transfers internal export bytes to the document picker',
      () async {
    final internalFile = File('${tempDirectory.path}/account.tox');
    await internalFile.writeAsBytes(const <int>[1, 3, 3, 7]);
    String? seenDialogTitle;
    String? seenFileName;
    Uint8List? pickerBytes;

    final result = await saveMobileExportCopy(
      internalFilePath: internalFile.path,
      dialogTitle: 'Export Account',
      fileName: 'alice.tox',
      saveFile: ({
        required String dialogTitle,
        required String fileName,
        required Uint8List bytes,
      }) async {
        seenDialogTitle = dialogTitle;
        seenFileName = fileName;
        pickerBytes = bytes;
        return '/user-visible/alice.tox';
      },
    );

    expect(result.disposition, MobileExportSaveDisposition.exported);
    expect(result.userSelectedPath, '/user-visible/alice.tox');
    expect(result.internalFilePath, internalFile.path);
    expect(seenDialogTitle, 'Export Account');
    expect(seenFileName, 'alice.tox');
    expect(pickerBytes, Uint8List.fromList(const <int>[1, 3, 3, 7]));
  });

  test('mobile picker cancellation keeps and identifies the private copy',
      () async {
    final internalFile = File('${tempDirectory.path}/backup.zip');
    await internalFile.writeAsBytes(const <int>[9, 8, 7]);

    final result = await saveMobileExportCopy(
      internalFilePath: internalFile.path,
      dialogTitle: 'Export Account',
      fileName: 'backup.zip',
      saveFile: ({
        required String dialogTitle,
        required String fileName,
        required Uint8List bytes,
      }) async =>
          null,
    );

    expect(result.disposition, MobileExportSaveDisposition.cancelled);
    expect(result.userSelectedPath, isNull);
    expect(await internalFile.exists(), isTrue);
    expect(await internalFile.readAsBytes(), const <int>[9, 8, 7]);
    expect(result.cancellationNotice, contains('private in-app copy'));
    expect(result.cancellationNotice, contains(internalFile.path));
  });

  test('mobile export creates its internal file before opening the picker',
      () async {
    final internalFile = File('${tempDirectory.path}/ordered.tox');
    var createCompleted = false;
    var pickerObservedCompletedExport = false;

    final result = await createAndSaveMobileExportCopy(
      createInternalExport: () async {
        await internalFile.writeAsBytes(const <int>[4, 2]);
        createCompleted = true;
        return internalFile.path;
      },
      dialogTitle: 'Export Account',
      fileName: 'ordered.tox',
      saveFile: ({
        required String dialogTitle,
        required String fileName,
        required Uint8List bytes,
      }) async {
        pickerObservedCompletedExport =
            createCompleted && await internalFile.exists();
        expect(bytes, const <int>[4, 2]);
        return '/user-visible/ordered.tox';
      },
    );

    expect(pickerObservedCompletedExport, isTrue);
    expect(result.disposition, MobileExportSaveDisposition.exported);
  });

  test('safe export file names preserve nickname and tox prefix', () {
    expect(
      buildAccountExportFileName(
        toxId: '1234567890abcdef',
        nickname: 'Al/ice:*',
        suffix: '.tox',
      ),
      'Al_ice___12345678.tox',
    );
  });
}
