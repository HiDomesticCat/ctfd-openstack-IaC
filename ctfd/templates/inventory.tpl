[ctfd]
${ctfd_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_private_key}

[ctfd:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3
