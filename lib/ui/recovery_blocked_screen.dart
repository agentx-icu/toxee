import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../util/app_spacing.dart';
import '../util/design_tokens.dart';

/// Shown when a journalled account recovery could not be completed at startup.
///
/// The app deliberately exposes no account in this state — a pending full-backup
/// restore or account deletion whose journal cannot be read might be
/// half-committed, and guessing would risk destroying data. Before this screen
/// existed the failure propagated out of `AppBootstrap.initialize()` and past
/// `runApp`, so the user got a black window with no explanation.
///
/// The copy's job is to stop the two things a stuck user would otherwise do:
/// re-register (their accounts are still on disk) or wipe app data (that is the
/// one action that would make the loss permanent).
class RecoveryBlockedApp extends StatelessWidget {
  const RecoveryBlockedApp({super.key, required this.detail});

  /// Sanitized reason, already stripped of paths and Tox IDs upstream.
  final String detail;

  static ColorScheme _scheme(Brightness brightness) => ColorScheme.fromSeed(
    seedColor: DesignTokens.primary,
    brightness: brightness,
  );

  @override
  Widget build(BuildContext context) {
    // Standalone MaterialApp: this runs instead of the real app, so it cannot
    // rely on any of its theming or locale controllers being initialized.
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: _scheme(Brightness.light),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: _scheme(Brightness.dark),
      ),
      home: _RecoveryBlockedBody(detail: detail),
    );
  }
}

class _RecoveryBlockedBody extends StatelessWidget {
  const _RecoveryBlockedBody({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  AppSpacing.verticalLg,
                  Text(
                    l10n.recoveryBlockedTitle,
                    style: theme.textTheme.headlineSmall,
                  ),
                  AppSpacing.verticalMd,
                  Text(
                    l10n.recoveryBlockedBody,
                    style: theme.textTheme.bodyMedium,
                  ),
                  AppSpacing.verticalLg,
                  // The sanitized reason, for a bug report. Selectable because
                  // the user has no other way to get it out of a screen with no
                  // app behind it.
                  SelectableText(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
