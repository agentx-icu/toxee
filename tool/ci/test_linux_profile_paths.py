#!/usr/bin/env python3
"""Real process environments; executes AppPaths and its on-disk migration."""
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
ACCOUNT = "existing-private-account-fixture"


class LinuxProfilePaths(unittest.TestCase):
    def test_real_environments(self):
        self.assertEqual(platform.system(), "Linux", "requires a native Linux host")
        for case in ("relative-migrate", "absolute-existing", "unset-default", "relative-no-home"):
            with self.subTest(case=case), tempfile.TemporaryDirectory(prefix="toxee-paths-") as tmp:
                root = Path(tmp)
                home = root / "home"
                home.mkdir()
                (root / "cwd").mkdir()
                legacy = home / ".config/toxee/profiles"
                legacy.mkdir(parents=True)
                env = dict(os.environ)
                for key in ("TOXEE_APP_SUPPORT_DIR", "XDG_DATA_HOME", "HOME"):
                    env.pop(key, None)
                env["HOME"] = str(home)
                env["XDG_CONFIG_HOME"] = str(root / "tool-config")
                env["FLUTTER_SUPPRESS_ANALYTICS"] = "true"
                if case == "absolute-existing":
                    data = root / "absolute-data"
                    env["XDG_DATA_HOME"] = str(data)
                    expected = data / "toxee/profiles"
                    expected.mkdir(parents=True)
                    (expected / "account.tox").write_text(ACCOUNT)
                    (legacy / "account.tox").write_text("legacy-account-fixture")
                    env["TOXEE_PATH_PROBE_RETAINED_LEGACY"] = str(legacy)
                elif case == "relative-no-home":
                    env.pop("HOME")
                    env["XDG_DATA_HOME"] = "relative-data"
                    expected = root / "platform-support/profiles"
                    expected.mkdir(parents=True)
                    (expected / "account.tox").write_text(ACCOUNT)
                else:
                    if case == "relative-migrate":
                        env["XDG_DATA_HOME"] = "relative-data"
                    expected = home / ".local/share/toxee/profiles"
                    (legacy / "account.tox").write_text(ACCOUNT)
                env["TOXEE_PATH_PROBE_ROOT"] = str(root)
                env["TOXEE_PATH_PROBE_EXPECTED"] = str(expected)
                # Preserve the already resolved dependency cache when HOME changes.
                env["PUB_CACHE"] = os.environ.get("PUB_CACHE", str(Path.home() / ".pub-cache"))
                result = subprocess.run(
                    ["flutter", "test", "--no-pub", "test/support/linux_profile_root_probe.dart"],
                    cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, timeout=180,
                )
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual((expected / "account.tox").read_text(), ACCOUNT)
                self.assertFalse((root / "cwd/relative-data/toxee").exists())
                print(f"PASS {case}: native Linux environment, account bytes, migration, idempotence, custom root")


if __name__ == "__main__":
    unittest.main()
