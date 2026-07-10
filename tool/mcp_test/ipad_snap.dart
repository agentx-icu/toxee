// Dump the current semantic tree (labels + bounds) of a running sim instance.
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
    final b = n['bounds'] as Map?;
    final label = '${n['label'] ?? ''}'.replaceAll('\n', ' ⏎ ');
    final bs = b == null
        ? ''
        : '[${b['left']?.round()},${b['top']?.round()} → ${b['right']?.round()},${b['bottom']?.round()}]';
    print('${n['ref']}  ${n['type']}  $bs  ${label.substring(0, label.length.clamp(0, 70))}');
  }
  await vm.dispose();
}
