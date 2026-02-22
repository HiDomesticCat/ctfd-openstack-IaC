# chell/modules/network/outputs.tf

output "network_id" {
  description = "k3s 內部網路 ID"
  value       = openstack_networking_network_v2.this.id
}

output "subnet_id" {
  description = "k3s 子網路 ID（master port 固定 IP 使用）"
  value       = openstack_networking_subnet_v2.this.id
}

output "network_name" {
  description = "k3s 內部網路名稱"
  value       = openstack_networking_network_v2.this.name
}
