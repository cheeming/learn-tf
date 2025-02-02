variable "aws_region" {
    description = "The AWS region"
    type        = string
}

variable "public_key_id_aws" {
    description = "The public key for the key pair used to SSH into the server"
    type        = string
    sensitive   = true
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
