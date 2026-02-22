// k8s-pod scenario for chall-manager
// 為每位 CTF 玩家在 k3s 叢集動態建立獨立的 Kubernetes 靶機環境
//
// chall-manager 規範：
//   - Config key : k8s-pod:identity     （chall-manager 自動注入）
//   - Output key : connection_info      （玩家連線 URL，必填）
//   - Output key : flag                 （動態 flag，選填）
//
// 建立的 Kubernetes 資源（每位玩家一組，以 shortID 隔離）：
//   - Namespace  ctf-<shortID>          （玩家隔離邊界）
//   - Pod        ctf-<shortID>          （靶機本體，resource limited）
//   - Service    ctf-<shortID>-svc      （NodePort，玩家連線入口）
//
// 環境變數（由 docker-compose chall-manager 注入）：
//   CHALLENGE_IMAGE       靶機 container image
//   CHALLENGE_PORT        靶機服務 port（預設 22）
//   CHALLENGE_COMMAND     覆蓋 entrypoint（測試用，如 "sleep,infinity"）
//   CHALLENGE_BASE_FLAG   flag 衍生基礎值
//   CHALLENGE_FLAG_PREFIX flag 前綴（預設 CTF）
//   K3S_WORKER_IPS        worker 節點 IP（逗號分隔，取第一個作為連線 IP）
//   KUBECONFIG            k3s kubeconfig 路徑（容器內 bind mount）
//
// NOTE: shortID 使用 MD5 前 8 hex 字元，目的是縮短 Kubernetes 資源名稱。
//       MD5 在此為 identifier 生成（非密碼學安全用途），不作密碼存儲。
//       若需要加密安全的 flag 生成，請參考 openstack-vm/main.go 的 HMAC-SHA256 做法。
package main

import (
	"crypto/md5"
	"fmt"
	"os"
	"strconv"
	"strings"

	corev1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/core/v1"
	metav1 "github.com/pulumi/pulumi-kubernetes/sdk/v4/go/kubernetes/meta/v1"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

// shortID 從玩家 identity 產生 8 字元識別碼（MD5 前 8 hex）。
// 用途：Kubernetes 資源命名（Namespace/Pod/Service 名稱需符合 DNS 規範且夠短）。
// 安全說明：MD5 在此為 identifier 生成，非密碼學安全用途。
func shortID(identity string) string {
	h := md5.Sum([]byte(identity))
	return fmt.Sprintf("%x", h)[:8]
}

// dynamicFlag 基於 baseFlag + identity 產生玩家專屬動態 flag。
// 演算法：MD5(baseFlag + identity) → 32 hex 字元。
// 注意：相較於 openstack-vm scenario 的 HMAC-SHA256，此處 MD5 較弱，
// 玩家若知道 baseFlag 可推算其他人的 flag。建議 baseFlag 使用足夠長的隨機值。
func dynamicFlag(baseFlag, identity, prefix string) string {
	h := md5.Sum([]byte(baseFlag + identity))
	return fmt.Sprintf("%s{%x}", prefix, h)
}

// getEnv 讀取環境變數，若未設定則回傳 fallback
func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "")
		identity := cfg.Require("identity")
		sid := shortID(identity)

		// ── 動態 flag ──────────────────────────────────────
		baseFlag := getEnv("CHALLENGE_BASE_FLAG", "default_base_flag")
		flagPrefix := getEnv("CHALLENGE_FLAG_PREFIX", "CTF")
		flag := dynamicFlag(baseFlag, identity, flagPrefix)

		// ── Challenge 設定（從環境變數讀取）────────────────
		// chall-manager 容器將這些 env vars 傳遞給 Pulumi 子程序
		image := getEnv("CHALLENGE_IMAGE", "ubuntu:22.04")

		// ── 可選指令覆蓋（comma-separated）────────────────
		// 測試時設 CHALLENGE_COMMAND="sleep,infinity" 讓容器持續運行
		// 正式 challenge image 通常不需要此設定（image 自帶啟動命令）
		var containerCommand pulumi.StringArray
		if rawCmd := getEnv("CHALLENGE_COMMAND", ""); rawCmd != "" {
			for _, part := range strings.Split(rawCmd, ",") {
				containerCommand = append(containerCommand, pulumi.String(strings.TrimSpace(part)))
			}
		}

		challengePort, _ := strconv.Atoi(getEnv("CHALLENGE_PORT", "22"))
		if challengePort == 0 {
			challengePort = 22
		}

		// worker IPs（逗號分隔，取第一個供連線資訊使用）
		rawWorkerIPs := getEnv("K3S_WORKER_IPS", "")
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
				// Kubernetes namespace 刪除本身會等所有子資源刪除，不需要 Pulumi 額外等待
				Annotations: pulumi.StringMap{
					"pulumi.com/skipAwait": pulumi.String("true"),
				},
			},
		})
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
				// 避免因 challenge image 啟動慢或 imagePull 時間長造成 timeout
				Annotations: pulumi.StringMap{
					"pulumi.com/skipAwait": pulumi.String("true"),
				},
			},
			Spec: &corev1.PodSpecArgs{
				// ✅ 設為 0：跳過 graceful shutdown，Pod 立即強制刪除
				// 預設 30 秒的 grace period 會讓關閉題目花很長時間
				// CTF 靶機為一次性環境，不需要 graceful shutdown
				TerminationGracePeriodSeconds: pulumi.Int(0),
				Containers: corev1.ContainerArray{
					&corev1.ContainerArgs{
						Name:    pulumi.String("challenge"),
						Image:   pulumi.String(image),
						Command: containerCommand, // nil = 使用 image 預設 entrypoint
						// ── 資源限制（防止單個 pod 耗盡節點資源）──
						Resources: &corev1.ResourceRequirementsArgs{
							Requests: pulumi.StringMap{
								"cpu":    pulumi.String("100m"),
								"memory": pulumi.String("128Mi"),
							},
							Limits: pulumi.StringMap{
								"cpu":    pulumi.String("500m"),
								"memory": pulumi.String("512Mi"),
							},
						},
						// ── 環境變數（flag + identity 注入到靶機）──
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
				// ✅ Never：pod 完成後不重啟（靶機為一次性環境）
				RestartPolicy: pulumi.String("Never"),
			},
		})
		if err != nil {
			return fmt.Errorf("create pod: %w", err)
		}

		// ── NodePort Service（玩家連線入口）──────────────
		// Kubernetes 自動在 30000-32767 範圍內分配 NodePort
		svc, err := corev1.NewService(ctx, "svc", &corev1.ServiceArgs{
			Metadata: &metav1.ObjectMetaArgs{
				Namespace: ns.Metadata.Name(),
				Name:      pulumi.String(svcName),
				// ✅ skipAwait：不等 Service 有 ready endpoints，Pulumi 建完即回傳 NodePort
				// Service health check 預設會等 selector 對應的 Pod ready，
				// 但 NodePort 在 Service 建立時就已分配，不需要等 Pod ready 才能告知玩家連線資訊
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
		})
		if err != nil {
			return fmt.Errorf("create service: %w", err)
		}

		// ── Outputs ───────────────────────────────────────
		// connection_info：玩家連線指令
		connInfo := svc.Spec.ApplyT(func(spec corev1.ServiceSpec) string {
			if len(spec.Ports) == 0 || spec.Ports[0].NodePort == nil {
				return fmt.Sprintf("Service initializing... worker=%s", workerIP)
			}
			nodePort := *spec.Ports[0].NodePort
			if challengePort == 22 {
				return fmt.Sprintf("ssh ctf@%s -p %d", workerIP, nodePort)
			}
			return fmt.Sprintf("%s:%d", workerIP, nodePort)
		}).(pulumi.StringOutput)

		ctx.Export("connection_info", connInfo)
		ctx.Export("flag", pulumi.String(flag))

		return nil
	})
}
