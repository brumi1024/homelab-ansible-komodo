# Complete Komodo Deployment Guide

This guide provides the complete end-to-end deployment process for your Komodo infrastructure with GitOps capabilities.

## Overview

You now have a complete infrastructure-as-code setup with:

1. **Infrastructure Layer**: Ansible-managed Komodo Core and Periphery nodes
2. **GitOps Layer**: Automated stack deployment via GitHub webhooks
3. **Secret Management**: 1Password integration via komodo-op
4. **Application Layer**: Docker Compose stacks deployed automatically

## Deployment Phases

### Phase 1: Infrastructure Deployment

**Prerequisites**: SSH access to servers, 1Password CLI configured

```bash
# 1. Setup Ansible dependencies
./scripts/setup-ansible.sh

# 2. Configure inventory
cp ansible/inventory/all.yml.example ansible/inventory/all.yml
# Edit all.yml with your server details

# 3. Bootstrap all servers
./scripts/deploy.sh bootstrap

# 4. Deploy Komodo Core
./scripts/deploy.sh core

# 5. Generate API keys in Komodo UI
# Access http://your-server:<komodo_port>, create API keys (default port 9120)

# 6. Store API keys in 1Password
op item edit "Komodo" --vault "Homelab" komodo_api_key="your-key"
op item edit "Komodo" --vault "Homelab" komodo_api_secret="your-secret"

# 7. Deploy Komodo Periphery nodes
./scripts/deploy.sh periphery

# 8. Verify deployment
./scripts/deploy.sh status
```

**Result**: Working Komodo infrastructure with Core and Periphery nodes

### Phase 2: GitOps Setup

**Prerequisites**: GitHub account, 1Password Connect server configured

```bash
# 1. Setup 1Password Connect credentials (see docs/komodo-gitops-setup.md)

# 2. Create GitHub repositories
# Repository 1: benjaminteke/komodo-op-stack
# Repository 2: benjaminteke/homelab-komodo-stacks

# 3. Push prepared code to repositories
cd /path/to/komodo-op-stack && git push origin main
cd /path/to/homelab-komodo-stacks && git push origin main

# 4. Configure Komodo resource syncs
./scripts/deploy.sh setup-syncs

# 5. Configure GitHub webhooks (see GitOps setup guide)
```

**Result**: Komodo can automatically sync and deploy from GitHub repositories

### Phase 3: Secret Management

**Prerequisites**: 1Password Connect server, vault permissions

```bash
# 1. Deploy komodo-op via Komodo UI
# - Access Komodo → Resource Syncs → komodo-op-sync → Sync Now
# - Navigate to Stacks → komodo-op → Deploy

# 2. Verify secret synchronization
# - Check komodo-op logs: docker logs komodo-op-komodo-op-1
# - Check Komodo → Variables for synced secrets

# 3. Add application secrets to 1Password
# komodo-op will automatically sync them to Komodo
```

**Result**: Secrets flow from 1Password → komodo-op → Komodo → Application Stacks

### Phase 4: Application Deployment

**Prerequisites**: komodo-op running and syncing secrets

```bash
# 1. Sync application stacks
# - Access Komodo → Resource Syncs → application-stacks-sync → Sync Now

# 2. Deploy stacks in order
# - Komodo → Stacks → monitoring → Deploy
# - Komodo → Stacks → homepage → Deploy  
# - Komodo → Stacks → servarr → Deploy

# 3. Verify deployments
docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"
```

**Result**: All application stacks running with secrets from 1Password

## Repository Structure

After completion, you'll have three repositories:

### 1. homelab-komodo (Infrastructure)
```
homelab-komodo/
├── ansible/
│   ├── inventory/all.yml          # Single configuration file
│   ├── playbooks/                 # Deployment playbooks
│   └── roles/komodo/              # Custom Komodo role
├── scripts/deploy.sh              # Main deployment script
└── docs/                         # Complete documentation
```

### 2. komodo-op-stack (Secret Management)
```
komodo-op-stack/
├── docker-compose.yaml           # 1Password Connect + komodo-op
├── compose.override.yaml         # Komodo environment overrides
├── stack.toml                    # Komodo stack definition
└── renovate.json                 # Dependency tracking
```

### 3. homelab-komodo-stacks (Applications)
```
homelab-komodo-stacks/
├── servarr/
│   ├── docker-compose.yaml      # Media automation stack
│   └── stack.toml               # Deployment config
├── monitoring/
│   ├── docker-compose.yaml      # Prometheus, Grafana
│   └── stack.toml               # Deployment config
└── homepage/
    ├── docker-compose.yaml      # Dashboard
    └── stack.toml               # Deployment config
```

## Workflow After Setup

### Daily Operations

1. **Add new secrets**: Put in 1Password, wait 30s for sync
2. **Update applications**: Push to homelab-komodo-stacks repo
3. **Monitor**: Check Komodo UI for deployment status
4. **Updates**: Renovate creates PRs for dependency updates

### Adding New Stacks

1. **Create directory** in homelab-komodo-stacks
2. **Add docker-compose.yaml** and stack.toml
3. **Reference secrets** using `[[SECRET_NAME]]` syntax
4. **Push to GitHub** → automatic deployment

### Infrastructure Changes

1. **Update ansible/inventory/all.yml** for server changes
2. **Run deployment commands** from scripts/deploy.sh
3. **Update documentation** as needed

## Monitoring and Maintenance

### Health Checks

```bash
# Check infrastructure
./scripts/deploy.sh status

# Check applications  
docker ps --format "table {{.Names}}\\t{{.Status}}"

# Check secret sync
docker logs komodo-op-komodo-op-1
```

### Regular Maintenance

- **Weekly**: Review and merge Renovate PRs
- **Monthly**: Check logs for errors or issues
- **Quarterly**: Review security and update credentials
- **Annually**: Review and update documentation

## Advanced Features

### Auto-deployment

Enable in stack.toml:
```toml
[stack.config]
auto_update = true
destroy_before_deploy = true
```

### Multi-environment

- Use different branches for environments
- Separate inventory files for staging/production
- Environment-specific 1Password vaults

### High Availability

- Deploy multiple Komodo Core instances
- Use load balancer for Komodo UI
- Replicate 1Password Connect across sites

## Troubleshooting Quick Reference

| Issue | Check | Solution |
|-------|-------|----------|
| Stack won't deploy | Komodo global variables | Verify komodo-op is syncing |
| Webhook not working | GitHub webhook delivery | Check URL and secret |
| Secret missing | 1Password vault | Verify field name and permissions |
| Service not starting | Docker logs | Check environment variables |
| Sync failing | Resource sync logs | Verify repository access |

## Security Best Practices

1. **Use private repositories** for sensitive stacks
2. **Rotate credentials regularly** (API keys, tokens)
3. **Monitor access logs** in 1Password and GitHub
4. **Use minimal permissions** for service accounts
5. **Keep secrets out of Git** (use .gitignore)
6. **Enable webhook secrets** for all integrations

## Next Steps

After successful deployment:

1. **Customize stacks** for your specific needs
2. **Add monitoring and alerting** for critical services
3. **Set up backup procedures** for Komodo Core and databases
4. **Document any custom configurations** you add
5. **Consider advanced features** like multi-site deployment

## Support and Documentation

- **Infrastructure**: See docs/ directory in homelab-komodo
- **GitOps**: See docs/komodo-gitops-setup.md
- **1Password**: See docs/1password-setup.md  
- **Troubleshooting**: See docs/troubleshooting/ (when created)
- **Komodo Official**: https://github.com/mbecker20/komodo

Your infrastructure is now fully automated and ready for production use!