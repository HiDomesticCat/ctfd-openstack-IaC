# OpenTofu 1.11 Precondition 使用說明

## 功能說明

使用 OpenTofu 1.11 的新功能 `precondition` 來實現刪除保護。這比單純的 `prevent_destroy` 更靈活，因為可以基於變數條件來決定是否允許刪除。

## 實現方式

### 1. 動態刪除保護

在 [`modules/project/main.tf`](tofu_iac/platform/modules/project/main.tf) 中：

```hcl
resource "openstack_identity_project_v3" "this" {
  name        = var.project_name
  description = var.project_description
  enabled     = true

  lifecycle {
    # OpenTofu 1.11+ precondition：刪除前的條件檢查
    # 注意：prevent_destroy 不能使用變數，所以只使用 precondition
    precondition {
      condition     = var.environment != "production"
      error_message = "Production 環境的 project 不允許直接刪除。請先設定 environment = \"dev\" 或 \"staging\"。"
    }
  }
}
```

**重要說明**: `prevent_destroy` 不能使用變數或表達式，必須是靜態布林值。因此我們使用 `precondition` 來實現基於變數的動態刪除保護。

## 使用場景

### 場景 1：開發環境（允許刪除）

```bash
# 設定為開發環境
export TF_VAR_environment="dev"

# 可以正常刪除資源
terraform destroy
```

### 場景 2：生產環境（阻止刪除）

```bash
# 預設或明確設定為生產環境
export TF_VAR_environment="production"

# 嘗試刪除會被阻止
terraform destroy
# 錯誤：Production 環境的 ctfd project 不允許直接刪除
```

### 場景 3：生產環境臨時允許刪除

如果確實需要刪除生產環境資源：

```bash
# 方法 1：暫時改為 staging
export TF_VAR_environment="staging"
terraform destroy

# 方法 2：修改 main.tf 中的 environment 參數
# module "ctfd_project" {
#   environment = "staging"  # 臨時改為 staging
#   ...
# }
```

## Precondition vs Prevent_Destroy

### Prevent_Destroy
- ✅ 簡單直接
- ✅ 硬性保護（無法繞過）
- ❌ **不能使用變數**（必須是靜態布林值）
- ❌ 必須修改程式碼才能解除

### Precondition (OpenTofu 1.11+)
- ✅ **可以基於變數動態判斷**
- ✅ 更靈活的控制邏輯
- ✅ 更清晰的錯誤訊息
- ✅ 可以同時使用多個條件
- ✅ 可以輕鬆透過環境變數切換

## 關鍵限制

**⚠️ prevent_destroy 不能使用變數！**

```hcl
# ❌ 錯誤：prevent_destroy 不能使用變數
lifecycle {
  prevent_destroy = var.environment == "production"  # 會報錯！
}

# ✅ 正確：使用 precondition
lifecycle {
  precondition {
    condition     = var.environment != "production"
    error_message = "Production 環境不允許刪除。"
  }
}

# ✅ 也正確：靜態 prevent_destroy + precondition
lifecycle {
  prevent_destroy = true  # 靜態值

  precondition {
    condition     = var.environment != "production"
    error_message = "Production 環境不允許刪除。"
  }
}
```

## 最佳實踐：只使用 Precondition

對於需要基於環境動態控制的場景，建議只使用 `precondition`：

```hcl
lifecycle {
  # 只使用 precondition，因為它支援變數
  precondition {
    condition     = var.environment != "production"
    error_message = "Production 環境不允許直接刪除。請先設定 environment = \"dev\" 或 \"staging\"。"
  }
}
```

## 進階用法

### 多重條件保護

```hcl
lifecycle {
  # 生產環境的重要專案不允許刪除
  precondition {
    condition = (
      var.environment != "production" ||
      !contains(["ctfd", "critical-app", "database"], var.project_name)
    )
    error_message = "Production 環境的關鍵專案 (${var.project_name}) 不允許刪除。"
  }

  # 必須提供刪除原因
  precondition {
    condition     = var.deletion_reason != "" || var.environment != "production"
    error_message = "刪除生產環境資源需要提供 deletion_reason 變數。"
  }
}
```

### 時間窗口控制

```hcl
locals {
  # 只允許在維護時間窗口刪除
  is_maintenance_window = (
    timeadd(timestamp(), "0h") >= "2024-01-01T02:00:00Z" &&
    timeadd(timestamp(), "0h") <= "2024-01-01T04:00:00Z"
  )
}

resource "..." {
  lifecycle {
    precondition {
      condition     = local.is_maintenance_window || var.environment != "production"
      error_message = "生產環境資源只能在維護時間窗口（02:00-04:00 UTC）刪除。"
    }
  }
}
```

## 與現有保護的比較

| 方法 | 靜態/動態 | 靈活性 | 錯誤訊息 | OpenTofu 版本需求 |
|------|----------|--------|----------|------------------|
| prevent_destroy | 靜態 | 低 | 一般 | 所有版本 |
| prevent_destroy (條件式) | 動態 | 中 | 一般 | >= 0.15 |
| precondition | 動態 | 高 | 自定義 | >= 1.11 |

## 注意事項

1. **Precondition 在刪除時檢查**
   - 資源刪除時會評估 precondition
   - 條件失敗會阻止刪除操作

2. **與 prevent_destroy 組合使用**
   - 可以同時使用兩者
   - prevent_destroy 提供硬保護
   - precondition 提供軟保護和更好的錯誤訊息

3. **版本要求**
   - 需要 OpenTofu >= 1.11.0 或 Terraform >= 1.9.0
   - 舊版本會忽略 precondition（降級處理）

4. **測試建議**
   ```bash
   # 測試刪除保護是否生效
   export TF_VAR_environment="production"
   terraform plan -destroy  # 應該顯示錯誤
   
   export TF_VAR_environment="dev"
   terraform plan -destroy  # 應該成功
   ```

## 實際案例

### 案例 1：部署到開發環境
```bash
export TF_VAR_environment="dev"
export TF_VAR_ctfd_deployer_password="DevPassword123!"
terraform apply  # 資源可正常創建和刪除
```

### 案例 2：部署到生產環境
```bash
export TF_VAR_environment="production"
export TF_VAR_ctfd_deployer_password="ProdPassword123!"
terraform apply  # 資源受保護
terraform destroy  # 被 precondition 阻止
```

### 案例 3：緊急刪除生產資源
```bash
# 需要先改為非生產環境
export TF_VAR_environment="staging"
terraform destroy  # 現在可以執行
# 記得在完成後恢復設定
```
