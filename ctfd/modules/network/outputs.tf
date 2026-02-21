# ctfd-openstack/modules/network/outputs.tf

output "network_id" {
  description = "內部網路 ID，instance 模組建立 VM 時需要"
  value       = openstack_networking_network_v2.this.id
}

output "network_name" {
  description = "內部網路名稱"
  value       = openstack_networking_network_v2.this.name
}

output "subnet_id" {
  description = "內部子網路 ID"
  value       = openstack_networking_subnet_v2.this.id
}

output "router_id" {
  description = "Router ID"
  value       = openstack_networking_router_v2.this.id
}

output "router_interface_id" {
  description = "Router Interface ID（instance 模組用來建立依賴關係）"
  value       = openstack_networking_router_interface_v2.this.id
}
