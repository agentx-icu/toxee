import 'dart:io';

import 'package:path/path.dart' as p;

import 'account_export/tox_file_io.dart';
import 'app_paths.dart';
import 'logger.dart';
import 'prefs.dart';

/// Startup-only repair pass for orphaned profile directories.
///
/// Background: older imports and the single `.tox` path can leave a per-account
/// `p_<first16>/tox_profile.tox` in [AppPaths.getProfileStorageRoot] without a
/// matching `account_list` entry. If the process is killed between those two
/// steps, the profile sits on disk invisible to startup — the user sees a
/// missing account, but the data is still there. Journaled full-backup restore
/// recovery runs before this helper and handles its own partial states.
///
/// This helper enumerates the profile storage root, finds `p_*` directories
/// with a readable `tox_profile.tox` that has no matching `account_list`
/// entry (matched by `toxId` prefix), and reconstructs a minimal entry via
/// [Prefs.addAccount]. The full Tox ID is extracted from the profile blob
/// using the same FFI extractor the importer uses.
///
/// The pass is idempotent and safe to call every cold start: profiles with
/// a matching account entry are skipped, and partial failures (unreadable
/// profile, FFI unavailable in tests, no matching scoped key on this
/// machine) are logged but do not throw.
abstract final class AccountReconciliation {
  AccountReconciliation._();

  /// Scan the profile storage root for orphaned profile directories and
  /// re-register them in [Prefs]. Call once during startup after
  /// [Prefs.initialize] has run.
  ///
  /// Returns the number of orphans recovered (0 on a clean run).
  static Future<int> reconcileOrphanedProfiles() async {
    int recovered = 0;
    try {
      final rootPath = await AppPaths.getProfileStorageRoot();
      final rootDir = Directory(rootPath);
      if (!await rootDir.exists()) return 0;

      // Build a set of known toxId prefixes (first 16 chars) from account_list.
      // We match by prefix because the on-disk dir name is `p_<first16>`.
      final accounts = await Prefs.getAccountList();
      final knownPrefixes = <String>{};
      for (final acc in accounts) {
        final toxId = (acc['toxId'] ?? '').trim();
        if (toxId.isEmpty) continue;
        knownPrefixes.add(_prefixOf(toxId));
      }

      await for (final entity in rootDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final dirName = p.basename(entity.path);
        if (!dirName.startsWith('p_')) continue;
        final prefix = dirName.substring(2);
        if (prefix.isEmpty) continue;
        if (knownPrefixes.contains(prefix)) continue;

        final profilePath = AppPaths.profileFileInDirectory(entity.path);
        final profileFile = File(profilePath);
        if (!await profileFile.exists()) continue;

        try {
          final bytes = await profileFile.readAsBytes();
          // Encrypted profiles cannot be reconciled without the user's
          // passphrase. We deliberately skip them rather than failing the
          // entire pass; the user can still recover via the import UI.
          final toxId = extractToxIdFromProfile(bytes);
          if (toxId.isEmpty) {
            AppLogger.warn(
              '[AccountReconciliation] empty toxId extracted from $profilePath; skipping',
            );
            continue;
          }
          // Belt-and-braces: confirm the extracted toxId matches the dir prefix,
          // so a stray directory with somebody else's profile (e.g. copied
          // by hand) doesn't get registered under the wrong key.
          if (_prefixOf(toxId) != prefix) {
            AppLogger.warn(
              '[AccountReconciliation] extracted toxId prefix (${_prefixOf(toxId)}) '
              'does not match dir prefix ($prefix); skipping $profilePath',
            );
            continue;
          }

          final nickname = 'Recovered ${toxId.substring(0, 8)}';
          await Prefs.addAccount(
            toxId: toxId,
            nickname: nickname,
            autoLogin: false,
          );
          recovered++;
          AppLogger.warn(
            '[AccountReconciliation] recovered orphaned profile: '
            'toxIdPrefix=$prefix nickname="$nickname" path=$profilePath',
          );
        } catch (e, st) {
          // Per-orphan failure must not abort the pass. The most common cause
          // here is an encrypted profile or a missing FFI (e.g. running in a
          // unit test without libtim2tox_ffi available).
          AppLogger.logError(
            '[AccountReconciliation] failed to recover $profilePath',
            e,
            st,
          );
        }
      }
    } catch (e, st) {
      AppLogger.logError(
        '[AccountReconciliation] reconcileOrphanedProfiles failed',
        e,
        st,
      );
    }
    return recovered;
  }

  static String _prefixOf(String toxId) {
    final normalized = toxId.trim();
    return normalized.length >= 16 ? normalized.substring(0, 16) : normalized;
  }
}
