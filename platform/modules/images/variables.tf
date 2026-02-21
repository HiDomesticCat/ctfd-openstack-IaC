# platform/modules/images/variables.tf

variable "images" {
  description = "要上傳的 image 清單"
  type = map(object({
    name             = string
    source_url       = string
    container_format = string
    disk_format      = string
    visibility       = string
    min_disk_gb      = number
    min_ram_mb       = number
    properties       = map(string)
  }))
}
