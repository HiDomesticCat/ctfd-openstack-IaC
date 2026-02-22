# chell/modules/secgroup/main.tf
# k3s 叢集 Security Group

resource "openstack_networking_secgroup_v2" "this" {
  name        = var.secgroup_name
  description = "k3s cluster security group for chell shell challenge backend"
}

# ── 叢集內部互通（同 secgroup 的節點互相通訊）───────────────
# 涵蓋所有 k3s 內部協定：
#   TCP: 6443 (API), 10250 (kubelet), 2379-2380 (etcd)
#   UDP: 8472 (Flannel VXLAN), 51820 (WireGuard optional)
resource "openstack_networking_secgroup_rule_v2" "intra_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_group_id   = openstack_networking_secgroup_v2.this.id
  security_group_id = openstack_networking_secgroup_v2.this.id
}

resource "openstack_networking_secgroup_rule_v2" "intra_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_group_id   = openstack_networking_secgroup_v2.this.id
  security_group_id = openstack_networking_secgroup_v2.this.id
}

# ── SSH 管理（限制來源 IP）────────────────────────────────
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.this.id
}

# ── k3s API Server（kubectl / chall-manager 存取）────────
resource "openstack_networking_secgroup_rule_v2" "k3s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.ssh_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.this.id
}

# ── NodePort 範圍（玩家 challenge 連線）─────────────────
# 每個 challenge pod 會被 Kubernetes 自動分配此範圍內的 port
resource "openstack_networking_secgroup_rule_v2" "nodeport" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.this.id
}

# ── ICMP（ping，方便除錯）────────────────────────────────
resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.this.id
}
