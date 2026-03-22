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
//   connection_info   連線資訊模板（支援 {ip} {port} 佔位符，預設 "nc {ip} {port}"）
//                     範例："http://{ip}:{port}" / "ssh ubuntu@{ip}" / "nc {ip} {port}"
//   readiness_timeout 等待服務就緒的超時時間（預設 "0" 跳過檢查，最快啟動）
//                     範例："0"（跳過）/ "30s"（等最多 30 秒）/ "120s"（原始行為）
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
	useFIP := configOrEnv(req, "use_fip", "CHALLENGE_USE_FIP", "true") == "true"
	bootFromVolume := configOrEnv(req, "boot_from_volume", "CHALLENGE_BOOT_FROM_VOLUME", "false") == "true"
	volumeSizeStr := configOrEnv(req, "volume_size", "CHALLENGE_VOLUME_SIZE", "10")
	volumeSize, _ := strconv.Atoi(volumeSizeStr)
	challengePortStr := configOrEnv(req, "port", "CHALLENGE_PORT", "8080")
	baseFlag := configOrEnv(req, "base_flag", "CHALLENGE_BASE_FLAG", "change_me")
	flagPrefix := configOrEnv(req, "flag_prefix", "CHALLENGE_FLAG_PREFIX", "CTF")

	// ── 啟動加速設定 ──────────────────────────────────────────
	flagPath := configOrEnv(req, "flag_path", "", "/opt/ctf/flag.txt")
	customCloudInit := configOrEnv(req, "cloud_init", "", "")
	fipAddress := configOrEnv(req, "fip_address", "", "")
	connTpl := configOrEnv(req, "connection_info", "", "nc {ip} {port}")
	readinessTimeoutStr := configOrEnv(req, "readiness_timeout", "CHALLENGE_READINESS_TIMEOUT", "0")

	// 解析 readiness_timeout：支援 "0"（跳過）/ "30s" / "120"（秒數）
	var readinessTimeout time.Duration
	if d, derr := time.ParseDuration(readinessTimeoutStr); derr == nil {
		readinessTimeout = d
	} else if secs, serr := strconv.Atoi(readinessTimeoutStr); serr == nil {
		readinessTimeout = time.Duration(secs) * time.Second
	}

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

	// ── VM + 網路 ──────────────────────────────────────────────
	// use_fip=true  → 明確建 Port（FIP association 需要已知 Port ID）
	// use_fip=false → 不建 Port，Nova 自動建立/刪除（少一個 Pulumi 資源，加速 destroy）
	// ConfigDrive: metadata 直接掛載為 ISO，cloud-init 不用等 DHCP 取 metadata（省 ~20s）
	// ForceDelete: destroy 時跳過 graceful shutdown
	instanceArgs := &compute.InstanceArgs{
		Name:        pulumi.String(prefix),
		FlavorName:  pulumi.String(flavorName),
		UserData:    pulumi.String(userData),
		ConfigDrive: pulumi.Bool(true),
		ForceDelete: pulumi.Bool(true),
	}
	if bootFromVolume {
		instanceArgs.BlockDevices = compute.InstanceBlockDeviceArray{
			&compute.InstanceBlockDeviceArgs{
				Uuid:                pulumi.String(imageID),
				SourceType:          pulumi.String("image"),
				DestinationType:     pulumi.String("volume"),
				VolumeSize:          pulumi.Int(volumeSize),
				BootIndex:           pulumi.Int(0),
				DeleteOnTermination: pulumi.Bool(true),
			},
		}
	} else {
		instanceArgs.ImageId = pulumi.String(imageID)
	}

	var connAddr pulumi.StringOutput

	if useFIP {
		// ── FIP 模式：需要明確 Port（FIP association 依賴 Port ID）────
		port, err := networking.NewPort(ctx, prefix+"-port", &networking.PortArgs{
			NetworkId:        pulumi.String(networkID),
			SecurityGroupIds: pulumi.StringArray{sgID},
			AdminStateUp:     pulumi.Bool(true),
		}, withProv()...)
		if err != nil {
			return err
		}

		instanceArgs.Networks = compute.InstanceNetworkArray{
			&compute.InstanceNetworkArgs{
				Port: port.ID(),
			},
		}

		vm, err := compute.NewInstance(ctx, prefix+"-vm", instanceArgs, withProv()...)
		if err != nil {
			return err
		}
		_ = vm

		if fipAddress != "" {
			_, err = networking.NewFloatingIpAssociate(ctx, prefix+"-fip-assoc", &networking.FloatingIpAssociateArgs{
				FloatingIp: pulumi.String(fipAddress),
				PortId:     port.ID(),
			}, withProv()...)
			if err != nil {
				return err
			}
			connAddr = pulumi.String(fipAddress).ToStringOutput()
		} else {
			fip, err := networking.NewFloatingIp(ctx, prefix+"-fip", &networking.FloatingIpArgs{
				Pool:   pulumi.String(fipPool),
				PortId: port.ID(),
			}, withProv()...)
			if err != nil {
				return err
			}
			connAddr = fip.Address
		}
	} else {
		// ── 內網模式：不建 Port，Nova 自動管理（加速 boot + destroy）────
		instanceArgs.SecurityGroups = pulumi.StringArray{sgID}
		instanceArgs.Networks = compute.InstanceNetworkArray{
			&compute.InstanceNetworkArgs{
				Uuid: pulumi.String(networkID),
			},
		}

		vm, err := compute.NewInstance(ctx, prefix+"-vm", instanceArgs, withProv()...)
		if err != nil {
			return err
		}

		// 從 instance 的 network 資訊取得內網 IP（DHCP 分配）
		connAddr = vm.Networks.ApplyT(func(networks []compute.InstanceNetwork) string {
			if len(networks) > 0 && networks[0].FixedIpV4 != nil {
				return *networks[0].FixedIpV4
			}
			return "unknown"
		}).(pulumi.StringOutput)
	}

	// ── Readiness Check（可配置）─────────────────────────────
	// readiness_timeout=0（預設）：跳過檢查，立即回傳（最快啟動，搭配 Pooler 使用）
	// readiness_timeout>0：等待 TCP port 就緒（保守模式）
	resp.ConnectionInfo = connAddr.ApplyT(func(ip string) string {
		if readinessTimeout > 0 {
			waitForPort(ip, challengePort, readinessTimeout)
		}
		return formatConnectionInfo(connTpl, ip, challengePort)
	}).(pulumi.StringOutput)
	ctx.Export("ssh_command", connAddr.ApplyT(func(ip string) string {
		return "ssh ubuntu@" + ip
	}).(pulumi.StringOutput))
	ctx.Export("connection_ip", connAddr)

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

// formatConnectionInfo 根據模板產生連線資訊
// 支援 {ip} 和 {port} 佔位符，例如 "http://{ip}:{port}" → "http://1.2.3.4:8080"
func formatConnectionInfo(tpl, ip string, port int) string {
	r := strings.NewReplacer("{ip}", ip, "{port}", strconv.Itoa(port))
	return r.Replace(tpl)
}

// waitForPort 等待 TCP port 可連線（服務就緒）
// 適用於所有題型：HTTP、SSH、TCP/NC
func waitForPort(host string, port int, timeout time.Duration) {
	addr := fmt.Sprintf("%s:%d", host, port)
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		conn, err := net.DialTimeout("tcp", addr, 2*time.Second)
		if err == nil {
			conn.Close()
			return
		}
		time.Sleep(1 * time.Second)
	}
	// timeout 不 fail deployment，只是 log warning
	fmt.Printf("WARNING: readiness check timed out for %s (waited %s)\n", addr, timeout)
}
