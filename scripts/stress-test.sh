#!/usr/bin/env bash
# stress-test.sh — 壓力測試：並發啟動/關閉 challenge instance 並計時
# 透過 chall-manager REST API 直接建立 instance（不經 CTFd 用戶系統）
#
# API endpoints:
#   POST   /api/v1/instance                              — 建立 instance
#   GET    /api/v1/instance/{challenge_id}/{source_id}    — 查詢 instance
#   DELETE /api/v1/instance/{challenge_id}/{source_id}    — 刪除 instance
#
# 用法：./scripts/stress-test.sh [並發數] [challenge_id]
#   例：./scripts/stress-test.sh 5 8
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 參數
CONCURRENCY="${1:-3}"
CHALLENGE_ID="${2:-8}"

# chall-manager 在 CTFd 主機上以 Docker 運行，只綁定 127.0.0.1:8080
# 需透過 SSH 存取
CM_HOST="${CM_HOST:-10.0.2.181}"
CM_SSH_USER="${CM_SSH_USER:-ubuntu}"

RESULTS_DIR="$PROJECT_ROOT/stress-test-results"
mkdir -p "$RESULTS_DIR"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULT_FILE="$RESULTS_DIR/run_${TIMESTAMP}_c${CONCURRENCY}.csv"
DESTROY_FILE="$RESULTS_DIR/run_${TIMESTAMP}_c${CONCURRENCY}_destroy.csv"
LOG_DIR="$RESULTS_DIR/logs_${TIMESTAMP}"
mkdir -p "$LOG_DIR"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  CTFd Challenge 壓力測試（啟動 + 關閉）             ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  並發數:       $CONCURRENCY"
echo "║  Challenge ID: $CHALLENGE_ID"
echo "║  CM Host:      $CM_HOST"
echo "║  結果檔案:     $RESULT_FILE"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Helper：透過 SSH 呼叫 chall-manager REST API ─────────────
cm_create() {
    local data="$1"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "$CM_SSH_USER@$CM_HOST" \
        "curl -s -X POST -H 'Content-Type: application/json' -d '$data' http://localhost:8080/api/v1/instance" 2>/dev/null
}

cm_get() {
    local cid="$1" sid="$2"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "$CM_SSH_USER@$CM_HOST" \
        "curl -s http://localhost:8080/api/v1/instance/${cid}/${sid}" 2>/dev/null
}

cm_delete() {
    local cid="$1" sid="$2"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "$CM_SSH_USER@$CM_HOST" \
        "curl -s -X DELETE http://localhost:8080/api/v1/instance/${cid}/${sid}" 2>/dev/null
}

# ── Helper：檢查 instance 是否已被完全刪除 ────────────────────
instance_gone() {
    local cid="$1" sid="$2"
    local resp
    resp=$(cm_get "$cid" "$sid" 2>/dev/null || echo "")
    local conn
    conn=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('connectionInfo','') or d.get('result',{}).get('connectionInfo',''))" 2>/dev/null || echo "")
    [[ -z "$conn" ]]
}

# ── 階段 1：清理舊 instance ──────────────────────────────────
echo "==> [1/5] 清理舊的測試 instance..."
for i in $(seq 1 "$CONCURRENCY"); do
    cm_delete "$CHALLENGE_ID" "stress_${i}" > /dev/null 2>&1 || true
done

echo "  等待 instance 完全清理..."
for attempt in $(seq 1 120); do
    all_gone=true
    for i in $(seq 1 "$CONCURRENCY"); do
        if ! instance_gone "$CHALLENGE_ID" "stress_${i}"; then
            all_gone=false
            break
        fi
    done
    if $all_gone; then
        break
    fi
    printf "\r  等待中... (%ds)" "$((attempt * 5))"
    sleep 5
done
echo ""
echo "  已清理"

# ── 階段 2：並發啟動 ──────────────────────────────────────────
echo ""
echo "==> [2/5] 並發啟動 $CONCURRENCY 個 instance..."
echo ""

# CSV header
echo "source_id,boot_api_ms,service_ready_ms,total_ms,connection_info,status" > "$RESULT_FILE"

# Worker function
launch_worker() {
    local idx=$1
    local source_id="stress_${idx}"
    local log_file="$LOG_DIR/worker_${idx}.log"

    local start_ns=$(date +%s%N)
    echo "[$(date '+%H:%M:%S.%3N')] [$source_id] boot 請求..." >> "$log_file"

    # Create instance via chall-manager API
    local boot_resp
    boot_resp=$(cm_create "{\"challengeId\":\"$CHALLENGE_ID\",\"sourceId\":\"$source_id\"}")

    local boot_end_ns=$(date +%s%N)
    local boot_ms=$(( (boot_end_ns - start_ns) / 1000000 ))

    echo "[$(date '+%H:%M:%S.%3N')] Boot API 回應 (${boot_ms}ms): $boot_resp" >> "$log_file"

    # Extract connection info
    local conn_info
    conn_info=$(echo "$boot_resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('connectionInfo',''))" 2>/dev/null)

    if [[ -z "$conn_info" ]]; then
        echo "$source_id,$boot_ms,0,0,,BOOT_FAILED" >> "$RESULT_FILE"
        echo "  [$source_id] BOOT FAILED (${boot_ms}ms) — $boot_resp"
        return
    fi

    # Extract host:port
    local host_port
    host_port=$(echo "$conn_info" | sed 's|http://||')

    # Poll until service responds
    local attempt=0
    while true; do
        attempt=$((attempt + 1))
        local now_ns=$(date +%s%N)
        local elapsed_ms=$(( (now_ns - start_ns) / 1000000 ))

        if curl -s --connect-timeout 2 --max-time 3 "http://$host_port/" > /dev/null 2>&1; then
            local end_ns=$(date +%s%N)
            local total_ms=$(( (end_ns - start_ns) / 1000000 ))
            local service_ms=$((total_ms - boot_ms))

            echo "$source_id,$boot_ms,$service_ms,$total_ms,$conn_info,OK" >> "$RESULT_FILE"

            local total_s=$(python3 -c "print(f'{$total_ms/1000:.1f}')")
            echo "  [$source_id] OK — boot=${boot_ms}ms service=${service_ms}ms total=${total_s}s (#${attempt})"
            return
        fi

        if [[ $elapsed_ms -gt 300000 ]]; then
            echo "$source_id,$boot_ms,0,$elapsed_ms,$conn_info,TIMEOUT" >> "$RESULT_FILE"
            echo "  [$source_id] TIMEOUT (>300s)"
            return
        fi

        sleep 3
    done
}

# Launch all workers in parallel
GLOBAL_START=$(date +%s%N)
echo "[$(date '+%H:%M:%S')] 開始並發啟動..."
echo ""

pids=()
for i in $(seq 1 "$CONCURRENCY"); do
    launch_worker "$i" &
    pids+=($!)
done

# Wait for all
for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
done

GLOBAL_END=$(date +%s%N)
GLOBAL_BOOT_MS=$(( (GLOBAL_END - GLOBAL_START) / 1000000 ))
GLOBAL_BOOT_S=$(python3 -c "print(f'{$GLOBAL_BOOT_MS/1000:.1f}')")

echo ""
echo "  啟動牆鐘時間: ${GLOBAL_BOOT_S}s"

# ── 階段 3：並發關閉 + 銷毀耗時測量 ──────────────────────────
echo ""
echo "==> [3/5] 並發關閉 $CONCURRENCY 個 instance（計時）..."
echo ""

echo "source_id,delete_api_ms,destroy_complete_ms,total_destroy_ms,status" > "$DESTROY_FILE"

destroy_worker() {
    local idx=$1
    local source_id="stress_${idx}"
    local log_file="$LOG_DIR/destroy_${idx}.log"

    local start_ns=$(date +%s%N)
    echo "[$(date '+%H:%M:%S.%3N')] [$source_id] delete 請求..." >> "$log_file"

    # Send DELETE request
    local del_resp
    del_resp=$(cm_delete "$CHALLENGE_ID" "$source_id" 2>/dev/null || echo "DELETE_ERROR")

    local del_end_ns=$(date +%s%N)
    local del_api_ms=$(( (del_end_ns - start_ns) / 1000000 ))

    echo "[$(date '+%H:%M:%S.%3N')] Delete API 回應 (${del_api_ms}ms): $del_resp" >> "$log_file"

    # Poll until instance is fully gone (resources destroyed)
    local attempt=0
    while true; do
        attempt=$((attempt + 1))
        local now_ns=$(date +%s%N)
        local elapsed_ms=$(( (now_ns - start_ns) / 1000000 ))

        if instance_gone "$CHALLENGE_ID" "$source_id"; then
            local end_ns=$(date +%s%N)
            local total_ms=$(( (end_ns - start_ns) / 1000000 ))
            local destroy_ms=$((total_ms - del_api_ms))

            echo "$source_id,$del_api_ms,$destroy_ms,$total_ms,OK" >> "$DESTROY_FILE"

            local total_s=$(python3 -c "print(f'{$total_ms/1000:.1f}')")
            echo "  [$source_id] DESTROYED — api=${del_api_ms}ms cleanup=${destroy_ms}ms total=${total_s}s"
            return
        fi

        if [[ $elapsed_ms -gt 600000 ]]; then
            echo "$source_id,$del_api_ms,0,$elapsed_ms,TIMEOUT" >> "$DESTROY_FILE"
            echo "  [$source_id] DESTROY TIMEOUT (>600s)"
            return
        fi

        sleep 3
    done
}

DESTROY_START=$(date +%s%N)
echo "[$(date '+%H:%M:%S')] 開始並發關閉..."
echo ""

pids=()
for i in $(seq 1 "$CONCURRENCY"); do
    destroy_worker "$i" &
    pids+=($!)
done

for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
done

DESTROY_END=$(date +%s%N)
GLOBAL_DESTROY_MS=$(( (DESTROY_END - DESTROY_START) / 1000000 ))
GLOBAL_DESTROY_S=$(python3 -c "print(f'{$GLOBAL_DESTROY_MS/1000:.1f}')")

echo ""
echo "  關閉牆鐘時間: ${GLOBAL_DESTROY_S}s"

# ── 階段 4：統計結果 ──────────────────────────────────────────
echo ""
echo "==> [4/5] 測試結果統計"
echo ""

python3 - "$RESULT_FILE" "$DESTROY_FILE" "$GLOBAL_BOOT_S" "$GLOBAL_DESTROY_S" << 'PYEOF'
import csv, sys, statistics

boot_file = sys.argv[1]
destroy_file = sys.argv[2]
boot_wall = sys.argv[3]
destroy_wall = sys.argv[4]

# ── 讀取啟動資料 ──
boot_rows = []
with open(boot_file) as f:
    for row in csv.DictReader(f):
        boot_rows.append(row)

boot_ok = [r for r in boot_rows if r["status"] == "OK"]
boot_fail = [r for r in boot_rows if r["status"] != "OK"]

# ── 讀取關閉資料 ──
destroy_rows = []
with open(destroy_file) as f:
    for row in csv.DictReader(f):
        destroy_rows.append(row)

destroy_ok = [r for r in destroy_rows if r["status"] == "OK"]
destroy_fail = [r for r in destroy_rows if r["status"] != "OK"]

def fmt(vals, label):
    avg = statistics.mean(vals)
    mn = min(vals)
    mx = max(vals)
    med = statistics.median(vals)
    sd = statistics.stdev(vals) if len(vals) > 1 else 0
    print(f"  {label}")
    print(f"    平均: {avg/1000:.1f}s  中位: {med/1000:.1f}s  最小: {mn/1000:.1f}s  最大: {mx/1000:.1f}s  標準差: {sd/1000:.1f}s")

# ── 啟動統計 ──
print("  ╔═══════════════════════════════════════════════════════╗")
print("  ║  啟動 (Boot) 統計                                    ║")
print("  ╠═══════════════════════════════════════════════════════╣")
print(f"  ║  成功: {len(boot_ok)}/{len(boot_rows)}    牆鐘時間: {boot_wall}s")
print("  ╚═══════════════════════════════════════════════════════╝")

if boot_ok:
    boot_times = [int(r["boot_api_ms"]) for r in boot_ok]
    svc_times = [int(r["service_ready_ms"]) for r in boot_ok]
    total_times = [int(r["total_ms"]) for r in boot_ok]

    print("  ┌─────────────────────────────────────────────────────┐")
    fmt(boot_times,  "  Boot API 回應時間（基礎設施建立）")
    print("  ├─────────────────────────────────────────────────────┤")
    fmt(svc_times,   "  服務就緒時間（VM 開機 + systemd）")
    print("  ├─────────────────────────────────────────────────────┤")
    fmt(total_times, "  端到端總耗時")
    print("  └─────────────────────────────────────────────────────┘")
    print()

    print("  各 instance 啟動詳細:")
    print(f"  {'Source':<15} {'Boot':>8} {'Service':>8} {'Total':>8}  Connection")
    print(f"  {'─'*15} {'─'*8} {'─'*8} {'─'*8}  {'─'*25}")
    for r in sorted(boot_ok, key=lambda x: int(x["total_ms"])):
        b = int(r["boot_api_ms"])/1000
        s = int(r["service_ready_ms"])/1000
        t = int(r["total_ms"])/1000
        print(f"  {r['source_id']:<15} {b:>7.1f}s {s:>7.1f}s {t:>7.1f}s  {r['connection_info']}")

if boot_fail:
    print()
    print("  啟動失敗:")
    for r in boot_fail:
        print(f"    {r['source_id']}: {r['status']} (boot={r['boot_api_ms']}ms)")

# ── 關閉統計 ──
print()
print("  ╔═══════════════════════════════════════════════════════╗")
print("  ║  關閉 (Destroy) 統計                                 ║")
print("  ╠═══════════════════════════════════════════════════════╣")
print(f"  ║  成功: {len(destroy_ok)}/{len(destroy_rows)}    牆鐘時間: {destroy_wall}s")
print("  ╚═══════════════════════════════════════════════════════╝")

if destroy_ok:
    del_api_times = [int(r["delete_api_ms"]) for r in destroy_ok]
    cleanup_times = [int(r["destroy_complete_ms"]) for r in destroy_ok]
    total_d_times = [int(r["total_destroy_ms"]) for r in destroy_ok]

    print("  ┌─────────────────────────────────────────────────────┐")
    fmt(del_api_times,  "  Delete API 回應時間")
    print("  ├─────────────────────────────────────────────────────┤")
    fmt(cleanup_times,  "  資源清理時間（Pulumi destroy）")
    print("  ├─────────────────────────────────────────────────────┤")
    fmt(total_d_times,  "  端到端銷毀耗時")
    print("  └─────────────────────────────────────────────────────┘")
    print()

    print("  各 instance 關閉詳細:")
    print(f"  {'Source':<15} {'API':>8} {'Cleanup':>8} {'Total':>8}")
    print(f"  {'─'*15} {'─'*8} {'─'*8} {'─'*8}")
    for r in sorted(destroy_ok, key=lambda x: int(x["total_destroy_ms"])):
        a = int(r["delete_api_ms"])/1000
        c = int(r["destroy_complete_ms"])/1000
        t = int(r["total_destroy_ms"])/1000
        print(f"  {r['source_id']:<15} {a:>7.1f}s {c:>7.1f}s {t:>7.1f}s")

if destroy_fail:
    print()
    print("  關閉失敗:")
    for r in destroy_fail:
        print(f"    {r['source_id']}: {r['status']}")

# ── 總覽 ──
print()
print("  ╔═══════════════════════════════════════════════════════╗")
print("  ║  總覽                                                ║")
print("  ╠═══════════════════════════════════════════════════════╣")
if boot_ok:
    avg_boot = statistics.mean([int(r["total_ms"]) for r in boot_ok])/1000
    print(f"  ║  平均啟動: {avg_boot:.1f}s    啟動牆鐘: {boot_wall}s")
if destroy_ok:
    avg_destroy = statistics.mean([int(r["total_destroy_ms"]) for r in destroy_ok])/1000
    print(f"  ║  平均關閉: {avg_destroy:.1f}s    關閉牆鐘: {destroy_wall}s")
if boot_ok and destroy_ok:
    print(f"  ║  完整週期牆鐘: {float(boot_wall)+float(destroy_wall):.1f}s")
print(f"  ║  成功率: 啟動 {len(boot_ok)}/{len(boot_rows)}, 關閉 {len(destroy_ok)}/{len(destroy_rows)}")
print("  ╚═══════════════════════════════════════════════════════╝")
PYEOF

# ── 階段 5：驗證清理 ──────────────────────────────────────────
echo ""
echo "==> [5/5] 驗證所有資源已清理..."

remaining=0
for i in $(seq 1 "$CONCURRENCY"); do
    if ! instance_gone "$CHALLENGE_ID" "stress_${i}"; then
        echo "  WARNING: stress_${i} 仍然存在！"
        remaining=$((remaining + 1))
    fi
done

if [[ $remaining -eq 0 ]]; then
    echo "  所有 instance 已清理完成"
else
    echo "  WARNING: $remaining 個 instance 未被清理，可能有 orphan 資源"
    echo "  請手動檢查: openstack --os-cloud ctfd server list | grep stress"
fi

echo ""
echo "=== 測試完成 ==="
echo "  啟動結果: $RESULT_FILE"
echo "  關閉結果: $DESTROY_FILE"
echo "  Logs:     $LOG_DIR/"
