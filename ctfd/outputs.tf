# ctfd/outputs.tf

output "floating_ip" {
  description = "CTFd 對外 Floating IP（use_floating_ip=false 時為 null）"
  value       = module.instance.floating_ip
}

output "ctfd_url" {
  description = "CTFd 存取網址（HTTP）"
  value       = "http://${coalesce(module.instance.floating_ip, module.instance.internal_ip)}:${var.ctfd_port}"
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh ubuntu@${coalesce(module.instance.floating_ip, module.instance.internal_ip)}"
}

output "internal_ip" {
  description = "VM 內部 IP"
  value       = module.instance.internal_ip
}

output "network_id" {
  description = "CTFd 網路 ID（自建或 shared）"
  value       = local.network_id
}

output "challenge_secgroup_ids" {
  description = "預建的 Challenge Security Group IDs（供 CTFd additional security_group_id 使用）"
  value       = module.challenge_secgroups.ids
}
