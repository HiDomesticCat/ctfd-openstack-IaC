# ansible/inventory/k3s_hosts.ini
# 由 chell/main.tf 自動產生，請勿手動修改
# 與 ansible/inventory/hosts.ini（由 ctfd/ 產生）搭配使用

[k3s_master]
${master_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_private_key}

[k3s_workers]
%{ for ip in worker_ips ~}
${ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_private_key}
%{ endfor ~}

[k3s:children]
k3s_master
k3s_workers

[k3s:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3
