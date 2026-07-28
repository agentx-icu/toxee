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
