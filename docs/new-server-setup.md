# Adding New Servers to Komodo Infrastructure

This guide walks through the complete process of adding new servers to your Komodo infrastructure.

## Overview

The process involves:
1. **Server Preparation**: Ensure server meets requirements
2. **Inventory Configuration**: Add server to Ansible inventory
3. **Role Selection**: Choose between Core and Periphery
4. **Deployment**: Run appropriate bootstrap and deployment commands
5. **Verification**: Confirm successful deployment and connectivity

## Prerequisites

### Server Requirements

**Minimum specifications:**
- **OS**: Ubuntu 20.04+ / Debian 11+ / RHEL 8+ / CentOS Stream 8+
- **RAM**: 2GB (4GB+ recommended for Core servers)
- **Storage**: 20GB (50GB+ recommended for Core servers)
- **Network**: Internet access and connectivity to existing infrastructure

**Required access:**
- SSH access with sudo/root privileges
- Firewall allows necessary ports (see Port Requirements below)

### Port Requirements

**Komodo Core servers need:**
- `9120`: Komodo Core API and Web UI
- `27017`: MongoDB (internal, can be firewalled)
- `22`: SSH access

**Komodo Periphery servers need:**
- `9001`: Komodo Periphery API
- `22`: SSH access
- Docker port ranges (for deployed services)

**All servers need:**
- Tailscale VPN connectivity (UDP 41641)

## Step-by-Step Setup

### 1. Server Preparation

**Install minimal requirements:**
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y curl openssh-server

# RHEL/CentOS
sudo dnf install -y curl openssh-server
```

**Configure SSH (if needed):**
```bash
# Enable SSH service
sudo systemctl enable --now ssh

# Add your public key
mkdir -p ~/.ssh
echo "your-public-key-here" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 2. Add Server to Inventory

Edit `ansible/inventory/hosts.yml` and add your server:

**For a new Komodo Core server:**
```yaml
komodo_core:
  hosts:
    new-core-server:
      ansible_host: "new-core.your-tailnet.ts.net"  # or IP address
      node_site: datacenter  # logical grouping
      komodo_role: core
```

**For a new Komodo Periphery server:**
```yaml
komodo_periphery:
  hosts:
    new-worker-server:
      ansible_host: "new-worker.your-tailnet.ts.net"  # or IP address
      node_site: home  # logical grouping
      node_type: worker  # optional: server type
      node_stacks:  # services this server will run
        - homepage
        - monitoring
        - your-custom-stack
```

### 3. Role Selection Guide

**Choose Komodo Core when:**
- You need a new control plane (backup/HA)
- This is your first/primary server
- You want regional separation of control planes

**Choose Komodo Periphery when:**
- You want to run workloads/services
- You have limited resources (Core requires more RAM)
- You want to distribute services geographically

**Typical setup patterns:**
- **Small homelab**: 1 Core server, 2-3 Periphery servers
- **Multi-site**: 1 Core per site, multiple Periphery per site
- **High availability**: 2 Core servers (active/backup), many Periphery

### 4. Test Connectivity

Before deployment, verify Ansible can reach the server:

```bash
# Test basic connectivity
./scripts/deploy.sh check -l new-server-name

# Test with verbose output
ansible new-server-name -i ansible/inventory/hosts.yml -m ping -v
```

**Common connectivity issues:**
- **DNS resolution**: Use IP address instead of hostname
- **SSH key**: Ensure your SSH key is added to the server
- **Firewall**: Verify SSH port (22) is open
- **User permissions**: Ensure ansible_user has sudo access

### 5. Bootstrap the Server

Bootstrap installs Docker and Tailscale:

```bash
# Bootstrap single server
./scripts/deploy.sh bootstrap -l new-server-name

# Bootstrap with verbose output (for troubleshooting)
./scripts/deploy.sh bootstrap -l new-server-name -v
```

**What bootstrap does:**
1. Installs Docker CE with compose plugin
2. Adds ansible_user to docker group
3. Configures Docker daemon with logging
4. Installs and configures Tailscale VPN
5. Creates bootstrap completion marker

**Bootstrap verification:**
```bash
# Verify Docker is running
ansible new-server-name -i ansible/inventory/hosts.yml -m shell -a "docker --version"

# Verify Tailscale is connected
ansible new-server-name -i ansible/inventory/hosts.yml -m shell -a "tailscale status"
```

### 6. Deploy Based on Role

#### For Komodo Core Servers

**Deploy Core:**
```bash
./scripts/deploy.sh core -l new-core-server
```

**What Core deployment does:**
1. Creates installation directory (`/opt/komodo`)
2. Deploys MongoDB container
3. Generates environment configuration with 1Password secrets
4. Deploys Komodo Core container
5. Waits for services to be healthy
6. Displays access information

**Post-Core deployment:**
1. Access web UI at `http://server-ip:9120`
2. Configure OIDC authentication (if not already done)
3. Generate API keys for Periphery nodes (if needed)

#### For Komodo Periphery Servers

**Ensure prerequisites:**
- Komodo Core is deployed and healthy
- API keys are generated and stored in 1Password

**Deploy Periphery:**
```bash
./scripts/deploy.sh periphery -l new-periphery-server
```

**What Periphery deployment does:**
1. Verifies Core is accessible
2. Retrieves API credentials from 1Password
3. Installs Komodo Periphery via systemd service
4. Generates unique server passkey
5. Registers with Komodo Core automatically

### 7. Verify Deployment

**Check service status:**
```bash
./scripts/deploy.sh status
```

**Manual verification:**

**For Core servers:**
```bash
# Check Core health endpoint
curl http://server-ip:9120/health

# Check MongoDB
docker ps | grep mongo

# Check logs
docker logs komodo-core-komodo-1
```

**For Periphery servers:**
```bash
# Check Periphery service
sudo systemctl status komodo

# Check Periphery health
curl http://server-ip:9001/health

# Check logs
journalctl -u komodo -f
```

### 8. Configure Services (Periphery Only)

After successful Periphery deployment:

1. **Access Komodo Core UI**
2. **Navigate to Servers**: Should see new server listed
3. **Configure Stacks**: Assign stacks to the new server
4. **Deploy Services**: Use the UI to deploy your services

## Advanced Configuration

### Custom Variables

Add server-specific variables to inventory:

```yaml
new-server:
  ansible_host: "192.168.1.100"
  # Custom Docker configuration
  docker_daemon_options:
    log-driver: "json-file"
    log-opts:
      max-size: "50m"
      max-file: "5"
  # Custom resource limits
  mongo_cache_size_gb: 0.5
  # Custom periphery secrets
  komodo_periphery_secrets:
    - name: "CUSTOM_SECRET"
      value: "secret-value"
```

### Network Configuration

**Using IP addresses instead of hostnames:**
```yaml
new-server:
  ansible_host: "192.168.1.100"  # Direct IP
  node_site: home
```

**Custom SSH configuration:**
```yaml
new-server:
  ansible_host: "server.domain.com"
  ansible_user: "deploy"  # Different user
  ansible_ssh_private_key_file: "~/.ssh/custom_key"
  ansible_port: 2222  # Custom SSH port
```

### Site-Specific Configuration

Group servers by site in `group_vars/`:

**Create `ansible/group_vars/datacenter.yml`:**
```yaml
---
# Datacenter-specific settings
site_config:
  datacenter:
    nas_ip: "10.0.1.100"
    config_dir: "/data/docker-config"
    repo_dir: "/data/repos"
    data_dir: "/data/app-data"

# Custom Docker settings for datacenter
docker_daemon_options:
  storage-driver: "overlay2"
  log-driver: "syslog"
  log-opts:
    syslog-address: "tcp://10.0.1.200:514"
```

**Reference in inventory:**
```yaml
datacenter_servers:
  hosts:
    dc-server-1:
      ansible_host: "10.0.1.10"
      node_site: datacenter
```

## Troubleshooting

### Common Issues

**Bootstrap fails with "Docker installation failed"**
```bash
# Check if server can reach Docker repos
ansible server -m shell -a "curl -fsSL https://download.docker.com/linux/ubuntu/gpg"

# Manual Docker installation
ssh user@server
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

**Tailscale authentication fails**
```bash
# Check if Tailscale auth key is in 1Password
op item get "Tailscale" --vault "Homelab" --fields label=tailscale_authkey

# Manual Tailscale setup
ssh user@server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey YOUR_AUTH_KEY
```

**Periphery can't connect to Core**
```bash
# Test connectivity from Periphery to Core
ansible periphery-server -m uri -a "url=http://core-server:9120/health method=GET"

# Check if API keys are correct
op item get "Komodo" --vault "Homelab" --fields label=komodo_api_key,label=komodo_api_secret
```

**1Password lookups fail**
```bash
# Verify 1Password authentication
op account list

# Test lookup manually
op item get "Komodo" --vault "Homelab" --fields label=komodo_passkey
```

### Debugging Steps

1. **Enable verbose Ansible output**: Add `-v`, `-vv`, or `-vvv`
2. **Check specific task**: Use `--start-at-task "Task Name"`
3. **Run individual commands**: Use `ansible server -m shell -a "command"`
4. **Check logs**: Server logs, Docker logs, systemd logs
5. **Verify networking**: Ping, telnet, curl between servers

### Recovery Procedures

**Re-bootstrap a server:**
```bash
# Remove bootstrap marker
ansible server -m file -a "path=/opt/.bootstrap_complete state=absent"

# Re-run bootstrap
./scripts/deploy.sh bootstrap -l server
```

**Reset Komodo installation:**
```bash
# Stop and remove containers
ansible server -m shell -a "cd /opt/komodo && docker compose down -v"

# Remove installation
ansible server -m file -a "path=/opt/komodo state=absent"

# Re-deploy
./scripts/deploy.sh core -l server  # or periphery
```

## Best Practices

1. **Test connectivity** before starting deployment
2. **Use meaningful server names** in inventory
3. **Group servers by site** for easier management
4. **Keep inventory backed up** in version control
5. **Document custom configurations** in comments
6. **Monitor resource usage** after deployment
7. **Regular updates** via bootstrap playbook
8. **Backup Core servers** regularly (especially MongoDB)

## Next Steps

After successful server addition:

1. **Configure monitoring** for the new server
2. **Set up backup procedures** if it's a Core server
3. **Deploy your services** via Komodo UI
4. **Update documentation** with any site-specific notes
5. **Test failover scenarios** if this adds redundancy