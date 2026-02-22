# Scenario: k8s-pod

為每位 CTF 玩家在 k3s 叢集動態建立獨立的 Kubernetes Pod 靶機。

## chall-manager 規範

| 項目 | 值 |
|------|----|
| Config key | `k8s-pod:identity`（chall-manager 自動注入，唯一來源） |
| Output `connection_info` | 玩家連線指令，例如 `ssh ctf@10.0.2.x -p 31234` |
| Output `flag` | 動態 flag，依 identity 生成，每人唯一 |

## 建立的 Kubernetes 資源

每個 instance 會建立（`{short_id}` = MD5(identity)[:8]）：

```
ctf-{short_id}              Namespace（玩家隔離）
ctf-{short_id}              Pod（challenge 靶機）
ctf-{short_id}-svc          NodePort Service（玩家連線入口）
```

## 環境變數設定

由 chall-manager Docker 容器繼承（在 `docker-compose.yml` 中定義）：

| 環境變數 | 說明 |
|---------|------|
| `CHALLENGE_IMAGE` | 靶機容器 image（例如 `my-registry/ctf-challenge:latest`） |
| `CHALLENGE_PORT` | 靶機對外 Port，預設 `22`（SSH）|
| `CHALLENGE_BASE_FLAG` | 動態 flag 的基底內容（不含 `CTF{}`） |
| `CHALLENGE_FLAG_PREFIX` | Flag 前綴，預設 `CTF` |
| `K3S_WORKER_IPS` | Worker 節點 IP（逗號分隔），取第一個作為連線 IP |
| `KUBECONFIG` | k3s kubeconfig 路徑（`/kubeconfig/k3s.yaml`） |

## 連線方式

玩家透過 NodePort 連線（自動分配在 30000-32767 範圍）：

```bash
# SSH challenge
ssh ctf@<worker-ip> -p <nodeport>

# 自訂 port challenge
nc <worker-ip> <nodeport>
```

## 資源限制

每個 Pod 預設資源限制：
- CPU request: 100m / limit: 500m
- Memory request: 128Mi / limit: 512Mi

可透過修改 `main.go` 調整。

## 本機手動測試

```bash
cd ansible/scenarios/k8s-pod

# 安裝 Go 依賴
go mod tidy

# 設定環境變數
export PULUMI_BACKEND_URL="file:///tmp/pulumi-k8s-test"
export PULUMI_CONFIG_PASSPHRASE=""
export KUBECONFIG="/path/to/k3s-kubeconfig"
export CHALLENGE_IMAGE="ubuntu:22.04"
export CHALLENGE_PORT="22"
export CHALLENGE_BASE_FLAG="test_flag_content"
export K3S_WORKER_IPS="<worker-floating-ip>"

# 編譯
go build -o main .

# 測試部署
pulumi stack init test --non-interactive
pulumi config set k8s-pod:identity "test-player-001"
pulumi up --yes
pulumi stack output connection_info
pulumi stack output flag

# 清理
pulumi destroy --yes
pulumi stack rm test --yes
```

## 打包為 OCI artifact（由 Ansible 自動執行）

Ansible 的 chall-manager role 會自動：
1. 編譯 Go binary（`go build -o main .`）
2. 打包為 OCI artifact（`oras push`）並推送到 local registry
3. 預熱 chall-manager cache

## 注意事項

- `KUBECONFIG` 需掛載到 chall-manager 容器，由 Ansible k3s role 負責設定
- `K3S_WORKER_IPS` 需填入 `ansible/group_vars/all/k3s.yml`
- Worker 節點的 NodePort (30000-32767) 需開放在 OpenStack Security Group（由 chell/ tofu 自動設定）
