// openstack-vm scenario for chall-manager
// 為每位玩家建立一台獨立的 OpenStack VM 靶機
//
// chall-manager 規範：
//   - Config key : openstack-vm:identity  （chall-manager 自動注入）
//   - Output key : connection_info        （玩家連線 URL，必填）
//   - Output key : flag                   （動態 flag，選填）
//
// NOTE: 使用 pulumi-openstack SDK v3 (terraform-provider-openstack v1.x)
//       SDK v4.1.0 對應的 terraform-provider-openstack v2.1.0 有 nil panic bug：
//       panic: interface conversion: interface {} is nil @ configureProvider/getOkExists
//
// NOTE: FIP association 必須使用明確建立的 port（不依賴 instance.Networks 輸出）
//       原因：pulumi-openstack v3 的 instance.Networks.Port() 回傳空值，
//       導致 FloatingIpAssociate 以空 portId 呼叫 OpenStack API，
//       API 接受但不實際關聯，造成 FIP 建立後仍顯示 None。
package main

import (
	"crypto/hmac"
	"crypto/md5"
	"crypto/sha256"
	"fmt"
	"os"
	"strconv"

	"github.com/pulumi/pulumi-openstack/sdk/v3/go/openstack"
	"github.com/pulumi/pulumi-openstack/sdk/v3/go/openstack/compute"
	"github.com/pulumi/pulumi-openstack/sdk/v3/go/openstack/networking"
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

	// ── 明確配置 OpenStack provider（繞過 env auto-detect bug）──
	osProvider, err := openstack.NewProvider(ctx, "openstack", &openstack.ProviderArgs{
		AuthUrl:           pulumi.StringPtr(requireEnv("OS_AUTH_URL")),
		UserName:          pulumi.StringPtr(requireEnv("OS_USERNAME")),
		Password:          pulumi.StringPtr(requireEnv("OS_PASSWORD")),
		TenantName:        pulumi.StringPtr(requireEnv("OS_PROJECT_NAME")),
		UserDomainName:    pulumi.StringPtr(envOrDefault("OS_USER_DOMAIN_NAME", "Default")),
		ProjectDomainName: pulumi.StringPtr(envOrDefault("OS_PROJECT_DOMAIN_NAME", "Default")),
		Region:            pulumi.StringPtr(envOrDefault("OS_REGION_NAME", "RegionOne")),
	})
	if err != nil {
		return fmt.Errorf("failed to create openstack provider: %w", err)
	}
	prov := pulumi.Provider(osProvider)

	// ── 資源唯一 prefix（MD5 hash 避免截斷衝突）──────────────
	h := md5.Sum([]byte(identity))
	shortID := fmt.Sprintf("%x", h)[:8]
	prefix := "ctf-" + shortID

	// ── Security Group ────────────────────────────────────────
	sg, err := networking.NewSecGroup(ctx, prefix+"-sg", &networking.SecGroupArgs{
		Name:        pulumi.String(prefix + "-sg"),
		Description: pulumi.Sprintf("CTF sg for identity=%s", identity),
	}, prov)
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
	}, prov); err != nil {
		return err
	}

	// 允許 ICMP
	if _, err = networking.NewSecGroupRule(ctx, prefix+"-sg-icmp", &networking.SecGroupRuleArgs{
		Direction:       pulumi.String("ingress"),
		Ethertype:       pulumi.String("IPv4"),
		Protocol:        pulumi.String("icmp"),
		RemoteIpPrefix:  pulumi.String("0.0.0.0/0"),
		SecurityGroupId: sg.ID(),
	}, prov); err != nil {
		return err
	}

	// ── Port（明確建立，確保有已知 ID 可用於 FIP 關聯）────────
	// ✅ 不從 instance.Networks 讀 port ID（pulumi-openstack v3 回傳空值）
	// 改為先建 port，再讓 instance 和 FIP 都引用此 ID
	port, err := networking.NewPort(ctx, prefix+"-port", &networking.PortArgs{
		NetworkId:        pulumi.String(networkID),
		SecurityGroupIds: pulumi.StringArray{sg.ID()},
		AdminStateUp:     pulumi.Bool(true),
	}, prov, pulumi.DependsOn([]pulumi.Resource{sg}))
	if err != nil {
		return err
	}

	// ── VM ───────────────────────────────────────────────────
	// SecurityGroups 由 port 繼承，instance 本身不再設定
	instance, err := compute.NewInstance(ctx, prefix+"-vm", &compute.InstanceArgs{
		Name:       pulumi.String(prefix),
		ImageId:    pulumi.String(imageID),
		FlavorName: pulumi.String(flavorName),
		Networks: compute.InstanceNetworkArray{
			&compute.InstanceNetworkArgs{
				Port: port.ID(),
			},
		},
	}, prov, pulumi.DependsOn([]pulumi.Resource{port}))
	if err != nil {
		return err
	}

	// ── Floating IP（建立時直接指定 port，一步完成關聯）──────
	// ✅ 用 PortId 取代獨立的 FloatingIpAssociate resource
	// 原因：networking.NewFloatingIp + PortId 在 OpenStack API 層面是原子操作，
	// 不會出現「建立成功但 association 為 None」的問題
	fip, err := networking.NewFloatingIp(ctx, prefix+"-fip", &networking.FloatingIpArgs{
		Pool:   pulumi.String(fipPool),
		PortId: port.ID(),
	}, prov, pulumi.DependsOn([]pulumi.Resource{port, instance}))
	if err != nil {
		return err
	}

	// ── Outputs ───────────────────────────────────────────────
	ctx.Export("connection_info", fip.Address.ApplyT(func(ip string) string {
		return fmt.Sprintf("http://%s:%d", ip, challengePort)
	}).(pulumi.StringOutput))

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
