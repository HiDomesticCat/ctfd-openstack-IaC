# ctfd/versions.tf

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# 使用 clouds.yaml 管理連線資訊，避免在 tf 檔中放置明文憑證
# cloud entry 中已包含 project_name 和 username，不在此重複指定
provider "openstack" {
  cloud = var.openstack_cloud
}
