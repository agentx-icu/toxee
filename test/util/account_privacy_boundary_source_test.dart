// WHAT THIS IS: a negative source-text lint over first-party Dart, not a
// behaviour test. It greps `lib/**` for interpolations that would leak a
// private value (filesystem paths, raw exception text) into a log line or a
// user-visible error, and asserts they are absent.
//
// It executes zero product code. A behaviour test cannot replace it: proving
// "no diagnostic anywhere in these files ever interpolates a path" would
// mean driving every failure branch of every export/import/login/logout path
// and asserting on captured log output — a combinatorial surface that no
// realistic test suite covers. The forbidden-substring sweep is the only shape
// of check that is actually exhaustive here, so it is a lint by nature.
//
// WHY IT IS STILL IN `test/` (2026-08-07 audit): sibling greps that only
// inspected `tool/mcp_test` harness scripts were moved out to
// `tool/check_source_contracts.py`. This one was kept because it is a *privacy
// regression* guard and `flutter test` is currently its only automated gate;
// moving it before the CI wiring exists would silently drop the enforcement.
//
// Note the positive assertions too — every file in the account-boundary sweep
// must still reference `SafeDiagnostics.`, and the `lib/util/account_export/`
// cases below each pin their own redaction primitive (path fingerprint, typed
// abort, `errorType=` diagnostics), so deleting a redaction helper cannot make
// the negative assertions trivially pass.
//
// SCOPE, and why it is not "every file under `lib/util/account_export/`":
// listing a file here is a claim that it has been audited and that its
// forbidden substrings are meaningful, so the list is opt-in per file.
// Deliberately *not* listed:
//   * `atomic_file_write.dart`, `exceptions.dart`, `account_export_service.dart`,
//     `ffi_constants.dart` — no diagnostics at all; their only interpolations
//     build temp file names / forward an already-safe `message`.
//   * (was) `encryption.dart` and `full_backup_crypto.dart` — both leaked when
//     this note was written and were held back so the list would not go red
//     without fixing anything. Both were redacted on 2026-08-08 and are now
//     asserted below, as that note asked.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  test('logging bootstrap diagnostics never interpolate private values', () {
    final source = _source('lib/bootstrap/logging_bootstrap.dart');

    for (final leak in <String>[
      r'$logDirEnv',
      r'${currentDir.path}',
      r'$logPath',
      r'$e',
      r'$stackTrace',
    ]) {
      expect(source, isNot(contains(leak)), reason: 'raw diagnostic: $leak');
    }
  });

  test('full-backup diagnostics and validation omit selected file paths', () {
    final source = _source('lib/util/account_export/full_backup.dart');

    expect(source, isNot(contains('Full backup exported: \$finalFilePath')));
    expect(source, isNot(contains('File not found: \$filePath')));
    expect(source, isNot(contains('Not a .zip file: \$filePath')));
    expect(
      source,
      contains("'Full backup exported (bytes=\${zipData.length}, files="),
      reason: 'success diagnostics retain useful counts without a destination',
    );
  });

  // Added 2026-08-08. `backup_path_safety.dart` was NOT covered when the four
  // `throw Exception('Unsafe backup path: $relativePath')` sites were written,
  // which is precisely why that leak survived: `relativePath` is an archive
  // entry name (`chat_history/<peer>.json`, `avatars/<peer>.png`, see
  // `restore_transaction.dart` `_stagePayload`), i.e. a contact identifier, and
  // the rejection is reported to the importing user. The positive half pins the
  // replacement primitive (a truncated SHA-256 fingerprint), so the negative
  // half cannot be satisfied by deleting the redaction altogether.
  test('backup path rejections never carry the rejected entry name', () {
    final source = _source('lib/util/account_export/backup_path_safety.dart');

    for (final leak in <String>[
      r'$relativePath',
      r'${relativePath',
      r'$normalizedRelative',
      r'$targetPath',
      r'$baseDir',
      r'$normalizedBase',
    ]) {
      expect(source, isNot(contains(leak)), reason: 'raw diagnostic: $leak');
    }

    expect(
      source,
      contains('pathFingerprint'),
      reason: 'rejections must stay correlatable without the path itself',
    );
    expect(
      source,
      contains('sha256.convert('),
      reason: 'the fingerprint must stay one-way',
    );
  });

  // Added 2026-08-08 alongside `RestoreDestinationExistsError`. Same leak class
  // as above, different source of the private value: every restore destination
  // is `…/p_<first 16 hex of the account's own Tox ID>` under the application
  // support root, so the previous `'Restore destination already exists: $path'`
  // published the account's public-key prefix and the local filesystem layout
  // into `flutter_client.log` (`AppLogger.logError` writes `Error: $error`).
  // This file also holds the only two places that split an archive entry name
  // into a peer-derived `relativePath`, so those names are guarded here too.
  // The path entries are deliberately broad (`$path`, not
  // `already exists: $path`): this file composes every path through `p.join`
  // and has no legitimate reason to interpolate a directory variable into a
  // string at all, diagnostic or otherwise.
  // Added 2026-08-08 together with the redaction. `profileFilePath` is
  // `<profileStorageRoot>/p_<own Tox ID first 16>/tox_profile.tox`, so the old
  // `Profile file not found: $profileFilePath` published the account's own
  // public-key prefix plus the absolute local layout (OS user name on desktop).
  // These two throws sit on the set-password / login / logout paths.
  test('profile crypto diagnostics never carry the profile path', () {
    final source = _source('lib/util/account_export/encryption.dart');

    for (final leak in <String>[
      r'$profileFilePath',
      r'${profileFilePath',
    ]) {
      expect(source, isNot(contains(leak)), reason: 'raw diagnostic: $leak');
    }

    // Positive pin: the negative half must not be satisfiable by deleting the
    // throw altogether.
    expect(source, contains('ProfileFileMissingException'));
  });

  // Added 2026-08-08 together with the redaction. The subtle one: the throw
  // forwarded a caught `FormatException` with `$e`, and
  // `FormatException.toString()` appends an excerpt of `source` around `offset`
  // when both are set — which `json.decode` does. The source there is
  // `metadata.json`, carrying the nickname, the Tox ID and scoped prefs
  // (friend avatar paths). Only the historical unbraced form is forbidden;
  // the replacement uses `${e.message}` / `${e.offset}`, which quote nothing.
  test('full-backup metadata parse errors never quote the metadata source', () {
    final source = _source('lib/util/account_export/full_backup_crypto.dart');

    for (final leak in <String>[
      r'malformed: $e',
      r'$exception',
    ]) {
      expect(source, isNot(contains(leak)), reason: 'raw diagnostic: $leak');
    }

    expect(source, contains('e.message'));
    expect(source, contains('e.offset'));
  });

  test('restore transaction aborts never carry paths or entry names', () {
    final source = _source('lib/util/account_export/restore_transaction.dart');

    for (final leak in <String>[
      r'$path',
      r'$destination',
      r'$source',
      r'$relativePath',
      r'${relativePath',
      r'$targetPath',
      r'$entry',
      r'${entry.name',
      r'$profileStageDir',
      r'$accountDataStageDir',
      r'$profileFinalDir',
      r'$accountDataFinalDir',
    ]) {
      expect(source, isNot(contains(leak)), reason: 'raw diagnostic: $leak');
    }

    expect(
      source,
      contains('RestoreDestinationExistsError'),
      reason: 'the typed, redacted abort must not be reverted to a bare '
          'StateError with an interpolated destination',
    );
    expect(source, contains('RestoreDestinationKind.'));
  });

  // Added 2026-08-08. `tox_file_io.dart` is the .tox import/export path: it
  // handles the account nickname, the raw Tox ID and a user-chosen file path,
  // and it is the most log-dense file in `lib/util/account_export/`. It has
  // already been through a redaction pass — every diagnostic reports
  // `identifierLength=` / `byteCount=` / `errorType=` instead of the value — so
  // what this case buys is that the pass cannot silently rot. The forbidden
  // list is only the *unbraced* interpolation forms, which is exactly what a
  // raw dump looks like; the surviving redacted forms are all `${x.length}` /
  // `${x.runtimeType}` and cannot match. `$toxId` is deliberately absent from
  // the list because `$toxIdPrefix` (a filename fragment, not a diagnostic)
  // would match it.
  test('tox file import/export diagnostics stay value-free', () {
    final source = _source('lib/util/account_export/tox_file_io.dart');

    for (final leak in <String>[
      r'$normalizedToxId',
      r'$accToxId',
      r'$nickname',
      r'$filePath',
      r'$resolvedPath',
      r'$error',
      r'$fileData',
      r'$decryptedData',
      r'$password',
    ]) {
      expect(source, isNot(contains(leak)), reason: 'raw diagnostic: $leak');
    }

    expect(
      source,
      contains(r'errorType=${error.runtimeType}'),
      reason: 'failures must still be typed, just not quoted',
    );
    expect(
      source,
      contains('identifierLength='),
      reason: 'Tox IDs are reported by length only',
    );
  });

  test(
    'account failure boundaries use safe diagnostics and safe UI detail',
    () {
      final sources = <String, String>{
        'controller': _source('lib/ui/login/login_page_controller.dart'),
        'login': _source('lib/ui/login_page.dart'),
        'settings': _source('lib/ui/settings/settings_page.dart'),
        'startup': _source('lib/startup/startup_session_use_case.dart'),
        'startupGate': _source('lib/startup/startup_gate.dart'),
        'switcher': _source('lib/util/account_switcher.dart'),
        'wizard': _source('lib/ui/widgets/first_run_backup_wizard.dart'),
      };

      final forbidden = <String, List<String>>{
        'controller': <String>[
          "AppLogger.logError('[LoginPageController]",
          'detail: e.toString()',
          '? e.toString().replaceFirst',
        ],
        'login': <String>[
          "AppLogger.logError('[LoginPage]",
          'failedToExportAccount(e.toString())',
          'AppSnackBar.showError(context, e.toString())',
        ],
        'settings': <String>[
          "AppLogger.logError('Full backup export error'",
          "AppLogger.logError('Export account error'",
          "'[SettingsPage] Import account failed: \$e'",
          'failedToImportAccount(e.toString())',
          'failedToSetPassword(e.toString())',
          'deleteAccountFailed(e.toString())',
        ],
        'startup': <String>[
          "AppLogger.logError(\n            '[StartupSessionUseCase]",
          'StartupShowError(e.toString())',
        ],
        'startupGate': <String>[
          "AppLogger.logError(\n        '[StartupGate]",
          "'[StartupGate] Error loading friends info: \$e'",
        ],
        'switcher': <String>[
          "AppLogger.logError(\n            '[AccountSwitcher]",
          'failedToSwitchAccount(e.toString())',
        ],
        'wizard': <String>[
          "AppLogger.log('[FirstRunBackupWizard] Exported to \$filePath')",
          "AppLogger.logError('[FirstRunBackupWizard] Export failed'",
          'firstRunBackupWizardExportFailed(e.toString())',
        ],
      };

      for (final entry in forbidden.entries) {
        for (final leak in entry.value) {
          expect(
            sources[entry.key],
            isNot(contains(leak)),
            reason: '${entry.key} still exposes $leak',
          );
        }
      }

      for (final source in sources.values) {
        expect(source, contains('SafeDiagnostics.'));
      }

      for (final surface in <String>['login', 'settings', 'wizard']) {
        expect(
          sources[surface],
          isNot(contains('.cancellationNotice')),
          reason: '$surface must not display the private internal export path',
        );
      }
    },
  );
}
