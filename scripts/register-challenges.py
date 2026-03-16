#!/usr/bin/env python3
"""
Challenge as Code — CTFd 題目自動註冊
讀取 challenges/*/challenge.yml，透過 CTFd REST API 建立/更新題目。

用法：
  # 註冊所有題目
  python3 scripts/register-challenges.py

  # 只註冊指定題目
  python3 scripts/register-challenges.py challenges/web-example/

  # 預覽模式（不實際呼叫 API）
  python3 scripts/register-challenges.py --dry-run

  # 強制更新（即使已存在也 PATCH）
  python3 scripts/register-challenges.py --force

環境變數：
  CTFD_URL    CTFd 位址（如 http://10.0.2.150:8000）
  CTFD_TOKEN  CTFd API Token（Settings > Access Tokens）
"""

import argparse
import glob
import json
import os
import sys
from pathlib import Path

try:
    import yaml
    import requests
except ImportError:
    print("Error: 需要 pyyaml 和 requests")
    print("  pip install pyyaml requests")
    sys.exit(1)

# ── 設定 ─────────────────────────────────────────────────────

PROJECT_ROOT = Path(__file__).resolve().parent.parent
CHALLENGES_DIR = PROJECT_ROOT / "challenges"
DEFAULTS_FILE = PROJECT_ROOT / "challenge_defaults.yml"


def load_env():
    """從環境變數或 .env 檔案載入設定"""
    env_file = PROJECT_ROOT / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())

    url = os.environ.get("CTFD_URL", "").rstrip("/")
    token = os.environ.get("CTFD_TOKEN", "")
    return url, token


def load_defaults():
    """載入 challenge_defaults.yml"""
    if not DEFAULTS_FILE.exists():
        return {}
    with open(DEFAULTS_FILE) as f:
        return yaml.safe_load(f) or {}


def load_challenge(path):
    """載入單一 challenge.yml"""
    challenge_file = Path(path)
    if challenge_file.is_dir():
        challenge_file = challenge_file / "challenge.yml"
    if not challenge_file.exists():
        print(f"  [!] {challenge_file} 不存在，跳過")
        return None
    with open(challenge_file) as f:
        return yaml.safe_load(f)


def expand_scenario(scenario, defaults):
    """展開 scenario 短名稱為完整 OCI reference"""
    # 如果已經包含 / 或 : 就視為完整 reference
    if "/" in scenario or ":" in scenario:
        return scenario
    registry = defaults.get("scenario_registry", "registry:5000")
    tag = defaults.get("scenario_tag", "latest")
    return f"{registry}/{scenario}:{tag}"


def merge_additional(scenario_type, challenge_additional, defaults):
    """合併 defaults + challenge additional，challenge 的值優先"""
    merged = {}
    # 從 defaults 取出 scenario type 對應的預設值
    scenario_defaults = defaults.get(scenario_type, {})
    if isinstance(scenario_defaults, dict):
        for k, v in scenario_defaults.items():
            merged[k] = str(v)
    # challenge 的 additional 覆蓋 defaults
    if challenge_additional and isinstance(challenge_additional, dict):
        for k, v in challenge_additional.items():
            merged[k] = str(v)
    return merged


def build_payload(challenge, defaults):
    """將 challenge.yml 轉換為 CTFd API payload"""
    scenario_short = challenge.get("scenario", "")
    scenario_full = expand_scenario(scenario_short, defaults)

    # 判斷 scenario type（用於合併 defaults）
    scenario_type = scenario_short
    if "/" not in scenario_short and ":" not in scenario_short:
        scenario_type = scenario_short  # e.g. "openstack-vm", "k8s-pod"
    else:
        # 從完整 reference 取出 scenario 名稱
        name_part = scenario_short.rsplit("/", 1)[-1]
        scenario_type = name_part.split(":")[0]

    additional = merge_additional(
        scenario_type,
        challenge.get("additional", {}),
        defaults,
    )

    payload = {
        "name": challenge["name"],
        "category": challenge.get("category", "misc"),
        "description": challenge.get("description", ""),
        "state": challenge.get("state", "hidden"),
        "type": "dynamic_iac",
        # 動態計分
        "initial": challenge.get("value", challenge.get("initial", 500)),
        "decay": challenge.get("decay", 50),
        "minimum": challenge.get("minimum", 50),
        "function": challenge.get("function", "logarithmic"),
        # chall-manager
        "scenario": scenario_full,
        "shared": challenge.get("shared", False),
        "destroy_on_flag": challenge.get("destroy_on_flag", False),
        "mana_cost": challenge.get("mana_cost", 0),
        "additional": additional,
    }

    # 選填欄位
    if "timeout" in challenge:
        timeout_str = str(challenge["timeout"])
        # 如果是 Go duration（如 "3600s"），轉為秒數
        if timeout_str.endswith("s"):
            payload["timeout"] = int(timeout_str[:-1])
        elif timeout_str.endswith("m"):
            payload["timeout"] = int(timeout_str[:-1]) * 60
        elif timeout_str.endswith("h"):
            payload["timeout"] = int(timeout_str[:-1]) * 3600
        else:
            payload["timeout"] = int(timeout_str)

    return payload


# ── CTFd API ─────────────────────────────────────────────────

class CTFdClient:
    def __init__(self, url, token):
        self.url = url
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Token {token}",
            "Content-Type": "application/json",
        })

    def list_challenges(self):
        """取得所有已存在的題目（name → id 對應）"""
        challenges = {}
        page = 1
        while True:
            resp = self.session.get(
                f"{self.url}/api/v1/challenges",
                params={"page": page},
            )
            resp.raise_for_status()
            data = resp.json()
            for c in data.get("data", []):
                challenges[c["name"]] = c["id"]
            # 檢查是否有下一頁
            meta = data.get("meta", {}).get("pagination", {})
            if page >= meta.get("pages", 1):
                break
            page += 1
        return challenges

    def create_challenge(self, payload):
        """建立新題目"""
        resp = self.session.post(
            f"{self.url}/api/v1/challenges",
            json=payload,
        )
        resp.raise_for_status()
        return resp.json()

    def update_challenge(self, challenge_id, payload):
        """更新已存在的題目"""
        resp = self.session.patch(
            f"{self.url}/api/v1/challenges/{challenge_id}",
            json=payload,
        )
        resp.raise_for_status()
        return resp.json()


# ── 主程式 ───────────────────────────────────────────────────

def discover_challenges(paths):
    """找到所有要註冊的 challenge.yml"""
    if paths:
        return [Path(p) for p in paths]
    # 掃描 challenges/*/ 目錄
    found = sorted(CHALLENGES_DIR.glob("*/challenge.yml"))
    return [f.parent for f in found if not f.parent.name.startswith("_")]


def main():
    parser = argparse.ArgumentParser(
        description="CTFd 題目自動註冊（Challenge as Code）"
    )
    parser.add_argument(
        "challenges",
        nargs="*",
        help="指定題目目錄（預設：掃描 challenges/*/）",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="預覽模式，不實際呼叫 API",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="強制更新已存在的題目",
    )
    args = parser.parse_args()

    # 載入設定
    load_env()
    ctfd_url, ctfd_token = load_env()
    defaults = load_defaults()

    if not args.dry_run:
        if not ctfd_url:
            print("Error: CTFD_URL 未設定")
            print("  export CTFD_URL=http://<ctfd-ip>:8000")
            sys.exit(1)
        if not ctfd_token:
            print("Error: CTFD_TOKEN 未設定")
            print("  export CTFD_TOKEN=ctfd_xxx...")
            sys.exit(1)

    # 找到要註冊的題目
    challenge_paths = discover_challenges(args.challenges)
    if not challenge_paths:
        print("沒有找到任何 challenge.yml")
        sys.exit(0)

    print(f"找到 {len(challenge_paths)} 道題目")
    print()

    # 載入已存在的題目（用於冪等判斷）
    existing = {}
    if not args.dry_run:
        client = CTFdClient(ctfd_url, ctfd_token)
        try:
            existing = client.list_challenges()
        except requests.RequestException as e:
            print(f"Error: 無法連線 CTFd ({ctfd_url}): {e}")
            sys.exit(1)

    # 逐題處理
    created = 0
    updated = 0
    skipped = 0
    errors = 0

    for path in challenge_paths:
        challenge = load_challenge(path)
        if challenge is None:
            errors += 1
            continue

        name = challenge.get("name", "???")
        try:
            payload = build_payload(challenge, defaults)
        except (KeyError, ValueError) as e:
            print(f"  [x] {name}: YAML 格式錯誤 — {e}")
            errors += 1
            continue

        if args.dry_run:
            print(f"  [~] {name}")
            print(f"      scenario: {payload['scenario']}")
            print(f"      additional: {json.dumps(payload['additional'], ensure_ascii=False)}")
            print(f"      scoring: {payload['initial']}/{payload['decay']}/{payload['minimum']} ({payload['function']})")
            skipped += 1
            continue

        try:
            if name in existing:
                if args.force:
                    try:
                        client.update_challenge(existing[name], payload)
                        print(f"  [~] {name}: 已更新 (id={existing[name]})")
                        updated += 1
                    except requests.RequestException:
                        # PATCH 失敗（常見於 chall-manager 重啟後狀態不一致）
                        # fallback: 刪除舊的 → 重新建立
                        client.session.delete(
                            f"{client.url}/api/v1/challenges/{existing[name]}"
                        )
                        result = client.create_challenge(payload)
                        cid = result.get("data", {}).get("id", "?")
                        print(f"  [~] {name}: 已重建 (id={cid})（舊 id={existing[name]} 已刪除）")
                        updated += 1
                else:
                    print(f"  [-] {name}: 已存在，跳過（使用 --force 強制更新）")
                    skipped += 1
            else:
                result = client.create_challenge(payload)
                cid = result.get("data", {}).get("id", "?")
                print(f"  [+] {name}: 已建立 (id={cid})")
                created += 1
        except requests.RequestException as e:
            print(f"  [x] {name}: API 錯誤 — {e}")
            try:
                print(f"      Response: {e.response.text[:200]}")
            except Exception:
                pass
            errors += 1

    # 統計
    print()
    if args.dry_run:
        print(f"預覽完成：{skipped} 道題目")
    else:
        parts = []
        if created:
            parts.append(f"{created} 建立")
        if updated:
            parts.append(f"{updated} 更新")
        if skipped:
            parts.append(f"{skipped} 跳過")
        if errors:
            parts.append(f"{errors} 錯誤")
        print("完成：" + "、".join(parts))

    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
