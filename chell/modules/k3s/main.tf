# chell/modules/k3s/main.tf
# k3s 叢集節點：master + workers
#
# 設計重點：
# 1. use_fip=true: FIP 先行分配，用於 cloud-init TLS SAN + 外部存取
# 2. use_fip=false: 不建 FIP，用內網 IP，透過 bastion 管理（省 FIP 資源）
# 3. 自建網路模式：master 使用 port 資源設定固定 IP
# 4. Shared 網路模式：master 使用 DHCP IP，worker 透過 master 內網 IP join

locals {
  use_fixed_ip = var.master_fixed_ip != ""
  # Master 內網 IP（port 建好後才知道）
  master_internal_ip = openstack_networking_port_v2.master.all_fixed_ips[0]
  # Worker join 用的 master IP：有固定 IP > FIP > 內網 IP
  master_join_ip = local.use_fixed_ip ? var.master_fixed_ip : local.master_internal_ip
  # 對外 IP（給 TLS SAN 和 output 用）
  master_external_ip = var.use_fip ? openstack_networking_floatingip_v2.master[0].address : local.master_internal_ip
}

# ── Floating IPs（可選）────────────────────────────────────
resource "openstack_networking_floatingip_v2" "master" {
  count = var.use_fip ? 1 : 0
  pool  = var.floating_ip_pool
}

resource "openstack_networking_floatingip_v2" "workers" {
  count = var.use_fip ? var.worker_count : 0
  pool  = var.floating_ip_pool
}

# ── Master Port ─────────────────────────────────────────────
resource "openstack_networking_port_v2" "master" {
  name           = "${var.master_name}-port"
  network_id     = var.network_id
  admin_state_up = true

  security_group_ids = [var.secgroup_id]

  dynamic "fixed_ip" {
    for_each = local.use_fixed_ip ? [1] : []
    content {
      subnet_id  = var.subnet_id
      ip_address = var.master_fixed_ip
    }
  }
}

# ── Worker Ports（主：chell-network 控制面）─────────────────
resource "openstack_networking_port_v2" "workers" {
  count          = var.worker_count
  name           = "${var.worker_name}-${count.index + 1}-port"
  network_id     = var.network_id
  admin_state_up = true

  security_group_ids = [var.secgroup_id]
}

# ── Worker 第二個 port：challenge-net（玩家↔題目共享網段）─────
# kube-proxy 預設聽全部介面，所以 NodePort 30000-32767 在這個網段也通。
# gamma4 VM 也接同一網段，Caldera 直接打 worker challenge-net IP : NodePort，
# 省掉 worker FIP 那一跳。secgroup 共用 chell-sg（NodePort 已對 0.0.0.0/0 開放）。
resource "openstack_networking_port_v2" "workers_challenge_net" {
  count          = var.challenge_network_id != "" ? var.worker_count : 0
  name           = "${var.worker_name}-${count.index + 1}-challenge-port"
  network_id     = var.challenge_network_id
  admin_state_up = true

  security_group_ids = [var.secgroup_id]
}

# ── k3s Master Instance ───────────────────────────────────
resource "openstack_compute_instance_v2" "master" {
  name        = var.master_name
  image_id    = var.boot_from_volume ? null : var.image_id
  flavor_name = var.master_flavor
  key_pair    = var.keypair_name

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

  user_data = templatefile("${path.module}/cloud-init/server.yaml.tpl", {
    timezone           = var.timezone
    k3s_token          = var.k3s_token
    k3s_version        = var.k3s_version
    master_fixed_ip    = local.use_fixed_ip ? var.master_fixed_ip : local.master_internal_ip
    master_floating_ip = local.master_external_ip
    registry_ip        = var.registry_ip
    dns_nameservers    = var.dns_nameservers
    network_mtu        = var.network_mtu
  })

  network {
    port = openstack_networking_port_v2.master.id
  }

  depends_on = [openstack_networking_port_v2.master]
}

# ── k3s Worker Instances ──────────────────────────────────
resource "openstack_compute_instance_v2" "workers" {
  count       = var.worker_count
  name        = "${var.worker_name}-${count.index + 1}"
  image_id    = var.boot_from_volume ? null : var.image_id
  flavor_name = var.worker_flavor
  key_pair    = var.keypair_name

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

  user_data = templatefile("${path.module}/cloud-init/agent.yaml.tpl", {
    timezone        = var.timezone
    k3s_token       = var.k3s_token
    k3s_version     = var.k3s_version
    master_fixed_ip = local.master_join_ip
    registry_ip     = var.registry_ip
    dns_nameservers = var.dns_nameservers
    network_mtu     = var.network_mtu
  })

  # 主介面：chell-network（k3s 控制面、kubelet ↔ master、預設路由）
  network {
    port = openstack_networking_port_v2.workers[count.index].id
  }

  # 第二介面：challenge-net（玩家↔題目共享網段，NodePort 也聽在這）
  dynamic "network" {
    for_each = var.challenge_network_id != "" ? [1] : []
    content {
      port = openstack_networking_port_v2.workers_challenge_net[count.index].id
    }
  }

  depends_on = [
    openstack_compute_instance_v2.master,
    openstack_networking_port_v2.workers,
    openstack_networking_port_v2.workers_challenge_net,
  ]
}

# ── Floating IP 關聯（可選）──────────────────────────────
resource "openstack_networking_floatingip_associate_v2" "master" {
  count       = var.use_fip ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.master[0].address
  port_id     = openstack_networking_port_v2.master.id
}

resource "openstack_networking_floatingip_associate_v2" "workers" {
  count       = var.use_fip ? var.worker_count : 0
  floating_ip = openstack_networking_floatingip_v2.workers[count.index].address
  port_id     = openstack_networking_port_v2.workers[count.index].id
}
