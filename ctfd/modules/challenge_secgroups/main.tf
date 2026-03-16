# modules/challenge_secgroups/main.tf
# 預建的 Challenge VM Security Groups
#
# 出題者在 CTFd Advanced 區塊設定 security_group_id=<UUID>
# 即可跳過 per-player SG 建立，加速題目啟動 ~3-5s
#
# 提供三種常用組合：
#   allow-all  — 所有 TCP port + ICMP（靈活題目）
#   allow-ssh  — SSH (22) + ICMP（SSH 類題目）
#   allow-web  — HTTP (80) + HTTPS (443) + SSH (22) + ICMP（Web 類題目）

# ── allow-all：所有 TCP port ──────────────────────────────
resource "openstack_networking_secgroup_v2" "allow_all" {
  name        = "${var.name_prefix}-allow-all"
  description = "CTF challenge: allow all TCP + ICMP"
}

resource "openstack_networking_secgroup_rule_v2" "allow_all_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_all.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_all_icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_all.id
}

# ── allow-ssh：SSH + ICMP ────────────────────────────────
resource "openstack_networking_secgroup_v2" "allow_ssh" {
  name        = "${var.name_prefix}-allow-ssh"
  description = "CTF challenge: SSH (22) + ICMP"
}

resource "openstack_networking_secgroup_rule_v2" "allow_ssh_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_ssh.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_ssh_icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_ssh.id
}

# ── allow-web：HTTP + HTTPS + SSH + ICMP ─────────────────
resource "openstack_networking_secgroup_v2" "allow_web" {
  name        = "${var.name_prefix}-allow-web"
  description = "CTF challenge: HTTP (80) + HTTPS (443) + SSH (22) + ICMP"
}

resource "openstack_networking_secgroup_rule_v2" "allow_web_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_web.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_web_https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_web.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_web_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_web.id
}

resource "openstack_networking_secgroup_rule_v2" "allow_web_icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_web.id
}
