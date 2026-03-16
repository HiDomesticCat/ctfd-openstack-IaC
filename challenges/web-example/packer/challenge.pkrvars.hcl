# web-example 題目的 Packer 變數
# 用法：cd packer && packer build -var-file=../challenges/web-example/packer/challenge.pkrvars.hcl .

challenge_name        = "web-example"
challenge_description = "Web 漏洞練習：HTTP header 注入 + 目錄遍歷"
challenge_port        = 8080

# 題目專屬 provisioning script
provision_scripts = [
  "../challenges/web-example/packer/scripts/setup.sh"
]
