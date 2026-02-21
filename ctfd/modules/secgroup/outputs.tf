# ctfd-openstack/modules/secgroup/outputs.tf

output "secgroup_id" {
  description = "Security Group ID"
  value       = openstack_networking_secgroup_v2.this.id
}

output "secgroup_name" {
  description = "Security Group 名稱，instance 模組建立 VM 時需要"
  value       = openstack_networking_secgroup_v2.this.name
}
