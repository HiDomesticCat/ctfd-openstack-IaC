# platform/variables.tf

# ── 環境 ─────────────────────────────────────────────────────

variable "environment" {
  description = "環境名稱（dev, staging, production）"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "環境必須是 dev、staging 或 production。"
  }
}

variable "openstack_cloud" {
  description = "OpenStack cloud 名稱（對應 ~/.config/openstack/clouds.yaml）"
  type        = string
  default     = "openstack"
}

# ── Project / User ──────────────────────────────────────────

variable "project_name" {
  description = "OpenStack project 名稱"
  type        = string
  default     = "ctfd"
}

variable "project_description" {
  description = "OpenStack project 描述"
  type        = string
  default     = "CTFd 競賽平台環境"
}

variable "deployer_username" {
  description = "部署帳號名稱"
  type        = string
  default     = "ctfd-deployer"
}

variable "ctfd_deployer_password" {
  description = "CTFd 部署帳號的密碼"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.ctfd_deployer_password) >= 12
    error_message = "密碼長度至少 12 個字元。"
  }
}

# ── 外部網路開關 ─────────────────────────────────────────────

variable "create_external_network" {
  description = "是否自建外部網路（true=自建，false=引用已有的 external network）"
  type        = bool
  default     = true
}

variable "existing_external_network_name" {
  description = "引用現有外部網路的名稱（create_external_network=false 時必填）"
  type        = string
  default     = ""
}

# 以下 variable 僅在 create_external_network=true 時使用

variable "external_subnet_cidr" {
  description = "外部網路 CIDR（自建模式）"
  type        = string
  default     = "10.0.2.0/24"

  validation {
    condition     = can(cidrhost(var.external_subnet_cidr, 0))
    error_message = "必須是合法的 CIDR 格式。"
  }
}

variable "external_gateway_ip" {
  description = "外部網路 Gateway（自建模式）"
  type        = string
  default     = "10.0.2.1"
}

variable "external_pool_start" {
  description = "Floating IP 池起始 IP（自建模式）"
  type        = string
  default     = "10.0.2.150"
}

variable "external_pool_end" {
  description = "Floating IP 池結束 IP（自建模式）"
  type        = string
  default     = "10.0.2.199"
}

variable "dns_nameservers" {
  description = "DNS 伺服器"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "physical_network" {
  description = "實體網路名稱（自建模式）"
  type        = string
  default     = "physnet1"
}

variable "network_type" {
  description = "外部網路類型（自建模式）"
  type        = string
  default     = "flat"
}

# ── Flavor 開關 ──────────────────────────────────────────────

variable "create_flavors" {
  description = "是否自建 flavor（true=自建，false=沿用環境現有 flavor）"
  type        = bool
  default     = true
}

variable "flavors" {
  description = "要建立的 flavor 定義（create_flavors=true 時使用）"
  type = map(object({
    name      = string
    ram       = number
    vcpus     = number
    disk      = number
    is_public = bool
  }))
  default = {}
}

# ── Image ────────────────────────────────────────────────────

variable "images" {
  description = "要上傳到 OpenStack 的 image 定義"
  type = map(object({
    name             = string
    source_url       = string
    container_format = string
    disk_format      = string
    visibility       = string
    min_disk_gb      = number
    min_ram_mb       = number
    properties       = map(string)
  }))
}

# ── 玩家↔題目共享網段 ──────────────────────────────────────

variable "challenge_network_name" {
  description = "玩家↔題目共享網段名稱（chell, ctfd, gamma4-IaC 用 data source 引用）"
  type        = string
  default     = "challenge-net"
}

variable "challenge_network_cidr" {
  description = "玩家↔題目 CIDR。連續編號：50 管理、77 gamma4 內、78 player↔challenge、100 ctfd web、200 chell 控制面"
  type        = string
  default     = "192.168.78.0/24"

  validation {
    condition     = can(cidrhost(var.challenge_network_cidr, 0))
    error_message = "必須是合法的 CIDR 格式。"
  }
}

variable "challenge_network_mtu" {
  description = "玩家↔題目 MTU。本叢集 path MTU ~928，900 是經驗安全值。"
  type        = number
  default     = 900
}

# ── Quota ────────────────────────────────────────────────────

variable "quota" {
  description = "Project 配額設定"
  type = object({
    instances            = number
    cores                = number
    ram                  = number
    key_pairs            = number
    server_groups        = number
    floatingips          = number
    networks             = number
    subnets              = number
    routers              = number
    ports                = number
    security_groups      = number
    security_group_rules = number
    volumes              = number
    gigabytes            = number
    snapshots            = number
    backups              = number
  })
  default = {
    instances            = 60
    cores                = 65
    ram                  = 122880
    key_pairs            = 10
    server_groups        = 10
    floatingips          = 60
    networks             = 10
    subnets              = 10
    routers              = 5
    ports                = 120
    security_groups      = 65
    security_group_rules = 500
    volumes              = 5
    gigabytes            = 500
    snapshots            = 10
    backups              = 5
  }
}
