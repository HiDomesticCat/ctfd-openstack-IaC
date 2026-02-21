// openstack-vm scenario for chall-manager
// 為每位玩家建立一台獨立的 OpenStack VM 靶機
//
// chall-manager 規範：
//   - Config key : openstack-vm:identity  （chall-manager 自動注入）
//   - Output key : connection_info        （玩家連線 URL，必填）
//   - Output key : flag                   （動態 flag，選填）
//
// 設定來源：環境變數（由 chall-manager docker-compose 繼承）
package main

import (
	"crypto/hmac"
	"crypto/md5"
	"crypto/sha256"
	"fmt"
	"os"
	"strconv"

	"github.com/pulumi/pulumi-openstack/sdk/v4/go/openstack/compute"
	"github.com/pulumi/pulumi-openstack/sdk/v4/go/openstack/networking"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(run)
}

func run(ctx *pulumi.Context) error {
	// ── chall-manager 唯一注入的 config key ──────────────────
	cfg := config.New(ctx, "")
	identity := cfg.Require("identity")

	// ── 環境變數（由 docker-compose 傳入）────────────────────
	imageID := requireEnv("CHALLENGE_IMAGE_ID")
	networkID := requireEnv("CHALLENGE_NETWORK_ID")
	flavorName := envOrDefault("CHALLENGE_FLAVOR", "general.small")
	fipPool := envOrDefault("CHALLENGE_FIP_POOL", "public")
	challengePortStr := envOrDefault("CHALLENGE_PORT", "8080")
	baseFlag := envOrDefault("CHALLENGE_BASE_FLAG", "change_me")
	flagPrefix := envOrDefault("CHALLENGE_FLAG_PREFIX", "CTF")

	challengePort, err := strconv.Atoi(challengePortStr)
	if err != nil {
		return fmt.Errorf("invalid CHALLENGE_PORT %q: %w", challengePortStr, err)
	}

	// ── 資源唯一 prefix（MD5 hash 避免截斷衝突）──────────────
	h := md5.Sum([]byte(identity))
	shortID := fmt.Sprintf("%x", h)[:8]
	prefix := "ctf-" + shortID

	// ── Security Group ────────────────────────────────────────
	sg, err := networking.NewSecGroup(ctx, prefix+"-sg", &networking.SecGroupArgs{
		Name:        pulumi.String(prefix + "-sg"),
		Description: pulumi.Sprintf("CTF sg for identity=%s", identity),
	})
	if err != nil {
		return err
	}

	// 允許題目 Port
	if _, err = networking.NewSecGroupRule(ctx, prefix+"-sg-chall", &networking.SecGroupRuleArgs{
		Direction:       pulumi.String("ingress"),
		Ethertype:       pulumi.String("IPv4"),
		Protocol:        pulumi.String("tcp"),
		PortRangeMin:    pulumi.Int(challengePort),
		PortRangeMax:    pulumi.Int(challengePort),
		RemoteIpPrefix:  pulumi.String("0.0.0.0/0"),
		SecurityGroupId: sg.ID(),
	}); err != nil {
		return err
	}

	// 允許 ICMP
	if _, err = networking.NewSecGroupRule(ctx, prefix+"-sg-icmp", &networking.SecGroupRuleArgs{
		Direction:       pulumi.String("ingress"),
		Ethertype:       pulumi.String("IPv4"),
		Protocol:        pulumi.String("icmp"),
		RemoteIpPrefix:  pulumi.String("0.0.0.0/0"),
		SecurityGroupId: sg.ID(),
	}); err != nil {
		return err
	}

	// ── VM ───────────────────────────────────────────────────
	instance, err := compute.NewInstance(ctx, prefix+"-vm", &compute.InstanceArgs{
		Name:           pulumi.String(prefix),
		ImageId:        pulumi.String(imageID),
		FlavorName:     pulumi.String(flavorName),
		SecurityGroups: pulumi.StringArray{sg.Name},
		Networks: compute.InstanceNetworkArray{
			&compute.InstanceNetworkArgs{
				Uuid: pulumi.String(networkID),
			},
		},
	}, pulumi.DependsOn([]pulumi.Resource{sg}))
	if err != nil {
		return err
	}

	// ── Floating IP ──────────────────────────────────────────
	fip, err := networking.NewFloatingIp(ctx, prefix+"-fip", &networking.FloatingIpArgs{
		Pool: pulumi.String(fipPool),
	}, pulumi.DependsOn([]pulumi.Resource{instance}))
	if err != nil {
		return err
	}

	// ✅ 直接用 instance_id 綁定，避免 Port data source 競速問題
	if _, err = compute.NewFloatingIpAssociate(ctx, prefix+"-fip-assoc", &compute.FloatingIpAssociateArgs{
		FloatingIp: fip.Address,
		InstanceId: instance.ID(),
	}, pulumi.DependsOn([]pulumi.Resource{fip, instance})); err != nil {
		return err
	}

	// ── Outputs ───────────────────────────────────────────────
	// ✅ connection_info：chall-manager 必填 output
	ctx.Export("connection_info", fip.Address.ApplyT(func(ip string) string {
		return fmt.Sprintf("http://%s:%d", ip, challengePort)
	}).(pulumi.StringOutput))

	// ✅ flag：HMAC-SHA256，每個 identity 產生唯一純 ASCII flag
	ctx.Export("flag", pulumi.String(
		fmt.Sprintf("%s{%s}", flagPrefix, variateFlag(identity, baseFlag)),
	))

	ctx.Export("ssh_command", fip.Address.ApplyT(func(ip string) string {
		return "ssh ubuntu@" + ip
	}).(pulumi.StringOutput))

	ctx.Export("floating_ip", fip.Address)

	return nil
}

// variateFlag 用 HMAC-SHA256(key=baseFlag, msg=identity) 產生唯一後綴
// 輸出純 ASCII，避免 CTFd flag 比對因 Unicode 失敗
// 例：baseFlag="pwn_me", identity="user-001" → "pwn_me_3f2a1b4c5d6e"
func variateFlag(identity, baseFlag string) string {
	mac := hmac.New(sha256.New, []byte(baseFlag))
	mac.Write([]byte(identity))
	sig := fmt.Sprintf("%x", mac.Sum(nil))[:12]
	return baseFlag + "_" + sig
}

func requireEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		panic(fmt.Sprintf("required environment variable %q is not set", key))
	}
	return v
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
