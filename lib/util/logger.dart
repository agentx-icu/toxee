import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'diagnostic_record.dart';
import 'logger_retention.dart';

/// Log levels for unified format (matches C++ V2TIMLog).
enum LogLevel { debug, info, warn, error, fatal }

class AppLogger {
  static int _sequence = 0;
  static bool _production = !kDebugMode;
  static const _maxEarlyRecords = 32;
  static final _earlyRecords = <DiagnosticRecord>[];
  static int _droppedEarlyRecords = 0;
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

  static const String _tid =
      'main'; // Dart main isolate; use Isolate.current.debugName if needed

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

  static void closeLogSinkForDeletion() {
    _logFile = null;
    _initialized = false;
    _hasLoggedError = false;
    _currentLogBytes = 0;
    _rotationIndex = 0;
    _sessionTimestamp = null;
  }

  static Future<void> openFreshLogSink(String path) async {
    closeLogSinkForDeletion();
    _customLogPath = path;
    _enableFileLogging = true;
    await _initialize(verifySink: true);
  }

  @visibleForTesting
  static void resetForTesting({bool production = false}) {
    _production = !kDebugMode || production;
    _earlyRecords.clear();
    _droppedEarlyRecords = 0;
    _sequence = 0;
    _enableFileLogging = true;
    _enableConsoleLogging = false;
    _logFile = null;
    _initialized = false;
    _customLogPath = null;
    _hasLoggedError = false;
    _currentLogBytes = 0;
    _rotationIndex = 0;
    _sessionTimestamp = null;
  }

  static Future<void> initialize() async {
    try {
      await _initialize();
    } catch (e) {
      _internalFailure(e);
      _enableFileLogging = false;
    }
  }

  static Future<void> _initialize({bool verifySink = false}) async {
    if (_initialized) return;
    if (_enableFileLogging) {
      if (_customLogPath != null) {
        final logFile = File(_customLogPath!);
        final logDir = logFile.parent;
        if (!await logDir.exists()) {
          await logDir.create(recursive: true);
        }
        _logFile = logFile;
        // LoggingBootstrap supplies the canonical timestamped path explicitly.
        // It must receive the same rotation policy as the implicit default.
        final timestamp = RegExp(
          r'^app_([0-9]+)\.log$',
        ).firstMatch(logFile.uri.pathSegments.last)?.group(1);
        if (timestamp != null) {
          _sessionTimestamp = DateTime.fromMillisecondsSinceEpoch(
            int.parse(timestamp),
          );
        }
        if (!_production) {
          stderr.writeln('AppLogger: Log file initialized at: ${logFile.path}');
        }
      } else {
        final logDir = await AppPaths.logsDir;
        if (!await logDir.exists()) {
          await logDir.create(recursive: true);
        }
        _sessionTimestamp = DateTime.now();
        final timestamp = _sessionTimestamp!.millisecondsSinceEpoch;
        _logFile = File('${logDir.path}/app_$timestamp.log');
      }
      const startMarker = '=== App Log Started ===\n';
      final logFile = _logFile!;
      final previousLength = verifySink && await logFile.exists()
          ? await logFile.length()
          : 0;
      await logFile.writeAsString(
        startMarker,
        mode: FileMode.append,
        flush: verifySink,
      );
      _currentLogBytes = verifySink
          ? await _verifySinkWrite(
              logFile,
              minimumLength: previousLength + startMarker.length,
            )
          : await _safeFileLength(logFile);

      // P11: clean up old log files. Keep the most recent [_maxLogFiles]
      // app_*.log files; never delete the file we just opened.
      await _pruneOldLogFiles();
    }
    _initialized = true;
    final early = List<DiagnosticRecord>.of(_earlyRecords);
    _earlyRecords.clear();
    for (final record in early) {
      _writeDiagnostic(record);
    }
    if (_droppedEarlyRecords != 0) {
      _emitTrusted(
        LogLevel.warn,
        'origin=logger early_records_dropped=$_droppedEarlyRecords',
      );
      _droppedEarlyRecords = 0;
    }
  }

  static Future<int> _verifySinkWrite(
    File file, {
    required int minimumLength,
  }) async {
    if (!await file.exists()) {
      throw FileSystemException('Fresh log sink was not created', file.path);
    }
    final length = await file.length();
    if (length < minimumLength) {
      throw FileSystemException(
        'Fresh log sink did not persist the startup marker',
        file.path,
      );
    }
    return length;
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

  static Future<void> _pruneOldLogFiles() async {
    final current = _logFile;
    if (current == null) return;
    try {
      LoggerRetention.prune(current, maximumFiles: _maxLogFiles);
    } catch (e) {
      _internalFailure(e);
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
      next.writeAsStringSync(
        '=== App Log Rotated (segment $_rotationIndex) ===\n',
        mode: FileMode.append,
      );
      _logFile = next;
      _currentLogBytes = next.lengthSync();
      LoggerRetention.prune(next, maximumFiles: _maxLogFiles);
    } catch (e) {
      _internalFailure(e);
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
        stderr.writeln(
          'AppLogger: Log file is null, cannot write. Call initialize() first.',
        );
      }
      return;
    }
    try {
      final bytes = '$line\n';
      _logFile!.writeAsStringSync(bytes, mode: FileMode.append);
      _currentLogBytes = _logFile!.lengthSync();
      _rotateIfNeeded();
      _hasLoggedError = false;
    } catch (e, stackTrace) {
      if (!_hasLoggedError) {
        _hasLoggedError = true;
        _internalFailure(e);
        if (!_production) {
          stderr.writeln(stackTrace);
        }
      }
    }
  }

  static void _internalFailure(Object error) {
    // Never call the logger from its own failed sink; this cannot recurse.
    stderr.writeln(
      DiagnosticRecord.capture(DiagnosticOrigin.logger, error, null).body,
    );
  }

  /// Captures only bounded safe metadata even before the file sink is ready.
  static void recordError(
    DiagnosticOrigin origin,
    Object? error,
    StackTrace? stack,
  ) {
    final record = DiagnosticRecord.capture(origin, error, stack);
    if (!_initialized) {
      if (_earlyRecords.length < _maxEarlyRecords) {
        _earlyRecords.add(record);
      } else {
        _droppedEarlyRecords++;
      }
      return;
    }
    _writeDiagnostic(record);
  }

  static void _writeDiagnostic(DiagnosticRecord record) {
    _emitTrusted(LogLevel.error, record.body);
    for (final frame in record.frames) {
      _emitTrusted(LogLevel.error, frame);
    }
  }

  static void _emit(LogLevel level, String body) {
    if (_production) {
      if (level.index >= LogLevel.warn.index) {
        _emitTrusted(level, 'origin=application body=omitted');
      }
      return;
    }
    _emitTrusted(level, body);
  }

  static void _emitTrusted(LogLevel level, String body) {
    final formatted = _formatLine(level, body);
    if (_enableConsoleLogging) {
      // Terminal sink: main's print router must not consume our output again.
      // Even root-zone debugPrint would join Flutter's shared throttle queue,
      // whose pending timer may belong to the routed app zone. Console logging
      // is opt-in; direct debug output trades throttling for exactly-once logs.
      Zone.root.print(formatted);
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
  static void logError(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (_production) {
      recordError(DiagnosticOrigin.application, error, stackTrace);
      return;
    }
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
      if (error != null) {
        Zone.root.print('Error: $error');
      }
      if (stackTrace != null) {
        Zone.root.print(stackTrace.toString());
      }
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
