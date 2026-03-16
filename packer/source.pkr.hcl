# OpenStack source：Packer 用來建立 build VM 的設定
# 所有題目共用此 source，透過 variables 差異化

source "openstack" "challenge" {
  # ── OpenStack 認證 ──────────────────────────────────────
  identity_endpoint = var.openstack_auth_url
  username          = var.openstack_username
  password          = var.openstack_password
  tenant_name       = var.openstack_project_name
  region            = var.openstack_region
  domain_name       = var.openstack_domain

  # ── Build VM 規格 ──────────────────────────────────────
  source_image      = var.source_image_id
  flavor            = var.flavor
  networks          = [var.network_id]
  security_groups   = var.security_groups
  ssh_username      = var.ssh_username

  # ── 輸出 image 設定 ────────────────────────────────────
  # 格式：challenge-<name>-<timestamp>（如 challenge-web-sqli-20260312-153000）
  image_name       = "challenge-${var.challenge_name}-${formatdate("YYYYMMDD-HHmmss", timestamp())}"
  image_visibility = "private"

  metadata = {
    challenge_name = var.challenge_name
    challenge_port = "${var.challenge_port}"
    description    = var.challenge_description
    built_by       = "packer"
    built_at       = timestamp()
  }

  # ── SSH / Floating IP ──────────────────────────────────
  ssh_timeout      = "10m"
  floating_ip_pool = var.floating_ip_pool
}
