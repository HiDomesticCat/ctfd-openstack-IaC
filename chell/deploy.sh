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
WORKER_IPS_JSON=$(tofu output -json worker_floating_ips)
K3S_API_URL=$(tofu output -raw k3s_api_url 2>/dev/null || echo "https://${MASTER_IP}:6443")

echo "    Master floating IP : $MASTER_IP"
echo "    Worker floating IPs: $WORKER_IPS_JSON"
echo "    k3s API URL        : $K3S_API_URL"

if [[ "$SKIP_ANSIBLE" == "true" ]]; then
  warn "SKIP_ANSIBLE=true，跳過 ansible 步驟"
  echo ""
  echo "可手動執行："
  echo "  cd $ANSIBLE_DIR"
  echo "  ansible-playbook site.yml \\"
  echo "    -i inventory/hosts.ini \\"
  echo "    -i inventory/k3s_hosts.ini \\"
  echo "    --extra-vars '{\"k3s_worker_ips\": $WORKER_IPS_JSON}' \\"
  echo "    --ask-vault-pass"
  exit 0
fi

# ── Step 3: 等待 master k3s API 就緒 ─────────────────────
info "[2.5/3] 等待 k3s master API (${MASTER_IP}:6443) 就緒..."
TIMEOUT=300
ELAPSED=0
until nc -z "$MASTER_IP" 6443 2>/dev/null; do
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo ""
    warn "逾時 ${TIMEOUT}s，k3s API 尚未就緒"
    warn "可能還在安裝中，請稍後手動重試 ansible-playbook"
    exit 1
  fi
  echo -n "."
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done
echo ""
success "k3s API 已就緒（等待 ${ELAPSED}s）"

# ── Step 4: ansible-playbook ──────────────────────────────
info "[3/3] 執行 ansible-playbook..."
cd "$ANSIBLE_DIR"

ANSIBLE_ARGS=(
  site.yml
  -i inventory/hosts.ini
  -i inventory/k3s_hosts.ini
  --extra-vars "{\"k3s_worker_ips\": ${WORKER_IPS_JSON}}"
)

if [[ -n "$VAULT_PASS_FILE" ]]; then
  ANSIBLE_ARGS+=(--vault-password-file "$VAULT_PASS_FILE")
else
  ANSIBLE_ARGS+=(--ask-vault-pass)
fi

ansible-playbook "${ANSIBLE_ARGS[@]}"

success "部署完成！"
echo ""
echo "k3s API   : $K3S_API_URL"
echo "Master SSH: ssh ubuntu@${MASTER_IP}"
