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

TODOs
-----
 - Refactor Terraform code so that we can have more than 1 server per region.
