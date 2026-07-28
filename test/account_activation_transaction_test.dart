import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/runtime/session_runtime_coordinator.dart';
import 'package:toxee/startup/startup_outcome.dart';
import 'package:toxee/startup/startup_session_use_case.dart';
import 'package:toxee/ui/login/login_page_controller.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/account_switcher.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';
import 'account_export/tox_profile_factory.dart';

const _previousToxId =
    'ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD12345678ABCD';
const _manualTargetToxId =
    '1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF12345678ABCD';
const _previousNickname = 'Previous nickname';
const _previousStatusMessage = 'Previous status';
const _previousAvatarPath = '/avatars/previous.png';
const _targetNickname = 'Target nickname';
const _targetStatusMessage = 'Target status';
const _targetAvatarPath = '/avatars/target.png';
const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccountExportTestEnv env;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    SessionRuntimeCoordinator.debugReset();
    AccountTeardownTestHooks.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async {
          switch (call.method) {
            case 'containsKey':
              return false;
            case 'readAll':
              return <String, String>{};
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
    AccountTeardownTestHooks.reset();
    SessionRuntimeCoordinator.debugReset();
    await env.dispose();
  });

  test(
    'startup boot failure restores the complete active-account mirror',
    () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('tim2tox FFI library not loadable in this environment');
        return;
      }
      await _stageProfile(fixture);
      await Prefs.addAccount(
        toxId: fixture.toxId,
        nickname: 'Startup target',
        statusMessage: '',
        avatarPath: _targetAvatarPath,
      );
      await Prefs.addAccount(
        toxId: _previousToxId,
        nickname: _previousNickname,
        statusMessage: _previousStatusMessage,
        avatarPath: _previousAvatarPath,
      );
      await Prefs.setCurrentAccountToxId(_previousToxId);
      await Prefs.setNickname('Startup target');
      await Prefs.setStatusMessage(_previousStatusMessage);
      SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {};
      AccountTeardownTestHooks.shutdownIrcSession = (_) async {};

      final outcome = await StartupSessionUseCase(
        bootSession: (_) async {
          await _writeActiveAccountMirror(
            toxId: fixture.toxId,
            nickname: _targetNickname,
            statusMessage: _targetStatusMessage,
            avatarPath: _targetAvatarPath,
          );
          throw StateError('startup boot failed');
        },
      ).execute(onStepChanged: (_) {}, loadFriends: (_) async {});

      expect(outcome, isA<StartupShowError>());
      expect(await Prefs.getCurrentAccountToxId(), _previousToxId);
      expect(await Prefs.getNickname(), 'Startup target');
      expect(await Prefs.getStatusMessage(), _previousStatusMessage);
      expect(await Prefs.getAvatarPath(), _previousAvatarPath);
    },
  );

  testWidgets(
    'manual login boot failure restores the complete mirror with no account current',
    (tester) async {
      await Prefs.addAccount(
        toxId: _manualTargetToxId,
        nickname: 'Manual target',
        statusMessage: '',
        avatarPath: _targetAvatarPath,
      );
      await Prefs.setCurrentAccountToxId(null);
      await Prefs.setNickname(_previousNickname);
      await Prefs.setStatusMessage('');
      await Prefs.setAvatarPath(_previousAvatarPath);
      final service = _FakeFfiChatService(_manualTargetToxId);
      final controller = _ActivatingLoginPageController(
        service: service,
        targetToxId: _manualTargetToxId,
      );
      var teardownCalls = 0;

      await tester.binding.setSurfaceSize(const Size(1024, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final originalOnError = FlutterError.onError;
      addTearDown(() => FlutterError.onError = originalOnError);
      FlutterError.onError = (details) {
        if (details.exception.toString().contains('A RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            TencentCloudChatLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: LoginPage(
            loginPageController: controller,
            bootSession: (_) async {
              throw StateError('manual boot failed');
            },
            teardownSession:
                ({required service, reEncryptProfile = true}) async {
                  teardownCalls++;
                  throw StateError('manual cleanup failed');
                },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(
        find.byKey(UiKeys.loginPageAccountCard(_manualTargetToxId)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(teardownCalls, 1);
      expect(await Prefs.getCurrentAccountToxId(), isNull);
      expect(await Prefs.getNickname(), _previousNickname);
      expect(await Prefs.getStatusMessage(), isNull);
      expect(await Prefs.getAvatarPath(), _previousAvatarPath);
      expect(find.textContaining('error_type=StateError'), findsWidgets);
      expect(find.textContaining('manual boot failed'), findsNothing);
    },
  );

  testWidgets(
    'account-switch boot failure restores the complete active-account mirror',
    (tester) async {
      await Prefs.addAccount(
        toxId: _previousToxId,
        nickname: _previousNickname,
        statusMessage: _previousStatusMessage,
        avatarPath: _previousAvatarPath,
      );
      await Prefs.addAccount(
        toxId: _manualTargetToxId,
        nickname: 'Switch target',
        statusMessage: '',
        avatarPath: _targetAvatarPath,
      );
      await Prefs.setCurrentAccountToxId(_previousToxId);
      await Prefs.setNickname(_previousNickname);
      await Prefs.setStatusMessage(_previousStatusMessage);
      final service = _FakeFfiChatService(_manualTargetToxId);

      late BuildContext switchContext;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            TencentCloudChatLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: Builder(
            builder: (context) {
              switchContext = context;
              return const Scaffold(body: Text('Current Home session'));
            },
          ),
        ),
      );
      expect(switchContext.mounted, isTrue);

      final steps = <String>[];
      final switchError = await tester.runAsync<Object?>(() async {
        try {
          await AccountSwitcher.switchAccount(
            context: switchContext,
            targetToxId: _manualTargetToxId,
            ensureNotDeleting: (_) async {},
            hasPasswordFn: (_) async => false,
            initializeService:
                ({
                  required toxId,
                  nickname,
                  statusMessage,
                  password,
                  required startPolling,
                }) async {
                  steps.add('initialize');
                  await _writeActiveAccountMirror(
                    toxId: toxId,
                    nickname: _targetNickname,
                    statusMessage: _targetStatusMessage,
                    avatarPath: _targetAvatarPath,
                  );
                  return service;
                },
            teardownSession: ({service, required reEncryptProfile}) async {
              steps.add(service == null ? 'teardown-current' : 'teardown-new');
              if (service != null) {
                throw StateError('switch cleanup failed');
              }
            },
            bootSession: (_) async {
              steps.add('boot');
              throw StateError('switch boot failed');
            },
          );
          return null;
        } catch (error) {
          return error;
        }
      });

      expect(steps, ['teardown-current', 'initialize', 'boot', 'teardown-new']);
      expect(switchError, isA<AccountSwitchFailure>());
      expect(await Prefs.getCurrentAccountToxId(), _previousToxId);
      expect(await Prefs.getNickname(), _previousNickname);
      expect(await Prefs.getStatusMessage(), _previousStatusMessage);
      expect(await Prefs.getAvatarPath(), _previousAvatarPath);
    },
  );

  testWidgets(
    'manual login unmount after boot tears down and restores mirrors',
    (tester) async {
      await Prefs.addAccount(
        toxId: _previousToxId,
        nickname: _previousNickname,
        statusMessage: _previousStatusMessage,
        avatarPath: _previousAvatarPath,
      );
      await Prefs.addAccount(
        toxId: _manualTargetToxId,
        nickname: 'Manual target',
        statusMessage: '',
        avatarPath: _targetAvatarPath,
      );
      await _writeActiveAccountMirror(
        toxId: _previousToxId,
        nickname: _previousNickname,
        statusMessage: _previousStatusMessage,
        avatarPath: _previousAvatarPath,
      );
      final service = _FakeFfiChatService(_manualTargetToxId);
      final controller = _ActivatingLoginPageController(
        service: service,
        targetToxId: _manualTargetToxId,
      );
      final bootEntered = Completer<void>();
      final releaseBoot = Completer<void>();
      var teardownCalls = 0;
      var navigationCalls = 0;

      await tester.binding.setSurfaceSize(const Size(1024, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      _ignoreKnownAccountCardOverflow(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            TencentCloudChatLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: LoginPage(
            loginPageController: controller,
            bootSession: (_) async {
              bootEntered.complete();
              await releaseBoot.future;
            },
            teardownSession:
                ({required service, reEncryptProfile = true}) async {
                  teardownCalls++;
                },
            navigateHome: (_, _) async {
              navigationCalls++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(
        find.byKey(UiKeys.loginPageAccountCard(_manualTargetToxId)),
      );
      while (!bootEntered.isCompleted) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      releaseBoot.complete();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );

      expect(teardownCalls, 1);
      expect(navigationCalls, 0);
      expect(await Prefs.getCurrentAccountToxId(), _previousToxId);
      expect(await Prefs.getNickname(), _previousNickname);
      expect(await Prefs.getStatusMessage(), _previousStatusMessage);
      expect(await Prefs.getAvatarPath(), _previousAvatarPath);
    },
  );

  testWidgets('manual login sync navigation failure remains rollbackable', (
    tester,
  ) async {
    await Prefs.addAccount(
      toxId: _previousToxId,
      nickname: _previousNickname,
      statusMessage: _previousStatusMessage,
      avatarPath: _previousAvatarPath,
    );
    await Prefs.addAccount(
      toxId: _manualTargetToxId,
      nickname: 'Manual target',
      statusMessage: '',
      avatarPath: _targetAvatarPath,
    );
    await _writeActiveAccountMirror(
      toxId: _previousToxId,
      nickname: _previousNickname,
      statusMessage: _previousStatusMessage,
      avatarPath: _previousAvatarPath,
    );
    final service = _FakeFfiChatService(_manualTargetToxId);
    final controller = _ActivatingLoginPageController(
      service: service,
      targetToxId: _manualTargetToxId,
    );
    var teardownCalls = 0;

    await tester.binding.setSurfaceSize(const Size(1024, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _ignoreKnownAccountCardOverflow(tester);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          TencentCloudChatLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: LoginPage(
          loginPageController: controller,
          bootSession: (_) async {},
          teardownSession: ({required service, reEncryptProfile = true}) async {
            teardownCalls++;
          },
          navigateHome: (_, _) => throw StateError('private navigation detail'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(
      find.byKey(UiKeys.loginPageAccountCard(_manualTargetToxId)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(teardownCalls, 1);
    expect(await Prefs.getCurrentAccountToxId(), _previousToxId);
    expect(await Prefs.getNickname(), _previousNickname);
    expect(await Prefs.getStatusMessage(), _previousStatusMessage);
    expect(await Prefs.getAvatarPath(), _previousAvatarPath);
    expect(find.textContaining('private navigation detail'), findsNothing);
    expect(find.textContaining('error_type=StateError'), findsWidgets);
  });

  test('commit preserves the complete target mirror', () async {
    await Prefs.addAccount(
      toxId: _previousToxId,
      nickname: _previousNickname,
      statusMessage: _previousStatusMessage,
      avatarPath: _previousAvatarPath,
    );
    await Prefs.addAccount(
      toxId: _manualTargetToxId,
      nickname: _targetNickname,
      statusMessage: _targetStatusMessage,
      avatarPath: _targetAvatarPath,
    );
    await _writeActiveAccountMirror(
      toxId: _previousToxId,
      nickname: _previousNickname,
      statusMessage: _previousStatusMessage,
      avatarPath: _previousAvatarPath,
    );
    final transaction = await AccountActivationTransaction.begin();

    await _writeActiveAccountMirror(
      toxId: _manualTargetToxId,
      nickname: _targetNickname,
      statusMessage: _targetStatusMessage,
      avatarPath: _targetAvatarPath,
    );
    transaction.commit();
    await transaction.rollback();
    await transaction.rollback();

    expect(await Prefs.getCurrentAccountToxId(), _manualTargetToxId);
    expect(await Prefs.getNickname(), _targetNickname);
    expect(await Prefs.getStatusMessage(), _targetStatusMessage);
    expect(await Prefs.getAvatarPath(), _targetAvatarPath);
  });
}

Future<void> _writeActiveAccountMirror({
  required String toxId,
  required String nickname,
  required String statusMessage,
  required String? avatarPath,
}) async {
  await Prefs.setCurrentAccountToxId(toxId);
  await Prefs.setNickname(nickname);
  await Prefs.setStatusMessage(statusMessage);
  await Prefs.setAvatarPath(avatarPath);
}

Future<void> _stageProfile(ToxProfileFixture fixture) async {
  final profileDirectory = await AppPaths.getProfileDirectoryForToxId(
    fixture.toxId,
  );
  await Directory(profileDirectory).create(recursive: true);
  await File(
    AppPaths.profileFileInDirectory(profileDirectory),
  ).writeAsBytes(fixture.savedata, flush: true);
}

final class _ActivatingLoginPageController extends LoginPageController {
  _ActivatingLoginPageController({
    required this.service,
    required this.targetToxId,
  });

  final FfiChatService service;
  final String targetToxId;

  @override
  Future<LoginControllerResult> login({
    required String nickname,
    required String statusMessage,
    String? password,
  }) async {
    await _writeActiveAccountMirror(
      toxId: targetToxId,
      nickname: _targetNickname,
      statusMessage: _targetStatusMessage,
      avatarPath: _targetAvatarPath,
    );
    return LoginControllerSuccess(service);
  }
}

final class _FakeFfiChatService implements FfiChatService {
  _FakeFfiChatService(this._toxId);

  final String _toxId;

  @override
  String? getSelfToxId() => _toxId;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _ignoreKnownAccountCardOverflow(WidgetTester tester) {
  final originalOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = originalOnError);
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('A RenderFlex overflowed')) {
      return;
    }
    originalOnError?.call(details);
  };
}
