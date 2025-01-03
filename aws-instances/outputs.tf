output "my_instance_id" {
  description = "ID of the EC2 instance"
  value       = module.tailscale_server_malaysia.instance_id
}

output "my_instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.tailscale_server_malaysia.instance_public_ip
}

output "hk_instance_id" {
  description = "ID of the EC2 instance"
  value       = module.tailscale_server_hongkong.instance_id
}

output "hk_instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.tailscale_server_hongkong.instance_public_ip
}
