# ctfd-openstack/modules/network/variables.tf

variable "network_name" {
  description = "內部網路名稱"
  type        = string
  default     = "ctfd-network"
}

variable "subnet_name" {
  description = "內部子網路名稱"
  type        = string
  default     = "ctfd-subnet"
}

variable "subnet_cidr" {
  description = "內部網路 CIDR（例如 192.168.100.0/24）"
  type        = string
  default     = "192.168.100.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "必須是合法的 CIDR 格式，例如 192.168.100.0/24。"
  }
}

variable "dns_nameservers" {
  description = "DNS 伺服器清單"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "router_name" {
  description = "Router 名稱"
  type        = string
  default     = "ctfd-router"
}

variable "external_network_id" {
  description = "外部網路 ID（從 platform 的 output 取得）"
  type        = string

  validation {
    condition     = length(var.external_network_id) > 0
    error_message = "external_network_id 不能為空，請從 platform output 取得。"
  }
}
