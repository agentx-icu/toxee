import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

import '../util/app_paths.dart';
import '../util/logger.dart';

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

  static Future<void> initialize() async {
    final logDirEnv = Platform.environment['TOXEE_LOG_DIR'];
    try {
      String? logPath;
      bool useSymlink = false;
      // (1) Dev-loop branch: `flutter_client.log` filename is required so
      // `run_toxee.sh`'s `tail -F` keeps working.
      if (logDirEnv != null && logDirEnv.isNotEmpty) {
        final testPath = p.join(logDirEnv, 'flutter_client.log');
        try {
          final testFile = File(testPath);
          final testDir = testFile.parent;
          if (!testDir.existsSync()) {
            testDir.createSync(recursive: true);
          }
          testFile.writeAsStringSync('test', mode: FileMode.write);
          testFile.deleteSync();
          logPath = testPath;
          stderr.writeln('AppLogger: Using log directory from environment: $logDirEnv');
        } catch (e) {
          stderr.writeln(
              'AppLogger: [INFO] Cannot write to project directory due to sandbox restrictions (expected): $logDirEnv');
          stderr.writeln(
              'AppLogger: [INFO] Will use application support directory and create symlink');
          useSymlink = true;
        }
      }

      // (1, cont.) Second dev-loop branch: `Directory.current/build/flutter_client.log`.
      // Same flat filename for the same reason. Desktop-only: on iOS/Android the
      // process working directory is `/` (read-only), so this probe always fails
      // and only emits a misleading stderr error before the appSupport fallback
      // below takes over — skip it on mobile and go straight to branch (2).
      if (logPath == null &&
          !useSymlink &&
          !Platform.isIOS &&
          !Platform.isAndroid) {
        try {
          final currentDir = Directory.current;
          final testPath = p.join(currentDir.path, 'build', 'flutter_client.log');
          final testFile = File(testPath);
          final testDir = testFile.parent;
          if (testDir.existsSync() || testDir.parent.existsSync()) {
            try {
              testFile.writeAsStringSync('test', mode: FileMode.write);
              testFile.deleteSync();
              logPath = testPath;
              stderr.writeln('AppLogger: Using Directory.current: ${currentDir.path}');
            } catch (e) {
              stderr.writeln('AppLogger: Cannot write to Directory.current: $e');
              useSymlink = true;
            }
          }
        } catch (e) {
          // Directory.current might not work in app bundle — fall through to
          // the symlink/timestamped fallback. Logger isn't initialised yet so
          // stderr is the best we can do, but the fallback path is the
          // canonical case so loud logging here would be noisy.
          stderr.writeln('AppLogger: Directory.current probe failed: $e');
        }
      }

      // (2) Production / fallback branch: timestamped path under
      // `<appSupport>/logs/`. This is the canonical convention.
      if (logPath == null || useSymlink) {
        try {
          logPath = await AppPaths.logFilePath;
          stderr.writeln(
              'AppLogger: Using application support directory: ${await AppPaths.applicationSupportPath}');
          if (useSymlink && logDirEnv != null && logDirEnv.isNotEmpty) {
            stderr.writeln(
                'AppLogger: [INFO] Cannot create symlink from sandbox (expected - macOS security restriction)');
            stderr.writeln('AppLogger: [INFO] Logs will be in: $logPath');
            stderr.writeln(
                'AppLogger: [INFO] Script will create symlink: $logDirEnv/flutter_client.log -> $logPath');
          }
        } catch (e) {
          stderr.writeln('AppLogger: Failed to get application support directory: $e');
        }
      }

      if (logPath != null) {
        AppLogger.setLogPath(logPath);
        stderr.writeln('AppLogger: Set log path to: $logPath');
      } else {
        stderr.writeln('AppLogger: WARNING - Could not determine log path, using default');
      }
    } catch (e, stackTrace) {
      stderr.writeln('AppLogger: Error setting custom log path: $e');
      stderr.writeln('AppLogger: Stack trace: $stackTrace');
    }

    await AppLogger.initialize();

    final logPath = AppLogger.getLogPath();
    if (logPath != null) {
      try {
        final logFile = File(logPath);
        logFile.writeAsStringSync('=== Test Write ===\n', mode: FileMode.append);
        stderr.writeln('AppLogger: Test write successful to: $logPath');
        AppLogger.log('AppLogger initialized, log file: $logPath');
        AppLogger.log('AppLogger: Log file exists and is ready');
      } catch (e, stackTrace) {
        stderr.writeln('AppLogger: ERROR - Failed to write to log file: $e');
        stderr.writeln('AppLogger: Stack trace: $stackTrace');
        stderr.writeln('AppLogger: Log file path: $logPath');
      }
    } else {
      stderr.writeln('AppLogger: WARNING - Log file path is null after initialization');
    }
    AppLogger.log('Application starting...');

    if (logPath != null) {
      try {
        final ffiLib = Tim2ToxFfi.open();
        ffiLib.setLogFile(logPath);
      } catch (e) {
        AppLogger.warn('Could not set C++ log file: $e');
      }
    }

    setNativeLibraryName('tim2tox_ffi');
    AppLogger.log(
        '[LoggingBootstrap] BINARY REPLACEMENT MODE: Using NativeLibraryManager with tim2tox_ffi');

    // iOS: mark the log directory excluded from iCloud / iTunes backups.
    // Logs are operational scratch data; they should not appear in user
    // backups. No-op on every other platform.
    if (logPath != null) {
      try {
        final logDir = File(logPath).parent.path;
        await AppPaths.markExcludedFromBackup(logDir);
      } catch (e) {
        AppLogger.warn('Could not mark log directory excluded from backup: $e');
      }
    }
  }
}
