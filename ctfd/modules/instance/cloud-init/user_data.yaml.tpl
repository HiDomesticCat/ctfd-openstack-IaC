#cloud-config
# CTFd Server cloud-init
# Terraform templatefile 會將 timezone / deploy_dir / mgmt 設定帶入

timezone: ${timezone}

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

%{ if mgmt_ip != "" ~}
# ── 管理網卡 netplan（讓 VM 能連到 OpenStack API）──────────
write_files:
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
