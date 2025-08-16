# Komodo Periphery Management

This guide explains how to deploy, update, and manage Komodo Periphery instances using the `bpbradley.komodo` Ansible role.

## Prerequisites

1. **Komodo Core deployed** - Run `./scripts/deploy.sh core` first
2. **API Keys generated** - Create API keys in Komodo Core UI and store in 1Password
3. **1Password CLI authenticated** - Run `op signin` to authenticate
4. **Nodes bootstrapped** - Run `./scripts/deploy.sh bootstrap` on target hosts

## Periphery Configuration

### Same-Host Periphery (home-server)

The `home-server` periphery runs on the same host as Komodo Core:

```yaml
home-server:
  ansible_host: "docker-test"
  server_address: "https://host.docker.internal:8120"
  komodo_bind_ip: "0.0.0.0"
```

- Uses `host.docker.internal` to communicate with Core running in Docker
- Uses HTTPS for secure connection
- No passkey needed (local communication)
- Listens on all interfaces for systemd service

### Remote Periphery (sequoia-server)

The `sequoia-server` periphery runs on a separate host:

```yaml
sequoia-server:
  ansible_host: "docker-test2"
  generate_server_passkey: true
  server_address: "https://{{ ansible_host }}:8120"
```

- Automatically generates and rotates passkeys
- Uses Tailscale hostname for reliable cross-site connectivity
- Registers itself with Komodo Core via API

## Commands

### Install Peripheries

Deploy all periphery instances:

```bash
./scripts/deploy.sh periphery
```

Deploy specific periphery:

```bash
./scripts/deploy.sh periphery -l home-server
./scripts/deploy.sh periphery -l sequoia-server
```

### Update Peripheries

Update to latest version:

```bash
./scripts/deploy.sh periphery-update
```

Update to specific version:

```bash
./scripts/deploy.sh periphery-update-version v1.18.4
```

Update specific periphery:

```bash
./scripts/deploy.sh periphery-update -l home-server
./scripts/deploy.sh periphery-update-version v1.18.4 -l sequoia-server
```

### Uninstall Peripheries

Remove periphery services:

```bash
./scripts/deploy.sh periphery-uninstall
```

Remove specific periphery:

```bash
./scripts/deploy.sh periphery-uninstall -l home-server
```

## Configuration Details

### Global Configuration (`inventory/all.yml`)

All periphery configuration is now consolidated in a single file under the `komodo` group:

- **API Connection**: Retrieves credentials from 1Password automatically
- **Server Management**: Enabled by default for automatic registration with Core  
- **Security**: Configurable IP restrictions and secrets
- **Service**: Systemd user-mode service configuration

### Host-Specific Variables (`inventory/all.yml`)

Each periphery can override group settings:

- **server_address**: Custom server address (required for same-host peripheries)
- **generate_server_passkey**: Enable automatic passkey rotation for remote peripheries
- **komodo_bind_ip**: Interface binding configuration (defaults to "0.0.0.0")
- **komodo_allowed_ips**: IP access restrictions (defaults to empty = allow all)

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Komodo Core   │    │ Remote Periphery│
│   (Docker)      │    │   (Systemd)     │
│   Port: 9120    │    │   Port: 8120    │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────────────────┘
              API Connection
              
┌─────────────────┐
│ Same-Host       │
│ Periphery       │
│ (Systemd)       │
│ Port: 8120      │
└─────────────────┘
         │
         └─── https://host.docker.internal:8120
```

## Troubleshooting

### Check Service Status

```bash
# On periphery host (user-mode systemd service)
sudo -u komodo systemctl --user status periphery
sudo -u komodo journalctl --user -u periphery -f
```

### Verify API Connection

```bash
# Test Core API endpoint
curl http://<core-host>:9120/health
```

### Check 1Password Integration

```bash
# Verify 1Password CLI works
op item get Komodo --vault Homelab
```

### Regenerate Passkeys

For hosts with `generate_server_passkey: true`, passkeys are automatically rotated on each deployment. To force regeneration:

```bash
./scripts/deploy.sh periphery -l <host>
```

## Adding New Peripheries

1. **Add to inventory** (`inventory/all.yml`):
   ```yaml
   all:
     children:
       komodo:
         children:
           periphery:
             hosts:
               new-periphery:
                 ansible_host: "new-host"
                 node_site: "new-site"
                 generate_server_passkey: true
   ```

2. **Bootstrap the host**:
   ```bash
   ./scripts/deploy.sh bootstrap -l new-periphery
   ```

3. **Deploy periphery**:
   ```bash
   ./scripts/deploy.sh periphery -l new-periphery
   ```

## Security Notes

- API keys are retrieved from 1Password at runtime (not stored in plain text)
- Passkeys are automatically rotated for remote peripheries
- Same-host peripheries use local communication (no passkey needed)
- All peripheries use systemd for service management and security