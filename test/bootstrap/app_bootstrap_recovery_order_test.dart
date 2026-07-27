import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/bootstrap/app_bootstrap.dart';

void main() {
  test('pending recoveries complete before account reconciliation', () async {
    final restoreStarted = Completer<void>();
    final releaseRestore = Completer<void>();
    final events = <String>[];

    final future = AppBootstrap.recoverPendingRestoreBeforeAccountExposure(
      recoverPendingRestore: () async {
        events.add('restore:start');
        restoreStarted.complete();
        await releaseRestore.future;
        events.add('restore:complete');
      },
      recoverPendingDeletions: () async => events.add('deletion:complete'),
      reconcileAccounts: () async => events.add('reconciliation'),
    );

    await restoreStarted.future;
    expect(events, <String>['restore:start']);

    releaseRestore.complete();
    await future;
    expect(events, <String>[
      'restore:start',
      'restore:complete',
      'deletion:complete',
      'reconciliation',
    ]);
  });

  test(
    'recovery failure propagates and prevents account reconciliation',
    () async {
      final failure = StateError('restore journal is unreadable');
      var reconciled = false;

      await expectLater(
        AppBootstrap.recoverPendingRestoreBeforeAccountExposure(
          recoverPendingRestore: () async => throw failure,
          recoverPendingDeletions: () async {},
          reconcileAccounts: () async => reconciled = true,
        ),
        throwsA(same(failure)),
      );

      expect(reconciled, isFalse);
    },
  );

  test('application bootstrap awaits the fail-closed recovery gate', () async {
    final source = await File(
      'lib/bootstrap/app_bootstrap.dart',
    ).readAsString();

    expect(
      source,
      contains('await recoverPendingRestoreBeforeAccountExposure();'),
    );
    expect(source, contains('await recoverDeletions();'));
    expect(
      source,
      isNot(contains('full-backup restore recovery failed; continuing')),
    );
  });
}
