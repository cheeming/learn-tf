provider "aws" {
  region  = "us-east-1"
}

# S3 bucket to hosts scripts, binaries and etc
resource "aws_s3_bucket" "vpn_configs" {
  bucket = "cheems-vpn-configs"
}

locals {
  ss_binaries = [
    "shadowsocks2-linux-arm64",
    "v2ray-plugin_linux_arm64",
    "update-ddns",
  ]
  ss_files_s3 = concat(local.ss_binaries, [
    "limits.conf",
    "sysctl.conf",
    "tmpsc.net/tmpsc_net.cer",
    "tmpsc.net/tmpsc_net.key",
    "noip-duc_3.3.0_arm64.deb",
  ])
}

# Shadowsocks related files
resource "aws_s3_object" "shadowsock_files" {
  for_each = toset(local.ss_files_s3)

  bucket = aws_s3_bucket.vpn_configs.id
  key = each.key
  source = "files/${each.key}"
  etag = filemd5("files/${each.key}")
}

locals {
  ss_start_script_content = templatefile("files/start-ss.tftpl", {
    PASSWORD    = var.ss_password
    DOMAIN_NAME = var.ss_domain_name
    CERT_FILE   = var.ss_cert_file
    KEY_FILE    = var.ss_key_file
  })

  init_script_content = templatefile("files/init.sh.tftpl", {
    SS_FILES    = concat(local.ss_files_s3, ["start-ss", "noip-duc.env"])
    SS_BINARIES = concat(local.ss_binaries, ["start-ss"])
  })

  noip_env_content = templatefile("files/noip-duc.env.tftpl", {
    USERNAME    = var.noip_username
    PASSWORD    = var.noip_password
  })
}

resource "aws_s3_object" "ss_start_script" {
  bucket = aws_s3_bucket.vpn_configs.id
  key = "start-ss"
  content = local.ss_start_script_content
  etag = md5(local.ss_start_script_content)
}

resource "aws_s3_object" "noip_env" {
  bucket = aws_s3_bucket.vpn_configs.id
  key = "noip-duc.env"
  content = local.noip_env_content
  etag = md5(local.noip_env_content)
}

module "tailscale_server_us" {
  source = "./modules/tailscale-exit-node"

  aws_region        = "us-east-1"
  public_key_id_aws = var.public_key_id_aws
  instance_name     = "awsus1"
  ami_id_ubuntu     = "ami-07041441b708acbd6"
  availability_zone = "us-east-1a"
}

module "shadowsock_tokyo" {
  source = "./modules/tailscale-exit-node"

  aws_region        = "ap-northeast-1"
  public_key_id_aws = var.public_key_id_aws
  instance_name     = "awstokyo1"
  ami_id_ubuntu     = "ami-0cef62348b8426830"

  user_data = local.init_script_content
  s3_bucket_arn = aws_s3_bucket.vpn_configs.arn
}
