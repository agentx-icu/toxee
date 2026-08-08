import 'dart:convert';
import 'dart:io';

const qtoxHarnessOwner = 'toxee-qtox-external-peer-harness';
const qtoxHarnessSchemaVersion = 1;
const qtoxDefaultScreenshotName = 'qtox-sigusr1.png';

class QtoxHarnessException implements Exception {
  QtoxHarnessException(this.message);

  final String message;

  @override
  String toString() => 'QtoxHarnessException: $message';
}

Future<void> writeQtoxJson(String path, Map<String, Object?> value) async {
  await File(path).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    flush: true,
  );
}
