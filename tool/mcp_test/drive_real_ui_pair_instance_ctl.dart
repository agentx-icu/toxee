// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Per-platform SINGLE-instance process control for the relaunch scenarios
// (sweep_p1_relaunch, presence_dot_relaunch): stop one peer, bring the SAME
// peer back, and read its new pid / ws_uri.
//
// The relaunch drivers used to shell out to the macOS `.sh` launchers and read
// `tool/mcp_test/.multi_instance_runtime/<name>/instance.json` unconditionally,
// so on Windows they booted nothing (no bash) and were skipped. Windows now has
// PowerShell twins (`stop_toxee_instance.ps1` / `launch_toxee_instance.ps1`)
// that work from the pair launcher's recorded contract under
// `build/windows_runtime/<name>/`. Mobile pairs are still deliberately NOT
// registered for these sweeps (see fixture_c_real_ui_mobile_campaigns.dart).

/// Command lines + runtime dir for controlling ONE instance on this platform.
({List<String> stop, List<String> launch, String runtimeDir}) _instanceCtl(
  String name,
) {
  if (_isWindowsRealUi) {
    final root = (Platform.environment['TOXEE_WINDOWS_RUNTIME_ROOT'] ?? '')
        .trim();
    List<String> ps(String script) => [
      'powershell',
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      'tool/mcp_test/$script',
      name,
    ];
    return (
      stop: ps('stop_toxee_instance.ps1'),
      launch: ps('launch_toxee_instance.ps1'),
      runtimeDir: root.isEmpty
          ? 'build/windows_runtime/$name'
          : '$root${Platform.pathSeparator}$name',
    );
  }
  if (_realUiPlatform == 'linux') {
    // Linux twins. The macOS scripts below are unusable here twice over: they
    // launch `Toxee.app` (no such thing on Linux) and they write under
    // `tool/mcp_test/.multi_instance_runtime`, which on a share-shim checkout
    // is a READ-ONLY symlink into the Mac share. The Linux pair keeps its
    // runtime under `build/linux_runtime/<name>/` like Windows does.
    final root = (Platform.environment['TOXEE_LINUX_RUNTIME_ROOT'] ?? '')
        .trim();
    // Explicit `bash`, not the script as the executable: a checkout made over
    // the CIFS/Parallels share can lose the exec bit, and a relaunch that dies
    // with EACCES mid-sweep is a confusing way to learn that.
    return (
      stop: ['bash', 'tool/mcp_test/stop_toxee_linux_instance.sh', name],
      launch: ['bash', 'tool/mcp_test/launch_toxee_linux_instance.sh', name],
      runtimeDir: root.isEmpty ? 'build/linux_runtime/$name' : '$root/$name',
    );
  }
  return (
    stop: ['tool/mcp_test/stop_toxee_instance.sh', name],
    launch: ['tool/mcp_test/launch_toxee_instance.sh', name],
    runtimeDir: 'tool/mcp_test/.multi_instance_runtime/$name',
  );
}

/// TCP-relay fallback port for [wireFullMeshBootstrap] sites, or null when the
/// pair has no localhost relay to add explicitly:
///   * Android star — the HOST-side port adb maps to A's guest relay
///     ([fixtureCTcpRelayHostPort]).
///   * Desktop same-host TCP-only pairs (`TOXEE_PAIR_TCP_ONLY=1`, which the
///     runner sets for Windows/Linux and the macOS launcher honours) — A
///     listens on `TOXEE_PAIR_TCP_RELAY_PORT`, defaulting to the launcher's
///     default: 3389 on macOS/Linux, **33390 on Windows** (3389 is the RDP
///     listener on any Windows box with Remote Desktop enabled — measured on
///     the win11_ltsc VM: A's tox_new failed with the relay port taken and the
///     pair never reached sessionReady). Adding the relay EXPLICITLY here
///     removes the dependency on toxcore's default-port probing altogether.
///   * iOS pairs have their OWN fixed listener ports → null.
int? _pairTcpRelayFallbackPort(Inst a, Inst b) {
  // Android needs the adb-reverse HOST port explicitly; desktop pairs leave it
  // null so wireFullMeshBootstrap resolves each PEER's own relay (pair.json)
  // before the env default.
  if (a.isAndroid || b.isAndroid) return fixtureCTcpRelayHostPort();
  return null;
}

/// Run one of the [_instanceCtl] command lines; throws a [DriveError] naming
/// the script on a non-zero exit.
Future<void> _runInstanceCtl(List<String> cmd, {required String what}) async {
  if (Platform.isWindows) {
    // Never CAPTURE the launcher's stdio on Windows: the toxee.exe it starts
    // inherits the pipe, so Process.run would block until the app EXITS
    // (sweep_p1_relaunch hung for 25 min at "relaunching instance"). The
    // script's own output goes to the campaign log through the inherited
    // console instead.
    final proc = await Process.start(
      cmd.first,
      cmd.sublist(1),
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await proc.exitCode;
    if (code != 0) throw DriveError('$what failed (exit $code)');
    return;
  }
  final r = await Process.run(cmd.first, cmd.sublist(1));
  if (r.exitCode != 0) {
    throw DriveError(
      '$what failed (exit ${r.exitCode}): ${'${r.stderr}'.trim()} '
      '${'${r.stdout}'.trim()}',
    );
  }
}
