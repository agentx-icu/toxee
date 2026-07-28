import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/runtime/session_runtime_coordinator.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/account_switcher.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/session_password_store.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'account_export/test_support.dart';

const _currentToxId = 'current-account';
const _targetToxId = 'target-account';
const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

class _CurrentService extends FfiChatService {
  _CurrentService() : super();

  @override
  String? getSelfToxId() => _currentToxId;
}

class _TargetService extends FfiChatService {
  _TargetService() : super();

  @override
  String? getSelfToxId() => _targetToxId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccountExportTestEnv env;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    SessionPasswordStore.clear();
    AccountTeardownTestHooks.reset();
    SessionRuntimeCoordinator.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (_) async => null);

    await Prefs.addAccount(
      toxId: _currentToxId,
      nickname: 'Current',
      statusMessage: '',
    );
    await Prefs.addAccount(
      toxId: _targetToxId,
      nickname: 'Target',
      statusMessage: '',
    );
    await Prefs.setCurrentAccountToxId(_currentToxId);

    final profileDirectory = await AppPaths.getProfileDirectoryForToxId(
      _currentToxId,
    );
    await Directory(profileDirectory).create(recursive: true);
    await File(
      AppPaths.profileFileInDirectory(profileDirectory),
    ).writeAsString('current-profile');
    SessionPasswordStore.set(_currentToxId, 'recovery-password');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    AccountTeardownTestHooks.reset();
    SessionRuntimeCoordinator.debugReset();
    SessionPasswordStore.clear();
    await env.dispose();
  });

  testWidgets(
    'teardown failure abandons the unusable Home session before rethrowing',
    (tester) async {
      final targetBefore = await Prefs.getAccountByToxId(_targetToxId);
      final originalFailure = StateError('profile re-encryption failed');
      var runtimeTornDown = false;
      var serviceDisposed = false;
      var encryptionAttempted = false;
      SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {
        runtimeTornDown = true;
      };
      AccountTeardownTestHooks.shutdownIrcSession = (_) async {};
      AccountTeardownTestHooks.disposeService = (_) async {
        serviceDisposed = true;
      };
      AccountTeardownTestHooks.encryptProfileFile = (_, _) async {
        encryptionAttempted = true;
        throw originalFailure;
      };

      late BuildContext homeContext;
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.8)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              homeContext = context;
              return const Scaffold(body: Text('Current Home session'));
            },
          ),
        ),
      );

      final switchFuture = AccountSwitcher.switchAccount(
        context: homeContext,
        targetToxId: _targetToxId,
        currentService: _CurrentService(),
      );
      final errorExpectation = expectLater(
        switchFuture,
        throwsA(
          isA<AccountTeardownFailure>()
              .having(
                (failure) => failure.stage,
                'stage',
                AccountTeardownStage.profileReEncryption,
              )
              .having((failure) => failure.cause, 'cause', originalFailure),
        ),
      );

      for (var frame = 0; frame < 100; frame += 1) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        if (find.byType(LoginPage).evaluate().isNotEmpty &&
            find.text('Current Home session').evaluate().isEmpty) {
          break;
        }
      }

      expect(runtimeTornDown, isTrue);
      expect(serviceDisposed, isTrue);
      expect(encryptionAttempted, isTrue);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Current Home session'), findsNothing);
      expect(await Prefs.getCurrentAccountToxId(), _currentToxId);
      expect(
        await Prefs.getAccountByToxId(_targetToxId),
        targetBefore,
        reason:
            'target initialization and boot must not run after teardown fails',
      );

      Navigator.of(tester.element(find.byType(LoginPage))).pop();
      await tester.pump();
      await errorExpectation;
    },
  );

  testWidgets(
    'protected switch with a dead context fails before teardown or init',
    (tester) async {
      late BuildContext deadContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              deadContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(deadContext.mounted, isFalse);

      var teardownCalls = 0;
      var initializeCalls = 0;
      final failure = await tester.runAsync<Object?>(() async {
        try {
          await AccountSwitcher.switchAccount(
            context: deadContext,
            targetToxId: _targetToxId,
            ensureNotDeleting: (_) async {},
            hasPasswordFn: (_) async => true,
            requestPasswordFn: (_, _) async {
              fail('password prompt must not use an unmounted context');
            },
            teardownSession: ({service, required reEncryptProfile}) async {
              teardownCalls++;
            },
            initializeService:
                ({
                  required toxId,
                  nickname,
                  statusMessage,
                  password,
                  required startPolling,
                }) async {
                  initializeCalls++;
                  return _TargetService();
                },
          );
          return null;
        } catch (error) {
          return error;
        }
      });

      expect(failure, isA<AccountSwitchContextUnavailable>());
      expect(teardownCalls, 0);
      expect(initializeCalls, 0);
      expect(await Prefs.getCurrentAccountToxId(), _currentToxId);
    },
  );

  testWidgets(
    'unmount after switch boot tears down the new service and rolls back',
    (tester) async {
      await Prefs.setNickname('Current');
      await Prefs.setStatusMessage('current status');
      final bootEntered = Completer<void>();
      final releaseBoot = Completer<void>();
      final targetService = _TargetService();
      final tornDown = <FfiChatService?>[];
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold(body: Text('Current Home session'));
            },
          ),
        ),
      );

      final switchFuture = AccountSwitcher.switchAccount(
        context: context,
        targetToxId: _targetToxId,
        ensureNotDeleting: (_) async {},
        hasPasswordFn: (_) async => false,
        teardownSession: ({service, required reEncryptProfile}) async {
          tornDown.add(service);
        },
        initializeService:
            ({
              required toxId,
              nickname,
              statusMessage,
              password,
              required startPolling,
            }) async {
              await Prefs.setCurrentAccountToxId(_targetToxId);
              await Prefs.setNickname('Target active');
              await Prefs.setStatusMessage('target active status');
              return targetService;
            },
        bootSession: (_) async {
          bootEntered.complete();
          await releaseBoot.future;
        },
        navigateHome: (_, _) async {
          fail('navigation must not run after context unmount');
        },
      );

      await bootEntered.future;
      await tester.pumpWidget(const SizedBox.shrink());
      releaseBoot.complete();

      await expectLater(
        switchFuture,
        throwsA(isA<AccountSwitchContextUnavailable>()),
      );
      expect(tornDown, [isNull, same(targetService)]);
      expect(await Prefs.getCurrentAccountToxId(), _currentToxId);
      expect(await Prefs.getNickname(), 'Current');
      expect(await Prefs.getStatusMessage(), 'current status');
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason:
            'AccountSwitcher returns typed errors; callers render them once',
      );
    },
  );

  testWidgets(
    'synchronous switch navigation failure rolls back and is sanitized',
    (tester) async {
      await Prefs.setNickname('Current');
      await Prefs.setStatusMessage('current status');
      final targetService = _TargetService();
      final tornDown = <FfiChatService?>[];
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold(body: Text('Current Home session'));
            },
          ),
        ),
      );

      Object? failure;
      try {
        await AccountSwitcher.switchAccount(
          context: context,
          targetToxId: _targetToxId,
          ensureNotDeleting: (_) async {},
          hasPasswordFn: (_) async => false,
          teardownSession: ({service, required reEncryptProfile}) async {
            tornDown.add(service);
          },
          initializeService:
              ({
                required toxId,
                nickname,
                statusMessage,
                password,
                required startPolling,
              }) async {
                await Prefs.setCurrentAccountToxId(_targetToxId);
                await Prefs.setNickname('Target active');
                await Prefs.setStatusMessage('target active status');
                return targetService;
              },
          bootSession: (_) async {},
          navigateHome: (_, _) => throw StateError('private navigator detail'),
        );
      } catch (error) {
        failure = error;
      }

      expect(failure, isA<AccountSwitchFailure>());
      expect(failure.toString(), isNot(contains('private navigator detail')));
      expect(tornDown, [isNull, same(targetService)]);
      expect(await Prefs.getCurrentAccountToxId(), _currentToxId);
      expect(await Prefs.getNickname(), 'Current');
      expect(await Prefs.getStatusMessage(), 'current status');
    },
  );

  testWidgets('concurrent switch calls share one teardown and boot', (
    tester,
  ) async {
    final teardownEntered = Completer<void>();
    final releaseTeardown = Completer<void>();
    var teardownCalls = 0;
    var initializeCalls = 0;
    var bootCalls = 0;
    var navigationCalls = 0;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: Text('Current Home session'));
          },
        ),
      ),
    );

    Future<void> runSwitch() => AccountSwitcher.switchAccount(
      context: context,
      targetToxId: _targetToxId,
      currentService: _CurrentService(),
      ensureNotDeleting: (_) async {},
      hasPasswordFn: (_) async => false,
      teardownSession: ({service, required reEncryptProfile}) async {
        teardownCalls++;
        teardownEntered.complete();
        await releaseTeardown.future;
      },
      initializeService:
          ({
            required toxId,
            nickname,
            statusMessage,
            password,
            required startPolling,
          }) async {
            initializeCalls++;
            return _TargetService();
          },
      bootSession: (_) async {
        bootCalls++;
      },
      navigateHome: (_, _) async {
        navigationCalls++;
      },
    );

    final first = runSwitch();
    final second = runSwitch();
    expect(identical(first, second), isTrue);
    await teardownEntered.future;
    expect(teardownCalls, 1);

    releaseTeardown.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(initializeCalls, 1);
    expect(bootCalls, 1);
    expect(navigationCalls, 1);
  });
}
