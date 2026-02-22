module github.com/ctferio/scenarios/k8s-pod

go 1.22

require (
	github.com/pulumi/pulumi-kubernetes/sdk/v4 v4.18.3
	github.com/pulumi/pulumi/sdk/v3 v3.143.0
)

// 執行 go mod tidy 自動補全間接依賴
