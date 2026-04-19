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

# ── Phase 3 α-exposure outputs ───────────────────────────────

output "challenge_net_ip" {
  description = "CTFd VM 在 challenge-net 上的固定 IP（expose_cm_proxy_to_challenge_net=true 時有值）。gamma4 VM 把 chall_manager_url / registry_url 指到這個 IP:<port>。"
  value       = module.instance.challenge_net_ip
}

output "gamma4_env_hints" {
  description = "貼進 /data/gamma4-lab-infra/terraform.tfvars 的 URL（expose_cm_proxy_to_challenge_net=true 時有值，否則提示未啟用）。"
  value = module.instance.challenge_net_ip != "" ? {
    chall_manager_url = "http://${module.instance.challenge_net_ip}:${var.cm_proxy_chall_manager_port}"
    registry_url      = "${module.instance.challenge_net_ip}:${var.cm_proxy_registry_port}"
    note              = "Credentials come from ansible-vault (vault_cm_proxy_basic_auth_user / vault_cm_proxy_basic_auth_password)."
  } : {
    chall_manager_url = ""
    registry_url      = ""
    note              = "expose_cm_proxy_to_challenge_net is false. Enable it + re-apply + run ansible site.yml to populate."
  }
}
