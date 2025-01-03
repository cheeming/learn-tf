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

module "tailscale_server_hongkong" {
  source = "./modules/tailscale-exit-node"

  aws_region        = "ap-east-1"
  public_key_id_aws = var.public_key_id_aws
  instance_name = "awshk1"
  ami_id_ubuntu = "ami-096a8f4ba68bb4fdf"
}
