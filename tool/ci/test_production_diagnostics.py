#!/usr/bin/env python3
"""Inspect actual terminal output and symbolize a real stripped Dart AOT stack."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MARKER = 'PRIVATE_DIAGNOSTIC_MARKER_a549a2'


class ProductionDiagnostics(unittest.TestCase):
    def run_checked(self, args):
        result = subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=180)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_actual_console_and_file_sinks(self):
        result = self.run_checked(['flutter', 'test', '--no-pub',
                                  'test/support/production_diagnostics_probe.dart'])
        self.assertNotIn(MARKER, result.stdout + result.stderr)
        self.assertIn('origin=logger error_type=FileSystemException', result.stdout + result.stderr)

    def test_actual_stripped_aot_stack_remains_symbolizable(self):
        with tempfile.TemporaryDirectory(prefix='toxee-diagnostic-aot-') as tmp:
            symbols = Path(tmp) / 'probe.symbols'
            binary = Path(tmp) / 'probe'
            trace = Path(tmp) / 'trace.txt'
            self.run_checked(['dart', 'compile', 'exe',
                              f'--save-debugging-info={symbols}',
                              'tool/ci/production_diagnostics_aot_probe.dart', '-o', str(binary)])
            result = self.run_checked([str(binary)])
            self.assertNotIn(MARKER, result.stdout + result.stderr)
            self.assertIn('_kDartIsolateSnapshotInstructions+0x', result.stdout)
            self.assertIn('build_id:', result.stdout)
            trace.write_text(result.stdout)
            decoded = self.run_checked(['flutter', 'symbolize',
                                        f'--debug-info={symbols}', f'--input={trace}'])
            self.assertIn('_throwDiagnosticProbe', decoded.stdout)
            self.assertIn('production_diagnostics_aot_probe.dart', decoded.stdout)


if __name__ == '__main__':
    unittest.main()
