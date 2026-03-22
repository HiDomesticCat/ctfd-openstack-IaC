# ctfd-openstack 開發待辦事項

> 目標：降低出題門檻、加速題目啟動、改善管理體驗

---

## 1. 題目啟動流程改造（核心）

### 1.1 通用化 scenario（使用 chall-manager `additional` 機制）

**現狀：** 所有題目共用同一組環境變數（image、port、command），無法在 CTFd 上同時跑多種不同的 container 題目。兩個 scenario 都用 raw Pulumi config，沒有使用 chall-manager 官方 SDK。

**發現：** chall-manager 已原生支援 per-challenge 設定，透過 `additional` 欄位（`map<string,string>`）：
- 註冊題目時傳入 `additional: {"image": "vuln-app:v1", "port": "8080"}`
- Scenario 透過 `req.Config.Additional["image"]` 讀取
- CTFd plugin UI 已內建 key-value 編輯器（Advanced 區塊）
- Challenge-level 與 instance-level 的 additional 會自動合併

**做法：**
- [x] 改造 scenario 使用 chall-manager 官方 Go SDK（`sdk.Run`）取代 raw `pulumi.Run`，以讀取 `additional` config
- [x] `k8s-pod/main.go`：從 `additional` 讀取 image、port、resource limits，fallback 到環境變數
- [x] `openstack-vm/main.go`：從 `additional` 讀取 image_id、flavor、port，fallback 到環境變數
- [x] 更新 Ansible chall-manager tasks：註冊題目時傳入 `additional` 欄位
- [ ] 驗證單一 scenario binary 能服務多種不同的題目（待部署後實測）

### 1.2 加速題目啟動時間

**現狀：** 玩家點擊開題後需要等待 Pulumi 執行 + 資源建立，k8s-pod 約 5-15 秒，openstack-vm 可能超過 60 秒。

#### k8s-pod 加速

- [x] **Pre-pull challenge images**：k3s role 加入 `crictl pull` task，搭配 `k3s_challenge_prepull_images` 變數
- [x] **ImagePullPolicy 改 IfNotPresent**：k8s-pod scenario 明確設定 `ImagePullPolicy: IfNotPresent`

#### openstack-vm 加速（研究重點，不可捨棄）

openstack-vm 是本專案的研究核心之一，需要從多個角度壓縮啟動時間：

- [x] **Snapshot 策略（Packer）**：建立完整 Packer 基礎設施（`packer/` 目錄），出題者用 `make packer-build CHALLENGE=<name>` 將題目環境 bake 成 OpenStack image snapshot，scenario 直接用 snapshot 開機（分鐘級 → ~15-20 秒）
  - `packer/plugins.pkr.hcl` — OpenStack plugin
  - `packer/variables.pkr.hcl` — 共用變數（認證 + 題目設定）
  - `packer/source.pkr.hcl` — OpenStack source block
  - `packer/build.pkr.hcl` — 3 階段 build：base setup → 題目 provisioning → cleanup
  - `packer/scripts/base-setup.sh` — 共用基礎（cloud-init 最小化設定）
  - `packer/scripts/cleanup.sh` — 清理暫存縮小 image
  - `challenges/web-example/` — 完整範例題目（Packer template + challenge.yml）
- [x] **共用 Security Group**：scenario 支援 `security_group_id` additional key，有值時跳過 SG 建立（省 ~3-5s）；出題者可選用預建的 SG
- [x] **Pulumi 平行建立資源**：移除 Port/VM/FIP 冗餘 `DependsOn`，FIP 與 VM 現可平行建立（省 ~2-3s）
- [x] **預分配 FIP**：scenario 支援 `fip_address` additional key，傳入預分配的 FIP 位址即跳過 FIP 建立（省 ~2-3s）。使用 `FloatingIpAssociate` 只管關聯不管生命週期
- [x] **cloud-init flag 注入**：scenario 自動產生 cloud-config 將 per-player flag 寫入 VM（預設 `/opt/ctf/flag.txt`）。支援 `flag_path`（自訂路徑）和 `cloud_init`（完全自訂腳本，`{{FLAG}}` `{{PORT}}` `{{IDENTITY}}` 佔位符）
- [x] **輕量 flavor**：新增 `general.tiny`（1 vCPU, 1GB RAM, 10GB disk）供簡單題目使用，進一步加速 VM 建立

### 1.3 Challenge as Code（題目設定即程式碼）

**痛點：** CTFd 每次重部署或版本升級後，MySQL 資料清除，所有題目設定（名稱、分類、描述、flag、scenario、additional）都要手動在 Web UI 重新輸入，耗時且容易出錯。

**目標：** 題目設定定義在版本控制的 YAML 檔案中，一鍵自動註冊到 CTFd。出題者只需要提供 Docker image + 一份 `challenge.yml`。

**架構設計：**

```
challenge.yml → register script → CTFd REST API (POST /api/v1/challenges)
                                       ↓ (chall-manager plugin 內部自動處理)
                                  chall-manager gRPC → 註冊 scenario + additional
```

- Registration script 只需與 CTFd API 溝通，chall-manager plugin 自動同步 scenario 設定
- CTFd API 認證：`Authorization: Token <token>`（在 CTFd Settings > Access Tokens 產生）

#### 1.3.1 challenge.yml 格式設計

```yaml
# challenges/web-sqli/challenge.yml 範例
name: "Web SQL Injection"
category: web
description: "Find the SQL injection vulnerability and extract the flag."
value: 500                            # 初始分數
type: dynamic_iac                     # CTFd challenge type（chall-manager plugin 提供）
state: visible                        # visible | hidden

# ── chall-manager 設定 ──
scenario: k8s-pod                     # scenario 名稱 → 展開為 registry:5000/k8s-pod:latest
timeout: "3600s"                      # instance 存活時間（Go duration）

additional:                           # per-challenge 設定（傳入 scenario additional map）
  image: "vuln-sqli:v1"
  port: "8080"
  base_flag: "SQL_1nj3ct10n_M4st3r"
  flag_prefix: "CTF"
```

- [x] 研究 CTFd chall-manager plugin 的 API payload 格式（type=`dynamic_iac`、scenario 為 OCI reference、additional 為 flat dict）
- [x] 設計 challenge.yml schema，支援 k8s-pod 和 openstack-vm 兩種 scenario
- [x] 確認 openstack-vm 的 additional key 對應（image_id、network_id、security_group_id、flavor 等）
- [x] 建立 `challenge_defaults.yml`（運維管理的基礎設施預設值，與 challenge.yml 合併）

#### 1.3.2 目錄結構

```
challenges/
├── README.md                          # 出題者指南
├── _templates/                        # YAML 範本（複製即用）
│   ├── k8s-pod.yml                    # 容器題範本
│   └── openstack-vm.yml               # VM 題範本
├── web-sqli/                          # 範例：容器題
│   └── challenge.yml
└── linux-privesc/                     # 範例：VM 題
    └── challenge.yml
```

- [x] 建立 `challenges/` 目錄與結構
- [x] 建立 k8s-pod 範本（`_templates/k8s-pod.yml`）
- [x] 建立 openstack-vm 範本（`_templates/openstack-vm.yml`）
- [x] 已有 openstack-vm 範例（`web-example/`）；k8s-pod 範例待建立

#### 1.3.3 Registration Script（Python）

檔案：`scripts/register-challenges.py`

```bash
# 用法
export CTFD_URL="http://<ctfd-floating-ip>:8000"
export CTFD_TOKEN="ctfd_xxx..."

python3 scripts/register-challenges.py                        # 註冊所有題目
python3 scripts/register-challenges.py --dry-run              # 預覽模式（不實際呼叫 API）
python3 scripts/register-challenges.py challenges/web-sqli/   # 只註冊指定題目
```

功能需求：
- 掃描 `challenges/*/challenge.yml` 讀取所有題目定義
- 透過 CTFd REST API 建立題目（`POST /api/v1/challenges`）
- **冪等操作**：以 `name` 比對已存在的題目 → `PATCH` 更新；不存在 → `POST` 建立
- `--dry-run`：顯示將要執行的操作但不呼叫 API
- 清楚的 console 輸出：✓ created / ⟳ updated / ✗ error
- 環境變數或 `.env` 檔案讀取 `CTFD_URL` + `CTFD_TOKEN`

開發步驟：
- [x] 確認 CTFd API Token 認證格式（`Authorization: Token <token>`）
- [x] 實作 CTFd API client（list / create / update challenge）
- [x] 實作 challenge.yml parser（YAML → CTFd API payload 轉換，scenario 名稱展開）
- [x] 實作冪等邏輯（name 比對 + create or update 判斷）
- [x] 實作 `--dry-run` 模式
- [x] 錯誤處理（API 失敗、YAML 格式錯誤、連線失敗、Token 無效）
- [ ] 整合測試：實際對 CTFd 執行 register → 驗證題目出現在 Web UI + chall-manager 已註冊

#### 1.3.4 Makefile 整合

- [x] 加入 `make register-challenges` / `register-challenges-dry` target
- [x] 加入 `make deploy-challenge CHALLENGE=<name>` target（Packer build + 註冊）
- [x] 更新 `make help` 說明

#### 1.3.5 .env 管理

```
# .env（gitignored）
CTFD_URL=http://10.0.1.xxx:8000
CTFD_TOKEN=ctfd_xxxxxxxxxxxx
```

- [x] 在 `.gitignore` 加入 `.env`
- [x] 建立 `.env.example` 範本
- [x] Registration script 支援從 `.env` 讀取

#### 1.3.6 出題者文件

- [ ] 撰寫 `challenges/README.md`：完整出題者指南
  - 如何新增一道容器題（step by step）
  - 如何新增一道 VM 題（step by step）
  - challenge.yml 各欄位說明
  - 如何取得 OpenStack image_id / network_id / security_group_id
  - 如何測試題目（本地 + 部署後）
  - 如何更新已上架的題目

---

## 2. 架構改善

### 2.1 Scenario flag 生成統一 ✅

**已完成（隨 1.1 一併解決）：** 兩個 scenario 都改用 `sdk.Variate(identity, baseFlag)`，取代各自的 HMAC-SHA256 / MD5 實作。flag 仍為動態（per-player deterministic），只是演算法統一由 SDK 提供。

- [x] 統一 flag 生成：兩個 scenario 都使用 `sdk.Variate()`
- [x] 移除自行實作的 `variateFlag()`（HMAC-SHA256）和 `dynamicFlag()`（MD5）

### 2.2 精簡 docker-compose 環境變數 ✅

**已完成：** 移除 docker-compose.yml.j2 中所有 `CHALLENGE_*` 環境變數，保留 OS_*、K3S_WORKER_IPS、KUBECONFIG、PULUMI_* 等基礎設施/全域設定。defaults/main.yml 和 challenge.yml.example 同步更新。

- [x] 移除 docker-compose.yml.j2 中題目專屬的環境變數（CHALLENGE_IMAGE_ID、CHALLENGE_PORT 等）
- [x] 保留 OpenStack 憑證、Pulumi 設定等全域環境變數

### 2.3 題目生命週期管理

**現狀：** 只有 chall-manager-janitor 做過期清理，缺少：
- 題目健康檢查（Pod crash 後玩家看到的是壞掉的環境）
- 資源用量監控（哪些題目消耗最多資源）
- 批量操作（一次關閉所有某類型題目）

- [ ] 加入 Pod readiness/liveness probe 到 k8s-pod scenario
- [ ] 考慮是否需要簡單的監控 dashboard（kubectl top + Grafana，或簡單 script）
- [ ] 評估是否需要 CTFd API 批量操作工具

---

## 3. 基礎設施改善

### 3.1 k3s 叢集彈性

- [ ] 評估是否需要 worker node auto-scaling（根據同時連線玩家數）
- [ ] 加入 k3s worker 健康檢查（node NotReady 時自動告警或重建）

### 3.3 壓力測試後修復（2026-03-15 壓力測試發現）

> 測試數據見 `stress-test-results/summary.md`

#### 3.3.1 Quota as Code

- [x] **Quota 納入 OpenTofu** — `platform/main.tf` 已更新為 50 人比賽規模
  - instances 10→60, cores 12→65, ram 24GB→120GB, floatingips 10→60, ports 50→120, SG 15→65, SG rules 150→500
  - 計算依據：4 infra VM (8c/16GB) + 50 題目 VM (各 1c/2GB) + 緩衝
  - 之前手動 CLI（`openstack quota set --instances 20 --cores 24 --ram 49152`）已同步回 code
- [x] **套用 quota 變更** — `cd platform && tofu plan && tofu apply`（2026-03-15 已套用）

#### 3.3.2 Nova 並發 spawn 修復

**問題**：並發 >6 個 VM spawn 時，部分 VM 進入 ERROR 狀態（玩家會看到錯誤）

**根因**：`ram_allocation_ratio = 1.0`（不 overcommit），兩台 node 合計 ~30GB RAM 扣除 infra 後只能放 ~6 個 small VM

**修復**：設定 `ram_allocation_ratio = 1.5`（允許 1.5x 記憶體 overcommit）

- [x] **Nova config as code** — `kolla-config/nova/nova-compute.conf` 已建立於 repo 中
- [x] **套用** — `make kolla-reconfigure-nova`（2026-03-15 已套用，3 nodes 全部成功）
- [x] **壓力測試驗證** — concurrency 10: 10/10 成功（修復前 6/10）
- [x] **對照測試** — 確認 `max_concurrent_builds` 非必要（移除後仍 10/10 成功且更快）

> `max_concurrent_builds` 已從設定中移除。詳見 `stress-test-results/summary.md`

#### 3.3.3 啟動時間優化（2026-03-15 實施）

> 單用戶啟動：63.5s → **46.8s**（-26%），且 URL 回來即可連線

- [x] **共用 Security Group** — `challenge_defaults.yml` 加入 `security_group_id: ctf-allow-all`，跳過 per-player SG 建立（-3s boot, -3s destroy）
- [x] **Readiness check** — scenario `waitForPort()` TCP 檢查，Pulumi 等服務就緒才回傳 URL。適用所有題型（HTTP/SSH/TCP）
- [x] **停用不必要 systemd services** — `base-setup.sh` purge snapd + disable ModemManager/udisks2/multipathd/unattended-upgrades/polkit 等（-5s boot）
- [x] **移除多餘 nginx** — web-example 用 Python server，不需要 nginx（-1s boot）
- [x] **Config-drive** — scenario `ConfigDrive: true` + image `datasource_list: [ConfigDrive]`，消除 DHCP metadata 等待（**-16s boot**，最大單一優化）
- [x] **Image 預熱** — `make packer-warmup IMAGE_ID=<id>` 在 compute node 預快取 image，消除 cold start penalty（-30s 首次）
- [x] **register-challenges.py 自動重建** — `--force` PATCH 失敗時自動 DELETE + POST，解決 chall-manager 重啟後狀態不一致

#### 3.3.4 進一步優化（可選）

- [ ] 增加 compute node 數量或 RAM（50 人比賽需 ~100GB RAM）
- [ ] 預分配 FIP pool 加速 boot（省 ~2-3s）
- [ ] `packer-build` 自動更新 `challenge.yml` 的 `image_id`（目前需手動）
- [ ] 考慮 container-based challenge 替代 VM（啟動 <5s）

### 3.6 Pooler 預分配池（2026-03-22 驗證成功）

> 實測結果：啟用 Pooler 後，容器題和 VM 題都從原本的 5s/60s+ 降到 ~5s（認領預建 instance）

- [x] **Pooler 功能驗證** — chall-manager 原生 Pooler 功能，CTFd UI 設定 min/max 即可
- [x] **Pooler as Code** — challenge.yml 的 `pool_min`/`pool_max` 由 register-challenges.py 自動 PATCH 到 CTFd（API 欄位名 `min`/`max`）
- [x] **Container Test (k8s-pod)** — min=3, max=5，預建 3 Pod，玩家 Boot ~5s 拿到 connection info
- [x] **Web Example (openstack-vm)** — min=2, max=3，預建 VM，玩家 Boot ~5s 拿到 connection info
- [x] **冷路徑加速：readiness_timeout** — openstack-vm 新增可配置 readiness_timeout（預設 "0" 跳過 waitForPort），冷建立 60s+ → ~24.5s
- [x] **冷路徑加速：共用 Namespace** — k8s-pod 預設用共用 challenges namespace（`use_shared_namespace=true`），省一次 K8s API call，加速 boot + destroy
- [x] **冷路徑加速：no-FIP 跳過 Port** — `use_fip=false` 時不明確建 Port，Nova 自動管理，Pulumi 少一個資源
- [x] **有 disk 的 challenge flavor** — 建立 `chall-1c2g-20d` / `chall-2c4g-20d`，跳過 boot_from_volume（省 volume 建立 23s）
- [x] **ForceDelete** — openstack-vm 加 `ForceDelete: true` 跳過 VM graceful shutdown
- [x] **Polling 加速** — waitForPort polling interval 2s→1s，dial timeout 3s→2s
- [x] **Destroy 異步化** — Patch CTFd plugin 的 delete handler 用 threading 背景執行 delete_instance，玩家點 Destroy 秒消失（與 timeout 到期行為一致）
- [x] **Race condition 修復** — CREATE handler 等待背景刪除完成（flag 檔消失）才呼叫 create_instance，避免新 instance 被背景 delete 誤殺。換題（刪 A 開 B）不受影響（不同 challenge_id 無 flag 檔）
- [x] **防濫用** — DELETE handler 檢查 flag 檔：已在刪除中則跳過（不重複觸發背景 thread）。搭配 mana=1 限制每人同時 1 台 instance

> 實測數據（lab50 環境 2026-03-22）：
> - OpenStack：Port 1.0s / Volume from image 23.3s / VM from volume 17.1s / VM from image (disk) 29.9s
> - chall-manager：CT Pool claim 2ms / CT cold 4.7s / VM cold (optimized) 24.5s / CT destroy 1.5s / VM destroy 11s (Nova 固有)
> - Destroy 異步化後：玩家體感 <1s（背景 11s 清理不影響 UX）
> - 同題重開：Destroy 秒回 + Boot 等 ~1.5s(CT)/~11s(VM) 背景刪除完成 + Pooler 認領
> - 換題：Destroy 秒回 + Boot 秒回（不同 challenge，無衝突）

### 3.4 未來升級：Ingress 模式（容器題）

**現狀：** k8s-pod scenario 使用 NodePort，玩家看到 `http://worker-ip:3xxxx`，不夠直覺。

**目標：** 改用 Nginx Ingress + wildcard DNS，每位玩家拿到子域名：
```
http://abc12345.ctf.example.com → Pod A
http://def67890.ctf.example.com → Pod B
```

- [ ] 部署 Nginx Ingress Controller 到 k3s
- [ ] 設定 wildcard DNS（`*.ctf.example.com → worker IP`）
- [ ] 修改 k8s-pod scenario：建立 Ingress 資源取代 NodePort Service
- [ ] connection_info 顯示子域名 URL 而非 IP:port

### 3.5 已修復的部署問題（2026-03-22）

- [x] **connection_info 寫死 nc 格式** — openstack-vm 和 k8s-pod scenario 加入 `connection_info` template 參數，支援 `{ip}` `{port}` 佔位符（預設 `nc {ip} {port}`，可設 `http://{ip}:{port}` 等）
- [x] **challenge.local.yml 環境覆蓋** — 新增 per-challenge gitignored 覆蓋檔，合併順序：`challenge_defaults.yml` → `challenge.yml` → `challenge.local.yml`。解決 image_id 等環境專屬值不該進 git 的問題
- [x] **kubeconfig 被 Docker 建成目錄** — chall-manager role 的 `docker compose up` 先於 k3s role 部署 kubeconfig，Docker bind mount 對不存在的 source 自動建目錄。修復：在 docker compose up 前預建 placeholder 空檔案

### 3.2 安全性強化

- [ ] `PULUMI_CONFIG_PASSPHRASE` 改為非空值（目前 state 未加密）
- [ ] k8s-pod scenario 加入 NetworkPolicy：限制題目 Pod 只能被外部存取，不能互相存取或存取 k3s 內部服務
- [ ] 評估是否需要 Pod Security Standards（restricted profile）防止容器逃逸

---

## 4. 已完成項目

- [x] ctfd/ 所有 module 的 `versions.tf` 補上 `version = "~> 3.4"` constraint（與 chell/ 一致）
- [x] 移除 `ctfd/modules/network/outputs.tf` 未使用的 `router_interface_id` output
- [x] **1.1 通用化 scenario**：兩個 scenario 遷移至 chall-manager SDK（`sdk.Run`）+ `configOrEnv()` 讀取 `additional`，Go 升級至 1.25.4
- [x] **2.1 Flag 生成統一**：兩個 scenario 改用 `sdk.Variate()`，移除自行維護的 hash 邏輯
- [x] **2.2 精簡 docker-compose**：移除 `CHALLENGE_*` 環境變數，題目設定改由 CTFd `additional` 傳入
- [x] **1.2 k8s-pod 加速**：`ImagePullPolicy: IfNotPresent` + k3s role pre-pull task（`k3s_challenge_prepull_images`）
- [x] **1.2 openstack-vm 平行化**：移除 Port/VM/FIP 冗餘 `DependsOn`，FIP 與 VM 平行建立
- [x] **1.2 共用 SG**：openstack-vm 支援 `security_group_id` additional key，跳過 per-player SG 建立
- [x] **1.2 Packer snapshot 基礎設施**：建立 `packer/` 目錄（plugins, source, build, scripts）+ `challenges/web-example/` 完整範例
- [x] **1.2 cloud-init flag 注入**：openstack-vm 新增 `UserData` 自動產生 cloud-config 寫入 per-player flag + `flag_path` / `cloud_init` additional key
- [x] **1.2 預分配 FIP**：openstack-vm 新增 `fip_address` additional key + `FloatingIpAssociate`
- [x] **1.2 輕量 flavor**：platform 新增 `general.tiny`（1C/1G/10G）
- [x] **Makefile Packer 整合**：新增 `packer-init` / `packer-validate` / `packer-build` targets
- [x] **1.3 challenge.yml 格式**：type 改為 `dynamic_iac`，基礎設施欄位移至 `challenge_defaults.yml`，scenario 短名稱自動展開
- [x] **1.3 Registration script**：`scripts/register-challenges.py` — 掃描 challenge.yml → CTFd API 自動建立/更新，支援 `--dry-run` / `--force`
- [x] **1.3 challenge_defaults.yml**：運維管理的 per-scenario 基礎設施預設值，與 challenge.yml additional 合併
- [x] **1.3 Makefile 整合**：新增 `register-challenges` / `register-challenges-dry` / `deploy-challenge` targets
- [x] **1.3 .env 管理**：`.env.example` 範本 + `.gitignore` 加入 `.env`
- [x] **1.3 challenge templates**：`_templates/k8s-pod.yml` + `_templates/openstack-vm.yml`
- [x] **Packer file provisioner**：`build.pkr.hcl` 新增 file provisioner + `challenge_files` 變數，支援複製題目原始碼到 VM

---

## 決策紀錄

- **openstack-vm scenario 保留** — 這是研究核心，不可捨棄。需要透過 snapshot、平行化等方式解決啟動速度問題。
- **VM pool 改用 chall-manager Pooler** — 之前「暫不實作」改為直接使用 chall-manager 原生 Pooler（2026-03-22 驗證成功）。零程式碼改動，CTFd UI 設定 min/max 即可。預建 instance 認領 <1ms（官方文件），實測含 CTFd UI 開銷 ~5s。資源策略：CT min=5（成本低）、VM min=3（每台 2GB RAM），搭配 mana 限制和題目分波釋出。
- **chall-manager 不可替換，且功能足夠** — 已確認原生支援 `additional`（per-challenge `map<string,string>`），可解決多題目設定問題。需改用官方 SDK 來讀取。
- **Image 分發採 pre-pull 策略** — 容器題：Ansible 預先 `crictl pull` 到 worker + `ImagePullPolicy: IfNotPresent`。VM 題：預先 bake snapshot image。兩者都是「賽前準備、賽中即用」。比賽中需更新時可重新 pull/snapshot 並更新 `additional`。
- **Snapshot 製作用 Packer** — 出題者寫 Packer template（OpenStack builder + provision script），`packer build` 產出 image。放在 `challenges/` 目錄版本控制。
- **Runbook 待實作完 1.1/1.2 後撰寫** — 具體步驟會隨改造而變，先保留在 TODO 1.3 的出題者文件中一併處理。
- **chall-manager SDK 用 v0.6.3** — 與 pulumi-openstack v3 無衝突（SDK 不依賴 pulumi-openstack）。需升級 Go 至 1.25+（目前 scenario 用 Go 1.22）。pulumi/sdk/v3 和 pulumi-kubernetes/v4 為 minor bump，相容。
- **Challenge as Code 採 CTFd API 路線** — 只透過 CTFd REST API 操作，不直接呼叫 chall-manager API。CTFd chall-manager plugin 會自動將題目同步到 chall-manager（scenario 註冊、additional 傳遞）。這樣只需維護一個 API 介面，且與 CTFd Web UI 完全一致。
- **Registration script 用 Python** — CTFd API 回傳 JSON，Python 的 requests + PyYAML 處理最自然。Bash + curl 可行但 JSON 處理不便、錯誤處理困難。Python 在 CTFd VM 上已可用（Ubuntu 預裝），管理機上也有。
- **不用 ctfcli** — CTFd 官方 CLI 不支援 chall-manager plugin 的 scenario / additional 欄位，需要自建。
- **Quota as Code** — OpenStack quota 由 OpenTofu `platform/main.tf` 管理（`openstack_compute_quotaset_v2` + `openstack_networking_quota_v2`），不手動 CLI。Nova 層級設定（`ram_allocation_ratio`）屬於 Kolla-Ansible 管理（`kolla-config/nova/nova-compute.conf`），不在 OpenTofu 範圍。兩者都寫在 code 中版本控制。
- **`max_concurrent_builds` 不需要** — 壓力測試對照實驗確認並發 spawn 失敗的根因是記憶體 allocation 不足（`ratio=1.0`），非 Nova compute 並發限制。移除 `max_concurrent_builds` 後反而更快（無排隊開銷）。
- **CTFd challenge type 為 `dynamic_iac`** — chall-manager plugin 註冊的 type 名稱是 `dynamic_iac`，不是 `chall_manager`。需要 `initial`/`decay`/`minimum` 動態計分欄位。
- **Ops/Creator 分離** — challenge.yml 只放出題者關心的欄位（name, category, flag, port）。基礎設施設定（network_id, flavor, SG）由 `challenge_defaults.yml` 提供，registration script 自動合併。
- **Config-drive 優於 metadata service** — 壓力測試發現 cloud-init DHCP→metadata 等待耗時 ~23s。改用 config-drive（metadata 燒成 ISO 掛載）後此等待消除，是最大單一優化（-16s）。cloud-init network config 不可停用（VM 仍需 DHCP 取得 IP），但 datasource 可改為 ConfigDrive 優先。
- **Readiness check 用 TCP 而非 HTTP** — scenario 中的 `waitForPort()` 使用 TCP connect 檢查（`net.DialTimeout`），適用所有題型（HTTP/SSH/TCP/NC）。timeout 120s 不會 fail deployment，只 log warning。玩家拿到 URL 時保證服務已就緒。
- **Image 預熱必要** — 新 image 首次在 compute node 上使用時有 ~30s cold start penalty（Glance→本地 cache 複製）。`make packer-warmup` 透過建立/刪除暫時 VM 觸發 cache。賽前必須執行。
- **VM Destroy 異步化** — Nova VM 刪除固有耗時 ~11s（Pulumi poll 等 instance 消失），無法從程式碼層面加速。解法：Patch CTFd plugin 的 delete handler 用 `threading.Thread` 背景執行 `delete_instance`，玩家體感 <1s。與 timeout 到期自動消失的行為一致。Ansible 每次部署自動重新打 patch（冪等）。
- **Async destroy race condition** — 背景 thread 刪除舊 instance 的同時 create 新 instance 會導致新 instance 被誤殺（同一 challenge_id/source_id）。CREATE handler 必須等 flag 檔消失（= 刪除完成）再呼叫 create_instance。換題（刪 A 開 B）不受此限制。
- **Pooler API 欄位名** — CTFd chall-manager plugin model 的 Pooler 欄位名是 `min` 和 `max`（不是 `pool_min`/`pool_max`）。不能在 POST 建題時帶入（會 500），必須先 POST 再 PATCH。
- **測試殘留資源清理** — Pooler + 測試迭代會累積大量 ctf-* VM/volume/port，需定期清理。流程：停 chall-manager → `openstack server delete` 所有 ctf-* → 清 orphan volume/port → 啟 chall-manager → 重新 register-challenges。
