# chell/versions.tf
# k3s 叢集 Infrastructure（for Chell Shell Challenge 後端）
# 依賴：需先完成 platform/ 與 ctfd/ 的 tofu apply

terraform {
  required_version = ">= 1.11.0"

  # 遠端 backend（生產環境強烈建議）
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "ctfd-openstack/chell/terraform.tfstate"
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
# 請在 ~/.config/openstack/clouds.yaml 新增（或使用已有的）ctfd cloud entry：
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
  cloud       = var.openstack_cloud
  tenant_name = "ctfd"
  user_name   = "ctfd-deployer"
}
