# ctfd-openstack/modules/instance/variables.tf

variable "instance_name" {
  description = "VM 名稱"
  type        = string
  default     = "ctfd-server"
}

variable "image_id" {
  description = "VM 使用的 image ID（從 platform output 或 terraform.tfvars 取得）"
  type        = string

  validation {
    condition     = length(var.image_id) > 0
    error_message = "image_id 不能為空。"
  }
}

variable "flavor_name" {
  description = "VM 規格名稱（例如 general.medium）"
  type        = string
  default     = "general.medium"
}

variable "keypair_name" {
  description = "SSH Keypair 名稱（由 keypair 模組產生）"
  type        = string
}

variable "secgroup_name" {
  description = "Security Group 名稱（由 secgroup 模組產生）。VM instance-level security_groups 用。"
  type        = string
}

variable "secgroup_id" {
  description = "Security Group UUID（由 secgroup 模組產生）。Pre-built challenge-net port 需顯式指定 security_group_ids，否則 fallback 到 default secgroup，cm-proxy 8443/5443 rules 不生效。"
  type        = string
  default     = ""
}

variable "network_id" {
  description = "VM 要接上的內部網路 ID（由 network 模組產生）"
  type        = string
}

variable "use_floating_ip" {
  description = "是否配置 Floating IP（false=僅 SNAT 聯外）"
  type        = bool
  default     = true
}

variable "floating_ip_pool" {
  description = "Floating IP 所在的外部網路名稱（use_floating_ip=true 時使用）"
  type        = string
  default     = "public"
}

# ── Management Network（OpenStack API 可達性）────────────

variable "mgmt_network_id" {
  description = "管理網路 ID（讓 VM 能連到 OpenStack API，空字串=不接）"
  type        = string
  default     = ""
}

variable "mgmt_routes" {
  description = "管理網卡的靜態路由（如到 OpenStack API 網段）"
  type = list(object({
    to  = string  # 目標網段，如 "192.168.50.0/24"
    via = string  # gateway，如 "192.168.235.1"
  }))
  default = []
}

# ── Challenge-net secondary NIC（Phase 3 α-exposure）─────────
# When non-empty, CTFd VM gets a 3rd port on the shared challenge-net subnet
# (192.168.78.0/24). Purpose: cm-proxy Caddy (8443/5443) binds here so the
# gamma4 research VM can reach chall-manager + registry without traversing
# the FIP (which would need NAT hairpin and break IP-restricted secgroup).
# Empty string = not attached (default; maintains pre-Phase-3 behaviour).

variable "challenge_net_id" {
  description = "OpenStack network UUID of the challenge-net shared subnet. Leave empty to skip the 3rd NIC (pre-Phase-3 behaviour). When set, the CTFd VM gets a pre-built port on this network so cm-proxy Caddy can bind to the challenge-net fixed IP."
  type        = string
  default     = ""
}

variable "challenge_net_subnet_id" {
  description = "OpenStack subnet UUID inside challenge_net_id. Required when challenge_net_fixed_ip is set, ignored otherwise. Typically fetched via `data \"openstack_networking_subnet_v2\"` in the parent module and passed in."
  type        = string
  default     = ""
}

variable "challenge_net_fixed_ip" {
  description = "Pin a specific IP on the challenge-net port so the address survives VM rebuilds AND `tofu destroy`+`tofu apply`. Empty = let neutron allocate (stable across VM rebuilds only). Paper-grade reproducibility wants this set to a specific /32 like \"192.168.78.162\"."
  type        = string
  default     = ""
}

# ── Volume Boot ───────────────────────────────────────────

variable "boot_from_volume" {
  description = "是否從 volume 開機（flavor disk=0 的環境必須設 true）"
  type        = bool
  default     = false
}

variable "volume_size" {
  description = "Volume 大小（GB），boot_from_volume=true 時使用"
  type        = number
  default     = 20
}

# ── DNS ────────────────────────────────────────────────────

variable "dns_nameservers" {
  description = "DNS 伺服器清單（cloud-init + Docker daemon 使用）"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "network_mtu" {
  description = "網路 MTU（Docker daemon MTU = network_mtu - 40）"
  type        = number
  default     = 1450
}

# ── Cloud-init ─────────────────────────────────────────────

variable "timezone" {
  description = "VM 時區（cloud-init 設定）"
  type        = string
  default     = "Asia/Taipei"
}

variable "deploy_dir" {
  description = "CTFd 部署目錄路徑（cloud-init 建立）"
  type        = string
  default     = "/opt/ctfd"

  validation {
    condition     = startswith(var.deploy_dir, "/")
    error_message = "deploy_dir 必須是絕對路徑（以 / 開頭）。"
  }
}
