# ctfd-openstack Makefile
# 管理 platform / ctfd / chell 三層 IaC + Ansible
#
# 常用流程：
#   make plan-chell       # 驗證 k3s 叢集 plan
#   make deploy-chell     # 建立 k3s 叢集 + 執行 ansible
#   make destroy-chell    # 刪除 k3s 叢集

CHELL_DIR  := $(CURDIR)/chell
CTF_DIR    := $(CURDIR)/ctfd
PLAT_DIR   := $(CURDIR)/platform
SHELL      := /usr/bin/env bash

# ── chell 層 ──────────────────────────────────────────────

.PHONY: plan-chell
plan-chell:
	cd $(CHELL_DIR) && tofu plan

.PHONY: deploy-chell
deploy-chell:
	@bash $(CHELL_DIR)/deploy.sh

# 全自動模式（CI / 測試用）：tofu 不問確認、vault 從檔案讀取
# 用法：make deploy-chell-auto VAULT_PASS_FILE=~/.vault_pass
.PHONY: deploy-chell-auto
deploy-chell-auto:
	AUTO_APPROVE=true VAULT_PASS_FILE=$(VAULT_PASS_FILE) bash $(CHELL_DIR)/deploy.sh

# 只跑 tofu apply，不跑 ansible（用於先建好 infra 再手動 ansible）
.PHONY: infra-chell
infra-chell:
	cd $(CHELL_DIR) && tofu apply

.PHONY: destroy-chell
destroy-chell:
	cd $(CHELL_DIR) && tofu destroy

.PHONY: output-chell
output-chell:
	cd $(CHELL_DIR) && tofu output

# ── ctfd 層 ───────────────────────────────────────────────

.PHONY: plan-ctfd
plan-ctfd:
	cd $(CTF_DIR) && tofu plan

.PHONY: deploy-ctfd
deploy-ctfd:
	cd $(CTF_DIR) && tofu apply

.PHONY: destroy-ctfd
destroy-ctfd:
	cd $(CTF_DIR) && tofu destroy

# ── platform 層 ───────────────────────────────────────────

.PHONY: plan-platform
plan-platform:
	cd $(PLAT_DIR) && tofu plan

.PHONY: deploy-platform
deploy-platform:
	cd $(PLAT_DIR) && tofu apply

# ── Ansible only（infra 已存在時快速重跑） ────────────────

.PHONY: ansible
ansible:
	@WORKER_IPS_JSON=$$(cd $(CHELL_DIR) && tofu output -json worker_floating_ips 2>/dev/null || echo '[]'); \
	cd $(CURDIR)/ansible && \
	ansible-playbook site.yml \
	  -i inventory/hosts.ini \
	  -i inventory/k3s_hosts.ini \
	  --extra-vars "{\"k3s_worker_ips\": $$WORKER_IPS_JSON}" \
	  --ask-vault-pass

.PHONY: ansible-k3s
ansible-k3s:
	@WORKER_IPS_JSON=$$(cd $(CHELL_DIR) && tofu output -json worker_floating_ips); \
	cd $(CURDIR)/ansible && \
	ansible-playbook site.yml \
	  -i inventory/k3s_hosts.ini \
	  --tags k3s \
	  --extra-vars "{\"k3s_worker_ips\": $$WORKER_IPS_JSON}" \
	  --ask-vault-pass

# ── 說明 ──────────────────────────────────────────────────

.PHONY: help
help:
	@echo "ctfd-openstack IaC 管理指令"
	@echo ""
	@echo "  make plan-chell        驗證 k3s 叢集 plan（不實際建立）"
	@echo "  make deploy-chell      建立 k3s 叢集 + 自動執行 ansible"
	@echo "  make infra-chell       只建立 k3s infra（跳過 ansible）"
	@echo "  make destroy-chell     刪除 k3s 叢集"
	@echo "  make output-chell      顯示 k3s 叢集 outputs（IP 等）"
	@echo ""
	@echo "  make ansible           重新執行完整 ansible（infra 已存在時）"
	@echo "  make ansible-k3s       只執行 k3s 相關 ansible tasks"
	@echo ""
	@echo "  make plan-ctfd / deploy-ctfd / destroy-ctfd"
	@echo "  make plan-platform / deploy-platform"
	@echo ""
	@echo "環境變數："
	@echo "  AUTO_APPROVE=true      tofu apply 不問確認"
	@echo "  VAULT_PASS_FILE=PATH   ansible vault 密碼檔路徑"
