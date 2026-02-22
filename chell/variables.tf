# chell/variables.tf

# ── Provider ───────────────────────────────────────────────
variable "openstack_cloud" {
  description = "clouds.yaml 中的 cloud entry 名稱（與 ctfd 層共用同一帳號）"
  type        = string
  default     = "ctfd"
}

# ── Keypair ────────────────────────────────────────────────
variable "keypair_name" {
  description = "k3s 節點 SSH Keypair 名稱"
  type        = string
  default     = "chell-key"

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

variable "k3s_subnet_cidr" {
  description = "k3s 內部網路 CIDR（不得與 ctfd 子網路 192.168.100.0/24 衝突）"
  type        = string
  default     = "192.168.200.0/24"

  validation {
    condition     = can(cidrhost(var.k3s_subnet_cidr, 0))
    error_message = "k3s_subnet_cidr 必須是合法的 CIDR 格式，例如 192.168.200.0/24。"
  }
}

variable "master_fixed_ip" {
  description = "k3s master 節點固定 IP（須在 k3s_subnet_cidr 範圍內，worker cloud-init 會用此 IP join 叢集）"
  type        = string
  default     = "192.168.200.10"

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.master_fixed_ip))
    error_message = "master_fixed_ip 必須是合法的 IPv4 位址。"
  }
}

variable "dns_nameservers" {
  description = "DNS 伺服器清單"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

# ── Security ───────────────────────────────────────────────
variable "ssh_allowed_cidr" {
  description = "允許 SSH/kubectl 管理的來源 CIDR（建議限制為管理 IP）"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr 必須是合法的 CIDR 格式。"
  }
}

# ── Instance ───────────────────────────────────────────────
variable "image_id" {
  description = "VM image ID（從 platform output 取得：module.images.image_ids[\"ubuntu\"]）"
  type        = string

  validation {
    condition     = length(var.image_id) > 0
    error_message = "image_id 不能為空，請從 platform output 取得。"
  }
}

variable "master_flavor" {
  description = "k3s master 節點 VM 規格（建議 ≥ 2 vCPU, 4GB RAM）"
  type        = string
  default     = "general.medium"
}

variable "worker_flavor" {
  description = "k3s worker 節點 VM 規格（challenge 容器運行於此）"
  type        = string
  default     = "general.medium"
}

variable "worker_count" {
  description = "k3s worker 節點數量（決定可同時執行的 challenge 容量）"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 10
    error_message = "worker_count 必須介於 1 到 10 之間。"
  }
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

# ── k3s ────────────────────────────────────────────────────
variable "k3s_token" {
  description = "k3s cluster 預共享 Token（server 與 agent 認證用，請使用強密碼，至少 32 字元）"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.k3s_token) >= 16
    error_message = "k3s_token 長度至少 16 字元，建議使用隨機強密碼（openssl rand -hex 32）。"
  }
}

variable "k3s_version" {
  description = "k3s 版本，例如 v1.31.4+k3s1。留空使用最新穩定版（不建議生產環境）"
  type        = string
  default     = ""
}

# ── Cloud-init ─────────────────────────────────────────────
variable "timezone" {
  description = "VM 時區"
  type        = string
  default     = "Asia/Taipei"
}
