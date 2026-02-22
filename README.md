# ctfd-openstack

在 OpenStack 上部署 [CTFd](https://github.com/CTFd/CTFd) 競賽平台，整合 [chall-manager](https://github.com/ctfer-io/chall-manager) 與 Pulumi，為每位玩家動態建立獨立靶機（OpenStack VM 或 Kubernetes Pod）。

## Architecture

```
OpenStack (ctfd project / ctfd-deployer account)
│
├── platform/              OpenTofu — 共享基礎設施（Layer 1）
│   └── modules/           network, images, flavors, project + quota
│
├── ctfd/                  OpenTofu — CTFd VM 部署（Layer 2）
│   └── modules/           keypair, network, secgroup, instance
│       cloud-init: 安裝 Docker + Docker Compose，建立 /opt/ctfd
│
├── chell/                 OpenTofu — k3s 叢集（Layer 3，Kubernetes challenge 後端）
│   └── modules/           k3s (master + workers), network, secgroup
│       cloud-init: 自動安裝 k3s server/agent，產生 kubeconfig
│
└── ansible/               Ansible — 應用程式配置（Layer 4）
    ├── roles/ctfd/        CTFd v3.8.1 + ctfd-chall-manager plugin（Docker Compose）
    ├── roles/chall-manager/  chall-manager + etcd + local OCI registry（Docker Compose）
    ├── roles/k3s/         k3s 叢集驗證 + kubeconfig 部署到 CTFd server
    └── scenarios/
        ├── openstack-vm/  Pulumi Go — 為玩家建立 OpenStack VM + Floating IP
        └── k8s-pod/       Pulumi Go — 為玩家在 k3s 建立 Namespace + Pod + NodePort Service
```

**部署順序：** `platform` → `ctfd` → `chell`（選用）→ `ansible`

## 前置需求

| 工具 | 最低版本 | 用途 |
|------|---------|------|
| OpenTofu | ≥ 1.11 | 基礎設施佈建 |
| Ansible | ≥ 2.14 | 應用程式配置管理 |
| Python | ≥ 3.10 | Ansible 執行環境 |
| `~/.config/openstack/clouds.yaml` | — | OpenStack 認證（取代 OS_ 環境變數）|

```yaml
# ~/.config/openstack/clouds.yaml 範例
clouds:
  ctfd:
    auth:
      auth_url: http://<OPENSTACK_IP>:5000/v3
      project_name: ctfd
      username: ctfd-deployer
      password: "<ctfd_deployer_password>"
      user_domain_name: Default
      project_domain_name: Default
    region_name: RegionOne
    identity_api_version: 3
```

> **重要：** 使用 `clouds.yaml` 而非 `admin-openrc.sh`（OS_ 環境變數）。
> OS_ 環境變數優先級高於 clouds.yaml，若兩者並存會導致資源建在錯誤 project。

## Quick Start

### Step 1 — 準備憑證（必要）

```bash
# 複製並填入 OpenStack 憑證
cp ansible/group_vars/all/vault.yml.example \
   ansible/group_vars/all/vault.yml
$EDITOR ansible/group_vars/all/vault.yml

# ⚠️  必要步驟：加密敏感憑證（嚴禁省略）
ansible-vault encrypt ansible/group_vars/all/vault.yml
```

### Step 2 — 部署共享平台層（platform）

```bash
cd platform
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars        # 設定 ctfd_deployer_password 等

tofu init && tofu apply
tofu output                     # 記下：external_network_id, image_ids["ubuntu2204"]
```

### Step 3 — 部署 CTFd VM（ctfd）

```bash
cd ../ctfd
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars        # 填入 Step 2 的 external_network_id, image_id

tofu init && tofu apply
# 自動產生：
#   ansible/inventory/hosts.ini               ← CTFd VM IP + SSH key
#   ansible/group_vars/all/challenge_ids.yml  ← network_id, image_id
tofu output                     # 記下：floating_ip（CTFd 存取位址）
```

### Step 4 — 部署 k3s 叢集（chell，選用）

若需要 Kubernetes Pod challenge，執行此步驟：

```bash
cd ../chell
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
# 必填：external_network_id, image_id（來自 Step 2）
# 必填：k3s_token（建議用強隨機值：openssl rand -hex 32）
# 建議：ssh_allowed_cidr 限制為管理機 IP（如 10.0.2.5/32）

tofu init && tofu apply
# 自動產生：
#   ansible/inventory/k3s_hosts.ini           ← k3s master + worker IP
#   ansible/group_vars/all/k3s_ids.yml        ← worker floating IPs
tofu output                     # 記下：master_floating_ip, worker_floating_ips
```

### Step 5 — 填入 Challenge 設定並執行 Ansible

```bash
cd ../ansible

# 填入 UUID、IP、flag 等環境特定值
cp group_vars/all/challenge.yml.example \
   group_vars/all/challenge.yml
$EDITOR group_vars/all/challenge.yml
# 來源：
#   challenge_image_id   ← platform tofu output: image_ids["ubuntu2204"]
#   challenge_network_id ← ctfd    tofu output: network_id（已自動寫入 challenge_ids.yml）
#   challenge_base_flag  ← 自定義（每位玩家的 flag 從此衍生）

# 部署（不含 k3s）
ansible-playbook site.yml \
  -i inventory/hosts.ini \
  --ask-vault-pass

# 部署（含 k3s Kubernetes challenge 後端）
ansible-playbook site.yml \
  -i inventory/hosts.ini \
  -i inventory/k3s_hosts.ini \
  --ask-vault-pass
```

## Local Config Files（gitignored，不進入版本控制）

| 檔案 | 內容 | 來源 | 敏感度 |
|------|------|------|--------|
| `ansible/group_vars/all/vault.yml` | OpenStack 帳號密碼 | 手動（**必須 vault 加密**）| ⚠️ 高 |
| `ansible/group_vars/all/challenge.yml` | image/network UUID、base flag | 手動（from tofu output）| 中 |
| `ansible/group_vars/all/challenge_ids.yml` | challenge 資源 UUID | ctfd `tofu apply` 自動生成 | 中 |
| `ansible/group_vars/all/k3s_ids.yml` | k3s worker floating IPs | chell `tofu apply` 自動生成 | 低 |
| `ansible/inventory/hosts.ini` | CTFd VM IP、SSH key 路徑 | ctfd `tofu apply` 自動生成 | 低 |
| `ansible/inventory/k3s_hosts.ini` | k3s 節點 IP | chell `tofu apply` 自動生成 | 低 |
| `ansible/k3s-kubeconfig` | k3s API 完整憑證 | k3s role 從 master fetch | ⚠️ 高 |
| `platform/terraform.tfvars` | 平台設定 + 部署帳號密碼 | 手動 | ⚠️ 高 |
| `ctfd/terraform.tfvars` | CTFd VM 設定 | 手動（from platform output）| 中 |
| `chell/terraform.tfvars` | k3s 叢集設定 | 手動（from platform output）| 中 |

## 網路架構

```
Internet / 管理機
       │
       ▼ floating IPs (10.0.2.150–199)
┌──────────────────────────────────────────────────┐
│ OpenStack External Network (10.0.2.0/24)         │
│                                                  │
│  CTFd VM ──── 192.168.100.0/24 (ctfd-network)    │
│  ports:  80 (HTTP), 443 (HTTPS), 8000 (CTFd)     │
│           22 SSH (限 ssh_allowed_cidr)            │
│                                                  │
│  chell-master ─┐                                 │
│  chell-worker  ├── 192.168.200.0/24 (chell)      │
│  chell-worker  │   master fixed: 192.168.200.10  │
│  ports: 30000-32767 (NodePort，玩家連線)          │
│          22 SSH, 6443 kubectl (限 ssh_allowed_cidr)│
└──────────────────────────────────────────────────┘
```

## CTFd Plugin 設定

Ansible 完成後，在 **CTFd Admin → Plugins → chall-manager** 填入：

| 欄位 | 值 |
|------|----|
| chall-manager URL | `http://chall-manager:8080` |
| Scenario（OpenStack VM）| `registry:5000/openstack-vm:latest` |
| Scenario（k8s Pod）| `registry:5000/k8s-pod:latest` |

> **重要：** CTFd 在 Docker 內，`localhost` 指 CTFd 容器本身。
> 必須使用 Docker Compose service name：`chall-manager`、`registry`。

## Ansible 變數優先級

```
roles/defaults/main.yml   ← 佔位符（committed，可被覆蓋）
group_vars/all/*.yml      ← 真實值（gitignored，覆蓋 defaults）
roles/vars/main.yml       ← 固定角色設定（committed，不可被覆蓋）
```

## 動態 Flag 機制

每位玩家根據其 `identity` 獲得唯一 flag：

- **openstack-vm**：`CTF{<baseFlag>_<HMAC-SHA256(identity, baseFlag)[:12]>}`
  使用 HMAC-SHA256（crypto/hmac + crypto/sha256），確保無法從 flag 反推 baseFlag。

- **k8s-pod**：`CTF{<MD5(baseFlag + identity)>}`
  使用 MD5 Hash（注意：此處用於 identifier 生成，非密碼學安全用途）。

在 `ansible/group_vars/all/challenge.yml` 中設定 `challenge_base_flag`。

## 安全注意事項

### 已實施的防護措施

| 措施 | 說明 |
|------|------|
| clouds.yaml 認證 | 避免與 admin-openrc.sh OS_ 環境變數衝突導致資源建在 admin project |
| chall-manager API 綁定 127.0.0.1 | 不對外暴露，只有同 Docker 網路的 CTFd 可存取 |
| etcd 僅在 Docker 內部網路 | 不對外暴露 |
| local OCI registry 綁定 localhost | HTTP registry 僅本機存取 |
| k3s 叢集 secgroup 隔離 | 節點間走 remote_group_id 規則，外部只開放必要 port |
| challenges namespace ResourceQuota | 限制 pod 數量 50、CPU 16core、記憶體 32Gi |
| .gitignore 完整保護 | state、tfvars、vault.yml、kubeconfig、compiled binary |

### 需要手動完成的安全設定

| 項目 | 風險等級 | 建議動作 |
|------|---------|---------|
| vault.yml 加密 | **HIGH** — 明文 OpenStack 密碼 | `ansible-vault encrypt vault.yml` |
| ssh_allowed_cidr | MEDIUM — 預設 `0.0.0.0/0` | 限制為管理機 IP（如 `10.0.2.5/32`）|
| k3s_token 強度 | MEDIUM — 最低 16 字元要求 | 建議 32 字元：`openssl rand -hex 32` |
| PULUMI_CONFIG_PASSPHRASE | LOW — Pulumi state 未加密 | 生產環境設定強密碼 |

### 已知設計取捨

- **k3s token 出現在 cloud-init 日誌**：`/var/log/k3s-init.log` 含明文 token（cloud-init 固有行為）。建議賽事結束後輪換 token，或限制 SSH 存取。
- **insecure local registry**：Docker registry 使用 HTTP，但只監聽 `localhost:5000`，不暴露到外網。
- **MD5 用於 k8s-pod shortID**：MD5 在此僅用於 Kubernetes 資源命名（8 字元 hex）的 identifier 生成，非密碼學安全用途。

## OpenTofu Provider 說明

本專案使用 `terraform-provider-openstack/openstack`（非 `hashicorp/openstack`），各模組均有 `versions.tf` 明確宣告。

若出現 `Provider requires explicit configuration` 錯誤：

```bash
# 在 platform/, ctfd/, chell/ 各目錄執行
rm -rf .terraform .terraform.lock.hcl
tofu init
```
