"""Offline integration tests for rotate-iam-key.sh (stdlib plus its CLI deps)."""

import datetime as dt
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "rotate-iam-key.sh"
NOW = dt.datetime(2026, 10, 31, tzinfo=dt.timezone.utc)
OLD_KEY = "FAKE_OLD_KEY"
NEW_KEY = "FAKE_NEW_KEY"
CALLER_KEY = "FAKE_CALLER_KEY"
OLD_SECRET = "FAKE_OLD_SECRET_NOT_A_CREDENTIAL"
NEW_SECRET = "FAKE_NEW_SECRET_NOT_A_CREDENTIAL"
CALLER_SECRET = "FAKE_CALLER_SECRET_NOT_A_CREDENTIAL"

# Each invocation reloads state, so subprocesses observe earlier mutations.
# Unrecognized commands fail closed; no mock can delegate to aws or glab.
MOCK_CLI = r'''
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import parse_qs, unquote, urlsplit

path = Path(os.environ["MOCK_STATE"])
state = json.loads(path.read_text())
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
entry = {"tool": tool, "argv": args}
state["calls"].append(entry)

def finish(value=None, code=0):
    path.write_text(json.dumps(state))
    if value is not None:
        print(json.dumps(value))
    if code:
        print("mock failure", file=sys.stderr)
    sys.exit(code)

def operation(name):
    entry["op"] = name
    count = state["counts"].get(name, 0) + 1
    state["counts"][name] = count
    if state["fail"].get(name) == count:
        finish(code=1)
    return count

if tool == "date":
    entry["op"] = "date"
    path.write_text(json.dumps(state))
    if args == ["-u", "+%s"]:
        print(state["now"])
        sys.exit(0)
    assert len(args) == 4 and args[:2] == ["-u", "-d"] and args[3] == "+%s", args
    sys.exit(subprocess.run([state["real_date"], *args]).returncode)

if tool == "aws":
    prefix = (["--profile", state["profile"]] if state["profile"] else [])
    prefix += ["--output", "json", "--no-cli-pager"]
    assert args[:len(prefix)] == prefix, args
    args = args[len(prefix):]
    service, command, *flags = args
    count = operation(command)
    if (service, command) == ("sts", "get-caller-identity"):
        assert not flags
        finish({"Account": "000000000000", "Arn": "arn:aws:iam::000000000000:user/mock"})
    if (service, command) == ("configure", "export-credentials"):
        assert flags == ["--format", "process"]
        finish({"Version": 1, "AccessKeyId": state["caller"],
                "SecretAccessKey": state["caller_secret"]})
    assert service == "iam", args
    if command == "get-access-key-last-used":
        assert flags[:1] == ["--access-key-id"] and len(flags) == 2
        key = flags[1]
        usage_count = state["usage_counts"].get(key, 0) + 1
        state["usage_counts"][key] = usage_count
        used = state["usage"][key]
        if state.get("newly_used") == key and usage_count == 2:
            used = state["recent"]
        finish({"AccessKeyLastUsed": {"LastUsedDate": used} if used or state.get("null_usage") else {}})
    assert flags[:2] == ["--user-name", state["user"]], flags
    if command == "list-access-keys":
        assert len(flags) == 2
        if state.get("changed_keys") and count == 2:
            state["keys"][0]["Status"] = "Inactive"
        finish({"AccessKeyMetadata": state["keys"]})
    if command == "delete-access-key":
        assert len(flags) == 4 and flags[2] == "--access-key-id"
        assert any(key["AccessKeyId"] == flags[3] for key in state["keys"])
        state["keys"] = [key for key in state["keys"] if key["AccessKeyId"] != flags[3]]
        finish({})
    if command == "create-access-key":
        assert len(flags) == 2
        response = state["created"]
        state["keys"].append({k: v for k, v in response["AccessKey"].items()
                              if k != "SecretAccessKey"})
        finish(response)

elif tool == "glab":
    assert args[0] == "api", args
    url = urlsplit(args[1])
    parts = url.path.split("/")
    assert len(parts) == 4 and parts[0] == "projects" and parts[2] == "variables"
    assert unquote(parts[1]) == state["project"], args
    expected_query = ({"filter[environment_scope]": [state["filter_scope"]]}
                      if state["filter_scope"] is not None else {})
    assert parse_qs(url.query) == expected_query, args
    name = parts[3]
    assert name in state["variables"], args
    assert args[2:5] == ["--hostname", state["hostname"], "--method"], args
    method = args[5]
    if method == "PUT":
        assert args[6:] == ["--field", "value=@-", "--silent"], args
        entry["stdin"] = sys.stdin.read()
    else:
        assert method == "GET" and len(args) == 6, args
    count = operation(method + ":" + name)
    variable = state["variables"][name]
    if method == "GET":
        if "raw_response" in state:
            sys.stdout.write(state["raw_response"])
            finish()
        if (state.get("changed_variable") == name and count == 2
                or state.get("bad_verification") == name and count == 3):
            variable = dict(variable, value="FAKE_CONCURRENT_VALUE")
        if (state.get("changed_metadata") == name and count == 2
                or state.get("bad_metadata") == name and count == 3):
            variable = dict(variable, protected=not variable["protected"])
        if variable.get("hidden") is True and "value" in variable:
            variable = dict(variable, value=None)
        finish(variable)
    variable["value"] = entry["stdin"]
    finish(variable)

raise AssertionError("Unexpected mock command: " + repr(sys.argv))
'''


def timestamp(days=0, seconds=0):
    return (NOW - dt.timedelta(days=days, seconds=seconds)).isoformat().replace("+00:00", "Z")


class RotateIAMKeyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for dependency in ("bash", "jq", "date"):
            if not shutil.which(dependency):
                raise unittest.SkipTest(f"Script dependency unavailable: {dependency}")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="test-rotate-iam-key-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        executable = self.bin / "mock-cli"
        executable.write_text(f"#!{sys.executable}\n" + MOCK_CLI)
        executable.chmod(0o700)
        for name in ("aws", "glab", "date"):
            (self.bin / name).symlink_to(executable)
        self.state_path = self.root / "state.json"
        self.id_name = "AWS_ACCESS_KEY_ID"
        self.secret_name = "AWS_SECRET_ACCESS_KEY"
        self.state = {
            "now": int(NOW.timestamp()), "real_date": shutil.which("date"),
            "user": "rotation-test", "project": "123", "scope": "*", "filter_scope": None,
            "profile": "", "hostname": "gitlab.com", "caller": CALLER_KEY,
            "caller_secret": CALLER_SECRET, "recent": timestamp(1),
            "keys": [], "usage": {}, "variables": {},
            "calls": [], "counts": {}, "usage_counts": {}, "fail": {},
            "created": {"AccessKey": {
                "UserName": "rotation-test", "AccessKeyId": NEW_KEY,
                "SecretAccessKey": NEW_SECRET, "Status": "Active",
                "CreateDate": timestamp(),
            }},
        }
        self.set_keys((OLD_KEY, 200, 100))
        self.set_variables()

    def set_keys(self, *keys):
        self.state["keys"] = [
            {"UserName": self.state["user"], "AccessKeyId": key,
             "Status": "Active", "CreateDate": timestamp(created)}
            for key, created, used in keys
        ]
        self.state["usage"] = {
            key: timestamp(used) if used is not None else None
            for key, created, used in keys
        }

    def set_variables(self):
        self.state["variables"] = {
            name: {"key": name, "value": value, "variable_type": "env_var",
                   "environment_scope": self.state["scope"], "protected": True,
                   "masked": masked, "hidden": False, "raw": False,
                   "description": "Keep this metadata"}
            for name, value, masked in (
                (self.id_name, OLD_KEY, False), (self.secret_name, OLD_SECRET, True))
        }

    def run_script(self, *options, success=True, trace=False):
        self.state.update(calls=[], counts={}, usage_counts={})
        self.state_path.write_text(json.dumps(self.state))
        # Do not inherit credentials, CLI configuration, shell startup, or debug env.
        env = {
            "PATH": str(self.bin) + os.pathsep + os.defpath,
            "HOME": str(self.root), "TMPDIR": str(self.root), "LC_ALL": "C",
            "MOCK_STATE": str(self.state_path), "AWS_EC2_METADATA_DISABLED": "true",
        }
        result = subprocess.run(
            [shutil.which("bash"), *(["-x"] if trace else []), str(SCRIPT), "--user", self.state["user"],
             "--project", self.state["project"], *options],
            env=env, cwd=self.root, text=True, capture_output=True, timeout=30,
        )
        self.state = json.loads(self.state_path.read_text())
        diagnostic = result.stdout + result.stderr
        if success:
            self.assertEqual(result.returncode, 0, diagnostic)
        else:
            self.assertNotEqual(result.returncode, 0, diagnostic)
        self.assertNotIn("Traceback", diagnostic)
        argv = json.dumps([call["argv"] for call in self.state["calls"]])
        for secret in (OLD_SECRET, NEW_SECRET, CALLER_SECRET):
            self.assertNotIn(secret, diagnostic)
            self.assertNotIn(secret, argv)
        self.assertNotIn(NEW_KEY, argv)
        return result

    def mutations(self):
        return [call for call in self.state["calls"]
                if call.get("op") in ("delete-access-key", "create-access-key")
                or call.get("op", "").startswith("PUT:")]

    def recovery_files(self):
        return list(self.root.glob("rotate-iam-key.*.json"))

    def assert_no_mutations(self):
        self.assertEqual(self.mutations(), [])
        self.assertEqual(self.recovery_files(), [])

    def assert_recovery(self, result, complete=True):
        files = self.recovery_files()
        self.assertEqual(len(files), 1)
        recovery = files[0]
        self.assertEqual(stat.S_IMODE(recovery.stat().st_mode), 0o600)
        self.assertIn(str(recovery), result.stderr)
        self.assertIn("old key was deleted", result.stderr)
        if complete:
            self.assertEqual(json.loads(recovery.read_text()), self.state["created"])
        return recovery

    def test_dry_run_does_not_mutate(self):
        before = json.loads(json.dumps(self.state))
        result = self.run_script()
        self.assertIn("Dry-run", result.stdout)
        self.assertIn("Selected key: " + OLD_KEY, result.stdout)
        self.assertEqual(self.state["keys"], before["keys"])
        self.assertEqual(self.state["variables"], before["variables"])
        self.assert_no_mutations()

    def test_success_orders_mutations_and_preserves_metadata(self):
        before = json.loads(json.dumps(self.state["variables"]))
        result = self.run_script("--apply")
        mutations = self.mutations()
        self.assertEqual([call["op"] for call in mutations], [
            "delete-access-key", "create-access-key",
            "PUT:" + self.secret_name, "PUT:" + self.id_name,
        ])
        self.assertEqual(mutations[0]["argv"][-2:], ["--access-key-id", OLD_KEY])
        for call, name, value in ((mutations[2], self.secret_name, NEW_SECRET),
                                  (mutations[3], self.id_name, NEW_KEY)):
            self.assertEqual(call["stdin"], value)
            self.assertEqual(call["argv"][-3:], ["--field", "value=@-", "--silent"])
            self.assertEqual(self.state["variables"][name], dict(before[name], value=value))
            self.assertEqual(self.state["counts"]["GET:" + name], 3)
        self.assertEqual(self.state["counts"]["list-access-keys"], 2)
        self.assertEqual(self.state["usage_counts"][OLD_KEY], 2)
        self.assertEqual([call["op"] for call in self.state["calls"]
                          if call["tool"] != "date"], [
            "get-caller-identity", "export-credentials",
            "GET:" + self.id_name, "GET:" + self.secret_name,
            "list-access-keys", "get-access-key-last-used",
            "GET:" + self.id_name, "GET:" + self.secret_name,
            "list-access-keys", "get-access-key-last-used",
            "delete-access-key", "create-access-key",
            "PUT:" + self.secret_name, "PUT:" + self.id_name,
            "GET:" + self.secret_name, "GET:" + self.id_name,
        ])
        self.assertEqual([key["AccessKeyId"] for key in self.state["keys"]], [NEW_KEY])
        self.assertIn("Rotation complete", result.stdout)
        self.assertEqual(self.recovery_files(), [])

    def test_exact_90_day_boundary_used_and_never_used(self):
        for never_used in (False, True):
            for seconds, eligible in ((-1, False), (0, True), (1, True)):
                with self.subTest(never_used=never_used, seconds=seconds):
                    self.set_keys((OLD_KEY, 200, None if never_used else 90))
                    boundary = timestamp(90, seconds)
                    if never_used:
                        self.state["keys"][0]["CreateDate"] = boundary
                    else:
                        self.state["usage"][OLD_KEY] = boundary
                    eligible = never_used or eligible
                    result = self.run_script("--apply", success=eligible)
                    if eligible:
                        self.assertIn("Rotation complete", result.stdout)
                        self.assertEqual(len(self.mutations()), 4)
                        self.assertEqual(self.state["usage_counts"][OLD_KEY], 2)
                    else:
                        self.assertIn("No eligible key", result.stderr)
                        self.assert_no_mutations()

    def test_recent_use_or_creation_is_ineligible(self):
        for created, used in ((200, 1), (1, 200)):
            with self.subTest(created=created, used=used):
                self.set_keys((OLD_KEY, created, used))
                self.run_script("--apply", success=False)
                self.assert_no_mutations()

    def test_never_used_keys_are_eligible_even_when_new(self):
        for explicit_null in (False, True):
            with self.subTest(explicit_null=explicit_null):
                self.set_keys((OLD_KEY, 0, None))
                self.state["null_usage"] = explicit_null
                result = self.run_script("--days", "999999", "--apply")
                self.assertIn("Never used (created", result.stdout)
                self.assertEqual(len(self.mutations()), 4)
                self.assertEqual(self.state["usage_counts"][OLD_KEY], 2)

    def test_never_used_key_is_selected_over_ineligible_recently_used_key(self):
        self.set_keys(("FAKE_RECENTLY_USED", 200, 1), (OLD_KEY, 1, None))
        result = self.run_script("--apply")
        self.assertIn("Selected key: " + OLD_KEY, result.stdout)
        self.assertEqual(self.mutations()[0]["argv"][-1], OLD_KEY)

    def test_two_never_used_keys_are_ranked_by_creation(self):
        self.set_keys(("FAKE_NEW_UNUSED", 1, None), (OLD_KEY, 2, None))
        result = self.run_script()
        self.assertIn("Selected key: " + OLD_KEY, result.stdout)
        self.assert_no_mutations()

    def test_previously_never_used_key_with_new_usage_aborts(self):
        self.set_keys((OLD_KEY, 5, None))
        self.state["newly_used"] = OLD_KEY
        result = self.run_script("--apply", success=False)
        self.assertIn("Selected key was used recently", result.stderr)
        self.assert_no_mutations()

    def test_empty_key_list_has_no_eligible_key(self):
        self.set_keys()
        result = self.run_script("--apply", success=False)
        self.assertIn("No eligible key", result.stderr)
        self.assert_no_mutations()

    def test_oldest_of_two_by_use_not_creation_or_list_order(self):
        for reverse in (False, True):
            with self.subTest(reverse=reverse):
                keys = [("FAKE_LONG_UNUSED", 200, 150), ("FAKE_OLDER_CREATED", 300, 100)]
                self.set_keys(*(reversed(keys) if reverse else keys))
                result = self.run_script()
                self.assertIn("Selected key: FAKE_LONG_UNUSED\n", result.stdout)
                self.assert_no_mutations()

    def test_caller_key_is_excluded(self):
        self.set_keys((CALLER_KEY, 400, None), (OLD_KEY, 200, 100))
        self.run_script("--apply")
        self.assertEqual(self.mutations()[0]["argv"][-1], OLD_KEY)
        self.assertNotIn(CALLER_KEY, self.state["usage_counts"])
        self.assertIn(CALLER_KEY, [key["AccessKeyId"] for key in self.state["keys"]])

    def test_only_caller_key_is_not_eligible(self):
        self.set_keys((CALLER_KEY, 400, None))
        self.run_script("--apply", success=False)
        self.assert_no_mutations()

    def test_current_gitlab_key_can_be_deleted_with_warning(self):
        result = self.run_script("--apply")
        self.assertIn("currently configured in GitLab", result.stderr)
        self.assertEqual(self.mutations()[0]["argv"][-1], OLD_KEY)

    def test_preflight_failures_do_not_mutate(self):
        for op in ("get-caller-identity", "export-credentials", "list-access-keys",
                   "get-access-key-last-used", "GET:" + self.id_name,
                   "GET:" + self.secret_name):
            with self.subTest(op=op):
                self.state["fail"] = {op: 1}
                self.run_script("--apply", success=False)
                self.assert_no_mutations()

    def test_invalid_arguments_do_not_call_apis(self):
        for options in (("--days", "0"), ("--days", "-1"), ("--days", "1.5"),
                        ("--days", "1000000"), ("--scope",), ("--unknown",),
                        ("--secret-variable", self.id_name)):
            with self.subTest(options=options):
                self.run_script(*options, success=False)
                self.assertEqual(self.state["calls"], [])
                self.assert_no_mutations()

    def test_wrong_variable_metadata_aborts_before_deletion(self):
        for field, value, diagnostic in (
            ("variable_type", "file", "variable_type is missing or is not env_var"),
            ("key", "WRONG_KEY", "key is missing or does not match"),
            ("value", None, "value must be a string, or null with hidden: true"),
            ("value", 123, "value must be a string, or null with hidden: true"),
        ):
            with self.subTest(field=field):
                self.set_variables()
                self.state["variables"][self.secret_name][field] = value
                result = self.run_script("--apply", success=False)
                self.assertIn(diagnostic, result.stderr)
                self.assert_no_mutations()

    def test_malformed_responses_have_safe_diagnostics(self):
        valid = json.dumps(self.state["variables"][self.secret_name])
        for response, diagnostic in (
            ("", "expected exactly one JSON value"),
            ("<html>" + OLD_SECRET, "invalid JSON or jq execution failure"),
            ("[]", "response is not a JSON object"),
            ("null", "response is not a JSON object"),
            (valid + valid, "expected exactly one JSON value"),
        ):
            with self.subTest(diagnostic=diagnostic, response_type=response[:1]):
                self.state["raw_response"] = response
                result = self.run_script("--apply", success=False)
                self.assertIn(diagnostic, result.stderr)
                self.assert_no_mutations()

    def test_missing_metadata_is_identified(self):
        for field in ("key", "variable_type", "value"):
            with self.subTest(field=field):
                self.set_variables()
                del self.state["variables"][self.secret_name][field]
                result = self.run_script("--apply", success=False)
                self.assertIn(field + " is missing", result.stderr)
                self.assert_no_mutations()

    def test_trace_is_disabled_before_handling_credentials(self):
        self.run_script("--apply", trace=True)
        self.assertEqual(len(self.mutations()), 4)

    def test_hidden_variables_allow_dry_run_with_warnings(self):
        for variable in self.state["variables"].values():
            variable.update(hidden=True, masked=True)
        result = self.run_script()
        self.assertIn("key ID is hidden", result.stderr)
        self.assertIn("Hidden values cannot be read back", result.stderr)
        self.assert_no_mutations()

    def test_hidden_updates_preserve_metadata_and_retain_recovery(self):
        for hidden_names in ((self.id_name,), (self.secret_name,),
                             (self.id_name, self.secret_name)):
            with self.subTest(hidden_names=hidden_names):
                self.set_keys((OLD_KEY, 200, 100))
                self.set_variables()
                for name in hidden_names:
                    self.state["variables"][name].update(hidden=True, masked=True)
                before = json.loads(json.dumps(self.state["variables"]))
                result = self.run_script("--apply")
                self.assertEqual(len(self.mutations()), 4)
                for name, value in ((self.id_name, NEW_KEY), (self.secret_name, NEW_SECRET)):
                    self.assertEqual(self.state["variables"][name], dict(before[name], value=value))
                self.assertIn("Manual verification required for hidden values", result.stdout)
                self.assertNotIn("Both GitLab variables verified", result.stdout)
                self.assertNotIn("Rotation incomplete", result.stderr)
                files = self.recovery_files()
                self.assertEqual(len(files), 1)
                self.assertEqual(stat.S_IMODE(files[0].stat().st_mode), 0o600)
                self.assertEqual(json.loads(files[0].read_text()), self.state["created"])
                self.assertIn(str(files[0]), result.stderr)
                files[0].unlink()

    def test_hidden_flag_does_not_allow_invalid_values(self):
        base = self.state["variables"][self.id_name]
        for response in (dict(base, hidden=True, value=123),
                         dict(base, hidden="true", value=None),
                         {k: v for k, v in dict(base, hidden=True).items() if k != "value"}):
            with self.subTest(value_present="value" in response):
                self.state["raw_response"] = json.dumps(response)
                self.run_script("--apply", success=False)
                self.assert_no_mutations()

    def test_hidden_update_failure_retains_recovery(self):
        for name in (self.secret_name, self.id_name):
            with self.subTest(variable=name):
                self.set_keys((OLD_KEY, 200, 100))
                self.set_variables()
                for variable in self.state["variables"].values():
                    variable.update(hidden=True, masked=True)
                self.state["fail"] = {"PUT:" + name: 1}
                result = self.run_script("--apply", success=False)
                self.assertIn("update failed", result.stderr)
                self.assert_recovery(result).unlink()

    def test_hidden_metadata_change_before_delete_aborts(self):
        self.state["variables"][self.id_name].update(hidden=True, masked=True)
        self.state["changed_metadata"] = self.id_name
        result = self.run_script("--apply", success=False)
        self.assertIn("variable changed or cannot be rechecked", result.stderr)
        self.assert_no_mutations()

    def test_hidden_metadata_verification_failure_retains_recovery(self):
        self.state["variables"][self.id_name].update(hidden=True, masked=True)
        self.state["bad_metadata"] = self.id_name
        result = self.run_script("--apply", success=False)
        self.assertIn("metadata changed unexpectedly", result.stderr)
        self.assert_recovery(result)

    def test_hidden_secret_does_not_skip_visible_id_verification(self):
        self.state["variables"][self.secret_name].update(hidden=True, masked=True)
        self.state["bad_verification"] = self.id_name
        result = self.run_script("--apply", success=False)
        self.assertIn("ID verification failed", result.stderr)
        self.assert_recovery(result)

    def test_default_requests_do_not_filter_scope(self):
        self.state["scope"] = "production"
        self.set_variables()
        self.run_script("--apply")
        for call in self.state["calls"]:
            if call["tool"] == "glab":
                self.assertNotIn("?", call["argv"][1])
        self.assertEqual(len(self.mutations()), 4)

    def test_explicit_wildcard_scope_is_filtered(self):
        self.state["filter_scope"] = "*"
        self.run_script("--scope", "*", "--apply")
        self.assertEqual(len(self.mutations()), 4)

    def test_explicit_scope_mismatch_aborts_before_deletion(self):
        self.state["filter_scope"] = "*"
        self.state["variables"][self.secret_name]["environment_scope"] = "production"
        result = self.run_script("--scope", "*", "--apply", success=False)
        self.assertIn("environment_scope does not match --scope", result.stderr)
        self.assert_no_mutations()

    def test_api_failure_has_distinct_diagnostic(self):
        self.state["fail"] = {"GET:" + self.id_name: 1}
        result = self.run_script("--apply", success=False)
        self.assertIn("GitLab API GET failed", result.stderr)
        self.assertNotIn("response validation failed", result.stderr)
        self.assert_no_mutations()

    def test_deletion_failure_never_creates_and_removes_recovery(self):
        self.state["fail"] = {"delete-access-key": 1}
        result = self.run_script("--apply", success=False)
        self.assertIn("Key deletion failed", result.stderr)
        self.assertEqual([call["op"] for call in self.mutations()], ["delete-access-key"])
        self.assertEqual(self.state["keys"][0]["AccessKeyId"], OLD_KEY)
        self.assertEqual(self.recovery_files(), [])

    def test_creation_failure_retains_private_recovery_and_warns(self):
        self.state["fail"] = {"create-access-key": 1}
        result = self.run_script("--apply", success=False)
        self.assertIn("Replacement creation failed", result.stderr)
        self.assertEqual([call["op"] for call in self.mutations()],
                         ["delete-access-key", "create-access-key"])
        self.assertEqual(self.state["keys"], [])
        self.assertEqual(self.assert_recovery(result, complete=False).read_text(), "")

    def test_secret_update_failure_preserves_creation_response(self):
        self.state["fail"] = {"PUT:" + self.secret_name: 1}
        result = self.run_script("--apply", success=False)
        self.assertIn("GitLab secret update failed", result.stderr)
        self.assertIn("secret=false, ID=false", result.stderr)
        self.assertEqual(len(self.mutations()), 3)
        self.assertEqual(self.state["variables"][self.id_name]["value"], OLD_KEY)
        self.assertEqual(self.state["variables"][self.secret_name]["value"], OLD_SECRET)
        self.assert_recovery(result)

    def test_invalid_creation_response_is_retained_without_gitlab_updates(self):
        del self.state["created"]["AccessKey"]["SecretAccessKey"]
        result = self.run_script("--apply", success=False)
        self.assertIn("Invalid replacement response", result.stderr)
        self.assertEqual([call["op"] for call in self.mutations()],
                         ["delete-access-key", "create-access-key"])
        self.assert_recovery(result)

    def test_id_update_failure_preserves_creation_response(self):
        self.state["fail"] = {"PUT:" + self.id_name: 1}
        result = self.run_script("--apply", success=False)
        self.assertIn("GitLab ID update failed", result.stderr)
        self.assertIn("secret=true, ID=false", result.stderr)
        self.assertEqual(len(self.mutations()), 4)
        self.assertEqual(self.state["variables"][self.id_name]["value"], OLD_KEY)
        self.assertEqual(self.state["variables"][self.secret_name]["value"], NEW_SECRET)
        self.assert_recovery(result)

    def test_verification_mismatch_retains_recovery(self):
        for name in (self.secret_name, self.id_name):
            with self.subTest(variable=name):
                self.set_keys((OLD_KEY, 200, 100))
                self.set_variables()
                self.state["bad_verification"] = name
                result = self.run_script("--apply", success=False)
                self.assertIn("verification failed", result.stderr)
                self.assertIn("secret=true, ID=true", result.stderr)
                self.assert_recovery(result).unlink()

    def test_changed_variable_aborts_before_deletion(self):
        for name in (self.id_name, self.secret_name):
            with self.subTest(variable=name):
                self.state["changed_variable"] = name
                result = self.run_script("--apply", success=False)
                self.assertIn("variable changed or cannot be rechecked", result.stderr)
                self.assert_no_mutations()

    def test_newly_used_key_aborts_before_deletion(self):
        self.state["newly_used"] = OLD_KEY
        result = self.run_script("--apply", success=False)
        self.assertIn("Selected key was used recently", result.stderr)
        self.assert_no_mutations()

    def test_changed_key_list_aborts_before_deletion(self):
        self.state["changed_keys"] = True
        result = self.run_script("--apply", success=False)
        self.assertIn("IAM keys changed", result.stderr)
        self.assert_no_mutations()

    def test_custom_options_and_encoded_endpoints(self):
        self.state.update(project="group/sub group/project", scope="review/* +prod",
                          filter_scope="review/* +prod", profile="rotation-profile",
                          hostname="gitlab.example.test")
        self.id_name, self.secret_name = "CUSTOM_KEY_ID", "CUSTOM_KEY_SECRET"
        self.set_variables()
        self.set_keys((OLD_KEY, 60, 40))
        self.run_script("--apply", "--days", "30", "--scope", self.state["scope"],
                        "--profile", self.state["profile"], "--hostname", self.state["hostname"],
                        "--id-variable", self.id_name, "--secret-variable", self.secret_name)
        for call in self.state["calls"]:
            if call["tool"] == "aws":
                self.assertEqual(call["argv"][:5],
                                 ["--profile", "rotation-profile", "--output", "json", "--no-cli-pager"])
            elif call["tool"] == "glab":
                self.assertIn("projects/group%2Fsub%20group%2Fproject/variables/CUSTOM_KEY_", call["argv"][1])
                self.assertIn("?filter%5Benvironment_scope%5D=review%2F%2A%20%2Bprod", call["argv"][1])
                self.assertEqual(call["argv"][2:4], ["--hostname", "gitlab.example.test"])
        self.assertEqual(len(self.mutations()), 4)


if __name__ == "__main__":
    unittest.main()
