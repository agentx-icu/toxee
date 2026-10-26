import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

import '../util/app_paths.dart';
import '../util/harness_environment.dart';
import '../util/logger.dart';
import '../util/safe_diagnostics.dart';

/// Log path detection, AppLogger initialization, FFI log file, and native library name.
///
/// Log path discovery is intentionally multi-branch (X6 from the 2026-05-18
/// local-storage review). The branches exist to support two distinct
/// audiences:
///
///   1. **Developer dev-loop** — `run_toxee.sh` tails a flat
///      `flutter_client.log` from either `$TOXEE_LOG_DIR` (if exported) or
///      `Directory.current/build/`. These two branches MUST keep that exact
///      filename or the tail-and-grep dev workflow breaks.
///   2. **Production / CI / mobile** — falls through to `AppPaths.logFilePath`
///      which returns the timestamped path under `<appSupport>/logs/`
///      (`app_<ts>.log`). This is the canonical convention. The flat
///      `<appSupport>/flutter_client.log` previously returned by
///      `AppPaths.logFilePath` is deprecated.
///
/// If you're adding a new discovery branch, document which audience it serves.
class LoggingBootstrap {
  LoggingBootstrap._();

  /// Routes print() output to AppLogger. Parses TCCF lines (TencentCloudChatLog)
  /// so level and body are normalized instead of duplicating timestamp in body.
  static void routePrintToLogger(String line) {
    // TCCF:2026-02-11 03:48:47 PM:TencentCloudChatMessageSDK:debug:{ addUIKitListener 1770796127319 }
    final tccfMatch = RegExp(
      r'^TCCF:(?:\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}:\d{2} [AP]M):([^:]+):(debug|info|error|all):\{ (.*) \}$',
    ).firstMatch(line);
    if (tccfMatch != null) {
      final component = tccfMatch.group(1)!.trim();
      final level = tccfMatch.group(2)!;
      final body = tccfMatch.group(3)!.trim();
      final logBody = '$component: $body';
      switch (level) {
        case 'debug':
          AppLogger.debug(logBody);
          break;
        case 'info':
          AppLogger.info(logBody);
          break;
        case 'error':
          AppLogger.error(logBody);
          break;
        case 'all':
        default:
          AppLogger.info(logBody);
      }
      return;
    }
    AppLogger.info(line);
  }

  /// Probe a private temporary child, never overwrite the intended log leaf.
  static void _probeDirectory(Directory directory) {
    directory.createSync(recursive: true);
    final probe = directory.createTempSync('.toxee-log-probe-');
    probe.deleteSync();
  }

  static Future<void> initialize() async {
    final logDirEnv = HarnessEnvironment.value(HarnessEnvironment.logDirKey);
    try {
      String? logPath;
      bool useSymlink = false;
      // (1) Dev-loop branch: `flutter_client.log` filename is required so
      // `run_toxee.sh`'s `tail -F` keeps working.
      if (logDirEnv != null && logDirEnv.isNotEmpty) {
        final testPath = p.join(logDirEnv, 'flutter_client.log');
        try {
          _probeDirectory(File(testPath).parent);
          logPath = testPath;
          stderr.writeln('AppLogger: Using configured log directory');
        } catch (e) {
          stderr.writeln(
            'AppLogger: [INFO] Cannot write to configured log directory',
          );
          stderr.writeln(
            'AppLogger: [INFO] Will use application support directory and create symlink',
          );
          useSymlink = true;
        }
      }

      // (1, cont.) Second dev-loop branch: `Directory.current/build/flutter_client.log`.
      // Same flat filename for the same reason. Desktop-only: on iOS/Android the
      // process working directory is `/` (read-only), so this probe always fails
      // and only emits a misleading stderr error before the appSupport fallback
      // below takes over — skip it on mobile and go straight to branch (2).
      if (kDebugMode &&
          logPath == null &&
          !useSymlink &&
          !Platform.isIOS &&
          !Platform.isAndroid) {
        try {
          final currentDir = Directory.current;
          final testPath = p.join(
            currentDir.path,
            'build',
            'flutter_client.log',
          );
          final testDir = File(testPath).parent;
          if (testDir.existsSync() || testDir.parent.existsSync()) {
            try {
              _probeDirectory(testDir);
              logPath = testPath;
              stderr.writeln('AppLogger: Using working-directory log storage');
            } catch (e) {
              stderr.writeln(
                'AppLogger: Cannot write to working-directory log storage '
                '${SafeDiagnostics.describeError(e)}',
              );
              useSymlink = true;
            }
          }
        } catch (e) {
          // Directory.current might not work in app bundle — fall through to
          // the symlink/timestamped fallback. Logger isn't initialised yet so
          // stderr is the best we can do, but the fallback path is the
          // canonical case so loud logging here would be noisy.
          stderr.writeln(
            'AppLogger: Working-directory probe failed '
            '${SafeDiagnostics.describeError(e)}',
          );
        }
      }

      // (2) Production / fallback branch: timestamped path under
      // `<appSupport>/logs/`. This is the canonical convention.
      if (logPath == null || useSymlink) {
        try {
          logPath = await AppPaths.logFilePath;
          stderr.writeln('AppLogger: Using application support log storage');
          if (useSymlink && logDirEnv != null && logDirEnv.isNotEmpty) {
            stderr.writeln(
              'AppLogger: [INFO] Cannot create symlink from sandbox (expected - macOS security restriction)',
            );
            stderr.writeln(
              'AppLogger: [INFO] Script will create the configured log symlink',
            );
          }
        } catch (e) {
          stderr.writeln(
            'AppLogger: Failed to get application support directory '
            '${SafeDiagnostics.describeError(e)}',
          );
        }
      }

      if (logPath != null) {
        AppLogger.setLogPath(logPath);
        stderr.writeln('AppLogger: Configured log path');
      } else {
        stderr.writeln(
          'AppLogger: WARNING - Could not determine log path, using default',
        );
      }
    } catch (e) {
      stderr.writeln(
        'AppLogger: Error setting custom log path '
        '${SafeDiagnostics.describeError(e)}',
      );
    }

    await AppLogger.initialize();

    final logPath = AppLogger.getLogPath();
    // initialize already made the first secure claim. This explicit handoff is
    // also the retry point if native loading was temporarily unavailable.
    if (!AppLogger.handoffToNative()) {
      stderr.writeln(
        'origin=logger file_sink=unavailable buffer=bounded_memory',
      );
    }
    AppLogger.log('Application starting...');

    setNativeLibraryName('tim2tox_ffi');
    AppLogger.log(
      '[LoggingBootstrap] BINARY REPLACEMENT MODE: Using NativeLibraryManager with tim2tox_ffi',
    );

    // iOS: mark the log directory excluded from iCloud / iTunes backups.
    // Logs are operational scratch data; they should not appear in user
    // backups. No-op on every other platform.
    if (logPath != null) {
      try {
        final logDir = File(logPath).parent.path;
        await AppPaths.markExcludedFromBackup(logDir);
      } catch (e) {
        SafeDiagnostics.logFailure(
          'Could not mark log directory excluded from backup',
          e,
        );
      }
    }
  }
}
