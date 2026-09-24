import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'account_export/tox_file_io.dart';
import 'app_paths.dart';
import 'async_gate.dart';
import 'legacy_offline_queue_merge.dart';
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
  ///
  /// [AsyncGate] and not a `_tail.then(...)` chain: chaining onto the previous
  /// caller's future would run the claim in THAT caller's zone, which inside a
  /// widget test means it does not run at all until the test is over.
  static final AsyncGate _claimGate = AsyncGate();

  /// Whether [toxId] may absorb the legacy global data.
  ///
  /// Records the claim as a side effect when it grants one, and only grants when
  /// that record actually persisted. Never throws: this runs inside account
  /// initialization and must not be able to block a login.
  static Future<bool> claim(String toxId) {
    return _claimGate.run(() => _claimUnsynchronized(toxId));
  }

  static Future<bool> _claimUnsynchronized(
    String toxId, {
    bool userAuthorized = false,
  }) async {
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

      // An explicit user request substitutes for cryptographic proof — see
      // [claimByUserRequest]. Exclusivity is still enforced above.
      if (!userAuthorized && !await _ownsLegacyData(normalized)) {
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

  /// Whether unclaimed legacy global data is sitting on disk.
  ///
  /// Used by the UI to offer an explicit recovery action. Making ownership
  /// provable-only closed a real data-bleed, but it also means an upgrader whose
  /// legacy profile is ENCRYPTED gets no automatic migration — the passphrase is
  /// not available at the point the claim runs, so neither proof applies. Their
  /// history is intact on disk with nothing pointing at it, which is exactly the
  /// situation that needs a user-visible door rather than silence.
  static Future<bool> hasUnclaimedLegacyData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final existing = prefs.getString(claimedByKey);
      if (existing != null && existing.isNotEmpty) return false;
      return await _legacyGlobalDataExists();
    } catch (_) {
      return false;
    }
  }

  /// Claim the legacy data for [toxId] on the user's explicit instruction.
  ///
  /// This is the ONE path that does not require cryptographic proof of
  /// ownership, because the proof is the user: they are logged into the account
  /// and have asked for the data. It is still exclusive — the claim is recorded
  /// exactly as an automatic one is, so no second account can take it
  /// afterwards.
  ///
  /// Returns whether the claim was granted (false when something else already
  /// owns it, or the record could not be persisted).
  static Future<bool> claimByUserRequest(String toxId) {
    final normalized = toxId.trim();
    if (normalized.isEmpty) return Future<bool>.value(false);
    return _claimGate.run(
      () => _claimUnsynchronized(normalized, userAuthorized: true),
    );
  }

  /// Whether any of the legacy global files exist.
  ///
  /// The directories must actually CONTAIN something. An empty
  /// `<appSupport>/chat_history` is not recoverable data, and offering a
  /// recovery that recovers nothing is its own bug — tim2tox now creates that
  /// directory (with an owner marker in it, and nothing else) the first time
  /// an account with no legacy data resolves the default path, so "the
  /// directory exists" stopped meaning anything.
  static Future<bool> _legacyGlobalDataExists() async {
    for (final probe in <Future<bool> Function()>[
      () async => _directoryHoldsData(await AppPaths.chatHistoryPath),
      () async => File(await AppPaths.offlineMessageQueueFilePath).exists(),
      () async => _directoryHoldsData(await AppPaths.avatarsPath),
    ]) {
      try {
        if (await probe()) return true;
      } catch (_) {
        // Keep probing; an unreadable path is not evidence either way.
      }
    }
    return false;
  }

  /// Whether [path] is a directory holding at least one non-hidden file.
  /// Bookkeeping files (tim2tox's `.tim2tox_history_owner` marker) do not
  /// count as data.
  static Future<bool> _directoryHoldsData(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (p.basename(entity.path).startsWith('.')) continue;
      return true;
    }
    return false;
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

/// Marks an account directory whose legacy migration already ran to completion.
///
/// Inert to every runtime reader (not `*.json`, and it sits in the account
/// ROOT, not in `chat_history/`).
const String legacyMigrationDoneMarkerName = '.legacy_data_migrated';

/// Copy the legacy global dataset into [toxId]'s account directory, but only if
/// [LegacyAccountDataClaim] grants this account the claim.
///
/// Split out of `AppPaths` so the entitlement decision and the copy it guards
/// live together — they are one policy, and the gate is the only thing standing
/// between an upgraded install and one identity's history landing in every
/// account created afterwards.
///
/// RUNS EXACTLY ONCE per account, recorded by [legacyMigrationDoneMarkerName].
/// The claim alone is not enough: it stays granted forever and the legacy
/// source is never retired, so "copy every file the destination is missing"
/// re-ran on every login by the owner and UNDID deletions — clearing a
/// conversation deletes its account-side file, and the next login copied the
/// legacy one back in. The marker is that deletion boundary: after it, the
/// legacy directory is a frozen archive nobody copies from again.
Future<void> migrateLegacyAccountDataIfClaimed(String toxId) async {
  if (!await LegacyAccountDataClaim.claim(toxId)) return;
  final accountRoot = await AppPaths.getAccountDataRoot(toxId);
  final doneMarker = File(p.join(accountRoot, legacyMigrationDoneMarkerName));
  if (await doneMarker.exists()) return;
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

  // The offline queue is a SINGLE file, so "skip when the destination exists"
  // discarded the entire legacy queue the moment the account had one of its
  // own — which one offline send is enough to create. Preserving it as an
  // inert `<...>.legacy.json` stopped the loss but not the DEFECT: an upgrader
  // with both queues never sent the legacy messages. Merge them by message
  // identity instead, before the service loads the file.
  final legacyQueueFile = File(legacyQueuePath);
  final destQueue = File(accountQueuePath);
  // An earlier build parked the legacy queue here without ever sending it;
  // absorb that too, so upgraders are not stranded.
  final preserved = File('$accountQueuePath.legacy.json');
  var queuesMerged = true;
  if (await legacyQueueFile.exists() || await preserved.exists()) {
    await Directory(accountRoot).create(recursive: true);
    if (!await destQueue.exists() && !await preserved.exists()) {
      await legacyQueueFile.copy(accountQueuePath);
    } else {
      queuesMerged = await mergeLegacyOfflineQueues(
        destination: destQueue,
        sources: <File>[preserved, legacyQueueFile],
      );
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

  if (!queuesMerged) {
    // The pending sends are still only in the legacy file. Leave the migration
    // unrecorded so the next login retries it rather than freezing that loss.
    AppLogger.warn(
      '[LegacyAccountDataClaim] the offline-queue merge did not complete; the '
      'migration stays open and will be retried',
    );
    return;
  }

  // Everything above landed. Record it so no later login copies any of it
  // again — the boundary that makes a deletion by the user permanent.
  try {
    await Directory(accountRoot).create(recursive: true);
    await doneMarker.writeAsString(
      DateTime.now().toUtc().toIso8601String(),
      flush: true,
    );
  } catch (e, st) {
    AppLogger.logError(
      '[LegacyAccountDataClaim] could not record the completed migration; it '
      'will run again on the next login and may restore deleted history',
      e,
      st,
    );
  }
}
