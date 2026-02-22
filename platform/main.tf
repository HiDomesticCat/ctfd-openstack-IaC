# platform/main.tf
# ─────────────────────────────────────────────────────────────
# 共享基礎設施層（Layer 1）：所有上層模組共用的 OpenStack 資源
#
# 職責：
#   1. 外部網路（external network）：Floating IP 來源，對應實體網段
#   2. VM Images：上傳 OS image 到 OpenStack Glance
#   3. VM Flavors：定義 vCPU/RAM/Disk 規格供各層選用
#   4. ctfd Project：建立隔離的 OpenStack project + 專屬使用者 + 配額
#
# 輸出（outputs.tf）供上層使用：
#   external_network_id  → ctfd/, chell/ 建立 Router 時引用
#   external_network_name→ ctfd/, chell/ 申請 Floating IP 時引用
#   image_ids            → ctfd/, chell/ 建立 VM 時引用
#   ctfd_credentials     → 生成 clouds.yaml 供 ctfd-deployer 使用
#
# ⚠️  此層以 admin 帳號執行（clouds.yaml 的 openstack cloud entry）
# ⚠️  ctfd 以下各層改用 ctfd-deployer 帳號（clouds.yaml 的 ctfd entry）
# ─────────────────────────────────────────────────────────────

module "external_network" {
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

module "images" {
  source = "./modules/images"
  images = var.images
}

module "flavors" {
  source  = "./modules/flavors"
  flavors = var.flavors
}

# CTFd 環境的 Project
module "ctfd_project" {
  source = "./modules/project"

  environment         = var.environment
  project_name        = "ctfd"
  project_description = "CTFd 競賽平台環境"
  username            = "ctfd-deployer"
  password            = var.ctfd_deployer_password
  role                = "member"
  enable_quota        = true
  quota = {
    # Compute quotas
    # 4 infra VM 用 8c/16GB；general.small = 1c/2GB/台
    # 3 個測試帳號最多同時開 3 台題目 VM
    instances     = 10   # 4 infra + 最多 6 台題目（保留緩衝）
    cores         = 12   # 8 infra + 3 題目 + 1 緩衝
    ram           = 24576 # 16384 infra + 3*2048 題目 + 2048 緩衝
    key_pairs     = 10
    server_groups = 10

    # Network quotas
    floatingips          = 10   # 4 infra + 最多 6 題目，已足夠
    networks             = 10
    subnets              = 10
    routers              = 5
    ports                = 50
    security_groups      = 15
    security_group_rules = 150

    # Storage quotas
    volumes   = 5
    gigabytes = 500
    snapshots = 10
    backups   = 5
  }
}
