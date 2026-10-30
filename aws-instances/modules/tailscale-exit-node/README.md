Overview
========
This is Terraform module to help you setup a tailscale server in a specific
region.

The instance does not use an EC2 SSH key pair. Its security group allows only
TCP 443 inbound and all IPv4 outbound traffic. The root module's bootstrap
removes the SSH server and SSM agent.
