// Ad-hoc iOS/iPad driver over the VM service `ext.mcp.toolkit.*` extensions
// (same ones the arenukvern MCP uses) so we can drive a sim instance when the
// MCP server is disconnected. Registers an account and lands on Home.
//
// Usage: dart run tool/mcp_test/ipad_drive.dart <ws_uri> [nickname]
// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'dart:convert';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

late VmService vm;
late String iso;

Future<Map<String, dynamic>> ext(String method,
    [Map<String, dynamic> args = const {}]) async {
  final r = await vm.callServiceExtension('ext.mcp.toolkit.$method',
      isolateId: iso, args: args);
  return r.json ?? {};
}

Future<List<dynamic>> snapshot() async {
  final r = await ext('semantic_snapshot');
  return (r['nodes'] as List?) ?? const [];
}

Map<String, dynamic>? find(List<dynamic> nodes, bool Function(String) match) {
  for (final n in nodes) {
    final label = (n['label'] ?? '').toString();
    if (label.isNotEmpty && match(label)) return n as Map<String, dynamic>;
  }
  return null;
}

Future<bool> tapLabel(String sub, {bool contains = true}) async {
  final nodes = await snapshot();
  final n = find(nodes, (l) => contains ? l.contains(sub) : l == sub);
  if (n == null) return false;
  await ext('tap_widget', {'ref': n['ref']});
  return true;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: ipad_drive.dart <ws_uri> [nickname]');
    return;
  }
  final nickname = args.length > 1 ? args[1] : 'iPadTest';
  vm = await vmServiceConnectUri(args[0]);
  final vmInfo = await vm.getVM();
  iso = vmInfo.isolates!.first.id!;
  print('connected iso=$iso');

  // Show what's on screen now.
  var nodes = await snapshot();
  print('screen nodes: ${nodes.map((n) => n['label']).where((l) => l != null && '$l'.isNotEmpty).toList()}');

  // 1) Onboarding -> Register.
  if (await tapLabel('Register new account')) {
    print('tapped Register new account');
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  // 2) Fill nickname.
  nodes = await snapshot();
  final nick = find(nodes, (l) => l.contains('Nickname') || l.contains('昵称'));
  if (nick != null) {
    await ext('enter_text', {'ref': nick['ref'], 'text': nickname});
    print('entered nickname');
    await Future<void>.delayed(const Duration(seconds: 1));
  } else {
    print('WARN: nickname field not found: ${nodes.map((n) => n['label']).toList()}');
  }

  // 3) Tap Register button (avoid the onboarding label which is gone now).
  nodes = await snapshot();
  final reg = find(nodes,
      (l) => l == 'Register' || l == 'Create' || l.trim() == 'Register account');
  if (reg != null) {
    await ext('tap_widget', {'ref': reg['ref']});
    print('tapped Register button');
  } else {
    print('WARN: register button not found: ${nodes.map((n) => n['label']).toList()}');
  }

  // 4) Poll for Home (Chats/Settings nav) up to 45s, dismissing any
  //    post-register wizard by tapping Skip/Done/Continue/Later.
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    nodes = await snapshot();
    final labels = nodes.map((n) => '${n['label']}').join(' | ');
    if (labels.contains('Settings') && labels.contains('Chats')) {
      print('HOME reached');
      break;
    }
    final adv = find(nodes, (l) {
      final s = l.toLowerCase();
      return s.contains('i understand') ||
          s.contains('continue') ||
          s.contains('do it later') ||
          s.contains('later') ||
          s == 'skip' ||
          s == 'done' ||
          s.contains('稍后') ||
          s.contains('跳过');
    });
    if (adv != null) {
      await ext('tap_widget', {'ref': adv['ref']});
      print('dismissed via "${adv['label']}"');
    }
    if (i % 5 == 0) print('waiting home… [$i] ${labels.substring(0, labels.length.clamp(0, 120))}');
  }
  print('final: ${jsonEncode(nodes.map((n) => n['label']).toList())}');
  await vm.dispose();
}
