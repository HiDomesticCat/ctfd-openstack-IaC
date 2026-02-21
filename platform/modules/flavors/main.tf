# platform/modules/flavors/main.tf

resource "openstack_compute_flavor_v2" "flavors" {
  for_each = var.flavors

  name      = each.value.name
  ram       = each.value.ram
  vcpus     = each.value.vcpus
  disk      = each.value.disk
  is_public = each.value.is_public
}