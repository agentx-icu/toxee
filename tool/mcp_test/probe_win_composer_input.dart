// Windows REAL-OS-INPUT diagnostic for the desktop chat composer.
//
// The real-UI driver's Windows backend (drive_real_ui_pair_inst_os_input.dart)
// drives `WScript.Shell.AppActivate` + `SendKeys` / `Set-Clipboard`. Plain
// TextFields (register / settings) take that input fine; this probe answers,
// for the ExtendedTextField CHAT COMPOSER specifically, which primitives land:
//   A. clipboard paste (Set-Clipboard + ^v)            → read back
//   B. caret clear chord (^{END} ^+{HOME} {BACKSPACE})  → read back
//   C. char-by-char SendKeys typing                      → read back
//   D. {ENTER}                                           → message sent?
//   E. ^a + {DEL} clear                                  → read back
// Read-back uses the same seams the driver uses (flutter_skill getTextValue /
// interactiveStructured / waitForElement{text}) plus the conversation's lastMessageText.
//
// Run INSIDE the Windows console session (tool/vmtest/win_run_interactive.ps1)
// against a freshly launched instance (no account yet — it registers one):
//   dart run tool/mcp_test/probe_win_composer_input.dart <ws-uri> <app-pid>
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _skillNs = 'ext.flutter.flutter_skill';
const _mcpNs = 'ext.mcp.toolkit';
// Seeded public key: toxcore's public_key_valid() needs the top bit of the LAST
// byte clear (see tool/screenshots/README.md).
const _friendKey =
    'ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB01';

late VmService vm;
late String iso;
late int appPid;

void log(String m) => stdout.writeln('[composer-probe] $m');

Future<Map<String, dynamic>> _raw(String method, Map<String, Object?> p) async {
  final args = <String, String>{
    for (final e in p.entries)
      e.key: e.value is String ? e.value as String : jsonEncode(e.value),
  };
  final r = await vm
      .callServiceExtension(method, isolateId: iso, args: args)
      .timeout(const Duration(seconds: 45));
  return r.json ?? <String, dynamic>{};
}

Future<Map<String, dynamic>> skill(
  String m, [
  Map<String, Object?> p = const {},
]) => _raw('$_skillNs.$m', p);
Future<Map<String, dynamic>> l3(
  String m, [
  Map<String, Object?> p = const {},
]) => _raw('$_mcpNs.$m', p);

String _ps(String s) => "'${s.replaceAll("'", "''")}'";

Future<void> win(String body, {bool force = false}) async {
  final script = StringBuffer()
    ..writeln(". '${Directory.current.path}\\tool\\mcp_test\\win_os_input.ps1'")
    ..writeln('\$ws = New-Object -ComObject WScript.Shell');
  if (force) {
    // Never AppActivate here: on an already-foreground window it moves Win32
    // focus from FLUTTERVIEW back to the runner frame (probe run 12).
    script
      ..writeln('[ToxeeU32]::ReleaseMods()')
      ..writeln('\$forced = Set-ToxeeForeground -ProcessId $appPid')
      ..writeln(
        '[ToxeeU32]::FocusFlutterView([IntPtr](Get-Process -Id $appPid).MainWindowHandle) | Out-Null',
      )
      ..writeln('Start-Sleep -Milliseconds 120')
      ..writeln(
        'Write-Output ("pre (strategy=" + \$forced + "): " + (Get-ForegroundDiag -ProcessId $appPid))',
      );
  } else {
    script
      ..writeln('\$ok = \$ws.AppActivate($appPid)')
      ..writeln('Start-Sleep -Milliseconds 220')
      ..writeln(
        'Write-Output ("pre (AppActivate=" + \$ok + "): " + (Get-ForegroundDiag -ProcessId $appPid))',
      );
  }
  script
    ..writeln(body)
    ..writeln(
      'Write-Output ("post: " + (Get-ForegroundDiag -ProcessId $appPid))',
    );
  // A temp .ps1 under build/: `-File` sidesteps every `-Command` re-parse.
  final tmp = File('${Directory.current.path}\\build\\probe_win_step.ps1');
  await tmp.writeAsString(script.toString(), flush: true);
  final r = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    tmp.path,
  ]);
  for (final l in '${r.stdout}\n${r.stderr}'.split('\n')) {
    final t = l.trim().replaceAll(RegExp(r' windows=\[[^\]]*\]'), '');
    if (t.isNotEmpty) log('  ps> $t');
  }
  if (r.exitCode != 0) log('WIN FAIL (${r.exitCode})');
}

Future<bool> waitKey(String key, {int secs = 20}) async {
  final r = await skill('waitForElement', {
    'key': key,
    'timeout': '${secs * 1000}',
  });
  return r['found'] == true;
}

/// Same resolver the driver uses (l3 `ui_key_center`, the element-tree walk);
/// flutter_skill's interactiveStructured does not surface the composer.
Future<({double x, double y})?> keyCenter(String key) async {
  final r = await l3('ui_key_center', {'key': key});
  if (r['ok'] != true) return null;
  final x = (r['x'] as num?)?.toDouble();
  final y = (r['y'] as num?)?.toDouble();
  if (x == null || y == null) return null;
  return (x: x, y: y);
}

Future<void> readback(String label) async {
  final v = (await skill('getTextValue', {
    'key': 'chat_input_text_field',
  }))['value'];
  String? structured;
  final r = await skill('interactiveStructured', const {});
  final data = r['data'];
  final els = data is Map ? data['elements'] : null;
  if (els is List) {
    for (final e in els) {
      if (e is Map && e['key'] == 'chat_input_text_field') {
        structured = '${e['text']}';
      }
    }
  }
  final found = await skill('waitForElement', {
    'text': 'PROBE',
    'timeout': '800',
  });
  log(
    '$label: getTextValue="$v" structured="$structured" textFound(PROBE)=${found['found']}',
  );
}

Future<String?> lastMessage() async {
  final s = await l3('l3_dump_state');
  for (final c in (s['conversations'] as List? ?? const [])) {
    if (c is Map) return c['lastMessageText']?.toString();
  }
  return null;
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: probe_win_composer_input.dart <ws-uri> <app-pid>');
    exit(64);
  }
  appPid = int.parse(args[1]);
  vm = await vmServiceConnectUri(args[0]);
  final v = await vm.getVM();
  final isos = v.isolates ?? const <IsolateRef>[];
  iso = isos
      .firstWhere(
        (i) => (i.name ?? '').contains('main'),
        orElse: () => isos.first,
      )
      .id!;
  for (var i = 0; i < 80; i++) {
    final rpcs = (await vm.getIsolate(iso)).extensionRPCs ?? const <String>[];
    if (rpcs.contains('$_skillNs.tap') &&
        rpcs.contains('$_mcpNs.l3_dump_state')) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  log('connected');

  // Register through the real UI (fields are plain TextFields: enterText is fine).
  if (!await waitKey('login_page_register_account_card')) exit(2);
  await skill('tap', {'key': 'login_page_register_account_card'});
  if (!await waitKey('register_page_nickname_field')) exit(2);
  // R1. Typing reliability on a plain TextField (getTextValue works there):
  // per-key delay x case. Flutter Windows redispatches unhandled keys
  // asynchronously, so too-fast injection can lose characters.
  await skill('tap', {'key': 'register_page_nickname_field'});
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final v in [
    ('REALNICK', 6),
    ('REALNICK', 20),
    ('RUIP1DRAFT-ab12', 12),
    ('Mixed-Case_9!', 12),
    ('realnick', 6),
  ]) {
    await win(
      "Send-ScanText -Text '${v.$1}' -DelayMs ${v.$2} | Out-Null\nStart-Sleep -Milliseconds 400",
      force: true,
    );
    log(
      'R1 typed "${v.$1}" delay=${v.$2}ms -> getTextValue="${(await skill('getTextValue', {'key': 'register_page_nickname_field'}))['value']}"',
    );
    await win(
      "Send-ScanKey -Name a -Modifiers ctrl\nStart-Sleep -Milliseconds 80\nSend-ScanKey -Name DEL\nStart-Sleep -Milliseconds 200",
      force: true,
    );
    log(
      'R1 after ctrl+a DEL -> getTextValue="${(await skill('getTextValue', {'key': 'register_page_nickname_field'}))['value']}"',
    );
  }
  await skill('enterText', {'key': 'register_page_nickname_field', 'text': ''});
  for (final e in {
    'register_page_nickname_field': 'ProbeUser',
    'register_page_password_field': 'Pr0be!Pass',
    'register_page_confirm_password_field': 'Pr0be!Pass',
  }.entries) {
    await skill('tap', {'key': e.key});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await skill('enterText', {'text': e.value});
  }
  await skill('tap', {'key': 'register_page_register_button'});
  var ready = false;
  for (var i = 0; i < 60 && !ready; i++) {
    await Future<void>.delayed(const Duration(seconds: 1));
    ready = (await l3('l3_dump_state'))['sessionReady'] == true;
  }
  log('sessionReady=$ready');
  if (!ready) exit(3);
  // Dismiss the first-run backup wizard if it is up (same texts the driver uses).
  for (final t in ["I'll do it later", 'I understand, continue']) {
    final f = await skill('waitForElement', {'text': t, 'timeout': '1500'});
    if (f['found'] == true) {
      await skill('tap', {'text': t});
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }
  log('mark test: ${(await l3('l3_mark_current_account_test'))['ok']}');
  log(
    'seed friend: ${await l3('l3_seed_friend', {'userId': _friendKey, 'nickname': 'ProbeFriend'})}',
  );
  log('open chat: ${(await l3('l3_open_chat', {'userId': _friendKey}))['ok']}');
  if (!await waitKey('chat_input_text_field', secs: 15)) {
    log('FAIL: composer never mounted');
    exit(4);
  }
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final c = await keyCenter('chat_input_text_field');
  log('composer center=$c');
  if (c != null) await skill('tapAt', {'x': c.x, 'y': c.y});
  await Future<void>.delayed(const Duration(milliseconds: 500));

  // C. synthetic tapAt, scan-coded typing, ENTER -> sent?
  if (c != null) await skill('tapAt', {'x': c.x, 'y': c.y});
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await win(
    "Send-ScanText -Text 'ProbeType-C' -DelayMs 12 | Out-Null\nStart-Sleep -Milliseconds 300\nSend-ScanKey -Name ENTER",
    force: true,
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  log(
    'C synthetic tap + typing + ENTER: lastMessage="${(await lastMessage())?.replaceAll('\n', '\\n')}"',
  );
  // R3. REAL click, typing, ENTER -> sent?
  if (c != null) {
    await win(
      "Write-Output ('click=' + [ToxeeU32]::ClickView([IntPtr](Get-Process -Id $appPid).MainWindowHandle, ${c.x}, ${c.y}))\nStart-Sleep -Milliseconds 500\nSend-ScanText -Text 'ProbeType-R3' -DelayMs 12 | Out-Null\nStart-Sleep -Milliseconds 300\nSend-ScanKey -Name ENTER",
      force: true,
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    log(
      'R3 real click + typing + ENTER: lastMessage="${(await lastMessage())?.replaceAll('\n', '\\n')}"',
    );
  }
  // E. shift+ENTER newline, then ENTER -> one two-line message?
  if (c != null) await skill('tapAt', {'x': c.x, 'y': c.y});
  await win(
    "Send-ScanText -Text 'line1' -DelayMs 30 | Out-Null\nSend-ScanKey -Name ENTER -Modifiers shift\nSend-ScanText -Text 'line2' -DelayMs 30 | Out-Null\nStart-Sleep -Milliseconds 300\nSend-ScanKey -Name ENTER",
    force: true,
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  log(
    'E shift+enter: lastMessage="${(await lastMessage())?.replaceAll('\n', '\\n')}"',
  );
  // B. type, caret-clear chord, then ENTER -> nothing new sent?
  await win(
    "Send-ScanText -Text 'SHOULD-BE-CLEARED' -DelayMs 12 | Out-Null\nSend-ScanKey -Name END -Modifiers ctrl\nStart-Sleep -Milliseconds 80\nSend-ScanKey -Name HOME -Modifiers ctrl,shift\nStart-Sleep -Milliseconds 80\nSend-ScanKey -Name BACKSPACE\nStart-Sleep -Milliseconds 300\nSend-ScanKey -Name ENTER",
    force: true,
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  log(
    'B caret-clear then ENTER: lastMessage="${(await lastMessage())?.replaceAll('\n', '\\n')}" (expect unchanged)',
  );
  // A2. clipboard + ctrl+v + ENTER.
  await win(
    'Set-Clipboard -Value ${_ps('PROBEPASTE-A2 with spaces & <chars>')}\nStart-Sleep -Milliseconds 150\nSend-ScanKey -Name v -Modifiers ctrl\nStart-Sleep -Milliseconds 400\nSend-ScanKey -Name ENTER',
    force: true,
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  log('A2 paste + ENTER: lastMessage="${await lastMessage()}"');
  // ESC: does it leave the composer state alone (no crash)?
  await win("Send-ScanKey -Name ESC", force: true);
  log('ESC sent');
  await vm.dispose();
  log('DONE');
  exit(0);
}
