provider "aws" {
  region  = "us-east-1"
}

module "tailscale_server_malaysia" {
  source = "./modules/tailscale-exit-node"

  aws_region        = "ap-southeast-5"
  public_key_id_aws = var.public_key_id_aws
  instance_name = "awsmy1"
  ami_id_ubuntu = "ami-042b35500928461d5"
}
