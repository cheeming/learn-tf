provider "aws" {
  region  = "us-east-1"
}

module "tailscale_server_tokyo" {
  source = "./modules/tailscale-exit-node"

  aws_region        = "ap-northeast-1"
  public_key_id_aws = var.public_key_id_aws
  instance_name = "awstokyo1"
  ami_id_ubuntu = "ami-0329c152b4ffaa305"
  availability_zone = "ap-northeast-1b"
}
