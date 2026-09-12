import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'account_export/tox_file_io.dart';
import 'app_paths.dart';
import 'logger.dart';
import 'tox_utils.dart';

/// Decides WHICH account may absorb the pre-multi-account global data
/// (`<appSupport>/chat_history/`, `offline_message_queue.json`,
/// `avatars/`), and records that decision durably so it happens exactly once.
///
/// THE BUG THIS EXISTS TO PREVENT: `AppPaths.migrateAccountDataFromLegacy`
/// copied that single global dataset into whatever account it was handed, on
/// every login and every registration, and never retired the source. On an
/// upgraded install the first account absorbed the legacy history — and then so
/// did the second, and the third. One person's message history, queued
/// messages and contact avatars were copied into unrelated local accounts, and
/// deleting the account that received them did not remove the source, so the
/// next new account got them again.
///
/// OWNERSHIP MUST BE PROVEN. Being first to ask is NOT proof, and neither is
/// being the only account registered so far: on an upgraded install with an
/// ENCRYPTED legacy profile, registering a brand-new account B before ever
/// logging into the legacy account A runs this check for B — and a
/// first-claim-wins rule would hand A's history to B. So an unproven claim
/// SKIPS the migration and records nothing; the data stays on disk, untouched
/// and still available to its owner.
///
/// PROOF, in order:
///   1. A claim already recorded. Only that owner may migrate; everyone else is
///      refused forever. This is the invariant that makes the grant exclusive.
///   2. The legacy profile's embedded Tox ID matches the requester. Works
///      whenever `<appSupport>/tim2tox/tox_profile.tox` is unencrypted, which is
///      the ordinary upgrade shape.
///   3. The legacy profile is byte-identical to the requester's OWN profile.
///      This is what covers the encrypted case: the account whose
///      `p_<prefix>/tox_profile.tox` is that same blob demonstrably IS the
///      legacy account (`initializeServiceForAccount` copies the legacy profile
///      into the account directory precisely when they are the same identity),
///      and it requires no passphrase.
///   4. Nothing proved -> skip.
abstract final class LegacyAccountDataClaim {
  LegacyAccountDataClaim._();

  /// Durable owner of the legacy dataset: the full Tox ID that claimed it.
  static const String claimedByKey = 'legacy_account_data_claimed_by';

  /// Serializes the read-then-write below.
  ///
  /// Without it two concurrent callers could both read "unclaimed", both prove
  /// ownership against the same blob, and both migrate — and more importantly a
  /// future relaxation of the proof rules would silently reintroduce the
  /// double-claim. Cheap: contention here is a login racing a registration.
  static Future<void> _claimGate = Future<void>.value();

  /// Whether [toxId] may absorb the legacy global data.
  ///
  /// Records the claim as a side effect when it grants one, and only grants when
  /// that record actually persisted. Never throws: this runs inside account
  /// initialization and must not be able to block a login.
  static Future<bool> claim(String toxId) {
    final pending = _claimGate.then((_) => _claimUnsynchronized(toxId));
    // Keep the gate alive regardless of outcome so a failed claim cannot wedge
    // every later one.
    _claimGate = pending.then((_) {}, onError: (_) {});
    return pending;
  }

  static Future<bool> _claimUnsynchronized(String toxId) async {
    final normalized = toxId.trim();
    if (normalized.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Re-read from the platform rather than trusting the in-process cache:
      // `SharedPreferences` updates its cache BEFORE the platform write
      // completes, so a failed write can leave a cached value that looks like a
      // durable record.
      await prefs.reload();
      final existing = prefs.getString(claimedByKey);
      if (existing != null && existing.isNotEmpty) {
        // Already spoken for. The owner re-entering is a no-op migration (every
        // copy is `if (!await dest.exists())` guarded); anyone else is refused.
        return compareToxIds(existing, normalized);
      }

      if (!await _ownsLegacyData(normalized)) {
        AppLogger.log(
          '[LegacyAccountDataClaim] refused: ownership of the legacy global '
          'data is not proven for this account; leaving it for its owner',
        );
        return false;
      }

      // Only grant once the record is durable. A granted-but-unrecorded claim
      // would let a DIFFERENT account claim after the next restart, which is
      // the bleed all over again.
      if (!await prefs.setString(claimedByKey, normalized)) {
        AppLogger.warn(
          '[LegacyAccountDataClaim] refused: could not persist the claim, so '
          'exclusivity cannot be guaranteed',
        );
        return false;
      }
      await prefs.reload();
      if (prefs.getString(claimedByKey) != normalized) {
        AppLogger.warn(
          '[LegacyAccountDataClaim] refused: the claim did not survive a '
          'reload, so it is not durable',
        );
        return false;
      }
      AppLogger.log('[LegacyAccountDataClaim] granted');
      return true;
    } catch (e, st) {
      // Fail CLOSED. Skipping leaves the legacy data untouched on disk, which is
      // recoverable; a wrong migration copies one account's messages into
      // another, which is not.
      AppLogger.logError(
        '[LegacyAccountDataClaim] claim check failed; skipping legacy '
        'migration rather than risk a cross-account copy',
        e,
        st,
      );
      return false;
    }
  }

  /// Whether [toxId] is demonstrably the pre-multi-account identity.
  ///
  /// See the class doc for why "first to ask" is not accepted here.
  static Future<bool> _ownsLegacyData(String toxId) async {
    final legacyBytes = await _legacyProfileBytes();
    // No legacy profile at all: there is no evidence to tie the global data to
    // anyone, so nobody may take it.
    if (legacyBytes == null) return false;

    // (2) Identity readable from the blob.
    try {
      final extracted = extractToxIdFromProfile(legacyBytes);
      if (extracted.isNotEmpty) return compareToxIds(extracted, toxId);
    } catch (_) {
      // Encrypted, or no FFI. Fall through to the byte-identity check, which
      // needs neither.
    }

    // (3) The requester's own profile IS the legacy blob.
    try {
      final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
      final ownProfile = File(AppPaths.profileFileInDirectory(profileDir));
      if (!await ownProfile.exists()) return false;
      final ownBytes = await ownProfile.readAsBytes();
      if (ownBytes.length != legacyBytes.length) return false;
      for (var i = 0; i < ownBytes.length; i++) {
        if (ownBytes[i] != legacyBytes[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The legacy single-account profile's bytes, or null when there is none.
  static Future<Uint8List?> _legacyProfileBytes() async {
    try {
      final legacyDir = await AppPaths.toxProfileDir;
      final legacyProfile = File(
        AppPaths.profileFileInDirectory(legacyDir.path),
      );
      if (!await legacyProfile.exists()) return null;
      final bytes = await legacyProfile.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }
}

/// Copy the legacy global dataset into [toxId]'s account directory, but only if
/// [LegacyAccountDataClaim] grants this account the claim.
///
/// Split out of `AppPaths` so the entitlement decision and the copy it guards
/// live together — they are one policy, and the gate is the only thing standing
/// between an upgraded install and one identity's history landing in every
/// account created afterwards.
///
/// Idempotent for the owner: the claim is durable and every copy below is
/// guarded by `if (!await dest.exists())`.
Future<void> migrateLegacyAccountDataIfClaimed(String toxId) async {
  if (!await LegacyAccountDataClaim.claim(toxId)) return;
  final accountRoot = await AppPaths.getAccountDataRoot(toxId);
  final accountHistoryDir = Directory(p.join(accountRoot, 'chat_history'));
  final accountQueuePath = p.join(accountRoot, 'offline_message_queue.json');
  final legacyHistoryPath = await AppPaths.chatHistoryPath;
  final legacyQueuePath = await AppPaths.offlineMessageQueueFilePath;

  final legacyHistoryDir = Directory(legacyHistoryPath);
  if (await legacyHistoryDir.exists()) {
    final legacyFiles = await legacyHistoryDir
        .list()
        .where((e) => e is File)
        .toList();
    if (legacyFiles.isNotEmpty) {
      await accountHistoryDir.create(recursive: true);
      for (final e in legacyFiles) {
        final file = e as File;
        final dest = File(
          p.join(accountHistoryDir.path, p.basename(file.path)),
        );
        if (!await dest.exists()) await file.copy(dest.path);
      }
    }
  }

  final legacyQueueFile = File(legacyQueuePath);
  if (await legacyQueueFile.exists()) {
    await Directory(accountRoot).create(recursive: true);
    final destQueue = File(accountQueuePath);
    if (!await destQueue.exists()) {
      await legacyQueueFile.copy(accountQueuePath);
    }
  }

  // Migrate avatars from global <appSupport>/avatars/ to per-account directory
  final globalAvatarsPath = await AppPaths.avatarsPath;
  final accountAvatarsPath = await AppPaths.getAccountAvatarsPath(toxId);
  final accountAvatarsDir = Directory(accountAvatarsPath);
  final globalAvatarsDir = Directory(globalAvatarsPath);
  if (await globalAvatarsDir.exists()) {
    // Same rule as `AppPaths._accountPrefix` (private there): the first 16
    // chars of the Tox ID, which is what every persistent account path uses.
    final trimmedId = toxId.trim();
    final prefix = trimmedId.length >= 16
        ? trimmedId.substring(0, 16)
        : trimmedId;
    final globalFiles = await globalAvatarsDir
        .list()
        .where((e) => e is File)
        .toList();
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
