Overview
========
This is Terraform module to help you setup a tailscale server in a specific
region.

The instance does not use an EC2 SSH key pair. Its security group allows only
TCP 443 inbound and all IPv4 outbound traffic. The root module's bootstrap
removes the SSH server and SSM agent.

IMDSv2 tokens are required, with a response hop limit of 1. The endpoint remains
enabled for bootstrap's instance-role credentials. These settings do not stop
an arbitrary TCP proxy from accessing IMDS; the root bootstrap installs separate
per-service host-firewall rules for that purpose.

Changes to `user_data` replace the instance (`user_data_replace_on_change`).
Review replacement plans before applying bootstrap updates.
