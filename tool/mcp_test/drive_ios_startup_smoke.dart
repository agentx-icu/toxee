// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _skillNs = 'ext.flutter.flutter_skill';
const _mcpNs = 'ext.mcp.toolkit';

class _LocalVmServiceHttpOverrides extends HttpOverrides {
  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    final host = url.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost' || host == '::1') {
      return 'DIRECT';
    }
    return super.findProxyFromEnvironment(url, environment);
  }
}

Future<void> main(List<String> args) async {
  await HttpOverrides.runWithHttpOverrides(
    () => _main(args),
    _LocalVmServiceHttpOverrides(),
  );
}

Future<void> _main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: drive_ios_startup_smoke.dart <instance.json|ws_uri>');
    exit(64);
  }
  var ws = args.single;
  final input = File(ws);
  if (await input.exists()) {
    final json = jsonDecode(await input.readAsString()) as Map<String, dynamic>;
    ws = json['ws_uri']?.toString() ?? ws;
  }

  final vm = await vmServiceConnectUri(ws);
  try {
    final isolate = await _mainIsolate(vm);
    await _waitExt(vm, isolate, '$_skillNs.waitForElement');
    await _waitExt(vm, isolate, '$_mcpNs.l3_dump_state');
    Map<String, dynamic> state = const <String, dynamic>{};
    var landmarkVisible = false;
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      state = await _call(vm, isolate, '$_mcpNs.l3_dump_state');
      landmarkVisible = state['sessionReady'] == true ||
          await _waitForText(vm, isolate, 'Register new account') ||
          await _waitForKey(vm, isolate, 'register_page_nickname_field') ||
          await _waitForKey(vm, isolate, 'new_entry_menu_button') ||
          await _waitForText(vm, isolate, 'Startup Failed') ||
          await _waitForText(vm, isolate, 'Go to Login');
      if (landmarkVisible) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (!landmarkVisible) {
      throw StateError(
        'iOS app started, but no login/register/home landmark was visible: $state',
      );
    }
    print(
      'ios_startup_smoke PASS: sessionReady=${state['sessionReady']} '
      'landmarkVisible=$landmarkVisible ws=$ws',
    );
  } finally {
    await vm.dispose();
  }
}

Future<String> _mainIsolate(VmService vm) async {
  final v = await vm.getVM();
  final isolates = v.isolates ?? const <IsolateRef>[];
  return isolates
      .firstWhere(
        (i) => (i.name ?? '').toLowerCase().contains('main'),
        orElse: () => isolates.first,
      )
      .id!;
}

Future<void> _waitExt(
  VmService vm,
  String isolate,
  String name, {
  int timeoutSecs = 90,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final i = await vm.getIsolate(isolate);
    if ((i.extensionRPCs ?? const <String>[]).contains(name)) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('extension never registered: $name');
}

Future<Map<String, dynamic>> _call(
  VmService vm,
  String isolate,
  String method, [
  Map<String, String> args = const {},
]) async {
  final resp = await vm.callServiceExtension(method, isolateId: isolate, args: args);
  return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
}

Future<bool> _waitForText(VmService vm, String isolate, String text) async {
  final result = await _call(vm, isolate, '$_skillNs.waitForElement', {
    'text': text,
    'timeout': '12000',
  });
  // flutter_skill's waitForElement reports the match under `found` (see
  // flutter_skill/.../flutter_driver.dart waitForElement), NOT `success` — the
  // latter is the field for tap/enterText/scroll. Reading `success` here made
  // every text/key landmark check silently return false, so the smoke only ever
  // passed via the sessionReady branch (an auto-logged-in account) and reported
  // a false negative for the no-account LoginPage.
  return result['found'] == true;
}

Future<bool> _waitForKey(VmService vm, String isolate, String key) async {
  final result = await _call(vm, isolate, '$_skillNs.waitForElement', {
    'key': key,
    'timeout': '12000',
  });
  return result['found'] == true;
}
