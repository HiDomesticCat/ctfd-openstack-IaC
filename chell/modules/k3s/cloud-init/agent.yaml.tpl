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

# ── MTU + MSS clamp + NTP（必須在 apt 前） ────────────────
# bootcmd 每次 boot 都跑（idempotent）。不靠 DHCP 派 MTU。
# NTP 顯式 on：跨 VM 監控研究的 trace/metric correlation 前提。
bootcmd:
  - 'PRIMARY_IF=$(ip route show default | awk "{print \$5; exit}"); ip link set "$PRIMARY_IF" mtu ${network_mtu}'
  - 'iptables -t mangle -C POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu'
  - 'timedatectl set-ntp true'

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

      # Pin BOTH k3s INTERNAL-IP and flannel VXLAN PublicIP to the interface
      # that can reach the master. With two NICs (chell-network + challenge-
      # net), DHCP races put default routes on both — k3s and flannel each
      # silently pick the first one. Without this, observed in practice:
      # worker registers flannel VXLAN PublicIP as the challenge-net IP, the
      # master tries to tunnel pod traffic to 192.168.78.x, the underlay
      # has no route there, packets vanish, all cross-node pod traffic
      # (CoreDNS, helm install, etc.) silently times out.
      #
      # `ip route get $MASTER` asks the kernel "which interface + source IP
      # would I use to reach the master?" — deterministic regardless of how
      # many other NICs we have or DHCP timing.
      ROUTE_INFO=$(ip -4 route get ${master_fixed_ip} | head -1)
      NODE_IP=$(echo "$ROUTE_INFO" | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')
      NODE_IFACE=$(echo "$ROUTE_INFO" | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
      echo "    node-ip       (route-based src towards master): $NODE_IP"
      echo "    flannel-iface (route-based dev towards master): $NODE_IFACE"

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
          --flannel-iface "$NODE_IFACE" \
          --with-node-id

      echo "==> [$(date)] k3s agent joined cluster successfully."

runcmd:
  # MTU + MSS 已在 bootcmd 套用（每次 boot 自動 idempotent 套）
  - /opt/k3s-agent-init.sh

final_message: "k3s agent joined cluster (master=${master_fixed_ip}), uptime=$${UPTIME}s"
