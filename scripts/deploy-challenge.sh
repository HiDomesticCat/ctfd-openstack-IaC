#!/usr/bin/env bash
# deploy-challenge.sh — 一鍵部署 VM 題目
# 流程：Packer build → 擷取 image ID → 更新 challenge.yml → 註冊到 CTFd
#
# 用法：./scripts/deploy-challenge.sh <challenge-name>
#   例：./scripts/deploy-challenge.sh web-example
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKER_DIR="$PROJECT_ROOT/packer"

CHALLENGE="${1:-}"
if [[ -z "$CHALLENGE" ]]; then
    echo "Usage: $0 <challenge-name>"
    echo "  例：$0 web-example"
    exit 1
fi

CHALLENGE_DIR="$PROJECT_ROOT/challenges/$CHALLENGE"
CHALLENGE_YML="$CHALLENGE_DIR/challenge.yml"
PKRVARS="$CHALLENGE_DIR/packer/challenge.pkrvars.hcl"

# 檢查檔案存在
for f in "$CHALLENGE_YML" "$PKRVARS"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: $f 不存在"
        exit 1
    fi
done

# ── 階段 1：Packer build ────────────────────────────────────
echo "==> [1/3] Packer build: $CHALLENGE"
BUILD_LOG=$(mktemp)
trap "rm -f $BUILD_LOG" EXIT

cd "$PACKER_DIR"
if ! packer build -var-file="$PKRVARS" . 2>&1 | tee "$BUILD_LOG"; then
    echo ""
    echo "Error: Packer build 失敗"
    exit 1
fi

# ── 階段 2：擷取 image ID 並更新 challenge.yml ──────────────
echo ""
echo "==> [2/3] 更新 image_id..."

# Packer OpenStack plugin 輸出格式：
#   ==> openstack.challenge: An image was created: <UUID>
IMAGE_ID=$(grep -oP 'An image was created: \K[0-9a-f-]+' "$BUILD_LOG" | tail -1)

if [[ -z "$IMAGE_ID" ]]; then
    echo "Error: 無法從 Packer 輸出中擷取 image ID"
    echo "請手動更新 $CHALLENGE_YML 的 image_id"
    exit 1
fi

# 也擷取 image 名稱（用於註解）
IMAGE_NAME=$(grep -oP 'An image was created: [0-9a-f-]+ \(\K[^)]+' "$BUILD_LOG" | tail -1 || echo "")

echo "  Image ID: $IMAGE_ID"
[[ -n "$IMAGE_NAME" ]] && echo "  Image Name: $IMAGE_NAME"

# 用 Python 更新 YAML（保持格式盡量不變）
python3 - "$CHALLENGE_YML" "$IMAGE_ID" "$IMAGE_NAME" << 'PYEOF'
import sys, re

yml_path, image_id, image_name = sys.argv[1], sys.argv[2], sys.argv[3]

with open(yml_path, "r") as f:
    content = f.read()

# 替換 image_id 值（保留縮排和註解結構）
if image_name:
    comment = f"   # {image_name}"
else:
    comment = ""

# 匹配 image_id: "..." 或 image_id: "..."   # comment
new_content = re.sub(
    r'(image_id:\s*")[^"]*(".*)',
    rf'\g<1>{image_id}\g<2>',
    content,
)

# 更新或新增行尾註解
new_content = re.sub(
    r'(image_id:\s*"[^"]*")(\s*#.*)?$',
    rf'\1{comment}',
    new_content,
    flags=re.MULTILINE,
)

with open(yml_path, "w") as f:
    f.write(new_content)

print(f"  已更新 {yml_path}")
PYEOF

# ── 階段 3：註冊到 CTFd ─────────────────────────────────────
echo ""
echo "==> [3/3] 註冊到 CTFd: $CHALLENGE"
python3 "$PROJECT_ROOT/scripts/register-challenges.py" --force "$CHALLENGE_DIR/"

echo ""
echo "==> 部署完成！"
echo "  Challenge: $CHALLENGE"
echo "  Image ID:  $IMAGE_ID"
