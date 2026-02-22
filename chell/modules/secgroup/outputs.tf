# chell/modules/secgroup/outputs.tf

output "secgroup_id" {
  description = "k3s Security Group ID（供 port 資源引用）"
  value       = openstack_networking_secgroup_v2.this.id
}

output "secgroup_name" {
  description = "k3s Security Group 名稱"
  value       = openstack_networking_secgroup_v2.this.name
}
