# ctfd-openstack/modules/instance/main.tf

# CTFd VM
# boot_from_volume=false → image_id 直接 boot（flavor disk>0）
# boot_from_volume=true  → image → volume → boot（flavor disk=0）
resource "openstack_compute_instance_v2" "this" {
  name        = var.instance_name
  image_id    = var.boot_from_volume ? null : var.image_id
  flavor_name = var.flavor_name
  key_pair    = var.keypair_name

  security_groups = [var.secgroup_name]

  network {
    uuid = var.network_id
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
    timezone   = var.timezone
    deploy_dir = var.deploy_dir
  })
}

# 申請 Floating IP
resource "openstack_networking_floatingip_v2" "this" {
  pool = var.floating_ip_pool
}

# 取得 VM 的 Port（用於綁定 Floating IP）
data "openstack_networking_port_v2" "this" {
  device_id  = openstack_compute_instance_v2.this.id
  network_id = var.network_id
}

# 將 Floating IP 綁定到 VM Port
resource "openstack_networking_floatingip_associate_v2" "this" {
  floating_ip = openstack_networking_floatingip_v2.this.address
  port_id     = data.openstack_networking_port_v2.this.id
}
