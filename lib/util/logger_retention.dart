import 'dart:io';

/// The existing app_*.log retention policy, including rotated segments.
/// Synchronous at rotation so repeated writes cannot queue unbounded pruning.
abstract final class LoggerRetention {
  static void prune(File current, {required int maximumFiles}) {
    if (!current.parent.existsSync()) return;
    final files = current.parent
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) {
          final name = file.uri.pathSegments.last;
          return name.startsWith('app_') && name.endsWith('.log');
        })
        .toList();
    if (files.length <= maximumFiles) return;
    final modified = <String, DateTime>{};
    for (final file in files) {
      try {
        modified[file.path] = file.statSync().modified;
      } catch (_) {
        modified[file.path] = DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    files.sort((a, b) => modified[b.path]!.compareTo(modified[a.path]!));
    var kept = 0;
    for (final file in files) {
      bool isCurrent;
      try {
        isCurrent = FileSystemEntity.identicalSync(file.path, current.path);
      } catch (_) {
        isCurrent = file.path == current.path;
      }
      if (isCurrent) continue;
      if (kept < maximumFiles - 1) {
        kept++;
      } else {
        try {
          file.deleteSync();
        } catch (_) {
          /* Locked or already removed. */
        }
      }
    }
  }
}
