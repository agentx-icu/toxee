// Android has no MIME type for .tox, so the account-file picker must not use
// file_picker's extension filter there (it throws with ['tox'] and greys
// .tox files out with ['tox','zip']); everywhere else the native filter stays.

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/account_import_file_picker.dart';

class _RecordingPicker extends FilePicker {
  FileType? type;
  List<String>? extensions;
  String? path;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    this.type = type;
    extensions = allowedExtensions;
    final p = path;
    if (p == null) return null;
    return FilePickerResult([PlatformFile(name: p, path: p, size: 0)]);
  }
}

void main() {
  late _RecordingPicker picker;
  setUp(() {
    picker = _RecordingPicker();
    FilePicker.platform = picker;
  });

  test('Android opens an unfiltered picker and hands back the path', () async {
    picker.path = '/x/account.tox';
    final path = await pickAccountImportFile(const [
      'tox',
      'zip',
    ], useUnfilteredPickerOverride: true);
    expect(path, '/x/account.tox');
    expect(picker.type, FileType.any);
    expect(picker.extensions, isNull);
  });

  test('other platforms keep the native extension filter', () async {
    picker.path = '/x/backup.zip';
    await pickAccountImportFile(const [
      'tox',
      'zip',
    ], useUnfilteredPickerOverride: false);
    expect(picker.type, FileType.custom);
    expect(picker.extensions, ['tox', 'zip']);
  });

  test('cancel is null; the extension guard is case-insensitive', () async {
    expect(await pickAccountImportFile(const ['tox']), isNull);
    expect(hasAccountImportExtension('/a/B.TOX', const ['tox', 'zip']), isTrue);
    expect(
      hasAccountImportExtension('/a/b.txt', const ['tox', 'zip']),
      isFalse,
    );
  });
}
