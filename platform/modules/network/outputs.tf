output "network_id" {
  description = "外部網路 ID，Router 設定 external gateway 需要用這個"
  value       = openstack_networking_network_v2.external.id
}

output "network_name" {
  description = "外部網路名稱，申請 Floating IP 時需要"
  value       = openstack_networking_network_v2.external.name
}

output "subnet_id" {
  description = "外部子網路 ID"
  value       = openstack_networking_subnet_v2.external.id
}

output "gateway_ip" {
  description = "外部網路 Gateway IP"
  value       = openstack_networking_subnet_v2.external.gateway_ip
}