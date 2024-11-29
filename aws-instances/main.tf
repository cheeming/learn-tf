terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "ap-southeast-1"
}

resource "aws_instance" "awssg2" {
  ami           = "ami-09b5c6390225b29cc"  // ubuntu 24.04 LTS arm64
  instance_type = "t4g.nano"
  associate_public_ip_address = true
  key_name = "id_aws"
  vpc_security_group_ids = ["sg-06517d58201cf854e"]
  subnet_id = "subnet-2d9afc44"

  tags = {
    Name = "awssg2"
  }
}
