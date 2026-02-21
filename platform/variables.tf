# platform/variables.tf

variable "environment" {
  description = "環境名稱（dev, staging, production）"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "環境必須是 dev、staging 或 production。"
  }
}

variable "openstack_cloud" {
  description = "OpenStack cloud 名稱（對應 ~/.config/openstack/clouds.yaml）"
  type        = string
  default     = "openstack"
}

variable "external_subnet_cidr" {
  description = "外部網路 CIDR"
  type        = string
  default     = "10.0.2.0/24"

  validation {
    condition     = can(cidrhost(var.external_subnet_cidr, 0))
    error_message = "必須是合法的 CIDR 格式。"
  }
}

variable "external_gateway_ip" {
  description = "外部網路 Gateway，對應 PVE vmbr1"
  type        = string
  default     = "10.0.2.1"
}

variable "external_pool_start" {
  description = "Floating IP 池起始 IP"
  type        = string
  default     = "10.0.2.150"
}

variable "external_pool_end" {
  description = "Floating IP 池結束 IP"
  type        = string
  default     = "10.0.2.199"
}

variable "dns_nameservers" {
  description = "DNS 伺服器"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "physical_network" {
  description = "實體網路名稱"
  type        = string
  default     = "physnet1"
}

variable "network_type" {
  description = "外部網路類型"
  type        = string
  default     = "flat"
}

variable "images" {
  description = "要上傳到 OpenStack 的 image 定義"
  type = map(object({
    name             = string
    source_url       = string
    container_format = string
    disk_format      = string
    visibility       = string
    min_disk_gb      = number
    min_ram_mb       = number
    properties       = map(string)
  }))
}

variable "flavors" {
  description = "要建立的 flavor 定義"
  type = map(object({
    name      = string
    ram       = number
    vcpus     = number
    disk      = number
    is_public = bool
  }))
}

variable "ctfd_deployer_password" {
  description = "CTFd 部署帳號的密碼"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.ctfd_deployer_password) >= 12
    error_message = "密碼長度至少 12 個字元。"
  }
}
