// Ad-hoc: connect to a live toxee debug VM, print per-isolate heap usage and
// the top allocation-profile classes by retained size. Diagnostic companion of
// the 2026-08-24 "VM service dies at ~790MB RSS" investigation.
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<int> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: heap_probe.dart <ws_uri>');
    return 64;
  }
  final vm = await vmServiceConnectUri(args[0]);
  try {
    final vmInfo = await vm.getVM();
    for (final ref in vmInfo.isolates ?? const <IsolateRef>[]) {
      final usage = await vm.getMemoryUsage(ref.id!);
      print(
        'isolate ${ref.name}: heap=${usage.heapUsage} '
        'capacity=${usage.heapCapacity} external=${usage.externalUsage}',
      );
      final profile = await vm.getAllocationProfile(ref.id!, gc: true);
      final members =
          (profile.members ?? const <ClassHeapStats>[])
              .where((m) => (m.bytesCurrent ?? 0) > 0)
              .toList()
            ..sort(
              (a, b) => (b.bytesCurrent ?? 0).compareTo(a.bytesCurrent ?? 0),
            );
      for (final m in members.take(25)) {
        print(
          '  ${m.bytesCurrent}\t${m.instancesCurrent}\t'
          '${m.classRef?.name}',
        );
      }
    }
  } finally {
    await vm.dispose();
  }
  return 0;
}
