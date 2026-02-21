# Scenario: openstack-vm

為每位 CTF 玩家在 OpenStack 動態建立獨立的 VM 靶機。

## 資源

每個 instance 會建立：
- `ctf-{challenge_id}-{player_id}-sg` — 獨立 Security Group
- `ctf-{challenge_id}-{player_id}` — VM
- `ctf-{challenge_id}-{player_id}-fip` — Floating IP

## 使用前準備

### 1. 設定 Pulumi.yaml 中的 config defaults

```bash
vim Pulumi.yaml
# 填入 image_id, network_id
```

### 2. 安裝 Python 依賴

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3. 手動測試（可選）

```bash
# 設定 OpenStack 憑證
export OS_AUTH_URL="http://192.168.15.200:5000/v3"
export OS_PROJECT_NAME="ctfd"
export OS_USERNAME="ctfd-deployer"
export OS_PASSWORD="your-password"
export OS_USER_DOMAIN_NAME="Default"
export OS_PROJECT_DOMAIN_NAME="Default"
export OS_IDENTITY_API_VERSION="3"

# 使用 local backend
export PULUMI_BACKEND_URL="file:///tmp/pulumi-test"
export PULUMI_CONFIG_PASSPHRASE=""

# 建立測試 stack
pulumi stack init test
pulumi config set player_id "testplayer"
pulumi config set challenge_id "web01"
pulumi config set image_id "your-image-uuid"
pulumi config set network_id "your-network-uuid"

pulumi up --yes
# 查看輸出
pulumi stack output

# 清理
pulumi destroy --yes
pulumi stack rm test
```

## chall-manager 整合

chall-manager 在玩家按下「開啟靶機」時自動執行：
1. `pulumi stack init ctfd-{challenge_id}-{player_id}`
2. 設定 `player_id`, `challenge_id` config
3. `pulumi up --yes`
4. 讀取 `connection_info` output 回傳給玩家

到期時自動執行：
1. `pulumi destroy --yes`
2. `pulumi stack rm`
