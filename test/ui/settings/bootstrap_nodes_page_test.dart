import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/bootstrap_nodes_page.dart';
import 'package:toxee/util/bootstrap_nodes.dart';
import 'package:toxee/util/prefs.dart';

typedef _NodeTuple = ({String host, int port, String pubkey});

final _candidate = BootstrapNode(
  ipv4: '192.0.2.20',
  ipv6: '2001:db8::20',
  port: 33445,
  publicKey: 'B' * 64,
  status: 'ONLINE',
);
final _ipv6Candidate = BootstrapNode(
  ipv4: '',
  ipv6: '2001:db8::20',
  port: 33445,
  publicKey: 'D' * 64,
  status: 'ONLINE',
);

const _original = (
  host: 'original.example.com',
  port: 443,
  pubkey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
);

class _RecordingService extends FfiChatService {
  _RecordingService({this.addResult = true}) : super();

  bool addResult;
  Completer<bool>? tryCompleter;
  Completer<bool>? addCompleter;
  final List<_NodeTuple> tried = [];
  final List<_NodeTuple> added = [];

  @override
  Future<bool> tryBootstrapNode(String host, int port, String publicKeyHex) {
    tried.add((host: host, port: port, pubkey: publicKeyHex));
    return tryCompleter?.future ?? Future<bool>.value(true);
  }

  @override
  Future<bool> addBootstrapNode(String host, int port, String publicKeyHex) {
    added.add((host: host, port: port, pubkey: publicKeyHex));
    return addCompleter?.future ?? Future<bool>.value(addResult);
  }
}

Future<void> _initPrefs() async {
  SharedPreferences.setMockInitialValues({});
  await Prefs.initialize(await SharedPreferences.getInstance());
}

Widget _harness({
  required _RecordingService service,
  required Future<List<BootstrapNode>> Function() fetchNodes,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: BootstrapNodesPage(service: service, fetchNodes: fetchNodes),
  );
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _RecordingService service,
  required Future<List<BootstrapNode>> Function() fetchNodes,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness(service: service, fetchNodes: fetchNodes));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void _expectCurrentNode(_NodeTuple expected) {
  expect(Prefs.getCurrentBootstrapNode(), completion(expected));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
  });

  setUp(_initPrefs);

  testWidgets('node test uses non-persisting probe without fake latency', (
    tester,
  ) async {
    await Prefs.setCurrentBootstrapNode(
      _original.host,
      _original.port,
      _original.pubkey,
    );
    final service = _RecordingService();
    await _pumpPage(
      tester,
      service: service,
      fetchNodes: () async => [_candidate],
    );

    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.tried, [
      (
        host: _candidate.ipv4,
        port: _candidate.port,
        pubkey: _candidate.publicKey,
      ),
    ]);
    expect(service.added, isEmpty);
    _expectCurrentNode(_original);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && RegExp(r'^\d+ms$').hasMatch(widget.data ?? ''),
      ),
      findsNothing,
    );
  });

  testWidgets('failed live selection leaves prior preference unchanged', (
    tester,
  ) async {
    await Prefs.setCurrentBootstrapNode(
      _original.host,
      _original.port,
      _original.pubkey,
    );
    final service = _RecordingService(addResult: false);
    await _pumpPage(
      tester,
      service: service,
      fetchNodes: () async => [_candidate],
    );

    await tester.tap(find.text('${_candidate.ipv4}:${_candidate.port}'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.added, hasLength(1));
    _expectCurrentNode(_original);
    expect(find.textContaining('Node switch failed'), findsOneWidget);
  });

  testWidgets('successful live selection persists when service has no prefs', (
    tester,
  ) async {
    await Prefs.setCurrentBootstrapNode(
      _original.host,
      _original.port,
      _original.pubkey,
    );
    final service = _RecordingService();
    await _pumpPage(
      tester,
      service: service,
      fetchNodes: () async => [_candidate],
    );

    await tester.tap(find.text('${_candidate.ipv4}:${_candidate.port}'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    _expectCurrentNode((
      host: _candidate.ipv4,
      port: _candidate.port,
      pubkey: _candidate.publicKey,
    ));
  });

  testWidgets('IPv6-only node displays brackets and probes with raw host', (
    tester,
  ) async {
    final service = _RecordingService();
    await _pumpPage(
      tester,
      service: service,
      fetchNodes: () async => [_ipv6Candidate],
    );

    expect(
      find.text('[${_ipv6Candidate.ipv6}]:${_ipv6Candidate.port}'),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pump();

    expect(service.tried.single.host, _ipv6Candidate.ipv6);
  });

  testWidgets('disposing while node list loads does not setState late', (
    tester,
  ) async {
    final fetch = Completer<List<BootstrapNode>>();
    final service = _RecordingService();
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _harness(service: service, fetchNodes: () => fetch.future),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    fetch.complete([_candidate]);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing while node probe awaits does not setState late', (
    tester,
  ) async {
    final probe = Completer<bool>();
    final service = _RecordingService()
      ..tryCompleter = probe
      ..addCompleter = probe;
    await _pumpPage(
      tester,
      service: service,
      fetchNodes: () async => [_candidate],
    );

    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    probe.complete(true);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
