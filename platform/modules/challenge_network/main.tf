# ─────────────────────────────────────────────────────────────
# 玩家 ↔ 題目共享網段（player ↔ challenge）
#
# Admin 創建，透過 RBAC access_as_shared 分享給 ctfd-deployer project。
# 三個層都用名字 data source 引用此網段：
#   1. chell/ k3s worker  — 加第二個 port，NodePort (30000-32767) 從這聽
#   2. ctfd/ openstack-vm scenario — 題目 VM 預設 network_id 指向此網段
#   3. gamma4-lab-infra/ 研究 VM — 加第二個 port，Caldera 直接打題目（不走 FIP）
#
# 為什麼不直接讓各層自建：
#   - 三方都要接同一個網段才能互通；自建會變三段獨立網段
#   - 這層走 admin scope，可一致管理（CIDR 不衝突、共用 MTU、RBAC policy 集中）
# ─────────────────────────────────────────────────────────────

resource "openstack_networking_network_v2" "challenge_net" {
  name           = var.network_name
  description    = "玩家↔題目共享網段（admin 創、RBAC share 給 ctfd-deployer）"
  admin_state_up = true
  mtu            = var.mtu
}

resource "openstack_networking_subnet_v2" "challenge_net" {
  name            = var.subnet_name
  network_id      = openstack_networking_network_v2.challenge_net.id
  cidr            = var.cidr
  ip_version      = 4
  enable_dhcp     = true
  dns_nameservers = var.dns_nameservers
}

# RBAC：分享給 ctfd-deployer 所屬 project
# - access_as_shared 讓對方可在自己的 project 裡建 port 接這個網段
# - 子網段隨網段一起被分享（不需要額外的 subnet RBAC）
resource "openstack_networking_rbac_policy_v2" "share_to_ctfd" {
  action        = "access_as_shared"
  object_id     = openstack_networking_network_v2.challenge_net.id
  object_type   = "network"
  target_tenant = var.target_project_id
}
