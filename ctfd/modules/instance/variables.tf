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

variable "floating_ip_pool" {
  description = "Floating IP 所在的外部網路名稱（例如 public）"
  type        = string
  default     = "public"

  validation {
    condition     = length(var.floating_ip_pool) > 0
    error_message = "floating_ip_pool 不能為空。"
  }
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
