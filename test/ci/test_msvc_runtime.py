from pathlib import Path
import struct
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


def pe(machine):
    value = bytearray(256)
    value[:2] = b'MZ'
    struct.pack_into('<I', value, 60, 128)
    value[128:132] = b'PE\0\0'
    struct.pack_into('<H', value, 132, machine)
    return value


class MsvcRuntimeCmakeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='toxee CRT ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.files = {}
        for name in ('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140_atomic_wait.dll'):
            path = self.root / name
            path.write_bytes(pe(0x8664))
            self.files[name] = path

    def configure(self, arch='x64', install=False):
        library_args = ' '.join('"' + str(p) + '"' for p in self.files.values())
        (self.root / 'CMakeLists.txt').write_text(
            'cmake_minimum_required(VERSION 3.14)\nproject(runtime NONE)\n'
            f'include("{ROOT}/windows/cmake/msvc_runtime.cmake")\n'
            f'toxee_install_msvc_files("${{CMAKE_INSTALL_PREFIX}}" "{arch}" {library_args})\n')
        result = subprocess.run(['cmake', '-S', str(self.root), '-B', str(self.root / 'build'),
                                 '-DCMAKE_INSTALL_PREFIX=' + str(self.root / 'installed')],
                                capture_output=True, text=True)
        if install and result.returncode == 0:
            result = subprocess.run(['cmake', '--install', str(self.root / 'build'), '--config', 'Release'],
                                    capture_output=True, text=True)
        return result

    def test_real_cmake_install_copies_release_dlls_and_license_notice(self):
        result = self.configure(install=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, path in self.files.items():
            self.assertEqual((self.root / 'installed' / name).read_bytes(), path.read_bytes())
        self.assertIn('license terms', (self.root / 'installed/MICROSOFT_RUNTIME_NOTICE.txt').read_text())

    def test_missing_required_crt_fails_configuration(self):
        self.files.pop('msvcp140.dll')
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing required', result.stderr)

    def test_native_arm64_crts_are_kept_but_ec_only_supplement_is_excluded(self):
        for name, path in self.files.items():
            path.write_bytes(pe(0x8664 if name == 'vcruntime140_1.dll' else 0xaa64))
        result = self.configure('arm64', install=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'installed/vcruntime140_1.dll').exists())
        self.assertTrue((self.root / 'installed/vcruntime140.dll').is_file())

    def test_x64_crt_cannot_enter_arm64_bundle(self):
        result = self.configure('arm64')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('CPU mismatch', result.stderr)

    def test_unreviewed_debug_file_cannot_be_redistributed(self):
        path = self.root / 'vcruntime140d.dll'
        path.write_bytes(pe(0x8664))
        self.files[path.name] = path
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unreviewed', result.stderr)

    def test_corrupt_runtime_fails_configuration(self):
        self.files['vcruntime140.dll'].write_text('corrupt')
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)

    def select_toolchain_runtime(self, ambiguous=False):
        redist = self.root / 'redist'
        for arch, machine in (('x64', 0x8664), ('arm64', 0xaa64)):
            directory = redist / arch / 'Microsoft.VC145.CRT'
            directory.mkdir(parents=True)
            for name in self.files:
                (directory / name).write_bytes(pe(0x8664 if arch == 'arm64' and name == 'vcruntime140_1.dll' else machine))
        if ambiguous:
            (redist / 'arm64/Microsoft.VC143.CRT').mkdir()
        (self.root / 'CMakeLists.txt').write_text(
            'cmake_minimum_required(VERSION 3.14)\nproject(runtime NONE)\n'
            'set(MSVC_CXX_ARCHITECTURE_ID ARM64)\n'
            f'set(ENV{{VCToolsRedistDir}} "{redist}")\n'
            f'include("{ROOT}/windows/cmake/msvc_runtime.cmake")\n'
            'toxee_install_msvc_runtime("${CMAKE_INSTALL_PREFIX}")\n')
        return subprocess.run(['cmake', '-S', str(self.root), '-B', str(self.root / 'selected'),
                               '-DCMAKE_INSTALL_PREFIX=' + str(self.root / 'installed')],
                              capture_output=True, text=True)

    def test_toolchain_architecture_selects_arm64_not_host_x64(self):
        result = self.select_toolchain_runtime()
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run(['cmake', '--install', str(self.root / 'selected'), '--config', 'Release'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'installed/msvcp140.dll').read_bytes(), pe(0xaa64))
        self.assertFalse((self.root / 'installed/vcruntime140_1.dll').exists())

    def test_ambiguous_toolchain_crt_directories_fail(self):
        result = self.select_toolchain_runtime(ambiguous=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Expected one arm64', result.stderr)


if __name__ == '__main__':
    unittest.main()
