import 'qtox_external_peer_harness.dart';

const qtoxExternalPeerUsage = '''
usage: dart run tool/mcp_test/qtox_external_peer_runner.dart
       (--qtox-app=<path>|--qtox-executable=<path>|--qtox-artifact=<path>)
       --bootstrap-public-key=<64 hex characters>
       [--scratch-root=<repo>/build/qtox_external_peer/<name>]
       [--bootstrap-port=<port>] [--bootstrap-tcp-port=<port>]
       [--profile-name=<scratch profile>] [--app-executable-name=qtox]
       [--plan-json|--prepare|--launch|--signal-screenshot|--teardown]

The default action is --plan-json. Plan mode performs no filesystem writes and
does not require qTox to be installed. Live actions are explicit:
  --prepare            reset the owned scratch root, stage qTox, write config
  --launch             launch a previously prepared root and wait for qTox
  --signal-screenshot  send SIGUSR1 and wait for the scratch screenshot
  --teardown           stop the recorded process; retain scratch evidence

Official artifacts must already be extracted to qTox.app or an executable.
This runner never downloads, installs, mounts, or builds qTox.
''';

enum QtoxRunnerAction { plan, prepare, launch, screenshot, teardown }

class QtoxRunnerOptions {
  const QtoxRunnerOptions({
    required this.action,
    required this.artifact,
    required this.bootstrapPublicKey,
    required this.bootstrapPort,
    required this.bootstrapTcpPort,
    required this.scratchRoot,
    required this.profileName,
    required this.showHelp,
    required this.error,
  });

  final QtoxRunnerAction action;
  final QtoxArtifactSelection? artifact;
  final String? bootstrapPublicKey;
  final int bootstrapPort;
  final int bootstrapTcpPort;
  final String? scratchRoot;
  final String? profileName;
  final bool showHelp;
  final String? error;

  static QtoxRunnerOptions parse(List<String> args) {
    var action = QtoxRunnerAction.plan;
    var actionWasSet = false;
    QtoxArtifactSelection? artifact;
    String? bootstrapPublicKey;
    var bootstrapPort = 33445;
    int? bootstrapTcpPort;
    String? scratchRoot;
    String? profileName;
    var appExecutableName = 'qtox';
    var showHelp = false;
    String? error;
    String? artifactFlag;
    String? artifactValue;

    void selectAction(QtoxRunnerAction selected, String flag) {
      if (actionWasSet && action != selected) {
        error ??= 'choose exactly one lifecycle action (conflict at $flag)';
        return;
      }
      action = selected;
      actionWasSet = true;
    }

    void selectArtifact(String selected, String value) {
      if (artifactFlag != null) {
        error ??= 'choose exactly one qTox app/executable/artifact path';
        return;
      }
      artifactFlag = selected;
      artifactValue = value;
    }

    for (final arg in args) {
      if (arg == '--plan-json') {
        selectAction(QtoxRunnerAction.plan, arg);
      } else if (arg == '--prepare') {
        selectAction(QtoxRunnerAction.prepare, arg);
      } else if (arg == '--launch') {
        selectAction(QtoxRunnerAction.launch, arg);
      } else if (arg == '--signal-screenshot') {
        selectAction(QtoxRunnerAction.screenshot, arg);
      } else if (arg == '--teardown') {
        selectAction(QtoxRunnerAction.teardown, arg);
      } else if (arg.startsWith('--qtox-app=')) {
        selectArtifact('app', arg.substring('--qtox-app='.length));
      } else if (arg.startsWith('--qtox-executable=')) {
        selectArtifact(
          'executable',
          arg.substring('--qtox-executable='.length),
        );
      } else if (arg.startsWith('--qtox-artifact=')) {
        selectArtifact(
          'official-artifact',
          arg.substring('--qtox-artifact='.length),
        );
      } else if (arg.startsWith('--bootstrap-public-key=')) {
        bootstrapPublicKey = arg.substring('--bootstrap-public-key='.length);
      } else if (arg.startsWith('--bootstrap-port=')) {
        bootstrapPort = _parsePort(
          arg.substring('--bootstrap-port='.length),
          '--bootstrap-port',
        );
      } else if (arg.startsWith('--bootstrap-tcp-port=')) {
        bootstrapTcpPort = _parsePort(
          arg.substring('--bootstrap-tcp-port='.length),
          '--bootstrap-tcp-port',
        );
      } else if (arg.startsWith('--scratch-root=')) {
        scratchRoot = arg.substring('--scratch-root='.length);
      } else if (arg.startsWith('--profile-name=')) {
        profileName = arg.substring('--profile-name='.length);
      } else if (arg.startsWith('--app-executable-name=')) {
        appExecutableName = arg.substring('--app-executable-name='.length);
      } else if (arg == '--help' || arg == '-h' || arg == 'help') {
        showHelp = true;
      } else if (arg.trim().isNotEmpty) {
        error ??= 'unknown argument: $arg';
      }
    }

    final selectedArtifactValue = artifactValue;
    if (!showHelp) {
      if (selectedArtifactValue == null || selectedArtifactValue.isEmpty) {
        error ??= 'one qTox app/executable/artifact path is required';
      }
      if (bootstrapPublicKey?.isEmpty ?? true) {
        error ??= '--bootstrap-public-key is required';
      }
    }
    if (selectedArtifactValue != null) {
      artifact = switch (artifactFlag) {
        'app' => QtoxArtifactSelection.app(
          selectedArtifactValue,
          executableName: appExecutableName,
        ),
        'executable' => QtoxArtifactSelection.executable(selectedArtifactValue),
        _ => QtoxArtifactSelection.officialArtifact(
          selectedArtifactValue,
          executableName: appExecutableName,
        ),
      };
    }

    return QtoxRunnerOptions(
      action: action,
      artifact: artifact,
      bootstrapPublicKey: bootstrapPublicKey,
      bootstrapPort: bootstrapPort,
      bootstrapTcpPort: bootstrapTcpPort ?? bootstrapPort,
      scratchRoot: scratchRoot,
      profileName: profileName,
      showHelp: showHelp,
      error: error,
    );
  }

  static int _parsePort(String value, String flag) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 65535) {
      throw FormatException('$flag must be an integer in 1..65535');
    }
    return parsed;
  }
}
