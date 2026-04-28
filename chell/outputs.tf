# chell/outputs.tf

output "master_floating_ip" {
  description = "k3s master 外部 IP（kubectl 管理用）"
  value       = module.k3s.master_floating_ip
}

output "worker_floating_ips" {
  description = "k3s worker 外部 IP 清單（管理/備援用；challenge 連線優先使用 worker_challenge_net_ips）"
  value       = module.k3s.worker_floating_ips
}

output "worker_challenge_net_ips" {
  description = "k3s worker 在 challenge-net 上的 IP 清單（Caldera/玩家 challenge NodePort 連線用）"
  value       = module.k3s.worker_challenge_net_ips
}

output "k3s_api_url" {
  description = "k3s API Server URL（設定 KUBECONFIG 後使用 kubectl）"
  value       = "https://${module.k3s.master_floating_ip}:6443"
}

output "ssh_master_command" {
  description = "SSH 登入 master 節點"
  value       = "ssh -i ${trimsuffix(var.public_key_path, ".pub")} ubuntu@${module.k3s.master_floating_ip}"
}

output "kubeconfig_fetch_command" {
  description = "從 master 取得 kubeconfig（已替換為外部 IP）"
  value       = "ssh ubuntu@${module.k3s.master_floating_ip} 'cat /home/ubuntu/.kube/config'"
}

output "k3s_worker_ips_csv" {
  description = "worker challenge-net IP 逗號分隔（chall-manager k8s-pod connection_info 使用）"
  value = join(",", (
    length(module.k3s.worker_challenge_net_ips) > 0
    ? module.k3s.worker_challenge_net_ips
    : module.k3s.worker_floating_ips
  ))
}

output "next_steps" {
  description = "下一步操作指引"
  value       = <<-EOT
    ✅ k3s 叢集已建立！接下來：

    1. chall-manager 會透過 ansible/group_vars/all/k3s_ids.yml 使用 worker challenge-net IP：
       k3s_worker_ips: [${join(", ", [for ip in(length(module.k3s.worker_challenge_net_ips) > 0 ? module.k3s.worker_challenge_net_ips : module.k3s.worker_floating_ips) : "\"${ip}\""])}]

    2. 執行 Ansible 配置叢集：
       ansible-playbook site.yml \
         -i ansible/inventory/hosts.ini \
         -i ansible/inventory/k3s_hosts.ini \
         --ask-vault-pass

    3. 驗證叢集狀態：
       ssh ubuntu@${module.k3s.master_floating_ip} 'kubectl get nodes -o wide'
  EOT
}
