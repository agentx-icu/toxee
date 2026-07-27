// Widget tests for [BootstrapSettingsSection].
//
// This section is shared between the login-time settings page and the
// post-login settings page; the `service` parameter is null in the login-mode
// flow. We exercise the **service: null** case because it doesn't touch
// FFI / `FfiChatService`, which keeps the test hermetic.
//
// Covered behaviors:
//   1. Initial render at mode='auto' shows the three RadioListTile options on
//      desktop (the test process inherits a desktop classification on macOS),
//      with 'auto' selected.
//   2. Switching to manual via RadioListTile persists the mode in Prefs and
//      reveals the "Manual node input" affordance.
//   3. Tapping the "Manual node input" expand button toggles the manual host
//      / port / pubkey input row.
//   4. With pre-seeded bootstrap_node_* prefs, the "current node" tile shows
//      the seeded host:port string.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/bootstrap_settings_section.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/lan_bootstrap_service.dart';
import 'package:toxee/util/prefs.dart';

typedef _BootstrapNode = ({String host, int port, String pubkey});

const _originalNode = (
  host: 'original.example.com',
  port: 33445,
  pubkey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
);
const _candidateNode = (
  host: 'candidate.example.com',
  port: 443,
  pubkey: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
);

class _RecordingFfiChatService extends FfiChatService {
  _RecordingFfiChatService({this.addResult = true, this.events}) : super();

  bool addResult;
  final List<String>? events;
  final List<_BootstrapNode> triedNodes = [];
  final List<_BootstrapNode> addedNodes = [];

  @override
  Future<bool> tryBootstrapNode(
    String host,
    int port,
    String publicKeyHex,
  ) async {
    triedNodes.add((host: host, port: port, pubkey: publicKeyHex));
    return true;
  }

  @override
  Future<bool> addBootstrapNode(
    String host,
    int port,
    String publicKeyHex,
  ) async {
    addedNodes.add((host: host, port: port, pubkey: publicKeyHex));
    events?.add('add:$host');
    return addResult;
  }
}

class _RecordingLanManager extends LanBootstrapServiceManager {
  _RecordingLanManager({this.events, this.stopResult = true})
    : super.forTesting(localAddressProvider: () async => '192.168.56.10');

  final List<String>? events;
  final bool stopResult;
  final ({String ip, int port, String pubkey})? info = const (
    ip: '192.168.56.10',
    port: 33445,
    pubkey: 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
  );
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> startLocalBootstrapService(int port) async {
    startCalls += 1;
    await Prefs.setLanBootstrapServiceRunning(true);
    return true;
  }

  @override
  Future<bool> stopLocalBootstrapService() async {
    stopCalls += 1;
    events?.add('stop');
    if (!stopResult) return false;
    await Prefs.setLanBootstrapServiceRunning(false);
    return true;
  }

  @override
  Future<({String ip, int port, String pubkey})?>
  getBootstrapServiceInfo() async => info;
}

Future<void> _initPrefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

Widget _harness({Widget? child}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: SingleChildScrollView(
        // service: null is the login-mode contract; the page must support it
        // because the FfiChatService is not constructed before login.
        child: child ?? const BootstrapSettingsSection(service: null),
      ),
    ),
  );
}

Future<void> _pumpSettled(WidgetTester tester, [Widget? root]) async {
  // Use a wide surface so all RadioListTiles fit on one row.
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(root ?? _harness());
  // Drain initState's async Prefs reads.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _showManualForm(
  WidgetTester tester,
  _RecordingFfiChatService service,
) async {
  await Prefs.setBootstrapNodeMode('manual');
  await _pumpSettled(
    tester,
    _harness(child: BootstrapSettingsSection(service: service)),
  );
  await tester.tap(find.byKey(UiKeys.manualNodeInputButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _enterManualNode(WidgetTester tester, _BootstrapNode node) async {
  await tester.enterText(find.byKey(UiKeys.manualNodeHostField), node.host);
  await tester.enterText(
    find.byKey(UiKeys.manualNodePortField),
    node.port.toString(),
  );
  await tester.enterText(find.byKey(UiKeys.manualNodePubkeyField), node.pubkey);
  await tester.pump();
}

Future<void> _testManualNode(WidgetTester tester) async {
  await tester.tap(find.byKey(UiKeys.manualNodeTestButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _expectNode(_BootstrapNode? actual, _BootstrapNode expected) {
  expect(actual, isNotNull);
  expect(actual!.host, expected.host);
  expect(actual.port, expected.port);
  expect(actual.pubkey, expected.pubkey);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
  });

  group('BootstrapSettingsSection - desktop mode row', () {
    testWidgets('default mode is auto and all three radios are present', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester);

      // Three RadioListTiles: manual / auto / lan.
      expect(find.byType(RadioListTile<String>), findsNWidgets(3));
      expect(find.byKey(UiKeys.settingsBootstrapModeManual), findsOneWidget);
      expect(find.byKey(UiKeys.settingsBootstrapModeAuto), findsOneWidget);
      expect(find.byKey(UiKeys.settingsBootstrapModeLan), findsOneWidget);

      // Auto is the default per Prefs.getBootstrapNodeMode().
      final modeGroup = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      expect(
        modeGroup.groupValue,
        'auto',
        reason: 'Auto is the documented default mode',
      );
    });

    testWidgets(
      'tapping manual radio persists mode to Prefs and shows manual input '
      'expand button',
      (tester) async {
        await _initPrefs();
        await _pumpSettled(tester);

        // Tap the "manual" radio.
        final manualRadio = find.byKey(UiKeys.settingsBootstrapModeManual);
        await tester.tap(manualRadio);
        // The on-change handler is async (writes to Prefs then reloads state).
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Mode was persisted.
        final mode = await Prefs.getBootstrapNodeMode();
        expect(
          mode,
          'manual',
          reason: 'Tapping a mode radio must persist via Prefs',
        );

        // The "Manual node input" expand button appears in manual mode (only).
        expect(
          find.textContaining(RegExp('[Mm]anual')),
          findsWidgets,
          reason: 'Manual mode reveals the manual-input affordance',
        );
      },
    );

    testWidgets('seeded current node prefs surface as a current-node tile', (
      tester,
    ) async {
      // Pre-seed via the documented Prefs keys (set via the public setter so
      // the implementation is the contract, not the underlying key names).
      await _initPrefs();
      await Prefs.setCurrentBootstrapNode(
        'bootstrap.example.com',
        33445,
        'A' * 64,
      );
      await _pumpSettled(tester);

      expect(
        find.textContaining('bootstrap.example.com:33445'),
        findsOneWidget,
        reason: 'Current node card surfaces the host:port pair',
      );
    });

    testWidgets('IPv6 current node uses an unambiguous bracketed endpoint', (
      tester,
    ) async {
      await _initPrefs();
      await Prefs.setCurrentBootstrapNode('2001:db8::20', 33445, 'A' * 64);
      await _pumpSettled(tester);

      expect(find.text('[2001:db8::20]:33445'), findsOneWidget);
      expect(find.text('2001:db8::20:33445'), findsNothing);
    });

    testWidgets('manual-mode expand toggle flips the manual input row', (
      tester,
    ) async {
      await _initPrefs();
      // Start directly in manual mode so the "Manual node input" button is
      // visible immediately. Bypassing the radio tap removes one source of
      // flake in this assertion.
      await Prefs.setBootstrapNodeMode('manual');
      await _pumpSettled(tester);

      // The expand button is an OutlinedButton.icon with an expand_more icon.
      expect(
        find.byIcon(Icons.expand_more),
        findsOneWidget,
        reason: 'Manual mode shows a closed expand-more chevron initially',
      );
      expect(
        find.byKey(UiKeys.manualNodeInputButton),
        findsOneWidget,
        reason: 'Manual mode ships a stable anchor for the expand affordance',
      );
      expect(find.byKey(UiKeys.manualNodeHostField), findsNothing);
      expect(find.byKey(UiKeys.manualNodePortField), findsNothing);
      expect(find.byKey(UiKeys.manualNodePubkeyField), findsNothing);
      expect(find.byKey(UiKeys.manualNodeTestButton), findsNothing);

      // Tap to expand.
      await tester.tap(find.byKey(UiKeys.manualNodeInputButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byIcon(Icons.expand_less),
        findsOneWidget,
        reason: 'After expand, the chevron flips to expand_less',
      );
      expect(
        find.byKey(UiKeys.manualNodeHostField),
        findsOneWidget,
        reason: 'Expanded manual mode exposes a stable host-field anchor',
      );
      expect(find.byKey(UiKeys.manualNodePortField), findsOneWidget);
      expect(find.byKey(UiKeys.manualNodePubkeyField), findsOneWidget);
      expect(find.byKey(UiKeys.manualNodeTestButton), findsOneWidget);
    });
  });

  group('BootstrapSettingsSection - manual transaction', () {
    testWidgets(
      'manual probe uses tryBootstrapNode without applying or persisting',
      (tester) async {
        await _initPrefs();
        await Prefs.setCurrentBootstrapNode(
          _originalNode.host,
          _originalNode.port,
          _originalNode.pubkey,
        );
        final service = _RecordingFfiChatService();
        await _showManualForm(tester, service);
        await _enterManualNode(tester, _candidateNode);

        await _testManualNode(tester);

        expect(service.triedNodes, [_candidateNode]);
        expect(
          service.addedNodes,
          isEmpty,
          reason: 'A probe must not apply or persist the candidate node',
        );
        _expectNode(await Prefs.getCurrentBootstrapNode(), _originalNode);
      },
    );

    testWidgets('successful manual probe is invalidated by any tuple edit', (
      tester,
    ) async {
      await _initPrefs();
      final service = _RecordingFfiChatService();
      await _showManualForm(tester, service);
      await _enterManualNode(tester, _candidateNode);

      Future<void> expectInvalidatedAfterEdit(
        Finder field,
        String editedValue,
      ) async {
        await _testManualNode(tester);
        expect(find.text('Set as Current Node'), findsOneWidget);

        await tester.enterText(field, editedValue);
        await tester.pump();

        expect(
          find.text('Set as Current Node'),
          findsNothing,
          reason: 'Changing any part of the tested tuple invalidates approval',
        );
      }

      await expectInvalidatedAfterEdit(
        find.byKey(UiKeys.manualNodeHostField),
        'edited.example.com',
      );
      await _enterManualNode(tester, _candidateNode);
      await expectInvalidatedAfterEdit(
        find.byKey(UiKeys.manualNodePortField),
        '33446',
      );
      await _enterManualNode(tester, _candidateNode);
      await expectInvalidatedAfterEdit(
        find.byKey(UiKeys.manualNodePubkeyField),
        'C' * 64,
      );
    });

    testWidgets(
      'false manual apply preserves prior prefs and shows switch failure',
      (tester) async {
        await _initPrefs();
        await Prefs.setCurrentBootstrapNode(
          _originalNode.host,
          _originalNode.port,
          _originalNode.pubkey,
        );
        final service = _RecordingFfiChatService();
        await _showManualForm(tester, service);
        await _enterManualNode(tester, _candidateNode);
        await _testManualNode(tester);
        expect(find.text('Set as Current Node'), findsOneWidget);
        ScaffoldMessenger.of(
          tester.element(find.byType(BootstrapSettingsSection)),
        ).clearSnackBars();
        await tester.pumpAndSettle();

        service.addResult = false;
        await tester.tap(find.text('Set as Current Node'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump();

        expect(service.addedNodes, [_candidateNode]);
        _expectNode(await Prefs.getCurrentBootstrapNode(), _originalNode);
        final messages = tester
            .widgetList<SnackBar>(find.byType(SnackBar))
            .map((snackBar) => (snackBar.content as Text).data)
            .whereType<String>();
        expect(
          messages.any((text) => text.contains('Node switch failed')),
          isTrue,
        );
        expect(find.text('Node set as current successfully'), findsNothing);
      },
    );

    testWidgets(
      'successful live apply persists even when service has no prefs',
      (tester) async {
        await _initPrefs();
        await Prefs.setCurrentBootstrapNode(
          _originalNode.host,
          _originalNode.port,
          _originalNode.pubkey,
        );
        final service = _RecordingFfiChatService();
        await _showManualForm(tester, service);
        await _enterManualNode(tester, _candidateNode);
        await _testManualNode(tester);
        ScaffoldMessenger.of(
          tester.element(find.byType(BootstrapSettingsSection)),
        ).clearSnackBars();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Set as Current Node'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        _expectNode(await Prefs.getCurrentBootstrapNode(), _candidateNode);
      },
    );
  });

  group('BootstrapSettingsSection - LAN transaction', () {
    testWidgets('pre-login start does not launch a native LAN manager', (
      tester,
    ) async {
      await _initPrefs();
      await Prefs.setBootstrapNodeMode('lan');
      final manager = _RecordingLanManager();
      await _pumpSettled(
        tester,
        _harness(
          child: BootstrapSettingsSection(
            service: null,
            lanBootstrapServiceManager: manager,
          ),
        ),
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Start Local Bootstrap Service'),
      );
      await tester.pump();

      expect(manager.startCalls, 0);
      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
      expect(find.text('Test unavailable before login'), findsOneWidget);
    });

    testWidgets('false live LAN apply rolls back manager and staged snapshot', (
      tester,
    ) async {
      await _initPrefs();
      await Prefs.setBootstrapNodeMode('lan');
      await Prefs.setCurrentBootstrapNode(
        _originalNode.host,
        _originalNode.port,
        _originalNode.pubkey,
      );
      final manager = _RecordingLanManager();
      final service = _RecordingFfiChatService(addResult: false);
      await _pumpSettled(
        tester,
        _harness(
          child: BootstrapSettingsSection(
            service: service,
            lanBootstrapServiceManager: manager,
          ),
        ),
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Start Local Bootstrap Service'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(manager.startCalls, 1);
      expect(manager.stopCalls, 1);
      expect(service.addedNodes, [
        (
          host: manager.info!.ip,
          port: manager.info!.port,
          pubkey: manager.info!.pubkey,
        ),
      ]);
      _expectNode(await Prefs.getCurrentBootstrapNode(), _originalNode);
      expect(await Prefs.getPreLanBootstrapNode(), isNull);
      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
    });

    testWidgets(
      'LAN stop restores prior node before stopping and clears snapshot',
      (tester) async {
        await _initPrefs();
        await Prefs.setBootstrapNodeMode('lan');
        await Prefs.setCurrentBootstrapNode('192.168.56.10', 33445, 'C' * 64);
        await Prefs.setPreLanBootstrapNode(
          _originalNode.host,
          _originalNode.port,
          _originalNode.pubkey,
        );
        await Prefs.setLanBootstrapServiceRunning(true);
        final events = <String>[];
        final manager = _RecordingLanManager(events: events);
        final service = _RecordingFfiChatService(events: events);
        await _pumpSettled(
          tester,
          _harness(
            child: BootstrapSettingsSection(
              service: service,
              lanBootstrapServiceManager: manager,
            ),
          ),
        );

        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Stop Local Bootstrap Service'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(events, ['add:${_originalNode.host}', 'stop']);
        _expectNode(await Prefs.getCurrentBootstrapNode(), _originalNode);
        expect(await Prefs.getPreLanBootstrapNode(), isNull);
        expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
      },
    );

    testWidgets(
      'failed prior-node restore keeps LAN running and snapshot intact',
      (tester) async {
        await _initPrefs();
        await Prefs.setBootstrapNodeMode('lan');
        const lanNode = (
          host: '192.168.56.10',
          port: 33445,
          pubkey:
              'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
        );
        await Prefs.setCurrentBootstrapNode(
          lanNode.host,
          lanNode.port,
          lanNode.pubkey,
        );
        await Prefs.setPreLanBootstrapNode(
          _originalNode.host,
          _originalNode.port,
          _originalNode.pubkey,
        );
        await Prefs.setLanBootstrapServiceRunning(true);
        final events = <String>[];
        final manager = _RecordingLanManager(events: events);
        final service = _RecordingFfiChatService(
          addResult: false,
          events: events,
        );
        await _pumpSettled(
          tester,
          _harness(
            child: BootstrapSettingsSection(
              service: service,
              lanBootstrapServiceManager: manager,
            ),
          ),
        );

        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Stop Local Bootstrap Service'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(events, ['add:${_originalNode.host}']);
        expect(manager.stopCalls, 0);
        _expectNode(await Prefs.getCurrentBootstrapNode(), lanNode);
        _expectNode(await Prefs.getPreLanBootstrapNode(), _originalNode);
        expect(await Prefs.getLanBootstrapServiceRunning(), isTrue);
      },
    );

    testWidgets(
      'switching from running LAN to manual restores and stops before persisting mode',
      (tester) async {
        await _initPrefs();
        await Prefs.setBootstrapNodeMode('lan');
        const lanNode = (
          host: '192.168.56.10',
          port: 33445,
          pubkey:
              'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
        );
        await Prefs.setCurrentBootstrapNode(
          lanNode.host,
          lanNode.port,
          lanNode.pubkey,
        );
        await Prefs.setPreLanBootstrapNode(
          _originalNode.host,
          _originalNode.port,
          _originalNode.pubkey,
        );
        await Prefs.setLanBootstrapServiceRunning(true);
        final events = <String>[];
        final manager = _RecordingLanManager(events: events);
        final service = _RecordingFfiChatService(events: events);
        await _pumpSettled(
          tester,
          _harness(
            child: BootstrapSettingsSection(
              service: service,
              lanBootstrapServiceManager: manager,
            ),
          ),
        );

        await tester.tap(find.byKey(UiKeys.settingsBootstrapModeManual));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(events, ['add:${_originalNode.host}', 'stop']);
        expect(await Prefs.getBootstrapNodeMode(), 'manual');
        expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
        expect(await Prefs.getPreLanBootstrapNode(), isNull);
        _expectNode(await Prefs.getCurrentBootstrapNode(), _originalNode);
      },
    );

    testWidgets(
      'failed restore blocks leaving LAN mode and keeps recovery state',
      (tester) async {
        await _initPrefs();
        await Prefs.setBootstrapNodeMode('lan');
        const lanNode = (
          host: '192.168.56.10',
          port: 33445,
          pubkey:
              'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
        );
        await Prefs.setCurrentBootstrapNode(
          lanNode.host,
          lanNode.port,
          lanNode.pubkey,
        );
        await Prefs.setPreLanBootstrapNode(
          _originalNode.host,
          _originalNode.port,
          _originalNode.pubkey,
        );
        await Prefs.setLanBootstrapServiceRunning(true);
        final events = <String>[];
        final manager = _RecordingLanManager(events: events);
        final service = _RecordingFfiChatService(
          addResult: false,
          events: events,
        );
        await _pumpSettled(
          tester,
          _harness(
            child: BootstrapSettingsSection(
              service: service,
              lanBootstrapServiceManager: manager,
            ),
          ),
        );

        await tester.tap(find.byKey(UiKeys.settingsBootstrapModeManual));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(events, ['add:${_originalNode.host}']);
        expect(manager.stopCalls, 0);
        expect(await Prefs.getBootstrapNodeMode(), 'lan');
        expect(await Prefs.getLanBootstrapServiceRunning(), isTrue);
        _expectNode(await Prefs.getPreLanBootstrapNode(), _originalNode);
        _expectNode(await Prefs.getCurrentBootstrapNode(), lanNode);
      },
    );

    testWidgets(
      'silent manager stop failure blocks mode change and keeps recovery state',
      (tester) async {
        await _initPrefs();
        await Prefs.setBootstrapNodeMode('lan');
        const lanNode = (
          host: '192.168.56.10',
          port: 33445,
          pubkey:
              'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
        );
        await Prefs.setCurrentBootstrapNode(
          lanNode.host,
          lanNode.port,
          lanNode.pubkey,
        );
        await Prefs.setPreLanBootstrapNode(
          _originalNode.host,
          _originalNode.port,
          _originalNode.pubkey,
        );
        await Prefs.setLanBootstrapServiceRunning(true);
        final events = <String>[];
        final manager = _RecordingLanManager(
          events: events,
          stopResult: false,
        );
        final service = _RecordingFfiChatService(events: events);
        await _pumpSettled(
          tester,
          _harness(
            child: BootstrapSettingsSection(
              service: service,
              lanBootstrapServiceManager: manager,
            ),
          ),
        );

        await tester.tap(find.byKey(UiKeys.settingsBootstrapModeManual));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(events, ['add:${_originalNode.host}', 'stop']);
        expect(await Prefs.getBootstrapNodeMode(), 'lan');
        expect(await Prefs.getLanBootstrapServiceRunning(), isTrue);
        _expectNode(await Prefs.getPreLanBootstrapNode(), _originalNode);
      },
    );
  });

  testWidgets(
    'disposing during initial prefs load does not touch controllers',
    (tester) async {
      await _initPrefs();
      await tester.pumpWidget(_harness());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}
