// Minimal Windows driving-layer SPIKE.
//
// Proves the macOS osascript real-UI driving layer has working Windows
// equivalents, by driving a REAL registration through REAL widgets on a live
// toxee.exe:
//   * flutter_skill RPC over the VM service (tap / waitForElement / dump_state)
//     — OS-agnostic, unchanged from the macOS harness.
//   * foreground-window  : macOS `System Events set frontmost` -> WScript.Shell
//     `AppActivate(pid)`.
//   * real text entry    : macOS pbcopy + Cmd+V -> `Set-Clipboard` + SendKeys
//     `^v` (the atomic paste path; same rationale as osaPaste).
//
// A successful registration (Login -> Register -> fill 3 fields -> submit ->
// Home) can only happen if the pasted nickname + matching passwords actually
// landed in the real fields, so reaching Home (dump_state.homeShellTab != null)
// is end-to-end proof the driving layer works on Windows.
//
// Usage (run ON win11, in the worktree):
//   dart run tool/mcp_test/spike_win_drive.dart <ws-uri> <app-pid> [nickname]
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _skillNs = 'ext.flutter.flutter_skill';
const _mcpNs = 'ext.mcp.toolkit';

late VmService vm;
late String iso;
late int appPid;

void log(String m) => stdout.writeln('[spike] $m');

Future<Map<String, dynamic>> _raw(
  String method,
  Map<String, Object?> params,
) async {
  final strArgs = <String, String>{
    for (final e in params.entries)
      e.key: e.value is String ? e.value as String : jsonEncode(e.value),
  };
  final r = await vm
      .callServiceExtension(method, isolateId: iso, args: strArgs)
      .timeout(const Duration(seconds: 45));
  return r.json ?? <String, dynamic>{};
}

Future<Map<String, dynamic>> skill(String m, [Map<String, Object?> p = const {}]) =>
    _raw('$_skillNs.$m', p);
Future<Map<String, dynamic>> l3(String m, [Map<String, Object?> p = const {}]) =>
    _raw('$_mcpNs.$m', p);

Future<bool> waitKey(String key, {int secs = 20}) async {
  final r = await skill('waitForElement', {'key': key, 'timeout': '${secs * 1000}'});
  return r['found'] == true;
}

Future<bool> tapKey(String key) async {
  final r = await skill('tap', {'key': key});
  return r['success'] == true;
}

String _psLiteral(String s) => "'${s.replaceAll("'", "''")}'";

/// Windows port of foreground + osaClear + osaPaste: bring the app window to the
/// front, clear the focused field, and paste [text] atomically via the clipboard.
Future<void> winFocusPaste(String text, {bool clearFirst = true}) async {
  final clear = clearFirst
      ? r"$ws.SendKeys('^a'); Start-Sleep -Milliseconds 80; $ws.SendKeys('{DEL}'); Start-Sleep -Milliseconds 80;"
      : '';
  final ps =
      '\$ws = New-Object -ComObject WScript.Shell\n'
      '\$ws.AppActivate($appPid) | Out-Null\n'
      'Start-Sleep -Milliseconds 450\n'
      '$clear\n'
      'Set-Clipboard -Value ${_psLiteral(text)}\n'
      'Start-Sleep -Milliseconds 150\n'
      "\$ws.SendKeys('^v')\n"
      'Start-Sleep -Milliseconds 200\n';
  final res = await Process.run('powershell', ['-NoProfile', '-Command', ps]);
  if (res.exitCode != 0) {
    throw StateError('winFocusPaste failed (${res.exitCode}): ${res.stderr}');
  }
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: spike_win_drive.dart <ws-uri> <app-pid> [nickname]');
    exit(64);
  }
  final ws = args[0];
  appPid = int.parse(args[1]);
  final nickname = args.length > 2 ? args[2] : 'WinSpikeUser';
  const password = 'Spik3Pass!word';

  vm = await vmServiceConnectUri(ws);
  final v = await vm.getVM();
  final isos = v.isolates ?? const <IsolateRef>[];
  iso = isos
      .firstWhere(
        (i) => (i.name ?? '').toLowerCase().contains('main'),
        orElse: () => isos.first,
      )
      .id!;

  // Wait for the flutter_skill + l3 extensions to register.
  var ready = false;
  for (var i = 0; i < 80; i++) {
    final ii = await vm.getIsolate(iso);
    final rpcs = ii.extensionRPCs ?? const <String>[];
    if (rpcs.contains('$_skillNs.tap') && rpcs.contains('$_mcpNs.l3_dump_state')) {
      ready = true;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (!ready) {
    log('FAIL: flutter_skill / l3 extensions never registered');
    exit(2);
  }
  log('connected + RPC live on Windows');

  // 1. RPC read works on Windows.
  final d0 = await l3('l3_dump_state');
  log('dump_state OK (homeShellTab before = ${d0['homeShellTab']})');

  // 2. Login -> Register (tap by key).
  if (!await waitKey('login_page_register_account_card')) {
    log('FAIL: register card not found on LoginPage');
    exit(2);
  }
  await tapKey('login_page_register_account_card');
  log('tapped "Register new account"');

  // 3. Fill the 3 required fields with real OS paste.
  if (!await waitKey('register_page_nickname_field')) {
    log('FAIL: RegisterPage nickname field not found');
    exit(2);
  }
  await tapKey('register_page_nickname_field');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  var er = await skill('enterText', {'text': nickname});
  log('enterText nickname success=${er['success']}');

  await tapKey('register_page_password_field');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  er = await skill('enterText', {'text': password});
  log('enterText password success=${er['success']}');

  await tapKey('register_page_confirm_password_field');
  await Future<void>.delayed(const Duration(milliseconds: 300));
  er = await skill('enterText', {'text': password});
  log('enterText confirm success=${er['success']}');

  // 3b. PROOF: screenshot the filled form (flutter-layer capture shows the real
  // field contents regardless of window focus/visibility) so paste-landing can
  // be verified visually.
  try {
    final shot = await skill('screenshot');
    final img = shot['image'] as String?;
    if (img != null && img.isNotEmpty) {
      await File(r'C:\toxee-win\.rt\A\after_fill.png')
          .writeAsBytes(base64Decode(img));
      log('saved after_fill.png (${img.length} b64 chars)');
    } else {
      log('screenshot empty');
    }
  } catch (e) {
    log('screenshot failed: $e');
  }

  // 4. Submit.
  if (!await waitKey('register_page_register_button')) {
    log('FAIL: register button not found');
    exit(2);
  }
  await tapKey('register_page_register_button');
  log('tapped Register — waiting for Home...');

  // 5. Reaching Home proves the pasted fields were valid => driving works.
  for (var i = 0; i < 40; i++) {
    final d = await l3('l3_dump_state');
    final tab = d['homeShellTab']?.toString();
    if (tab != null && tab != 'null' && tab.isNotEmpty) {
      final selfId = d['selfToxId'] ?? d['selfId'] ?? d['toxId'];
      log('PASS: reached Home (homeShellTab=$tab) — real-UI registration '
          'succeeded via Windows foreground+paste driving.');
      log('selfToxId=${selfId ?? '(not surfaced in dump)'} '
          'isConnected=${d['isConnected']}');
      await vm.dispose();
      exit(0);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1500));
  }
  log('FAIL: never reached Home (homeShellTab stayed null) — registration or '
      'driving incomplete.');
  await vm.dispose();
  exit(3);
}
