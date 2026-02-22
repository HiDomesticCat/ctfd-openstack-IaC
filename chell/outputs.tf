# chell/outputs.tf

output "master_floating_ip" {
  description = "k3s master 外部 IP（kubectl 管理用）"
  value       = module.k3s.master_floating_ip
}

output "worker_floating_ips" {
  description = "k3s worker 外部 IP 清單（玩家 challenge NodePort 連線用）"
  value       = module.k3s.worker_floating_ips
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
  description = "worker IP 逗號分隔（填入 ansible/group_vars/all/challenge.yml 的 k3s_worker_ips）"
  value       = join(",", module.k3s.worker_floating_ips)
}

output "next_steps" {
  description = "下一步操作指引"
  value       = <<-EOT
    ✅ k3s 叢集已建立！接下來：

    1. 複製 worker IP 到 challenge.yml：
       k3s_worker_ips: [${join(", ", [for ip in module.k3s.worker_floating_ips : "\"${ip}\""])}]

    2. 執行 Ansible 配置叢集：
       ansible-playbook site.yml \
         -i ansible/inventory/hosts.ini \
         -i ansible/inventory/k3s_hosts.ini \
         --ask-vault-pass

    3. 驗證叢集狀態：
       ssh ubuntu@${module.k3s.master_floating_ip} 'kubectl get nodes -o wide'
  EOT
}
