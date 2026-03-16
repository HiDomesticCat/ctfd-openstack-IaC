module github.com/ctferio/scenarios/k8s-pod

go 1.25

require (
	github.com/ctfer-io/chall-manager/sdk v0.6.3
	github.com/pulumi/pulumi-kubernetes/sdk/v4 v4.25.0
	github.com/pulumi/pulumi/sdk/v3 v3.219.0
)

// 執行 go mod tidy 自動補全間接依賴
