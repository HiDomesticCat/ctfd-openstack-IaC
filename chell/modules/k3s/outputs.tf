# chell/modules/k3s/outputs.tf

output "master_floating_ip" {
  description = "k3s master 外部 IP（kubectl 管理用）"
  value       = openstack_networking_floatingip_v2.master.address
}

output "master_internal_ip" {
  description = "k3s master 內部固定 IP"
  value       = var.master_fixed_ip
}

output "worker_floating_ips" {
  description = "k3s worker 外部 IP 清單（玩家 challenge NodePort 連線用）"
  value       = [for fip in openstack_networking_floatingip_v2.workers : fip.address]
}

output "worker_instance_ids" {
  description = "k3s worker 節點 Instance ID 清單"
  value       = [for w in openstack_compute_instance_v2.workers : w.id]
}
