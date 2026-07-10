// Open the first conversation, type into the composer so the send button
// appears, and leave it. Usage: dart run tool/mcp_test/ipad_type_in_chat.dart <ws> <convLabel>
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

late VmService vm;
late String iso;

Future<List<dynamic>> snap() async {
  final r = await vm.callServiceExtension('ext.mcp.toolkit.semantic_snapshot',
      isolateId: iso);
  return (r.json?['nodes'] as List?) ?? const [];
}

Future<void> tapRef(String ref) => vm.callServiceExtension(
    'ext.mcp.toolkit.tap_widget', isolateId: iso, args: {'ref': ref});

Future<bool> tapLabel(String sub) async {
  for (final n in await snap()) {
    if ('${n['label'] ?? ''}'.contains(sub)) {
      await tapRef(n['ref']);
      print('tapped "$sub"');
      return true;
    }
  }
  print('not found: $sub');
  return false;
}

Future<void> main(List<String> args) async {
  vm = await vmServiceConnectUri(args[0]);
  iso = (await vm.getVM()).isolates!.first.id!;
  await tapLabel(args.length > 1 ? args[1] : 'iPadUi');
  await Future<void>.delayed(const Duration(seconds: 2));
  // Find the composer text field and enter text.
  final nodes = await snap();
  Map<String, dynamic>? field;
  for (final n in nodes) {
    if (n['type'] == 'textField') {
      field = n as Map<String, dynamic>;
      break;
    }
  }
  if (field != null) {
    await tapRef(field['ref']);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await vm.callServiceExtension('ext.mcp.toolkit.enter_text',
        isolateId: iso, args: {'ref': field['ref'], 'text': 'hi'});
    print('entered text into ${field['bounds']}');
  } else {
    print('no textField found; labels=${nodes.map((n) => n['type']).toSet()}');
  }
  await Future<void>.delayed(const Duration(milliseconds: 600));
  await vm.dispose();
}
