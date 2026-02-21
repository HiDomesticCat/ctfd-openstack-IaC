# ctfd-openstack/modules/network/main.tf

# 內部網路
resource "openstack_networking_network_v2" "this" {
  name           = var.network_name
  admin_state_up = true
}

# 內部子網路：開 DHCP，讓 VM 自動取得 IP
resource "openstack_networking_subnet_v2" "this" {
  name            = var.subnet_name
  network_id      = openstack_networking_network_v2.this.id
  cidr            = var.subnet_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
  enable_dhcp     = true
}

# Router：連接內部網路與外部網路
resource "openstack_networking_router_v2" "this" {
  name                = var.router_name
  admin_state_up      = true
  external_network_id = var.external_network_id
}

# 將內部子網路接到 Router
resource "openstack_networking_router_interface_v2" "this" {
  router_id = openstack_networking_router_v2.this.id
  subnet_id = openstack_networking_subnet_v2.this.id
}
