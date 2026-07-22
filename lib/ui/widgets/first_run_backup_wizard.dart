import 'dart:io';
import 'dart:typed_data';

// ignore: directives_ordering
import 'safe_dialog_pop.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/account_export_service.dart';
import '../../util/app_paths.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/feature_flags.dart';
import '../../util/logger.dart';
import '../../util/mobile_export_policy.dart';
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
    @visibleForTesting this.isDesktopExportPlatformOverride,
    @visibleForTesting this.mobileExportSaveFile,
    @visibleForTesting this.createAndSaveMobileExportCopyOverride,
  });

  final String toxId;
  final String nickname;

  /// Test hook: overrides the real [AccountExportService.exportAccountData]
  /// call so widget tests can run without a real FFI library loaded.
  /// Production code must NOT pass this — leaving it null routes to the
  /// real service.
  @visibleForTesting
  final Future<String?> Function(String toxId, String nickname)? exportOverride;

  @visibleForTesting
  final bool? isDesktopExportPlatformOverride;

  @visibleForTesting
  final MobileExportSaveFile? mobileExportSaveFile;

  @visibleForTesting
  final CreateAndSaveMobileExportCopyFn? createAndSaveMobileExportCopyOverride;

  /// Show the wizard as a non-dismissable modal route. Returns when the user
  /// either successfully exports or explicitly acknowledges the dismiss
  /// consequence.
  static Future<FirstRunBackupWizardResult> show(
    BuildContext context, {
    required String toxId,
    required String nickname,
  }) async {
    final result = await Navigator.of(context, rootNavigator: true)
        .push<FirstRunBackupWizardResult>(
          PageRouteBuilder<FirstRunBackupWizardResult>(
            opaque: true,
            barrierDismissible: false,
            fullscreenDialog: true,
            pageBuilder: (ctx, _, __) =>
                FirstRunBackupWizard(toxId: toxId, nickname: nickname),
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
  // Single-step "wizard" today (one explainer + one CTA). The progress bar is
  // a forward-compatibility nod — when product wants a "verify by re-importing"
  // step it slots cleanly into [_totalSteps] / [_currentStep] without touching
  // the build tree. Keeping it visible at one-step parity is intentional:
  // the value `1/1` reads as "you're at the only step", which is more honest
  // than hiding the bar.
  static const int _totalSteps = 1;
  static const int _currentStep = 1;

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
      final isDesktopPlatform = isDesktopExportPlatform(
        override: widget.isDesktopExportPlatformOverride,
      );
      final defaultFileName = buildAccountExportFileName(
        toxId: widget.toxId,
        nickname: widget.nickname,
        suffix: '.tox',
      );
      // In production, prompt for save location on desktop platforms. When an
      // exportOverride is supplied (test path), skip the picker entirely —
      // the override owns the path semantics.
      if (widget.exportOverride == null && isDesktopPlatform) {
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
      MobileExportSaveResult? mobileSaveResult;
      if (widget.exportOverride != null && isDesktopPlatform) {
        filePath = await widget.exportOverride!(widget.toxId, widget.nickname);
      } else if (!isDesktopPlatform) {
        final createAndSaveCopy =
            widget.createAndSaveMobileExportCopyOverride ??
            createAndSaveMobileExportCopy;
        mobileSaveResult = await createAndSaveCopy(
          createInternalExport: () async {
            if (widget.exportOverride != null) {
              final path = await widget.exportOverride!(
                widget.toxId,
                widget.nickname,
              );
              if (path == null || path.isEmpty) {
                throw StateError('Export override did not create a file');
              }
              return path;
            }
            return AccountExportService.exportAccountData(toxId: widget.toxId);
          },
          dialogTitle: l10n.firstRunBackupWizardTitle,
          fileName: defaultFileName,
          saveFile:
              widget.mobileExportSaveFile ??
              ({
                required String dialogTitle,
                required String fileName,
                required Uint8List bytes,
              }) => FilePicker.platform.saveFile(
                dialogTitle: dialogTitle,
                fileName: fileName,
                bytes: bytes,
              ),
        );
        if (mobileSaveResult.disposition ==
            MobileExportSaveDisposition.cancelled) {
          if (mounted) {
            setState(() {
              _busy = false;
              _statusMessage = mobileSaveResult!.cancellationNotice;
              _statusIsError = false;
            });
          }
          return;
        }
        filePath =
            mobileSaveResult.userSelectedPath ??
            mobileSaveResult.internalFilePath;
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
          _statusMessage = AppLocalizations.of(
            context,
          )!.firstRunBackupWizardExportFailed(e.toString());
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
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.dialog),
          ),
          title: Text(l10n.firstRunBackupWizardDismissTitle),
          content: Text(l10n.firstRunBackupWizardDismissBody),
          actions: [
            TextButton(
              onPressed: () => popDialogIfCurrent(ctx, false),
              child: Text(l10n.cancel),
            ),
            // Skip is destructive — outlined-error button reads as "danger,
            // proceed with care" without claiming the visual weight a
            // FilledButton would (which is reserved for the safe path).
            OutlinedButton(
              key: const Key('firstRunBackupWizard.confirmDismissButton'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
                ),
              ),
              onPressed: () => popDialogIfCurrent(ctx, true),
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
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final width = MediaQuery.of(context).size.width;
    final isMobileWidth = width < 600;
    // Hard back-button block: registration must NOT be dismissable without
    // either an export or an acknowledged dismiss.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Slim progress indicator at the very top — shows position in the
              // (presently single-step) wizard. Bar stays visible at 100% on
              // the only step so the affordance is consistent with multi-step
              // flows elsewhere in the app.
              SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  value: _currentStep / _totalSteps,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: AnimatedSwitcher(
                        // Status message slides in/out with the wizard's
                        // motion tokens; respects reduced-motion.
                        duration: reduceMotion
                            ? Duration.zero
                            : AppDurations.medium,
                        switchInCurve: AppCurves.enter,
                        switchOutCurve: AppCurves.exit,
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: _buildBody(context, l10n, cs),
                      ),
                    ),
                  ),
                ),
              ),
              // Bottom-aligned actions row. SafeArea (outer) ensures the
              // bottom-inset is respected; the extra Padding gives breathing
              // room above the home indicator on iOS.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _buildActions(context, l10n, isMobileWidth),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Body: icon + title + body text + (optional) status banner. Re-keyed on
  /// status presence so [AnimatedSwitcher] can fade the banner in/out cleanly.
  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return Column(
      key: ValueKey<String>(
        'wizard-body-${_statusMessage != null}-$_statusIsError',
      ),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tinted-primary chip for the shield icon — same recipe as the
        // upgrade screen / login form, keeps the visual language consistent.
        Center(
          child: Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppThemeConfig.tintedPrimaryCardColor(cs.primary),
              border: Border.all(
                color: AppThemeConfig.tintedPrimaryCardBorderColor(cs.primary),
              ),
            ),
            child: Icon(Icons.shield_outlined, size: 44, color: cs.primary),
          ),
        ),
        AppSpacing.verticalLg,
        Text(
          l10n.firstRunBackupWizardTitle,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        AppSpacing.verticalMd,
        Text(
          l10n.firstRunBackupWizardBody,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        if (_statusMessage != null) ...[
          AppSpacing.verticalLg,
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: _statusIsError
                  ? cs.errorContainer
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _statusIsError ? Icons.error_outline : Icons.info_outline,
                  size: 20,
                  color: _statusIsError ? cs.onErrorContainer : cs.onSurface,
                ),
                AppSpacing.horizontalSm,
                Expanded(
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      color: _statusIsError
                          ? cs.onErrorContainer
                          : cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Bottom action row: primary FilledButton ("Export now") + secondary
  /// TextButton ("I'll do it later"). Primary is full-width on mobile, capped
  /// at 320 on desktop so it doesn't stretch absurdly wide on tablets.
  Widget _buildActions(
    BuildContext context,
    AppLocalizations l10n,
    bool isMobileWidth,
  ) {
    final primaryWidth = isMobileWidth ? double.infinity : 320.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: SizedBox(
            width: primaryWidth,
            child: FilledButton.icon(
              key: const Key('firstRunBackupWizard.exportButton'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.button),
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
        ),
        AppSpacing.verticalSm,
        TextButton(
          key: const Key('firstRunBackupWizard.laterButton'),
          onPressed: _busy ? null : _maybeDismiss,
          child: Text(l10n.firstRunBackupWizardLater),
        ),
      ],
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
