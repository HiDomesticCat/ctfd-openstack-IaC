# chell/main.tf
# ─────────────────────────────────────────────────────────────
# k3s 叢集基礎設施（Layer 3，可選）：Kubernetes Pod challenge 後端
#
# 職責：
#   1. SSH Keypair：k3s 節點管理用 SSH 公鑰
#   2. 內部網路（192.168.200.0/24）：k3s 叢集節點所在的私有子網路
#      master 固定 IP 192.168.200.10（worker cloud-init join 時需要）
#   3. Security Group：
#      - 叢集內部互通（all TCP/UDP, remote_group_id）
#      - SSH/kubectl API 6443（限 ssh_allowed_cidr）
#      - NodePort 30000-32767（玩家 challenge 連線，0.0.0.0/0）
#   4. k3s 模組：master + N worker VM，各自有 Floating IP
#      cloud-init 自動安裝 k3s server/agent，產生外部 kubeconfig
#   5. Ansible 自動化（local_file）：
#      - ansible/inventory/k3s_hosts.ini         ← master + worker IP
#      - ansible/group_vars/all/k3s_ids.yml      ← worker floating IPs
#
# 部署順序：
#   1. cd ../platform && tofu apply   （取得 external_network_id, image_id）
#   2. cd ../ctfd    && tofu apply   （取得 ctfd floating_ip）
#   3. cd .          && tofu apply   （本層：k3s 叢集）
#   4. ansible-playbook site.yml ...  （應用程式設定）
#
# ⚠️  安全注意事項：
#   - k3s_token 會出現在 cloud-init 日誌（/var/log/k3s-init.log）
#     建議賽事結束後輪換 token 或清除日誌
#   - ssh_allowed_cidr 預設 0.0.0.0/0，建議限制為管理機 IP
#   - k3s API 6443 與 ssh_allowed_cidr 相同 CIDR，確認限制正確
# ─────────────────────────────────────────────────────────────

# ── SSH Keypair ────────────────────────────────────────────
resource "openstack_compute_keypair_v2" "chell" {
  name       = var.keypair_name
  public_key = file(var.public_key_path)
}

# ── k3s 內部網路 ───────────────────────────────────────────
module "network" {
  source = "./modules/network"

  # 明確指定 provider，避免 hashicorp/openstack 與 terraform-provider-openstack/openstack 衝突
  providers = {
    openstack = openstack
  }

  network_name        = "chell-network"
  subnet_name         = "chell-subnet"
  subnet_cidr         = var.k3s_subnet_cidr
  master_fixed_ip     = var.master_fixed_ip
  dns_nameservers     = var.dns_nameservers
  router_name         = "chell-router"
  external_network_id = var.external_network_id
}

# ── Security Group ─────────────────────────────────────────
module "secgroup" {
  source = "./modules/secgroup"

  providers = {
    openstack = openstack
  }

  secgroup_name    = "chell-sg"
  ssh_allowed_cidr = var.ssh_allowed_cidr
}

# ── k3s Cluster（master + workers）────────────────────────
module "k3s" {
  source = "./modules/k3s"

  providers = {
    openstack = openstack
  }

  master_name      = "chell-master"
  worker_name      = "chell-worker"
  image_id         = var.image_id
  master_flavor    = var.master_flavor
  worker_flavor    = var.worker_flavor
  worker_count     = var.worker_count
  keypair_name     = openstack_compute_keypair_v2.chell.name
  secgroup_id      = module.secgroup.secgroup_id
  network_id       = module.network.network_id
  subnet_id        = module.network.subnet_id
  master_fixed_ip  = var.master_fixed_ip
  floating_ip_pool = var.floating_ip_pool
  k3s_token        = var.k3s_token
  k3s_version      = var.k3s_version
  timezone         = var.timezone

  depends_on = [module.network, module.secgroup]
}

# ── 自動產生 Ansible k3s_ids（worker IPs 等因重新 apply 可能改變的值）──
resource "local_file" "k3s_ids" {
  content = templatefile("${path.module}/templates/k3s_ids.tpl", {
    worker_ips = module.k3s.worker_floating_ips
  })
  filename        = "${path.module}/../ansible/group_vars/all/k3s_ids.yml"
  file_permission = "0644"
}

# ── 自動產生 Ansible inventory（k3s 節點）─────────────────
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    master_ip       = module.k3s.master_floating_ip
    worker_ips      = module.k3s.worker_floating_ips
    ssh_private_key = trimsuffix(var.public_key_path, ".pub")
  })
  filename        = "${path.module}/../ansible/inventory/k3s_hosts.ini"
  file_permission = "0644"
}
