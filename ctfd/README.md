# ctfd-openstack

OpenStack 上的 CTFd 應用程式層基礎設施。

**必須先完成 `../platform` 的部署，才能執行此目錄。**

## 架構

```
ctfd-openstack/
├── main.tf                    # 模組呼叫
├── variables.tf               # 根層變數
├── outputs.tf                 # 根層輸出
├── versions.tf                # Provider 設定（使用 clouds.yaml）
├── terraform.tfvars.example   # 配置範例
├── .gitignore
└── modules/
    ├── keypair/               # SSH Keypair
    ├── network/               # 內部網路 + 子網路 + Router
    ├── secgroup/              # Security Group + 防火牆規則
    └── instance/             # VM + Floating IP
```

## 依賴關係

```
keypair ──┐
          ├──→ instance
secgroup ─┤
          │
network ──┘ (depends_on)
```

## 環境需求

- OpenTofu/Terraform >= 1.11.0
- 已完成 `../platform` 部署
- `~/.config/openstack/clouds.yaml` 包含 `ctfd` cloud entry

## 快速開始

### 1. 設定 clouds.yaml

```yaml
# ~/.config/openstack/clouds.yaml
clouds:
  ctfd:
    auth:
      auth_url: http://<openstack-ip>:5000/v3
      username: ctfd-deployer
      password: <ctfd_deployer_password>
      project_name: ctfd
      user_domain_name: Default
      project_domain_name: Default
    region_name: RegionOne
    interface: public
    identity_api_version: 3
```

### 2. 從 platform 取得必要 Output

```bash
cd ../platform
tofu output
# 複製 external_network_id 和 image_id
```

### 3. 建立 terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入從 platform 取得的值
```

### 4. 初始化並部署

```bash
tofu init
tofu plan
tofu apply
```

### 5. 取得連線資訊

```bash
tofu output
# floating_ip  → CTFd 對外 IP
# ctfd_url     → http://<ip>:8000
# ssh_command  → ssh ubuntu@<ip>
```

## 模組說明

### keypair
建立 SSH Keypair，使用本機公鑰。

| 變數 | 說明 | 預設 |
|------|------|------|
| `keypair_name` | Keypair 名稱 | `ctfd-key` |
| `public_key_path` | 公鑰絕對路徑 | `/root/.ssh/id_rsa.pub` |

### network
建立內部網路、子網路（開 DHCP）、Router，並接上外部網路。

| 變數 | 說明 | 預設 |
|------|------|------|
| `external_network_id` | 外部網路 ID（必填） | — |
| `internal_subnet_cidr` | 內部網路 CIDR | `192.168.100.0/24` |
| `dns_nameservers` | DNS 清單 | `["8.8.8.8", "8.8.4.4"]` |

### secgroup
建立 Security Group，開放 SSH / HTTP / HTTPS / CTFd Port。

| 變數 | 說明 | 預設 |
|------|------|------|
| `ssh_allowed_cidr` | SSH 來源限制（建議填管理 IP）| `0.0.0.0/0` |
| `ctfd_port` | CTFd 應用程式 Port | `8000` |

### instance
建立 VM，申請並綁定 Floating IP。

| 變數 | 說明 | 預設 |
|------|------|------|
| `image_id` | Image ID（必填） | — |
| `flavor_name` | VM 規格 | `general.medium` |
| `floating_ip_pool` | Floating IP 外部網路名稱 | `public` |

## 安全設定

### 強烈建議限制 SSH 來源

```hcl
# terraform.tfvars
ssh_allowed_cidr = "203.0.113.10/32"  # 只允許管理 IP
```

### 使用 clouds.yaml 管理憑證

本配置使用 `clouds.yaml` 取代明文憑證，避免密碼出現在 tfvars 和 state 中。

```bash
# 驗證 clouds.yaml 設定
openstack --os-cloud=ctfd token issue
```

## Outputs

| 名稱 | 說明 |
|------|------|
| `floating_ip` | CTFd 對外 IP |
| `ctfd_url` | CTFd 存取網址 |
| `ssh_command` | SSH 連線指令 |
| `internal_ip` | VM 內部 IP |
| `network_id` | 內部網路 ID |

## 常見問題

### VM 無法對外連線
確認 platform 的 Router 和外部網路設定正確：
```bash
cd ../platform
tofu output
```

### Image 不存在
```bash
openstack --os-cloud=ctfd image list
```

### Flavor 不存在
```bash
openstack --os-cloud=ctfd flavor list
```

### SSH 無法連線
1. 確認 `ssh_allowed_cidr` 包含你的 IP
2. 確認 keypair 使用正確的公鑰
3. 確認 VM 狀態為 ACTIVE：
   ```bash
   openstack --os-cloud=ctfd server show ctfd-server
   ```
