import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../tool/mcp_test/qtox_external_peer_harness.dart';

Future<void> main() async {
  final suite = _TestSuite();

  await suite.test(
    'plan JSON is deterministic, isolated, and metadata-only',
    () async {
      await _withFixture((fixture) async {
        final first = fixture.harness.plan.toPrettyJson();
        final second = fixture.harness.plan.toPrettyJson();
        _check(second == first, 'plan changed between identical calls');
        _check(
          !first.contains('A' * 64),
          'plan exposed the bootstrap public key',
        );

        final json = jsonDecode(first) as Map<String, dynamic>;
        _check(json['mode'] == 'plan-only', 'plan mode was not explicit');
        _check(json['liveExecution'] == false, 'plan implied live execution');
        final launch = json['launch'] as Map<String, dynamic>;
        _check(
          launch['inheritParentEnvironment'] == false,
          'plan inherited the parent environment',
        );
        final arguments = (launch['arguments'] as List<dynamic>).cast<String>();
        _check(
          arguments.join(' ') ==
              '-D ${fixture.layout.portableRoot} -I on -U on -L on -P none -l',
          'qTox arguments did not enforce the approved portable network policy',
        );
        final environment = launch['environment'] as Map<String, dynamic>;
        _check(
          environment['HOME'] == fixture.layout.homeRoot,
          'HOME was not isolated',
        );
        _check(
          environment['HOME'] != Platform.environment['HOME'],
          'plan selected the real HOME',
        );
        _check(
          environment['QTOX_SCREENSHOT'] == 'qtox-sigusr1.png',
          'SIGUSR1 screenshot name changed',
        );

        final configuration = json['configuration'] as Map<String, dynamic>;
        final network = configuration['network'] as Map<String, dynamic>;
        _check(network['ipv6'] == true, 'IPv6 was not enabled');
        _check(network['udp'] == true, 'UDP was not enabled');
        _check(
          network['lanDiscovery'] == true,
          'LAN discovery was not enabled',
        );
        _check(network['proxy'] == 'none', 'proxy was not disabled');
        final bootstrap = network['bootstrap'] as Map<String, dynamic>;
        _check(
          bootstrap['publicKey'] == 'configured',
          'public key was not redacted',
        );
      });
    },
  );

  await suite.test('official app selection uses only the staged app', () async {
    await _withFixture((fixture) async {
      final artifact = QtoxArtifactSelection.officialArtifact(
        p.join(fixture.repository.path, 'downloaded', 'qTox.app'),
      );
      final harness = QtoxExternalPeerHarness(
        layout: fixture.layout,
        artifact: artifact,
        bootstrap: QtoxBootstrapConfig(publicKey: 'B' * 64),
      );
      final expected = p.join(
        fixture.layout.stagingRoot,
        'qTox.app',
        'Contents',
        'MacOS',
        'qtox',
      );
      _check(
        harness.plan.executablePath == expected,
        'staged app path was wrong',
      );
      _check(
        p.isWithin(fixture.layout.scratchRoot, harness.plan.executablePath),
        'staged executable escaped scratch',
      );
      _check(
        harness.plan.executablePath != artifact.sourcePath,
        'plan would launch the original artifact',
      );
    });
  });

  await suite.test(
    'prepare writes owned config and resets deterministically',
    () async {
      await _withFixture((fixture) async {
        const sourceContents = '#!/bin/sh\nexit 0\n';
        await fixture.harness.prepare();
        _check(
          File(fixture.layout.markerPath).existsSync(),
          'owner marker missing',
        );
        _check(
          File(fixture.layout.qtoxIniPath).existsSync(),
          'qtox.ini missing',
        );
        _check(
          File(fixture.layout.bootstrapNodesPath).existsSync(),
          'bootstrapNodes.json missing',
        );
        _check(
          File(fixture.harness.plan.executablePath).existsSync(),
          'staged executable missing',
        );
        _check(
          await fixture.fakeExecutable.readAsString() == sourceContents,
          'source executable was modified',
        );

        final ini = await File(fixture.layout.qtoxIniPath).readAsString();
        for (final setting in <String>[
          'makeToxPortable=true',
          'enableIPv6=true',
          'enableLanDiscovery=true',
          'forceTCP=false',
          'checkUpdates=false',
        ]) {
          _check(ini.contains(setting), 'qtox.ini omitted $setting');
        }

        final nodes =
            jsonDecode(
                  await File(fixture.layout.bootstrapNodesPath).readAsString(),
                )
                as Map<String, dynamic>;
        final node =
            (nodes['nodes'] as List<dynamic>).single as Map<String, dynamic>;
        _check(node['ipv4'] == '127.0.0.1', 'bootstrap IPv4 was not loopback');
        _check(node['ipv6'] == '::1', 'bootstrap IPv6 was not loopback');
        _check(node['public_key'] == 'A' * 64, 'bootstrap key was not written');
        _check(node['status_udp'] == true, 'bootstrap UDP status was disabled');
        _check(node['status_tcp'] == true, 'bootstrap TCP status was disabled');

        final stale = File(p.join(fixture.layout.scratchRoot, 'stale'));
        await stale.writeAsString('remove on reset');
        await fixture.harness.prepare();
        _check(!stale.existsSync(), 'owned reset retained stale state');
        _check(
          await fixture.fakeExecutable.readAsString() == sourceContents,
          'owned reset modified the source artifact',
        );
        _check(
          !await fixture.harness.teardown(),
          'teardown found an unlaunched process',
        );
      });
    },
  );

  await suite.test('prepare refuses to reset an unowned directory', () async {
    await _withFixture((fixture) async {
      await Directory(fixture.layout.scratchRoot).create(recursive: true);
      final sentinel = File(p.join(fixture.layout.scratchRoot, 'sentinel'));
      await sentinel.writeAsString('must survive');
      await _expectHarnessFailure(fixture.harness.prepare);
      _check(
        await sentinel.readAsString() == 'must survive',
        'unowned state changed',
      );
    });
  });

  await suite.test('paths outside scratch fail closed', () async {
    await _withFixture((fixture) async {
      await _expectHarnessFailure(() async {
        QtoxScratchLayout.fromRepository(
          repositoryRoot: fixture.repository.path,
          scratchRoot: p.join(
            fixture.repository.path,
            'build',
            'qtox_external_peer',
            '..',
            'escaped',
          ),
        );
      });
      await _expectHarnessFailure(() async {
        fixture.layout.guardPath(
          p.join(fixture.layout.scratchRoot, '..', 'escaped'),
        );
      });
    });
  });

  await suite.test(
    'symbolic links in the scratch boundary fail closed',
    () async {
      await _withFixture((fixture) async {
        final outside = await Directory.systemTemp.createTemp('qtox_outside_');
        try {
          await Link(
            p.join(fixture.repository.path, 'build'),
          ).create(outside.path);
          await _expectHarnessFailure(fixture.harness.prepare);
          await _expectHarnessFailure(fixture.harness.launch);
          await _expectHarnessFailure(fixture.harness.signalScreenshot);
          await _expectHarnessFailure(fixture.harness.teardown);
          _check(
            !Directory(p.join(outside.path, 'qtox_external_peer')).existsSync(),
            'prepare wrote through a scratch boundary symlink',
          );
        } finally {
          if (outside.existsSync()) {
            await outside.delete(recursive: true);
          }
        }
      });
    },
  );

  await suite.test('SIGUSR1 requires an owned scratch marker', () async {
    await _withFixture((fixture) async {
      await Directory(fixture.layout.scratchRoot).create(recursive: true);
      await _expectHarnessFailure(fixture.harness.signalScreenshot);
      _check(
        !File(fixture.layout.screenshotPath).existsSync(),
        'unowned screenshot action wrote an artifact',
      );
    });
  });

  await suite.test('bootstrap input is loopback-only and validated', () async {
    await _withFixture((_) async {
      await _expectHarnessFailure(() async {
        QtoxBootstrapConfig(publicKey: 'not-a-key');
      });
      await _expectHarnessFailure(() async {
        QtoxBootstrapConfig(publicKey: 'C' * 64, ipv4: '192.0.2.1');
      });
    });
  });

  suite.finish();
}

Future<void> _withFixture(Future<void> Function(_Fixture fixture) body) async {
  final fixture = await _Fixture.create();
  try {
    await body(fixture);
  } finally {
    await fixture.dispose();
  }
}

Future<void> _expectHarnessFailure(FutureOr<void> Function() operation) async {
  try {
    await operation();
  } on QtoxHarnessException {
    return;
  }
  throw StateError('expected QtoxHarnessException');
}

void _check(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

class _Fixture {
  const _Fixture({
    required this.repository,
    required this.fakeExecutable,
    required this.layout,
    required this.harness,
  });

  final Directory repository;
  final File fakeExecutable;
  final QtoxScratchLayout layout;
  final QtoxExternalPeerHarness harness;

  static Future<_Fixture> create() async {
    final repository = await Directory.systemTemp.createTemp(
      'qtox_harness_test_',
    );
    final fakeExecutable = File(p.join(repository.path, 'fake_qtox'));
    await fakeExecutable.writeAsString('#!/bin/sh\nexit 0\n');
    final chmod = await Process.run('/bin/chmod', <String>[
      '700',
      fakeExecutable.path,
    ]);
    _check(chmod.exitCode == 0, 'could not prepare fake executable');
    final layout = QtoxScratchLayout.fromRepository(
      repositoryRoot: repository.path,
    );
    return _Fixture(
      repository: repository,
      fakeExecutable: fakeExecutable,
      layout: layout,
      harness: QtoxExternalPeerHarness(
        layout: layout,
        artifact: QtoxArtifactSelection.executable(fakeExecutable.path),
        bootstrap: QtoxBootstrapConfig(publicKey: 'A' * 64),
      ),
    );
  }

  Future<void> dispose() async {
    if (repository.existsSync()) {
      await repository.delete(recursive: true);
    }
  }
}

class _TestSuite {
  var _passed = 0;
  var _failed = 0;

  Future<void> test(String name, Future<void> Function() body) async {
    try {
      await body();
      _passed += 1;
      stdout.writeln('PASS: $name');
    } catch (error, stackTrace) {
      _failed += 1;
      stderr.writeln('FAIL: $name: $error');
      stderr.writeln(stackTrace);
    }
  }

  void finish() {
    stdout.writeln('RESULT: $_passed passed, $_failed failed');
    if (_failed != 0) {
      exitCode = 1;
    }
  }
}
