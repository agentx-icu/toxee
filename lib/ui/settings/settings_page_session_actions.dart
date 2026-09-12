part of 'settings_page.dart';

// Ending the session, split out of `settings_page.dart` (complexity-gate pin).
// Two entry points with deliberately different consent: the Log out button asks
// first, the legacy-data recovery flow has already asked its own question and
// must not be cancellable at this stage.

extension _SettingsSessionActions on _SettingsPageState {
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.logOut),
        content: Text(AppLocalizations.of(context)!.logOutConfirm),
        actions: [
          TextButton(
            key: UiKeys.settingsLogoutCancelButton,
            onPressed: () => popDialogIfCurrent(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            key: UiKeys.settingsLogoutConfirmButton,
            onPressed: () => popDialogIfCurrent(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(AppLocalizations.of(context)!.logOut),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _performLogout();
    }
  }

  /// End the session, WITHOUT asking again.
  ///
  /// Split out of [_logout] for the legacy-data recovery flow, which used to
  /// call `_logout()` after committing the claim - and that opens a SECOND
  /// confirmation the user can cancel. Cancelling left the claim recorded (the
  /// recovery button is gone) while the session kept running, so an offline send
  /// created the destination queue and the merge at the next sign-in had two
  /// queues to reconcile instead of one to install: the legacy messages then sat
  /// in an inert `.legacy.json` and were never sent. The recovery dialog is the
  /// consent; there is nothing for a second one to add.
  Future<void> _performLogout() async {
    final homeRoute = ModalRoute.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(HapticFeedback.heavyImpact());
    if (homeRoute != null) {
      navigator.popUntil(
        (route) => route.isFirst || identical(route, homeRoute),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await _teardownSession(service: widget.service);
    await Prefs.setCurrentAccountToxId(null);

    if (!mounted) return;
    await navigator.pushAndRemoveUntil(
      AppPageRoute<void>(page: const LoginPage()),
      (route) => false,
    );
  }
}
