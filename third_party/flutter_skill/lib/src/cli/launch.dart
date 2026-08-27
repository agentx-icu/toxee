import 'dart:convert';
import 'dart:io';
import 'setup.dart'; // Import setup logic

Future<void> runLaunch(List<String> args) async {
  // Extract project path. Everything else is passed to flutter run.
  // We assume: flutter_skill launch [project_path] [flutter_args...]
  // But wait, standard args might be tricky.
  // Let's say: first arg is project path if it doesn't start with -?

  String projectPath = '.';
  List<String> flutterArgs = [];

  if (args.isNotEmpty) {
    if (!args[0].startsWith('-')) {
      projectPath = args[0];
      flutterArgs = args.sublist(1);
    } else {
      // Current dir, all args are for flutter
      flutterArgs = args;
    }
  }

  print('Running auto-setup...');
  try {
    // Call the setup logic directly
    await runSetup(projectPath);
  } catch (e) {
    print('Setup failed: $e');
    print('Proceeding with launch anyway...');
  }

  // Auto-add --vm-service-port=50000 if not specified
  // This ensures faster discovery (recommended but not required)
  if (!flutterArgs.any((arg) => arg.contains('--vm-service-port'))) {
    flutterArgs.add('--vm-service-port=50000');
    print('💡 Auto-adding --vm-service-port=50000 (推荐，可加速发现)');
  }

  print('Launching Flutter app in: $projectPath with args: $flutterArgs');

  final flutterCmd = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final process = await Process.start(
    flutterCmd,
    ['run', ...flutterArgs],
    workingDirectory: projectPath,
    mode: ProcessStartMode.normal,
    runInShell: Platform.isWindows,
  );

  print(
      'Flutter process started (PID: ${process.pid}). Waiting for connection URI...');

  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    print('[Flutter]: $line');
    _checkForUri(line);
  });

  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    print('[Flutter Error]: $line');
  });

  // Forward stdin to flutter run
  if (stdin.hasTerminal) {
    stdin.listen((data) => process.stdin.add(data));
  }

  final exitCode = await process.exitCode;
  print('Flutter app exited with code $exitCode');
  exit(exitCode);
}

void _checkForUri(String line) {
  if (line.contains('ws://')) {
    final uriRegex = RegExp(r'ws://[^\s]+');
    final match = uriRegex.firstMatch(line);
    if (match != null) {
      final uri = match.group(0)!;
      print('\n✅ Flutter Skill: VM Service 已启动');
      print('   URI: $uri');
      print('   🚀 现在可以直接使用: flutter_skill inspect (自动发现)');
      // Note: No longer saving to .flutter_skill_uri - using auto-discovery instead!
    }
  }
}
