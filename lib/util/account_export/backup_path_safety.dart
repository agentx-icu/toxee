import 'package:path/path.dart' as p;

/// Resolves a backup archive entry's [relativePath] against [baseDir] and
/// rejects anything that would escape the base directory (path traversal).
///
/// Backup zips are untrusted input — a crafted entry like `../../etc/foo` or an
/// absolute path could otherwise let an import write outside the account's data
/// directory. Throws if the path contains `\\` or `:`, normalizes to `.`/`..`,
/// is absolute, or resolves outside [baseDir]. Returns the safe absolute target
/// path otherwise.
String safeBackupRestorePath({
  required String baseDir,
  required String relativePath,
}) {
  if (relativePath.contains('\\')) {
    throw Exception('Unsafe backup path: $relativePath');
  }
  if (relativePath.contains(':')) {
    throw Exception('Unsafe backup path: $relativePath');
  }

  final normalizedRelative = p.url.normalize(relativePath);
  if (normalizedRelative == '.' ||
      normalizedRelative == '..' ||
      normalizedRelative.startsWith('../') ||
      p.url.isAbsolute(normalizedRelative)) {
    throw Exception('Unsafe backup path: $relativePath');
  }

  final normalizedBase = p.normalize(p.absolute(baseDir));
  final targetPath = p.normalize(
    p.joinAll(<String>[
      normalizedBase,
      ...p.url.split(normalizedRelative),
    ]),
  );
  if (targetPath != normalizedBase && !p.isWithin(normalizedBase, targetPath)) {
    throw Exception('Unsafe backup path: $relativePath');
  }
  return targetPath;
}
