# ctfd-openstack/modules/keypair/outputs.tf

output "keypair_name" {
  description = "已建立的 Keypair 名稱，給 instance 模組使用"
  value       = openstack_compute_keypair_v2.this.name
}
