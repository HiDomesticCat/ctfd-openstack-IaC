# chell/modules/k3s/outputs.tf

output "master_floating_ip" {
  description = "k3s master 外部 IP（有 FIP 時為 FIP，無 FIP 時為內網 IP）"
  value       = local.master_external_ip
}

output "master_internal_ip" {
  description = "k3s master 內部 IP"
  value       = local.master_internal_ip
}

output "worker_floating_ips" {
  description = "k3s worker 外部 IP 清單（有 FIP 時為 FIP，無 FIP 時為內網 IP）"
  value       = var.use_fip ? [for fip in openstack_networking_floatingip_v2.workers : fip.address] : [for p in openstack_networking_port_v2.workers : p.all_fixed_ips[0]]
}

output "worker_challenge_net_ips" {
  description = "k3s worker 在 challenge-net 上的 IP 清單（Caldera/玩家直接打 NodePort 用）"
  value       = var.challenge_network_id != "" ? [for p in openstack_networking_port_v2.workers_challenge_net : p.all_fixed_ips[0]] : []
}

output "worker_instance_ids" {
  description = "k3s worker 節點 Instance ID 清單"
  value       = [for w in openstack_compute_instance_v2.workers : w.id]
}
