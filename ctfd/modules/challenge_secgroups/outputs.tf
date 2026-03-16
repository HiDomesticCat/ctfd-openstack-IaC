# modules/challenge_secgroups/outputs.tf

output "ids" {
  description = "Challenge Security Group IDs（供 CTFd additional security_group_id 使用）"
  value = {
    allow_all = openstack_networking_secgroup_v2.allow_all.id
    allow_ssh = openstack_networking_secgroup_v2.allow_ssh.id
    allow_web = openstack_networking_secgroup_v2.allow_web.id
  }
}
