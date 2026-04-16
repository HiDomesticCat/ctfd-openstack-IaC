# ctfd-openstack/modules/instance/variables.tf

variable "instance_name" {
  description = "VM 名稱"
  type        = string
  default     = "ctfd-server"
}

variable "image_id" {
  description = "VM 使用的 image ID（從 platform output 或 terraform.tfvars 取得）"
  type        = string

  validation {
    condition     = length(var.image_id) > 0
    error_message = "image_id 不能為空。"
  }
}

variable "flavor_name" {
  description = "VM 規格名稱（例如 general.medium）"
  type        = string
  default     = "general.medium"
}

variable "keypair_name" {
  description = "SSH Keypair 名稱（由 keypair 模組產生）"
  type        = string
}

variable "secgroup_name" {
  description = "Security Group 名稱（由 secgroup 模組產生）"
  type        = string
}

variable "network_id" {
  description = "VM 要接上的內部網路 ID（由 network 模組產生）"
  type        = string
}

variable "use_floating_ip" {
  description = "是否配置 Floating IP（false=僅 SNAT 聯外）"
  type        = bool
  default     = true
}

variable "floating_ip_pool" {
  description = "Floating IP 所在的外部網路名稱（use_floating_ip=true 時使用）"
  type        = string
  default     = "public"
}

# ── Management Network（OpenStack API 可達性）────────────

variable "mgmt_network_id" {
  description = "管理網路 ID（讓 VM 能連到 OpenStack API，空字串=不接）"
  type        = string
  default     = ""
}

variable "mgmt_routes" {
  description = "管理網卡的靜態路由（如到 OpenStack API 網段）"
  type = list(object({
    to  = string  # 目標網段，如 "192.168.50.0/24"
    via = string  # gateway，如 "192.168.235.1"
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
  description = "Volume 大小（GB），boot_from_volume=true 時使用"
  type        = number
  default     = 20
}

# ── DNS ────────────────────────────────────────────────────

variable "dns_nameservers" {
  description = "DNS 伺服器清單（cloud-init + Docker daemon 使用）"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

# ── Cloud-init ─────────────────────────────────────────────

variable "timezone" {
  description = "VM 時區（cloud-init 設定）"
  type        = string
  default     = "Asia/Taipei"
}

variable "deploy_dir" {
  description = "CTFd 部署目錄路徑（cloud-init 建立）"
  type        = string
  default     = "/opt/ctfd"

  validation {
    condition     = startswith(var.deploy_dir, "/")
    error_message = "deploy_dir 必須是絕對路徑（以 / 開頭）。"
  }
}
