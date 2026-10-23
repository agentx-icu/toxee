import 'diagnostic_record.dart';
import 'logger.dart';

final class SafeDiagnostics {
  SafeDiagnostics._();

  static String describeError(Object error) {
    return 'error_type=${DiagnosticRecord.errorCategory(error)}';
  }

  static void logFailure(String context, Object error) {
    AppLogger.recordError(DiagnosticOrigin.application, error, null);
    AppLogger.error('$context ${describeError(error)}');
  }
}
