"""Exercise connectivity-check outcomes with a fake nc; no network requests."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "test_connect_ss.sh"


class ConnectivityCheck(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix="ss-connect-test-")
        self.addCleanup(self.work.cleanup)
        self.nc = Path(self.work.name) / "nc"
        self.nc.write_text("""#!/bin/sh
case "$*" in
    '-z -w 5 proxy.example.com 443') exit "$NC_443" ;;
    '-z -w 5 proxy.example.com 22') exit "$NC_22" ;;
    *) exit 2 ;;
esac
""")
        self.nc.chmod(0o700)

    def run_check(self, mode=None, https_open=False, ssh_open=False):
        args = ["/bin/sh", str(SCRIPT), "proxy.example.com"]
        if mode is not None:
            args.append(mode)
        return subprocess.run(
            args, capture_output=True, text=True,
            env={
                **os.environ,
                "PATH": self.work.name,
                "NC_443": "0" if https_open else "1",
                "NC_22": "0" if ssh_open else "1",
            },
        )

    def test_expected_access_and_ssh_rejection(self):
        for mode in ("reachable", "blocked"):
            for https_open in (True, False):
                for ssh_open in (True, False):
                    with self.subTest(mode=mode, https=https_open, ssh=ssh_open):
                        result = self.run_check(mode, https_open, ssh_open)
                        success = https_open == (mode == "reachable") and not ssh_open
                        self.assertEqual(result.returncode == 0, success, result.stderr)
                        if success:
                            self.assertIn(f"TCP 443 is {mode}", result.stdout)
                        else:
                            self.assertIn("ERROR:", result.stderr)

    def test_default_requires_reachable_https(self):
        self.assertEqual(self.run_check(https_open=True).returncode, 0)
        self.assertNotEqual(self.run_check(https_open=False).returncode, 0)

    def test_invalid_mode_is_rejected(self):
        result = self.run_check("typo")
        self.assertEqual(result.returncode, 2)
        self.assertIn("must be reachable or blocked", result.stderr)

    def test_missing_nc_cannot_pass_blocked_check(self):
        self.nc.unlink()
        result = self.run_check("blocked")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("nc is required", result.stderr)


if __name__ == "__main__":
    unittest.main()
