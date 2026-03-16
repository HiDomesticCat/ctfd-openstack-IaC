// openstack-vm scenario for chall-manager
// 為每位玩家建立一台獨立的 OpenStack VM 靶機
//
// 使用 chall-manager SDK 模式：
//   - identity 由 SDK 從 Pulumi config 自動讀取
//   - 題目設定透過 additional（per-challenge）讀取，fallback 到環境變數（全域）
//   - connection_info 和 flag 透過 sdk.Response 回傳
//
// additional 支援的 key（可在 CTFd Advanced 區塊設定）：
//   image_id          OpenStack image ID（必填；使用 Packer snapshot 可大幅加速啟動）
//   flavor            VM flavor（預設 general.small）
//   port              題目服務 port（預設 8080）
//   base_flag         flag 衍生基礎值
//   flag_prefix       flag 前綴（預設 CTF）
//   fip_pool          Floating IP pool（預設 public）
//   network_id        OpenStack network ID（通常為全域設定）
//   security_group_id 預建的 Security Group ID（若提供則跳過 SG 建立，省 ~3-5s）
//   flag_path         VM 內 flag 檔案路徑（預設 /opt/ctf/flag.txt）
//   cloud_init        自訂 cloud-init 腳本（支援 {{FLAG}} {{PORT}} {{IDENTITY}} 佔位符）
//   fip_address       預分配的 Floating IP 位址（跳過 FIP 建立，省 ~2-3s）
//
// 啟動加速策略：
//   1. Packer snapshot：出題者用 Packer 預先 bake 題目 image，VM 直接開機即可用
//   2. 共用 SG：security_group_id 跳過 per-player SG 建立
//   3. 預分配 FIP：fip_address 跳過 FIP 建立
//   4. cloud-init 最小化：有 snapshot 時 cloud-init 只寫 flag（< 5 秒）
//   5. 資源平行建立：VM 和 FIP 無冗餘依賴，同時建立
//
// NOTE: 使用 pulumi-openstack SDK v3 (terraform-provider-openstack v1.x)
//       SDK v4.1.0 對應的 terraform-provider-openstack v2.1.0 有 nil panic bug：
//       panic: interface conversion: interface {} is nil @ configureProvider/getOkExists
//
// NOTE: FIP association 必須使用明確建立的 port（不依賴 instance.Networks 輸出）
//       原因：pulumi-openstack v3 的 instance.Networks.Port() 回傳空值
package main

import (
	"crypto/md5"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/ctfer-io/chall-manager/sdk"
	"github.com/pulumi/pulumi-openstack/sdk/v3/go/openstack"
	"github.com/pulumi/pulumi-openstack/sdk/v3/go/openstack/compute"
	"github.com/pulumi/pulumi-openstack/sdk/v3/go/openstack/networking"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	sdk.Run(run)
}

func run(req *sdk.Request, resp *sdk.Response, opts ...pulumi.ResourceOption) error {
	ctx := req.Ctx
	identity := req.Config.Identity

	// ── 題目設定（additional 優先，fallback 到環境變數）────────
	imageID := configOrEnv(req, "image_id", "CHALLENGE_IMAGE_ID", "")
	if imageID == "" {
		return fmt.Errorf("image_id is required (set via additional or CHALLENGE_IMAGE_ID env)")
	}
	networkID := configOrEnv(req, "network_id", "CHALLENGE_NETWORK_ID", "")
	if networkID == "" {
		return fmt.Errorf("network_id is required (set via additional or CHALLENGE_NETWORK_ID env)")
	}
	flavorName := configOrEnv(req, "flavor", "CHALLENGE_FLAVOR", "general.small")
	fipPool := configOrEnv(req, "fip_pool", "CHALLENGE_FIP_POOL", "public")
	challengePortStr := configOrEnv(req, "port", "CHALLENGE_PORT", "8080")
	baseFlag := configOrEnv(req, "base_flag", "CHALLENGE_BASE_FLAG", "change_me")
	flagPrefix := configOrEnv(req, "flag_prefix", "CHALLENGE_FLAG_PREFIX", "CTF")

	// ── 啟動加速設定 ──────────────────────────────────────────
	flagPath := configOrEnv(req, "flag_path", "", "/opt/ctf/flag.txt")
	customCloudInit := configOrEnv(req, "cloud_init", "", "")
	fipAddress := configOrEnv(req, "fip_address", "", "")

	challengePort, err := strconv.Atoi(challengePortStr)
	if err != nil {
		return fmt.Errorf("invalid port %q: %w", challengePortStr, err)
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
	provOpt := pulumi.Provider(osProvider)

	// 合併 SDK opts 與 OpenStack provider option
	withProv := func(extra ...pulumi.ResourceOption) []pulumi.ResourceOption {
		all := make([]pulumi.ResourceOption, 0, len(opts)+len(extra)+1)
		all = append(all, opts...)
		all = append(all, provOpt)
		all = append(all, extra...)
		return all
	}

	// ── 資源唯一 prefix（MD5 hash 避免截斷衝突）──────────────
	h := md5.Sum([]byte(identity))
	shortID := fmt.Sprintf("%x", h)[:8]
	prefix := "ctf-" + shortID

	// ── 動態 flag（per-player deterministic）─────────────────
	flag := fmt.Sprintf("%s{%s}", flagPrefix, sdk.Variate(identity, baseFlag))

	// ── User Data（cloud-init: 注入 flag 到 VM）──────────────
	// 使用 snapshot 時 cloud-init 只寫 flag，啟動時間 < 5 秒
	userData := generateUserData(flag, flagPath, challengePort, identity, customCloudInit)

	// ── Security Group ────────────────────────────────────────
	// 若提供 security_group_id，使用預建的共用 SG（省 ~3-5s）
	// 否則動態建立 per-player SG
	sharedSGID := configOrEnv(req, "security_group_id", "CHALLENGE_SECURITY_GROUP_ID", "")

	var sgID pulumi.IDOutput
	if sharedSGID != "" {
		// 使用預建的共用 SG，不建立任何 SG 資源
		sgID = pulumi.ID(sharedSGID).ToIDOutput()
	} else {
		// 動態建立 per-player SG
		sg, err := networking.NewSecGroup(ctx, prefix+"-sg", &networking.SecGroupArgs{
			Name:        pulumi.String(prefix + "-sg"),
			Description: pulumi.Sprintf("CTF sg for identity=%s", identity),
		}, withProv()...)
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
		}, withProv()...); err != nil {
			return err
		}

		// 允許 ICMP
		if _, err = networking.NewSecGroupRule(ctx, prefix+"-sg-icmp", &networking.SecGroupRuleArgs{
			Direction:       pulumi.String("ingress"),
			Ethertype:       pulumi.String("IPv4"),
			Protocol:        pulumi.String("icmp"),
			RemoteIpPrefix:  pulumi.String("0.0.0.0/0"),
			SecurityGroupId: sg.ID(),
		}, withProv()...); err != nil {
			return err
		}

		sgID = sg.ID()
	}

	// ── Port（明確建立，確保有已知 ID 可用於 FIP 關聯）────────
	port, err := networking.NewPort(ctx, prefix+"-port", &networking.PortArgs{
		NetworkId:        pulumi.String(networkID),
		SecurityGroupIds: pulumi.StringArray{sgID},
		AdminStateUp:     pulumi.Bool(true),
	}, withProv()...)
	if err != nil {
		return err
	}

	// ── VM ───────────────────────────────────────────────────
	// VM 和 FIP 平行建立：兩者都只依賴 port，不互相依賴
	// ConfigDrive: metadata 直接掛載為 ISO，cloud-init 不用等 DHCP 取 metadata（省 ~20s）
	_, err = compute.NewInstance(ctx, prefix+"-vm", &compute.InstanceArgs{
		Name:        pulumi.String(prefix),
		ImageId:     pulumi.String(imageID),
		FlavorName:  pulumi.String(flavorName),
		UserData:    pulumi.String(userData),
		ConfigDrive: pulumi.Bool(true),
		Networks: compute.InstanceNetworkArray{
			&compute.InstanceNetworkArgs{
				Port: port.ID(),
			},
		},
	}, withProv()...) // port.ID() 已建立隱式依賴
	if err != nil {
		return err
	}

	// ── Floating IP ──────────────────────────────────────────
	// 取得 FIP 的 IP 位址 output，用於 readiness check 和 connectionInfo
	var fipAddr pulumi.StringOutput

	if fipAddress != "" {
		// 使用預分配的 FIP（省 ~2-3s FIP 建立時間）
		// FloatingIpAssociate 只管理關聯，不建立/刪除 FIP 本身
		_, err = networking.NewFloatingIpAssociate(ctx, prefix+"-fip-assoc", &networking.FloatingIpAssociateArgs{
			FloatingIp: pulumi.String(fipAddress),
			PortId:     port.ID(),
		}, withProv()...)
		if err != nil {
			return err
		}
		fipAddr = pulumi.String(fipAddress).ToStringOutput()
	} else {
		// 建立新 FIP（建立時直接指定 port，一步完成關聯）
		fip, err := networking.NewFloatingIp(ctx, prefix+"-fip", &networking.FloatingIpArgs{
			Pool:   pulumi.String(fipPool),
			PortId: port.ID(),
		}, withProv()...) // port.ID() 已建立隱式依賴；不依賴 VM → FIP 與 VM 平行建立
		if err != nil {
			return err
		}
		fipAddr = fip.Address
	}

	// ── Readiness Check ─────────────────────────────────────
	// 等待 VM 上的 challenge service 真正就緒（TCP port 可連）
	// Pulumi 會等 ApplyT 完成才回傳結果給 chall-manager → CTFd
	// 這樣玩家拿到 URL 時，服務保證可用
	resp.ConnectionInfo = fipAddr.ApplyT(func(ip string) string {
		waitForPort(ip, challengePort, 120*time.Second)
		return fmt.Sprintf("http://%s:%d", ip, challengePort)
	}).(pulumi.StringOutput)
	ctx.Export("ssh_command", fipAddr.ApplyT(func(ip string) string {
		return "ssh ubuntu@" + ip
	}).(pulumi.StringOutput))
	ctx.Export("floating_ip", fipAddr)

	resp.Flag = pulumi.String(flag).ToStringOutput()
	return nil
}

// generateUserData 產生 cloud-init user_data，將動態 flag 注入 VM
//
// 若提供 customScript，替換佔位符後直接使用（支援 shell script 或 cloud-config）。
// 否則產生預設的 cloud-config，只寫入 flag 檔案（搭配 snapshot 使用時 < 5 秒）。
func generateUserData(flag, flagPath string, port int, identity, customScript string) string {
	if customScript != "" {
		r := strings.NewReplacer(
			"{{FLAG}}", flag,
			"{{FLAG_PATH}}", flagPath,
			"{{PORT}}", strconv.Itoa(port),
			"{{IDENTITY}}", identity,
		)
		return r.Replace(customScript)
	}

	// 預設 cloud-config：只寫 flag（最小化，搭配 Packer snapshot 使用）
	return fmt.Sprintf(`#cloud-config
write_files:
  - path: %s
    content: |
      %s
    permissions: '0444'
    owner: root:root
`, flagPath, flag)
}

// configOrEnv 從 additional config 讀取，fallback 到環境變數，再 fallback 到預設值
func configOrEnv(req *sdk.Request, key, envKey, defaultVal string) string {
	if v, ok := req.Config.Additional[key]; ok && v != "" {
		return v
	}
	if envKey != "" {
		if v := os.Getenv(envKey); v != "" {
			return v
		}
	}
	return defaultVal
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

// waitForPort 等待 TCP port 可連線（服務就緒）
// 適用於所有題型：HTTP、SSH、TCP/NC
func waitForPort(host string, port int, timeout time.Duration) {
	addr := fmt.Sprintf("%s:%d", host, port)
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		conn, err := net.DialTimeout("tcp", addr, 3*time.Second)
		if err == nil {
			conn.Close()
			return
		}
		time.Sleep(2 * time.Second)
	}
	// timeout 不 fail deployment，只是 log warning
	fmt.Printf("WARNING: readiness check timed out for %s (waited %s)\n", addr, timeout)
}
