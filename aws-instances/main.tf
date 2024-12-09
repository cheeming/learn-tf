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
  region  = "ap-east-1"
}

locals {
  instance_name = "awshk1"
}

# networking

resource "aws_vpc" "vpc_tailscale" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "vpc_tailscale"
  }
}

resource "aws_subnet" "subnet_tailscale" {
  vpc_id     = aws_vpc.vpc_tailscale.id
  cidr_block = "10.0.0.0/24"

  tags = {
    Name = "subnet_tailscale"
  }
}

resource "aws_internet_gateway" "gw_tailscale" {
  vpc_id = aws_vpc.vpc_tailscale.id

  tags = {
    Name = "gw_tailscale"
  }
}

resource "aws_route_table" "rt_tailscale" {
  vpc_id = aws_vpc.vpc_tailscale.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw_tailscale.id
  }

  tags = {
    Name = "rt_tailscale"
  }
}

resource "aws_route_table_association" "rta_subnet_tailscale" {
  subnet_id      = aws_subnet.subnet_tailscale.id
  route_table_id = aws_route_table.rt_tailscale.id
}


# security

resource "aws_security_group" "sg_only_ssh" {
  name        = "sg_only_ssh"
  description = "Allow SSH inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.vpc_tailscale.id

  tags = {
    Name = "sg_only_ssh"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_in_ipv4_only_ssh" {
  security_group_id = aws_security_group.sg_only_ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_eg_ipv4_all" {
  security_group_id = aws_security_group.sg_only_ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_key_pair" "id_aws" {
  key_name   = "id_aws"
  public_key = var.public_key_id_aws
}

# servers

resource "aws_instance" "ec2_server" {
  ami           = "ami-096a8f4ba68bb4fdf"  // ubuntu 24.04 LTS arm64 in HK
  instance_type = "t4g.nano"
  associate_public_ip_address = true
  key_name = aws_key_pair.id_aws.id
  vpc_security_group_ids = [aws_security_group.sg_only_ssh.id]
  subnet_id = aws_subnet.subnet_tailscale.id

  tags = {
    Name = local.instance_name
  }
}
