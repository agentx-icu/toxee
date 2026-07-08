import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/app_localizations.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import '../util/design_tokens.dart';
import '../util/logger.dart';
import '../util/prefs.dart';

/// Canonical release page for toxee. Hardcoded rather than wired to a remote
/// config: this screen is shown precisely when the local app is behind the
/// data file, so any "fetch the URL from the server" approach would be racy.
const String _kReleasesUrl = 'https://github.com/agentx-icu/toxee/releases';

/// Shown when stored preferences were saved by a newer app version.
/// Prompts the user to upgrade the app and does not overwrite their data.
class UpgradeRequiredApp extends StatelessWidget {
  const UpgradeRequiredApp({
    super.key,
    required this.storedVersion,
    required this.currentVersion,
  });

  final int storedVersion;
  final int currentVersion;

  static ThemeData get _lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        // Pin the sampled surfaces/text/error exactly (the rest of the app
        // uses an explicit scheme too) so this pre-app bootstrap screen can't
        // tonal-drift away from white/near-black.
        colorScheme: ColorScheme.fromSeed(
          seedColor: DesignTokens.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: DesignTokens.primary,
          onPrimary: DesignTokens.onPrimary,
          surface: DesignTokens.scaffoldLight,
          onSurface: DesignTokens.textPrimaryLight,
          onSurfaceVariant: DesignTokens.textSecondaryLight,
          error: DesignTokens.errorLight,
          outline: DesignTokens.inputBorderLight,
          outlineVariant: DesignTokens.dividerLight,
        ),
        scaffoldBackgroundColor: AppThemeConfig.lightScaffoldBackground,
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          // Flat surface + hairline border, matches the rest of the app.
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.button),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
        ),
      );

  static ThemeData get _darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: DesignTokens.primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: DesignTokens.primary,
          onPrimary: DesignTokens.onPrimary,
          surface: DesignTokens.scaffoldDark,
          onSurface: DesignTokens.textPrimaryDark,
          onSurfaceVariant: DesignTokens.textSecondaryDark,
          error: DesignTokens.errorDark,
          outline: DesignTokens.inputBorderDark,
          outlineVariant: DesignTokens.dividerDark,
        ),
        scaffoldBackgroundColor: AppThemeConfig.darkScaffoldBackground,
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          // Flat surface + hairline border, matches the rest of the app.
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.button),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: Prefs.getThemeMode(),
      builder: (context, snapshot) {
        final ThemeMode themeMode;
        if (!snapshot.hasData) {
          themeMode = ThemeMode.system;
        } else if (snapshot.data == 'dark') {
          themeMode = ThemeMode.dark;
        } else if (snapshot.data == 'light') {
          themeMode = ThemeMode.light;
        } else {
          themeMode = ThemeMode.system;
        }
        return MaterialApp(
          title: 'Toxee',
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: themeMode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: UpgradeRequiredScreen(
            storedVersion: storedVersion,
            currentVersion: currentVersion,
          ),
        );
      },
    );
  }
}

class UpgradeRequiredScreen extends StatelessWidget {
  const UpgradeRequiredScreen({
    super.key,
    required this.storedVersion,
    required this.currentVersion,
    this.onUpdate,
  });

  final int storedVersion;
  final int currentVersion;

  /// Seam: invoked by the primary "Update" action. Defaults to opening the
  /// canonical releases page in the system browser. Overridable so the real
  /// button handler can be driven in widget tests without a live url_launcher.
  final Future<void> Function()? onUpdate;

  Future<void> _openReleasesPage() async {
    final uri = Uri.parse(_kReleasesUrl);
    try {
      final ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        AppLogger.log('[UpgradeRequiredScreen] launchUrl returned false for $_kReleasesUrl');
      }
    } catch (e, st) {
      AppLogger.logError('[UpgradeRequiredScreen] Failed to open releases page', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          // Tighter constraint (480 → 440) keeps the eye anchored on the
          // single message and primary action even on tablet widths.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tinted-primary chip for the status icon — same visual
                  // language as the primary action card on the login page.
                  // Note on color choice: `cs.error` would alarm users (their
                  // data is fine, the app is just out of date), and
                  // `cs.tertiary` (success-emerald in this scheme) reads too
                  // positive for "blocked from using the app". Primary tint
                  // reads as "important info, action needed" — the right
                  // semantic for an out-of-date client.
                  Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppThemeConfig.tintedPrimaryCardColor(scheme.primary),
                      border: Border.all(
                        color: AppThemeConfig.tintedPrimaryCardBorderColor(scheme.primary),
                      ),
                    ),
                    child: Icon(
                      Icons.system_update,
                      size: 48,
                      color: scheme.primary,
                    ),
                  ),
                  AppSpacing.verticalXl,
                  Text(
                    l10n.upgradeRequiredTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.verticalMd,
                  Text(
                    l10n.upgradeRequiredMessage(storedVersion, currentVersion),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.verticalXl,
                  // Primary action: open the releases page in the system
                  // browser so the user can download the latest build.
                  FilledButton.icon(
                    onPressed: onUpdate ?? _openReleasesPage,
                    icon: const Icon(Icons.open_in_new),
                    label: Text(l10n.update),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                        horizontal: AppSpacing.lg,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.button),
                      ),
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
