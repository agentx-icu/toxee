import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

import 'app_paths.dart';
import 'diagnostic_record.dart';
import 'native_log_bridge.dart';
import 'owned_log_sink.dart';

/// Log levels for unified format (matches C++ V2TIMLog).
enum LogLevel { debug, info, warn, error, fatal }

class AppLogger {
  static int _sequence = 0;
  static void Function(String) _consoleWriter = Zone.root.print;
  static void Function(String) _errorWriter = stderr.writeln;
  static bool _writingStderr = false;
  static bool _production = !kDebugMode;
  static const _maxEarlyRecords = 32;
  static final _earlyRecords = <DiagnosticRecord>[];
  static int _droppedEarlyRecords = 0;
  static final int _pid = _getPid();
  static bool _enableFileLogging = true;
  static bool _enableConsoleLogging = false;
  static String? _logPath;
  static OwnedLogSink _fileSink = OwnedLogSink();
  static NativeLogBridge? _nativeBridge;
  static bool _initialized = false;
  static Future<void>? _initializing;
  static int _sinkEpoch = 0;
  static String? _customLogPath;

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
    _sinkEpoch++;
    _initializing = null;
    // Throws before a caller can delete any logs if native cannot confirm close.
    _fileSink.close();
    _logPath = null;
    _initialized = false;
  }

  static Future<void> openFreshLogSink(String path) async {
    closeLogSinkForDeletion();
    final epoch = _sinkEpoch;
    _customLogPath = path;
    _enableFileLogging = true;
    await _initialize();
    if (epoch != _sinkEpoch || !_fileSink.ownsFile) {
      throw StateError('Fresh native log sink could not be established');
    }
  }

  @visibleForTesting
  static void resetForTesting({
    bool production = false,
    void Function(String)? consoleWriter,
    void Function(String)? errorWriter,
  }) {
    _sinkEpoch++;
    _initializing = null;
    _fileSink.discardMemory();
    _fileSink = OwnedLogSink();
    _nativeBridge = null;
    _consoleWriter = consoleWriter ?? Zone.root.print;
    _errorWriter = errorWriter ?? stderr.writeln;
    _production = !kDebugMode || production;
    _earlyRecords.clear();
    _droppedEarlyRecords = 0;
    _sequence = 0;
    _enableFileLogging = true;
    _enableConsoleLogging = false;
    _logPath = null;
    _initialized = false;
    _customLogPath = null;
  }

  static Future<void> initialize() async {
    final epoch = _sinkEpoch;
    try {
      await _initialize();
    } catch (e) {
      if (epoch != _sinkEpoch) return;
      _internalFailure(e);
      // Directory/native failure must not silently disable the bounded memory
      // sink. It performs no IO and cannot bypass the failed path validation.
      _completeInitialization();
    }
  }

  static Future<void> _initialize() {
    if (_initialized) return Future.value();
    final pending = _initializing;
    if (pending != null) return pending;
    final task = _initializeSink(_sinkEpoch);
    _initializing = task;
    return task.whenComplete(() {
      if (identical(_initializing, task)) _initializing = null;
    });
  }

  static Future<void> _initializeSink(int epoch) async {
    if (_enableFileLogging) {
      final path = _customLogPath ?? await AppPaths.logFilePath;
      if (epoch != _sinkEpoch) return;
      // Resolve legitimate OS/container aliases on the established parent only.
      // Never resolve or probe the leaf: native rejects leaf links/hard links
      // and owns the validated physical directory handle for all later writes.
      final log = File(path).absolute;
      await log.parent.create(recursive: true);
      final parent = await log.parent.resolveSymbolicLinks();
      if (epoch != _sinkEpoch) return;
      _fileSink.begin();
      _logPath = p.join(parent, p.basename(log.path));
      _fileSink.append('=== App Log Started ===\n');
      if (!handoffToNative()) {
        _writeStderr(
          'origin=logger file_sink=unavailable buffer=bounded_memory',
        );
      }
    }
    _completeInitialization();
  }

  static void _completeInitialization() {
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

  /// Explicitly retries a safe handoff after an unavailable native library.
  /// Until it succeeds, at most 32 bounded records remain in memory and process
  /// death can lose them. No Dart file writer bypasses native path validation.
  static bool handoffToNative() {
    final path = _logPath;
    if (!_enableFileLogging || path == null) return false;
    if (_fileSink.ownsFile) return true;
    try {
      final bridge = _nativeBridge ??= Tim2ToxLogBridge(Tim2ToxFfi.open());
      return _fileSink.handoff(bridge, path);
    } catch (error) {
      _internalFailure(error);
      return false;
    }
  }

  static void setFileLoggingEnabled(bool enabled) {
    if (!enabled) {
      _sinkEpoch++;
      _initializing = null;
      _fileSink.close();
    }
    _enableFileLogging = enabled;
    if (enabled && _logPath != null) handoffToNative();
  }

  static void setConsoleLoggingEnabled(bool enabled) {
    _enableConsoleLogging = enabled;
  }

  static String? getLogPath() {
    return _fileSink.ownsFile ? _logPath : null;
  }

  static void _writeToFile(String line) {
    if (!_enableFileLogging) return;
    _fileSink.append('$line\n');
  }

  static void _writeStderr(String message) {
    if (_writingStderr) return;
    _writingStderr = true;
    try {
      _errorWriter(message);
    } catch (_) {
      /* No recursive fallback. */
    } finally {
      _writingStderr = false;
    }
  }

  static void _writeConsole(String message) {
    try {
      _consoleWriter(message);
    } catch (error) {
      _enableConsoleLogging = false;
      _internalFailure(error);
    }
  }

  static void _internalFailure(Object error) {
    // Never call the logger from its own failed sink; this cannot recurse.
    _writeStderr(DiagnosticRecord.capture(DiagnosticOrigin.logger, error).body);
  }

  /// Captures only bounded safe metadata even before the file sink is ready.
  static void recordError(
    DiagnosticOrigin origin,
    Object? error,
    StackTrace? stack,
  ) {
    final record = DiagnosticRecord.capture(origin, error);
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
      _writeConsole(formatted);
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
        _writeConsole('Error: $error');
      }
      if (stackTrace != null) {
        _writeConsole(stackTrace.toString());
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
