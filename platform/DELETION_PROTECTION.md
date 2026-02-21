# 刪除保護機制說明

## ⚠️ 重要更正

**Precondition 不能用於刪除保護！**

經過測試發現，Terraform/OpenTofu 的 `precondition` 只在資源**創建/更新**時觸發，**不會在刪除時觸發**。

## Terraform/OpenTofu 刪除保護的限制

### prevent_destroy 
- ✅ **唯一**能阻止刪除的原生方法
- ❌ **必須是靜態布林值**，不能使用變數或表達式
- ❌ 必須修改代碼才能啟用/禁用

### precondition/postcondition
- ❌ 只在創建/更新時觸發
- ❌ **刪除操作不會檢查這些條件**

## 實際可用的解決方案

### 方案 1：靜態 prevent_destroy（推薦用於生產環境）

**優點**: 最安全，無法繞過  
**缺點**: 需要修改代碼才能刪除

```hcl
# modules/project/main.tf
resource "openstack_identity_project_v3" "this" {
  name        = var.project_name
  description = var.project_description
  enabled     = true

  lifecycle {
    prevent_destroy = true  # 生產環境啟用
  }
}
```

**解除方法**:
```bash
# 1. 註解掉 prevent_destroy
# lifecycle {
#   prevent_destroy = true
# }

# 2. 重新初始化
tofu init -reconfigure

# 3. 執行刪除
tofu destroy

# 4. 恢復防護（如果需要重新部署）
# lifecycle {
#   prevent_destroy = true
# }
```

### 方案 2：使用 Terraform Workspaces

**優點**: 不同環境使用不同配置  
**缺點**: 需要維護多個 state

```bash
# 開發環境（無防護）
tofu workspace new dev
tofu apply

# 生產環境（有防護）
tofu workspace new production
# 修改代碼啟用 prevent_destroy
tofu apply
```

### 方案 3：分離配置檔案

**優點**: 清晰分離  
**缺點**: 需要維護多套配置

```
platform/
├── environments/
│   ├── dev/
│   │   └── main.tf          # 無 prevent_destroy
│   └── production/
│       └── main.tf          # 有 prevent_destroy
└── modules/
    └── project/
```

### 方案 4：CI/CD 管道控制（推薦）

**優點**: 外部控制，靈活且安全  
**缺點**: 需要 CI/CD 設置

在 CI/CD 管道中添加檢查：

```yaml
# .github/workflows/terraform.yml
name: Terraform

on:
  pull_request:
    branches: [main]

jobs:
  prevent-destroy:
    runs-on: ubuntu-latest
    steps:
      - name: Check if destroying production
        run: |
          if [[ "${{ github.event_name }}" == "destroy" ]] && [[ "${{ env.ENVIRONMENT }}" == "production" ]]; then
            echo "❌ Cannot destroy production environment"
            exit 1
          fi
```

### 方案 5：外部腳本包裝（簡單有效）

創建包裝腳本控制刪除：

```bash
#!/bin/bash
# tofu-wrapper.sh

ENVIRONMENT=${TF_VAR_environment:-production}

if [[ "$1" == "destroy" ]] && [[ "$ENVIRONMENT" == "production" ]]; then
    echo "❌ 錯誤：不允許刪除生產環境！"
    echo "如果確實需要刪除，請執行："
    echo "  export TF_VAR_environment=dev"
    echo "  tofu destroy"
    exit 1
fi

# 執行實際的 tofu 命令
tofu "$@"
```

使用方式：
```bash
# 開發環境
export TF_VAR_environment="dev"
./tofu-wrapper.sh destroy  # ✅ 允許

# 生產環境
export TF_VAR_environment="production"
./tofu-wrapper.sh destroy  # ❌ 阻止
```

## 當前實現

目前代碼採用**方案 1 的變體**：

```hcl
lifecycle {
  # 靜態刪除保護：生產環境請手動啟用
  # 取消下一行的註解以啟用刪除保護
  # prevent_destroy = true
}
```

### 使用建議

#### 開發/測試環境
- 保持 `prevent_destroy` 註解狀態（已禁用）
- 可以自由創建和刪除資源

#### 生產環境
1. **部署前**: 取消 `prevent_destroy` 的註解
   ```hcl
   lifecycle {
     prevent_destroy = true
   }
   ```

2. **部署**: 
   ```bash
   tofu apply
   ```

3. **如需刪除**: 
   - 先註解 `prevent_destroy`
   - 提交 pull request 記錄
   - 經審核後執行刪除
   - 刪除後重新啟用保護

## 推薦的最佳實踐

### 小型團隊
- 方案 1（靜態 prevent_destroy）+ 方案 5（外部腳本）

### 中型團隊
- 方案 3（分離配置）+ 方案 4（CI/CD控制）

### 企業級
- 方案 2（Workspaces）+ 方案 4（CI/CD管道）+ Terraform Cloud/Enterprise

## 總結

| 方案 | 安全性 | 靈活性 | 複雜度 | 適用場景 |
|------|--------|--------|--------|----------|
| 靜態 prevent_destroy | 最高 | 最低 | 最低 | 生產環境 |
| Workspaces | 高 | 中 | 中 | 多環境管理 |
| 分離配置 | 高 | 中 | 中 | 清晰分離 |
| CI/CD 控制 | 高 | 高 | 高 | 團隊協作 |
| 外部腳本 | 中 | 高 | 低 | 快速實施 |

**結論**: Terraform/OpenTofu 沒有原生的基於變數的動態刪除保護。必須使用靜態 `prevent_destroy` 或外部控制機制。
