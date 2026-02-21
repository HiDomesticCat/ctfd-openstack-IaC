# ctfd-openstack/modules/keypair/main.tf

resource "openstack_compute_keypair_v2" "this" {
  name       = var.keypair_name
  public_key = file(var.public_key_path)
}
