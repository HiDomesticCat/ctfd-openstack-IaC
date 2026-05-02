# Internal IaC wrapper for gamma4-lab spec/build separation (ADR-0008).
# Pulls public spec_to_provisioner.py + research-vm-base.pkr.hcl from
# gamma4-lab at a pinned ref; substitutes our lab's specific OpenStack
# config (ansible-vars.yaml); records resulting Glance UUID into
# built-uuids.yaml for cross-repo reference back to gamma4-lab.
#
# Usage:  source ansible-vars.yaml && make bake/lab-pwnkit-cve-2021-4034

GAMMA4_REPO ?= https://github.com/HiDomesticCat/ctfd-gamma4-lab.git
GAMMA4_REF  ?= main

WORK := /tmp/iac-bake-$(shell date +%s)

bake/%:
	@command -v packer    >/dev/null || { echo "ERROR: packer not on PATH"; exit 1; }
	@command -v openstack >/dev/null || { echo "ERROR: openstack CLI not on PATH"; exit 1; }
	@command -v jq        >/dev/null || { echo "ERROR: jq not on PATH"; exit 1; }
	@command -v python3   >/dev/null || { echo "ERROR: python3 not on PATH"; exit 1; }
	@test -n "$$OS_AUTH_URL" || { echo "ERROR: source ansible-vars.yaml first"; exit 1; }
	@mkdir -p $(WORK) ; cd $(WORK) ; \
	echo ">>> Cloning gamma4-lab @$(GAMMA4_REF)" ; \
	git clone --depth 50 -b $(GAMMA4_REF) $(GAMMA4_REPO) gamma4-lab >/dev/null ; \
	GAMMA4_SHA=$$(git -C gamma4-lab rev-parse HEAD) ; \
	echo ">>> Pinned at gamma4-lab@$$GAMMA4_SHA" ; \
	SPEC=gamma4-lab/catalog/components/$*/bake/vulnerability.spec.yaml ; \
	test -f $$SPEC || { echo "ERROR: $$SPEC missing - component not migrated to spec/build yet (e.g. lab-oracle stays on legacy packer.pkr.hcl)"; exit 1; } ; \
	echo ">>> Generating provisioner steps from spec" ; \
	cd gamma4-lab && uv run python bake_infrastructure/spec_to_provisioner.py \
	    catalog/components/$*/bake/vulnerability.spec.yaml \
	    --metadata-out $(WORK)/m.json --steps-out $(WORK)/s.json ; \
	OS_VER=$$(jq -r '.os_version' $(WORK)/m.json) ; \
	case "$$OS_VER" in \
	    "20.04") IMAGE_ID="$$BASE_IMAGE_UBUNTU_2004" ;; \
	    "22.04") IMAGE_ID="$$BASE_IMAGE_UBUNTU_2204" ;; \
	    *) echo "ERROR: unsupported os_version $$OS_VER"; exit 1 ;; \
	esac ; \
	test -n "$$IMAGE_ID" || { echo "ERROR: BASE_IMAGE for Ubuntu $$OS_VER is empty in ansible-vars.yaml"; exit 1; } ; \
	echo ">>> Pre-flight: required env vars" ; \
	for v in $$(jq -r '.required_env_vars[]' $(WORK)/m.json); do \
	    eval "test -n \"\$$$$v\"" || { echo "ERROR: $$v not set; export it before running make (suggestion: $$v=\$$(openssl rand -hex 16))"; exit 1; } ; \
	done ; \
	cd $(WORK)/gamma4-lab/bake_infrastructure && \
	echo ">>> packer init" && \
	packer init research-vm-base.pkr.hcl && \
	echo ">>> packer build (Ubuntu $$OS_VER, image $$IMAGE_ID)" && \
	packer build \
	    -var "spec_metadata_path=$(WORK)/m.json" \
	    -var "provisioner_steps_path=$(WORK)/s.json" \
	    -var "openstack_auth_url=$$OS_AUTH_URL" \
	    -var "openstack_username=$$OS_USERNAME" \
	    -var "openstack_password=$$OS_PASSWORD" \
	    -var "openstack_project_name=$$OS_PROJECT_NAME" \
	    -var "source_image_id=$$IMAGE_ID" \
	    -var "network_id=$$NETWORK_ID" \
	    research-vm-base.pkr.hcl ; \
	PREFIX=$$(jq -r '.image_name_prefix' $(WORK)/m.json) ; \
	NEW_UUID=$$(openstack image list --private --name "$$PREFIX-*" --sort-column Created_at --sort-desc -f value -c ID | head -n 1) ; \
	test -n "$$NEW_UUID" || { echo "ERROR: failed to locate fresh Glance image for $*"; exit 1; } ; \
	echo "" ; echo ">>> $* baked. Glance UUID: $$NEW_UUID" ; \
	mkdir -p $(CURDIR)/specs ; \
	cp $(WORK)/gamma4-lab/catalog/components/$*/bake/vulnerability.spec.yaml $(CURDIR)/specs/$*.yaml ; \
	cd $(CURDIR) && python3 scripts/update_built_uuids.py "$*" "$$NEW_UUID" "$$GAMMA4_SHA" built-uuids.yaml ; \
	rm -rf $(WORK) ; \
	echo ">>> Updated built-uuids.yaml + mirrored spec to specs/$*.yaml" ; \
	echo ">>> Next: cd $(CURDIR) && git add -A && git commit -m 'challenges/research: bake $* (gamma4-lab@$$GAMMA4_SHA)' && git push"
