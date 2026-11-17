Overview
========
This is Terraform module to help you setup a tailscale server in a specific
region.

The instance does not use an EC2 SSH key pair. Its security group allows only
TCP 443 inbound from the optional `ss_allowed_ipv4_cidrs` input (a nonempty
`set(string)` of IPv4 CIDRs, excluding `/0`) and all IPv4 outbound traffic.
There is one ingress rule per allowed CIDR. The defaults in this module's
`variables.tf` are `112.114.246.0/23`, `60.160.102.0/23`, and `106.61.170.0/23`.
All regions inherit this home/mobile allowlist unless explicitly overridden in
their module blocks. Apply a full plan when changing the
allowlist; targeting only the instance does not reconcile standalone rules.
The root module's bootstrap removes the SSH server and SSM agent.

IMDSv2 tokens are required, with a response hop limit of 1. The endpoint remains
enabled for bootstrap's instance-role credentials. These settings do not stop
an arbitrary TCP proxy from accessing IMDS; the root bootstrap installs separate
per-service host-firewall rules for that purpose.

Changes to `user_data` replace the instance (`user_data_replace_on_change`).
Review replacement plans before applying bootstrap updates.
