# platform/modules/flavors/variables.tf

variable "flavors" {
  description = "要建立的 flavor 清單"
  type = map(object({
    name      = string
    ram       = number
    vcpus     = number
    disk      = number
    is_public = bool
  }))
}