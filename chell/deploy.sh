#!/usr/bin/env bash
# chell/deploy.sh
# 自動化：tofu apply → 擷取 outputs → ansible-playbook
#
# 用法：
#   ./deploy.sh                                          # 互動式（推薦）
#   AUTO_APPROVE=true ./deploy.sh                        # tofu 自動確認
#   VAULT_PASS_FILE=~/.vault_pass ./deploy.sh            # ansible vault 免輸入
#   AUTO_APPROVE=true VAULT_PASS_FILE=~/.vault_pass ./deploy.sh  # 全自動

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"

AUTO_APPROVE="${AUTO_APPROVE:-false}"
SKIP_ANSIBLE="${SKIP_ANSIBLE:-false}"
VAULT_PASS_FILE="${VAULT_PASS_FILE:-}"

# ── 確保 ansible-playbook 可用 ──────────────────────────
# 若 venv 存在且 ansible-playbook 不在 PATH 中，自動 activate
KOLLA_VENV="$HOME/kolla-venv"
if ! command -v ansible-playbook &>/dev/null && [[ -f "$KOLLA_VENV/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source "$KOLLA_VENV/bin/activate"
fi

# ── 顏色輸出 ──────────────────────────────────────────────
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}==>${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC} $*"; }

# ── Step 1: tofu apply ────────────────────────────────────
info "[1/3] tofu apply (工作目錄: $SCRIPT_DIR)"
cd "$SCRIPT_DIR"

if [[ "$AUTO_APPROVE" == "true" ]]; then
  tofu apply -auto-approve
else
  tofu apply
fi
success "tofu apply 完成"

# ── Step 2: 擷取 outputs ──────────────────────────────────
info "[2/3] 擷取 tofu outputs..."

MASTER_IP=$(tofu output -raw master_floating_ip)
WORKER_MGMT_IPS_JSON=$(tofu output -json worker_floating_ips)
if K3S_WORKER_IPS_JSON=$(tofu output -json worker_challenge_net_ips 2>/dev/null) && [[ "$K3S_WORKER_IPS_JSON" != "[]" ]]; then
  K3S_WORKER_IPS_LABEL="worker challenge-net IPs"
else
  K3S_WORKER_IPS_JSON="$WORKER_MGMT_IPS_JSON"
  K3S_WORKER_IPS_LABEL="worker floating IPs (fallback)"
fi
K3S_API_URL=$(tofu output -raw k3s_api_url 2>/dev/null || echo "https://${MASTER_IP}:6443")

echo "    Master floating IP : $MASTER_IP"
echo "    Worker floating IPs: $WORKER_MGMT_IPS_JSON"
echo "    K3S_WORKER_IPS     : $K3S_WORKER_IPS_JSON ($K3S_WORKER_IPS_LABEL)"
echo "    k3s API URL        : $K3S_API_URL"

if [[ "$SKIP_ANSIBLE" == "true" ]]; then
  warn "SKIP_ANSIBLE=true，跳過 ansible 步驟"
  echo ""
  echo "可手動執行："
  echo "  cd $ANSIBLE_DIR"
  echo "  ansible-playbook site.yml \\"
  echo "    -i inventory/hosts.ini \\"
  echo "    -i inventory/k3s_hosts.ini \\"
  echo "    --extra-vars '{\"k3s_worker_ips\": $K3S_WORKER_IPS_JSON}' \\"
  echo "    --ask-vault-pass"
  exit 0
fi

# ── Step 3: 等待 VM SSH 就緒 ─────────────────────────────
# 只等 SSH（port 22），不等 k3s API（port 6443）
# 因為 k3s 是由 Ansible 安裝的，等 6443 會永遠卡住
ALL_IPS=("$MASTER_IP")
for ip in $(echo "$WORKER_MGMT_IPS_JSON" | tr -d '[]"' | tr ',' ' '); do
  ALL_IPS+=("$ip")
done

TIMEOUT=180
for ip in "${ALL_IPS[@]}"; do
  info "[2.5/3] 等待 ${ip}:22 (SSH) 就緒..."
  ELAPSED=0
  until nc -z "$ip" 22 2>/dev/null; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
      echo ""
      warn "逾時 ${TIMEOUT}s，${ip} SSH 尚未就緒"
      warn "請確認 VM 狀態後手動重試"
      exit 1
    fi
    echo -n "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
  done
  echo ""
  success "${ip} SSH 已就緒（等待 ${ELAPSED}s）"
done

# ── Step 4: ansible-playbook ──────────────────────────────
info "[3/3] 執行 ansible-playbook..."
cd "$ANSIBLE_DIR"

ANSIBLE_ARGS=(
  site.yml
  -i inventory/hosts.ini
  -i inventory/k3s_hosts.ini
  --extra-vars "{\"k3s_worker_ips\": ${K3S_WORKER_IPS_JSON}}"
)

# 只在有 vault 加密檔時才要求密碼
HAS_VAULT=$(grep -rl '^\$ANSIBLE_VAULT' "$ANSIBLE_DIR" 2>/dev/null | head -1 || true)
if [[ -n "$VAULT_PASS_FILE" ]]; then
  ANSIBLE_ARGS+=(--vault-password-file "$VAULT_PASS_FILE")
elif [[ -n "$HAS_VAULT" ]]; then
  ANSIBLE_ARGS+=(--ask-vault-pass)
fi

ansible-playbook "${ANSIBLE_ARGS[@]}"

success "部署完成！"
echo ""
echo "k3s API   : $K3S_API_URL"
echo "Master SSH: ssh ubuntu@${MASTER_IP}"
