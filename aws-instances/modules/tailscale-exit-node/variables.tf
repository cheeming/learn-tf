variable "ss_allowed_ipv4_cidrs" {
  description = "Public IPv4 source CIDRs permitted to reach Shadowsocks TCP 443"
  type        = set(string)
  nullable    = false
  default = [
    "112.114.246.0/23",
    "60.160.102.0/23",
    "106.61.170.0/23",
  ]

  validation {
    condition = length(var.ss_allowed_ipv4_cidrs) > 0 && alltrue([
      for cidr in var.ss_allowed_ipv4_cidrs :
      can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) > 0, false)
    ])
    error_message = "Provide a nonempty set of valid IPv4 CIDRs; unrestricted /0 access is not permitted."
  }
}

variable "aws_region" {
  description = "The AWS region"
  type        = string
}

variable "instance_name" {
  description = "The server instance name"
  type        = string
}

variable "ami_id_ubuntu" {
  description = "The AMI for the server, preferably Ubuntu arm64 LTS"
  type        = string
}

variable "availability_zone" {
  description = "(Optional) Specify a specific AZ because some instance types are only available in specific AZs"
  type        = string
  default     = null
}

variable "user_data" {
  description = "(Optional) Script to be executed when the instance starts"
  type        = string
  default     = null
}

variable "s3_bucket_arn" {
  description = "S3 bucket to store scripts, binaries and etc"
  type        = string
  default     = ""
}
