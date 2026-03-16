#!/bin/bash
# base-setup.sh — 所有題目 image 共用的基礎設定
# 目標：最小化 VM 開機時間，讓 snapshot boot 後最快提供題目服務
#
# 優化紀錄 (2026-03-15):
#   原始 Ubuntu 24.04 boot: ~41s（kernel 6s + systemd/DHCP 35s）
#   優化後目標: ~20-25s
#
# 優化項目：
#   1. cloud-init 最小化（只 write_files + runcmd）
#   2. datasource 限 ConfigDrive（省去 metadata service 探測）
#   3. 停用/移除不必要 systemd services（snapd, ModemManager 等）
#   4. Kernel cmdline 優化（quiet, skip fsck/raid/lvm）
#   5. Initramfs 瘦身（lz4 壓縮, 只含必要 modules）
#   6. systemd timeout 縮短
#   7. Mask networkd-wait-online（最大 systemd 瓶頸之一）
set -euo pipefail

echo "==> [base] 等待 cloud-init 完成..."
sudo cloud-init status --wait || true

echo "==> [base] 更新套件清單..."
sudo apt-get update -qq

echo "==> [base] 安裝常用基礎套件..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl \
  wget \
  net-tools \
  jq \
  unzip \
  > /dev/null

# ══════════════════════════════════════════════════════════
# 1. Cloud-init 最小化
# ══════════════════════════════════════════════════════════
echo "==> [base] 設定 cloud-init 為最小化模式..."
sudo tee /etc/cloud/cloud.cfg.d/99-challenge-fast-boot.cfg > /dev/null << 'CLOUDCFG'
# Challenge VM fast boot configuration
# cloud-init 只執行最小必要模組
cloud_init_modules:
  - write_files
  - runcmd

cloud_config_modules: []
cloud_final_modules: []

# ConfigDrive only：metadata 從掛載的 ISO 讀取
# 不探測 metadata service（省 ~2-5s）
datasource_list: [ ConfigDrive, None ]

# 停用不必要的 cloud-init 功能
apt:
  preserve_sources_list: true
manage_etc_hosts: false
disable_ec2_metadata: true
CLOUDCFG

# ══════════════════════════════════════════════════════════
# 2. 停用不必要的 systemd services
# ══════════════════════════════════════════════════════════
echo "==> [base] 停用不必要的 systemd services..."
# 保留：systemd-networkd, systemd-resolved, cloud-init, sshd, cron, challenge.service

# ── Snap（最大 boot 開銷）──
sudo systemctl disable --now snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
sudo systemctl mask snapd.service snapd.socket 2>/dev/null || true
sudo apt-get purge -y -qq snapd 2>/dev/null || true
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd

# ── 硬體管理（VM 不需要）──
sudo systemctl mask ModemManager.service udisks2.service multipathd.service multipathd.socket 2>/dev/null || true

# ── 自動更新 ──
sudo systemctl mask unattended-upgrades.service 2>/dev/null || true
sudo systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

# ── 雜項 ──
sudo systemctl mask polkit.service packagekit.service accounts-daemon.service 2>/dev/null || true
sudo systemctl disable man-db.timer motd-news.timer fstrim.timer e2scrub_all.timer 2>/dev/null || true
sudo systemctl disable dpkg-db-backup.timer sysstat-collect.timer sysstat-summary.timer 2>/dev/null || true
sudo systemctl disable update-notifier-download.timer update-notifier-motd.timer 2>/dev/null || true
sudo systemctl disable fwupd-refresh.timer 2>/dev/null || true

# ── networkd-wait-online（重要！這個 service 等所有介面就緒，預設 timeout 120s）──
sudo systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

# ── Plymouth（boot splash，VM 不需要）──
sudo systemctl mask plymouth-quit.service plymouth-quit-wait.service 2>/dev/null || true

# ── LVM/fsck（VM 用簡單 ext4，不需要）──
sudo systemctl mask lvm2-monitor.service 2>/dev/null || true

# ══════════════════════════════════════════════════════════
# 3. Kernel 命令列優化
# ══════════════════════════════════════════════════════════
echo "==> [base] 優化 kernel 開機參數..."
# quiet: 減少 console 輸出（serial I/O 瓶頸）
# nomodeset: 跳過 GPU/framebuffer 初始化
# raid/lvm/luks: 跳過不需要的 storage 偵測
# fsck.mode=skip: 跳過檔案系統檢查（CTF VM 生命週期短）
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 nomodeset raid=noautodetect rd.lvm=0 rd.md=0 rd.luks=0 fsck.mode=skip plymouth.enable=0 systemd.show_status=auto"/' /etc/default/grub
sudo update-grub 2>/dev/null || true

# ══════════════════════════════════════════════════════════
# 4. Initramfs 瘦身
# ══════════════════════════════════════════════════════════
echo "==> [base] 最佳化 initramfs..."
# MODULES=dep: 只包含偵測到的硬體 modules（不包含所有 generic modules）
# COMPRESS=lz4: 比預設 zstd 解壓更快
sudo sed -i 's/^MODULES=.*/MODULES=dep/' /etc/initramfs-tools/initramfs.conf 2>/dev/null || true
sudo sed -i 's/^COMPRESS=.*/COMPRESS=lz4/' /etc/initramfs-tools/initramfs.conf 2>/dev/null || true
# 確保 lz4 可用
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq lz4 > /dev/null 2>&1 || true
sudo update-initramfs -u 2>/dev/null || true

# ══════════════════════════════════════════════════════════
# 5. Systemd timeout 縮短
# ══════════════════════════════════════════════════════════
echo "==> [base] 縮短 systemd timeout..."
sudo mkdir -p /etc/systemd/system.conf.d
sudo tee /etc/systemd/system.conf.d/99-fast-boot.conf > /dev/null << 'SYSTEMDCFG'
[Manager]
# 預設 90s → 10s：CTF VM 不需要等那麼久
DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=5s
DefaultDeviceTimeoutSec=5s
SYSTEMDCFG

echo "==> [base] 基礎設定完成"
