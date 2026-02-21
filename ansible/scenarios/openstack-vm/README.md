# Scenario: openstack-vm

為每位 CTF 玩家在 OpenStack 動態建立獨立的 VM 靶機。

## chall-manager 規範

| 項目 | 值 |
|------|----|
| Config key | `openstack-vm:identity`（chall-manager 自動注入，唯一來源） |
| Output `connection_info` | 玩家連線 URL，例如 `http://10.0.2.x:8080` |
| Output `flag` | 動態 flag，依 identity 生成，每人唯一 |

## 建立的資源

每個 instance 會建立（`{short_id}` = MD5(identity)[:8]）：

```
ctf-{short_id}-sg       Security Group
ctf-{short_id}-vm       VM
ctf-{short_id}-fip      Floating IP
ctf-{short_id}-fip-assoc  FloatingIpAssociate
```

## 設定來源（環境變數）

由 chall-manager Docker 容器繼承（在 `docker-compose.yml` 中定義）：

| 環境變數 | 說明 |
|---------|------|
| `CHALLENGE_IMAGE_ID` | VM Image UUID（platform tofu output） |
| `CHALLENGE_NETWORK_ID` | 內部網路 UUID（ctfd tofu output） |
| `CHALLENGE_FLAVOR` | VM 規格，預設 `general.small` |
| `CHALLENGE_PORT` | 題目對外 Port，預設 `8080` |
| `CHALLENGE_FIP_POOL` | Floating IP 外部網路名稱，預設 `public` |
| `CHALLENGE_BASE_FLAG` | 動態 flag 的基底內容（不含 `CTF{}`） |
| `CHALLENGE_FLAG_PREFIX` | Flag 前綴，預設 `CTF` |

## 本機手動測試

```bash
cd ansible/scenarios/openstack-vm

# 安裝依賴
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# 設定環境變數
export PULUMI_BACKEND_URL="file:///tmp/pulumi-test"
export PULUMI_CONFIG_PASSPHRASE=""
export OS_AUTH_URL="http://192.168.15.200:5000/v3"
export OS_PROJECT_NAME="ctfd"
export OS_USERNAME="ctfd-deployer"
export OS_PASSWORD="your-password"
export OS_USER_DOMAIN_NAME="Default"
export OS_PROJECT_DOMAIN_NAME="Default"
export OS_IDENTITY_API_VERSION="3"
export CHALLENGE_IMAGE_ID="<uuid>"
export CHALLENGE_NETWORK_ID="<uuid>"
export CHALLENGE_BASE_FLAG="test_flag_content"

# 測試部署
pulumi stack init test --non-interactive
pulumi config set openstack-vm:identity "test-user-001"
pulumi up --yes
pulumi stack output connection_info
pulumi stack output flag

# 清理
pulumi destroy --yes
pulumi stack rm test --yes
```

## 打包為 OCI artifact（由 Ansible 自動執行）

```bash
# Ansible task 會自動執行以下步驟：
pip install -r requirements.txt         # 安裝 venv
zip -r /tmp/openstack-vm.zip . ...      # 打包
oras push --insecure \
  localhost:5000/openstack-vm:latest \
  /tmp/openstack-vm.zip:application/zip
```
