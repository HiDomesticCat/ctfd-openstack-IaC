# ctfd-openstack/modules/instance/outputs.tf

output "instance_id" {
  description = "VM ID"
  value       = openstack_compute_instance_v2.this.id
}

output "internal_ip" {
  description = "VM 內部 IP"
  value       = openstack_compute_instance_v2.this.access_ip_v4
}

output "floating_ip" {
  description = "CTFd 對外 Floating IP（use_floating_ip=false 時為 null）"
  value       = var.use_floating_ip ? openstack_networking_floatingip_v2.this[0].address : null
}
