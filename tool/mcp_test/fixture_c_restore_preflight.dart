part of 'fixture_c_unified_runner.dart';

int? _preflightPairedFixtureRestore(String? restore) {
  final error = _pairedFixtureRestorePreflightError(restore);
  if (error == null) return null;
  stderr.writeln(error);
  return 66;
}

String? _pairedFixtureRestorePreflightError(String? restore) {
  if (restore != 'paired_for_e2e' && restore != 'paired') return null;
  final manifestPath = _restorePairManifestPath();
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    return '[unified] paired_for_e2e restore preflight failed: '
        'fixture manifest is missing. ${_restorePairManifestExpectation()}';
  }

  late final Map<String, dynamic> root;
  try {
    root = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    return '[unified] paired_for_e2e restore preflight failed: '
        'fixture manifest is not readable JSON: $e';
  }

  final instances = (root['instances'] as Map?)?.cast<String, dynamic>();
  if (instances == null) {
    return '[unified] paired_for_e2e restore preflight failed: '
        'fixture manifest is missing instances.A/B fixture_dir entries.';
  }

  final malformed = <String>[];
  final missing = <String>[];
  for (final name in const ['A', 'B']) {
    final raw = (instances[name] as Map?)?.cast<String, dynamic>();
    final fixtureDir = raw?['fixture_dir']?.toString().trim();
    if (fixtureDir == null || fixtureDir.isEmpty) {
      malformed.add('instances.$name.fixture_dir');
      continue;
    }
    final fixturePath = 'tool/mcp_test/fixtures/$fixtureDir';
    if (!Directory(fixturePath).existsSync()) missing.add(fixturePath);
  }
  if (malformed.isNotEmpty) {
    return '[unified] paired_for_e2e restore preflight failed: '
        'fixture manifest is missing ${malformed.join(', ')}.';
  }
  if (missing.isEmpty) return null;
  final noun = missing.length == 1 ? 'directory' : 'directories';
  return '[unified] paired_for_e2e restore preflight failed: missing fixture '
      'source $noun: ${missing.join(', ')}. These secret-bearing trees are '
      'gitignored; restore or generate them before running friendship-dependent '
      'Fixture C / real-UI scenarios, or choose a no-friend campaign.';
}

String _restorePairManifestPath() {
  if (_realUiPlatform == 'android') return _pairManifest;
  final override = Platform.environment['TOXEE_FIXTURE_C_MANIFEST']?.trim();
  if (override != null && override.isNotEmpty) return override;
  return _pairManifest;
}

String _restorePairManifestExpectation() {
  if (_realUiPlatform == 'android') return 'Expected $_pairManifest.';
  return 'Expected $_pairManifest or set TOXEE_FIXTURE_C_MANIFEST to a '
      'readable paired fixture manifest.';
}
