// Tap the right-most empty-label top button (the "+" in the app bar).
// Usage: dart run tool/mcp_test/ipad_tap_plus.dart <ws_uri>
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

void main(List<String> a) async {
  final vm = await vmServiceConnectUri(a[0]);
  final iso = (await vm.getVM()).isolates!.first.id!;
  final r = await vm.callServiceExtension('ext.mcp.toolkit.semantic_snapshot',
      isolateId: iso);
  final nodes = (r.json?['nodes'] as List?) ?? const [];
  Map? best;
  double mr = 0;
  for (final n in nodes) {
    final b = n['bounds'] as Map?;
    if (b == null) continue;
    final top = (b['top'] as num).toDouble();
    final right = (b['right'] as num).toDouble();
    if ((n['type'] == 'tappable' || n['type'] == 'button') &&
        '${n['label'] ?? ''}'.isEmpty &&
        top < 120 &&
        right > 760 &&
        right > mr) {
      mr = right;
      best = n;
    }
  }
  if (best != null) {
    await vm.callServiceExtension('ext.mcp.toolkit.tap_widget',
        isolateId: iso, args: {'ref': best['ref']});
    print('tapped + at ${best['bounds']}');
  } else {
    print('no + found');
  }
  await vm.dispose();
}
