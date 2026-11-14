#!/usr/bin/env python3
"""Read-only checks on a bootstrapped Linux host; run as root after deployment.

Opens test connections under the service accounts. Never requests metadata or
credentials, changes firewall rules, or starts/stops services.
"""
import json
import os
import shutil
import subprocess
import sys


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs)


def rejects(chain):
    rules = json.loads(run("nft", "-j", "list", "chain", "inet", "shadowsocks", chain).stdout)
    return sum(
        expression["counter"]["packets"]
        for item in rules["nftables"]
        for expression in item.get("rule", {}).get("expr", [])
        if "counter" in expression
    )


def blocked(user, chain, host, port):
    before = rejects(chain)
    code = """
import socket, sys
try:
    connection = socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=2)
except OSError:
    sys.exit(0)
connection.close()
sys.exit(1)
"""
    run("runuser", "-u", user, "--", "python3", "-c", code, host, str(port), timeout=5)
    if rejects(chain) <= before:
        raise RuntimeError(f"No firewall rejection recorded for {user} -> {host}:{port}")
    print(f"PASS: firewall rejected {user} -> {host}:{port}")


def main():
    if sys.platform != "linux" or os.geteuid() != 0:
        raise RuntimeError("Run as root on a Linux host with the installed proxy setup")
    for tool in ("nft", "systemctl", "runuser", "python3", "curl", "getent", "ip"):
        if not shutil.which(tool):
            raise RuntimeError(f"Required tool missing: {tool}")
    for unit in ("shadowsocks-firewall", "shadowsocks-backend", "shadowsocks-plugin"):
        run("systemctl", "is-active", "--quiet", unit)
    run("nft", "--check", "-f", "/etc/shadowsocks/egress.nft")
    for host in ("169.254.169.254", "10.0.0.1", "100.100.100.100", "127.0.0.1", "::1"):
        blocked("ss-backend", "backend", host, 80)
    blocked("ss-plugin", "plugin", "169.254.169.254", 80)
    blocked("ss-plugin", "plugin", "1.1.1.1", 443)
    route = subprocess.run(["ip", "-6", "route", "get", "fd00:ec2::254"], capture_output=True)
    if route.returncode == 0:
        blocked("ss-backend", "backend", "fd00:ec2::254", 80)
    else:
        print("SKIP: IPv6 IMDS connection check (host has no route); IPv6 loopback was checked")
    run("runuser", "-u", "ss-backend", "--", "getent", "ahosts", "example.com", timeout=15)
    run("runuser", "-u", "ss-backend", "--", "curl", "--noproxy", "*",
        "--fail", "--silent", "--show-error", "--max-time", "20", "https://example.com/",
        timeout=25)
    print("PASS: backend DNS and public HTTPS access")
    print("Also verify a full client TLS/WebSocket/SOCKS request and repeat after reboot.")


if __name__ == "__main__":
    main()
