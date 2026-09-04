// Print one instance's `l3_dump_state` as JSON (diagnostics for the real-UI
// harness; no product code). Usage:
//   dart run tool/mcp_test/dump_l3_state.dart <ws-uri> [key ...]
// With keys, only those top-level entries are printed.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dump_l3_state.dart <ws-uri> [key ...]');
    exit(64);
  }
  final vm = await vmServiceConnectUri(args.first);
  final isos = (await vm.getVM()).isolates ?? const <IsolateRef>[];
  final iso = isos
      .firstWhere((i) => (i.name ?? '').contains('main'), orElse: () => isos.first)
      .id!;
  final r = await vm.callServiceExtension(
    'ext.mcp.toolkit.l3_dump_state',
    isolateId: iso,
  );
  final json = r.json ?? <String, dynamic>{};
  final keys = args.sublist(1);
  final out = keys.isEmpty
      ? json
      : {for (final k in keys) k: json[k]};
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(out));
  await vm.dispose();
}
