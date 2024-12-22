Overview
========
This is Terraform module to help you setup a tailscale server in a specific
region.

FAQ
---
1. Where to find AMI IDs?
  - Use this link https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#AMICatalog: and switch to another location
  - Look under Community AMIs, select Ubuntu, 64-bit Arm, search for "ubuntu 24.04 LTS"
  - And choose one that has the latest date, and ensure it is a "verified provider"
