# ctfd-openstack/modules/secgroup/variables.tf

variable "secgroup_name" {
  description = "Security Group 名稱"
  type        = string
  default     = "ctfd-sg"
}

variable "secgroup_description" {
  description = "Security Group 說明"
  type        = string
  default     = "CTFd Server Security Group"
}

variable "ssh_allowed_cidr" {
  description = "允許 SSH 連入的來源 CIDR（建議限制為管理 IP，不要用 0.0.0.0/0）"
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
