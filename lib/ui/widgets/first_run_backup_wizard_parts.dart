part of 'first_run_backup_wizard.dart';

class _FirstRunBackupWizardBody extends StatelessWidget {
  const _FirstRunBackupWizardBody({
    super.key,
    required this.statusMessage,
    required this.statusIsError,
    required this.l10n,
    required this.colorScheme,
  });

  final String? statusMessage;
  final bool statusIsError;
  final AppLocalizations l10n;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppThemeConfig.tintedPrimaryCardColor(colorScheme.primary),
              border: Border.all(
                color: AppThemeConfig.tintedPrimaryCardBorderColor(
                  colorScheme.primary,
                ),
              ),
            ),
            child: Icon(
              Icons.shield_outlined,
              size: 44,
              color: colorScheme.primary,
            ),
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
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        if (statusMessage != null) ...[
          AppSpacing.verticalLg,
          _FirstRunBackupWizardStatusBanner(
            message: statusMessage!,
            isError: statusIsError,
            colorScheme: colorScheme,
          ),
        ],
      ],
    );
  }
}

class _FirstRunBackupWizardStatusBanner extends StatelessWidget {
  const _FirstRunBackupWizardStatusBanner({
    required this.message,
    required this.isError,
    required this.colorScheme,
  });

  final String message;
  final bool isError;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isError
            ? colorScheme.errorContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 20,
            color: isError
                ? colorScheme.onErrorContainer
                : colorScheme.onSurface,
          ),
          AppSpacing.horizontalSm,
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError
                    ? colorScheme.onErrorContainer
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstRunBackupWizardActions extends StatelessWidget {
  const _FirstRunBackupWizardActions({
    required this.busy,
    required this.l10n,
    required this.isMobileWidth,
    required this.onExportNow,
    required this.onMaybeDismiss,
  });

  final bool busy;
  final AppLocalizations l10n;
  final bool isMobileWidth;
  final VoidCallback onExportNow;
  final VoidCallback onMaybeDismiss;

  @override
  Widget build(BuildContext context) {
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
              onPressed: busy ? null : onExportNow,
              icon: busy
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
          onPressed: busy ? null : onMaybeDismiss,
          child: Text(l10n.firstRunBackupWizardLater),
        ),
      ],
    );
  }
}
