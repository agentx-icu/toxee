import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/main.dart' show StartupGate;
import 'package:toxee/startup/startup_outcome.dart';
import 'package:toxee/startup/startup_session_use_case.dart';
import 'package:toxee/startup/startup_step.dart';
import 'package:toxee/ui/startup_loading_screen.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

const _previousToxId =
    'ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD12345678ABCD';
const _targetToxId =
    '1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF12345678ABCD';
const _targetNickname = 'Startup target';
const _originalLoginTime = '2000-01-01T00:00:00.000Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccountExportTestEnv env;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
  });

  tearDown(() async {
    await env.dispose();
  });

  test(
    'immediate loadFriends failure tears down and rolls activation back',
    () async {
      await _stageAutoLoginAccount();
      final service = _FakeFfiChatService(isConnected: true);
      var teardownCalls = 0;
      final useCase = StartupSessionUseCase(
        bootSession: (_) async {},
        initializeServiceForAccount:
            ({
              required toxId,
              nickname,
              statusMessage,
              password,
              startPolling = true,
            }) async {
              await Prefs.setCurrentAccountToxId(toxId);
              return service;
            },
        teardownSession: ({service, reEncryptProfile = true}) async {
          teardownCalls++;
        },
      );

      final outcome = await useCase.execute(
        onStepChanged: (_) {},
        loadFriends: (_) async {
          throw StateError('friends failed before navigation');
        },
      );

      expect(outcome, isA<StartupShowError>());
      expect(teardownCalls, 1);
      expect(await Prefs.getCurrentAccountToxId(), isNull);
      expect(await _targetLastLoginTime(), _originalLoginTime);
    },
  );

  test(
    'ready outcome transfers an uncommitted activation without touching login time',
    () async {
      await _stageAutoLoginAccount();
      final service = _FakeFfiChatService(isConnected: true);
      final useCase = StartupSessionUseCase(
        bootSession: (_) async {},
        initializeServiceForAccount:
            ({
              required toxId,
              nickname,
              statusMessage,
              password,
              startPolling = true,
            }) async {
              await Prefs.setCurrentAccountToxId(toxId);
              return service;
            },
      );

      final outcome = await useCase.execute(
        onStepChanged: (_) {},
        loadFriends: (_) async {},
      );

      expect(outcome, isA<StartupOpenHome>());
      final ready = outcome as StartupOpenHome;
      expect(ready.service, same(service));
      expect(await _targetLastLoginTime(), _originalLoginTime);

      await ready.activation.rollback();
      expect(
        await Prefs.getCurrentAccountToxId(),
        isNull,
        reason: 'the use case must transfer, not commit, the activation',
      );
    },
  );

  testWidgets('post-execute unmount tears down and rolls back once', (
    tester,
  ) async {
    final lease = await _createTargetActivation();
    final outcomeCompleter = Completer<StartupOutcome>();
    final useCase = _StubStartupSessionUseCase(outcomeCompleter.future);
    var teardownCalls = 0;
    var navigationCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StartupGate(
          startupUseCase: useCase,
          navigateHome: (_, _) async {
            navigationCalls++;
          },
          teardownSession: ({service, reEncryptProfile = true}) async {
            teardownCalls++;
          },
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    outcomeCompleter.complete(StartupOpenHome(lease.service, lease.activation));
    await _flushAsync(tester);

    expect(navigationCalls, 0);
    expect(teardownCalls, 1);
    expect(await Prefs.getCurrentAccountToxId(), _previousToxId);
  });

  testWidgets('synchronous Home navigation failure remains rollbackable', (
    tester,
  ) async {
    final lease = await _createTargetActivation();
    var teardownCalls = 0;
    var touchCalls = 0;
    final teardownStarted = Completer<void>();
    final releaseTeardown = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: StartupGate(
          startupUseCase: _StubStartupSessionUseCase(
            Future<StartupOutcome>.value(
              StartupOpenHome(lease.service, lease.activation),
            ),
          ),
          navigateHome: (_, _) {
            throw StateError('private navigation detail');
          },
          teardownSession: ({service, reEncryptProfile = true}) async {
            teardownCalls++;
            teardownStarted.complete();
            await releaseTeardown.future;
          },
          touchAccountLoginTime: (_) async {
            touchCalls++;
          },
        ),
      ),
    );
    await teardownStarted.future;
    await tester.pump();

    expect(await Prefs.getCurrentAccountToxId(), _targetToxId);
    expect(
      tester
          .widget<StartupLoadingScreen>(find.byType(StartupLoadingScreen))
          .onRetry,
      isNull,
    );

    releaseTeardown.complete();
    await _flushAsync(tester);

    expect(teardownCalls, 1);
    expect(touchCalls, 0);
    expect(await Prefs.getCurrentAccountToxId(), _previousToxId);
    expect(
      tester
          .widget<StartupLoadingScreen>(find.byType(StartupLoadingScreen))
          .onRetry,
      isNotNull,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await _flushAsync(tester);
  });

  testWidgets('dispose while waiting tears down and rolls back once', (
    tester,
  ) async {
    final lease = await _createTargetActivation();
    var teardownCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StartupGate(
          startupUseCase: _StubStartupSessionUseCase(
            Future<StartupOutcome>.value(
              StartupWaitForConnection(lease.service, lease.activation),
            ),
          ),
          teardownSession: ({service, reEncryptProfile = true}) async {
            teardownCalls++;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    lease.service.emitConnection(true);
    await _flushAsync(tester);

    expect(teardownCalls, 1);
    expect(await Prefs.getCurrentAccountToxId(), _previousToxId);
  });

  testWidgets(
    'timeout and connection share one claim before Home commit and touch',
    (tester) async {
      final lease = await _createTargetActivation();
      var loadFriendsCalls = 0;
      var navigationCalls = 0;
      var touchCalls = 0;
      var teardownCalls = 0;
      String? accountDuringTouch;

      await tester.pumpWidget(
        MaterialApp(
          home: StartupGate(
            startupUseCase: _StubStartupSessionUseCase(
              Future<StartupOutcome>.value(
                StartupWaitForConnection(lease.service, lease.activation),
              ),
            ),
            loadFriends: (_) async {
              loadFriendsCalls++;
            },
            navigateHome: (_, _) async {
              navigationCalls++;
            },
            teardownSession: ({service, reEncryptProfile = true}) async {
              teardownCalls++;
            },
            touchAccountLoginTime: (_) async {
              touchCalls++;
              await lease.activation.rollback();
              accountDuringTouch = await Prefs.getCurrentAccountToxId();
            },
            connectionTimeout: const Duration(milliseconds: 1),
            completionDelay: Duration.zero,
          ),
        ),
      );
      await tester.pump();

      lease.service.emitConnection(true);
      await tester.pump(const Duration(milliseconds: 1));
      lease.service.emitConnection(true);
      await _flushAsync(tester);

      expect(navigationCalls, 1);
      expect(loadFriendsCalls, lessThanOrEqualTo(1));
      expect(touchCalls, 1);
      expect(accountDuringTouch, _targetToxId);
      expect(teardownCalls, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await _flushAsync(tester);
      expect(teardownCalls, 0);
    },
  );

  testWidgets('retry startup is single-flight', (tester) async {
    final useCase = _RetryStartupSessionUseCase();

    await tester.pumpWidget(
      MaterialApp(home: StartupGate(startupUseCase: useCase)),
    );
    await _flushAsync(tester);
    expect(useCase.calls, 1);

    final loadingScreen = tester.widget<StartupLoadingScreen>(
      find.byType(StartupLoadingScreen),
    );
    expect(loadingScreen.onRetry, isNotNull);
    loadingScreen.onRetry!();
    loadingScreen.onRetry!();
    await tester.pump();

    expect(
      useCase.calls,
      2,
      reason: 'rapid retry taps must join the same startup attempt',
    );

    useCase.retryOutcome.complete(const StartupShowError('retry failed'));
    await _flushAsync(tester);
  });
}

Future<void> _stageAutoLoginAccount() async {
  await Prefs.setAccountList([
    {
      'toxId': _targetToxId,
      'nickname': _targetNickname,
      'statusMessage': '',
      'lastLoginTime': _originalLoginTime,
    },
  ]);
  await Prefs.setCurrentAccountToxId(null);
  await Prefs.setNickname(_targetNickname);
  await Prefs.setStatusMessage('');
  await Prefs.setAutoLogin(true);
}

Future<String?> _targetLastLoginTime() async {
  final account = await Prefs.getAccountByToxId(_targetToxId);
  return account?['lastLoginTime'];
}

Future<({AccountActivationTransaction activation, _FakeFfiChatService service})>
_createTargetActivation() async {
  await Prefs.setCurrentAccountToxId(_previousToxId);
  await Prefs.setNickname('Previous');
  await Prefs.setStatusMessage('Previous status');
  final activation = await AccountActivationTransaction.begin();
  await Prefs.setCurrentAccountToxId(_targetToxId);
  await Prefs.setNickname(_targetNickname);
  await Prefs.setStatusMessage('Target status');
  return (
    activation: activation,
    service: _FakeFfiChatService(isConnected: false),
  );
}

Future<void> _flushAsync(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

final class _StubStartupSessionUseCase extends StartupSessionUseCase {
  _StubStartupSessionUseCase(this.outcome)
    : super(bootSession: _unusedBootSession);

  final Future<StartupOutcome> outcome;

  @override
  Future<StartupOutcome> execute({
    required void Function(StartupStep) onStepChanged,
    required Future<void> Function(FfiChatService) loadFriends,
  }) => outcome;
}

final class _RetryStartupSessionUseCase extends StartupSessionUseCase {
  _RetryStartupSessionUseCase() : super(bootSession: _unusedBootSession);

  int calls = 0;
  final Completer<StartupOutcome> retryOutcome = Completer<StartupOutcome>();

  @override
  Future<StartupOutcome> execute({
    required void Function(StartupStep) onStepChanged,
    required Future<void> Function(FfiChatService) loadFriends,
  }) {
    calls++;
    if (calls == 1) {
      return Future<StartupOutcome>.value(
        const StartupShowError('first startup failed'),
      );
    }
    return retryOutcome.future;
  }
}

Future<void> _unusedBootSession(FfiChatService _) async {}

final class _FakeFfiChatService implements FfiChatService {
  _FakeFfiChatService({required this.isConnected});

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast(sync: true);

  @override
  final bool isConnected;

  @override
  Stream<bool> get connectionStatusStream => _connectionController.stream;

  void emitConnection(bool connected) {
    if (!_connectionController.isClosed) {
      _connectionController.add(connected);
    }
  }

  @override
  String? getSelfToxId() => _targetToxId;

  @override
  String get selfId => _targetToxId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
