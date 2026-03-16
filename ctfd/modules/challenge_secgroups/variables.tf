# modules/challenge_secgroups/variables.tf

variable "name_prefix" {
  description = "SG 名稱前綴"
  type        = string
  default     = "ctf"
}
