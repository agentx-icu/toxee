import 'logger.dart';

final class SafeDiagnostics {
  SafeDiagnostics._();

  static String describeError(Object error) {
    return 'error_type=${error.runtimeType}';
  }

  static void logFailure(String context, Object error) {
    AppLogger.error('$context ${describeError(error)}');
  }
}
