provider "aws" {
  region  = var.aws_region
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
  availability_zone = var.availability_zone

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

resource "aws_security_group" "sg_ssh_proxy_vpn" {
  name        = "sg_ssh_proxy_vpn"
  description = "Allow SSH and Proxy/VPN related ports inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.vpc_tailscale.id

  tags = {
    Name = "sg_ssh_proxy_vpn"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_in_ipv4_only_ssh" {
  security_group_id = aws_security_group.sg_ssh_proxy_vpn.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_in_ipv4_https" {
  security_group_id = aws_security_group.sg_ssh_proxy_vpn.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "allow_in_ipv4_only_shadowsocks_tcp" {
  security_group_id = aws_security_group.sg_ssh_proxy_vpn.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 8488
  ip_protocol       = "tcp"
  to_port           = 8488
}

resource "aws_vpc_security_group_ingress_rule" "allow_in_ipv4_only_shadowsocks_udp" {
  security_group_id = aws_security_group.sg_ssh_proxy_vpn.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 8488
  ip_protocol       = "udp"
  to_port           = 8488
}

resource "aws_vpc_security_group_egress_rule" "allow_eg_ipv4_all" {
  security_group_id = aws_security_group.sg_ssh_proxy_vpn.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_key_pair" "id_aws" {
  key_name   = "id_aws"
  public_key = var.public_key_id_aws
}

# servers

resource "aws_instance" "ec2_server" {
  ami           = var.ami_id_ubuntu  // ubuntu 24.04 LTS arm64 in HK
  instance_type = "t4g.nano"
  associate_public_ip_address = true
  key_name = aws_key_pair.id_aws.id
  vpc_security_group_ids = [aws_security_group.sg_ssh_proxy_vpn.id]
  subnet_id = aws_subnet.subnet_tailscale.id
  user_data = var.user_data

  iam_instance_profile = aws_iam_instance_profile.ec2_server.name

  tags = {
    Name = var.instance_name
  }
}

# IAM role

resource "aws_iam_policy" "ec2_permission_boundary" {
  name   = "ec2_permission_boundary"
  policy = <<EOF
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect":"Allow",
      "Action":["s3:Get*","s3:List*"],
      "Resource":[
        "${var.s3_bucket_arn}",
        "${var.s3_bucket_arn}/*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role" "ec2_server" {
  permissions_boundary = aws_iam_policy.ec2_permission_boundary.arn
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ec2_server_s3_policy" {
  role       = aws_iam_role.ec2_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ec2_server" {
  name = "ec2_server_instance_profile"
  role = aws_iam_role.ec2_server.name
}
