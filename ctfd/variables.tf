# ctfd/variables.tf

# ── Provider ───────────────────────────────────────────────
variable "openstack_cloud" {
  description = "clouds.yaml 中的 cloud entry 名稱（對應 ctfd-deployer 帳號）"
  type        = string
  default     = "ctfd"
}

# ── Keypair ────────────────────────────────────────────────
variable "keypair_name" {
  description = "SSH Keypair 名稱"
  type        = string
  default     = "ctfd-key"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.keypair_name))
    error_message = "keypair_name 只能包含字母、數字、點、底線和連字號。"
  }
}

variable "public_key_path" {
  description = "SSH 公鑰絕對路徑（例如 /home/user/.ssh/id_rsa.pub）"
  type        = string
  default     = "~/.ssh/id_rsa.pub"

  validation {
    condition     = length(var.public_key_path) > 0
    error_message = "public_key_path 不能為空。"
  }
}

# ── Network 開關 ─────────────────────────────────────────────

variable "use_shared_network" {
  description = "是否使用現有 shared network（true=引用 shared network，false=自建 network + router）"
  type        = bool
  default     = false
}

variable "shared_network_name" {
  description = "引用的 shared network 名稱（use_shared_network=true 時必填）"
  type        = string
  default     = ""
}

# 以下 variable 僅在 use_shared_network=false 時使用

variable "external_network_id" {
  description = "外部網路 ID（自建網路模式，從 platform output 取得）"
  type        = string
  default     = ""
}

variable "internal_subnet_cidr" {
  description = "CTFd 內部網路 CIDR（自建網路模式）"
  type        = string
  default     = "192.168.100.0/24"

  validation {
    condition     = can(cidrhost(var.internal_subnet_cidr, 0))
    error_message = "必須是合法的 CIDR 格式，例如 192.168.100.0/24。"
  }
}

variable "dns_nameservers" {
  description = "DNS 伺服器清單"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

# ── Security Group ─────────────────────────────────────────
variable "ssh_allowed_cidr" {
  description = "允許 SSH 連入的來源 CIDR（建議限制為管理 IP，避免全網際網路暴露）"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr 必須是合法的 CIDR 格式，例如 10.0.0.0/8 或 1.2.3.4/32。"
  }
}

variable "ctfd_port" {
  description = "CTFd 應用程式 Port"
  type        = number
  default     = 8000

  validation {
    condition     = var.ctfd_port >= 1 && var.ctfd_port <= 65535
    error_message = "ctfd_port 必須介於 1 到 65535 之間。"
  }
}

variable "registry_allowed_cidr" {
  description = "允許存取 Docker Registry (5000) 的來源 CIDR（k3s 節點子網，空字串=不建立規則）"
  type        = string
  default     = ""
}

# ── Instance ───────────────────────────────────────────────
variable "instance_name" {
  description = "CTFd VM 名稱"
  type        = string
  default     = "ctfd-server"
}

variable "image_id" {
  description = "VM 使用的 image ID（從 platform output 取得）"
  type        = string

  validation {
    condition     = length(var.image_id) > 0
    error_message = "image_id 不能為空，請從 platform output 取得。"
  }
}

variable "flavor_name" {
  description = "VM 規格名稱"
  type        = string
  default     = "general.medium"
}

variable "use_floating_ip" {
  description = "是否配置 Floating IP（false=僅使用 router SNAT 聯外，無外部 IP 連入）"
  type        = bool
  default     = true
}

variable "floating_ip_pool" {
  description = "Floating IP 所在的外部網路名稱（use_floating_ip=true 時使用）"
  type        = string
  default     = "public"
}

# ── Management Network ────────────────────────────────────

variable "mgmt_network_id" {
  description = "管理網路 ID（讓 VM 能連到 OpenStack API，空字串=不接）"
  type        = string
  default     = ""
}

variable "mgmt_routes" {
  description = "管理網卡的靜態路由"
  type = list(object({
    to  = string
    via = string
  }))
  default = []
}

# ── Volume Boot ───────────────────────────────────────────

variable "boot_from_volume" {
  description = "是否從 volume 開機（flavor disk=0 的環境必須設 true）"
  type        = bool
  default     = false
}

variable "volume_size" {
  description = "CTFd VM volume 大小（GB），boot_from_volume=true 時使用"
  type        = number
  default     = 20
}

# ── Cloud-init ─────────────────────────────────────────────

variable "timezone" {
  description = "VM 時區"
  type        = string
  default     = "Asia/Taipei"
}

variable "deploy_dir" {
  description = "CTFd 部署目錄路徑（cloud-init 自動建立）"
  type        = string
  default     = "/opt/ctfd"

  validation {
    condition     = startswith(var.deploy_dir, "/")
    error_message = "deploy_dir 必須是絕對路徑（以 / 開頭）。"
  }
}
