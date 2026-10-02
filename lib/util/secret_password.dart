// An account password as zeroable bytes.
//
// A Dart `String` is immutable and lives in the heap until the GC happens to
// reclaim it, so a password that is kept as a String — for the session, or
// just handed from layer to layer across awaits — stays readable in a memory
// dump long after it was needed. Every RETAINED or PASSED-ALONG copy of an
// account password is therefore a [SecretPassword]: a Uint8List that is
// zeroed on [dispose], handed out only as a scoped view, never compared or
// printed by content.
//
// The UI text field unavoidably produces a String once. Convert it at that
// edge (`SecretPassword.fromString`, or the `use` helpers) and drop the String
// reference immediately; nothing below the edge takes a String.
//
// Ownership rules — the same everywhere, so a reader never has to guess:
//
//  * A SecretPassword received as a PARAMETER is BORROWED until the call —
//    or the Future it returns — completes. The callee never disposes it, and
//    `copy()`s it if it must outlive the call (`SessionPasswordStore.set`
//    does). The caller keeps it alive until then.
//  * A SecretPassword returned in a RESULT or kept in a FIELD is OWNED by the
//    receiver / holder, which disposes it when done. The exception is a
//    parameter-carrier object (`LoginParams`, `FullBackupRestoreInput`): its
//    field is a borrowed parameter in disguise and says so.
//  * Bytes handed to `withBytes` are a VIEW valid only inside the callback;
//    the callback must not retain them.

import 'dart:convert';
import 'dart:typed_data';

final class SecretPassword {
  SecretPassword._(this._bytes);

  /// UTF-8 encodes [text]. The String cannot be zeroed; the caller drops it.
  /// `utf8.encode` returns a fresh Uint8List, so no second copy is made.
  factory SecretPassword.fromString(String text) =>
      SecretPassword._(_asUint8List(utf8.encode(text)));

  /// Copies [bytes]; the caller keeps ownership of its own buffer.
  factory SecretPassword.fromBytes(List<int> bytes) =>
      SecretPassword._(Uint8List.fromList(bytes));

  /// [fromString] for a nullable edge value (a dismissed dialog yields null).
  /// An empty String is wrapped, not nulled: callers decide what empty means.
  static SecretPassword? fromStringOrNull(String? text) =>
      text == null ? null : SecretPassword.fromString(text);

  /// Wraps [text], runs [body], and disposes the wrapper — for an edge that
  /// only needs the password for one call (a verification, a one-off export).
  ///
  /// Synchronous on purpose: the String is converted before anything is
  /// awaited, so it is not kept alive by an async frame for the duration of
  /// [body].
  static Future<T> use<T>(
    String text,
    Future<T> Function(SecretPassword password) body,
  ) => _runThenDispose(SecretPassword.fromString(text), body);

  /// [use] for a nullable edge value: null passes through as null.
  static Future<T> useOrNull<T>(
    String? text,
    Future<T> Function(SecretPassword? password) body,
  ) => _runThenDispose(fromStringOrNull(text), body);

  static Future<T> _runThenDispose<T, P extends SecretPassword?>(
    P password,
    Future<T> Function(P password) body,
  ) async {
    try {
      return await body(password);
    } finally {
      password?.dispose();
    }
  }

  final Uint8List _bytes;
  bool _disposed = false;

  int get length {
    _checkLive();
    return _bytes.length;
  }

  bool get isEmpty => length == 0;
  bool get isNotEmpty => length != 0;
  bool get isDisposed => _disposed;

  /// Runs [body] on a VIEW of the bytes. The view is valid only for the
  /// duration of the callback and must not be retained or returned.
  T withBytes<T>(T Function(Uint8List bytes) body) {
    _checkLive();
    return body(_bytes);
  }

  /// An independent copy with its own lifetime.
  SecretPassword copy() {
    _checkLive();
    return SecretPassword._(Uint8List.fromList(_bytes));
  }

  /// Zero-fills the bytes. Idempotent; every access afterwards throws.
  void dispose() {
    if (_disposed) return;
    _bytes.fillRange(0, _bytes.length, 0);
    _disposed = true;
  }

  void _checkLive() {
    if (_disposed) {
      throw StateError('SecretPassword used after dispose()');
    }
  }

  /// Identity only. Two passwords are never compared by content here — a
  /// verification goes through the PBKDF2 verifier, never through `==`.
  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);

  /// Never the content, and not even the length: a log line must not help
  /// anyone narrow the search.
  @override
  String toString() => 'SecretPassword(redacted)';

  static Uint8List _asUint8List(List<int> bytes) =>
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
}

/// `null` and empty both mean "no password" at most call sites.
extension SecretPasswordOrNull on SecretPassword? {
  bool get hasValue {
    final self = this;
    return self != null && self.isNotEmpty;
  }
}
