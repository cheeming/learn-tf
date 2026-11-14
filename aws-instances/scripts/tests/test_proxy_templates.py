"""Offline template checks. No backend, AWS requests, or real secrets are used."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


def render(name, variables):
    expression = "jsonencode(templatefile(%s, %s))\n" % (
        json.dumps(str(ROOT / "files" / name)), json.dumps(variables)
    )
    # An empty working directory prevents reading the deployment state/backend.
    with tempfile.TemporaryDirectory(prefix="ss-template-test-") as work:
        output = subprocess.run(
            ["terraform", "console", "-no-color"], input=expression,
            text=True, cwd=work, capture_output=True, check=True,
        ).stdout
    return json.loads(json.loads(output))


class ProxyTemplates(unittest.TestCase):
    def test_bootstrap_shell_and_lint(self):
        text = render("init.sh.tftpl", {
            "SS_FILES": ["backend.env", "plugin.env", "tmpsc.net/tmpsc_net.key"],
            "SS_BINARIES": ["shadowsocks2-linux-arm64", "v2ray-plugin_linux_arm64"],
            "CERT_FILE": "/etc/shadowsocks/tls/fullchain.cer",
            "KEY_FILE": "/etc/shadowsocks/tls/private.key",
            "SS_REVISION": "offline-test",
        })
        subprocess.run(["bash", "-n"], input=text, text=True, check=True)
        subprocess.run(["shellcheck", "--shell=bash", "-"], input=text,
                       text=True, check=True)
        self.assertIn('"${FILES[@]}"', text)
        self.assertIn("systemctl start shadowsocks-firewall.service", text)
        self.assertNotIn("choom", text)

    def test_password_is_literal_environment_data(self):
        password = 'spaces "quotes" \\ dollar$ percent% backtick` apostrophe\''
        text = render("backend.env.tftpl", {"PASSWORD": password})
        expected = password.replace("\\", "\\\\").replace('"', '\\"')
        self.assertEqual(text, f'SS_PASSWORD="{expected}"\n')

    def test_plugin_configuration(self):
        text = render("plugin.env.tftpl", {
            "DOMAIN_NAME": "proxy.example.com",
            "CERT_FILE": "/etc/shadowsocks/tls/fullchain.cer",
            "KEY_FILE": "/etc/shadowsocks/tls/private.key",
        })
        self.assertEqual(text.splitlines(), [
            'SS_DOMAIN_NAME="proxy.example.com"',
            'SS_CERT_FILE="/etc/shadowsocks/tls/fullchain.cer"',
            'SS_KEY_FILE="/etc/shadowsocks/tls/private.key"',
        ])


if __name__ == "__main__":
    unittest.main()
