# platform/outputs.tf

output "external_network_id" {
  description = "外部網路 ID（自建或引用），上層建立 Router / FIP 時引用"
  value       = local.external_network_id
}

output "external_network_name" {
  description = "外部網路名稱，上層申請 Floating IP 時引用"
  value       = local.external_network_name
}

output "image_ids" {
  description = "所有 image 的 ID（key=image key, value=UUID）"
  value       = module.images.image_ids
}

output "ctfd_project_id" {
  description = "CTFd Project ID"
  value       = module.ctfd_project.project_id
}

output "ctfd_credentials" {
  description = "CTFd 部署帳號憑證，給 ctfd 層使用"
  sensitive   = true
  value       = module.ctfd_project.credentials
}

output "ctfd_deployer_password" {
  description = "CTFd 部署帳號密碼。Apply 後 `tofu output -raw ctfd_deployer_password` 取出，貼進 ~/.config/openstack/clouds.yaml 的 ctfd cloud entry password 欄位。手動設 var.ctfd_deployer_password 時也可從這拿值，方便驗證。"
  sensitive   = true
  value       = local.ctfd_deployer_password
}

# ── 玩家↔題目共享網段 ──────────────────────────────────────

output "challenge_network_id" {
  description = "玩家↔題目共享網段 ID（admin 創、RBAC share 給 ctfd-deployer）"
  value       = module.challenge_network.network_id
}

output "challenge_network_name" {
  description = "玩家↔題目共享網段名稱（chell, ctfd, gamma4-IaC 用 data source 引用）"
  value       = module.challenge_network.network_name
}

output "challenge_network_cidr" {
  description = "玩家↔題目 CIDR（給 secgroup rule source 用，例如 Caldera agent ingress）"
  value       = module.challenge_network.cidr
}
