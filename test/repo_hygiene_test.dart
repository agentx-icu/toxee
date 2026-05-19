// Regression guard for hardcoded developer-machine paths.
//
// Why: `/Users/<someone>/...` paths in vendored / committed source are a
// portability landmine — they compile fine on the original author's box,
// silently break on every other developer and on CI. Once they slip into
// `third_party/tim2tox`, they're easy to miss in review because that subtree
// is largely vendored.
//
// We only scan a curated list of files known to have previously leaked
// such paths or to be high-risk (FFI bootstrap, library resolution). A
// repo-wide grep would be more thorough but slow and would need its own
// ignore-list for `auto_tests/` fixtures, documentation examples, etc.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = Directory.current.path;

  // Files at elevated risk of accumulating dev-only paths. Add to this list
  // as new high-risk surfaces appear (e.g. FFI loaders, build glue, asset
  // resolvers). Each path is asserted to exist so the test reports clearly
  // if the file is moved or removed instead of silently passing on nothing.
  final watchedFiles = <String>[
    '$repoRoot/third_party/tim2tox/dart/lib/ffi/tim2tox_ffi.dart',
  ];

  // Substrings that should never appear in committed source. `/Users/bin.gao/`
  // is the specific maintainer path that has leaked in the past. The check
  // is intentionally case-sensitive: false positives from generic words like
  // "users" would be impractical to suppress.
  const forbiddenSubstrings = <String>[
    '/Users/bin.gao/',
  ];

  group('repo hygiene — no hardcoded developer paths in source', () {
    for (final path in watchedFiles) {
      test('${path.split('/').last} contains no forbidden absolute paths',
          () async {
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Watched file missing — update test/repo_hygiene_test.dart to '
              'reflect the new layout: $path',
        );

        final src = await file.readAsString();
        for (final needle in forbiddenSubstrings) {
          expect(
            src,
            isNot(contains(needle)),
            reason:
                'Hardcoded developer path leaked into $path: '
                'found "$needle". Use a relative path, an env var, or a '
                'runtime-resolved location instead.',
          );
        }
      });
    }
  });
}
