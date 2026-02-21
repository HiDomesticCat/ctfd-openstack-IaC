# CTFd Platform Infrastructure

OpenStack 基礎設施配置，用於 CTFd 競賽平台。

## 已修復的問題

### ✅ 關鍵問題修復
1. **語法錯誤** - 移除了 `modules/project/variables.tf` 中的重複變數聲明
2. **安全性** - 密碼不再存於 outputs 中，需透過環境變數管理
3. **依賴關係** - 配額資源現在正確依賴於角色分配
4. **完整配額** - 支援完整的計算、網路和儲存配額設定
5. **輸入驗證** - 添加了變數驗證規則
6. **生命週期保護** - 重要資源有 prevent_destroy 保護

## 環境需求

- OpenTofu/Terraform >= 1.11.0
- OpenStack 訪問權限
- 已配置 `~/.config/openstack/clouds.yaml`

## 快速開始

### 1. 設定憑證

**選項 A: 使用環境變數（推薦）**
```bash
export TF_VAR_ctfd_deployer_password="YourSecurePassword123!"
export TF_VAR_openstack_cloud="openstack"  # 可選，預設值為 "openstack"
```

**選項 B: 使用 tfvars 檔案（本地開發）**
```bash
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars 並設定密碼（不要提交到 git！）
```

### 2. 初始化並部署

```bash
# 初始化
terraform init

# 檢查變更（使用包裝腳本）
./tofu-safe plan

# 套用配置
./tofu-safe apply
```

## 變數說明

### 必要變數
- `ctfd_deployer_password` - CTFd 部署帳號密碼（至少 12 字元，需包含大小寫字母和數字）

### 可選變數
- `environment` - 環境名稱（預設: "production"）
  - `dev` - 開發環境（允許刪除資源）
  - `staging` - 測試環境（允許刪除資源）
  - `production` - 生產環境（啟用刪除保護）
- `openstack_cloud` - OpenStack cloud 名稱（預設: "openstack"）

## 配額設定

預設配額：
- **計算**: 5 實例, 8 核心, 16GB RAM
- **網路**: 3 浮動 IP, 10 網路, 10 子網, 5 路由器
- **儲存**: 5 卷, 500GB, 10 快照

修改 `main.tf` 中的 `quota` 區塊來調整。

## 刪除保護機制

### 使用包裝腳本（推薦）

本配置提供 `tofu-safe` 包裝腳本來防止誤刪生產環境：

```bash
# 使用 tofu-safe 替代 tofu
./tofu-safe plan
./tofu-safe apply
./tofu-safe destroy  # 生產環境會被阻止
```

**生產環境（預設）:**
```bash
$ ./tofu-safe destroy
📋 當前環境: production
❌ 錯誤：不允許刪除生產環境！
```

**開發/測試環境:**
```bash
$ export TF_VAR_environment="dev"
$ ./tofu-safe destroy
📋 當前環境: dev
⚠️  警告：即將刪除 dev 環境的所有資源
▶️  執行: tofu destroy
```

### 靜態防護（生產環境）

對於生產環境，建議啟用資源級別的 `prevent_destroy`：

1. 編輯 [`modules/project/main.tf`](modules/project/main.tf)
2. 取消 `prevent_destroy = true` 的註解
3. 重新部署

詳細說明請參考 [`DELETION_PROTECTION.md`](DELETION_PROTECTION.md)

## 安全最佳實踐

### 密碼管理
```bash
# 使用環境變數
export TF_VAR_ctfd_deployer_password="$(pass show ctfd/deployer)"

# 或使用密鑰管理系統
export TF_VAR_ctfd_deployer_password="$(vault kv get -field=password secret/ctfd)"
```

### State 檔案加密
編輯 `versions.tf` 並啟用遠程 backend：

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "platform/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "terraform-state-lock"
}
```

## Outputs

- `ctfd_project_id` - 建立的 Project ID
- `ctfd_credentials` - 連線資訊（不含密碼）

## 故障排除

### 驗證密碼複雜度
密碼必須：
- 至少 12 個字元
- 包含大寫字母
- 包含小寫字母
- 包含數字

### 檢查配置
```bash
terraform validate
terraform fmt -check -recursive
```

### 匯入既有資源
```bash
terraform import module.ctfd_project.openstack_identity_project_v3.this <project-id>
terraform import module.ctfd_project.openstack_identity_user_v3.this <user-id>
```

## 目錄結構

```
platform/
├── main.tf              # 主要配置
├── variables.tf         # 輸入變數
├── outputs.tf          # 輸出值
├── versions.tf         # Provider 和 backend 配置
├── .gitignore          # Git 忽略檔案
├── terraform.tfvars.example  # 範例配置
└── modules/
    └── project/        # 可重用的 Project 模組
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## 注意事項

⚠️ **重要安全提醒**
- 永遠不要提交 `terraform.tfvars` 到版本控制
- State 檔案包含敏感資料，需使用加密的遠程 backend
- 定期輪換密碼
- 使用最小權限原則

## Module 重用

此 project 模組可重用於其他環境：

```hcl
module "dev_project" {
  source = "./modules/project"

  project_name        = "dev-environment"
  project_description = "開發環境"
  username            = "dev-deployer"
  password            = var.dev_password
  role                = "member"
  enable_quota        = true
  quota               = { ... }
}
```
