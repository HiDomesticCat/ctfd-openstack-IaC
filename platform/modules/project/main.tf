# 取得 role 的 ID（role 已經存在於 OpenStack，只是查詢）
data "openstack_identity_role_v3" "role" {
  name = var.role
}

# 建立 Project
resource "openstack_identity_project_v3" "this" {
  name        = var.project_name
  description = var.project_description
  enabled     = true

  lifecycle {
    # 靜態刪除保護：生產環境請手動啟用
    # 取消下一行的註解以啟用刪除保護
    # prevent_destroy = true
  }
}

# 建立專屬使用者
resource "openstack_identity_user_v3" "this" {
  name               = var.username
  password           = var.password
  default_project_id = openstack_identity_project_v3.this.id
  enabled            = true

  # 強制使用者不能修改自己的密碼（部署帳號）
  ignore_change_password_upon_first_use = true

  lifecycle {
    # 忽略密碼變更以避免不必要的資源重建
    ignore_changes = [password]
    
    # 刪除保護：生產環境請手動啟用
    # prevent_destroy = true
  }
}

# 指派角色
resource "openstack_identity_role_assignment_v3" "this" {
  user_id    = openstack_identity_user_v3.this.id
  project_id = openstack_identity_project_v3.this.id
  role_id    = data.openstack_identity_role_v3.role.id
}

# 設定配額（只有 enable_quota = true 才建立）
resource "openstack_compute_quotaset_v2" "this" {
  count      = var.enable_quota ? 1 : 0
  project_id = openstack_identity_project_v3.this.id

  instances      = var.quota.instances
  cores          = var.quota.cores
  ram            = var.quota.ram
  key_pairs      = var.quota.key_pairs
  server_groups  = var.quota.server_groups

  depends_on = [openstack_identity_role_assignment_v3.this]
}

resource "openstack_networking_quota_v2" "this" {
  count      = var.enable_quota ? 1 : 0
  project_id = openstack_identity_project_v3.this.id

  floatingip          = var.quota.floatingips
  network             = var.quota.networks
  subnet              = var.quota.subnets
  router              = var.quota.routers
  port                = var.quota.ports
  security_group      = var.quota.security_groups
  security_group_rule = var.quota.security_group_rules

  depends_on = [openstack_identity_role_assignment_v3.this]
}

resource "openstack_blockstorage_quotaset_v3" "this" {
  count      = var.enable_quota ? 1 : 0
  project_id = openstack_identity_project_v3.this.id

  volumes   = var.quota.volumes
  gigabytes = var.quota.gigabytes
  snapshots = var.quota.snapshots
  backups   = var.quota.backups

  depends_on = [openstack_identity_role_assignment_v3.this]
}
