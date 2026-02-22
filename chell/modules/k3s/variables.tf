# chell/modules/k3s/variables.tf

variable "master_name" {
  description = "k3s master 節點名稱"
  type        = string
}

variable "worker_name" {
  description = "k3s worker 節點名稱前綴（後綴會加 -1, -2, ...）"
  type        = string
}

variable "image_id" {
  description = "VM Image ID"
  type        = string
}

variable "master_flavor" {
  description = "master 節點 VM 規格"
  type        = string
}

variable "worker_flavor" {
  description = "worker 節點 VM 規格"
  type        = string
}

variable "worker_count" {
  description = "worker 節點數量"
  type        = number
}

variable "keypair_name" {
  description = "SSH Keypair 名稱"
  type        = string
}

variable "secgroup_id" {
  description = "Security Group ID"
  type        = string
}

variable "network_id" {
  description = "k3s 內部網路 ID"
  type        = string
}

variable "subnet_id" {
  description = "k3s 子網路 ID（master port 固定 IP 使用）"
  type        = string
}

variable "master_fixed_ip" {
  description = "master 節點固定 IP"
  type        = string
}

variable "floating_ip_pool" {
  description = "Floating IP 外部網路名稱"
  type        = string
}

variable "k3s_token" {
  description = "k3s cluster 預共享 Token"
  type        = string
  sensitive   = true
}

variable "k3s_version" {
  description = "k3s 版本（留空使用最新穩定版）"
  type        = string
  default     = ""
}

variable "timezone" {
  description = "VM 時區"
  type        = string
  default     = "Asia/Taipei"
}
