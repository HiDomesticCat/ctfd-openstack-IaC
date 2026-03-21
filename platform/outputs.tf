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
