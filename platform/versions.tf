# platform/versions.tf
terraform {
  required_version = ">= 1.11.0"

  # 遠程 backend 配置（生產環境強烈建議使用）
  # 取消註解並配置適當的 backend
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "platform/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }
}

provider "openstack" {
  cloud = var.openstack_cloud
}
