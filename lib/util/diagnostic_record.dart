import 'dart:async';
import 'dart:io';

/// Origins are closed metadata, never caller-supplied operation/body strings.
enum DiagnosticOrigin { application, framework, dispatcher, zone, logger }

/// The production log boundary: no error value, context, URL or arbitrary body.
/// Never evaluates caller-controlled Type/StackTrace objects. Coordinates come
/// from StackTrace.current inside this boundary: they identify the capture point,
/// not the original throwing frame. Original exception stacks remain debug-only.
final class DiagnosticRecord {
  DiagnosticRecord.capture(this.origin, Object? error)
    : errorType = errorCategory(error),
      frames = _captureFrames();

  final DiagnosticOrigin origin;
  final String errorType;
  final List<String> frames;

  String get body =>
      'origin=${origin.name} error_type=$errorType stack=capture_point';

  /// Static categories do not read a virtual runtimeType getter or render Type.
  static String errorCategory(Object? error) {
    if (error == null) return 'unspecified';
    if (error is RangeError) return 'RangeError';
    if (error is ArgumentError) return 'ArgumentError';
    if (error is StateError) return 'StateError';
    if (error is FormatException) return 'FormatException';
    if (error is FileSystemException) return 'FileSystemException';
    if (error is TimeoutException) return 'TimeoutException';
    if (error is UnsupportedError) return 'UnsupportedError';
    if (error is UnimplementedError) return 'UnimplementedError';
    if (error is TypeError) return 'TypeError';
    if (error is IOException) return 'IOException';
    if (error is Exception) return 'Exception';
    if (error is Error) return 'Error';
    return 'unknown';
  }

  static List<String> _captureFrames() {
    final stack = StackTrace.current;
    final sourceFrame = RegExp(
      r'^#\d+\s+.*\(((?:package:[a-z_][a-z0-9_]*/[A-Za-z0-9_./-]+\.dart|dart:[A-Za-z0-9_./-]+)(?::[0-9]+){1,2})\)$',
    );
    final aotFrame = RegExp(
      r'^\s*#\d+\s+abs\s+[0-9a-fA-F]+\s+virt\s+[0-9a-fA-F]+(?:\s+_kDart(?:Isolate|Vm)SnapshotInstructions\+0x[0-9a-fA-F]+)?\s*$',
    );
    final aotPlatform = RegExp(
      r'^os: (?:android|ios|macos|linux|windows) arch: (?:arm|arm64|ia32|x64|riscv32|riscv64) comp: (?:yes|no) sim: (?:yes|no)$',
    );
    const aotStart =
        '*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***';
    final aotBase = RegExp(
      r'^isolate_dso_base: [0-9a-fA-F]+, vm_dso_base: [0-9a-fA-F]+$',
    );
    final aotInstructions = RegExp(
      r'^isolate_instructions: [0-9a-fA-F]+, vm_instructions: [0-9a-fA-F]+$',
    );
    final buildId = RegExp(r"^build_id: '[0-9a-fA-F]+'$");
    final frames = <String>[];
    for (final line in stack.toString().split('\n')) {
      final source = sourceFrame.firstMatch(line);
      if (source != null) {
        // Keep source locations, not arbitrary function display text.
        frames.add('at ${source.group(1)}');
      } else if (line == aotStart ||
          aotPlatform.hasMatch(line) ||
          aotFrame.hasMatch(line) ||
          aotBase.hasMatch(line) ||
          aotInstructions.hasMatch(line) ||
          buildId.hasMatch(line)) {
        frames.add(line.trim());
      }
      if (frames.length == 24) break;
    }
    return List.unmodifiable(frames);
  }
}
