// Real-UI L1 WidgetTester coverage for [BootstrapSettingsSection] (service: null).
//
// Companion to bootstrap_settings_section_test.dart. The sibling proves the
// mode row + manual-input toggle render; this file drives the REAL controls
// and asserts the REAL observables for the service-less (login-mode) contract:
//   - each mode radio (manual / auto / lan) persists via Prefs.getBootstrapNodeMode
//     and flips the visible affordances;
//   - the manual node form's Test button validates host/port/pubkey and, with
//     no FfiChatService, still runs a REAL reachability probe through
//     BootstrapNodeProbe (which supplies its own ephemeral Tox instance) and
//     reports a genuine verdict — never a "not available before login" excuse;
//   - invalid manual input (empty fields, out-of-range port) raises the
//     invalidNodeInfo error snackbar and never writes Prefs;
//   - the current-node card reflects Prefs.setCurrentBootstrapNode (the same
//     write the "Set as Current Node" button performs once a node tests OK).
//
// service: null is the login-time contract — BootstrapSettingsSection must work
// before FfiChatService exists. That makes it hermetic (no FFI / native calls
// on the paths exercised here). The LAN radio is safe to tap because
// Prefs.getLanBootstrapServiceRunning() defaults false, so _loadLanBootstrapState
// never reaches LanBootstrapServiceManager.
//
// Mobile parity: the mode persistence + manual-form validation + current-node
// Prefs round-trip all live in shared Dart and so apply on iOS/Android too.
// TWO things are desktop-only by design and are *not* drivable here:
//   - the 'lan' mode + the entire LAN service panel: on mobile the section
//     renders _buildModeRowMobile (a 2-segment manual/auto button, no LAN) and
//     Prefs.setBootstrapNodeMode('lan') is coerced back to 'auto'. We assert
//     the desktop classification (the test process is macOS) explicitly.
//   - "Set as Current Node" through the button appears once a node tests
//     successfully. Pre-login that is now reachable (the probe no longer needs
//     a session), but the probe itself talks to the network, so these hermetic
//     tests stub it via BootstrapNodeProbe.debugProbeOverride and additionally
//     validate its persistence target (setCurrentBootstrapNode) directly.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/bootstrap_settings_section.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/bootstrap_node_probe.dart';
import 'package:toxee/util/platform_utils.dart';
import 'package:toxee/util/prefs.dart';

const String _validPubkey =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789';

Future<void> _initPrefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

Widget _harness() {
  return const MaterialApp(
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: [Locale('en')],
    home: Scaffold(
      body: SingleChildScrollView(
        child: BootstrapSettingsSection(service: null),
      ),
    ),
  );
}

Future<void> _pumpSettled(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Expands the manual-input row from a manual-mode section. Assumes mode is
/// already 'manual' (so the expand button is present).
Future<void> _expandManualInput(WidgetTester tester) async {
  await tester.tap(find.byKey(UiKeys.manualNodeInputButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // url_launcher (auto-mode link tap) + any HapticFeedback go through
  // SystemChannels.platform; swallow it so nothing throws under the binding.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });
  tearDownAll(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('environment guard', () {
    test('test host classifies as desktop (so the 3-radio row renders)', () {
      // Several assertions below depend on the desktop layout. macOS test
      // processes are desktop; if this ever flips, the LAN-radio cases would
      // be testing the wrong widget tree.
      expect(
        PlatformUtils.isDesktop,
        isTrue,
        reason: 'flutter test on macOS/Linux must be desktop',
      );
    });
  });

  // ----------------------------------------------------------------------
  // 5. Bootstrap mode radios: persist to Prefs + flip the affordances.
  // ----------------------------------------------------------------------
  group('bootstrap mode radios', () {
    testWidgets('tapping manual persists "manual" + reveals manual-input '
        'expand button', (tester) async {
      await _initPrefs(); // default mode 'auto'
      await _pumpSettled(tester);

      expect(
        await Prefs.getBootstrapNodeMode(),
        'auto',
        reason: 'Sanity: default before interaction',
      );
      expect(
        find.byKey(UiKeys.manualNodeInputButton),
        findsNothing,
        reason: 'Manual-input affordance is hidden in auto mode',
      );

      await tester.tap(find.byKey(UiKeys.settingsBootstrapModeManual));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        await Prefs.getBootstrapNodeMode(),
        'manual',
        reason: 'Tapping the manual radio persists the mode',
      );
      expect(
        find.byKey(UiKeys.manualNodeInputButton),
        findsOneWidget,
        reason: 'Manual mode reveals the manual-input expand button',
      );
    });

    testWidgets('tapping auto (from manual) persists "auto"', (tester) async {
      await _initPrefs({'bootstrap_node_mode': 'manual'});
      await _pumpSettled(tester);

      expect(await Prefs.getBootstrapNodeMode(), 'manual');

      // The auto tile's *subtitle* is a GestureDetector (the nodes.tox.chat
      // link), so a center tap on the tile lands on the link's gesture arena
      // rather than the radio's onChanged. Tap the title text instead — it sits
      // in the RadioListTile's own tap region, above the link.
      await tester.tap(find.text('Auto (Fetch from Web)'));
      await tester.pump();
      // auto mode kicks off _loadAndUseAutoNode (network fetch). With no
      // service it only writes Prefs on success; the fetch fails offline and is
      // caught + surfaced as a snackbar. Either way the *mode* write already
      // happened synchronously before the fetch, which is what we assert.
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        await Prefs.getBootstrapNodeMode(),
        'auto',
        reason: 'Tapping the auto radio persists the mode regardless of fetch',
      );
      expect(
        find.byKey(UiKeys.manualNodeInputButton),
        findsNothing,
        reason: 'Leaving manual mode hides the manual-input button',
      );
    });

    testWidgets('tapping LAN (desktop only) persists "lan" + shows LAN panel', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester);

      await tester.tap(find.byKey(UiKeys.settingsBootstrapModeLan));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        await Prefs.getBootstrapNodeMode(),
        'lan',
        reason: 'On desktop the LAN radio persists "lan"',
      );
      // The "Start Local Bootstrap Service" title is exclusive to LAN mode.
      expect(
        find.text('Start Local Bootstrap Service'),
        findsWidgets,
        reason: 'LAN panel renders its start-service section',
      );
      // ...and the service status reads "Stopped" by default (running pref
      // defaults false, so no LanBootstrapServiceManager call happens).
      expect(
        find.text('Stopped'),
        findsOneWidget,
        reason: 'LAN panel renders the default stopped status',
      );
    });
  });

  // ----------------------------------------------------------------------
  // 6. Manual node form (service: null): validation + test-unavailable path.
  // ----------------------------------------------------------------------
  group('manual node form (service: null)', () {
    Future<void> enterManualMode(WidgetTester tester) async {
      await _initPrefs({'bootstrap_node_mode': 'manual'});
      await _pumpSettled(tester);
      await _expandManualInput(tester);
    }

    testWidgets('expand reveals host/port/pubkey fields + test button', (
      tester,
    ) async {
      await enterManualMode(tester);

      expect(find.byKey(UiKeys.manualNodeHostField), findsOneWidget);
      expect(find.byKey(UiKeys.manualNodePortField), findsOneWidget);
      expect(find.byKey(UiKeys.manualNodePubkeyField), findsOneWidget);
      expect(find.byKey(UiKeys.manualNodeTestButton), findsOneWidget);
    });

    testWidgets('Test with empty fields shows invalidNodeInfo error snackbar', (
      tester,
    ) async {
      await enterManualMode(tester);

      // The current-node load seeds the port field to 33445, so clear all
      // three fields to force the empty-validation branch.
      await tester.enterText(find.byKey(UiKeys.manualNodeHostField), '');
      await tester.enterText(find.byKey(UiKeys.manualNodePortField), '');
      await tester.enterText(find.byKey(UiKeys.manualNodePubkeyField), '');
      await tester.pump();

      await tester.tap(find.byKey(UiKeys.manualNodeTestButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text(
          'Please enter valid node information (host, port, and public key)',
        ),
        findsOneWidget,
        reason: 'Empty host/port/pubkey trips the invalidNodeInfo guard',
      );
    });

    testWidgets('Test with out-of-range port shows invalidNodeInfo snackbar', (
      tester,
    ) async {
      await enterManualMode(tester);

      await tester.enterText(
        find.byKey(UiKeys.manualNodeHostField),
        'node.example.com',
      );
      await tester.enterText(find.byKey(UiKeys.manualNodePortField), '70000');
      await tester.enterText(
        find.byKey(UiKeys.manualNodePubkeyField),
        _validPubkey,
      );
      await tester.pump();

      await tester.tap(find.byKey(UiKeys.manualNodeTestButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text(
          'Please enter valid node information (host, port, and public key)',
        ),
        findsOneWidget,
        reason: 'port=70000 > 65535 fails the range guard',
      );
    });

    // REGRESSION GATE. This case used to assert the OPPOSITE — that pre-login
    // the Test button surfaced "Cannot send a bootstrap request before login".
    // That string was the bug: the one surface a disconnected user can reach
    // refused to do the one thing they needed. The button must now run the real
    // probe (stubbed here) and render its verdict.
    testWidgets('Test with valid fields and no service still probes for real', (
      tester,
    ) async {
      final probed = <({String host, int port, String pubkey, bool hadService})>[];
      var verdict = BootstrapProbeVerdict.reachable;
      BootstrapNodeProbe.debugProbeOverride =
          ({
            required String host,
            required int port,
            required String publicKey,
            service,
          }) async {
            probed.add((
              host: host,
              port: port,
              pubkey: publicKey,
              hadService: service != null,
            ));
            return verdict;
          };
      addTearDown(() => BootstrapNodeProbe.debugProbeOverride = null);

      await enterManualMode(tester);

      await tester.enterText(
        find.byKey(UiKeys.manualNodeHostField),
        'node.example.com',
      );
      await tester.enterText(find.byKey(UiKeys.manualNodePortField), '33445');
      await tester.enterText(
        find.byKey(UiKeys.manualNodePubkeyField),
        _validPubkey,
      );
      await tester.pump();

      await tester.tap(find.byKey(UiKeys.manualNodeTestButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        probed,
        [
          (
            host: 'node.example.com',
            port: 33445,
            pubkey: _validPubkey,
            hadService: false,
          ),
        ],
        reason:
            'Pre-login the Test button must drive BootstrapNodeProbe with the '
            'typed tuple and no session, not bail out early',
      );
      expect(
        find.text('Cannot send a bootstrap request before login'),
        findsNothing,
        reason: 'That verdict no longer exists in the product',
      );
      expect(find.text('Node reachable'), findsWidgets);
      // A reachable node pre-login now unlocks promotion, which is the whole
      // point: a user who cannot connect can configure a working node.
      expect(find.text('Set as Current Node'), findsOneWidget);

      // And a negative probe reads as a real failure verdict.
      verdict = BootstrapProbeVerdict.unreachable;
      await tester.enterText(
        find.byKey(UiKeys.manualNodeHostField),
        'dead.example.com',
      );
      await tester.pump();
      await tester.tap(find.byKey(UiKeys.manualNodeTestButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(probed, hasLength(2));
      expect(find.text('Node unreachable'), findsWidgets);
      expect(find.text('Set as Current Node'), findsNothing);
    });
  });

  group('current-node card (Prefs.setCurrentBootstrapNode)', () {
    testWidgets('seeded current node renders host:port + truncated pubkey', (
      tester,
    ) async {
      // This is exactly the write _setManualNodeAsCurrent performs once a node
      // tests OK; we assert the card reflects it. With service: null the button
      // path is unreachable (needs a live test success), so this validates the
      // observable side of that handler directly.
      await _initPrefs({'bootstrap_node_mode': 'manual'});
      await Prefs.setCurrentBootstrapNode(
        'seed.tox.example',
        33445,
        _validPubkey,
      );
      await _pumpSettled(tester);

      expect(
        find.textContaining('seed.tox.example:33445'),
        findsOneWidget,
        reason: 'Current-node card surfaces the persisted host:port',
      );
      expect(
        find.textContaining(_validPubkey.substring(0, 20)),
        findsOneWidget,
        reason: 'Card shows the first 20 hex chars of the persisted pubkey',
      );
    });

    testWidgets('updating the current node via Prefs is reflected after reload', (
      tester,
    ) async {
      await _initPrefs({'bootstrap_node_mode': 'manual'});
      await Prefs.setCurrentBootstrapNode('first.example', 33445, _validPubkey);
      await _pumpSettled(tester);

      expect(find.textContaining('first.example:33445'), findsOneWidget);

      // Persist a different node and rebuild the section from scratch (mirrors
      // what _loadCurrentBootstrapNode does after a successful set-as-current).
      // Unmount first so the second pump constructs a fresh State whose
      // initState re-reads the now-updated Prefs (an identical-tree re-pump
      // would reuse the same Element/State and skip initState).
      await Prefs.setCurrentBootstrapNode(
        'second.example',
        44455,
        _validPubkey,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pumpSettled(tester);

      expect(
        find.textContaining('second.example:44455'),
        findsOneWidget,
        reason: 'The card reads the latest persisted current node on load',
      );
      expect(find.textContaining('first.example'), findsNothing);
    });
  });
}
