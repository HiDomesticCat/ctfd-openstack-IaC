#cloud-config
# CTFd Server cloud-init
# Terraform templatefile 會將 timezone / deploy_dir / mgmt 設定帶入

timezone: ${timezone}

# ── DNS 設定（確保 SNAT 模式下 apt/docker 能解析域名）────────
manage_resolv_conf: true
resolv_conf:
  nameservers:
%{ for ns in dns_nameservers ~}
    - ${ns}
%{ endfor ~}

# 更新套件清單並升級系統
package_update: true
package_upgrade: true

packages:
  - ca-certificates
  - curl
  - wget
  - gnupg
  - git
  - docker.io
  - docker-compose-v2
  # docker-buildx-plugin 需從 Docker 官方 apt 倉庫安裝
  # 由 Ansible playbook 負責加入倉庫並安裝

write_files:
  - path: /etc/systemd/resolved.conf.d/dns.conf
    content: |
      [Resolve]
%{ for ns in dns_nameservers ~}
      DNS=${ns}
%{ endfor ~}
    permissions: '0644'
  - path: /etc/docker/daemon.json
    content: |
      {"dns": [${join(", ", [for ns in dns_nameservers : "\"${ns}\""])}], "mtu": ${network_mtu - 40}}
    permissions: '0644'
%{ if mgmt_ip != "" ~}
  - path: /etc/netplan/99-mgmt.yaml
    content: |
      network:
        version: 2
        ethernets:
          ens7:
            dhcp4: false
            addresses:
              - ${mgmt_ip}/24
%{ for route in mgmt_routes ~}
            routes:
              - to: ${route.to}
                via: ${route.via}
%{ endfor ~}
    permissions: '0600'
%{ endif ~}

runcmd:
  - systemctl restart systemd-resolved
  # TCP MSS clamping — 確保 HTTPS 大封包不被上游 gateway 丟棄
  # VXLAN overlay + 受限校園 MTU 環境下必要
  - iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  - mkdir -p /etc/iptables
  - iptables-save > /etc/iptables/rules.v4
  # Docker
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ubuntu
  # 建立部署目錄
  - mkdir -p ${deploy_dir}
  - chown ubuntu:ubuntu ${deploy_dir}
%{ if mgmt_ip != "" ~}
  # 啟用管理網卡
  - netplan apply
%{ endif ~}
  # 記錄完成時間
  - bash -c 'echo "cloud-init done at $(date)" >> /var/log/cloud-init-ctfd.log'

final_message: "CTFd server ready. deploy_dir=${deploy_dir}, uptime=$$UPTIME sec"
