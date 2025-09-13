# Homelab Komodo Infrastructure

Infrastructure-as-code solution for deploying and managing Komodo-based homelab infrastructure using Ansible. This project automates the complete deployment of Komodo Core, Komodo Periphery nodes, secret management via 1Password Connect, and GitOps-driven application stacks.

## Overview

This repository deploys a distributed container orchestration platform with:

- **Komodo Core**: Central management server with web interface (port 9120)
- **Komodo Periphery**: Distributed agent nodes for executing deployments (port 8120)
- **Docker**: Container runtime on all infrastructure nodes
- **komodo-op**: Optional 1Password Connect integration for secret management
- **Application Stacks**: GitOps-driven application deployment from GitHub repositories

The infrastructure uses a hub-and-spoke architecture where Komodo Core acts as the central controller, coordinating deployments across multiple Periphery nodes connected via Tailscale VPN.

## Prerequisites

- **Ansible** 2.9+ with community.general collection
- **1Password CLI** (`op`) configured with appropriate vault access
- **SSH access** to all target servers with sudo privileges
- **Tailscale VPN** network configured across all nodes
- **Git repositories** for komodo-op stack and application definitions

## Quick Start

1. **Install dependencies**:
   ```bash
   make setup
   ```

2. **Verify connectivity**:
   ```bash
   make check
   ```

3. **Deploy complete infrastructure**:
   ```bash
   # Complete deployment (includes 1Password secret management)
   make deploy
   ```

4. **Access Komodo Core** at `https://your-komodo-host:9120`

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Komodo Core   │────│   Tailscale VPN  │────│ Komodo Periphery│
│   (Controller)  │    │                  │    │   (Agent Nodes) │
│   Port: 9120    │    │                  │    │   Port: 8120    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
    ┌────────┐             ┌─────────────┐         ┌───────────┐
    │MongoDB │             │  komodo-op  │         │Application│
    │27017   │             │ (Optional)  │         │  Stacks   │
    └────────┘             └─────────────┘         └───────────┘
```

### Host Groups

- **control**: Ansible control node (localhost)
- **core**: Komodo Core server with MongoDB
- **periphery**: Komodo Periphery agent nodes

## Make Targets Reference

### Setup and Dependencies

| Target | Description |
|--------|-------------|
| `make setup` | Install Ansible dependencies and collections |
| `make check` | Test SSH connectivity to all hosts |
| `make lint` | Run ansible-lint and yamllint code quality checks |

### Individual Deployment Steps

| Target | Description |
|--------|-------------|
| `make docker` | Install Docker on all infrastructure nodes |
| `make core` | Deploy Komodo Core server with MongoDB |
| `make auth` | Initialize authentication (admin user, API keys) |
| `make periphery` | Deploy Komodo Periphery agents to all nodes |

### Complete Deployment

| Target | Description |
|--------|-------------|
| `make deploy` | Complete deployment with 1Password integration |
| `make check-deploy` | Dry run deployment (check mode) |

### Secret Management & GitOps

| Target | Description |
|--------|-------------|
| `make komodo-op` | Deploy resource syncs and komodo-op stack for 1Password secret sync |
| `make app-syncs` | Verify and manage application resource syncs for GitOps |

### Upgrade & Management

| Target | Description |
|--------|-------------|
| `make upgrade` | Upgrade both Core and all Periphery nodes |
| `make core-upgrade` | Upgrade Komodo Core (pulls latest images) |
| `make periphery-upgrade` | Update all Periphery nodes to latest version |
| `make periphery-uninstall` | Remove Komodo Periphery from all nodes |

### Maintenance

| Target | Description |
|--------|-------------|
| `make status` | Check health status of all Komodo services |
| `make clean` | Clean up temporary files and caches |

### Advanced Options

| Target | Description |
|--------|-------------|
| `make run PLAYBOOK=<name>` | Run specific playbook with optional OPTS |

## Basic Operations

### Adding a New Server

1. **Update inventory** in `ansible/inventory/all.yml`:
   ```yaml
   periphery:
     hosts:
       existing-node:
         ansible_host: 100.x.x.x
       new-node:                    # Add new server
         ansible_host: 100.x.x.x    # Tailscale IP
   ```

2. **Deploy to new node**:
   ```bash
   make check                      # Verify connectivity
   make docker                     # Install Docker
   make periphery                  # Deploy Periphery agent
   ```

### Updating Komodo

All operations are **idempotent** - safe to run multiple times:

```bash
# Update Core server
make core-upgrade

# Update all Periphery nodes
make periphery-upgrade

# Update everything at once
make upgrade
```

**Note**: The Ansible playbooks are designed to be idempotent, meaning you can safely run them repeatedly without causing issues. They will only make changes when necessary.

### Deploying Applications

Applications are deployed via GitOps using resource syncs:

1. **Verify resource syncs** (optional - already created by `make komodo-op`):
   ```bash
   make app-syncs
   ```

2. **Applications auto-pull** from configured GitHub repositories but require manual deployment for safety

### Health Monitoring

```bash
# Check all services
make status

# Manual health check
curl -s http://your-komodo-host:9120
```

## Configuration

### Single Source of Truth

All configuration is centralized in `ansible/inventory/all.yml`:

- Host definitions and network settings
- Komodo Core and Periphery configuration
- Authentication credentials (via 1Password lookups)
- Git repository settings for komodo-op and app stacks
- Resource sync repositories (required for GitOps)

### Key Configuration Sections

```yaml
all:
  vars:
    # Network & Connection
    ansible_user: root
    tailnet: "{{ 1password_lookup }}"
    
    # Komodo Core Settings
    komodo_port: 9120
    komodo_mongo_port: 27017
    
    # Komodo Periphery Settings
    komodo_periphery_port: 8120
    
    # Resource Syncs Configuration (GitOps) - REQUIRED
    komodo_resource_syncs_repo: "brumi1024/komodo-resource-syncs"
    komodo_resource_syncs_branch: "main"
    komodo_resource_syncs_git_account: "brumi1024"

    # Secret Management
    enable_komodo_op: true  # Enable 1Password integration

    # Individual sync repositories (defined in komodo-resource-syncs repo)
    # app_stacks_repo: "brumi1024/komodo-app-stacks"  # Reference only
```

## Secret Management

The deployment includes 1Password integration by default (configured via `enable_komodo_op: true` in the inventory):

```bash
make deploy
```

This enables automatic secret synchronization from 1Password vaults. To deploy without komodo-op, you can override the setting:

```bash
# Deploy without secret management (if needed)
make run PLAYBOOK=site.yml OPTS="-e enable_komodo_op=false"
```

See [1Password Setup Guide](docs/1PASSWORD_SETUP.md) for detailed configuration requirements.

## GitOps Workflow

The infrastructure uses a centralized resource sync approach:

1. **komodo-resource-syncs**: Meta-sync repository at `brumi1024/komodo-resource-syncs`
   - Contains `syncs.toml` defining all resource syncs
   - Automatically creates and manages individual syncs
   - Single source of truth for GitOps configuration
   - Repository URLs are defined in this repo, not in local ansible inventory

2. **komodo-op-sync**: Infrastructure deployment (auto-deploy enabled)
   - Source: `brumi1024/deploy-komodo-op`
   - Provides 1Password Connect server
   - Syncs secrets from 1Password vaults
   - Creates environment variables in Komodo

3. **komodo-app-stacks**: Application deployments (manual deploy for safety)
   - Source: `brumi1024/komodo-app-stacks`
   - Auto-pulls latest definitions on changes
   - Requires manual deployment approval
   - Uses secrets synchronized via komodo-op

## Troubleshooting

### Common Issues

**Connection failures**:
```bash
make check  # Verify SSH connectivity
```

**Service not starting**:
```bash
make status  # Check service health
```

**1Password lookups failing**:
```bash
op account list  # Verify 1Password CLI authentication
```

**API Key Silent Failures (Critical)**:

If you're deploying to a fresh Komodo instance but have stale API keys in 1Password from a previous deployment, authentication setup will be silently skipped, causing failures in subsequent steps.

**Symptoms**: Subsequent playbooks fail with authentication errors despite auth playbook appearing to succeed.

**Solution**: Choose one of these approaches:

```bash
# Option 1: Use force recreate flag (recommended)
make auth OPTS="-e komodo_auth_force_recreate=true"

# Option 2: Delete entire Komodo item (will be recreated)
op item delete "Komodo" --vault "Homelab Ansible"

# Option 3: Remove just the API key field
op item edit "Komodo" --vault "Homelab Ansible" komodo_api_key=""
```

**Permission issues**:
```bash
# Ensure SSH user has sudo privileges
ansible all -i inventory/all.yml -m shell -a "sudo -l"
```

### Log Locations

- **Komodo Core**: `docker logs komodo-core`
- **Komodo Periphery**: `journalctl -u komodo-periphery`
- **Ansible logs**: Console output during playbook execution

## Development

### Code Quality

```bash
make lint  # Run ansible-lint and yamllint
```

### Testing Changes

```bash
make check-deploy  # Dry run to see what would change
```

## Repository Structure

```
├── Makefile                    # Main deployment commands
├── ansible/                    # Ansible configuration
│   ├── inventory/all.yml      # Single source of truth configuration
│   ├── playbooks/             # Deployment playbooks (01-07)
│   ├── roles/                 # Custom Ansible roles
│   │   ├── komodo/           # Komodo Core deployment
│   │   └── komodo_auth/      # Authentication management
│   ├── tasks/                # Shared task files
│   └── site.yml              # Master orchestration playbook
├── scripts/                   # Setup and utility scripts
└── docs/                      # Additional documentation
```