import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'account_deletion_journal.dart';
import 'account_export/atomic_file_write.dart';
import 'app_paths.dart';
import 'default_avatar_installer.dart';
import 'imported_account_name.dart';
import 'prefs.dart';
import 'safe_diagnostics.dart';

/// Cold-start recovery of a registration interrupted between the profile rename
/// and the account-list write. Its intent moves with the profile directory.
abstract final class AccountRegistrationRecovery {
  static const _stagePrefix = '.tmp_register_v1_';
  static const _markerName = '.toxee_registration.json';
  static final _toxAddress = RegExp(r'^[A-Fa-f0-9]{76}$');

  static Future<String> createStage(String parent) async =>
      (await Directory(parent).createTemp(_stagePrefix)).path;

  static Future<void> stage({
    required String directory,
    required String toxId,
    required String nickname,
    required String statusMessage,
    required bool expectsPassword,
  }) {
    if (!_toxAddress.hasMatch(toxId)) {
      throw StateError('Registration did not produce a complete Tox address');
    }
    return writeBytesAtomically(
      _marker(directory),
      utf8.encode(
        jsonEncode({
          'version': 1,
          'toxId': toxId,
          'nickname': nickname,
          'statusMessage': statusMessage,
          'expectsPassword': expectsPassword,
        }),
      ),
    );
  }

  static Future<void> finish(String directory) async {
    try {
      await _marker(directory).delete();
    } on FileSystemException catch (error) {
      // The account is already durable. The next cold start can retry.
      SafeDiagnostics.logFailure('[AccountRegistration] marker cleanup', error);
    }
  }

  static Future<bool> hasMarker(String directory) async =>
      await _type(_marker(directory).path) != FileSystemEntityType.notFound;

  static Future<void> recover() async {
    final root = Directory(await AppPaths.getProfileStorageRoot());
    if (!await root.exists()) return;
    final staged = <Directory>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      if (name.startsWith(_stagePrefix)) {
        staged.add(entry);
      } else if (name.startsWith('p_') && await hasMarker(entry.path)) {
        await _tryRecover(() => _publishProfile(entry));
      }
    }
    // Resolve committed directories before deciding whether a staged verifier
    // has an owner. The process lease excludes a live registration here.
    for (final entry in staged) {
      await _tryRecover(() => _discardStage(entry));
    }
  }

  static Future<void> _tryRecover(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      SafeDiagnostics.logFailure(
        '[AccountRegistration] recovery deferred',
        error,
      );
    }
  }

  static Future<void> _publishProfile(Directory directory) async {
    final intent = await _read(directory.path);
    final toxId = intent.toxId;
    final expected = await AppPaths.getProfileDirectoryForToxId(toxId);
    if (!p.equals(directory.path, expected) ||
        await _type(AppPaths.profileFileInDirectory(directory.path)) !=
            FileSystemEntityType.file) {
      throw StateError('Registration profile and marker disagree');
    }
    if (await AccountDeletionJournalStore.hasPendingForToxId(toxId) ||
        AccountDeletionJournalStore.unattributableQuarantine.isNotEmpty) {
      return;
    }
    switch (await Prefs.accountRegistryPresence(toxId)) {
      case AccountRegistryPresence.present:
        if (await Prefs.getAccountByToxId(toxId) != null) {
          await finish(directory.path);
        }
        return;
      case AccountRegistryPresence.unknown:
        return;
      case AccountRegistryPresence.absent:
        break;
    }
    if (intent.expectsPassword &&
        await Prefs.accountProtectionState(toxId) !=
            AccountProtectionState.protected) {
      throw StateError('Registration verifier is unavailable');
    }
    final nickname = await ImportedAccountName.allocate(
      preferred: intent.nickname,
      toxId: toxId,
    );
    await Prefs.disableAutoLoginBeforeAccountPublication(toxId);
    await Prefs.addAccount(
      toxId: toxId,
      nickname: nickname,
      statusMessage: intent.statusMessage,
      autoLogin: false,
      updateLastLogin: false,
    );
    await DefaultAvatarInstaller.ensureSelfAvatar(toxId: toxId);
    await finish(directory.path);
  }

  static Future<void> _discardStage(Directory directory) async {
    if (await hasMarker(directory.path)) {
      final intent = await _read(directory.path);
      if (intent.expectsPassword) {
        final destination = await AppPaths.getProfileDirectoryForToxId(
          intent.toxId,
        );
        final presence = await Prefs.accountRegistryPresence(intent.toxId);
        if (presence == AccountRegistryPresence.unknown) return;
        if (presence == AccountRegistryPresence.absent) {
          if (await _type(AppPaths.profileFileInDirectory(destination)) !=
              FileSystemEntityType.notFound) {
            return;
          }
          if (!await Prefs.passwordChanges.removeAllCredentials(intent.toxId)) {
            return;
          }
        }
      }
    }
    await directory.delete(recursive: true);
  }

  static Future<
    ({
      String toxId,
      String nickname,
      String statusMessage,
      bool expectsPassword,
    })
  >
  _read(String directory) async {
    final marker = _marker(directory);
    if (await _type(marker.path) != FileSystemEntityType.file) {
      throw const FormatException('Registration marker is not a regular file');
    }
    final record = jsonDecode(await marker.readAsString());
    if (record case {
      'version': 1,
      'toxId': final String toxId,
      'nickname': final String nickname,
      'statusMessage': final String statusMessage,
      'expectsPassword': final bool expectsPassword,
    } when _toxAddress.hasMatch(toxId)) {
      return (
        toxId: toxId,
        nickname: nickname,
        statusMessage: statusMessage,
        expectsPassword: expectsPassword,
      );
    }
    throw const FormatException('Unrecognized registration marker');
  }

  static File _marker(String path) => File(p.join(path, _markerName));

  static Future<FileSystemEntityType> _type(String path) =>
      FileSystemEntity.type(path, followLinks: false);
}
