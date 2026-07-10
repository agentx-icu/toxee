// Applications/IRC page real-UI L1 coverage.
//
// The dialog has its own focused tests. This file mounts the production
// ApplicationsPage and injects an in-memory ApplicationsIrcController so the
// page list, install state, config form, channel list, live status updates, and
// remove confirmation are driven without loading the real IRC dylib or FFI.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/applications/applications_page.dart';
import 'package:toxee/util/irc_app_manager.dart' show IrcAddChannelResult;
import 'package:toxee/ui/testing/ui_keys.dart';

class _FakeApplicationsIrcController implements ApplicationsIrcController {
  _FakeApplicationsIrcController({
    this.installed = false,
    List<String> channels = const [],
    this.server = 'irc.example.net',
    this.port = 6667,
    this.useSasl = false,
    this.libraryLoadsOnInstall = true,
    this.addChannelConnects = true,
    Set<String> connectedChannels = const {},
  })  : channels = List<String>.of(channels),
        connectedChannels = Set<String>.of(connectedChannels);

  bool installed;
  List<String> channels;
  String server;
  int port;
  bool useSasl;
  int installCalls = 0;
  int uninstallCalls = 0;
  // Controls the honest-outcome paths added to the controller contract.
  bool libraryLoadsOnInstall = true;
  bool addChannelConnects = true;
  Set<String> connectedChannels = {};
  final List<String> removedChannels = [];
  final List<({String channel, String? password, String? customNickname})>
  addedChannels = [];
  ({String server, int port, bool useSasl})? savedConfig;

  final _statusController =
      StreamController<
        ({String channel, int status, String? message})
      >.broadcast();
  final _usersController =
      StreamController<({String channel, List<String> users})>.broadcast();
  final _joinPartController =
      StreamController<
        ({String channel, String nickname, bool joined})
      >.broadcast();

  @override
  Stream<({String channel, int status, String? message})>
  get ircConnectionStatusStream => _statusController.stream;

  @override
  Stream<({String channel, List<String> users})> get ircUserListStream =>
      _usersController.stream;

  @override
  Stream<({String channel, String nickname, bool joined})>
  get ircUserJoinPartStream => _joinPartController.stream;

  @override
  Future<ApplicationsIrcSnapshot> loadState() async => ApplicationsIrcSnapshot(
    isInstalled: installed,
    channels: List<String>.of(channels),
    server: server,
    port: port,
    useSasl: useSasl,
  );

  @override
  Future<void> saveConfig({
    required String server,
    required int port,
    required bool useSasl,
  }) async {
    this.server = server;
    this.port = port;
    this.useSasl = useSasl;
    savedConfig = (server: server, port: port, useSasl: useSasl);
  }

  @override
  Future<bool> install() async {
    installCalls++;
    installed = true;
    return libraryLoadsOnInstall;
  }

  @override
  Future<void> uninstall() async {
    uninstallCalls++;
    installed = false;
    channels.clear();
    connectedChannels.clear();
  }

  @override
  Future<IrcAddChannelResult> addChannel(
    String channel, {
    String? password,
    String? customNickname,
  }) async {
    addedChannels.add((
      channel: channel,
      password: password,
      customNickname: customNickname,
    ));
    channels.add(channel);
    if (addChannelConnects) connectedChannels.add(channel);
    return IrcAddChannelResult(
      added: true,
      connected: addChannelConnects,
      groupId: 'group_$channel',
    );
  }

  @override
  Future<void> removeChannel(String channel) async {
    removedChannels.add(channel);
    channels.remove(channel);
    connectedChannels.remove(channel);
  }

  @override
  Future<bool> isChannelConnected(String channel) async =>
      connectedChannels.contains(channel);

  void emitStatus(String channel, int status, {String? message}) {
    _statusController.add((channel: channel, status: status, message: message));
  }

  void emitUsers(String channel, List<String> users) {
    _usersController.add((channel: channel, users: users));
  }

  Future<void> dispose() async {
    await _statusController.close();
    await _usersController.close();
    await _joinPartController.close();
  }
}

Widget _harness(_FakeApplicationsIrcController controller) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: ApplicationsPage(ircController: controller),
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeApplicationsIrcController controller,
) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(controller.dispose);

  await tester.pumpWidget(_harness(controller));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'IRC app card installs and reveals the config + empty channel list',
    (tester) async {
      final controller = _FakeApplicationsIrcController(
        server: 'irc.example.net',
        port: 6667,
        useSasl: false,
      );
      await _pumpPage(tester, controller);

      expect(find.byKey(UiKeys.applicationsIrcCard), findsOneWidget);
      expect(find.text('IRC Channel'), findsOneWidget);
      expect(find.byKey(UiKeys.applicationsIrcInstallButton), findsOneWidget);
      expect(find.text('IRC Server Configuration'), findsNothing);

      await tester.tap(find.byKey(UiKeys.applicationsIrcInstallButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.installCalls, 1);
      expect(find.byKey(UiKeys.applicationsIrcUninstallButton), findsOneWidget);
      expect(
        find.byKey(UiKeys.applicationsIrcAddChannelButton),
        findsOneWidget,
      );
      expect(find.text('IRC Server Configuration'), findsOneWidget);
      expect(find.text('No IRC channels'), findsOneWidget);
    },
  );

  testWidgets('IRC config save writes through the page controller', (
    tester,
  ) async {
    final controller = _FakeApplicationsIrcController(installed: true);
    await _pumpPage(tester, controller);

    await tester.enterText(
      find.byKey(UiKeys.applicationsIrcServerField),
      'irc.libera.chat',
    );
    await tester.enterText(find.byKey(UiKeys.applicationsIrcPortField), '6697');
    await tester.tap(find.byKey(UiKeys.applicationsIrcSaveConfigButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.savedConfig, (
      server: 'irc.libera.chat',
      port: 6697,
      useSasl: false,
    ));
    expect(find.text('IRC configuration saved'), findsOneWidget);
  });

  testWidgets('IRC add-channel dialog submits through the page controller', (
    tester,
  ) async {
    final controller = _FakeApplicationsIrcController(installed: true);
    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(UiKeys.applicationsIrcAddChannelButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(UiKeys.ircChannelDialogChannelField),
      '#mcp_irc',
    );
    await tester.enterText(
      find.byKey(UiKeys.ircChannelDialogPasswordField),
      'secret',
    );
    await tester.enterText(
      find.byKey(UiKeys.ircChannelDialogNicknameField),
      'mcpnick',
    );
    await tester.tap(find.byKey(UiKeys.ircChannelDialogJoinButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.addedChannels, [
      (channel: '#mcp_irc', password: 'secret', customNickname: 'mcpnick'),
    ]);
    expect(
      find.byKey(UiKeys.applicationsIrcChannelTile('#mcp_irc')),
      findsOneWidget,
    );
    expect(find.text('IRC channel added: #mcp_irc'), findsOneWidget);
  });

  testWidgets(
    'installed IRC page lists channels, reflects status/users, and removes via confirm',
    (tester) async {
      final controller = _FakeApplicationsIrcController(
        installed: true,
        channels: ['#dart', '&local'],
      );
      await _pumpPage(tester, controller);

      expect(
        find.byKey(UiKeys.applicationsIrcChannelTile('#dart')),
        findsOneWidget,
      );
      expect(
        find.byKey(UiKeys.applicationsIrcChannelTile('&local')),
        findsOneWidget,
      );

      controller.emitStatus('#dart', 2, message: 'ready');
      controller.emitUsers('#dart', ['alice', 'bob']);
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('ready'), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.applicationsIrcChannelTile('#dart')));
      await tester.pumpAndSettle();
      expect(find.text('Users (2)'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);

      await tester.tap(
        find.byKey(UiKeys.applicationsIrcRemoveChannelButton('#dart')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove IRC Channel'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.removedChannels, ['#dart']);
      expect(
        find.byKey(UiKeys.applicationsIrcChannelTile('#dart')),
        findsNothing,
      );
      expect(
        find.byKey(UiKeys.applicationsIrcChannelTile('&local')),
        findsOneWidget,
      );
      expect(find.text('IRC channel removed: #dart'), findsOneWidget);
    },
  );

  testWidgets('uninstall clears the installed detail surface', (tester) async {
    final controller = _FakeApplicationsIrcController(
      installed: true,
      channels: ['#dart'],
    );
    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(UiKeys.applicationsIrcUninstallButton));
    await tester.pumpAndSettle();
    expect(find.text('Uninstall IRC Channel App'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Uninstall'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.uninstallCalls, 1);
    expect(find.byKey(UiKeys.applicationsIrcInstallButton), findsOneWidget);
    expect(find.text('IRC Server Configuration'), findsNothing);
  });

  testWidgets(
    'install warns honestly when the native IRC library fails to load',
    (tester) async {
      final controller = _FakeApplicationsIrcController(
        libraryLoadsOnInstall: false,
      );
      await _pumpPage(tester, controller);

      await tester.tap(find.byKey(UiKeys.applicationsIrcInstallButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.installCalls, 1);
      // The install still succeeds (config surface appears) but the message is
      // the honest "live IRC unavailable" warning, not a plain success.
      expect(find.text('IRC Server Configuration'), findsOneWidget);
      expect(
        find.text('IRC app installed, but live IRC is unavailable on this device'),
        findsOneWidget,
      );
      expect(find.text('IRC Channel app installed'), findsNothing);
    },
  );

  testWidgets(
    'add-channel reports the honest not-connected outcome',
    (tester) async {
      final controller = _FakeApplicationsIrcController(
        installed: true,
        addChannelConnects: false,
      );
      await _pumpPage(tester, controller);

      await tester.tap(find.byKey(UiKeys.applicationsIrcAddChannelButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(UiKeys.ircChannelDialogChannelField),
        '#offline',
      );
      await tester.tap(find.byKey(UiKeys.ircChannelDialogJoinButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Channel tile still appears (the group was created), but the message
      // reflects that the IRC connection could not be established.
      expect(
        find.byKey(UiKeys.applicationsIrcChannelTile('#offline')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Channel #offline added, but the IRC connection could not be established',
        ),
        findsOneWidget,
      );
      expect(find.text('IRC channel added: #offline'), findsNothing);
    },
  );

  testWidgets(
    'per-channel status is rehydrated from live connection state on load',
    (tester) async {
      // Simulates a remount (e.g. locale change) where the status map is empty
      // but the underlying connection is live: the tile should show Connected
      // without waiting for a fresh status event.
      final controller = _FakeApplicationsIrcController(
        installed: true,
        channels: ['#persist'],
        connectedChannels: {'#persist'},
      );
      await _pumpPage(tester, controller);

      expect(
        find.byKey(UiKeys.applicationsIrcChannelTile('#persist')),
        findsOneWidget,
      );
      expect(find.text('Connected'), findsOneWidget);
    },
  );
}
