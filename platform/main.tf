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
    instances     = 5
    cores         = 8
    ram           = 16384
    key_pairs     = 10
    server_groups = 10

    # Network quotas
    floatingips          = 3
    networks             = 10
    subnets              = 10
    routers              = 5
    ports                = 50
    security_groups      = 10
    security_group_rules = 100

    # Storage quotas
    volumes   = 5
    gigabytes = 500
    snapshots = 10
    backups   = 5
  }
}
