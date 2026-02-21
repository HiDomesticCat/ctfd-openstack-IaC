# platform/modules/flavors/outputs.tf

output "flavor_ids" {
  description = "所有 flavor 的 ID"
  value = {
    for k, flavor in openstack_compute_flavor_v2.flavors :
    k => flavor.id
  }
}

output "flavor_names" {
  description = "所有 flavor 的名稱"
  value = {
    for k, flavor in openstack_compute_flavor_v2.flavors :
    k => flavor.name
  }
}