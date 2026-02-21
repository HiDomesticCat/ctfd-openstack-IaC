"""
openstack-vm scenario for chall-manager
為每位玩家建立一台獨立的 OpenStack VM 靶機

chall-manager 會傳入 player_id 和 challenge_id 作為 Pulumi config，
此程式根據這些值建立隔離的網路資源和 VM。

清理（destroy）由 chall-manager Janitor 自動執行。
"""

import pulumi
import pulumi_openstack as openstack

# ── 讀取設定 ──────────────────────────────────────────────

cfg = pulumi.Config()
player_id = cfg.require("player_id")               # 由 chall-manager 傳入
challenge_id = cfg.require("challenge_id")         # 由 chall-manager 傳入
image_id = cfg.require("image_id")                 # 靶機 Image UUID
flavor_name = cfg.get("flavor_name") or "general.small"
network_id = cfg.require("network_id")             # 內部網路 ID
floating_ip_pool = cfg.get("floating_ip_pool") or "public"
challenge_port = cfg.get_int("challenge_port") or 8080

# 唯一識別此 challenge instance 的 prefix
prefix = f"ctf-{challenge_id}-{player_id}"

# ── Security Group（每個 instance 獨立）────────────────────

sg = openstack.networking.SecGroup(
    f"{prefix}-sg",
    name=f"{prefix}-sg",
    description=f"Security group for player {player_id}, challenge {challenge_id}",
)

# 允許 SSH（可選，依題目需求）
openstack.networking.SecGroupRule(
    f"{prefix}-sg-ssh",
    direction="ingress",
    ethertype="IPv4",
    protocol="tcp",
    port_range_min=22,
    port_range_max=22,
    remote_ip_prefix="0.0.0.0/0",
    security_group_id=sg.id,
)

# 允許題目 Port
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

# ── VM ────────────────────────────────────────────────────

instance = openstack.compute.Instance(
    f"{prefix}-vm",
    name=f"{prefix}",
    image_id=image_id,
    flavor_name=flavor_name,
    security_groups=[sg.name],
    networks=[{"uuid": network_id}],
    opts=pulumi.ResourceOptions(depends_on=[sg]),
)

# ── Floating IP ───────────────────────────────────────────

fip = openstack.networking.FloatingIp(
    f"{prefix}-fip",
    pool=floating_ip_pool,
)

port = openstack.networking.Port.get(
    f"{prefix}-port",
    id=instance.id.apply(
        lambda iid: openstack.networking.get_port(
            device_id=iid,
            network_id=network_id,
        ).id
    ),
)

openstack.networking.FloatingIpAssociate(
    f"{prefix}-fip-assoc",
    floating_ip=fip.address,
    port_id=port.id,
    opts=pulumi.ResourceOptions(depends_on=[instance, fip]),
)

# ── Outputs（chall-manager 會讀取這些值回傳給玩家）──────────────

pulumi.export("connection_info", fip.address.apply(
    lambda ip: f"http://{ip}:{challenge_port}"
))
pulumi.export("ssh_command", fip.address.apply(
    lambda ip: f"ssh ubuntu@{ip}"
))
pulumi.export("floating_ip", fip.address)
