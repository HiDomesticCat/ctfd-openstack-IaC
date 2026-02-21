variable "environment" {
  description = "環境名稱（用於刪除保護檢查）"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "OpenStack Project 名稱"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name 只能包含小寫字母、數字和連字號。"
  }
}

variable "project_description" {
  description = "Project 描述"
  type        = string
  default     = ""
}

variable "username" {
  description = "這個 Project 專屬的部署使用者名稱"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,31}$", var.username))
    error_message = "使用者名稱必須是 3-32 個字元，以字母或數字開頭，只能包含小寫字母、數字和連字號。"
  }
}

variable "password" {
  description = "部署使用者的密碼"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.password) >= 12
    error_message = "密碼長度至少 12 個字元。"
  }

  validation {
    condition     = can(regex("[A-Z]", var.password)) && can(regex("[a-z]", var.password)) && can(regex("[0-9]", var.password))
    error_message = "密碼必須包含大寫字母、小寫字母和數字。"
  }
}

variable "role" {
  description = "使用者在 Project 內的角色"
  type        = string
  default     = "member"

  validation {
    condition     = contains(["member", "admin", "reader"], var.role)
    error_message = "role 只能是 member、admin 或 reader。"
  }
}

variable "enable_quota" {
  description = "是否設定資源配額"
  type        = bool
  default     = false
}

variable "quota" {
  description = "Project 的資源配額設定"
  type = object({
    # Compute quotas
    instances     = number
    cores         = number
    ram           = number
    key_pairs     = optional(number, 10)
    server_groups = optional(number, 10)

    # Network quotas
    floatingips          = number
    networks             = optional(number, 10)
    subnets              = optional(number, 10)
    routers              = optional(number, 5)
    ports                = optional(number, 50)
    security_groups      = optional(number, 10)
    security_group_rules = optional(number, 100)

    # Storage quotas
    volumes   = number
    gigabytes = optional(number, 1000)
    snapshots = optional(number, 10)
    backups   = optional(number, 10)
  })
  default = {
    instances            = 10
    cores                = 20
    ram                  = 51200
    key_pairs            = 10
    server_groups        = 10
    floatingips          = 5
    networks             = 10
    subnets              = 10
    routers              = 5
    ports                = 50
    security_groups      = 10
    security_group_rules = 100
    volumes              = 10
    gigabytes            = 1000
    snapshots            = 10
    backups              = 10
  }

  validation {
    condition = (
      var.quota.instances >= 0 && var.quota.instances <= 1000 &&
      var.quota.cores >= 0 && var.quota.cores <= 1000 &&
      var.quota.ram >= 0 && var.quota.ram <= 1048576 &&
      var.quota.floatingips >= 0 && var.quota.floatingips <= 100 &&
      var.quota.volumes >= 0 && var.quota.volumes <= 1000
    )
    error_message = "配額值必須為非負數且在合理範圍內。"
  }
}