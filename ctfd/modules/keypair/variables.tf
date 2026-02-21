# ctfd-openstack/modules/keypair/variables.tf

variable "keypair_name" {
  description = "SSH Keypair 名稱"
  type        = string
  default     = "ctfd-key"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.keypair_name))
    error_message = "keypair_name 只能包含字母、數字、點、底線和連字號。"
  }
}

variable "public_key_path" {
  description = "本機 SSH 公鑰檔案路徑（絕對路徑，例如 /home/user/.ssh/id_rsa.pub）"
  type        = string

  validation {
    condition     = length(var.public_key_path) > 0
    error_message = "public_key_path 不能為空。"
  }
}
