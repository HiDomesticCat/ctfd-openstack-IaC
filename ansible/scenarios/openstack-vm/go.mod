module openstack-vm

go 1.25

require (
	github.com/ctfer-io/chall-manager/sdk v0.6.3
	// ✅ 使用 SDK v3（對應 pulumi-resource-openstack v3.x / terraform-provider-openstack v1.x）
	// SDK v4.1.0 對應的 terraform-provider-openstack v2.1.0 有 GetRawConfig() nil panic bug
	github.com/pulumi/pulumi-openstack/sdk/v3 v3.15.0
	github.com/pulumi/pulumi/sdk/v3 v3.219.0
)

// 執行 go mod tidy 自動補全間接依賴
