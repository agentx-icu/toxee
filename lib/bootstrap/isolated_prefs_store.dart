import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// A `SharedPreferences` store that keeps its JSON file INSIDE the
/// application-support override directory.
///
/// WHY (Windows real-UI pair, 2026-09-04): `shared_preferences_windows` keeps
/// one `%APPDATA%\<company>\<app>\shared_preferences.json` per Windows user and
/// rewrites the WHOLE file from its in-memory map on every write. Two toxee
/// instances of the same user (the two-process harness, A + B, each with its
/// own `TOXEE_SHARED_PREFS_PREFIX`) therefore clobber each other's keys on
/// disk: the last writer wins, and a relaunched instance reads back only the
/// other one's keys (the L3 seed-account marker vanished after
/// `sweep_p1_relaunch` restarted A). macOS `NSUserDefaults` merges per key, so
/// the key prefix was isolation enough there.
///
/// Installed by [PrefsBootstrap] only when `TOXEE_APP_SUPPORT_DIR` is set on a
/// desktop platform — the same switch that already moves every other store —
/// so ordinary single-instance installs keep the platform plugin untouched.
class IsolatedPrefsStore extends SharedPreferencesStorePlatform {
  IsolatedPrefsStore(this.file);

  /// The backing JSON file (created on first write).
  final File file;

  Map<String, Object>? _cache;
  Future<Map<String, Object>>? _loading;

  /// Single-flight load: concurrent first callers share one read, otherwise
  /// each would build its own map and the last one to finish would win.
  Future<Map<String, Object>> _read() {
    if (_cache != null) return Future.value(_cache);
    // A failed load (e.g. a transient FileSystemException) must not be
    // retained, or every later read/write would replay it until restart.
    return _loading ??= _load().catchError((Object e) {
      _loading = null;
      throw e;
    });
  }

  Future<Map<String, Object>> _load() async {
    var loaded = <String, Object>{};
    try {
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            loaded = decoded.map((k, v) => MapEntry(k.toString(), v as Object));
          }
        }
      }
    } on FormatException {
      // A torn write leaves an unreadable file: start from an empty map rather
      // than crash the app at boot; the next write replaces it.
      loaded = <String, Object>{};
    }
    return _cache = loaded;
  }

  /// Writes are chained so overlapping fire-and-forget `set*` calls from the
  /// app never race on the temp file or reorder on disk.
  Future<void> _writeQueue = Future<void>.value();
  int _writeSeq = 0;

  Future<bool> _write() {
    final done = _writeQueue.then((_) async {
      final prefs = await _read();
      await file.parent.create(recursive: true);
      // Write-then-rename so a crash mid-write cannot truncate the live file;
      // a unique temp name per write keeps queued writers apart.
      final tmp = File('${file.path}.$pid.${_writeSeq++}.tmp');
      await tmp.writeAsString(jsonEncode(prefs), flush: true);
      await tmp.rename(file.path);
    });
    _writeQueue = done.catchError((Object _) {});
    return done.then((_) => true);
  }

  /// The legacy contract (and both desktop plugins) scope [getAll] / [clear]
  /// to the default `flutter.` prefix; the prefixed variants below carry the
  /// caller's real prefix (`SharedPreferences.setPrefix`).
  static const _legacyPrefix = 'flutter.';

  @override
  Future<bool> clear() async {
    (await _read()).removeWhere((k, _) => k.startsWith(_legacyPrefix));
    return _write();
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final prefs = await _read();
    final filter = parameters.filter;
    prefs.removeWhere(
      (k, _) =>
          k.startsWith(filter.prefix) &&
          (filter.allowList == null || filter.allowList!.contains(k)),
    );
    return _write();
  }

  @override
  Future<Map<String, Object>> getAll() async => {
    for (final e in (await _read()).entries)
      if (e.key.startsWith(_legacyPrefix)) e.key: e.value,
  };

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final prefs = await _read();
    final filter = parameters.filter;
    return {
      for (final e in prefs.entries)
        if (e.key.startsWith(filter.prefix) &&
            (filter.allowList == null || filter.allowList!.contains(e.key)))
          e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    (await _read()).remove(key);
    return _write();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    (await _read())[key] = value;
    return _write();
  }
}
