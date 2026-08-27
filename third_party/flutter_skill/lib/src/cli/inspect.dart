import 'dart:io';
import '../drivers/flutter_driver.dart';

Future<void> runInspect(List<String> args) async {
  // No initial arg check, let resolveUri handle it
  // if (args.isEmpty) ...

  String uri;
  try {
    uri = await FlutterSkillClient.resolveUri(args);
  } catch (e) {
    print(e);
    exit(1);
  }

  final client = FlutterSkillClient(uri);

  try {
    await client.connect();
    final elements = await client.getInteractiveElements();

    // Print simplified tree for LLM consumption
    print('Interactive Elements:');
    if (elements.isEmpty) {
      print('(No interactive elements found)');
    } else {
      for (final e in elements) {
        _printElement(e);
      }
    }
  } catch (e) {
    print('Error: $e');
    exit(1);
  } finally {
    await client.disconnect();
  }
}

void _printElement(dynamic element, [String prefix = '']) {
  if (element is! Map) return;

  // Try to extract useful info
  final type = element['type'] ?? 'Widget';
  final key = element['key'];
  final text = element['text'];
  final tooltip = element['tooltip'];

  var buffer = StringBuffer();
  buffer.write(prefix);
  buffer.write('- **$type**');

  if (key != null) buffer.write(' [Key: "$key"]');
  if (text != null && text.toString().isNotEmpty)
    buffer.write(' [Text: "$text"]');
  if (tooltip != null) buffer.write(' [Tooltip: "$tooltip"]');

  print(buffer.toString());

  // Recursively print children if any
  if (element.containsKey('children') && element['children'] is List) {
    for (final child in element['children']) {
      _printElement(child, '$prefix  ');
    }
  }
}
