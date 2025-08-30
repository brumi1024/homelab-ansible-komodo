# Komodo Configuration Reference

This document provides a reference for all configuration variables in the Komodo homelab infrastructure.

## Configuration Architecture

All configuration has been centralized in **one single file** following the **single source of truth** principle:

- **Everything**: `inventory/all.yml` - All configuration, secrets, and host definitions in one place
- **Role Defaults**: `roles/*/defaults/main.yml` - Only role-internal behavior settings

## Core Variables

All variables are now defined in `inventory/all.yml` at the `all.vars` level.

### Network & Connection
| Variable | Default | Description |
|----------|---------|-------------|
| `ansible_user` | `root` | SSH user for Ansible connections |
| `ansible_ssh_private_key_file` | `~/.ssh/id_rsa` | SSH private key path |
| `tailnet` | `{{ lookup('community.general.onepassword', 'Network', field='tailnet', vault='Homelab Ansible') }}` | Tailscale network name (in `komodo.vars`) |

### Komodo Core Settings
| Variable | Default | Description |
|----------|---------|-------------|
| `komodo_install_dir` | `/opt/komodo` | Installation directory for Komodo Core |
| `komodo_port` | `9120` | **Core web interface port** |
| `komodo_mongo_port` | `27017` | MongoDB port |
| `komodo_mongo_cache_size_gb` | `2` | MongoDB cache size in GB |

### Komodo Periphery Settings
| Variable | Default | Description |
|----------|---------|-------------|
| `komodo_periphery_port` | `8120` | **Periphery agent port** |
| `komodo_periphery_version` | `latest` | Periphery Docker image tag |
| `komodo_user` | `komodo` | System user for periphery service |
| `komodo_group` | `komodo` | System group for periphery service |
| `komodo_bind_ip` | `0.0.0.0` | IP address for periphery to bind to |
| `komodo_bind_port` | `{{ komodo_periphery_port }}` | Port for periphery (bpbradley.komodo role) |
| `komodo_allowed_ips` | `[]` | List of allowed IPs (empty = allow all) |
| `komodo_secrets` | `[]` | List of secrets for periphery |
| `komodo_periphery_root_directory` | `/etc/komodo` | Periphery configuration directory |
| `enable_server_management` | `true` | Allow automatic server creation/updates |

### Computed URLs
| Variable | Value | Description |
|----------|-------|-------------|
| `komodo_core_url` | `http://{{ hostvars[groups['core'][0]]['ansible_host'] }}:{{ komodo_port }}` | Full URL to Core API |
| `komodo_periphery_url_pattern` | `https://{host}:{{ komodo_periphery_port }}` | URL pattern for periphery connections |

### Authentication Settings
| Variable | Default | Description |
|----------|---------|-------------|
| `komodo_auth_base_url` | `{{ komodo_core_url }}` | Base URL for auth operations |
| `komodo_auth_admin_username` | `{{ vault_komodo_admin_username }}` | Admin username |
| `komodo_auth_admin_password` | `{{ vault_komodo_admin_password }}` | Admin password |
| `komodo_auth_service_user` | `komodo-automation` | Service user name |
| `komodo_auth_service_user_description` | `Service user for automated deployments and API access` | Service user description |
| `komodo_auth_api_key_name` | `deployment-api-key` | API key name |

## Host-Specific Variables

These are defined per-host in `inventory/all.yml`:

### Required Host Variables
| Variable | Description | Example |
|----------|-------------|---------|
| `ansible_host` | Hostname or IP for SSH connection | `docker-test.{{ tailnet }}` |
| `node_site` | Site/location identifier | `home`, `sequoia` |

### Optional Host Variables
| Variable | Description | Example |
|----------|-------------|---------|
| `node_stacks` | List of Docker stacks for this node | `[servarr, homepage]` |
| `server_address` | Periphery server address override | `https://{{ ansible_host }}:{{ komodo_periphery_port }}` |
| `generate_server_passkey` | Auto-generate passkey for this periphery | `true` |
| `komodo_role` | Role for this host | `core` |

## Secret Variables

Defined in `group_vars/all/secrets.yml` using 1Password lookups:

| Variable | 1Password Field | Description |
|----------|-----------------|-------------|
| `vault_tailnet` | Network.tailnet | Tailscale network name |
| `vault_komodo_admin_username` | Komodo.username | Admin username |
| `vault_komodo_admin_password` | Komodo.password | Admin password |
| `komodo_core_api_key` | Komodo.komodo_api_key | API key for Core |
| `komodo_core_api_secret` | Komodo.komodo_api_secret | API secret for Core |

## Port Reference

| Service | Port | Variable | Used For |
|---------|------|----------|----------|
| Komodo Core | `9120` | `komodo_port` | Web UI, API |
| Komodo Periphery | `8120` | `komodo_periphery_port` | Agent communication |
| MongoDB | `27017` | `komodo_mongo_port` | Database |

## Variable Precedence

Variables are resolved in this simplified order:

1. **Host-specific** (inventory/all.yml per-host) - highest precedence
2. **Global** (inventory/all.yml `all.vars`) - medium precedence
3. **Role defaults** (roles/*/defaults/main.yml) - lowest precedence

## Customization Guide

### Changing Configuration
All configuration is in `inventory/all.yml`. To change settings:

```yaml
# inventory/all.yml
all:
  vars:
    komodo_port: 9130                    # New core port
    komodo_periphery_port: 8130          # New periphery port
```

### Adding New Hosts
Add to the `children` section:
```yaml
periphery:
  hosts:
    new-server:
      ansible_host: "new-host.{{ tailnet }}"
      node_site: remote
      node_stacks: [monitoring]
```

### Adding Secrets
Add 1Password lookups to the `all.vars` section:
```yaml
all:
  vars:
    new_secret: "{{ lookup('community.general.onepassword', 'Item', field='field', vault='Vault') }}"
```

## Troubleshooting

### Common Issues

1. **Port conflicts**: Check that `komodo_port` and `komodo_periphery_port` don't conflict
2. **1Password lookups failing**: Verify 1Password CLI is configured and vault/item names match
3. **Host resolution**: Ensure `tailnet` variable resolves correctly for your Tailscale setup

### Validation Commands

```bash
# Check variable resolution
ansible-inventory -i inventory/all.yml --host hostname

# Test 1Password lookups
ansible localhost -m debug -a "var=vault_tailnet"

# Validate syntax
ansible-playbook --syntax-check -i inventory/all.yml site.yml
```

## Migration Notes

This configuration structure represents the **ultimate simplification** - everything moved from scattered `group_vars/` files into a single `inventory/all.yml`. All hardcoded `8120` and `9120` references have been replaced with variable references for consistency.

**Previous structure** (complex):
```
group_vars/all/main.yml     # Global config
group_vars/all/secrets.yml  # 1Password lookups
group_vars/core/main.yml    # Core-specific
group_vars/periphery/main.yml # Periphery-specific
inventory/all.yml           # Just hosts
```

**Current structure** (simple):
```
inventory/all.yml           # Everything in one place
roles/*/defaults/main.yml   # Only role-internal settings
```