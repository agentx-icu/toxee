import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'logger.dart';
import 'prefs.dart';

/// Centralized paths for app data (settings dir, avatars, downloads, history).
/// Uses platform path_provider under the hood; use this instead of calling
/// getApplicationSupportDirectory() and building paths manually.
abstract final class AppPaths {
  /// Application support directory (persistent, backed up on iOS).
  static Future<Directory> get applicationSupport async {
    return getApplicationSupportDirectory();
  }

  /// Path string for application support directory.
  static Future<String> get applicationSupportPath async {
    return (await applicationSupport).path;
  }

  /// Directory for chat history JSON files: `<appSupport>/chat_history`.
  static Future<Directory> get chatHistory async {
    final base = await applicationSupportPath;
    return Directory(p.join(base, 'chat_history'));
  }

  static Future<String> get chatHistoryPath async {
    return (await chatHistory).path;
  }

  /// Directory for avatar images: `<appSupport>/avatars`.
  static Future<Directory> get avatars async {
    final base = await applicationSupportPath;
    return Directory(p.join(base, 'avatars'));
  }

  static Future<String> get avatarsPath async {
    return (await avatars).path;
  }

  /// Directory for received files: `<appSupport>/file_recv`.
  static Future<Directory> get fileRecv async {
    final base = await applicationSupportPath;
    return Directory(p.join(base, 'file_recv'));
  }

  static Future<String> get fileRecvPath async {
    return (await fileRecv).path;
  }

  /// Path for offline message queue JSON: `<appSupport>/offline_message_queue.json`.
  static Future<String> get offlineMessageQueueFilePath async {
    final base = await applicationSupportPath;
    return p.join(base, 'offline_message_queue.json');
  }

  /// Directory for Tox profile files: `<appSupport>/tim2tox`.
  static Future<Directory> get toxProfileDir async {
    final base = await applicationSupportPath;
    return Directory(p.join(base, 'tim2tox'));
  }

  /// Path for a Tox profile file for the given [toxId]: `<appSupport>/tim2tox/tox_profile_<toxId>.tox`.
  static Future<String> toxProfilePath(String toxId) async {
    final dir = await toxProfileDir;
    return p.join(dir.path, 'tox_profile_$toxId.tox');
  }

  /// Path for the LAN bootstrap service profile file:
  /// `<appSupport>/tim2tox/bootstrap_service_profile.tox`.
  ///
  /// Single source of truth shared with `LanBootstrapService`. Kept at the
  /// same on-disk location as the historical inline construction so existing
  /// installs continue to find their bootstrap profile (X6 from the
  /// 2026-05-18 local-storage review).
  static Future<String> get lanBootstrapProfilePath async {
    final dir = await toxProfileDir;
    return p.join(dir.path, 'bootstrap_service_profile.tox');
  }

  /// Persistent root directory for multi-account tox profiles (outside app dir when possible).
  /// Uses [Prefs.getProfileStorageRoot] if set; otherwise platform default:
  /// macOS: ~/Library/Application Support/toxee/profiles
  /// Linux: $XDG_DATA_HOME/toxee/profiles or ~/.local/share/toxee/profiles (XDG Base Dir spec)
  /// Windows: %APPDATA%/toxee/profiles
  /// Fallback: app Application Support when custom root not set.
  ///
  /// On Linux, a one-time best-effort migration from the legacy
  /// `~/.config/toxee/profiles` location (used pre-XDG-compliance) is
  /// attempted on first call when the new location is empty.
  static Future<String> getProfileStorageRoot() async {
    final custom = await Prefs.getProfileStorageRoot();
    if (custom != null && custom.isNotEmpty) return custom;
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return p.join(home, 'Library', 'Application Support', 'toxee', 'profiles');
      }
    }
    if (Platform.isLinux) {
      final dataHome = Platform.environment['XDG_DATA_HOME'];
      String? root;
      if (dataHome != null && dataHome.isNotEmpty) {
        root = p.join(dataHome, 'toxee', 'profiles');
      } else {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          // XDG spec default: $XDG_DATA_HOME defaults to $HOME/.local/share
          // (NOT $HOME/.config — that's $XDG_CONFIG_HOME, which is for
          // app configuration, not user data).
          root = p.join(home, '.local', 'share', 'toxee', 'profiles');
        }
      }
      if (root != null) {
        await _maybeMigrateLegacyLinuxProfileRoot(root);
        return root;
      }
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'toxee', 'profiles');
      }
    }
    final base = await applicationSupportPath;
    return p.join(base, 'profiles');
  }

  /// One-shot migration: if the XDG-correct profile root is empty (or
  /// missing) and the legacy `~/.config/toxee/profiles` exists with content,
  /// rename the legacy directory to the new location. Idempotent — skips
  /// when the new root already has any entries.
  static Future<void> _maybeMigrateLegacyLinuxProfileRoot(String newRoot) async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;
      final legacy = Directory(p.join(home, '.config', 'toxee', 'profiles'));
      if (!await legacy.exists()) return;
      final newDir = Directory(newRoot);
      if (await newDir.exists()) {
        // Skip if the new location is already populated.
        final entries = await newDir.list().take(1).toList();
        if (entries.isNotEmpty) return;
      }
      // New location is empty / missing — migrate.
      AppLogger.warn(
          '[AppPaths] Migrating legacy Linux profile root '
          '${legacy.path} -> $newRoot (XDG spec compliance). '
          'This is a one-time operation.');
      await Directory(p.dirname(newRoot)).create(recursive: true);
      if (await newDir.exists()) {
        // Empty placeholder — remove so rename can succeed.
        await newDir.delete();
      }
      try {
        await legacy.rename(newRoot);
      } on FileSystemException catch (e) {
        // Cross-filesystem rename can fail; fall back to recursive copy.
        AppLogger.warn(
            '[AppPaths] rename() failed ($e); will leave legacy in place '
            'and not auto-migrate. Manual fix: '
            '`mv ${legacy.path} $newRoot`');
      }
    } catch (e, st) {
      AppLogger.logError(
          '[AppPaths] Linux profile migration failed (non-fatal)', e, st);
    }
  }

  /// Short directory name for one account: p_<first 16 hex chars of toxId>.
  static const int _profileDirPrefixLen = 16;
  static const String _profileDirPrefix = 'p_';

  /// Directory for the given [toxId] under profile storage root (short name: p_<toxId first 16 chars>).
  /// Native expects this path as initPath; it will create tox_profile.tox inside it.
  static Future<String> getProfileDirectoryForToxId(String toxId) async {
    final root = await getProfileStorageRoot();
    final normalized = toxId.trim();
    final first16 = normalized.length >= _profileDirPrefixLen
        ? normalized.substring(0, _profileDirPrefixLen)
        : normalized;
    return p.join(root, '$_profileDirPrefix$first16');
  }

  /// Path to the tox_profile.tox file inside a profile directory (for existence check / import).
  static String profileFileInDirectory(String profileDir) {
    return p.join(profileDir, 'tox_profile.tox');
  }

  /// Resolves the tox profile file for [toxId] by trying primary and fallback locations.
  /// Returns the path of the first existing file, or null if none found.
  /// Tries: (1) profile storage root p_<first16>/tox_profile.tox,
  /// (2) app support profiles/p_<first16>/tox_profile.tox,
  /// (3) legacy appSupport/tim2tox/tox_profile_<toxId>.tox.
  static Future<String?> resolveToxProfilePath(String toxId) async {
    final normalized = toxId.trim();
    final first16 = normalized.length >= _profileDirPrefixLen
        ? normalized.substring(0, _profileDirPrefixLen)
        : normalized;

    // 1. Primary: profile storage root / p_<first16> / tox_profile.tox
    final profileDir = await getProfileDirectoryForToxId(normalized);
    final primary = profileFileInDirectory(profileDir);
    final primaryFile = File(primary);
    if (await primaryFile.exists()) return primary;

    // 2. Fallback: app support profiles (e.g. when root differed or sandbox path)
    final base = await applicationSupportPath;
    final appSupportProfile =
        p.join(base, 'profiles', '$_profileDirPrefix$first16', 'tox_profile.tox');
    if (await File(appSupportProfile).exists()) return appSupportProfile;

    // 3. Legacy: appSupport/tim2tox/tox_profile_<fullToxId>.tox
    final legacy = await toxProfilePath(normalized);
    if (await File(legacy).exists()) return legacy;

    return null;
  }

  /// Account prefix (first 16 chars of toxId) for data directory naming. Same as used in p_<prefix> profile dirs.
  static String _accountPrefix(String toxId) {
    final normalized = toxId.trim();
    return normalized.length >= _profileDirPrefixLen
        ? normalized.substring(0, _profileDirPrefixLen)
        : normalized;
  }

  /// Per-account data root: `<appSupport>/account_data/<prefix>`. One dir per account for chat history, offline queue, etc.
  static Future<String> getAccountDataRoot(String toxId) async {
    final base = await applicationSupportPath;
    return p.join(base, 'account_data', _accountPrefix(toxId));
  }

  /// Chat history directory for the given account: `<accountDataRoot>/chat_history`.
  static Future<String> getAccountChatHistoryPath(String toxId) async {
    final root = await getAccountDataRoot(toxId);
    return p.join(root, 'chat_history');
  }

  /// Offline message queue file for the given account: `<accountDataRoot>/offline_message_queue.json`.
  static Future<String> getAccountOfflineQueueFilePath(String toxId) async {
    final root = await getAccountDataRoot(toxId);
    return p.join(root, 'offline_message_queue.json');
  }

  /// Avatars directory for the given account (optional): `<accountDataRoot>/avatars`.
  static Future<String> getAccountAvatarsPath(String toxId) async {
    final root = await getAccountDataRoot(toxId);
    return p.join(root, 'avatars');
  }

  /// File receive directory for the given account (optional): `<accountDataRoot>/file_recv`.
  static Future<String> getAccountFileRecvPath(String toxId) async {
    final root = await getAccountDataRoot(toxId);
    return p.join(root, 'file_recv');
  }

  /// Migrates legacy global chat_history and offline_message_queue into account_data/<prefix>/ once.
  /// Safe to call every time; only copies when legacy data exists and account dir is empty/missing.
  static Future<void> migrateAccountDataFromLegacy(String toxId) async {
    final accountRoot = await getAccountDataRoot(toxId);
    final accountHistoryDir = Directory(p.join(accountRoot, 'chat_history'));
    final accountQueuePath = p.join(accountRoot, 'offline_message_queue.json');
    final legacyHistoryPath = await chatHistoryPath;
    final legacyQueuePath = await offlineMessageQueueFilePath;

    final legacyHistoryDir = Directory(legacyHistoryPath);
    if (await legacyHistoryDir.exists()) {
      final legacyFiles = await legacyHistoryDir.list().where((e) => e is File).toList();
      if (legacyFiles.isNotEmpty) {
        await accountHistoryDir.create(recursive: true);
        for (final e in legacyFiles) {
          final file = e as File;
          final dest = File(p.join(accountHistoryDir.path, p.basename(file.path)));
          if (!await dest.exists()) await file.copy(dest.path);
        }
      }
    }

    final legacyQueueFile = File(legacyQueuePath);
    if (await legacyQueueFile.exists()) {
      await Directory(accountRoot).create(recursive: true);
      final destQueue = File(accountQueuePath);
      if (!await destQueue.exists()) await legacyQueueFile.copy(accountQueuePath);
    }

    // Migrate avatars from global <appSupport>/avatars/ to per-account directory
    final globalAvatarsPath = await avatarsPath;
    final accountAvatarsPath = await getAccountAvatarsPath(toxId);
    final accountAvatarsDir = Directory(accountAvatarsPath);
    final globalAvatarsDir = Directory(globalAvatarsPath);
    if (await globalAvatarsDir.exists()) {
      final prefix = _accountPrefix(toxId);
      final globalFiles = await globalAvatarsDir.list().where((e) => e is File).toList();
      if (globalFiles.isNotEmpty) {
        await accountAvatarsDir.create(recursive: true);
        for (final e in globalFiles) {
          final file = e as File;
          final baseName = p.basename(file.path);
          // Migrate self avatars matching this account's prefix
          // and friend avatars (friend_<id>_avatar.ext) for all friends
          if (baseName.startsWith('avatar_$prefix') ||
              baseName.startsWith('self_avatar') ||
              baseName.startsWith('friend_')) {
            final dest = File(p.join(accountAvatarsPath, baseName));
            if (!await dest.exists()) {
              await file.copy(dest.path);
            }
          }
        }
      }
    }
  }

  /// Directory for app logs: `<appSupport>/logs`.
  static Future<Directory> get logsDir async {
    final base = await applicationSupportPath;
    return Directory(p.join(base, 'logs'));
  }

  /// Platform default downloads directory (e.g. user's Downloads folder).
  /// Use when the user has not set a custom downloads directory in settings.
  static Future<Directory?> get defaultDownloadsDirectory async {
    if (Platform.isAndroid) {
      return getExternalStorageDirectory();
    }
    return getDownloadsDirectory();
  }

  /// Get the downloads directory for the current platform, respecting user configuration.
  /// Priority: user-configured > system Downloads > app documents fallback.
  /// Centralised logic shared by FfiChatService and AccountExportService.
  static Future<String> getDownloadsPath() async {
    // 1. Check user-configured custom path (from settings page)
    final custom = await Prefs.getDownloadsDirectory();
    if (custom != null && custom.isNotEmpty) {
      final dir = Directory(custom);
      if (await dir.exists()) return custom;
      try {
        await dir.create(recursive: true);
        return custom;
      } catch (_) {}
    }

    // 2. Desktop: system Downloads via path_provider, with manual fallback
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      try {
        final dir = await getDownloadsDirectory();
        if (dir != null) {
          if (!await dir.exists()) await dir.create(recursive: true);
          return dir.path;
        }
      } catch (_) {}
      // Manual fallback
      if (Platform.isMacOS || Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          final dir = Directory(p.join(home, 'Downloads'));
          if (!await dir.exists()) await dir.create(recursive: true);
          return dir.path;
        }
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          final dir = Directory(p.join(userProfile, 'Downloads'));
          if (!await dir.exists()) await dir.create(recursive: true);
          return dir.path;
        }
      }
    }

    // 3. Android: use the app's own documents/Downloads directory.
    //
    // Why not the shared /storage/emulated/0/Download anymore?
    //   - WRITE_EXTERNAL_STORAGE is capped at maxSdkVersion=28 in
    //     android/app/src/main/AndroidManifest.xml.
    //   - On API 29+ (Android 10), scoped storage blocks direct writes to
    //     the shared Downloads folder; the previous 4-parent traversal
    //     (`extDir.parent.parent.parent.parent / 'Download'`) silently
    //     failed and we ended up in this fallback anyway.
    //   - User-visible "save to Downloads" should go through MediaStore or
    //     the SAF document picker. That's intentionally out of scope here;
    //     the share-sheet export path already covers user-visible exports.
    if (Platform.isAndroid) {
      final appDir = await getApplicationDocumentsDirectory();
      final fallback = Directory(p.join(appDir.path, 'Downloads'));
      if (!await fallback.exists()) await fallback.create(recursive: true);
      return fallback.path;
    }

    // 4. iOS: app documents/Downloads (accessible via Files app if UIFileSharingEnabled)
    if (Platform.isIOS) {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'Downloads'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir.path;
    }

    // Ultimate fallback
    final base = await applicationSupportPath;
    final dir = Directory(p.join(base, 'Downloads'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// Path for the production app log file. Convention is the **timestamped
  /// path** under `<appSupport>/logs/app_<sessionTimestamp>.log`, matching
  /// `AppLogger.initialize()`'s built-in default. This deprecates the flat
  /// `<appSupport>/flutter_client.log` convention (X6 from the 2026-05-18
  /// local-storage review).
  ///
  /// The development dev-loop scripts (`run_toxee.sh`) tail a flat
  /// `flutter_client.log` under `TOXEE_LOG_DIR` or `Directory.current/build/`.
  /// That is intentional — see `LoggingBootstrap.initialize()`. It only
  /// applies when those locations are writable; production / CI / mobile
  /// always end up here at the timestamped convention.
  static Future<String> get logFilePath async {
    final logDir = await logsDir;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return p.join(logDir.path, 'app_$timestamp.log');
  }

  // ─────────────────────────────────────────────────────────────────────
  // iOS backup-exclusion helper
  //
  // Apple's review guidelines forbid storing regenerable data (caches,
  // received files, log scratch space) in a directory that gets backed up
  // to iCloud / iTunes. The OS gives us `NSURLIsExcludedFromBackupResourceKey`
  // for fine-grained control on directories under Application Support.
  //
  // Dart-side: call AppPaths.markExcludedFromBackup(<path>) on directories
  // that hold derivable / ephemeral content (logs, file_recv, QR cache).
  // iOS-side: AppDelegate.swift handles the MethodChannel and applies the
  // resource value. Android/macOS/Linux/Windows: no-op.
  // ─────────────────────────────────────────────────────────────────────
  static const MethodChannel _backupChannel =
      MethodChannel('toxee/ios_backup');

  /// Marks a directory or file as excluded from iOS backups. No-op on
  /// non-iOS platforms. Safe to call multiple times; the underlying API
  /// is idempotent. Errors are logged at debug level and swallowed —
  /// failing to set this attribute should never prevent the app from
  /// running.
  static Future<void> markExcludedFromBackup(String path) async {
    if (!Platform.isIOS) return;
    try {
      await _backupChannel.invokeMethod<void>(
          'markExcludedFromBackup', <String, String>{'path': path});
    } catch (e) {
      // Log but never throw — this is a defensive housekeeping call.
      AppLogger.warn('[AppPaths] markExcludedFromBackup($path) failed: $e');
    }
  }
}
