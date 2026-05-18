import 'dart:io';
import 'package:flutter/foundation.dart';
import 'app_paths.dart';

/// Log levels for unified format (matches C++ V2TIMLog).
enum LogLevel {
  debug,
  info,
  warn,
  error,
  fatal,
}

class AppLogger {
  static int _sequence = 0;
  static final int _pid = _getPid();
  static bool _enableFileLogging = true;
  static bool _enableConsoleLogging = false;
  static File? _logFile;
  static bool _initialized = false;
  static String? _customLogPath;
  static bool _hasLoggedError = false;

  /// P11 (`local-storage-review-2026-05-18.md`): the logger creates a new
  /// `app_<timestamp>.log` per launch. Without bounds the `logs/` directory
  /// grows for the lifetime of the install. We keep the most recent N files
  /// and within a session rotate when the current file exceeds [_maxLogBytes].
  static const int _maxLogFiles = 10;
  static const int _maxLogBytes = 10 * 1024 * 1024; // 10 MB
  static int _currentLogBytes = 0;
  static int _rotationIndex = 0;
  static DateTime? _sessionTimestamp;

  static const String _tid = 'main'; // Dart main isolate; use Isolate.current.debugName if needed

  static int _getPid() {
    try {
      return pid;
    } catch (e) {
      return 0;
    }
  }

  static String _formatTime(DateTime now) {
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  /// Unified format: [pid-tid-seqno] YYYY-MM-DD HH:MM:SS [LEVEL] body
  static String _formatLine(LogLevel level, String body) {
    _sequence++;
    final seq = _sequence.toString();
    final now = DateTime.now();
    final timeStr = _formatTime(now);
    const levelStr = {
      LogLevel.debug: 'DEBUG',
      LogLevel.info: 'INFO',
      LogLevel.warn: 'WARN',
      LogLevel.error: 'ERROR',
      LogLevel.fatal: 'FATAL',
    };
    return '[$_pid-$_tid-$seq] $timeStr [${levelStr[level]}] $body';
  }

  static void setLogPath(String? path) {
    _customLogPath = path;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (_enableFileLogging) {
        if (_customLogPath != null) {
          final logFile = File(_customLogPath!);
          final logDir = logFile.parent;
          if (!await logDir.exists()) {
            await logDir.create(recursive: true);
          }
          _logFile = logFile;
          stderr.writeln('AppLogger: Log file initialized at: ${logFile.path}');
          stderr.writeln('AppLogger: Log directory exists: ${await logDir.exists()}');
        } else {
          final logDir = await AppPaths.logsDir;
          if (!await logDir.exists()) {
            await logDir.create(recursive: true);
          }
          _sessionTimestamp = DateTime.now();
          final timestamp = _sessionTimestamp!.millisecondsSinceEpoch;
          _logFile = File('${logDir.path}/app_$timestamp.log');
        }
        await _logFile!.writeAsString('=== App Log Started ===\n', mode: FileMode.append);
        _currentLogBytes = await _safeFileLength(_logFile!);

        // P11: clean up old log files. Keep the most recent [_maxLogFiles]
        // app_*.log files; never delete the file we just opened.
        await _pruneOldLogFiles();
      }
      _initialized = true;
    } catch (e) {
      stderr.writeln('Warning: Failed to initialize file logging: $e');
      _enableFileLogging = false;
    }
  }

  /// Length of [file] in bytes, or 0 if it does not exist / cannot be stat'd.
  static Future<int> _safeFileLength(File file) async {
    try {
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {
      // Ignore stat failures; treat as zero.
    }
    return 0;
  }

  /// P11: Delete the oldest `app_*.log` files in the same directory as the
  /// current log, keeping only the most recent [_maxLogFiles] entries by
  /// modification time. Never deletes the currently open log file.
  static Future<void> _pruneOldLogFiles() async {
    final current = _logFile;
    if (current == null) return;
    try {
      final dir = current.parent;
      if (!await dir.exists()) return;

      final logFiles = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : entity.path.split(Platform.pathSeparator).last;
        if (!name.startsWith('app_') || !name.endsWith('.log')) continue;
        logFiles.add(entity);
      }
      if (logFiles.length <= _maxLogFiles) return;

      // Sort by mtime descending (newest first). Files that fail to stat
      // sort to the back so they're the first candidates for deletion.
      final stats = <File, DateTime>{};
      for (final f in logFiles) {
        try {
          stats[f] = (await f.stat()).modified;
        } catch (_) {
          stats[f] = DateTime.fromMillisecondsSinceEpoch(0);
        }
      }
      logFiles.sort((a, b) => stats[b]!.compareTo(stats[a]!));

      final currentPath = current.path;
      var kept = 0;
      for (final f in logFiles) {
        if (f.path == currentPath) {
          kept++;
          continue;
        }
        if (kept < _maxLogFiles) {
          kept++;
          continue;
        }
        try {
          await f.delete();
        } catch (_) {
          // Ignore — file may be locked or already gone.
        }
      }
    } catch (e) {
      stderr.writeln('AppLogger: log pruning failed: $e');
    }
  }

  /// P11: rotate the active log when it exceeds [_maxLogBytes]. Only applies
  /// when a session timestamp is set (i.e., the default `app_<ts>.log` path).
  /// Custom paths (CI / test) keep the previous append-forever behaviour.
  static void _rotateIfNeeded() {
    if (_sessionTimestamp == null) return;
    final current = _logFile;
    if (current == null) return;
    if (_currentLogBytes < _maxLogBytes) return;
    try {
      final dir = current.parent;
      _rotationIndex++;
      final timestamp = _sessionTimestamp!.millisecondsSinceEpoch;
      final next = File('${dir.path}/app_${timestamp}_$_rotationIndex.log');
      _logFile = next;
      _currentLogBytes = 0;
      try {
        next.writeAsStringSync(
          '=== App Log Rotated (segment $_rotationIndex) ===\n',
          mode: FileMode.append,
        );
      } catch (_) {
        // Ignore; the next _writeToFile will surface the error path.
      }
    } catch (e) {
      stderr.writeln('AppLogger: log rotation failed: $e');
    }
  }

  static void setFileLoggingEnabled(bool enabled) {
    _enableFileLogging = enabled;
  }

  static void setConsoleLoggingEnabled(bool enabled) {
    _enableConsoleLogging = enabled;
  }

  static String? getLogPath() {
    return _logFile?.path;
  }

  static void _writeToFile(String line) {
    if (!_enableFileLogging) return;
    if (_logFile == null) {
      if (!_hasLoggedError) {
        _hasLoggedError = true;
        stderr.writeln('AppLogger: Log file is null, cannot write. Call initialize() first.');
      }
      return;
    }
    try {
      final bytes = '$line\n';
      _logFile!.writeAsStringSync(bytes, mode: FileMode.append);
      _currentLogBytes += bytes.length;
      _rotateIfNeeded();
      _hasLoggedError = false;
    } catch (e, stackTrace) {
      if (!_hasLoggedError) {
        _hasLoggedError = true;
        stderr.writeln('AppLogger: Failed to write to log file: $e');
        stderr.writeln('AppLogger: Log file path: ${_logFile?.path}');
        for (final line in stackTrace.toString().split('\n')) {
          if (line.trim().isNotEmpty) stderr.writeln('AppLogger:   $line');
        }
      }
    }
  }

  static void _emit(LogLevel level, String body) {
    final formatted = _formatLine(level, body);
    if (_enableConsoleLogging) {
      if (level == LogLevel.debug) {
        debugPrint(formatted);
      } else {
        print(formatted);
      }
    }
    _writeToFile(formatted);
  }

  /// Log at DEBUG level
  static void debug(String message) {
    _emit(LogLevel.debug, message);
  }

  /// Log at INFO level
  static void info(String message) {
    _emit(LogLevel.info, message);
  }

  /// Log at WARN level
  static void warn(String message) {
    _emit(LogLevel.warn, message);
  }

  /// Log at ERROR level (message only)
  static void error(String message) {
    _emit(LogLevel.error, message);
  }

  /// Log at ERROR level with exception and stack trace
  static void logError(String message, [Object? error, StackTrace? stackTrace]) {
    _emit(LogLevel.error, message);
    if (error != null) {
      _emit(LogLevel.error, 'Error: $error');
    }
    if (stackTrace != null) {
      for (final line in stackTrace.toString().split('\n')) {
        if (line.trim().isNotEmpty) _writeToFile('  $line');
      }
    }
    if (_enableConsoleLogging && (error != null || stackTrace != null)) {
      if (error != null) print('Error: $error');
      if (stackTrace != null) debugPrint(stackTrace.toString());
    }
  }

  /// Legacy: log at INFO level (for callers that used log())
  static void log(String message) {
    info(message);
  }

  /// Legacy: log at DEBUG level
  static void debugLog(String message) {
    debug(message);
  }
}
