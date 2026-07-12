// Minimal generic prober: call ONE service extension on a running toxee
// debug instance and print the full JSON response. For interactive
// diagnosis of the l3_* / flutter_skill surfaces without writing a bespoke
// driver per question.
//
//   dart run tool/mcp_test/l3_call.dart <ws_uri> <method> [key=value ...]
//
// <method> may be a bare l3 name (l3_dump_state) — the ext.mcp.toolkit.
// prefix is added — or a fully qualified extension name.
// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:convert';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<int> main(List<String> args) async {
  if (args.length < 2) {
    print('usage: l3_call.dart <ws_uri> <method> [key=value ...]');
    return 64;
  }
  final wsUri = args[0];
  var method = args[1];
  if (!method.contains('.')) {
    method = 'ext.mcp.toolkit.$method';
  }
  final params = <String, String>{};
  for (final kv in args.skip(2)) {
    final i = kv.indexOf('=');
    if (i <= 0) {
      print('bad arg (want key=value): $kv');
      return 64;
    }
    params[kv.substring(0, i)] = kv.substring(i + 1);
  }

  final vm = await vmServiceConnectUri(wsUri);
  try {
    final vmInfo = await vm.getVM();
    final isolates = vmInfo.isolates ?? const <IsolateRef>[];
    final iso = isolates
        .firstWhere(
          (i) => (i.name ?? '').toLowerCase().contains('main'),
          orElse: () => isolates.first,
        )
        .id!;
    if (args[1] == '__list') {
      final isolate = await vm.getIsolate(iso);
      for (final rpc in (isolate.extensionRPCs ?? const <String>[])..sort()) {
        print(rpc);
      }
      return 0;
    }
    final resp = await vm
        .callServiceExtension(method, isolateId: iso, args: params)
        .timeout(const Duration(seconds: 60));
    print(const JsonEncoder.withIndent('  ').convert(resp.json ?? {}));
    return 0;
  } catch (e) {
    print('CALL FAILED: $e');
    return 1;
  } finally {
    await vm.dispose();
  }
}
