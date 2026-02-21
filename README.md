# ctfd-openstack

Deploy [CTFd](https://github.com/CTFd/CTFd) with per-player dynamic VM instances on OpenStack, powered by [chall-manager](https://github.com/ctfer-io/chall-manager) and Pulumi.

## Architecture

```
OpenStack
├── platform/          OpenTofu — shared infra (images, flavors, network, project)
├── ctfd/              OpenTofu — CTFd VM + network + floating IP
└── ansible/           Ansible  — CTFd app + chall-manager + per-player scenario
    ├── roles/ctfd/         CTFd (Docker)
    ├── roles/chall-manager/  chall-manager + etcd + local OCI registry
    └── scenarios/openstack-vm/  Pulumi Python — spawns a VM per player
```

**Deployment order:** `platform` → `ctfd` → `ansible`

## Prerequisites

| Tool | Version |
|------|---------|
| OpenTofu | ≥ 1.11 |
| Ansible | ≥ 2.14 |
| Python | ≥ 3.10 |
| `~/.config/openstack/clouds.yaml` | configured |

## Quick Start

### 1. Clone & prepare local config files

```bash
# OpenStack credentials (ansible-vault encrypted)
cp ansible/group_vars/all/vault.yml.example \
   ansible/group_vars/all/vault.yml
$EDITOR ansible/group_vars/all/vault.yml      # fill real credentials
ansible-vault encrypt ansible/group_vars/all/vault.yml

# Inventory (real VM IP)
cp ansible/inventory/hosts.ini.example \
   ansible/inventory/hosts.ini
```

### 2. Deploy shared platform infra

```bash
cd platform
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars                      # set ctfd_deployer_password
tofu init && tofu apply
tofu output                                   # note: image_ids, external_network_id
```

### 3. Deploy CTFd VM

```bash
cd ../ctfd
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars                      # set image_id, external_network_id
tofu init && tofu apply
tofu output                                   # note: floating_ip, network_id
```

### 4. Prepare challenge config & run Ansible

```bash
cd ../ansible

# Fill UUIDs from tofu output + your real flag
cp group_vars/all/challenge.yml.example \
   group_vars/all/challenge.yml
$EDITOR group_vars/all/challenge.yml

# Update inventory with the CTFd VM floating IP
$EDITOR inventory/hosts.ini

# Deploy
ansible-playbook site.yml --ask-vault-pass
```

## Local Config Files (gitignored)

| File | Contents | Source |
|------|----------|--------|
| `ansible/group_vars/all/vault.yml` | OpenStack credentials | manual |
| `ansible/group_vars/all/challenge.yml` | Image/Network UUIDs, flag | `tofu output` |
| `ansible/inventory/hosts.ini` | CTFd VM IP, SSH key path | `ctfd tofu output floating_ip` |
| `ctfd/terraform.tfvars` | ctfd deployment config | manual (from platform output) |
| `platform/terraform.tfvars` | platform config + deployer password | manual |

## CTFd Plugin Setup

After `ansible-playbook` completes, configure the **chall-manager** plugin in CTFd:

| Field | Value |
|-------|-------|
| API URL | `http://127.0.0.1:8080` |
| Scenario (per-challenge) | `registry:5000/openstack-vm:latest` |

> **Note:** CTFd runs inside Docker. Use the Docker service name `registry:5000`, not `localhost:5000`.

## Variable Precedence (Ansible)

```
roles/defaults/main.yml   ← placeholder (committed)
group_vars/all/*.yml      ← real values (gitignored) ← overrides defaults
roles/vars/main.yml       ← fixed role config (committed, cannot be overridden)
```

## Dynamic Flag

Each player receives a unique flag derived from their `identity`:

```
CTF{variate_flag(identity, base_flag)}
```

Set `challenge_base_flag` in `ansible/group_vars/all/challenge.yml`.
