# platform/modules/images/main.tf

resource "openstack_images_image_v2" "images" {
  # for_each 讓這個 resource 根據 images 變數的內容
  # 自動建立對應數量的 image
  for_each = var.images

  name             = each.value.name
  image_source_url = each.value.source_url
  container_format = each.value.container_format
  disk_format      = each.value.disk_format
  visibility       = each.value.visibility
  min_disk_gb      = each.value.min_disk_gb
  min_ram_mb       = each.value.min_ram_mb

  properties = each.value.properties

  # image 下載需要時間，設定合理的 timeout
  timeouts {
    create = "30m"
  }
}