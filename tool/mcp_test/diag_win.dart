// One-shot Windows diag: connect to a running toxee VM service, dump home state,
// list on-screen keyed elements, and screenshot. Usage:
//   dart run tool/mcp_test/diag_win.dart <ws-uri>
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final ws = args[0];
  final vm = await vmServiceConnectUri(ws);
  final v = await vm.getVM();
  final isos = v.isolates ?? const <IsolateRef>[];
  final iso = isos
      .firstWhere((i) => (i.name ?? '').toLowerCase().contains('main'),
          orElse: () => isos.first)
      .id!;
  Future<Map<String, dynamic>> raw(String m, Map<String, Object?> p) async {
    final args = <String, String>{
      for (final e in p.entries)
        e.key: e.value is String ? e.value as String : jsonEncode(e.value),
    };
    final r = await vm.callServiceExtension(m, isolateId: iso, args: args);
    return r.json ?? <String, dynamic>{};
  }

  for (var i = 0; i < 80; i++) {
    final ii = await vm.getIsolate(iso);
    if ((ii.extensionRPCs ?? const <String>[])
        .contains('ext.mcp.toolkit.l3_dump_state')) break;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  // Poll for up to 75s to see if it connects / reaches Home / times out.
  for (var i = 0; i < 15; i++) {
    final d = await raw('ext.mcp.toolkit.l3_dump_state', {});
    stdout.writeln('[t=${i * 5}s] homeShellTab=${d['homeShellTab']} '
        'sessionReady=${d['sessionReady']} isConnected=${d['isConnected']} '
        'nickname=${d['nickname']}');
    if (d['homeShellTab'] != null && '${d['homeShellTab']}'.isNotEmpty) {
      stdout.writeln('REACHED HOME at t=${i * 5}s');
      break;
    }
    await Future<void>.delayed(const Duration(seconds: 5));
  }
  final d = await raw('ext.mcp.toolkit.l3_dump_state', {});
  final el = await raw('ext.flutter.flutter_skill.interactiveStructured', {});
  final data = el['data'];
  final elements = (data is Map ? data['elements'] : null) as List? ?? [];
  final keys = <String>[];
  for (final e in elements) {
    if (e is Map && e['key'] != null) keys.add('${e['key']}');
  }
  stdout.writeln('KEYS(${keys.length}): ${keys.toSet().take(60).join(", ")}');
  final shot = await raw('ext.flutter.flutter_skill.screenshot', {});
  final img = shot['image'] as String?;
  if (img != null && img.isNotEmpty) {
    await File(r'C:\toxee-win\diag_home.png').writeAsBytes(base64Decode(img));
    stdout.writeln('shot saved (${img.length} b64)');
  } else {
    stdout.writeln('no screenshot');
  }
  await vm.dispose();
}
