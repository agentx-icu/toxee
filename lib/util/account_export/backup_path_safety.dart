import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Why [safeBackupRestorePath] refused a backup archive entry.
///
/// Carried by [UnsafeBackupPathException] so callers, tests and logs can tell
/// the rejection modes apart *without* being handed the offending path.
enum UnsafeBackupPathReason {
  /// Contains `\`: a Windows separator, or the `\\server\share` UNC prefix.
  /// Rejected on every host so a Windows-authored zip behaves identically when
  /// it is restored on macOS/Linux/iOS/Android.
  backslash,

  /// Contains `:`: a `C:` drive letter, an NTFS alternate data stream
  /// (`notes.json:hidden`), or a URI scheme (`file://`, `http://`).
  colon,

  /// Normalises to `.`, i.e. it names the base directory itself rather than an
  /// entry inside it. Covers the empty string and things like `a/..`.
  normalizesToBase,

  /// Escapes the base directory through `..`.
  parentTraversal,

  /// An absolute path, which would discard the base directory entirely.
  absolute,

  /// Resolved outside the base directory. Defence in depth — see the note at
  /// the containment check in [safeBackupRestorePath].
  outsideBase,
}

/// Thrown by [safeBackupRestorePath] when a backup archive entry would be
/// written outside the account's data directory.
///
/// PRIVACY: this exception never carries the rejected path. Backup entry names
/// are derived from peer identities (`avatars/<peer>.png`,
/// `chat_history/<peer>.json`), so interpolating one into a message would push
/// a contact identifier into logs and user-visible errors — exactly what
/// `test/util/account_privacy_boundary_source_test.dart` exists to prevent.
/// What is kept instead is enough to triage a report: the rejection [reason],
/// the [pathLength], and a truncated one-way [pathFingerprint] that lets two
/// occurrences of the same crafted entry be correlated.
class UnsafeBackupPathException implements Exception {
  UnsafeBackupPathException(this.reason, String relativePath)
      : pathLength = relativePath.length,
        pathFingerprint = _fingerprint(relativePath);

  /// Why the path was refused.
  final UnsafeBackupPathReason reason;

  /// Length in UTF-16 code units of the rejected entry name.
  final int pathLength;

  /// First 12 hex digits of the SHA-256 of the rejected entry name.
  final String pathFingerprint;

  /// Kept prefixed with `Unsafe backup path` because the service-level import
  /// tests match on that substring rather than on the type.
  String get message =>
      'Unsafe backup path rejected (reason=${reason.name}, '
      'len=$pathLength, fp=$pathFingerprint)';

  @override
  String toString() => 'UnsafeBackupPathException: $message';
}

String _fingerprint(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 12);

/// Resolves a backup archive entry's [relativePath] against [baseDir] and
/// rejects anything that would escape the base directory (path traversal).
///
/// Backup zips are untrusted input — a crafted entry like `../../etc/foo` or an
/// absolute path could otherwise let an import write outside the account's data
/// directory. Throws [UnsafeBackupPathException] if the path contains `\` or
/// `:`, normalizes to `.`/`..`, is absolute, or resolves outside [baseDir].
/// Returns the safe absolute target path otherwise.
String safeBackupRestorePath({
  required String baseDir,
  required String relativePath,
}) {
  if (relativePath.contains('\\')) {
    throw UnsafeBackupPathException(
      UnsafeBackupPathReason.backslash,
      relativePath,
    );
  }
  if (relativePath.contains(':')) {
    throw UnsafeBackupPathException(
      UnsafeBackupPathReason.colon,
      relativePath,
    );
  }

  final normalizedRelative = p.url.normalize(relativePath);
  if (normalizedRelative == '.') {
    throw UnsafeBackupPathException(
      UnsafeBackupPathReason.normalizesToBase,
      relativePath,
    );
  }
  if (normalizedRelative == '..' || normalizedRelative.startsWith('../')) {
    throw UnsafeBackupPathException(
      UnsafeBackupPathReason.parentTraversal,
      relativePath,
    );
  }
  if (p.url.isAbsolute(normalizedRelative)) {
    throw UnsafeBackupPathException(
      UnsafeBackupPathReason.absolute,
      relativePath,
    );
  }

  final normalizedBase = p.normalize(p.absolute(baseDir));
  final targetPath = p.normalize(
    p.joinAll(<String>[
      normalizedBase,
      ...p.url.split(normalizedRelative),
    ]),
  );
  // `p.isWithin` is strict containment: it is false when `targetPath` equals
  // `normalizedBase`. That case is already unreachable here — `normalizedRelative`
  // is a normalised, non-absolute, non-`.`, non-`..`-leading path, so every one
  // of its segments is a real name and `targetPath` is strictly deeper than the
  // base. The check used to be guarded by `targetPath != normalizedBase`, which
  // only ever *weakened* it (it would have let "the base itself" through), so
  // that dead disjunct was removed rather than kept. What remains is the single
  // authoritative containment assertion, retained as defence in depth against a
  // future change to the checks above or to `package:path` normalisation.
  if (!p.isWithin(normalizedBase, targetPath)) {
    throw UnsafeBackupPathException(
      UnsafeBackupPathReason.outsideBase,
      relativePath,
    );
  }
  return targetPath;
}
