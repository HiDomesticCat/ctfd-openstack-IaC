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

output "challenge_net_ip" {
  description = "CTFd VM 在 challenge-net (192.168.78.0/24) 上的固定 IP。Phase 3 α-exposure 用：cm-proxy Caddy 綁在這個 IP 上提供 chall-manager + registry 給 gamma4 VM。challenge_net_id 未設時為空字串。"
  value       = var.challenge_net_id != "" ? local.challenge_net_fip_ip : ""
}
