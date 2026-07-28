import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../util/account_service.dart';

/// Result of [StartupSessionUseCase.execute].
/// Widget reacts by updating UI and/or navigating.
sealed class StartupOutcome {
  const StartupOutcome();
}

/// No registered user or auto-login disabled; show login/registration.
final class StartupShowLogin extends StartupOutcome {
  const StartupShowLogin();
}

/// Startup failed; show error message and retry/go-to-login.
final class StartupShowError extends StartupOutcome {
  const StartupShowError(this.message);
  final String message;
}

/// Service is ready and (if needed) friends loaded; navigate to home.
///
/// The caller owns the uncommitted [activation]. It must synchronously schedule
/// Home before committing it, or tear down [service] and roll it back before
/// abandoning this outcome.
final class StartupOpenHome extends StartupOutcome {
  const StartupOpenHome(this.service, this.activation);
  final FfiChatService service;
  final AccountActivationTransaction activation;
}

/// Service created but not yet connected; widget must wait and then load friends
/// and navigate.
///
/// The caller owns [service] and the uncommitted [activation] as one lease. It
/// must synchronously schedule Home before committing, or tear down and roll
/// back both when waiting or pre-navigation work is abandoned.
final class StartupWaitForConnection extends StartupOutcome {
  const StartupWaitForConnection(this.service, this.activation);
  final FfiChatService service;
  final AccountActivationTransaction activation;
}
