#cloud-config
# k3s agent (worker) cloud-init
# Terraform templatefile 變數：timezone, k3s_token, k3s_version, master_fixed_ip

timezone: ${timezone}

# ── DNS 設定 ──────────────────────────────────────────────
manage_resolv_conf: true
resolv_conf:
  nameservers:
%{ for ns in dns_nameservers ~}
    - ${ns}
%{ endfor ~}

# ── MTU + MSS clamp（必須在 apt 前） ─────────────────────
# bootcmd 每次 boot 都跑（idempotent）。不靠 DHCP 派 MTU。
bootcmd:
  - 'PRIMARY_IF=$(ip route show default | awk "{print \$5; exit}"); ip link set "$PRIMARY_IF" mtu ${network_mtu}'
  - 'iptables -t mangle -C POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu'

package_update: true
package_upgrade: true

packages:
  - curl
  - wget
  - open-iscsi
  - nfs-common
  - netcat-openbsd

write_files:
%{~ if registry_ip != "" }
  - path: /etc/rancher/k3s/registries.yaml
    permissions: '0644'
    owner: root:root
    content: |
      mirrors:
        "${registry_ip}:5000":
          endpoint:
            - "http://${registry_ip}:5000"
%{~ endif }
  - path: /opt/k3s-agent-init.sh
    permissions: '0755'
    owner: root:root
    content: |
      #!/bin/bash
      set -euo pipefail
      LOG=/var/log/k3s-init.log
      exec > >(tee -a "$LOG") 2>&1

      echo "==> [$(date)] k3s agent installation starting..."
      echo "    joining master at: ${master_fixed_ip}:6443"
      %{~ if k3s_version != "" }
      echo "    k3s version (pinned): ${k3s_version}"
      %{~ else }
      echo "    k3s version: latest stable"
      %{~ endif }

      echo "==> Waiting for k3s master API to be reachable..."
      RETRY=0
      until nc -z "${master_fixed_ip}" 6443 2>/dev/null; do
        RETRY=$((RETRY + 1))
        if [ "$RETRY" -ge 60 ]; then
          echo "ERROR: master API not reachable after 10 minutes, aborting."
          exit 1
        fi
        echo "  ... attempt $RETRY, retrying in 10s ..."
        sleep 10
      done
      echo "==> master API is reachable, joining cluster..."

      %{~ if k3s_version != "" }
      export INSTALL_K3S_VERSION="${k3s_version}"
      %{~ endif }

      # Pin k3s INTERNAL-IP to the primary (default-route) interface.
      # Without this, when the worker has a second NIC on challenge-net,
      # k3s races on DHCP and may pick the challenge-net IP as INTERNAL-IP,
      # causing cross-node pod traffic to tunnel via challenge-net instead
      # of chell-network's control plane.
      PRIMARY_IF=$(ip route show default | awk '{print $5; exit}')
      NODE_IP=$(ip -4 -o addr show "$PRIMARY_IF" | awk '{print $4}' | cut -d/ -f1)
      echo "    node-ip (auto-detected): $NODE_IP (on $PRIMARY_IF)"

      # --with-node-id appends a stable hash suffix to the node name (e.g.
      # chell-worker-1-abc123). This prevents the "Node password rejected,
      # duplicate hostname" error when an existing worker is force-replaced
      # by tofu (the rebuilt VM keeps the same hostname but generates a new
      # node-password; the suffix makes it register as a new node so the
      # master's stale node-passwd entry is sidestepped).
      curl -sfL https://get.k3s.io | \
        K3S_URL="https://${master_fixed_ip}:6443" \
        K3S_TOKEN="${k3s_token}" \
        sh -s - agent \
          --node-ip "$NODE_IP" \
          --with-node-id

      echo "==> [$(date)] k3s agent joined cluster successfully."

runcmd:
  # MTU + MSS 已在 bootcmd 套用（每次 boot 自動 idempotent 套）
  - /opt/k3s-agent-init.sh

final_message: "k3s agent joined cluster (master=${master_fixed_ip}), uptime=$${UPTIME}s"
