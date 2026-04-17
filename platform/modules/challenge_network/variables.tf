variable "network_name" {
  description = "共享網段名稱。chell, ctfd, gamma4-IaC 都用這名字 data source 引用，不靠 ID。"
  type        = string
  default     = "challenge-net"
}

variable "subnet_name" {
  description = "共享子網段名稱"
  type        = string
  default     = "challenge-net-subnet"
}

variable "cidr" {
  description = "CIDR。lab 內連續編號慣例：50 管理、77 gamma4 內、78 player↔challenge、100 ctfd web、200 chell 控制面"
  type        = string
  default     = "192.168.78.0/24"

  validation {
    condition     = can(cidrhost(var.cidr, 0))
    error_message = "必須是合法的 CIDR 格式。"
  }
}

variable "mtu" {
  description = "MTU。本叢集 path MTU ~928，900 是經驗安全值（gamma4-lab-infra 同設定）。"
  type        = number
  default     = 900
}

variable "dns_nameservers" {
  description = "DNS 伺服器（給接這個網段的實例用）"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "target_project_id" {
  description = "RBAC 分享的目標 project ID（ctfd-deployer 所屬 project）"
  type        = string
}
