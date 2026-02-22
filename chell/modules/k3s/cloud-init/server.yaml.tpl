#cloud-config
# k3s server (master) cloud-init
# ─────────────────────────────────────────────────────────────
# Terraform templatefile 變數：
#   timezone           VM 時區（如 Asia/Taipei）
#   k3s_token          叢集預共享 token（server 與 agent 認證用）
#   k3s_version        k3s 版本號（空字串 = 最新穩定版）
#   master_fixed_ip    master 節點固定 IP（192.168.200.10，worker join 目標）
#   master_floating_ip master 節點 Floating IP（kubeconfig + TLS SAN）
#
# 安裝流程：
#   1. 安裝基礎套件
#   2. 執行 /opt/k3s-server-init.sh（runcmd）
#   3. k3s-server-init.sh：安裝 k3s server → 等待 Ready → 產生 kubeconfig
#
# ⚠️  SECURITY NOTE: k3s_token 會被記錄到 /var/log/k3s-init.log
# 此為 cloud-init exec 日誌的固有行為，無法避免。
# 建議賽事結束後執行以下操作降低風險：
#   sudo truncate -s 0 /var/log/k3s-init.log
#   # 若需輪換 token，需重建 k3s 叢集
#
# kubeconfig 已替換為 floating IP（master_floating_ip），
# 供外部（Ansible、chall-manager）透過公網 IP 存取 k3s API。
# ─────────────────────────────────────────────────────────────

timezone: ${timezone}

package_update: true
package_upgrade: true

packages:
  - curl
  - wget
  - git
  - open-iscsi
  - nfs-common
  - jq
  - netcat-openbsd

write_files:
  - path: /opt/k3s-server-init.sh
    permissions: '0755'
    owner: root:root
    content: |
      #!/bin/bash
      set -euo pipefail
      LOG=/var/log/k3s-init.log
      exec > >(tee -a "$LOG") 2>&1

      echo "==> [$(date)] k3s server installation starting..."
      echo "    master internal IP : ${master_fixed_ip}"
      echo "    master floating IP : ${master_floating_ip}"
      %{~ if k3s_version != "" }
      echo "    k3s version (pinned): ${k3s_version}"
      export INSTALL_K3S_VERSION="${k3s_version}"
      %{~ else }
      echo "    k3s version: latest stable"
      %{~ endif }

      curl -sfL https://get.k3s.io | \
        K3S_TOKEN="${k3s_token}" \
        sh -s - server \
          --node-ip "${master_fixed_ip}" \
          --advertise-address "${master_fixed_ip}" \
          --tls-san "${master_fixed_ip}" \
          --tls-san "${master_floating_ip}" \
          --disable traefik \
          --disable servicelb \
          --write-kubeconfig-mode 644

      echo "==> Waiting for k3s API to be ready..."
      until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
        echo "  ... still initializing ..."
        sleep 5
      done

      echo "==> k3s cluster nodes:"
      kubectl get nodes -o wide

      echo "==> Preparing kubeconfig for ubuntu user (with external IP)..."
      mkdir -p /home/ubuntu/.kube
      sed "s/127.0.0.1/${master_floating_ip}/g" /etc/rancher/k3s/k3s.yaml \
        > /home/ubuntu/.kube/config
      chown -R ubuntu:ubuntu /home/ubuntu/.kube
      chmod 600 /home/ubuntu/.kube/config

      echo "==> [$(date)] k3s server ready!"
      echo "    kubectl API : https://${master_floating_ip}:6443"
      echo "    kubeconfig  : /home/ubuntu/.kube/config"

runcmd:
  - /opt/k3s-server-init.sh

final_message: "k3s master ready. API=https://${master_floating_ip}:6443, uptime=$${UPTIME}s"
