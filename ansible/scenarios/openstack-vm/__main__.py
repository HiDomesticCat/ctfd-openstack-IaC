"""
openstack-vm scenario for chall-manager
為每位玩家建立一台獨立的 OpenStack VM 靶機

【chall-manager 規範】
  - Config key : <project-name>:identity  （本專案 = openstack-vm:identity）
  - Output key : connection_info          （必填，玩家看到的連線資訊）
  - Output key : flag                     （選填，動態 flag）

清理（destroy）由 chall-manager Janitor 自動執行。
"""

import hashlib
import os

import pulumi
import pulumi_openstack as openstack

# ── 讀取 chall-manager 注入的唯一識別 ─────────────────────────
# pulumi.Config() 預設使用專案名稱 "openstack-vm" 作為 namespace，
# chall-manager 傳入的 key 就是 "openstack-vm:identity"
cfg = pulumi.Config()
identity = cfg.require("identity")   # ✅ 正確 key，chall-manager 只傳這個

# ── 從環境變數讀取題目設定（由 chall-manager 容器繼承）──────────
image_id          = os.environ["CHALLENGE_IMAGE_ID"]
network_id        = os.environ["CHALLENGE_NETWORK_ID"]
flavor_name       = os.environ.get("CHALLENGE_FLAVOR", "general.small")
floating_ip_pool  = os.environ.get("CHALLENGE_FIP_POOL", "public")
challenge_port    = int(os.environ.get("CHALLENGE_PORT", "8080"))
base_flag         = os.environ.get("CHALLENGE_BASE_FLAG", "change_me_in_vars")
ctf_prefix        = os.environ.get("CHALLENGE_FLAG_PREFIX", "CTF")

# 資源唯一 prefix（只用 identity，避免 name 過長）
prefix = f"ctf-{identity[:24]}"


# ── 動態 flag（每個 identity 產生不同的 flag）────────────────
def variate_flag(ident: str, flag: str) -> str:
    """
    以 identity + base_flag 的 SHA-256 作為 PRNG seed，
    對 flag 中可替換的字元做視覺相近替換，
    使每位玩家拿到的 flag 字串唯一。
    """
    seed = int.from_bytes(
        hashlib.sha256(f"{ident}:{flag}".encode()).digest()[:8], "big"
    )
    alike: dict[str, list[str]] = {
        "a": ["a", "а", "ａ"],   # ASCII / 西里爾 / 全形
        "e": ["e", "е", "ｅ"],
        "o": ["o", "о", "ｏ"],
        "i": ["i", "і", "ｉ"],
        "c": ["c", "с", "ｃ"],
        "s": ["s", "ѕ", "ｓ"],
    }
    result = []
    for ch in flag:
        if ch in alike:
            seed = (seed * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
            result.append(alike[ch][seed % len(alike[ch])])
        else:
            result.append(ch)
    return "".join(result)


# ── Security Group（每個 instance 獨立）────────────────────────
sg = openstack.networking.SecGroup(
    f"{prefix}-sg",
    name=f"{prefix}-sg",
    description=f"CTF instance sg for identity={identity}",
)

openstack.networking.SecGroupRule(
    f"{prefix}-sg-chall",
    direction="ingress",
    ethertype="IPv4",
    protocol="tcp",
    port_range_min=challenge_port,
    port_range_max=challenge_port,
    remote_ip_prefix="0.0.0.0/0",
    security_group_id=sg.id,
)

openstack.networking.SecGroupRule(
    f"{prefix}-sg-icmp",
    direction="ingress",
    ethertype="IPv4",
    protocol="icmp",
    remote_ip_prefix="0.0.0.0/0",
    security_group_id=sg.id,
)

# ── VM ────────────────────────────────────────────────────────
instance = openstack.compute.Instance(
    f"{prefix}-vm",
    name=prefix,
    image_id=image_id,
    flavor_name=flavor_name,
    security_groups=[sg.name],
    networks=[{"uuid": network_id}],
    opts=pulumi.ResourceOptions(depends_on=[sg]),
)

# ── Floating IP ──────────────────────────────────────────────
fip = openstack.networking.FloatingIp(
    f"{prefix}-fip",
    pool=floating_ip_pool,
    opts=pulumi.ResourceOptions(depends_on=[instance]),
)

# ✅ 修復：不使用 Port data source（在 apply() 內呼叫 get_port 會競速失敗）
# 改用 compute.FloatingIpAssociate 直接以 instance_id 綁定
openstack.compute.FloatingIpAssociate(
    f"{prefix}-fip-assoc",
    floating_ip=fip.address,
    instance_id=instance.id,
    opts=pulumi.ResourceOptions(depends_on=[fip, instance]),
)

# ── Outputs ───────────────────────────────────────────────────
# ✅ 必須叫 "connection_info"，chall-manager 以此回傳給 CTFd 外掛
pulumi.export(
    "connection_info",
    fip.address.apply(lambda ip: f"http://{ip}:{challenge_port}"),
)

# ✅ 動態 flag：每個 identity 產生獨一無二的 flag
pulumi.export(
    "flag",
    pulumi.Output.from_input(identity).apply(
        lambda ident: f"{ctf_prefix}{{{variate_flag(ident, base_flag)}}}"
    ),
)

pulumi.export("ssh_command",  fip.address.apply(lambda ip: f"ssh ubuntu@{ip}"))
pulumi.export("floating_ip",  fip.address)
