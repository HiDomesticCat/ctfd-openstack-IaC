# ctfd-openstack/modules/instance/main.tf

# ── Management Network Port（可選）──────────────────────────
# 預建 port 讓 Neutron 分配 IP，再透過 cloud-init 設定 netplan
resource "openstack_networking_port_v2" "mgmt" {
  count          = var.mgmt_network_id != "" ? 1 : 0
  name           = "${var.instance_name}-mgmt"
  network_id     = var.mgmt_network_id
  admin_state_up = true
}

locals {
  mgmt_ip = var.mgmt_network_id != "" ? openstack_networking_port_v2.mgmt[0].all_fixed_ips[0] : ""
}

# ── CTFd VM ──────────────────────────────────────────────────
# boot_from_volume=false → image_id 直接 boot（flavor disk>0）
# boot_from_volume=true  → image → volume → boot（flavor disk=0）
resource "openstack_compute_instance_v2" "this" {
  name        = var.instance_name
  image_id    = var.boot_from_volume ? null : var.image_id
  flavor_name = var.flavor_name
  key_pair    = var.keypair_name

  security_groups = [var.secgroup_name]

  # 主網卡
  network {
    uuid = var.network_id
  }

  # 管理網卡（可選，用 pre-built port 掛載）
  dynamic "network" {
    for_each = var.mgmt_network_id != "" ? [1] : []
    content {
      port = openstack_networking_port_v2.mgmt[0].id
    }
  }

  dynamic "block_device" {
    for_each = var.boot_from_volume ? [1] : []
    content {
      uuid                  = var.image_id
      source_type           = "image"
      destination_type      = "volume"
      volume_size           = var.volume_size
      boot_index            = 0
      delete_on_termination = true
    }
  }

  # Cloud-init：VM 第一次啟動時自動執行
  user_data = templatefile("${path.module}/cloud-init/user_data.yaml.tpl", {
    timezone        = var.timezone
    deploy_dir      = var.deploy_dir
    mgmt_ip         = local.mgmt_ip
    mgmt_routes     = var.mgmt_routes
    dns_nameservers = var.dns_nameservers
    network_mtu     = var.network_mtu
  })
}

# 申請 Floating IP（可選）
resource "openstack_networking_floatingip_v2" "this" {
  count = var.use_floating_ip ? 1 : 0
  pool  = var.floating_ip_pool
}

# 取得 VM 的 Port（用於綁定 Floating IP）
data "openstack_networking_port_v2" "this" {
  count      = var.use_floating_ip ? 1 : 0
  device_id  = openstack_compute_instance_v2.this.id
  network_id = var.network_id
}

# 將 Floating IP 綁定到 VM Port
resource "openstack_networking_floatingip_associate_v2" "this" {
  count       = var.use_floating_ip ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.this[0].address
  port_id     = data.openstack_networking_port_v2.this[0].id
}
