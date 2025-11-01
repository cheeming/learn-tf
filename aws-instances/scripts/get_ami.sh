#!/bin/bash

REGION=${1}

# get official AMI from Canonical for Ubuntu
aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text --region ${REGION}
