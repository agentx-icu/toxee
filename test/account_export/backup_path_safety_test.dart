// Unit tests for `lib/util/account_export/backup_path_safety.dart`.
//
// WHY THIS FILE IS WORTH TESTING (security boundary)
// --------------------------------------------------
// `safeBackupRestorePath` is the only thing standing between an untrusted
// backup `.zip` and an arbitrary-filesystem-write primitive. `restore_
// transaction.dart` feeds it *every* `chat_history/…` and `avatars/…` archive
// entry name (twice: once in `_validateArchivePaths`, once in `_stagePayload`)
// and every `@account_data/…` avatar preference, and then writes the returned
// path with `File.writeAsBytes`. A crafted entry named
// `../../../../.ssh/authorized_keys` that survives this function is a full
// account takeover, so every rejection rule below is load-bearing.
//
// The function is purely lexical — it never touches the filesystem — which is
// what makes it cheap to test exhaustively here.
//
// COVERED
//   * `..` traversal in every position (leading, interior, whole-path,
//     normalising back onto the base), absolute paths, `.` and the empty
//     string.
//   * Windows-flavoured escapes (backslash separators, `C:` drive letters,
//     UNC `\\server\share`, NTFS `file:stream`) are rejected on *every* host
//     OS. This is mobile/desktop parity in the literal sense: a zip authored
//     on Windows gets restored on macOS/Linux/iOS/Android, and the platform
//     `p.isWithin` check alone would not catch `..\..` on POSIX.
//   * URI-shaped entries (`http://`, `file://`).
//   * Percent-encoded traversal is *not* decoded — pinned as "treated as a
//     literal path segment", which is precisely what keeps it inside the base.
//   * The accepted-path contract: the result is absolute, normalised, inside
//     `baseDir`, and `/`-separated archive names are re-joined with the host
//     separator.
//   * `baseDir` is absolutised and normalised before containment is checked.
//   * Every rejection is typed (`UnsafeBackupPathException`) and classified
//     (`UnsafeBackupPathReason`), so each case below pins *which* rule fired
//     rather than merely "something threw".
//   * PRIVACY: the rejection carries no raw path. Entry names under
//     `avatars/` and `chat_history/` are derived from peer identities, and
//     `test/util/account_privacy_boundary_source_test.dart` forbids leaking
//     such values into diagnostics — so the exception exposes only a reason, a
//     length and a truncated one-way fingerprint.
//
// NOT COVERED (and why)
//   * `UnsafeBackupPathReason.outsideBase`. It is unreachable by construction:
//     once the `\`, `:`, `.`, `..`-leading and absolute cases are rejected, the
//     normalised remainder consists only of real segment names, so the joined
//     target is always strictly deeper than the base. The containment check is
//     kept as defence in depth (see the comment on it), and inventing an input
//     that "reaches" it would mean asserting a reachability that does not
//     exist. Its absence from this file is deliberate, not an oversight.
//   * Symlinks. The function is lexical and never stats the filesystem, so a
//     pre-existing symlink *inside* `baseDir` is outside its contract; there is
//     nothing here to assert. (The real mitigation is that restore stages into
//     a freshly created directory — that belongs to `restore_transaction`.)
//   * Path-length / filename-length limits. The implementation imposes none;
//     asserting a rejection would invent a guarantee that does not exist. The
//     long-segment test below therefore pins the *actual* behaviour (accepted,
//     still contained) rather than a wished-for one.
//   * NUL bytes / control characters in segment names — not part of the
//     documented contract and not filtered by the implementation.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/util/account_export/backup_path_safety.dart';

/// An absolute, already-normalised base directory. Nothing is created on disk:
/// `safeBackupRestorePath` is purely lexical.
final String _base = p.normalize(
  p.absolute(p.join(Directory.systemTemp.path, 'toxee_backup_path_safety')),
);

/// Asserts both the typed rejection *and* which rule fired. Pinning [reason]
/// is what keeps these cases attributable: without it, a bug that made (say)
/// every input take the `backslash` branch would leave all of them green.
///
/// The `toString()` clause additionally pins the `Unsafe backup path` prefix,
/// which the service-level import tests in `account_export_roundtrip_test.dart`
/// match on by substring.
Matcher _throwsUnsafePath(UnsafeBackupPathReason reason) => throwsA(
  isA<UnsafeBackupPathException>()
      .having(
        (UnsafeBackupPathException e) => e.reason,
        'reason',
        reason,
      )
      .having(
        (UnsafeBackupPathException e) => e.toString(),
        'toString()',
        contains('Unsafe backup path'),
      ),
);

String _resolve(String relativePath, {String? baseDir}) {
  return safeBackupRestorePath(
    baseDir: baseDir ?? _base,
    relativePath: relativePath,
  );
}

void main() {
  group('safeBackupRestorePath accepts contained archive entries', () {
    test('a plain entry name resolves directly under the base directory', () {
      expect(_resolve('conversation.json'), p.join(_base, 'conversation.json'));
    });

    test('slash-separated archive names are re-joined with the host '
        'separator', () {
      // Archive entry names are always `/`-separated regardless of the OS that
      // produced them; the restore target must use the host separator.
      final result = _resolve('2024/07/peer-a.json');
      expect(result, p.join(_base, '2024', '07', 'peer-a.json'));
      expect(p.split(result).length, p.split(_base).length + 3);
    });

    test('interior "." and ".." that stay inside the base are normalised '
        'away', () {
      expect(_resolve('a/./b/../c.json'), p.join(_base, 'a', 'c.json'));
    });

    test('a trailing separator is normalised away', () {
      expect(_resolve('a/b/'), p.join(_base, 'a', 'b'));
    });

    test('percent-encoded traversal is kept as a literal segment, not '
        'decoded', () {
      // If this function ever started URL-decoding, `%2e%2e` would become `..`
      // and escape. Pinning the literal behaviour is what makes the encoded
      // form harmless.
      final result = _resolve('%2e%2e/%2e%2e/etc/passwd');
      expect(result, p.join(_base, '%2e%2e', '%2e%2e', 'etc', 'passwd'));
      expect(p.isWithin(_base, result), isTrue);
    });

    test('segments that merely begin with dots are not traversal', () {
      expect(_resolve('..foo/...bar/.hidden'),
          p.join(_base, '..foo', '...bar', '.hidden'));
    });

    test('an over-long segment is accepted and still contained (no length '
        'limit is enforced)', () {
      final longName = 'a' * 4096;
      final result = _resolve(longName);
      expect(result, p.join(_base, longName));
      expect(p.isWithin(_base, result), isTrue);
    });
  });

  group('safeBackupRestorePath rejects traversal and absolute paths', () {
    test('a leading "../" escapes the base', () {
      expect(
        () => _resolve('../evil.json'),
        _throwsUnsafePath(UnsafeBackupPathReason.parentTraversal),
      );
    });

    test('a deep interior escape is caught after normalisation', () {
      expect(
        () => _resolve('chat/2024/../../../evil.json'),
        _throwsUnsafePath(UnsafeBackupPathReason.parentTraversal),
      );
    });

    test('a bare ".." is rejected', () {
      expect(
        () => _resolve('..'),
        _throwsUnsafePath(UnsafeBackupPathReason.parentTraversal),
      );
    });

    test('"./.." is rejected after normalisation', () {
      expect(
        () => _resolve('./..'),
        _throwsUnsafePath(UnsafeBackupPathReason.parentTraversal),
      );
    });

    test('a bare "." (the base directory itself) is rejected', () {
      expect(
        () => _resolve('.'),
        _throwsUnsafePath(UnsafeBackupPathReason.normalizesToBase),
      );
    });

    test('a path that normalises back onto the base itself is rejected', () {
      // `a/..` normalises to `.`; writing "the base directory" as if it were a
      // file entry is never legitimate.
      expect(
        () => _resolve('a/..'),
        _throwsUnsafePath(UnsafeBackupPathReason.normalizesToBase),
      );
    });

    test('an empty entry name is rejected', () {
      // `p.url.normalize('')` is `.`, so this shares the "names the base
      // directory" rule rather than having a rule of its own.
      expect(
        () => _resolve(''),
        _throwsUnsafePath(UnsafeBackupPathReason.normalizesToBase),
      );
    });

    test('a POSIX absolute path is rejected', () {
      expect(
        () => _resolve('/etc/passwd'),
        _throwsUnsafePath(UnsafeBackupPathReason.absolute),
      );
    });

    test('a bare root separator is rejected', () {
      expect(
        () => _resolve('/'),
        _throwsUnsafePath(UnsafeBackupPathReason.absolute),
      );
    });
  });

  group('safeBackupRestorePath rejects Windows-shaped escapes on every host',
      () {
    test('backslash traversal is rejected', () {
      expect(
        () => _resolve(r'..\..\evil.json'),
        _throwsUnsafePath(UnsafeBackupPathReason.backslash),
      );
    });

    test('a plain backslash separator is rejected', () {
      // On POSIX this would otherwise become a *single* file literally named
      // `sub\file.json`; on Windows it would be a real subdirectory. Rejecting
      // it keeps restore behaviour identical on all five target platforms.
      expect(
        () => _resolve(r'sub\file.json'),
        _throwsUnsafePath(UnsafeBackupPathReason.backslash),
      );
    });

    test('a drive-letter path with backslashes is rejected', () {
      // The backslash rule runs first, so this is classified as `backslash`
      // even though the `:` rule would also have caught it.
      expect(
        () => _resolve(r'C:\Windows\System32\evil.dll'),
        _throwsUnsafePath(UnsafeBackupPathReason.backslash),
      );
    });

    test('a drive-letter path with forward slashes is rejected', () {
      // No backslash here — only the `:` rule catches this one, and it must,
      // because `p.joinAll` on Windows treats `C:/…` as absolute and would
      // discard the base directory entirely.
      expect(
        () => _resolve('C:/Windows/System32/evil.dll'),
        _throwsUnsafePath(UnsafeBackupPathReason.colon),
      );
    });

    test('a UNC share path is rejected', () {
      expect(
        () => _resolve(r'\\server\share\evil.json'),
        _throwsUnsafePath(UnsafeBackupPathReason.backslash),
      );
    });

    test('an NTFS alternate-data-stream suffix is rejected', () {
      expect(
        () => _resolve('notes.json:hidden'),
        _throwsUnsafePath(UnsafeBackupPathReason.colon),
      );
    });
  });

  group('safeBackupRestorePath rejects URI-shaped entries', () {
    test('an http URL is rejected', () {
      expect(
        () => _resolve('http://evil.example/payload'),
        _throwsUnsafePath(UnsafeBackupPathReason.colon),
      );
    });

    test('a file URI is rejected', () {
      expect(
        () => _resolve('file:///etc/passwd'),
        _throwsUnsafePath(UnsafeBackupPathReason.colon),
      );
    });
  });

  group('safeBackupRestorePath normalises the base directory', () {
    test('a relative baseDir is resolved against the current directory', () {
      final result = _resolve('x.json', baseDir: p.join('build', 'restore'));
      expect(p.isAbsolute(result), isTrue);
      expect(p.basename(result), 'x.json');
      expect(p.isWithin(p.current, result), isTrue);
    });

    test('an unnormalised baseDir is normalised before containment is '
        'checked', () {
      final messyBase = p.join(_base, 'stage', '..', 'final');
      final result = _resolve('f.json', baseDir: messyBase);
      expect(result, p.join(_base, 'final', 'f.json'));
    });

    test('traversal is still rejected when baseDir itself is unnormalised', () {
      final messyBase = p.join(_base, 'stage', '..', 'final');
      expect(
        () => _resolve('../escaped.json', baseDir: messyBase),
        _throwsUnsafePath(UnsafeBackupPathReason.parentTraversal),
      );
    });
  });

  group('rejection diagnostics stay inside the privacy boundary', () {
    // A crafted entry name is attacker-controlled, but a *legitimate* one is
    // derived from a peer identity (`avatars/<peer>.png`). The rejection path
    // cannot tell the two apart, so it must never echo either. The marker
    // below deliberately contains `-`, which cannot occur in the hex
    // fingerprint, so `isNot(contains(...))` cannot pass by accident.
    const String peerEntry = '../../7f3c-peer-secret-id/avatar.png';

    UnsafeBackupPathException capture(String relativePath) {
      try {
        _resolve(relativePath);
      } on UnsafeBackupPathException catch (e) {
        return e;
      }
      fail('expected $relativePath to be rejected');
    }

    test('the message omits the raw entry name', () {
      final error = capture(peerEntry);

      expect(error.message, isNot(contains(peerEntry)));
      expect(error.message, isNot(contains('peer-secret-id')));
      expect(error.message, isNot(contains('avatar.png')));
      expect(error.toString(), isNot(contains('peer-secret-id')));
    });

    test('the message still carries reason, length and fingerprint', () {
      final error = capture(peerEntry);

      expect(error.reason, UnsafeBackupPathReason.parentTraversal);
      expect(error.pathLength, peerEntry.length);
      expect(error.pathFingerprint, matches(RegExp(r'^[0-9a-f]{12}$')));
      expect(error.message, contains('reason=parentTraversal'));
      expect(error.message, contains('len=${peerEntry.length}'));
      expect(error.message, contains('fp=${error.pathFingerprint}'));
    });

    test('the fingerprint is stable per entry and differs between entries', () {
      // Stability is what makes the fingerprint useful in a bug report: two
      // rejections of the same crafted archive correlate. Distinctness is what
      // makes it a fingerprint rather than a constant.
      expect(
        capture(peerEntry).pathFingerprint,
        capture(peerEntry).pathFingerprint,
      );
      expect(
        capture(peerEntry).pathFingerprint,
        isNot(capture('../../7f3c-peer-secret-id/avatar2.png').pathFingerprint),
      );
    });

    test('every rejection rule produces the same shape of diagnostic', () {
      // Guards against one branch regressing to a raw-path message while the
      // others stay redacted.
      const Map<String, UnsafeBackupPathReason> cases =
          <String, UnsafeBackupPathReason>{
        r'sub\peer-secret-id.json': UnsafeBackupPathReason.backslash,
        'peer-secret-id.json:hidden': UnsafeBackupPathReason.colon,
        'peer-secret-id/..': UnsafeBackupPathReason.normalizesToBase,
        '../peer-secret-id.json': UnsafeBackupPathReason.parentTraversal,
        '/peer-secret-id.json': UnsafeBackupPathReason.absolute,
      };

      for (final entry in cases.entries) {
        final error = capture(entry.key);
        expect(error.reason, entry.value, reason: entry.key);
        expect(
          error.message,
          isNot(contains('peer-secret-id')),
          reason: '${entry.value.name} leaked the entry name',
        );
        expect(error.pathLength, entry.key.length, reason: entry.key);
      }
    });
  });
}
