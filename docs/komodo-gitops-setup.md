# Komodo GitOps Setup Guide

This guide explains how to set up GitOps with Komodo using resource syncs, komodo-op for secret management, and automatic deployments via webhooks.

## Overview

The GitOps setup consists of two main repositories:

1. **komodo-op-stack**: Infrastructure stack that syncs secrets from 1Password to Komodo
2. **homelab-komodo-stacks**: Application stacks that use secrets from Komodo

### Architecture Flow

```
1Password Vault → komodo-op → Komodo Global Variables → Application Stacks
     ↑                ↑              ↑                        ↑
GitHub Repo 1   Resource Sync 1  Resource Sync 2      GitHub Repo 2
```

## Prerequisites

1. **Komodo Core deployed** with API keys generated
2. **1Password Connect configured** with service account and vault access
3. **GitHub repositories created** for both komodo-op-stack and homelab-komodo-stacks
4. **Git repositories pushed** to GitHub

## Phase 1: 1Password Connect Setup

### Step 1: Create Connect Server

1. **Access 1Password admin console**
2. **Navigate to Integrations → 1Password Connect**
3. **Create new Connect server**
4. **Download 1password-credentials.json**
5. **Generate service account token**

### Step 2: Store Credentials in 1Password

Create item `ConnectServer` in `Homelab` vault with fields:

```bash
# Create the item
op item create --category "Secure Note" --title "ConnectServer" --vault "Homelab"

# Add the credentials file (upload the downloaded JSON)
op item edit "ConnectServer" --vault "Homelab" --file 1password-credentials.json="./1password-credentials.json"

# Add service account token  
op item edit "ConnectServer" --vault "Homelab" OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"

# Add vault UUID (get from vault settings)
op item edit "ConnectServer" --vault "Homelab" OP_VAULT_UUID="your-vault-uuid-here"
```

### Step 3: Update Komodo Item

Add komodo-op specific fields to existing `Komodo` item:

```bash
# Add komodo-op API credentials (same as existing ones)
op item edit "Komodo" --vault "Homelab" KOMODO_API_KEY="$(op item get Komodo --vault Homelab --fields komodo_api_key)"
op item edit "Komodo" --vault "Homelab" KOMODO_API_SECRET="$(op item get Komodo --vault Homelab --fields komodo_api_secret)"

# Add 1Password Connect credentials
op item edit "Komodo" --vault "Homelab" OP_SERVICE_ACCOUNT_TOKEN="$(op item get ConnectServer --vault Homelab --fields OP_SERVICE_ACCOUNT_TOKEN)"
op item edit "Komodo" --vault "Homelab" OP_VAULT_UUID="$(op item get ConnectServer --vault Homelab --fields OP_VAULT_UUID)"

# Note: KOMODO_HOST is not stored in 1Password since komodo-op uses host.docker.internal to connect to Komodo Core
```

## Phase 2: Create GitHub Repositories

### Step 1: Create komodo-op-stack Repository

```bash
# Navigate to komodo-op-stack directory
cd /Users/benjaminteke/Developer/personal/projects/komodo-op-stack

# Create GitHub repository
gh repo create benjaminteke/komodo-op-stack --public --description "Komodo stack for 1Password Connect and komodo-op"

# Push to GitHub
git remote add origin https://github.com/benjaminteke/komodo-op-stack.git
git push -u origin main
```

### Step 2: Create homelab-komodo-stacks Repository

```bash
# Navigate to homelab-komodo-stacks directory
cd /Users/benjaminteke/Developer/personal/projects/homelab-komodo-stacks

# Create GitHub repository
gh repo create benjaminteke/homelab-komodo-stacks --public --description "Homelab application stacks for Komodo deployment"

# Push to GitHub
git remote add origin https://github.com/benjaminteke/homelab-komodo-stacks.git
git push -u origin main
```

## Phase 3: Configure Komodo Resource Syncs

### Step 1: Run Setup Playbook

```bash
# From homelab-komodo directory
./scripts/deploy.sh setup-syncs
```

This creates:
- Resource sync for `komodo-op-stack` repository
- Resource sync for `homelab-komodo-stacks` repository  
- Webhooks for automatic deployment

### Step 2: Bootstrap komodo-op Variables

Before deploying komodo-op, bootstrap the required global variables:

```bash
# From homelab-komodo directory
./scripts/deploy.sh bootstrap-komodo-op
```

This creates the initial Komodo global variables that komodo-op needs to start:
- `KOMODO_API_KEY` and `KOMODO_API_SECRET` (from Komodo item in 1Password)
- `OP_SERVICE_ACCOUNT_TOKEN` and `OP_VAULT_UUID` (from ConnectServer item in 1Password)

### Step 3: Configure GitHub Webhooks

After the playbook runs, configure GitHub webhooks:

**For komodo-op-stack repository:**
```
URL: http://your-komodo-host:<komodo_port>/api/sync/komodo-op-sync/webhook
Content-Type: application/json
Secret: <webhook_secret_from_1password>
Events: push
```

**For homelab-komodo-stacks repository:**
```
URL: http://your-komodo-host:<komodo_port>/api/sync/application-stacks-sync/webhook  
Content-Type: application/json
Secret: <webhook_secret_from_1password>
Events: push
```

Note: Replace `<komodo_port>` with your configured port (default is 9120).

## Phase 4: Deploy komodo-op (Foundation)

### Step 1: Initial Deployment

1. **Access Komodo UI** at `http://your-komodo-host:<komodo_port>` (default port 9120)
2. **Navigate to Resource Syncs**
3. **Find komodo-op-sync** and click "Sync Now"
4. **Wait for sync** to complete (should create komodo-op stack)
5. **Navigate to Stacks** and find "komodo-op"
6. **Deploy the stack** by clicking "Deploy"

### Step 2: Verify komodo-op Deployment

Check that services are running:

```bash
# On the target server (home-server)
docker ps | grep -E "(connect|komodo-op)"

# Expected output:
# - 1password/connect-api
# - 1password/connect-sync  
# - ghcr.io/0dragosh/komodo-op
```

### Step 3: Verify Secret Synchronization

1. **Check komodo-op logs**:
   ```bash
   docker logs komodo-op-komodo-op-1
   ```

2. **Check Komodo global variables**:
   - Access Komodo UI → Variables
   - Look for secrets that have been synced from 1Password
   - Should see secrets with names matching 1Password items

### Step 4: Wait for Complete Sync

Allow 1-2 minutes for komodo-op to complete initial synchronization of all secrets from 1Password to Komodo.

## Phase 5: Deploy Application Stacks

### Step 1: Sync Application Stacks

1. **Navigate to Resource Syncs** in Komodo UI
2. **Find application-stacks-sync** and click "Sync Now"  
3. **Wait for sync** to complete (should discover all stack.toml files)

### Step 2: Deploy Individual Stacks

Deploy stacks in order of dependencies:

1. **Monitoring stack** (independent):
   - Navigate to Stacks → monitoring
   - Click "Deploy"
   - Wait for containers to start

2. **Homepage stack** (independent):
   - Navigate to Stacks → homepage
   - Click "Deploy"
   - Wait for container to start

3. **Servarr stack** (may depend on monitoring):
   - Navigate to Stacks → servarr
   - Click "Deploy"
   - Wait for all containers to start

### Step 3: Verify Deployments

Check that all stacks are running:

```bash
# Check all deployed containers
docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"

# Check specific stack logs
docker logs <container-name>
```

## Phase 6: Test GitOps Workflow

### Step 1: Test komodo-op Updates

1. **Make a change** to komodo-op-stack repository
2. **Push to GitHub**
3. **Verify webhook** triggers automatic sync and deployment
4. **Check Komodo UI** for updated deployment

### Step 2: Test Application Stack Updates

1. **Make a change** to any stack in homelab-komodo-stacks
2. **Push to GitHub**
3. **Verify webhook** triggers automatic sync
4. **Check auto-deployment** (if enabled in stack.toml)

## Ongoing Management

### Adding New Secrets

1. **Add secret** to 1Password "Homelab" vault
2. **Wait 30-60 seconds** for komodo-op to sync
3. **Reference secret** in stack.toml as `[[SECRET_NAME]]`
4. **Deploy/redeploy** affected stacks

### Adding New Stacks

1. **Create stack directory** in homelab-komodo-stacks
2. **Add docker-compose.yaml** and stack.toml
3. **Commit and push** to GitHub
4. **Webhook automatically syncs** new stack definition
5. **Deploy manually** or enable auto-deploy

### Monitoring

**Regular checks:**
- komodo-op logs for sync errors
- Komodo global variables for missing secrets  
- Stack deployment status in Komodo UI
- GitHub webhook delivery status

## Troubleshooting

### komodo-op Not Syncing

```bash
# Check komodo-op container logs
docker logs komodo-op-komodo-op-1

# Common issues:
# - Invalid service account token
# - Incorrect vault UUID
# - Network connectivity to 1Password Connect
```

### Stacks Can't Access Secrets

1. **Verify secret exists** in Komodo global variables
2. **Check secret name** matches exactly in stack.toml
3. **Redeploy komodo-op** if sync appears broken
4. **Check 1Password vault permissions**

### Webhooks Not Working

1. **Verify webhook URL** is correct and reachable
2. **Check webhook secret** matches Komodo configuration
3. **Test webhook** delivery in GitHub repository settings
4. **Check Komodo logs** for webhook processing errors

### Resource Sync Failures

1. **Check repository access** (public repos work best)
2. **Verify branch name** is correct (main vs master)
3. **Check resource_path** matches file structure
4. **Review Komodo sync logs** for specific errors

## Security Considerations

- **Repository visibility**: Use private repositories for sensitive configurations
- **Webhook secrets**: Always use webhook secrets for security
- **1Password permissions**: Grant minimal required access to service accounts
- **Network access**: Restrict access to Komodo and 1Password Connect endpoints
- **Credential rotation**: Regularly rotate service account tokens and webhook secrets

## Performance Tips

- **Sync intervals**: Adjust komodo-op sync interval based on requirements
- **Auto-deploy**: Use sparingly to avoid unintended deployments
- **Resource limits**: Set appropriate resource limits in compose files
- **Cleanup**: Regularly clean up unused Docker images and volumes