// k8s-pod scenario for chall-manager
// 為每位 CTF 玩家在 k3s 叢集動態建立獨立的 Kubernetes 靶機環境
//
// 使用 chall-manager SDK 模式：
//   - identity 由 SDK 從 Pulumi config 自動讀取
//   - 題目設定透過 additional（per-challenge）讀取，fallback 到環境變數（全域）
//   - connection_info 和 flag 透過 sdk.Response 回傳
//
// additional 支援的 key（可在 CTFd Advanced 區塊設定）：
//   image          靶機 container image（預設 ubuntu:22.04）
//   port           靶機服務 port（預設 22）
//   command        覆蓋 entrypoint（逗號分隔，如 "sleep,infinity"）
//   base_flag      flag 衍生基礎值
//   flag_prefix    flag 前綴（預設 CTF）
//   cpu_request    CPU request（預設 100m）
//   cpu_limit      CPU limit（預設 500m）
//   memory_request Memory request（預設 128Mi）
//   memory_limit   Memory limit（預設 512Mi）
//
// 建立的 Kubernetes 資源（每位玩家一組，以 shortID 隔離）：
//   - Namespace  ctf-<shortID>          （玩家隔離邊界）
//   - Pod        ctf-<shortID>          （靶機本體，resource limited）
//   - Service    ctf-<shortID>-svc      （NodePort，玩家連線入口）
package main

import (
	"crypto/md5"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/ctfer-io/chall-manager/sdk"
	corev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// shortID 從玩家 identity 產生 8 字元識別碼（MD5 前 8 hex）。
// 用途：Kubernetes 資源命名（需符合 DNS 規範且夠短）。
func shortID(identity string) string {
	h := md5.Sum([]byte(identity))
	return fmt.Sprintf("%x", h)[:8]
}

func main() {
	sdk.Run(func(req *sdk.Request, resp *sdk.Response, opts ...pulumi.ResourceOption) error {
		ctx := req.Ctx
		identity := req.Config.Identity
		sid := shortID(identity)

		// ── 題目設定（additional 優先，fallback 到環境變數）────
		baseFlag := configOrEnv(req, "base_flag", "CHALLENGE_BASE_FLAG", "default_base_flag")
		flagPrefix := configOrEnv(req, "flag_prefix", "CHALLENGE_FLAG_PREFIX", "CTF")
		image := configOrEnv(req, "image", "CHALLENGE_IMAGE", "ubuntu:22.04")
		challengePortStr := configOrEnv(req, "port", "CHALLENGE_PORT", "22")

		challengePort, _ := strconv.Atoi(challengePortStr)
		if challengePort == 0 {
			challengePort = 22
		}

		// ── 資源限制（additional 可覆蓋）─────────────────────
		cpuRequest := configOrEnv(req, "cpu_request", "", "100m")
		cpuLimit := configOrEnv(req, "cpu_limit", "", "500m")
		memRequest := configOrEnv(req, "memory_request", "", "128Mi")
		memLimit := configOrEnv(req, "memory_limit", "", "512Mi")

		// ── 可選指令覆蓋（comma-separated）────────────────────
		// 測試時設 command="sleep,infinity" 讓容器持續運行
		var containerCommand pulumi.StringArray
		if rawCmd := configOrEnv(req, "command", "CHALLENGE_COMMAND", ""); rawCmd != "" {
			for _, part := range strings.Split(rawCmd, ",") {
				containerCommand = append(containerCommand, pulumi.String(strings.TrimSpace(part)))
			}
		}

		// ── 動態 flag（使用 SDK Variate，統一演算法）─────────
		flag := fmt.Sprintf("%s{%s}", flagPrefix, sdk.Variate(identity, baseFlag))

		// worker IPs（逗號分隔，取第一個供連線資訊使用）
		rawWorkerIPs := envOrDefault("K3S_WORKER_IPS", "")
		workerIPs := strings.Split(rawWorkerIPs, ",")
		workerIP := strings.TrimSpace(workerIPs[0])

		// ── Kubernetes 資源名稱 ────────────────────────────
		nsName := fmt.Sprintf("ctf-%s", sid)
		podName := fmt.Sprintf("ctf-%s", sid)
		svcName := fmt.Sprintf("ctf-%s-svc", sid)

		// ── Namespace（每位玩家獨立）──────────────────────
		ns, err := corev1.NewNamespace(ctx, "ns", &corev1.NamespaceArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Name: pulumi.String(nsName),
				Labels: pulumi.StringMap{
					"managed-by":   pulumi.String("chall-manager"),
					"ctf-id":       pulumi.String(sid),
					"ctf-scenario": pulumi.String("k8s-pod"),
				},
				// ✅ skipAwait：destroy 時不等 namespace 內所有資源清空
				Annotations: pulumi.StringMap{
					"pulumi.com/skipAwait": pulumi.String("true"),
				},
			},
		}, opts...)
		if err != nil {
			return fmt.Errorf("create namespace: %w", err)
		}

		// ── Challenge Pod ──────────────────────────────────
		_, err = corev1.NewPod(ctx, "pod", &corev1.PodArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Namespace: ns.Metadata.Name(),
				Name:      pulumi.String(podName),
				Labels: pulumi.StringMap{
					"app":          pulumi.String("ctf-challenge"),
					"ctf-id":       pulumi.String(sid),
					"ctf-scenario": pulumi.String("k8s-pod"),
				},
				// ✅ skipAwait：不等 Pod Running，Pulumi 建完即繼續
				Annotations: pulumi.StringMap{
					"pulumi.com/skipAwait": pulumi.String("true"),
				},
			},
			Spec: &corev1.PodSpecArgs{
				// ✅ 設為 0：跳過 graceful shutdown，Pod 立即強制刪除
				TerminationGracePeriodSeconds: pulumi.Int(0),
				Containers: corev1.ContainerArray{
					&corev1.ContainerArgs{
						Name:            pulumi.String("challenge"),
						Image:           pulumi.String(image),
						ImagePullPolicy: pulumi.String("IfNotPresent"),
						Command:         containerCommand, // nil = 使用 image 預設 entrypoint
						Resources: &corev1.ResourceRequirementsArgs{
							Requests: pulumi.StringMap{
								"cpu":    pulumi.String(cpuRequest),
								"memory": pulumi.String(memRequest),
							},
							Limits: pulumi.StringMap{
								"cpu":    pulumi.String(cpuLimit),
								"memory": pulumi.String(memLimit),
							},
						},
						Env: corev1.EnvVarArray{
							&corev1.EnvVarArgs{
								Name:  pulumi.String("CTF_FLAG"),
								Value: pulumi.String(flag),
							},
							&corev1.EnvVarArgs{
								Name:  pulumi.String("CTF_IDENTITY"),
								Value: pulumi.String(identity),
							},
						},
						Ports: corev1.ContainerPortArray{
							&corev1.ContainerPortArgs{
								ContainerPort: pulumi.Int(challengePort),
								Protocol:      pulumi.String("TCP"),
							},
						},
					},
				},
				RestartPolicy: pulumi.String("Never"),
			},
		}, opts...)
		if err != nil {
			return fmt.Errorf("create pod: %w", err)
		}

		// ── NodePort Service（玩家連線入口）──────────────
		svc, err := corev1.NewService(ctx, "svc", &corev1.ServiceArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Namespace: ns.Metadata.Name(),
				Name:      pulumi.String(svcName),
				Annotations: pulumi.StringMap{
					"pulumi.com/skipAwait": pulumi.String("true"),
				},
			},
			Spec: &corev1.ServiceSpecArgs{
				Type: pulumi.String("NodePort"),
				Selector: pulumi.StringMap{
					"app":    pulumi.String("ctf-challenge"),
					"ctf-id": pulumi.String(sid),
				},
				Ports: corev1.ServicePortArray{
					&corev1.ServicePortArgs{
						Name:       pulumi.String("challenge"),
						Port:       pulumi.Int(challengePort),
						TargetPort: pulumi.Int(challengePort),
						Protocol:   pulumi.String("TCP"),
					},
				},
			},
		}, opts...)
		if err != nil {
			return fmt.Errorf("create service: %w", err)
		}

		// ── Response（SDK 自動 export connection_info 和 flag）───
		resp.ConnectionInfo = svc.Spec.ApplyT(func(spec corev1.ServiceSpec) string {
			if len(spec.Ports) == 0 || spec.Ports[0].NodePort == nil {
				return fmt.Sprintf("Service initializing... worker=%s", workerIP)
			}
			nodePort := *spec.Ports[0].NodePort
			if challengePort == 22 {
				return fmt.Sprintf("ssh ctf@%s -p %d", workerIP, nodePort)
			}
			return fmt.Sprintf("%s:%d", workerIP, nodePort)
		}).(pulumi.StringOutput)

		resp.Flag = pulumi.String(flag).ToStringOutput()

		return nil
	})
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

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
