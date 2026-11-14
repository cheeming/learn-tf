Overview
========
Terraform config to help manage my Tailscale servers

Pre-requisite
-------------
 - terraform v1.10.2

Server access and connectivity
------------------------------
Bootstrap purges the SSH server and masks both its service and socket. Instances
have no EC2 SSH key pair or SSH ingress rule, and the SSM agent is removed to
reduce memory usage. TCP 443 is the only permitted inbound port.

The GitLab connectivity check verifies that TCP 443 is reachable and TCP 22 is
inaccessible. To run it manually:
```
./scripts/test_connect_ss.sh <hostname>
```

When deploying the SSH removal, review and apply a full Terraform plan once to
remove existing SSH ingress rules and key-pair resources. The scheduled jobs
target only the EC2 instance and do not reconcile those removed resources.

Internet-only Shadowsocks isolation
-----------------------------------
Bootstrap installs three systemd units:

- `shadowsocks-firewall`: atomically loads a dedicated nftables table before
  either proxy service starts. Stopping this unit deliberately keeps the rules.
- `shadowsocks-backend`: runs as `ss-backend`, listening on `127.0.0.1:8388`.
- `shadowsocks-plugin`: runs standalone as `ss-plugin`, listening on TCP 443 with
  TLS/WebSocket path `/ws`, forwarding to the backend. Only this service receives
  `CAP_NET_BIND_SERVICE`. No Shadowsocks `-plugin` option is used.

The plugin may reply to clients and connect to the backend only. The backend may
reply to the plugin, query Ubuntu's `127.0.0.53:53` resolver, and connect to public
Internet addresses. Private, local, link-local, CGNAT/Tailscale, multicast,
reserved, and documentation ranges are denied. IPv6 permits only `2000::/3`, with
additional conservative exclusions for protocol assignments, documentation and
6to4; NAT64 and other transition ranges outside this allocation are denied.
IPv4-mapped destinations use the IPv4 routing/filter path. Rules apply to the
actual destination IP, including destinations obtained through DNS.

The local DNS exception can also be reached by authenticated proxy users on port
53; it does not allow arbitrary access to other private services. The address
policy is conservative (some globally reachable special-purpose addresses are
also denied), static, and should be reviewed when IANA allocations change.
Only these two accounts are restricted; root bootstrap retains metadata access
for S3 downloads. IMDSv2 is explicitly required but is not the egress control.
Other host firewall tables are preserved; do not flush the global ruleset while
these services run. Rules use connection-tracking reply direction, not a blanket
established-connection exception.

Binaries are installed root-owned under `/usr/local/libexec`. The password is in
root-only `/etc/shadowsocks/backend.env` and is passed by systemd, not on the
command line. The plugin reads its certificate and key under
`/etc/shadowsocks/tls/` (root-owned, plugin-group-readable). `ss_cert_file` and
`ss_key_file` now specify installation paths directly in that directory; remove
old `/home/ubuntu/...` overrides. The source certificate objects remain
`tmpsc.net/tmpsc_net.cer` and `tmpsc.net/tmpsc_net.key` in S3. Passwords must be
nonempty with no line breaks. Environment files are not shell scripts; do not
source them. Secrets remain in Terraform state and restricted S3 objects.

Logs go to the system journal; inspect with
`journalctl -u shadowsocks-backend -u shadowsocks-plugin`.
The legacy root cron launcher and its OOM-kill exemption are removed.
Bootstrap requires systemd-resolved's stub resolver and fails if the expected
resolver is absent. For another image, deliberately adjust both the DNS exception
and bootstrap check. Service startup fails if firewall installation fails.

Offline checks (no AWS requests or deployment):

```sh
terraform fmt -check -recursive
terraform validate
python3 -B -m unittest discover -s scripts/tests -p test_proxy_templates.py -v
```

Linux acceptance checks, to be run separately on a bootstrapped test host:

```sh
sudo python3 scripts/check_proxy_isolation.py
```

This checks active services, nftables validity, per-account rejection counters,
backend DNS and public HTTPS. It only attempts socket connections to metadata;
it never requests metadata or credentials. It does not change the firewall.
Also test full client TLS/WebSocket/SOCKS traffic and repeat after reboot. The
macOS transport test does not validate Linux firewall or systemd behavior.

Future deployment must be explicitly reviewed: the bootstrap references the S3
resources so Terraform orders their updates before instance creation. S3 bucket
and instance regions differ; allow for cross-region S3 propagation if needed.
`user_data_replace_on_change = true` makes bootstrap changes replace instances.
A fingerprint of binaries, units and firewall rules in user data also triggers
replacement when those files change. Password/domain/certificate-content changes
alone still require an explicit replacement or a controlled configuration update
and service restart. Existing instances do not download new assets on reboot.
Review the complete plan, including removal of the old `start-ss` S3 object and
any instance replacements, before any future deployment. No rollout is performed
by these local validation steps.

Terraform
---------
```
TF_STATE_NAME=aws-instances;
terraform init -backend-config="address=https://gitlab.com/api/v4/projects/71332047/terraform/state/$TF_STATE_NAME" -backend-config="lock_address=https://gitlab.com/api/v4/projects/71332047/terraform/state/$TF_STATE_NAME/lock" -backend-config="unlock_address=https://gitlab.com/api/v4/projects/71332047/terraform/state/$TF_STATE_NAME/lock" -backend-config="username=cheeming" -backend-config="password=$GITLAB_ACCESS_TOKEN" -backend-config="lock_method=POST" -backend-config="unlock_method=DELETE" -backend-config="retry_wait_min=5"
```

Summarise Terraform Plan
------------------------
If you want better summaries: https://github.com/dineshba/tf-summarize
```
terraform plan -out=tfplan
tf-summarize tfplan
```

Rotate IAM Access Keys for GitLab
--------------------------------
`scripts/rotate-iam-key.sh` deletes one stale or never-used IAM access key, creates a replacement,
then updates two existing GitLab **project** CI/CD variables. It runs as a
read-only dry-run unless `--apply` is passed. This is separate from Terraform;
credentials are not written to Terraform state.

Requirements:

- Bash, AWS CLI v2 supporting `aws configure export-credentials`, `glab`, `jq`, and GNU `date`.
- AWS credentials with `iam:ListAccessKeys`, `iam:GetAccessKeyLastUsed`, `iam:DeleteAccessKey`, and `iam:CreateAccessKey` for the target user. Dry-run only needs the read operations. The script also calls `sts:GetCallerIdentity`.
- Authenticated `glab` with API access and permission to read/update project variables (normally a Maintainer or Owner with an `api`-scoped token). Use `glab auth login` if needed.
- Existing `env_var` variables named `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, unless overridden. By default, variables are fetched and updated by name without an environment-scope filter. Use `--scope` when a name exists in multiple scopes. Configure appropriate masking and protection beforehand; the script preserves existing settings.

Run from `aws-instances`:

```bash
# Read-only inspection. Project can be a numeric ID or a group/project path.
./scripts/rotate-iam-key.sh --user deploy-user --project group/project

# Delete the selected key first, create its replacement, then update GitLab.
./scripts/rotate-iam-key.sh --user deploy-user --project group/project --apply

# Optional overrides, including self-hosted GitLab and scoped variables.
./scripts/rotate-iam-key.sh \
  --user deploy-user --project 12345 --profile administrator \
  --hostname gitlab.example.com --scope production --days 90 \
  --id-variable DEPLOY_AWS_ACCESS_KEY_ID \
  --secret-variable DEPLOY_AWS_SECRET_ACCESS_KEY
```

Selection and safety:

- Previously used keys must be unused for at least 90 days by default (configurable with `--days`), and creation must also be at least that old. Keys with no recorded last use are eligible regardless of creation date or `--days`.
- Among eligible keys, the longest-unused key is selected, using creation time for never-used keys, regardless of active/inactive status. If none qualifies, the script exits nonzero without changes. Dry-run labels never-used keys explicitly.
- The key authenticating the script is excluded. Use a separate administrator identity for rotation. For temporary role credentials, the script cannot identify or protect an IAM source key that originally obtained the session.
- A stale key currently configured in GitLab **can be deleted**, with a warning. Deletion is irreversible, including if replacement creation fails. Verify the displayed AWS account and GitLab target during dry-run before applying.
- IAM last-used reporting can lag. Inactivity or a missing last-use timestamp is not proof a key has no consumers. A newly created replacement may qualify again until AWS records its first use, so do not rerun rotation just to verify it. Check other users of the key, and pause pipelines and other consumers before applying.
- GitLab's two updates are not atomic. The secret is updated first, then the key ID. Readable values are compared with the replacement; metadata is checked for both variables. Only values are changed; scope, masking, protection, and other metadata are preserved.
- Each update uses `glab api --method PUT --field value=@-`, reading the plain credential from stdin without an added newline. `glab` encodes it as the request's `value` field; credentials are not passed as command-line arguments.
- Hidden variables are supported: GitLab returns `value: null` with `hidden: true`. Their values cannot be compared or checked for concurrent changes. If the key ID is hidden, the script cannot tell whether the selected IAM key is currently configured in GitLab. Null values without `hidden: true` are still rejected.
- The script rechecks variables, the key list, and selected key usage before deletion, but cannot lock AWS or GitLab. Run only one rotation per user/project at a time and prevent concurrent variable edits. Read preflight checks cannot guarantee subsequent writes will be permitted or succeed.
- This handles long-lived IAM credentials only. It does not update `AWS_SESSION_TOKEN`, group/inherited variables, other projects/scopes, or credentials held by already-running jobs.

Failure recovery:

Before deletion, the script allocates a mode-`0600` temporary file in `${TMPDIR:-/tmp}`.
The replacement creation response, including its secret, is written directly there.
The file is removed only after both GitLab values are read back and verified. If
either variable is hidden, successful updates exit zero with a manual-verification
warning and retain the file: API acknowledgments and matching metadata do not prove
the hidden values match. Run a controlled, non-mutating CI check using these variables
(for example, `aws sts get-caller-identity`, checking the expected identity), then
remove the file once satisfied that the new credentials work. Do not rerun rotation
just to verify hidden values.

If creation, an update, or verification fails, the script exits nonzero, reports the
recovery path, and retains any new key. No secret values are printed or passed as
command-line arguments.

If rotation fails after creation, **do not simply rerun rotation**: it will not
resume the interrupted updates. Keep consumers paused, use the recovery response's
`AccessKey.AccessKeyId` and `AccessKey.SecretAccessKey` to finish updating the exact
project variables/scope through a secure channel, verify both, then remove the
recovery file. The status output indicates acknowledged updates, not guaranteed
server state after a network error. If the file is empty or incomplete, inspect
IAM for an orphaned key: AWS cannot return a previously created secret again.
The deleted old key cannot be restored.

Treat the recovery file as a credential. Use a private, durable `TMPDIR` outside
the repository if recovery must survive temporary-directory cleanup or reboot.
Avoid external HTTP/CLI debug logging or session recording while rotating.

If preflight reports `Cannot read existing env_var`, check the preceding diagnostic.
API request failures are reported separately from response validation failures.
Validation identifies invalid JSON, an unexpected response shape, a mismatched
key/scope, an unsupported variable type, or an invalid value (allowing null only
for hidden variables), without printing credentials. Do not enable `set -x` to investigate: shell tracing can
expose the existing GitLab secret even during a dry-run.

Offline checks (no live AWS or GitLab requests):

```bash
bash -n scripts/rotate-iam-key.sh
shellcheck scripts/rotate-iam-key.sh
python3 -B -m unittest discover -s scripts/tests -v
```

FAQ
---
1. Where to find AMI IDs?
  - Use this link https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#AMICatalog: and switch to another location
  - Look under Quick Start AMI's first, look for Ubuntu 24.04 LTS 64-bit Arm
  - Or run this command: `./scripts/get_ami.sh REGION`

TODOs
-----
 - Refactor Terraform code so that we can have more than 1 server per region.
