variable "network_name" {
  description = "外部網路名稱"
  type        = string
  default     = "public"
}

variable "subnet_name" {
  description = "外部子網路名稱"
  type        = string
  default     = "public-subnet"
}

variable "subnet_cidr" {
  description = "外部網路 CIDR，必須與 PVE vmbr1 網段一致"
  type        = string

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "必須是合法的 CIDR 格式，例如 10.0.2.0/24。"
  }
}

variable "gateway_ip" {
  description = "Gateway IP，對應 PVE vmbr1 的 IP"
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.gateway_ip))
    error_message = "必須是合法的 IP 格式。"
  }
}

variable "allocation_pool_start" {
  description = "Floating IP 可用範圍起始"
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.allocation_pool_start))
    error_message = "必須是合法的 IP 格式。"
  }
}

variable "allocation_pool_end" {
  description = "Floating IP 可用範圍結束"
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.allocation_pool_end))
    error_message = "必須是合法的 IP 格式。"
  }
}

variable "dns_nameservers" {
  description = "DNS 伺服器清單"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "physical_network" {
  description = "實體網路名稱，對應 Kolla 的 neutron_external_interface"
  type        = string
  default     = "physnet1"
}

variable "network_type" {
  description = "網路類型，外部網路固定用 flat"
  type        = string
  default     = "flat"

  validation {
    condition     = contains(["flat", "vlan", "vxlan", "gre"], var.network_type)
    error_message = "network_type 必須是 flat、vlan、vxlan 或 gre。"
  }
}