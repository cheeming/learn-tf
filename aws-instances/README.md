Overview
========
Terraform config to help manage my Tailscale servers

Pre-requisite
-------------
 - terraform v1.10.2

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

FAQ
---
1. Where to find AMI IDs?
  - Use this link https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#AMICatalog: and switch to another location
  - Look under Quick Start AMI's first, look for Ubuntu 24.04 LTS 64-bit Arm
  - Or run this command: `./scripts/get_ami.sh REGION`

TODOs
-----
 - Refactor Terraform code so that we can have more than 1 server per region.
