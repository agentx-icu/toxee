/// Barrel: re-exports the public account-export API so existing imports of
/// `package:toxee/util/account_export_service.dart` keep resolving without
/// changes after the split into `lib/util/account_export/`.
///
/// New code may import the submodules directly if it only needs a slice of
/// the surface, but the static façade `AccountExportService` remains the
/// canonical entry point used by all current call sites.
library;

export 'account_export/account_export_service.dart'
    show AccountExportService, PasswordRequiredException;
