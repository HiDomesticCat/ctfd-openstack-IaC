# chell/modules/k3s/main.tf
# k3s 叢集節點：master（固定 IP）+ workers
#
# 設計重點：
# 1. master floating IP 先行分配，用於 cloud-init TLS SAN → kubeconfig 直接包含外部 IP
# 2. worker floating IP 先行分配，玩家透過 NodePort 連接 challenge
# 3. master 使用 port 資源設定固定 IP，確保 worker 可用固定 IP join cluster

# ── 預先分配 Floating IPs ──────────────────────────────────
# 分配在 instance 建立前，使 cloud-init 可以直接使用這些 IP
resource "openstack_networking_floatingip_v2" "master" {
  pool = var.floating_ip_pool
}

resource "openstack_networking_floatingip_v2" "workers" {
  count = var.worker_count
  pool  = var.floating_ip_pool
}

# ── Master Port（固定 IP）────────────────────────────────
# 固定 IP 使 worker cloud-init 不需等 DHCP 即可知道 master 的 IP
resource "openstack_networking_port_v2" "master" {
  name           = "${var.master_name}-port"
  network_id     = var.network_id
  admin_state_up = true

  security_group_ids = [var.secgroup_id]

  fixed_ip {
    subnet_id  = var.subnet_id
    ip_address = var.master_fixed_ip
  }
}

# ── Worker Ports ──────────────────────────────────────────
resource "openstack_networking_port_v2" "workers" {
  count          = var.worker_count
  name           = "${var.worker_name}-${count.index + 1}-port"
  network_id     = var.network_id
  admin_state_up = true

  security_group_ids = [var.secgroup_id]
}

# ── k3s Master Instance ───────────────────────────────────
resource "openstack_compute_instance_v2" "master" {
  name        = var.master_name
  image_id    = var.image_id
  flavor_name = var.master_flavor
  key_pair    = var.keypair_name

  user_data = templatefile("${path.module}/cloud-init/server.yaml.tpl", {
    timezone           = var.timezone
    k3s_token          = var.k3s_token
    k3s_version        = var.k3s_version
    master_fixed_ip    = var.master_fixed_ip
    master_floating_ip = openstack_networking_floatingip_v2.master.address
  })

  network {
    port = openstack_networking_port_v2.master.id
  }

  depends_on = [openstack_networking_port_v2.master]
}

# ── k3s Worker Instances ──────────────────────────────────
# 依賴 master instance 確保 cloud-init 等待時 master 已開始啟動
resource "openstack_compute_instance_v2" "workers" {
  count       = var.worker_count
  name        = "${var.worker_name}-${count.index + 1}"
  image_id    = var.image_id
  flavor_name = var.worker_flavor
  key_pair    = var.keypair_name

  user_data = templatefile("${path.module}/cloud-init/agent.yaml.tpl", {
    timezone        = var.timezone
    k3s_token       = var.k3s_token
    k3s_version     = var.k3s_version
    master_fixed_ip = var.master_fixed_ip
  })

  network {
    port = openstack_networking_port_v2.workers[count.index].id
  }

  depends_on = [
    openstack_compute_instance_v2.master,
    openstack_networking_port_v2.workers,
  ]
}

# ── Floating IP 關聯 ──────────────────────────────────────
resource "openstack_networking_floatingip_associate_v2" "master" {
  floating_ip = openstack_networking_floatingip_v2.master.address
  port_id     = openstack_networking_port_v2.master.id
}

resource "openstack_networking_floatingip_associate_v2" "workers" {
  count       = var.worker_count
  floating_ip = openstack_networking_floatingip_v2.workers[count.index].address
  port_id     = openstack_networking_port_v2.workers[count.index].id
}
