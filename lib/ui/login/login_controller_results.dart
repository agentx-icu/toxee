// Result types for [LoginPageController]'s login / import / restore entry
// points.
//
// Split out of `login_page_controller.dart` (it had grown past the complexity
// gate's pin). These are pure data — sealed result hierarchies plus the two
// failure-kind enums the UI maps to localized copy — so they carry no behaviour
// and nothing here depends on the controller.

import 'package:tim2tox_dart/service/ffi_chat_service.dart';

/// Result of [LoginPageController.login].
sealed class LoginControllerResult {
  const LoginControllerResult();
}

final class LoginControllerSuccess extends LoginControllerResult {
  const LoginControllerSuccess(this.service);
  final FfiChatService service;
}

final class LoginControllerFailure extends LoginControllerResult {
  const LoginControllerFailure(this.message);
  final String message;
}

/// Result of [LoginPageController.importAccount].
sealed class ImportResult {
  const ImportResult();
}

final class ImportSuccess extends ImportResult {
  const ImportSuccess();
}

/// Reason an import failed. The UI maps this to a localized message;
/// keeping a kind enum (instead of stringly-typed messages) lets the UI
/// distinguish user-initiated cancellation from genuine errors without
/// fragile string comparisons.
enum ImportFailureKind {
  noFileSelected,
  cancelled,
  invalidPassword,
  accountAlreadyExists,
  generalError,
}

final class ImportFailure extends ImportResult {
  const ImportFailure(this.kind, {this.detail});
  final ImportFailureKind kind;

  /// Sanitized runtime-type detail for [ImportFailureKind.generalError]; null
  /// for cancellation / file-not-selected / duplicate-account cases.
  final String? detail;
}

/// Reason a restore failed. Mirrors [ImportFailureKind] but is scoped to the
/// .tox-only "Restore from .tox file" first-class login entry. Kept as a
/// separate enum so the UI can show restore-specific copy ("This file doesn't
/// look like a valid Tox profile") without bleeding restore strings into the
/// generic import path.
enum RestoreFailureKind {
  noFileSelected,
  cancelled,
  invalidPassword,
  accountAlreadyExists,
  notAToxProfile,
  generalError,
}

/// Result of [LoginPageController.restoreFromToxFile].
sealed class RestoreResult {
  const RestoreResult();
}

final class RestoreSuccess extends RestoreResult {
  const RestoreSuccess({
    required this.toxId,
    required this.nickname,
    this.password,
  });
  final String toxId;
  final String nickname;
  final String? password;
}

final class RestoreFailure extends RestoreResult {
  const RestoreFailure(this.kind, {this.detail});
  final RestoreFailureKind kind;
  final String? detail;
}
