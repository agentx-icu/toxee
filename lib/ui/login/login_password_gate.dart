import '../../util/prefs.dart';

/// Result of resolving a saved account's password before login.
///
/// A value type rather than a nullable `String`, because the outcomes need
/// different UI: two are user actions (cancelled, wrong password), one is an
/// environment fault worth naming (the secure store would not answer), and one
/// means no password is needed at all. Collapsing them is how "secure storage
/// unavailable" came to be reported to the user as "Invalid password".
enum PasswordGateResult {
  /// The account is not password-protected.
  notRequired,

  /// A password was supplied and verified — [PasswordGateOutcome.password] holds
  /// it so the caller can pass it to init without prompting twice.
  verified,

  /// The user dismissed the prompt. Not an error; say nothing.
  cancelled,

  /// The supplied password did not match.
  invalid,

  /// Secure storage would not answer, so whether the account is protected — and
  /// therefore whether any password is correct — is unknown. Transient.
  storeUnavailable,
}

/// [PasswordGateResult] plus the verified password, when there is one.
final class PasswordGateOutcome {
  const PasswordGateOutcome._(this.result, this.password);

  const PasswordGateOutcome.notRequired()
    : this._(PasswordGateResult.notRequired, null);
  const PasswordGateOutcome.verified(String password)
    : this._(PasswordGateResult.verified, password);
  const PasswordGateOutcome.cancelled()
    : this._(PasswordGateResult.cancelled, null);
  const PasswordGateOutcome.invalid()
    : this._(PasswordGateResult.invalid, null);
  const PasswordGateOutcome.storeUnavailable()
    : this._(PasswordGateResult.storeUnavailable, null);

  final PasswordGateResult result;

  /// Non-null only for [PasswordGateResult.verified].
  final String? password;
}

/// Resolve the password for a saved account before login.
///
/// Both login entry points — the saved-account card and the nickname form —
/// needed this exact sequence (consult the cached verified password, branch on
/// the protection TRI-STATE, prompt, verify) and each carried its own copy with
/// its own error handling.
///
/// Takes no `BuildContext`: the caller supplies [promptForPassword] and owns
/// every piece of UI, which keeps the async-gap rules where its State can see
/// them.
///
/// [cachedVerifiedPassword] is a password this session already verified for this
/// account, so the user is not asked twice in one flow. Treat it as single-use:
/// the caller clears it after this returns.
Future<PasswordGateOutcome> resolveAccountPassword({
  required String toxId,
  required String? cachedVerifiedPassword,
  required Future<String?> Function() promptForPassword,
}) async {
  final cached = cachedVerifiedPassword;
  final hasCached = cached != null && cached.isNotEmpty;
  // The TRI-STATE, not a bool. `hasAccountPassword` folds "the secure store
  // would not answer" into `true`, which is the right default for a gate but the
  // wrong thing to show a user: these callers prompt and verify BEFORE invoking
  // `LoginUseCase`, so an unreadable Keychain produced a password prompt
  // followed by "Invalid password" — telling the user their own correct password
  // was wrong. The condition is transient (a locked keychain, a missing
  // entitlement, a plugin that failed to register), so name it and let them
  // retry.
  final protection = hasCached
      ? AccountProtectionState.protected
      : await Prefs.accountProtectionState(toxId);
  if (protection == AccountProtectionState.unknown) {
    return const PasswordGateOutcome.storeUnavailable();
  }
  if (protection == AccountProtectionState.none) {
    return const PasswordGateOutcome.notRequired();
  }
  if (hasCached) return PasswordGateOutcome.verified(cached);
  final entered = await promptForPassword();
  if (entered == null || entered.isEmpty) {
    return const PasswordGateOutcome.cancelled();
  }
  if (!await Prefs.verifyAccountPassword(toxId, entered)) {
    return const PasswordGateOutcome.invalid();
  }
  return PasswordGateOutcome.verified(entered);
}
