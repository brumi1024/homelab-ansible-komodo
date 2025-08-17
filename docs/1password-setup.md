# 1Password Setup for Komodo Infrastructure

This guide explains how to configure 1Password for secure secret management in your Komodo infrastructure.

## Overview

The Komodo infrastructure uses 1Password to securely store and retrieve all sensitive configuration values including:
- Database passwords
- API keys and secrets
- JWT tokens
- OIDC credentials
- Tailscale authentication keys

All secrets are retrieved dynamically during deployment using 1Password CLI and Ansible's `community.general.onepassword` lookup plugin.

## Prerequisites

### 1Password CLI Installation

**macOS:**
```bash
brew install --cask 1password-cli
```

**Linux:**
```bash
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list
sudo apt update && sudo apt install 1password-cli
```

**Verify installation:**
```bash
op --version
```

### Authentication Methods

#### Method 1: Interactive Sign-in (Recommended for local use)

```bash
# Initial sign-in
op account add --address your-account.1password.com --email your-email@domain.com

# Subsequent sign-ins
op signin
```

#### Method 2: Service Account (Recommended for CI/CD)

1. **Create a service account** in your 1Password account
2. **Grant appropriate vault permissions**
3. **Set the token as an environment variable:**

```bash
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"
```

## Required 1Password Items

All items should be created in the **'Homelab' vault**. The exact item names and field names matter - they must match what's used in the Ansible templates.

### 1. Komodo Core Configuration

**Item Name:** `Komodo`  
**Item Type:** Login or Secure Note

**Required Fields:**
| Field Name | Description | Example Value |
|------------|-------------|---------------|
| `komodo_db_username` | MongoDB username | `komodo_user` |
| `komodo_db_password` | MongoDB password | `secure_random_password` |
| `komodo_passkey` | Core/Periphery authentication | `generated_passkey_32_chars` |
| `komodo_host` | External hostname for Komodo | `komodo.yourdomain.com` |
| `komodo_webhook_secret` | Git webhook secret | `webhook_secret_key` |
| `komodo_jwt_secret` | JWT signing secret | `jwt_signing_key_64_chars` |
| `komodo_oidc_provider` | OIDC provider URL | `https://auth.yourdomain.com` |
| `komodo_oidc_redirect_host` | OIDC redirect host | `komodo.yourdomain.com` |
| `komodo_oidc_client_id` | OIDC client ID | `komodo-client-id` |
| `komodo_oidc_client_secret` | OIDC client secret | `oidc_client_secret` |
| `komodo_api_key` | API key for periphery | `generated_after_core_deployment` |
| `komodo_api_secret` | API secret for periphery | `generated_after_core_deployment` |
| `KOMODO_API_KEY` | API key for komodo-op | `same_as_komodo_api_key` |
| `KOMODO_API_SECRET` | API secret for komodo-op | `same_as_komodo_api_secret` |
| `OP_SERVICE_ACCOUNT_TOKEN` | 1Password Connect service token | `from_1password_admin` |
| `OP_VAULT_UUID` | 1Password vault UUID | `from_vault_settings` |

**How to create:**
```bash
# Create the item
op item create --category Login --title "Komodo" --vault "Homelab"

# Add each field
op item edit "Komodo" --vault "Homelab" komodo_db_username="komodo_user"
op item edit "Komodo" --vault "Homelab" komodo_db_password="$(op generate 32)"
op item edit "Komodo" --vault "Homelab" komodo_passkey="$(op generate 32)"
# ... continue for all fields
```

### 2. Tailscale Configuration

**Item Name:** `Tailscale`  
**Item Type:** Login or Secure Note

**Required Fields:**
| Field Name | Description | How to Generate |
|------------|-------------|-----------------|
| `tailscale_authkey` | Tailscale authentication key | Generate in Tailscale admin console |

**How to create:**
```bash
op item create --category Login --title "Tailscale" --vault "Homelab"
op item edit "Tailscale" --vault "Homelab" tailscale_authkey="tskey-auth-your-key-here"
```

### 3. 1Password Connect (Required for komodo-op integration)

**Item Name:** `ConnectServer`  
**Item Type:** Document or Secure Note

**Required Fields:**
| Field Name | Description | Source |
|------------|-------------|--------|
| `1password-credentials.json` | Connect server credentials | Download from 1Password admin |
| `OP_SERVICE_ACCOUNT_TOKEN` | Connect service account token | Generate in 1Password admin |
| `OP_VAULT_UUID` | Vault UUID for komodo-op sync | Get from vault settings |

**Note:** These are required for komodo-op to sync secrets from 1Password to Komodo global variables.

**How to set up:**

1. **Create Connect Server** in 1Password admin console
2. **Download credentials** (`1password-credentials.json`) 
3. **Create service account** with read access to Homelab vault
4. **Get vault UUID** from vault settings
5. **Store in 1Password** item named `ConnectServer`

## Field Generation Guidelines

### Secure Password Generation

Use 1Password CLI to generate secure values:

```bash
# Generate random passwords
op generate 32  # 32-character password
op generate 64  # 64-character password

# Generate with specific character sets
op generate --letters --digits 32  # alphanumeric only
op generate --symbols 64  # include symbols
```

### Specific Field Requirements

**Database passwords:**
- Minimum 16 characters
- Include letters, numbers, and symbols
- Avoid characters that might cause shell escaping issues: `"`, `'`, `\`, `$`

**JWT secrets:**
- Minimum 32 characters (64+ recommended)
- Use strong randomness
- Base64 encoding is acceptable but not required

**API keys/secrets:**
- Will be generated automatically by Komodo Core after deployment
- Add these fields with placeholder values initially
- Update with real values after Core deployment

**Passkeys:**
- 32+ character random string
- Used for secure communication between Core and Periphery
- Critical for infrastructure security

## Vault Permissions

### For Personal Accounts

Ensure your user has:
- **Read access** to the 'Homelab' vault
- **Item management** permissions for updating API keys

### For Service Accounts (CI/CD)

Grant the service account:
- **Read-only access** to the 'Homelab' vault
- Access to specific items only (principle of least privilege)

**Example service account permissions:**
```
Vault: Homelab
  - Read access to items: Komodo, Tailscale
  - No write permissions (for security)
```

## Verification

### Test 1Password CLI Access

```bash
# Test authentication
op account list

# Test vault access
op vault list

# Test item retrieval
op item get "Komodo" --vault "Homelab"

# Test specific field retrieval
op item get "Komodo" --vault "Homelab" --fields label=komodo_db_password
```

### Test Ansible Integration

```bash
# Test from project root
cd ansible

# Test 1Password lookup
ansible localhost -m debug -a "msg={{ lookup('community.general.onepassword', 'Komodo', field='komodo_passkey', vault='Homelab') }}"
```

## Troubleshooting

### Common Issues

**"Authentication failed" errors:**
```bash
# Check current authentication
op account list

# Re-authenticate
op signin

# For service accounts
echo $OP_SERVICE_ACCOUNT_TOKEN | wc -c  # Should be >20 characters
```

**"Item not found" errors:**
```bash
# List all items in vault
op item list --vault "Homelab"

# Check exact item name
op item get "Komodo" --vault "Homelab" --format json | jq '.title'
```

**"Field not found" errors:**
```bash
# List all fields in an item
op item get "Komodo" --vault "Homelab" --format json | jq '.fields[].label'

# Check for typos in field names
op item get "Komodo" --vault "Homelab" --fields label=komodo_db_password
```

### Debugging Ansible Lookups

**Enable debug output:**
```yaml
- name: Debug 1Password lookup
  debug:
    msg: "{{ lookup('community.general.onepassword', 'Komodo', field='komodo_passkey', vault='Homelab') }}"
  delegate_to: localhost
```

**Common lookup issues:**
- **Vault name case sensitivity**: Must be exactly "Homelab"
- **Field name mismatches**: Check spelling and underscores
- **Authentication context**: Lookups run on Ansible controller, not target hosts

## Advanced Configuration

### Multiple Vaults

If using multiple vaults, specify in each lookup:

```yaml
# Production vault
prod_secret: "{{ lookup('community.general.onepassword', 'Item', field='field', vault='Production') }}"

# Development vault
dev_secret: "{{ lookup('community.general.onepassword', 'Item', field='field', vault='Development') }}"
```

### Custom Field Types

For complex configurations, use JSON fields:

```bash
# Store JSON configuration
op item edit "Komodo" --vault "Homelab" custom_config='{"key": "value", "array": [1,2,3]}'
```

```yaml
# Parse in Ansible
custom_config: "{{ lookup('community.general.onepassword', 'Komodo', field='custom_config', vault='Homelab') | from_json }}"
```

### Environment-Specific Items

For multiple environments:

```
Items:
  - Komodo-Production
  - Komodo-Staging  
  - Komodo-Development
```

Reference based on environment:
```yaml
komodo_item: "Komodo-{{ environment }}"
db_password: "{{ lookup('community.general.onepassword', komodo_item, field='komodo_db_password', vault='Homelab') }}"
```