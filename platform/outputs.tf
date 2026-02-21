# platform/outputs.tf

output "external_network_id" {
  description = "外部網路 ID，ctfd 層建立 Router 時需要"
  value       = module.external_network.network_id
}

output "external_network_name" {
  description = "外部網路名稱，ctfd 層申請 Floating IP 時需要"
  value       = module.external_network.network_name
}

output "image_ids" {
  description = "所有 image 的 ID，ctfd 層用來建立 VM"
  value       = module.images.image_ids
}

output "flavor_ids" {
  description = "所有 flavor 的 ID，ctfd 層建立 VM 時需要"
  value       = module.flavors.flavor_ids
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