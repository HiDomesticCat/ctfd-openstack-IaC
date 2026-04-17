output "network_id" {
  description = "Challenge-net 網段 ID"
  value       = openstack_networking_network_v2.challenge_net.id
}

output "network_name" {
  description = "Challenge-net 網段名稱（給其他層 data source 引用）"
  value       = openstack_networking_network_v2.challenge_net.name
}

output "subnet_id" {
  description = "Challenge-net 子網段 ID"
  value       = openstack_networking_subnet_v2.challenge_net.id
}

output "cidr" {
  description = "Challenge-net CIDR（給 secgroup rule source 用，例如 Caldera agent ingress）"
  value       = openstack_networking_subnet_v2.challenge_net.cidr
}
