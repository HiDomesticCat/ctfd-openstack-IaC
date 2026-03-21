# ctfd/main.tf
# ─────────────────────────────────────────────────────────────
# CTFd 應用層（Layer 2）：CTFd 競賽平台的 VM 與網路基礎設施
#
# 職責：
#   1. SSH Keypair：管理用 SSH 公鑰上傳到 OpenStack
#   2. 內部網路：CTFd VM 所在的網路
#      → use_shared_network = false → 自建 network + router（lab15）
#      → use_shared_network = true  → 引用現有 shared network（lab50）
#   3. Security Group：開放 SSH、HTTP、HTTPS、CTFd port（8000）
#   4. Challenge Security Groups：預建的 SG（allow-all / allow-ssh / allow-web）供出題者選用
#   5. VM + Floating IP：CTFd server 本體，具備外部可存取 IP
#   6. Ansible 自動化（local_file）：
#      - ansible/inventory/hosts.ini       ← CTFd VM IP + SSH key 路徑
#      - ansible/group_vars/all/challenge_ids.yml ← network_id, image_id, SG IDs
#
# 前置：platform 層必須已 apply（需要 external_network_id, image_id）
# 執行帳號：ctfd-deployer（clouds.yaml 的 ctfd cloud entry）
#
# ⚠️  ssh_allowed_cidr 預設為 0.0.0.0/0，建議限制為管理機 IP
# ─────────────────────────────────────────────────────────────

# ── SSH Keypair ────────────────────────────────────────────
module "keypair" {
  source = "./modules/keypair"

  keypair_name    = var.keypair_name
  public_key_path = var.public_key_path

  providers = { openstack = openstack }
}

# ── 內部網路：自建 or 引用 shared ────────────────────────────

module "network" {
  count  = var.use_shared_network ? 0 : 1
  source = "./modules/network"

  network_name        = "ctfd-network"
  subnet_name         = "ctfd-subnet"
  subnet_cidr         = var.internal_subnet_cidr
  dns_nameservers     = var.dns_nameservers
  router_name         = "ctfd-router"
  external_network_id = var.external_network_id

  providers = { openstack = openstack }
}

data "openstack_networking_network_v2" "shared" {
  count = var.use_shared_network ? 1 : 0
  name  = var.shared_network_name
}

locals {
  network_id = var.use_shared_network ? data.openstack_networking_network_v2.shared[0].id : module.network[0].network_id
}

# ── Security Group ─────────────────────────────────────────
module "secgroup" {
  source = "./modules/secgroup"

  secgroup_name        = "ctfd-sg"
  secgroup_description = "CTFd Server Security Group"
  ssh_allowed_cidr     = var.ssh_allowed_cidr
  ctfd_port            = var.ctfd_port

  providers = { openstack = openstack }
}

# ── Challenge Security Groups（預建，供出題者選用）─────────
module "challenge_secgroups" {
  source = "./modules/challenge_secgroups"

  name_prefix = "ctf"

  providers = { openstack = openstack }
}

# ── VM + Floating IP ───────────────────────────────────────
module "instance" {
  source = "./modules/instance"

  instance_name    = var.instance_name
  image_id         = var.image_id
  flavor_name      = var.flavor_name
  keypair_name     = module.keypair.keypair_name
  secgroup_name    = module.secgroup.secgroup_name
  network_id       = local.network_id
  floating_ip_pool = var.floating_ip_pool

  # Cloud-init 設定
  timezone   = var.timezone
  deploy_dir = var.deploy_dir

  # 自建模式需等 network + router 完全就緒；shared 模式不需要
  depends_on = [module.network]

  providers = { openstack = openstack }
}

# 自動產生 Ansible challenge_ids（network_id、image_id 等因重新 apply 可能改變的值）
# ⚠️ 靜態設定（flag、flavor、port）仍在 group_vars/all/challenge.yml 手動維護
resource "local_file" "challenge_ids" {
  content = templatefile("${path.module}/templates/challenge_ids.tpl", {
    network_id            = local.network_id
    image_id              = var.image_id
    challenge_secgroup_ids = module.challenge_secgroups.ids
  })
  filename        = "${path.module}/../ansible/group_vars/all/challenge_ids.yml"
  file_permission = "0644"
}

# 自動產生 Ansible inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    ctfd_ip         = module.instance.floating_ip
    ssh_private_key = trimsuffix(var.public_key_path, ".pub")
  })
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"
}
