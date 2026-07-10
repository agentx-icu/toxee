// Close any dialog, go to Chats, find + tap the brightness toggle (the
// unlabeled IconButton left of the "+" in the conversation app bar).
// Usage: dart run tool/mcp_test/ipad_toggle_theme.dart <ws_uri>
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
  await tapLabel('Chats');
  await Future<void>.delayed(const Duration(seconds: 1));
  // The brightness toggle: a tappable/button with empty label near the top,
  // to the LEFT of the "+" (which is the right-most). Pick the empty-label
  // top-row button that is NOT the right-most.
  final nodes = await snap();
  final candidates = <Map<String, dynamic>>[];
  for (final n in nodes) {
    final b = n['bounds'] as Map?;
    if (b == null) continue;
    final top = (b['top'] as num).toDouble();
    final right = (b['right'] as num).toDouble();
    final label = '${n['label'] ?? ''}';
    if ((n['type'] == 'tappable' || n['type'] == 'button') &&
        label.isEmpty &&
        top < 120 &&
        right > 300) {
      candidates.add(n as Map<String, dynamic>);
    }
  }
  candidates.sort((a, b) =>
      ((a['bounds']['right'] as num)).compareTo((b['bounds']['right'] as num)));
  print('top-right empty buttons: ${candidates.map((c) => c['bounds']).toList()}');
  if (candidates.length >= 2) {
    // second-from-right = brightness toggle (right-most = "+")
    final toggle = candidates[candidates.length - 2];
    await tapRef(toggle['ref']);
    print('tapped brightness toggle at ${toggle['bounds']}');
  } else if (candidates.isNotEmpty) {
    await tapRef(candidates.first['ref']);
    print('tapped only candidate at ${candidates.first['bounds']}');
  } else {
    print('no toggle candidate found');
  }
  await vm.dispose();
}
