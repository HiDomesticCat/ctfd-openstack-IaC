# platform/main.tf
# ─────────────────────────────────────────────────────────────
# 共享基礎設施層（Layer 1）：所有上層模組共用的 OpenStack 資源
#
# 職責：
#   1. 外部網路（external network）：Floating IP 來源，對應實體網段
#      → create_external_network = true  → 自建（lab15）
#      → create_external_network = false → 引用現有（lab50）
#   2. VM Images：上傳 OS image 到 OpenStack Glance
#   3. VM Flavors：定義 vCPU/RAM/Disk 規格供各層選用
#      → create_flavors = true  → 自建（lab15）
#      → create_flavors = false → 沿用現有（lab50）
#   4. ctfd Project：建立隔離的 OpenStack project + 專屬使用者 + 配額
#
# 輸出（outputs.tf）供上層使用：
#   external_network_id  → ctfd/, chell/ 建立 Router 或申請 FIP 時引用
#   external_network_name→ ctfd/, chell/ 申請 Floating IP 時引用
#   image_ids            → ctfd/, chell/ 建立 VM 時引用
#   ctfd_credentials     → 生成 clouds.yaml 供 ctfd-deployer 使用
#
# ⚠️  此層以 admin 帳號執行（clouds.yaml 的 openstack cloud entry）
# ⚠️  ctfd 以下各層改用 ctfd-deployer 帳號（clouds.yaml 的 ctfd entry）
# ─────────────────────────────────────────────────────────────

# ── 外部網路：自建 or 引用 ──────────────────────────────────

module "external_network" {
  count  = var.create_external_network ? 1 : 0
  source = "./modules/network"

  network_name          = "public"
  subnet_name           = "public-subnet"
  subnet_cidr           = var.external_subnet_cidr
  gateway_ip            = var.external_gateway_ip
  allocation_pool_start = var.external_pool_start
  allocation_pool_end   = var.external_pool_end
  dns_nameservers       = var.dns_nameservers
  physical_network      = var.physical_network
  network_type          = var.network_type
}

data "openstack_networking_network_v2" "existing_external" {
  count = var.create_external_network ? 0 : 1
  name  = var.existing_external_network_name
}

locals {
  external_network_id   = var.create_external_network ? module.external_network[0].network_id : data.openstack_networking_network_v2.existing_external[0].id
  external_network_name = var.create_external_network ? module.external_network[0].network_name : data.openstack_networking_network_v2.existing_external[0].name
}

# ── VM Images ────────────────────────────────────────────────

module "images" {
  source = "./modules/images"
  images = var.images
}

# ── VM Flavors：自建 or 沿用現有 ─────────────────────────────

module "flavors" {
  count   = var.create_flavors ? 1 : 0
  source  = "./modules/flavors"
  flavors = var.flavors
}

# ── CTFd 環境的 Project ──────────────────────────────────────

module "ctfd_project" {
  source = "./modules/project"

  environment         = var.environment
  project_name        = var.project_name
  project_description = var.project_description
  username            = var.deployer_username
  password            = var.ctfd_deployer_password
  role                = "member"
  enable_quota        = true
  quota               = var.quota
}
