resource "openstack_networking_network_v2" "external" {
  name           = var.network_name
  description    = "外部網路，提供 Floating IP 和對外連線"
  admin_state_up = true
  external       = true

  segments {
    physical_network = var.physical_network
    network_type     = var.network_type
  }
}

resource "openstack_networking_subnet_v2" "external" {
  name       = var.subnet_name
  network_id = openstack_networking_network_v2.external.id
  cidr       = var.subnet_cidr
  gateway_ip = var.gateway_ip
  ip_version = 4

  # 外部網路不用 DHCP
  # Floating IP 透過 OpenStack NAT 機制分配，不是 DHCP
  enable_dhcp = false

  allocation_pool {
    start = var.allocation_pool_start
    end   = var.allocation_pool_end
  }

  dns_nameservers = var.dns_nameservers
}