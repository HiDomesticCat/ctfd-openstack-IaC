# chell/modules/network/variables.tf

variable "network_name" {
  description = "k3s 內部網路名稱"
  type        = string
}

variable "subnet_name" {
  description = "k3s 子網路名稱"
  type        = string
}

variable "subnet_cidr" {
  description = "k3s 子網路 CIDR"
  type        = string
}

variable "master_fixed_ip" {
  description = "master 節點固定 IP（用於文件標注，實際由 k3s 模組的 port 設定）"
  type        = string
}

variable "dns_nameservers" {
  description = "DNS 伺服器清單"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "router_name" {
  description = "Router 名稱"
  type        = string
}

variable "external_network_id" {
  description = "外部網路 ID"
  type        = string
}
