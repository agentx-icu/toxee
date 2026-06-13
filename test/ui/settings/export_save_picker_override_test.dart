import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugResetL3FilePickerOverridesForTests();
    debugSetL3TestSurfaceEnabledForTests(null);
  });

  test('L3 export save override short-circuits native picker', () async {
    debugSetL3TestSurfaceEnabledForTests(true);
    debugSetExportSaveFileOverridePathForTests('/tmp/l3-export.tox');

    var nativePickerCalls = 0;
    final resolvedPath = await runL3AwareExportSaveFilePicker(
      dialogTitle: 'Export Account',
      fileName: 'seeded_8895A8D6.tox',
      saveFile: (dialogTitle, fileName) async {
        nativePickerCalls += 1;
        return '/tmp/native-picker.tox';
      },
    );

    expect(resolvedPath, '/tmp/l3-export.tox');
    expect(nativePickerCalls, 0);
  });

  test('normal path still invokes native save picker', () async {
    debugSetL3TestSurfaceEnabledForTests(false);
    debugSetExportSaveFileOverridePathForTests('/tmp/l3-export.tox');

    var nativePickerCalls = 0;
    String? seenDialogTitle;
    String? seenFileName;
    final resolvedPath = await runL3AwareExportSaveFilePicker(
      dialogTitle: 'Export Account',
      fileName: 'seeded_8895A8D6.tox',
      saveFile: (dialogTitle, fileName) async {
        nativePickerCalls += 1;
        seenDialogTitle = dialogTitle;
        seenFileName = fileName;
        return '/tmp/native-picker.tox';
      },
    );

    expect(resolvedPath, '/tmp/native-picker.tox');
    expect(nativePickerCalls, 1);
    expect(seenDialogTitle, 'Export Account');
    expect(seenFileName, 'seeded_8895A8D6.tox');
  });

  test(
    'L3 account import override short-circuits native open picker',
    () async {
      debugSetL3TestSurfaceEnabledForTests(true);
      debugSetAccountImportPickFileOverridePathForTests('/tmp/l3-import.tox');

      var nativePickerCalls = 0;
      final resolvedPath = await runL3AwareAccountImportPicker(
        pickFile: () async {
          nativePickerCalls += 1;
          return '/tmp/native-import.tox';
        },
      );

      expect(resolvedPath, '/tmp/l3-import.tox');
      expect(nativePickerCalls, 0);
    },
  );

  test('normal account import path still invokes native open picker', () async {
    debugSetL3TestSurfaceEnabledForTests(false);
    debugSetAccountImportPickFileOverridePathForTests('/tmp/l3-import.tox');

    var nativePickerCalls = 0;
    final resolvedPath = await runL3AwareAccountImportPicker(
      pickFile: () async {
        nativePickerCalls += 1;
        return '/tmp/native-import.tox';
      },
    );

    expect(resolvedPath, '/tmp/native-import.tox');
    expect(nativePickerCalls, 1);
  });

  test('L3 attachment override short-circuits native open picker', () async {
    debugSetL3TestSurfaceEnabledForTests(true);
    debugSetAttachmentPickFileOverridePathForTests('/tmp/l3-attachment.png');

    var nativePickerCalls = 0;
    final resolvedPath = await runL3AwareAttachmentPicker(
      pickFile: () async {
        nativePickerCalls += 1;
        return '/tmp/native-attachment.png';
      },
    );

    expect(resolvedPath, '/tmp/l3-attachment.png');
    expect(nativePickerCalls, 0);
  });

  test('normal attachment path still invokes native open picker', () async {
    debugSetL3TestSurfaceEnabledForTests(false);
    debugSetAttachmentPickFileOverridePathForTests('/tmp/l3-attachment.png');

    var nativePickerCalls = 0;
    final resolvedPath = await runL3AwareAttachmentPicker(
      pickFile: () async {
        nativePickerCalls += 1;
        return '/tmp/native-attachment.png';
      },
    );

    expect(resolvedPath, '/tmp/native-attachment.png');
    expect(nativePickerCalls, 1);
  });
}
