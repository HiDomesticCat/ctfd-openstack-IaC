# ctfd/variables.tf

# ── Provider ───────────────────────────────────────────────
variable "openstack_cloud" {
  description = "clouds.yaml 中的 cloud entry 名稱（對應 ctfd-deployer 帳號）"
  type        = string
  default     = "ctfd"
}

# ── Keypair ────────────────────────────────────────────────
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
  description = "SSH 公鑰絕對路徑（例如 /home/user/.ssh/id_rsa.pub）"
  type        = string
  default     = "~/.ssh/id_rsa.pub"

  validation {
    condition     = length(var.public_key_path) > 0
    error_message = "public_key_path 不能為空。"
  }
}

# ── Network 開關 ─────────────────────────────────────────────

variable "use_shared_network" {
  description = "是否使用現有 shared network（true=引用 shared network，false=自建 network + router）"
  type        = bool
  default     = false
}

variable "shared_network_name" {
  description = "引用的 shared network 名稱（use_shared_network=true 時必填）"
  type        = string
  default     = ""
}

# ── 玩家↔題目共享網段（Phase 3+）────────────────────────────

variable "use_challenge_network_for_scenarios" {
  description = "openstack-vm scenario 部署題目時是否預設使用 challenge-net（玩家↔題目共享網段）。true（建議）= 題目實例放在 challenge-net，gamma4 上的 Caldera 直接打。false = 落回 ctfd-network，僅 debug 用。出題者仍可在 CTFd Advanced 區塊用 additional.network_id 個案覆蓋。"
  type        = bool
  default     = true
}

variable "challenge_network_name" {
  description = "玩家↔題目共享網段名稱（admin 在 platform/ 創、RBAC share 過來）。data source 用名字引用。"
  type        = string
  default     = "challenge-net"
}

# ── Phase 3 α-exposure（gamma4 research VM 整合）──────────────
# 當為 true：CTFd VM 在 challenge-net (192.168.78.0/24) 上加一張 NIC，
# ansible 的 cm-proxy role 會把 Caddy 綁在該 IP，提供 basic-auth 反代給
# 外部可達的 chall-manager (8443) 和 registry (5443)。目的是讓 gamma4 VM
# （也在 challenge-net）能不繞 FIP、不 NAT hairpin 地直接呼叫。
#
# 預設 false：維持 Phase 1-2 行為，不動既有部署。打開前要：
#   1. 設定 cm_proxy_allowed_cidr（限制 8443/5443 只給 gamma4 VM 的 challenge-net IP/32）
#   2. ansible-vault 裡填 vault_cm_proxy_basic_auth_hash（bcrypt）+ password
#   3. tofu apply（CTFd VM 會新增 port，VM 本身會 in-place update，不 rebuild）
#   4. ansible-playbook site.yml（cm-proxy role 部署 Caddy）
#   5. 從 ctfd output 取 challenge_net_ip，填進 gamma4-lab-infra/terraform.tfvars
variable "expose_cm_proxy_to_challenge_net" {
  description = "Phase 3: CTFd VM 是否在 challenge-net 上加第二 NIC + 由 cm-proxy Caddy 對外暴露 chall-manager/registry（basic-auth 保護）。需搭配 use_challenge_network_for_scenarios=true。"
  type        = bool
  default     = false
}

variable "cm_proxy_allowed_cidr" {
  description = "允許存取 cm-proxy (8443/5443) 的來源 CIDR，建議設為 gamma4 VM 的 challenge-net /32（e.g. \"192.168.78.17/32\"）。空字串=不建立規則（適用於 expose_cm_proxy_to_challenge_net=false 時）。"
  type        = string
  default     = ""

  validation {
    condition     = var.cm_proxy_allowed_cidr == "" || can(cidrhost(var.cm_proxy_allowed_cidr, 0))
    error_message = "cm_proxy_allowed_cidr 必須是合法的 CIDR 格式，或空字串。"
  }
}

variable "cm_proxy_chall_manager_port" {
  description = "cm-proxy Caddy 對外聽的 chall-manager 反代 port。預設 8443（HTTP + basic-auth，internal net 不需 TLS）。"
  type        = number
  default     = 8443
}

variable "cm_proxy_registry_port" {
  description = "cm-proxy Caddy 對外聽的 registry 反代 port。預設 5443（HTTP + basic-auth）。gamma4 VM 必須把這個 host:port 加進 Docker insecure-registries。"
  type        = number
  default     = 5443
}

variable "cm_proxy_fixed_ip" {
  description = "Phase 3: pin the CTFd VM's challenge-net IP to a specific address so it survives `tofu destroy` + re-apply. Empty = let neutron allocate (stable across VM rebuilds only, drift on full destroy). Paper reproducibility wants this set."
  type        = string
  default     = ""

  validation {
    condition     = var.cm_proxy_fixed_ip == "" || can(cidrhost("${var.cm_proxy_fixed_ip}/32", 0))
    error_message = "cm_proxy_fixed_ip must be a valid IPv4 address or empty."
  }
}

# 以下 variable 僅在 use_shared_network=false 時使用

variable "external_network_id" {
  description = "外部網路 ID（自建網路模式，從 platform output 取得）"
  type        = string
  default     = ""
}

variable "internal_subnet_cidr" {
  description = "CTFd 內部網路 CIDR（自建網路模式）"
  type        = string
  default     = "192.168.100.0/24"

  validation {
    condition     = can(cidrhost(var.internal_subnet_cidr, 0))
    error_message = "必須是合法的 CIDR 格式，例如 192.168.100.0/24。"
  }
}

variable "dns_nameservers" {
  description = "DNS 伺服器清單"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "network_mtu" {
  description = "內部網路 MTU。textbook VXLAN 是 1500-50=1450；本叢集實測 path MTU ~928，請設 900（保留 28 bytes 餘裕）。974 不夠，會讓 HTTPS 大封包 RST。"
  type        = number
  default     = 1450
}

# ── Security Group ─────────────────────────────────────────
variable "ssh_allowed_cidr" {
  description = "允許 SSH 連入的來源 CIDR（建議限制為管理 IP，避免全網際網路暴露）"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr 必須是合法的 CIDR 格式，例如 10.0.0.0/8 或 1.2.3.4/32。"
  }
}

variable "ctfd_port" {
  description = "CTFd 應用程式 Port"
  type        = number
  default     = 8000

  validation {
    condition     = var.ctfd_port >= 1 && var.ctfd_port <= 65535
    error_message = "ctfd_port 必須介於 1 到 65535 之間。"
  }
}

variable "registry_allowed_cidr" {
  description = "允許存取 Docker Registry (5000) 的來源 CIDR（k3s 節點子網，空字串=不建立規則）"
  type        = string
  default     = ""
}

# ── Instance ───────────────────────────────────────────────
variable "instance_name" {
  description = "CTFd VM 名稱"
  type        = string
  default     = "ctfd-server"
}

variable "image_id" {
  description = "VM 使用的 image ID（從 platform output 取得）"
  type        = string

  validation {
    condition     = length(var.image_id) > 0
    error_message = "image_id 不能為空，請從 platform output 取得。"
  }
}

variable "flavor_name" {
  description = "VM 規格名稱"
  type        = string
  default     = "general.medium"
}

variable "use_floating_ip" {
  description = "是否配置 Floating IP（false=僅使用 router SNAT 聯外，無外部 IP 連入）"
  type        = bool
  default     = true
}

variable "floating_ip_pool" {
  description = "Floating IP 所在的外部網路名稱（use_floating_ip=true 時使用）"
  type        = string
  default     = "public"
}

# ── Management Network ────────────────────────────────────

variable "mgmt_network_id" {
  description = "管理網路 ID（讓 VM 能連到 OpenStack API，空字串=不接）"
  type        = string
  default     = ""
}

variable "mgmt_routes" {
  description = "管理網卡的靜態路由"
  type = list(object({
    to  = string
    via = string
  }))
  default = []
}

# ── Volume Boot ───────────────────────────────────────────

variable "boot_from_volume" {
  description = "是否從 volume 開機（flavor disk=0 的環境必須設 true）"
  type        = bool
  default     = false
}

variable "volume_size" {
  description = "CTFd VM volume 大小（GB），boot_from_volume=true 時使用"
  type        = number
  default     = 20
}

# ── Cloud-init ─────────────────────────────────────────────

variable "timezone" {
  description = "VM 時區"
  type        = string
  default     = "Asia/Taipei"
}

variable "deploy_dir" {
  description = "CTFd 部署目錄路徑（cloud-init 自動建立）"
  type        = string
  default     = "/opt/ctfd"

  validation {
    condition     = startswith(var.deploy_dir, "/")
    error_message = "deploy_dir 必須是絕對路徑（以 / 開頭）。"
  }
}
