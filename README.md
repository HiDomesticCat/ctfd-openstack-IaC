# ctfd-openstack

在 OpenStack 上部署 [CTFd](https://github.com/CTFd/CTFd) 競賽平台，整合 [chall-manager](https://github.com/ctfer-io/chall-manager) 與 Pulumi，為每位玩家動態建立獨立靶機（OpenStack VM 或 Kubernetes Pod）。

## Architecture

```
OpenStack (ctfd project / ctfd-deployer account)
│
├── platform/              OpenTofu — 共享基礎設施（Layer 1，admin scope）
│   └── modules/           network, images, flavors, project + quota,
│                          challenge_network (玩家↔題目共享網段，RBAC share 給 ctfd)
│
├── ctfd/                  OpenTofu — CTFd VM 部署（Layer 2）
│   └── modules/           keypair, network, secgroup, instance
│       cloud-init: 安裝 Docker + Docker Compose，建立 /opt/ctfd
│
├── chell/                 OpenTofu — k3s 叢集（Layer 3，Kubernetes challenge 後端）
│   └── modules/           k3s (master + workers), network, secgroup
│       cloud-init: 自動安裝 k3s server/agent，產生 kubeconfig
│       k3s worker 第二個 port 接 challenge-net（NodePort 從這聽）
│
└── ansible/               Ansible — 應用程式配置（Layer 4）
    ├── roles/ctfd/        CTFd v3.8.1 + ctfd-chall-manager plugin（Docker Compose）
    ├── roles/chall-manager/  chall-manager + etcd + local OCI registry（Docker Compose）
    ├── roles/k3s/         k3s 叢集驗證 + kubeconfig 部署到 CTFd server
    └── scenarios/
        ├── openstack-vm/  Pulumi Go — 為玩家建立 OpenStack VM + Floating IP
        │                  預設網段 = challenge-net（可在 CTFd Advanced 個案覆蓋）
        └── k8s-pod/       Pulumi Go — 為玩家在 k3s 建立 Namespace + Pod + NodePort Service
```

**部署順序：** `platform` → `ctfd` → `chell`（選用）→ `ansible`

## 網段配置

lab 內的 IP 段（連續編號慣例）：

| CIDR | 用途 | 由哪管 |
|------|------|--------|
| `192.168.50.0/24` | 管理 LAN（control plane、operator、CTFd web FIP） | OpenStack `public` external network |
| `192.168.77.0/24` | gamma4 研究 VM 內網 | sister repo `gamma4-lab-infra` |
| **`192.168.78.0/24`** | **玩家↔題目共享網段（challenge-net）** | **`platform/modules/challenge_network/`** |
| `192.168.100.0/24` | CTFd web 前端 | `ctfd/` |
| `192.168.200.0/24` | k3s 控制面 | `chell/` |

**challenge-net** 是 admin 創、透過 `openstack_networking_rbac_policy_v2` 用 `access_as_shared` 分享給 ctfd-deployer project 的內部 VXLAN 網段。三方共用：

- **k3s worker**（chell/）— 加第二個 port 接 challenge-net；NodePort (30000-32767) 從這個介面也聽
- **openstack-vm scenario**（ctfd/）— 題目 VM 預設網段（`use_challenge_network_for_scenarios = true`）
- **gamma4 研究 VM**（sister repo）— 加第二個 port 接 challenge-net；Caldera 直接打題目（不走 worker FIP）

子網段隨網段一起被 RBAC 分享，不需要額外 subnet RBAC。各層用名字（`challenge-net`）`data source` 引用，不靠 ID（每次 apply ID 都不同）。

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
$EDITOR terraform.tfvars        # 設定 network_mtu / quota 等；ctfd_deployer_password 留空就會自動產生

tofu init && tofu apply
tofu output                     # 記下：external_network_id, image_ids["ubuntu2204"]
tofu output -raw ctfd_deployer_password   # 取出自動產生的密碼，貼進 ~/.config/openstack/clouds.yaml 的 ctfd entry
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
# 留空：k3s_token 會自動 random_password 產生並 persist 在 tfstate
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

## Rebuild & Reproducibility

整個 stack 設計為可 `tofu destroy && tofu apply` 重建。下列機制讓 rebuild 不需要手動介入：

| 機制 | 解決什麼 |
|------|---------|
| **k3s `--with-node-id`**（agent.yaml.tpl） | Worker rebuild 時 hostname 加 hash 後綴（`chell-worker-1-<id>`），新 node 不會撞 master 的 stale node-passwd entry。**不需要 `kubectl delete node`**。 |
| **`random_password.k3s_token`**（chell/main.tf） | `var.k3s_token` 留空時自動產生並 persist 在 tfstate，跨 apply 不變。Operator 不用 `openssl rand`。 |
| **`random_password.ctfd_deployer_password`**（platform/main.tf） | 同上；自動產生後用 `tofu output -raw ctfd_deployer_password` 取出貼進 clouds.yaml。 |
| **MTU 顯式設定 in cloud-init bootcmd**（chell + ctfd） | 不靠 DHCP（in-place network MTU update 不會傳到既有 VM）；改 tfvars 後 force-replace 即生效。 |
| **Sister gamma4-lab-infra: cloud-init `git clone` retry loop** | 第一次 fresh deploy 操作者貼 GitHub deploy key 到 repo settings 時，cloud-init 會等到 clone 成功（15 min 容窗）。 |

**Fresh deploy 一個新 OpenStack cluster 從零開始**：

```bash
# 0. 一次性：clouds.yaml 的 admin section（手動，無法 IaC）
$EDITOR ~/.config/openstack/clouds.yaml      # 加 openstack (admin) entry

# 1. platform — admin scope，創 ctfd project + challenge-net
cd platform && cp terraform.tfvars.example terraform.tfvars && tofu init && tofu apply
DEPLOYER_PW=$(tofu output -raw ctfd_deployer_password)
# 把 $DEPLOYER_PW 貼進 clouds.yaml 的 ctfd entry password 欄位

# 2. ctfd — CTFd VM（新 ctfd cloud entry 即可登入）
cd ../ctfd && cp terraform.tfvars.example terraform.tfvars && tofu init && tofu apply

# 3. chell — k3s 叢集
cd ../chell && cp terraform.tfvars.example terraform.tfvars && tofu init && tofu apply

# 4. ansible — 應用程式層
cd ../ansible
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
$EDITOR group_vars/all/vault.yml && ansible-vault encrypt group_vars/all/vault.yml
ansible-playbook site.yml -i inventory/hosts.ini -i inventory/k3s_hosts.ini --ask-vault-pass

# 5. （選用）gamma4-lab-infra — 研究 VM
cd /data/gamma4-lab-infra
export TF_VAR_openrouter_api_key=sk-or-...
tofu init && tofu apply                       # 第一次會卡在 git clone（deploy key 未註冊）
tofu output -raw github_deploy_public_key     # 貼到 GitHub repo Settings -> Deploy keys
# cloud-init 的 retry loop 會在 15 min 內偵測到 deploy key OK 自動繼續
```

**Operator 必填的 4 個機密**（無法 IaC 化）：
1. `clouds.yaml` 的 admin password（OpenStack admin 帳號）
2. `ansible-vault` 密碼（vault.yml 解密）
3. `TF_VAR_openrouter_api_key`（gamma4-lab-infra）
4. GitHub deploy key 公鑰一次性貼到 repo settings（gamma4-lab-infra）

其他全部 IaC 自動化。

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
