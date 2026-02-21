# ctfd-openstack/outputs.tf

output "floating_ip" {
  description = "CTFd 對外 Floating IP"
  value       = module.instance.floating_ip
}

output "ctfd_url" {
  description = "CTFd 存取網址（HTTP）"
  value       = "http://${module.instance.floating_ip}:${var.ctfd_port}"
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh ubuntu@${module.instance.floating_ip}"
}

output "internal_ip" {
  description = "VM 內部 IP"
  value       = module.instance.internal_ip
}

output "network_id" {
  description = "CTFd 內部網路 ID"
  value       = module.network.network_id
}
