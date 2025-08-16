# Homelab Komodo Infrastructure

Automated deployment of [Komodo](https://github.com/mbecker20/komodo) orchestration platform for homelab management using Ansible.

## Overview

This project provides Infrastructure as Code (IaC) for deploying and managing a distributed Komodo infrastructure across multiple servers. Komodo acts as a centralized control plane for managing Docker containers, services, and deployments across your homelab.

### Architecture

- **Komodo Core**: Central control plane with web UI, API, and MongoDB database
- **Komodo Periphery**: Worker nodes that execute deployments and manage containers
- **1Password Integration**: Secure secret management for all credentials
- **Tailscale VPN**: Secure networking between all nodes

## Quick Start

### Prerequisites

**macOS (recommended):**
```bash
# Install all dependencies with Homebrew
brew bundle
```

**Manual installation:**
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) with collections
- [1Password CLI](https://developer.1password.com/docs/cli/get-started/)
- SSH access to target servers

### 1. Setup Dependencies

```bash
# Install Ansible roles and collections
./scripts/setup-ansible.sh
```

### 2. Configure Infrastructure

```bash
# Copy and edit inventory
cp ansible/inventory/all.yml.example ansible/inventory/all.yml
# Edit all.yml with your server details
```

### 3. Authenticate to 1Password

**Local development:**
```bash
op signin
```

**CI/CD environments:**
```bash
export OP_SERVICE_ACCOUNT_TOKEN="your-token"
```

### 4. Deploy Infrastructure

**Bootstrap all servers:**
```bash
./scripts/deploy.sh bootstrap
```

**Deploy Komodo Core:**
```bash
./scripts/deploy.sh core
```

**Generate API Keys (Manual Step):**
1. Access Komodo Core web UI (see deployment output for URL)
2. Login via OIDC or add local user by setting KOMODO_DISABLE_USER_REGISTRATION to false temporarily
3. Generate API key/secret pair with appropriate permissions
4. Store in 1Password item 'Komodo' with fields 'komodo_api_key' and 'komodo_api_secret'

**Deploy Periphery Nodes:**
```bash
./scripts/deploy.sh periphery
```

### 5. Verify Deployment

```bash
./scripts/deploy.sh status
```

## Project Structure

```
├── ansible/
│   ├── inventory/all.yml   # Single consolidated configuration file
│   ├── playbooks/          # Ansible playbooks
│   └── roles/komodo/       # Custom Komodo deployment role
├── docs/                   # Documentation
├── scripts/               # Deployment scripts
└── compose/              # Manual compose files (for reference)
```

## Configuration

### Inventory Configuration

Define your servers in `ansible/inventory/all.yml`:

```yaml
all:
  children:
    komodo:
      vars:
        ansible_user: root
        komodo_core_url: "http://{{ hostvars[groups['core'][0]]['ansible_host'] }}:9120"
        # All Komodo configuration consolidated here
        
      children:
        core:             # Central control plane (one server)
          hosts:
            main-server:
              ansible_host: "main-server.your-tailnet.ts.net"
              node_site: home
              
        periphery:        # Worker nodes (multiple servers)  
          hosts:
            home-server:
              ansible_host: "main-server.your-tailnet.ts.net"
              node_site: home
              node_stacks: [servarr, monitoring]
              server_address: "https://host.docker.internal:8120"  # Same-host config
              
            worker-1:
              ansible_host: "worker-1.your-tailnet.ts.net"
              node_site: remote
              node_stacks: [uptime-kuma]
              generate_server_passkey: true  # Auto-generated passkey
```

### 1Password Setup

Required 1Password items in the 'Homelab' vault:

- **Komodo**: Core configuration secrets
- **ConnectServer**: 1Password Connect credentials (for future komodo-op integration)
- **Tailscale**: VPN authentication

See [docs/1password-setup.md](docs/1password-setup.md) for detailed field requirements.

## Commands

| Command | Description |
|---------|-------------|
| `./scripts/deploy.sh bootstrap` | Install Docker and Tailscale on all servers |
| `./scripts/deploy.sh core` | Deploy Komodo Core (MongoDB + API + UI) |
| `./scripts/deploy.sh periphery` | Deploy Komodo Periphery workers |
| `./scripts/deploy.sh periphery-update` | Update periphery nodes to latest version |
| `./scripts/deploy.sh periphery-update-version VERSION` | Update periphery to specific version |
| `./scripts/deploy.sh periphery-uninstall` | Remove periphery services |
| `./scripts/deploy.sh check` | Test connectivity to all servers |
| `./scripts/deploy.sh status` | Check health of all Komodo services |
| `./scripts/deploy.sh full` | Complete deployment (bootstrap + core) |

### Command Options

```bash
# Target specific servers
./scripts/deploy.sh bootstrap -l worker-1,worker-2

# Verbose output
./scripts/deploy.sh core -v

# Use different inventory
./scripts/deploy.sh bootstrap -i inventory/test.yml

# Update periphery to specific version
./scripts/deploy.sh periphery-update-version v1.18.4

# Remove periphery services
./scripts/deploy.sh periphery-uninstall
```

## Adding New Servers

1. **Add to inventory**: Edit `ansible/inventory/all.yml`
2. **Bootstrap server**: `./scripts/deploy.sh bootstrap -l new-server`  
3. **Deploy periphery**: `./scripts/deploy.sh periphery -l new-server`
4. **Verify**: Check status and configure stacks

See [docs/new-server-setup.md](docs/new-server-setup.md) for detailed instructions.

## Post-Deployment

### 1. Access Komodo UI

The web interface will be available at `http://your-core-server:9120`

### 2. Configure Authentication

- OIDC is pre-configured (check your 1Password settings)
- Local authentication is enabled as backup

### 3. Set Up Stack Management

- Connect your [homelab-stacks](https://github.com/mbecker20/komodo-stacks) repository
- Configure stack deployments through the UI
- Set up automated builds and deployments

### 4. Optional: komodo-op Integration

For enhanced 1Password integration:
1. Deploy 1Password Connect server
2. Configure komodo-op service
3. Sync secrets automatically

## Troubleshooting

### Common Issues

**"connect_host and connect_token are required together"**
- This error occurs if you have Connect variables in group_vars/all.yml
- The template-based approach should prevent this

**"Authentication failed" with 1Password**
- Verify: `op account list`
- Re-authenticate: `op signin`
- For CI/CD: Set `OP_SERVICE_ACCOUNT_TOKEN`

**Periphery deployment fails**
- Ensure API keys are generated in Core UI first
- Verify API keys are stored correctly in 1Password
- Check Core is healthy: `./scripts/deploy.sh status`

**SSH connection failures**
- Verify Tailscale is running on all nodes
- Check SSH key authentication
- Confirm hostnames in inventory match Tailscale names

### Logs

```bash
# Komodo Core logs
docker logs komodo-core-komodo-1

# Komodo Periphery logs (on periphery nodes)  
sudo -u komodo journalctl --user -u periphery -f

# MongoDB logs
docker logs komodo-core-mongo-1
```

## Development

### Testing Changes

```bash
# Test against specific servers
./scripts/deploy.sh bootstrap -l test-server

# Dry run (check mode)
ansible-playbook -i inventory/all.yml playbooks/bootstrap.yml --check
```

## Related Projects

- [Komodo](https://github.com/moghtech/komodo) - The orchestration platform