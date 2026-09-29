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

  test(
    'Android (SAF): a save anywhere removes the staging copy even though the '
    'returned path is not real',
    () async {
      // file_picker on Android returns `<public Downloads>/<name>` whatever
      // folder / provider the user chose; the path need not exist.
      final internalFile = File('${tempDirectory.path}/staging.tox');
      await internalFile.writeAsBytes(const <int>[1, 2]);

      final result = await saveMobileExportCopy(
        internalFilePath: internalFile.path,
        dialogTitle: 'Export Account',
        fileName: 'alice.tox',
        pickerIsSaf: true,
        saveFile: ({
          required String dialogTitle,
          required String fileName,
          required Uint8List bytes,
        }) async =>
            '/storage/emulated/0/Download/does-not-exist/alice.tox',
      );

      expect(result.disposition, MobileExportSaveDisposition.exported);
      expect(await internalFile.exists(), isFalse);
    },
  );

  test(
    'Android (SAF): a cancelled save removes the unreachable staging copy',
    () async {
      final internalFile = File('${tempDirectory.path}/kept.tox');
      await internalFile.writeAsBytes(const <int>[3]);

      final result = await saveMobileExportCopy(
        internalFilePath: internalFile.path,
        dialogTitle: 'Export Account',
        fileName: 'kept.tox',
        pickerIsSaf: true,
        stagingVisibleInFiles: false,
        saveFile: ({
          required String dialogTitle,
          required String fileName,
          required Uint8List bytes,
        }) async =>
            null,
      );

      expect(result.disposition, MobileExportSaveDisposition.cancelled);
      expect(result.cancelledCopyInFiles, isFalse);
      expect(await internalFile.exists(), isFalse);
    },
  );

  test('iOS: a cancelled save keeps the Files-visible copy and says so',
      () async {
    final internalFile = File('${tempDirectory.path}/visible.tox');
    await internalFile.writeAsBytes(const <int>[5]);

    final result = await saveMobileExportCopy(
      internalFilePath: internalFile.path,
      dialogTitle: 'Export Account',
      fileName: 'visible.tox',
      pickerIsSaf: false,
      stagingVisibleInFiles: true,
      saveFile: ({
        required String dialogTitle,
        required String fileName,
        required Uint8List bytes,
      }) async =>
          null,
    );

    expect(result.disposition, MobileExportSaveDisposition.cancelled);
    expect(result.cancelledCopyInFiles, isTrue);
    expect(await internalFile.exists(), isTrue);
  });

  group('iOS save-sheet source copy (<Documents>/<fileName>)', () {
    late String source;

    // What file_picker does between our two calls: delete whatever is at the
    // path, then write the new export there.
    Future<void> pluginWritesSource(List<int> bytes) async {
      final f = File(source);
      if (await f.exists()) await f.delete();
      await f.writeAsBytes(bytes);
    }

    setUp(() {
      source = '${tempDirectory.path}/alice_1234.tox';
    });

    test('removed after a save elsewhere', () async {
      final aside = await moveAsideBeforeSaveSheet(source);
      expect(aside, isNull);
      await pluginWritesSource(const [7]);
      await restoreAfterSaveSheet(
        sourceCopyPath: source,
        asidePath: aside,
        userSelectedPath:
            '/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/alice_1234.tox',
      );
      expect(await File(source).exists(), isFalse);
    });

    test('removed after a cancelled sheet', () async {
      await pluginWritesSource(const [7]);
      await restoreAfterSaveSheet(
        sourceCopyPath: source,
        asidePath: null,
        userSelectedPath: null,
      );
      expect(await File(source).exists(), isFalse);
    });

    test('kept when the user saved onto that very file', () async {
      await pluginWritesSource(const [7]);
      await restoreAfterSaveSheet(
        sourceCopyPath: source,
        asidePath: null,
        userSelectedPath: source,
      );
      expect(await File(source).readAsBytes(), const [7]);
    });

    test('an earlier backup at that path survives a cancelled export',
        () async {
      await File(source).writeAsBytes(const [1, 1]); // the earlier backup
      final aside = await moveAsideBeforeSaveSheet(source);
      expect(aside, isNotNull);
      await pluginWritesSource(const [9, 9]); // the new export
      await restoreAfterSaveSheet(
        sourceCopyPath: source,
        asidePath: aside,
        userSelectedPath: null,
      );
      expect(await File(source).readAsBytes(), const [1, 1]);
      expect(await File(aside!).exists(), isFalse);
    });

    test('an earlier backup survives a save elsewhere too', () async {
      await File(source).writeAsBytes(const [1, 1]);
      final aside = await moveAsideBeforeSaveSheet(source);
      await pluginWritesSource(const [9, 9]);
      await restoreAfterSaveSheet(
        sourceCopyPath: source,
        asidePath: aside,
        userSelectedPath: '/elsewhere/alice_1234.tox',
      );
      expect(await File(source).readAsBytes(), const [1, 1]);
    });

    test('saving onto the earlier backup replaces it (the user chose to)',
        () async {
      await File(source).writeAsBytes(const [1, 1]);
      final aside = await moveAsideBeforeSaveSheet(source);
      await pluginWritesSource(const [9, 9]);
      await restoreAfterSaveSheet(
        sourceCopyPath: source,
        asidePath: aside,
        userSelectedPath: source,
      );
      expect(await File(source).readAsBytes(), const [9, 9]);
      expect(await File(aside!).exists(), isFalse);
    });

    test('the /private alias of the same file counts as the same file',
        () async {
      // iOS reports sandbox paths both with and without /private; the
      // decision must not depend on being able to stat the picked path.
      await pluginWritesSource(const [3]);
      final plain = source.startsWith('/private/')
          ? source.substring('/private'.length)
          : source;
      await restoreAfterSaveSheet(
        sourceCopyPath: plain,
        asidePath: null,
        userSelectedPath: '/private$plain',
      );
      expect(await File(source).exists(), isTrue);
    });

    test('a leftover from an interrupted export is never overwritten',
        () async {
      // An earlier sheet was interrupted after the move-aside: the backup is
      // under `.toxee-previous` and the plugin's copy is at the path.
      await File('$source.toxee-previous').writeAsBytes(const [1, 1]);
      await File(source).writeAsBytes(const [5]);
      final aside = await moveAsideBeforeSaveSheet(source);
      expect(aside, '$source.toxee-previous-2');
      expect(await File('$source.toxee-previous').readAsBytes(), const [1, 1]);
    });

    test('a same-named FOLDER is moved aside and put back, never deleted',
        () async {
      await Directory(source).create();
      await File('$source/inside.txt').writeAsString('keep me');
      final aside = await moveAsideBeforeSaveSheet(source);
      expect(aside, isNotNull);
      await pluginWritesSource(const [9]);
      await restoreAfterSaveSheet(
        sourceCopyPath: source,
        asidePath: aside,
        userSelectedPath: null,
      );
      expect(await File('$source/inside.txt').readAsString(), 'keep me');
    });
  });

  test(
    'iOS: a save to a provider path we cannot stat removes the staging copy',
    () async {
      final internalFile = File('${tempDirectory.path}/staging_ios.tox');
      await internalFile.writeAsBytes(const <int>[4]);

      final result = await saveMobileExportCopy(
        internalFilePath: internalFile.path,
        dialogTitle: 'Export Account',
        fileName: 'staging_ios.tox',
        pickerIsSaf: false,
        stagingVisibleInFiles: true,
        saveFile: ({
          required String dialogTitle,
          required String fileName,
          required Uint8List bytes,
        }) async =>
            '/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/staging_ios.tox',
      );

      expect(result.disposition, MobileExportSaveDisposition.exported);
      expect(await internalFile.exists(), isFalse);
    },
  );

  test('iOS: saving onto the staging file itself keeps it', () async {
    final internalFile = File('${tempDirectory.path}/onto.tox');
    await internalFile.writeAsBytes(const <int>[6]);

    await saveMobileExportCopy(
      internalFilePath: internalFile.path,
      dialogTitle: 'Export Account',
      fileName: 'onto.tox',
      pickerIsSaf: false,
      stagingVisibleInFiles: true,
      saveFile: ({
        required String dialogTitle,
        required String fileName,
        required Uint8List bytes,
      }) async =>
          internalFile.path,
    );

    expect(await internalFile.readAsBytes(), const <int>[6]);
  });
}
