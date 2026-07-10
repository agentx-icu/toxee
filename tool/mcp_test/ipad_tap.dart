// Tap a widget by label substring on a running sim instance.
// Usage: dart run tool/mcp_test/ipad_tap.dart <ws_uri> <labelSubstr>
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final vm = await vmServiceConnectUri(args[0]);
  final iso = (await vm.getVM()).isolates!.first.id!;
  final r = await vm.callServiceExtension('ext.mcp.toolkit.semantic_snapshot',
      isolateId: iso);
  final nodes = (r.json?['nodes'] as List?) ?? const [];
  for (final n in nodes) {
    if ('${n['label'] ?? ''}'.contains(args[1])) {
      await vm.callServiceExtension('ext.mcp.toolkit.tap_widget',
          isolateId: iso, args: {'ref': n['ref']});
      print('tapped "${n['label']}"');
      await vm.dispose();
      return;
    }
  }
  print('not found: ${nodes.map((n) => n['label']).where((l) => '$l'.isNotEmpty).toList()}');
  await vm.dispose();
}
