#cloud-config
# k3s agent (worker) cloud-init
# Terraform templatefile 變數：timezone, k3s_token, k3s_version, master_fixed_ip

timezone: ${timezone}

package_update: true
package_upgrade: true

packages:
  - curl
  - wget
  - open-iscsi
  - nfs-common
  - netcat-openbsd

write_files:
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

      curl -sfL https://get.k3s.io | \
        K3S_URL="https://${master_fixed_ip}:6443" \
        K3S_TOKEN="${k3s_token}" \
        sh -s - agent

      echo "==> [$(date)] k3s agent joined cluster successfully."

runcmd:
  - /opt/k3s-agent-init.sh

final_message: "k3s agent joined cluster (master=${master_fixed_ip}), uptime=$${UPTIME}s"
