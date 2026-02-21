# ctfd-openstack/variables.tf

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
  default     = "/home/hicat0x0/.ssh/id_rsa.pub"

  validation {
    condition     = length(var.public_key_path) > 0
    error_message = "public_key_path 不能為空。"
  }
}

# ── Network ────────────────────────────────────────────────
variable "external_network_id" {
  description = "外部網路 ID（從 platform output 取得：module.external_network.network_id）"
  type        = string

  validation {
    condition     = length(var.external_network_id) > 0
    error_message = "external_network_id 不能為空，請從 platform output 取得。"
  }
}

variable "internal_subnet_cidr" {
  description = "CTFd 內部網路 CIDR（不能與其他子網路衝突）"
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

# ── Instance ───────────────────────────────────────────────
variable "instance_name" {
  description = "CTFd VM 名稱"
  type        = string
  default     = "ctfd-server"
}

variable "image_id" {
  description = "VM 使用的 image ID（從 platform output 取得：module.images.image_ids[\"ubuntu\"]）"
  type        = string

  validation {
    condition     = length(var.image_id) > 0
    error_message = "image_id 不能為空，請從 platform output 取得。"
  }
}

variable "flavor_name" {
  description = "VM 規格名稱（從 platform 建立的 flavor 中選擇）"
  type        = string
  default     = "general.medium"
}

variable "floating_ip_pool" {
  description = "Floating IP 所在的外部網路名稱（與 platform external_network 的 network_name 一致）"
  type        = string
  default     = "public"

  validation {
    condition     = length(var.floating_ip_pool) > 0
    error_message = "floating_ip_pool 不能為空。"
  }
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
