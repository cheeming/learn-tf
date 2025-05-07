output "hk_instance_id" {
  description = "ID of the EC2 instance"
  value       = module.tailscale_server_hongkong.instance_id
}

output "hk_instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.tailscale_server_hongkong.instance_public_ip
}

output "jp_instance_id" {
  description = "ID of the EC2 instance"
  value       = module.tailscale_server_tokyo.instance_id
}

output "jp_instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.tailscale_server_tokyo.instance_public_ip
}

