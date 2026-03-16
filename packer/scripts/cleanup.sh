#!/bin/bash
# cleanup.sh — 清理暫存檔案，縮小 snapshot image 大小
set -euo pipefail

echo "==> [cleanup] 清理 apt cache..."
sudo apt-get autoremove -y -qq > /dev/null
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "==> [cleanup] 清理暫存檔案..."
sudo rm -rf /tmp/* /var/tmp/*

echo "==> [cleanup] 清除 shell history..."
history -c || true
cat /dev/null > ~/.bash_history || true
sudo tee /root/.bash_history < /dev/null > /dev/null || true

echo "==> [cleanup] 清除 cloud-init 狀態（下次 boot 視為首次啟動）..."
sudo cloud-init clean --logs

echo "==> [cleanup] 清理完成，image 準備就緒"
