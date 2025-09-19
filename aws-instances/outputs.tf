output "jp_instance_id" {
  description = "ID of the EC2 instance"
  value       = module.shadowsock_tokyo.instance_id
}

output "jp_instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.shadowsock_tokyo.instance_public_ip
}

output "sg_instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.shadowsock_sg.instance_public_ip
}
