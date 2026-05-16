import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/account_export_service.dart';
import '../../util/app_paths.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/feature_flags.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';

/// Outcome of the first-run backup wizard. The caller (registration flow)
/// uses this to decide whether to proceed to HomePage. Today both terminal
/// states proceed to HomePage; the type exists so future product changes
/// (e.g. force-retry on dismiss-with-error) don't require a UI-level
/// refactor.
enum FirstRunBackupWizardResult {
  /// User exported the .tox file successfully.
  exported,

  /// User explicitly dismissed the wizard after acknowledging the
  /// data-loss consequence.
  acknowledgedDismiss,
}

/// First-run backup wizard.
///
/// Shown after [AccountService.registerNewAccount] returns success but BEFORE
/// the user reaches HomePage. The wizard is non-dismissable (no tap-outside-
/// to-close) and offers exactly two paths:
///
/// 1. **Export now** — opens a file save dialog and writes the `.tox` file
///    via [AccountExportService.exportAccountData]. On success, the wizard
///    returns [FirstRunBackupWizardResult.exported].
/// 2. **I'll do it later** — opens a SECOND confirmation dialog quoting the
///    explicit data-loss consequence. Only if the user confirms there does
///    the wizard return [FirstRunBackupWizardResult.acknowledgedDismiss].
///    The confirmation's Cancel button returns the user to the wizard.
///
/// Gated by [FeatureFlags.enableFirstRunBackupWizard] at the call site; this
/// widget itself does not check the flag (so tests can render it directly).
///
/// Pass [toxId] for the freshly-registered account and [nickname] for the
/// dialog body's default filename. The whole flow is async-safe: if the
/// caller's `mounted` becomes false during await, the navigator pop is still
/// safe (the route is owned by this widget's [Navigator]).
class FirstRunBackupWizard extends StatefulWidget {
  const FirstRunBackupWizard({
    super.key,
    required this.toxId,
    required this.nickname,
    @visibleForTesting this.exportOverride,
  });

  final String toxId;
  final String nickname;

  /// Test hook: overrides the real [AccountExportService.exportAccountData]
  /// call so widget tests can run without a real FFI library loaded.
  /// Production code must NOT pass this — leaving it null routes to the
  /// real service.
  @visibleForTesting
  final Future<String?> Function(String toxId, String nickname)? exportOverride;

  /// Show the wizard as a non-dismissable modal route. Returns when the user
  /// either successfully exports or explicitly acknowledges the dismiss
  /// consequence.
  static Future<FirstRunBackupWizardResult> show(
    BuildContext context, {
    required String toxId,
    required String nickname,
  }) async {
    final result = await Navigator.of(context, rootNavigator: true).push<FirstRunBackupWizardResult>(
      PageRouteBuilder<FirstRunBackupWizardResult>(
        opaque: true,
        barrierDismissible: false,
        fullscreenDialog: true,
        pageBuilder: (ctx, _, __) => FirstRunBackupWizard(
          toxId: toxId,
          nickname: nickname,
        ),
      ),
    );
    // Defensive: a screen-orientation change or back-gesture dispatch could
    // theoretically pop the route without a value. Treat that as
    // acknowledgedDismiss (the user implicitly chose "later") rather than
    // crash the caller. The plan's hard requirement is that an explicit
    // dismiss has the consequence dialog; an OS-level pop bypassing the UI
    // is documented as a known edge case.
    return result ?? FirstRunBackupWizardResult.acknowledgedDismiss;
  }

  @override
  State<FirstRunBackupWizard> createState() => _FirstRunBackupWizardState();
}

class _FirstRunBackupWizardState extends State<FirstRunBackupWizard> {
  bool _busy = false;
  String? _statusMessage;
  bool _statusIsError = false;

  Future<void> _exportNow() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    try {
      String? outputPath;
      // In production, prompt for save location on desktop platforms. When an
      // exportOverride is supplied (test path), skip the picker entirely —
      // the override owns the path semantics.
      if (widget.exportOverride == null &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final toxIdPrefix =
            widget.toxId.length >= 8 ? widget.toxId.substring(0, 8) : widget.toxId;
        final safeNickname = (widget.nickname.isEmpty ? 'account' : widget.nickname)
            .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        final defaultFileName = '${safeNickname}_$toxIdPrefix.tox';
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: l10n.firstRunBackupWizardTitle,
          fileName: defaultFileName,
        );
        if (outputPath == null) {
          // User cancelled the file picker — stay on the wizard.
          if (mounted) {
            setState(() {
              _busy = false;
              _statusMessage = null;
            });
          }
          return;
        }
      }

      String? filePath;
      if (widget.exportOverride != null) {
        filePath = await widget.exportOverride!(widget.toxId, widget.nickname);
      } else {
        filePath = await AccountExportService.exportAccountData(
          toxId: widget.toxId,
          filePath: outputPath,
        );
      }

      if (!mounted) return;
      // Pop the route with success — the registration flow then proceeds to HomePage.
      Navigator.of(context).pop(FirstRunBackupWizardResult.exported);
      // Note: we deliberately do NOT show an extra success state inside the
      // wizard before popping. The caller is responsible for surfacing the
      // saved-path message (e.g. via SnackBar) on its next frame.
      AppLogger.log('[FirstRunBackupWizard] Exported to $filePath');
    } catch (e, st) {
      AppLogger.logError('[FirstRunBackupWizard] Export failed', e, st);
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = AppLocalizations.of(context)!
              .firstRunBackupWizardExportFailed(e.toString());
          _statusIsError = true;
        });
      }
    }
  }

  Future<void> _maybeDismiss() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(l10n.firstRunBackupWizardDismissTitle),
          content: Text(l10n.firstRunBackupWizardDismissBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.firstRunBackupWizardDismissConfirm),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (confirmed == true) {
      Navigator.of(context).pop(FirstRunBackupWizardResult.acknowledgedDismiss);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    // Hard back-button block: registration must NOT be dismissable without
    // either an export or an acknowledged dismiss.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 64,
                      color: scheme.primary,
                    ),
                    AppSpacing.verticalLg,
                    Text(
                      l10n.firstRunBackupWizardTitle,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.verticalMd,
                    Text(
                      l10n.firstRunBackupWizardBody,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.verticalXl,
                    if (_statusMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: (_statusIsError ? scheme.errorContainer : scheme.surfaceContainerHighest)
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
                        ),
                        child: Text(
                          _statusMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _statusIsError ? scheme.onErrorContainer : scheme.onSurface,
                          ),
                        ),
                      ),
                      AppSpacing.verticalLg,
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        key: const Key('firstRunBackupWizard.exportButton'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                          ),
                        ),
                        onPressed: _busy ? null : _exportNow,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_alt),
                        label: Text(l10n.firstRunBackupWizardExportNow),
                      ),
                    ),
                    AppSpacing.verticalSm,
                    TextButton(
                      key: const Key('firstRunBackupWizard.laterButton'),
                      onPressed: _busy ? null : _maybeDismiss,
                      child: Text(l10n.firstRunBackupWizardLater),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Convenience extension used by the registration flow. Resolves a
/// per-account profile directory existence check so the wizard call site
/// stays small.
@visibleForTesting
Future<bool> profileDirectoryExistsForToxId(String toxId) async {
  final dir = await AppPaths.getProfileDirectoryForToxId(toxId);
  return Directory(dir).existsSync();
}

/// Convenience for callers that want to read back the just-registered
/// account's nickname without hitting the network — used by the registration
/// flow to pass [FirstRunBackupWizard.nickname].
@visibleForTesting
Future<String> readNicknameForToxId(String toxId) async {
  final account = await Prefs.getAccountByToxId(toxId);
  return account?['nickname'] ?? '';
}
