# ctfd-openstack Makefile
# 管理 platform / ctfd / chell 三層 IaC + Ansible
#
# 多環境支援：
#   make deploy-platform ENV=lab50    # 使用 lab50 環境設定
#   make deploy-ctfd ENV=lab50
#   make deploy-chell ENV=lab50
#
# 不指定 ENV 時使用各層目錄內的 terraform.tfvars（向下相容）

CHELL_DIR   := $(CURDIR)/chell
CTF_DIR     := $(CURDIR)/ctfd
PLAT_DIR    := $(CURDIR)/platform
PACKER_DIR  := $(CURDIR)/packer
ENV_DIR     := $(CURDIR)/environments
SHELL       := /usr/bin/env bash

# 環境設定檔路徑（ENV 有值時使用 environments/<ENV>/*.tfvars）
ifdef ENV
  PLAT_VARFILE  := -var-file=$(ENV_DIR)/$(ENV)/platform.tfvars
  CTF_VARFILE   := -var-file=$(ENV_DIR)/$(ENV)/ctfd.tfvars
  CHELL_VARFILE := -var-file=$(ENV_DIR)/$(ENV)/chell.tfvars
else
  PLAT_VARFILE  :=
  CTF_VARFILE   :=
  CHELL_VARFILE :=
endif

# ── platform 層 ───────────────────────────────────────────

.PHONY: plan-platform
plan-platform:
	cd $(PLAT_DIR) && tofu plan $(PLAT_VARFILE)

.PHONY: deploy-platform
deploy-platform:
	cd $(PLAT_DIR) && tofu apply $(PLAT_VARFILE)

.PHONY: destroy-platform
destroy-platform:
	cd $(PLAT_DIR) && tofu destroy $(PLAT_VARFILE)

.PHONY: output-platform
output-platform:
	cd $(PLAT_DIR) && tofu output

# ── ctfd 層 ───────────────────────────────────────────────

.PHONY: plan-ctfd
plan-ctfd:
	cd $(CTF_DIR) && tofu plan $(CTF_VARFILE)

.PHONY: deploy-ctfd
deploy-ctfd:
	cd $(CTF_DIR) && tofu apply $(CTF_VARFILE)

.PHONY: destroy-ctfd
destroy-ctfd:
	cd $(CTF_DIR) && tofu destroy $(CTF_VARFILE)

.PHONY: output-ctfd
output-ctfd:
	cd $(CTF_DIR) && tofu output

# ── chell 層 ──────────────────────────────────────────────

.PHONY: plan-chell
plan-chell:
	cd $(CHELL_DIR) && tofu plan $(CHELL_VARFILE)

.PHONY: deploy-chell
deploy-chell:
ifdef ENV
	ENV_DIR=$(ENV_DIR) ENV=$(ENV) bash $(CHELL_DIR)/deploy.sh
else
	@bash $(CHELL_DIR)/deploy.sh
endif

# 全自動模式（CI / 測試用）：tofu 不問確認、vault 從檔案讀取
# 用法：make deploy-chell-auto VAULT_PASS_FILE=~/.vault_pass ENV=lab50
.PHONY: deploy-chell-auto
deploy-chell-auto:
ifdef ENV
	AUTO_APPROVE=true VAULT_PASS_FILE=$(VAULT_PASS_FILE) ENV_DIR=$(ENV_DIR) ENV=$(ENV) bash $(CHELL_DIR)/deploy.sh
else
	AUTO_APPROVE=true VAULT_PASS_FILE=$(VAULT_PASS_FILE) bash $(CHELL_DIR)/deploy.sh
endif

# 只跑 tofu apply，不跑 ansible（用於先建好 infra 再手動 ansible）
.PHONY: infra-chell
infra-chell:
	cd $(CHELL_DIR) && tofu apply $(CHELL_VARFILE)

.PHONY: destroy-chell
destroy-chell:
	cd $(CHELL_DIR) && tofu destroy $(CHELL_VARFILE)

.PHONY: output-chell
output-chell:
	cd $(CHELL_DIR) && tofu output

# ── Ansible only（infra 已存在時快速重跑） ────────────────

.PHONY: ansible
ansible:
	@WORKER_IPS_JSON=$$(cd $(CHELL_DIR) && tofu output -json worker_floating_ips 2>/dev/null || echo '[]'); \
	VAULT_ARG=""; \
	if grep -qrl '^\$$ANSIBLE_VAULT' $(CURDIR)/ansible 2>/dev/null; then VAULT_ARG="--ask-vault-pass"; fi; \
	cd $(CURDIR)/ansible && \
	ansible-playbook site.yml \
	  -i inventory/hosts.ini \
	  -i inventory/k3s_hosts.ini \
	  --extra-vars "{\"k3s_worker_ips\": $$WORKER_IPS_JSON}" \
	  $$VAULT_ARG

.PHONY: ansible-k3s
ansible-k3s:
	@WORKER_IPS_JSON=$$(cd $(CHELL_DIR) && tofu output -json worker_floating_ips); \
	VAULT_ARG=""; \
	if grep -qrl '^\$$ANSIBLE_VAULT' $(CURDIR)/ansible 2>/dev/null; then VAULT_ARG="--ask-vault-pass"; fi; \
	cd $(CURDIR)/ansible && \
	ansible-playbook site.yml \
	  -i inventory/k3s_hosts.ini \
	  --tags k3s \
	  --extra-vars "{\"k3s_worker_ips\": $$WORKER_IPS_JSON}" \
	  $$VAULT_ARG

# ── Packer（題目 image snapshot）──────────────────────────
# 用法：make packer-build CHALLENGE=web-example ENV=lab50
# 流程：base setup → 題目 provisioning → cleanup → snapshot

.PHONY: packer-init
packer-init:
	cd $(PACKER_DIR) && packer init .

.PHONY: packer-validate
packer-validate:
	@if [ -z "$(CHALLENGE)" ]; then echo "Usage: make packer-validate CHALLENGE=<name>"; exit 1; fi
	cd $(PACKER_DIR) && packer validate \
	  $(if $(ENV),-var-file=$(ENV_DIR)/$(ENV)/packer.pkrvars.hcl) \
	  -var-file=../challenges/$(CHALLENGE)/packer/challenge.pkrvars.hcl .

.PHONY: packer-build
packer-build:
	@if [ -z "$(CHALLENGE)" ]; then echo "Usage: make packer-build CHALLENGE=<name>"; exit 1; fi
	cd $(PACKER_DIR) && packer build \
	  $(if $(ENV),-var-file=$(ENV_DIR)/$(ENV)/packer.pkrvars.hcl) \
	  -var-file=../challenges/$(CHALLENGE)/packer/challenge.pkrvars.hcl .
	@echo ""
	@echo "==> Image 建立完成。執行以下步驟完成部署："
	@echo "  1. 將新 image ID 更新到 challenges/$(CHALLENGE)/challenge.yml"
	@echo "  2. make register-challenges --force"
	@echo "  3. （選用）make packer-warmup IMAGE_ID=<id>  預熱 image cache"

.PHONY: packer-warmup
packer-warmup:
	@if [ -z "$(IMAGE_ID)" ]; then echo "Usage: make packer-warmup IMAGE_ID=<uuid>"; exit 1; fi
	@CLOUD=$${PACKER_OS_CLOUD:-ctfd}; \
	FLAVOR=$${PACKER_FLAVOR:-general.small}; \
	NETWORK=$${PACKER_NETWORK:-ctfd-network}; \
	echo "==> 設定 image 屬性（virtio + 無 video，加速 VM 啟動）..."; \
	openstack --os-cloud $$CLOUD image set $(IMAGE_ID) \
	  --property hw_vif_model=virtio \
	  --property hw_disk_bus=virtio \
	  --property hw_video_model=none \
	  --property os_type=linux \
	  --property hw_qemu_guest_agent=no \
	  --property hw_rng_model=virtio 2>/dev/null || true; \
	echo "==> 預熱 image cache（在所有 compute node 上快取 image）..."; \
	echo "    建立暫時 VM → 等待 ACTIVE → 刪除..."; \
	openstack --os-cloud $$CLOUD server create \
	  --image $(IMAGE_ID) \
	  --flavor $$FLAVOR \
	  --network $$NETWORK \
	  --wait \
	  _warmup-tmp > /dev/null; \
	openstack --os-cloud $$CLOUD server delete _warmup-tmp --wait 2>/dev/null || true; \
	echo "==> Image cache 預熱完成"

# ── Challenge as Code（題目註冊）─────────────────────────
# 需先設定 .env（CTFD_URL + CTFD_TOKEN）

.PHONY: register-challenges
register-challenges:
	python3 $(CURDIR)/scripts/register-challenges.py $(ARGS)

.PHONY: register-challenges-dry
register-challenges-dry:
	python3 $(CURDIR)/scripts/register-challenges.py --dry-run $(ARGS)

# 一鍵部署 VM 題目：Packer build → 自動更新 image_id → 註冊到 CTFd
# 用法：make deploy-challenge CHALLENGE=web-example
.PHONY: deploy-challenge
deploy-challenge:
	@if [ -z "$(CHALLENGE)" ]; then echo "Usage: make deploy-challenge CHALLENGE=<name>"; exit 1; fi
	@bash $(CURDIR)/scripts/deploy-challenge.sh $(CHALLENGE)

# ── Kolla-Ansible config（OpenStack 層設定）────────────────
# kolla-config/ 目錄下的檔案會同步到 /etc/kolla/config/
# 修改後執行對應的 reconfigure target 套用

KOLLA_CONFIG_SRC := $(CURDIR)/kolla-config
KOLLA_CONFIG_DST := /etc/kolla/config
KOLLA_INVENTORY  ?= $(HOME)/multinode

.PHONY: kolla-sync
kolla-sync:
	@echo "==> 同步 kolla-config/ → $(KOLLA_CONFIG_DST)/"
	sudo rsync -av --checksum $(KOLLA_CONFIG_SRC)/ $(KOLLA_CONFIG_DST)/
	@echo "==> 同步完成。請執行 kolla-ansible reconfigure 套用變更"

.PHONY: kolla-reconfigure-nova
kolla-reconfigure-nova: kolla-sync
	kolla-ansible reconfigure -i $(KOLLA_INVENTORY) -t nova

# ── 說明 ──────────────────────────────────────────────────

.PHONY: help
help:
	@echo "ctfd-openstack IaC 管理指令"
	@echo ""
	@echo "多環境支援：加 ENV=<name> 使用 environments/<name>/ 的設定"
	@echo "  例如：make deploy-platform ENV=lab50"
	@echo ""
	@echo "  make plan-platform / deploy-platform / destroy-platform / output-platform"
	@echo "  make plan-ctfd     / deploy-ctfd     / destroy-ctfd     / output-ctfd"
	@echo "  make plan-chell    / deploy-chell    / destroy-chell    / output-chell"
	@echo ""
	@echo "  make deploy-chell      建立 k3s 叢集 + 自動執行 ansible"
	@echo "  make infra-chell       只建立 k3s infra（跳過 ansible）"
	@echo ""
	@echo "  make ansible           重新執行完整 ansible（infra 已存在時）"
	@echo "  make ansible-k3s       只執行 k3s 相關 ansible tasks"
	@echo ""
	@echo "  make packer-init                        初始化 Packer plugins"
	@echo "  make packer-validate CHALLENGE=<name>   驗證題目 Packer 設定"
	@echo "  make packer-build CHALLENGE=<name>      建立題目 snapshot image"
	@echo ""
	@echo "  make register-challenges                註冊所有題目到 CTFd"
	@echo "  make register-challenges-dry             預覽（不實際呼叫 API）"
	@echo "  make deploy-challenge CHALLENGE=<name>  Packer build + 註冊"
	@echo ""
	@echo "  make kolla-sync                         同步 kolla-config/ 到 /etc/kolla/config/"
	@echo "  make kolla-reconfigure-nova              同步 + reconfigure Nova"
	@echo ""
	@echo "環境變數："
	@echo "  ENV=<name>             環境名稱（如 lab15, lab50）"
	@echo "  AUTO_APPROVE=true      tofu apply 不問確認"
	@echo "  VAULT_PASS_FILE=PATH   ansible vault 密碼檔路徑"
	@echo "  CHALLENGE=<name>       Packer 題目名稱（如 web-example）"
	@echo "  CTFD_URL=<url>         CTFd 位址（或寫在 .env）"
	@echo "  CTFD_TOKEN=<token>     CTFd API Token（或寫在 .env）"
	@echo "  PACKER_OS_CLOUD=<name> Packer warmup 用的 cloud entry（預設 ctfd）"
	@echo "  PACKER_FLAVOR=<name>   Packer warmup 用的 flavor（預設 general.small）"
	@echo "  PACKER_NETWORK=<name>  Packer warmup 用的 network（預設 ctfd-network）"
