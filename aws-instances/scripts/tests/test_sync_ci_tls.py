"""Offline integration checks for TLS sync and the Makefile success hook."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


MODULE = Path(__file__).resolve().parents[2]


class SyncCiTlsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        (self.root / "files/tmpsc.net").mkdir(parents=True)
        (self.root / "bin").mkdir()
        shutil.copyfile(MODULE / "scripts/sync-ci-tls.sh", self.root / "scripts/sync-ci-tls.sh")
        shutil.copyfile(MODULE / "Makefile", self.root / "Makefile")
        self.cert = "certificate\nwith multiple lines\n"
        self.key = "private key\nwith multiple lines\n"
        (self.root / "files/tmpsc.net/tmpsc_net.cer").write_text(self.cert)
        (self.root / "files/tmpsc.net/tmpsc_net.key").write_text(self.key)
        self.log = self.root / "requests.jsonl"
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
                        REQUEST_LOG=str(self.log))
        self.executable("glab", '''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["REQUEST_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if "--method" not in args:
    if os.environ.get("LIST_FAIL"):
        sys.exit(1)
    print(os.environ.get("VARIABLES", "[]"))
else:
    if os.environ.get("WRITE_FAIL"):
        sys.exit(1)
    value = next(a[7:] for a in args if a.startswith("value=@"))
    with open(os.environ["REQUEST_LOG"] + ".values", "a") as log:
        log.write(json.dumps(pathlib.Path(value).read_text()) + "\\n")
''')
        self.executable("terraform", '#!/bin/sh\nexit "${TF_EXIT:-0}"\n')

    def executable(self, name, content):
        path = self.root / "bin" / name
        path.write_text(content)
        path.chmod(0o700)

    def run_command(self, *args):
        result = subprocess.run(args, cwd=self.root, env=self.env, text=True,
                                capture_output=True)
        self.assertNotIn(self.cert, result.stdout + result.stderr)
        self.assertNotIn(self.key, result.stdout + result.stderr)
        return result

    def requests(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_creates_file_variables_with_exact_contents(self):
        result = self.run_command("bash", "scripts/sync-ci-tls.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        writes = self.requests()[1:]
        self.assertEqual(len(writes), 2)
        for request in writes:
            self.assertEqual(request[request.index("--method") + 1], "POST")
            for field in ("variable_type=file", "protected=true", "raw=true", "environment_scope=*"):
                self.assertIn(field, request)
        values = [json.loads(line) for line in Path(str(self.log) + ".values").read_text().splitlines()]
        self.assertEqual(values, [self.cert, self.key])

    def test_updates_only_matching_scope(self):
        self.env["VARIABLES"] = json.dumps([
            {"key": "SS_TLS_CERT_FILE", "environment_scope": "production"},
            {"key": "SS_TLS_KEY_FILE", "environment_scope": "*"},
        ])
        result = self.run_command("bash", "scripts/sync-ci-tls.sh", "--scope", "production")
        self.assertEqual(result.returncode, 0, result.stderr)
        cert, key = self.requests()[1:]
        self.assertIn("PUT", cert)
        self.assertIn("filter%5Benvironment_scope%5D=production", cert[1])
        self.assertIn("POST", key)

    def test_missing_file_prevents_all_requests(self):
        (self.root / "files/tmpsc.net/tmpsc_net.key").unlink()
        result = self.run_command("bash", "scripts/sync-ci-tls.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_list_failure_does_not_create_variables(self):
        self.env["LIST_FAIL"] = "1"
        result = self.run_command("bash", "scripts/sync-ci-tls.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.requests()), 1)

    def test_failed_apply_skips_sync_and_keeps_plan(self):
        (self.root / "tfplan").touch()
        self.env["TF_EXIT"] = "1"
        result = self.run_command("make", "apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())
        self.assertTrue((self.root / "tfplan").exists())

    def test_successful_apply_runs_sync(self):
        (self.root / "tfplan").touch()
        result = self.run_command("make", "apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.requests()), 3)
        self.assertFalse((self.root / "tfplan").exists())

    def test_sync_failure_fails_make_after_successful_apply(self):
        (self.root / "tfplan").touch()
        self.env["WRITE_FAIL"] = "1"
        result = self.run_command("make", "apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "tfplan").exists())
        self.assertEqual(len(self.requests()), 2)


if __name__ == "__main__":
    unittest.main()
