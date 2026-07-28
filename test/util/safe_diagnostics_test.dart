import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/logger.dart';
import 'package:toxee/util/safe_diagnostics.dart';

const _messageSecret = 'MESSAGE_SECRET_9cf34a';
const _stackSecret = 'STACK_SECRET_2d69b1';
const _pathSecret = '/private/secret/path_61e980';
const _filenameSecret = 'account_backup_743bd2.tox';
const _accountIdSecret = 'ACCOUNT_ID_SECRET_a4149c';
const _payloadSecret = 'PAYLOAD_SECRET_b56f08';

class SentinelFailure implements Exception {
  SentinelFailure({
    required this.message,
    required this.stack,
    required this.path,
    required this.filename,
    required this.accountId,
    required this.payload,
  });

  final String message;
  final StackTrace stack;
  final String path;
  final String filename;
  final String accountId;
  final String payload;

  @override
  String toString() {
    return '$message $stack $path $filename $accountId $payload';
  }
}

SentinelFailure _failure(String suffix) {
  return SentinelFailure(
    message: '$_messageSecret$suffix',
    stack: StackTrace.fromString('$_stackSecret$suffix'),
    path: '$_pathSecret$suffix',
    filename: '$_filenameSecret$suffix',
    accountId: '$_accountIdSecret$suffix',
    payload: '$_payloadSecret$suffix',
  );
}

void main() {
  group('SafeDiagnostics', () {
    late Directory tempDir;
    late File logFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('safe_diagnostics_');
      logFile = File('${tempDir.path}${Platform.pathSeparator}app.log');
      AppLogger.resetForTesting();
      AppLogger.setLogPath(logFile.path);
      await AppLogger.initialize();
    });

    tearDown(() async {
      AppLogger.resetForTesting();
      await tempDir.delete(recursive: true);
    });

    test('describeError returns only a stable runtime-type token', () {
      expect(
        SafeDiagnostics.describeError(_failure('_first')),
        'error_type=SentinelFailure',
      );
      expect(
        SafeDiagnostics.describeError(_failure('_second')),
        'error_type=SentinelFailure',
      );
    });

    test('logFailure omits all exception details', () async {
      SafeDiagnostics.logFailure('account_restore_failed', _failure(''));

      final logged = await logFile.readAsString();
      expect(logged, contains('account_restore_failed'));
      expect(logged, contains('error_type=SentinelFailure'));
      for (final secret in <String>[
        _messageSecret,
        _stackSecret,
        _pathSecret,
        _filenameSecret,
        _accountIdSecret,
        _payloadSecret,
      ]) {
        expect(logged, isNot(contains(secret)));
      }
    });
  });
}
