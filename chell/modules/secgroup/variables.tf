# chell/modules/secgroup/variables.tf

variable "secgroup_name" {
  description = "Security Group 名稱"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "允許 SSH 和 kubectl 管理連入的來源 CIDR"
  type        = string
  default     = "0.0.0.0/0"
}
