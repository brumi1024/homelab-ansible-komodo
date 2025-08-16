#!/bin/bash
set -euo pipefail

# Quick Add Server Script
# Interactive script to add a new server to Komodo infrastructure

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
INVENTORY_FILE="ansible/inventory/hosts.yml"

# Usage information
usage() {
    cat << EOF
Quick Add Server Script

Usage: $0 [OPTIONS]

Options:
    -n, --name NAME        Server name (required if not interactive)
    -h, --host HOST        Hostname or IP address (required if not interactive)
    -r, --role ROLE        Server role: core or periphery (required if not interactive)
    -s, --site SITE        Site/location name (required if not interactive)
    --stacks STACKS        Comma-separated list of stacks (periphery only)
    --non-interactive      Run without prompts (requires all options)
    --help                 Show this help

Examples:
    $0                                    # Interactive mode
    $0 -n worker-3 -h 192.168.1.100 -r periphery -s home --stacks servarr,monitoring
    $0 --non-interactive -n core-backup -h core2.mydomain.com -r core -s datacenter

Interactive mode will guide you through the process step by step.
EOF
}

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local errors=0
    
    # Check if we're in the right directory
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file not found: $INVENTORY_FILE"
        log_error "Please run this script from the project root directory"
        ((errors++))
    fi
    
    # Check for required tools
    if ! command -v ansible &> /dev/null; then
        log_error "Ansible not found. Please install Ansible first."
        ((errors++))
    fi
    
    if ! command -v yq &> /dev/null; then
        log_warning "yq not found. YAML editing will be done with sed (less reliable)"
        log_warning "Consider installing yq: brew install yq"
    fi
    
    # Check if inventory file is writable
    if [[ ! -w "$INVENTORY_FILE" ]]; then
        log_error "Cannot write to inventory file: $INVENTORY_FILE"
        ((errors++))
    fi
    
    if (( errors > 0 )); then
        log_error "Prerequisites check failed with $errors error(s)"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Interactive input functions
get_server_name() {
    while true; do
        echo
        read -p "Enter server name (e.g., worker-3, core-backup): " SERVER_NAME
        
        if [[ -z "$SERVER_NAME" ]]; then
            log_error "Server name cannot be empty"
            continue
        fi
        
        if [[ ! "$SERVER_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
            log_error "Server name can only contain letters, numbers, and hyphens"
            continue
        fi
        
        # Check if name already exists
        if grep -q "^    $SERVER_NAME:" "$INVENTORY_FILE"; then
            log_error "Server name '$SERVER_NAME' already exists in inventory"
            continue
        fi
        
        log_success "Server name: $SERVER_NAME"
        break
    done
}

get_server_host() {
    while true; do
        echo
        read -p "Enter hostname or IP address: " SERVER_HOST
        
        if [[ -z "$SERVER_HOST" ]]; then
            log_error "Hostname/IP cannot be empty"
            continue
        fi
        
        log_success "Server host: $SERVER_HOST"
        break
    done
}

get_server_role() {
    while true; do
        echo
        echo "Select server role:"
        echo "1) core      - Komodo Core (control plane with web UI)"
        echo "2) periphery - Komodo Periphery (worker node for services)"
        echo
        read -p "Enter choice (1-2): " choice
        
        case $choice in
            1) SERVER_ROLE="core"; break ;;
            2) SERVER_ROLE="periphery"; break ;;
            *) log_error "Invalid choice. Please enter 1 or 2." ;;
        esac
    done
    
    log_success "Server role: $SERVER_ROLE"
}

get_server_site() {
    echo
    echo "Available sites (from existing inventory):"
    grep -o "node_site: [a-zA-Z0-9_-]*" "$INVENTORY_FILE" | cut -d' ' -f2 | sort -u | while read -r site; do
        echo "  - $site"
    done
    echo
    read -p "Enter site name (or create new): " SERVER_SITE
    
    if [[ -z "$SERVER_SITE" ]]; then
        SERVER_SITE="default"
        log_warning "Using default site: $SERVER_SITE"
    else
        log_success "Server site: $SERVER_SITE"
    fi
}

get_server_stacks() {
    if [[ "$SERVER_ROLE" == "core" ]]; then
        log_info "Core servers don't need stack configuration"
        SERVER_STACKS=""
        return
    fi
    
    echo
    echo "Enter stacks this server will run (comma-separated, optional):"
    echo "Examples: servarr,monitoring  or  uptime-kuma  or  <empty for none>"
    read -p "Stacks: " stacks_input
    
    if [[ -n "$stacks_input" ]]; then
        # Convert comma-separated to array format
        SERVER_STACKS="$stacks_input"
        log_success "Server stacks: $SERVER_STACKS"
    else
        SERVER_STACKS=""
        log_info "No stacks configured (can be added later)"
    fi
}

# Test connectivity to server
test_connectivity() {
    log_info "Testing connectivity to $SERVER_HOST..."
    
    # Test basic connectivity
    if ! timeout 10 bash -c "</dev/tcp/$SERVER_HOST/22"; then
        log_error "Cannot connect to SSH port (22) on $SERVER_HOST"
        log_error "Please verify:"
        log_error "  - Server is running and accessible"
        log_error "  - SSH service is running"
        log_error "  - No firewall blocking port 22"
        
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Aborting due to connectivity issues"
            exit 1
        fi
    else
        log_success "SSH connectivity test passed"
    fi
}

# Add server to inventory
add_to_inventory() {
    log_info "Adding server to inventory..."
    
    # Determine the group based on role
    local group
    if [[ "$SERVER_ROLE" == "core" ]]; then
        group="komodo_core"
    else
        group="komodo_periphery"
    fi
    
    # Backup inventory file
    cp "$INVENTORY_FILE" "${INVENTORY_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Created backup: ${INVENTORY_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Check if group exists, add if not
    if ! grep -q "^  $group:" "$INVENTORY_FILE"; then
        log_warning "Group '$group' not found in inventory, adding it"
        
        # Add the group under children
        if grep -q "^  children:" "$INVENTORY_FILE"; then
            sed -i "/^  children:/a\\    $group:\\n      hosts:" "$INVENTORY_FILE"
        else
            # Add children section if it doesn't exist
            sed -i "/^all:/a\\  children:\\n    $group:\\n      hosts:" "$INVENTORY_FILE"
        fi
    fi
    
    # Build the server entry
    local server_entry="    $SERVER_NAME:\n      ansible_host: \"$SERVER_HOST\"\n      node_site: $SERVER_SITE"
    
    if [[ "$SERVER_ROLE" == "core" ]]; then
        server_entry="$server_entry\n      komodo_role: core"
    fi
    
    if [[ -n "$SERVER_STACKS" && "$SERVER_ROLE" == "periphery" ]]; then
        server_entry="$server_entry\n      node_stacks:"
        IFS=',' read -ra STACKS <<< "$SERVER_STACKS"
        for stack in "${STACKS[@]}"; do
            stack=$(echo "$stack" | xargs)  # trim whitespace
            server_entry="$server_entry\n        - $stack"
        done
    fi
    
    # Add server to the group
    # Find the line with the group's hosts: and add after it
    local group_line=$(grep -n "^  $group:" "$INVENTORY_FILE" | cut -d: -f1)
    local hosts_line=$(tail -n +$((group_line + 1)) "$INVENTORY_FILE" | grep -n "^    hosts:" | head -1 | cut -d: -f1)
    hosts_line=$((group_line + hosts_line))
    
    # Insert the server entry after the hosts: line
    sed -i "${hosts_line}a\\$server_entry" "$INVENTORY_FILE"
    
    log_success "Server added to inventory in group '$group'"
}

# Show deployment instructions
show_next_steps() {
    echo
    log_success "Server '$SERVER_NAME' has been added to the inventory!"
    echo
    log_info "Next steps:"
    echo
    echo "1. Verify the inventory entry:"
    echo "   grep -A 10 \"$SERVER_NAME:\" $INVENTORY_FILE"
    echo
    echo "2. Test connectivity:"
    echo "   ./scripts/deploy.sh check -l $SERVER_NAME"
    echo
    echo "3. Bootstrap the server:"
    echo "   ./scripts/deploy.sh bootstrap -l $SERVER_NAME"
    echo
    if [[ "$SERVER_ROLE" == "core" ]]; then
        echo "4. Deploy Komodo Core:"
        echo "   ./scripts/deploy.sh core -l $SERVER_NAME"
        echo
        echo "5. Access the web UI and configure as needed"
        echo "   URL will be shown after deployment"
    else
        echo "4. Ensure Komodo Core is deployed and API keys are generated"
        echo
        echo "5. Deploy Komodo Periphery:"
        echo "   ./scripts/deploy.sh periphery -l $SERVER_NAME"
        echo
        echo "6. Configure stacks in the Komodo web UI"
    fi
    echo
    echo "6. Verify deployment:"
    echo "   ./scripts/deploy.sh status"
    echo
    log_warning "Remember to commit the inventory changes to git!"
}

# Parse command line arguments
INTERACTIVE=true
SERVER_NAME=""
SERVER_HOST=""
SERVER_ROLE=""
SERVER_SITE=""
SERVER_STACKS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            SERVER_NAME="$2"
            shift 2
            ;;
        -h|--host)
            SERVER_HOST="$2"
            shift 2
            ;;
        -r|--role)
            SERVER_ROLE="$2"
            shift 2
            ;;
        -s|--site)
            SERVER_SITE="$2"
            shift 2
            ;;
        --stacks)
            SERVER_STACKS="$2"
            shift 2
            ;;
        --non-interactive)
            INTERACTIVE=false
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo "🚀 Quick Add Server Script"
    echo
    
    # Change to project root
    cd "$(dirname "$0")/.."
    
    check_prerequisites
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        echo
        log_info "Interactive mode - please provide server details"
        
        get_server_name
        get_server_host
        get_server_role
        get_server_site
        get_server_stacks
        
        echo
        log_info "Server configuration summary:"
        echo "  Name: $SERVER_NAME"
        echo "  Host: $SERVER_HOST"
        echo "  Role: $SERVER_ROLE"
        echo "  Site: $SERVER_SITE"
        if [[ -n "$SERVER_STACKS" ]]; then
            echo "  Stacks: $SERVER_STACKS"
        fi
        echo
        
        read -p "Add this server to inventory? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warning "Operation cancelled by user"
            exit 0
        fi
    else
        # Non-interactive mode - validate required parameters
        if [[ -z "$SERVER_NAME" || -z "$SERVER_HOST" || -z "$SERVER_ROLE" || -z "$SERVER_SITE" ]]; then
            log_error "Non-interactive mode requires --name, --host, --role, and --site parameters"
            usage
            exit 1
        fi
        
        if [[ "$SERVER_ROLE" != "core" && "$SERVER_ROLE" != "periphery" ]]; then
            log_error "Role must be 'core' or 'periphery'"
            exit 1
        fi
        
        log_info "Non-interactive mode: adding $SERVER_NAME ($SERVER_ROLE) at $SERVER_HOST"
    fi
    
    test_connectivity
    add_to_inventory
    show_next_steps
}

# Run main function
main "$@"