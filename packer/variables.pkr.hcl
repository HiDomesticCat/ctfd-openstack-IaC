# Packer 變數定義
# OpenStack 憑證由 credentials.auto.pkrvars.hcl 提供（gitignored）
# 題目設定由 challenges/<name>/packer/challenge.pkrvars.hcl 提供

# ── OpenStack 認證 ────────────────────────────────────────
variable "openstack_auth_url" {
  type        = string
  description = "OpenStack Keystone endpoint（如 http://192.168.15.200:5000/v3）"
}

variable "openstack_username" {
  type        = string
  description = "OpenStack 使用者名稱"
}

variable "openstack_password" {
  type        = string
  sensitive   = true
  description = "OpenStack 密碼"
}

variable "openstack_project_name" {
  type        = string
  default     = "ctfd"
  description = "OpenStack project"
}

variable "openstack_region" {
  type        = string
  default     = "RegionOne"
  description = "OpenStack region"
}

variable "openstack_domain" {
  type        = string
  default     = "Default"
  description = "OpenStack domain"
}

# ── 基礎 image 設定 ──────────────────────────────────────
variable "source_image_id" {
  type        = string
  description = "來源 image ID（如 Ubuntu 22.04 cloud image，從 platform output 取得）"
}

variable "flavor" {
  type        = string
  default     = "general.small"
  description = "Build VM 使用的 flavor"
}

variable "network_id" {
  type        = string
  description = "Build VM 連接的 network ID（使用 CTFd 內部網路）"
}

variable "floating_ip_pool" {
  type        = string
  default     = "public"
  description = "Packer SSH 連線用的 FIP pool"
}

variable "security_groups" {
  type        = list(string)
  default     = ["ctf-allow-web"]
  description = "Build VM 使用的 security groups（需包含 SSH）"
}

variable "ssh_username" {
  type        = string
  default     = "ubuntu"
  description = "SSH 使用者名稱（Ubuntu cloud image 預設為 ubuntu）"
}

# ── 題目設定（由 challenge.pkrvars.hcl 覆蓋）────────────
variable "challenge_name" {
  type        = string
  description = "題目名稱（用於 image 命名，如 web-sqli, linux-privesc）"
}

variable "challenge_description" {
  type        = string
  default     = ""
  description = "題目描述（寫入 image metadata）"
}

variable "provision_scripts" {
  type        = list(string)
  default     = []
  description = "題目專屬 provisioning scripts 路徑列表（相對於 packer/ 目錄）"
}

variable "provision_inline" {
  type        = list(string)
  default     = []
  description = "行內 provisioning 指令（簡單題目不需要獨立 script 時使用）"
}

variable "challenge_port" {
  type        = number
  default     = 8080
  description = "題目服務 port（寫入 image metadata，供出題者參考）"
}

variable "challenge_files" {
  type        = string
  default     = ""
  description = "題目檔案目錄路徑（如 ../challenges/web-example/src/），會複製到 VM 的 /tmp/challenge-files/"
}
