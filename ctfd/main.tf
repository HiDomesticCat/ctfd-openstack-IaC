# ctfd-openstack/main.tf

# ── SSH Keypair ────────────────────────────────────────────
module "keypair" {
  source = "./modules/keypair"

  keypair_name    = var.keypair_name
  public_key_path = var.public_key_path
}

# ── 內部網路 ──────────────────────────────────────────────
module "network" {
  source = "./modules/network"

  network_name        = "ctfd-network"
  subnet_name         = "ctfd-subnet"
  subnet_cidr         = var.internal_subnet_cidr
  dns_nameservers     = var.dns_nameservers
  router_name         = "ctfd-router"
  external_network_id = var.external_network_id
}

# ── Security Group ─────────────────────────────────────────
module "secgroup" {
  source = "./modules/secgroup"

  secgroup_name        = "ctfd-sg"
  secgroup_description = "CTFd Server Security Group"
  ssh_allowed_cidr     = var.ssh_allowed_cidr
  ctfd_port            = var.ctfd_port
}

# ── VM + Floating IP ───────────────────────────────────────
module "instance" {
  source = "./modules/instance"

  instance_name    = var.instance_name
  image_id         = var.image_id
  flavor_name      = var.flavor_name
  keypair_name     = module.keypair.keypair_name
  secgroup_name    = module.secgroup.secgroup_name
  network_id       = module.network.network_id
  floating_ip_pool = var.floating_ip_pool

  # Cloud-init 設定
  timezone   = var.timezone
  deploy_dir = var.deploy_dir

  # 確保網路和 Router Interface 完全就緒後才建立 VM
  depends_on = [module.network]
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