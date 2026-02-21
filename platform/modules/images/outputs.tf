# platform/modules/images/outputs.tf

output "image_ids" {
  description = "所有上傳的 image ID，key 跟 input 的 map key 一致"
  value = {
    for k, image in openstack_images_image_v2.images :
    k => image.id
  }
}

output "image_names" {
  description = "所有上傳的 image 名稱"
  value = {
    for k, image in openstack_images_image_v2.images :
    k => image.name
  }
}