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

variable "registry_allowed_cidr" {
  description = "允許存取 Docker Registry (5000) 的來源 CIDR（k3s 節點所在子網），空字串=不建立規則"
  type        = string
  default     = ""
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

# ── Phase 3 cm-proxy ingress ─────────────────────────────────

variable "cm_proxy_allowed_cidr" {
  description = "允許存取 cm-proxy (chall-manager + registry 反代) 的來源 CIDR。空字串=不建立規則。建議設為 gamma4 VM 的 challenge-net IP /32。"
  type        = string
  default     = ""
}

variable "cm_proxy_chall_manager_port" {
  description = "cm-proxy 反代 chall-manager 的對外 port。"
  type        = number
  default     = 8443
}

variable "cm_proxy_registry_port" {
  description = "cm-proxy 反代 registry 的對外 port。gamma4 VM 的 Docker insecure-registries 要加上 <challenge_net_ip>:<this_port>。"
  type        = number
  default     = 5443
}
