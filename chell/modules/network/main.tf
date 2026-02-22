# chell/modules/network/main.tf
# k3s 叢集專用內部網路

# k3s 內部網路
resource "openstack_networking_network_v2" "this" {
  name           = var.network_name
  admin_state_up = true
}

# k3s 子網路
# DHCP pool 從 .20 起，保留 .1~.19 給固定 IP（master = .10）
resource "openstack_networking_subnet_v2" "this" {
  name            = var.subnet_name
  network_id      = openstack_networking_network_v2.this.id
  cidr            = var.subnet_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
  enable_dhcp     = true

  allocation_pool {
    start = cidrhost(var.subnet_cidr, 20)
    end   = cidrhost(var.subnet_cidr, 200)
  }
}

# Router：chell 網路獨立對外，不與 ctfd 網路共用
resource "openstack_networking_router_v2" "this" {
  name                = var.router_name
  admin_state_up      = true
  external_network_id = var.external_network_id
}

# 將 k3s 子網路接到 Router
resource "openstack_networking_router_interface_v2" "this" {
  router_id = openstack_networking_router_v2.this.id
  subnet_id = openstack_networking_subnet_v2.this.id
}
