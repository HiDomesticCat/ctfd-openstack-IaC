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
  default     = "~/.ssh/id_rsa.pub"

  validation {
    condition     = length(var.public_key_path) > 0
    error_message = "public_key_path 不能為空。"
  }
}

# ── Network 開關 ─────────────────────────────────────────────

variable "use_shared_network" {
  description = "是否使用現有 shared network（true=引用，false=自建 network + router）"
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

variable "k3s_subnet_cidr" {
  description = "k3s 內部網路 CIDR（自建網路模式）"
  type        = string
  default     = "192.168.200.0/24"

  validation {
    condition     = can(cidrhost(var.k3s_subnet_cidr, 0))
    error_message = "k3s_subnet_cidr 必須是合法的 CIDR 格式，例如 192.168.200.0/24。"
  }
}

variable "master_fixed_ip" {
  description = "k3s master 節點固定 IP（自建網路模式，worker cloud-init 會用此 IP join 叢集）"
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
  description = "VM image ID（從 platform output 取得）"
  type        = string

  validation {
    condition     = length(var.image_id) > 0
    error_message = "image_id 不能為空，請從 platform output 取得。"
  }
}

variable "master_flavor" {
  description = "k3s master 節點 VM 規格（建議 >= 2 vCPU, 4GB RAM）"
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
  description = "Floating IP 所在的外部網路名稱"
  type        = string
  default     = "public"

  validation {
    condition     = length(var.floating_ip_pool) > 0
    error_message = "floating_ip_pool 不能為空。"
  }
}

# ── Bastion ───────────────────────────────────────────────

variable "bastion_ip" {
  description = "Bastion/Jump host IP（use_fip=false 時，Ansible 透過此 IP 跳板 SSH）"
  type        = string
  default     = ""
}

# ── FIP 開關 ──────────────────────────────────────────────

variable "use_fip" {
  description = "是否建立 Floating IP（false=用內網 IP，透過 bastion 管理）"
  type        = bool
  default     = true
}

# ── Volume Boot ───────────────────────────────────────────

variable "boot_from_volume" {
  description = "是否從 volume 開機（flavor disk=0 的環境必須設 true）"
  type        = bool
  default     = false
}

variable "volume_size" {
  description = "k3s 節點 volume 大小（GB），boot_from_volume=true 時使用"
  type        = number
  default     = 20
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
