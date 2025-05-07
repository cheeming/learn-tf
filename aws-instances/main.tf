provider "aws" {
  region  = "us-east-1"
}

/*
module "tailscale_server_malaysia" {
  source = "./modules/tailscale-exit-node"

  aws_region        = "ap-southeast-5"
  public_key_id_aws = var.public_key_id_aws
  instance_name = "awsmy1"
  ami_id_ubuntu = "ami-042b35500928461d5"
}
*/

module "tailscale_server_hongkong" {
  source = "./modules/tailscale-exit-node"

  aws_region        = "ap-east-1"
  public_key_id_aws = var.public_key_id_aws
  instance_name = "awshk1"
  ami_id_ubuntu = "ami-096a8f4ba68bb4fdf"
}

/*
module "tailscale_server_seoul" {
  source = "./modules/tailscale-exit-node"

  aws_region        = "ap-northeast-2"
  public_key_id_aws = var.public_key_id_aws
  instance_name = "awsseoul1"
  ami_id_ubuntu = "ami-05a03364f8ca05a04"
}
*/

module "tailscale_server_tokyo" {
  source = "./modules/tailscale-exit-node"

  aws_region        = "ap-northeast-1"
  public_key_id_aws = var.public_key_id_aws
  instance_name = "awstokyo1"
  ami_id_ubuntu = "ami-0329c152b4ffaa305"
  availability_zone = "ap-northeast-1b"
}

/*
module "tailscale_server_singapore" {
  source = "./modules/tailscale-exit-node"

  aws_region        = "ap-southeast-1"
  public_key_id_aws = var.public_key_id_aws
  instance_name = "awssg1"
  ami_id_ubuntu = "ami-0c2e5288624699cd8"
}
*/
