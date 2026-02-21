output "project_id" {
  description = "建立的 Project ID"
  value       = openstack_identity_project_v3.this.id
}

output "project_name" {
  description = "Project 名稱"
  value       = openstack_identity_project_v3.this.name
}

output "user_id" {
  description = "部署使用者 ID"
  value       = openstack_identity_user_v3.this.id
}

output "username" {
  description = "部署使用者名稱"
  value       = openstack_identity_user_v3.this.name
}

# 連線資訊（不包含密碼）
# 密碼應透過環境變數或秘密管理系統單獨管理
output "credentials" {
  description = "這個 Project 的連線資訊（密碼請另外管理）"
  sensitive   = true
  value = {
    project_id   = openstack_identity_project_v3.this.id
    project_name = openstack_identity_project_v3.this.name
    username     = openstack_identity_user_v3.this.name
    # 密碼已移除：請使用環境變數 OS_PASSWORD 或秘密管理系統
  }
}
