// Navigate to Contacts, open the "+" menu -> Add Contact, then dump the
// dialog's semantic tree with bounds. Diagnoses AppDialog layout on a sim.
// Usage: dart run tool/mcp_test/ipad_open_dialog.dart <ws_uri>
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
    'ext.mcp.toolkit.tap_widget',
    isolateId: iso,
    args: {'ref': ref});

Future<bool> tapLabel(String sub) async {
  final nodes = await snap();
  for (final n in nodes) {
    if ('${n['label'] ?? ''}'.contains(sub)) {
      await tapRef(n['ref']);
      print('tapped "$sub"');
      return true;
    }
  }
  return false;
}

void dump(List<dynamic> nodes) {
  for (final n in nodes) {
    final b = n['bounds'] as Map?;
    final bs = b == null
        ? ''
        : '[${b['left']?.round()},${b['top']?.round()}→${b['right']?.round()},${b['bottom']?.round()}]';
    final label = '${n['label'] ?? ''}'.replaceAll('\n', '⏎').trim();
    print('${n['ref']} ${n['type']} $bs ${label.substring(0, label.length.clamp(0, 60))}');
  }
}

Future<void> main(List<String> args) async {
  vm = await vmServiceConnectUri(args[0]);
  iso = (await vm.getVM()).isolates!.first.id!;
  await tapLabel('Contacts');
  await Future<void>.delayed(const Duration(seconds: 2));
  // "+" button: a small tappable near the top-right with no label.
  var nodes = await snap();
  Map<String, dynamic>? plus;
  double maxRight = 0;
  for (final n in nodes) {
    final b = n['bounds'] as Map?;
    if (b == null) continue;
    final right = (b['right'] as num).toDouble();
    final top = (b['top'] as num).toDouble();
    final label = '${n['label'] ?? ''}';
    if ((n['type'] == 'tappable' || n['type'] == 'button') &&
        label.isEmpty &&
        top < 120 &&
        right > 700 &&
        right > maxRight) {
      maxRight = right;
      plus = n as Map<String, dynamic>;
    }
  }
  if (plus != null) {
    await tapRef(plus['ref']);
    print('tapped + at ${plus['bounds']}');
    await Future<void>.delayed(const Duration(seconds: 1));
  } else {
    print('+ not found');
  }
  await tapLabel('Add Contact');
  await Future<void>.delayed(const Duration(seconds: 2));
  print('=== ADD CONTACT DIALOG TREE ===');
  dump(await snap());
  await vm.dispose();
}
