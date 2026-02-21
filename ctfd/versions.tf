# ctfd-openstack/versions.tf

terraform {
  required_version = ">= 1.11.0"

  # 遠程 backend 配置（生產環境強烈建議使用）
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "ctfd-openstack/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
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
# 請在 ~/.config/openstack/clouds.yaml 新增 ctfd cloud entry：
#
# clouds:
#   ctfd:
#     auth:
#       auth_url: http://<openstack-ip>:5000/v3
#       username: ctfd-deployer
#       password: <password>
#       project_name: ctfd
#       user_domain_name: Default
#       project_domain_name: Default
#     region_name: RegionOne
#     interface: public
#     identity_api_version: 3
provider "openstack" {
  cloud = var.openstack_cloud
}
