#!/bin/bash
set -euo pipefail

# Komodo Deployment Script
echo "🚀 Komodo Deployment Script"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
INVENTORY="${INVENTORY:-inventory/all.yml}"
PLAYBOOK_DIR="playbooks"

# Usage information
usage() {
    cat << EOF
Komodo Deployment Script

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    bootstrap              Bootstrap all nodes (install Docker, Tailscale)
    core                  Deploy Komodo Core only (MongoDB + Core)
    periphery             Deploy Komodo Periphery nodes (requires API keys)
    periphery-update      Update periphery nodes to latest version
    periphery-update-version VERSION  Update periphery to specific version
    periphery-uninstall   Remove periphery services
    full                  Bootstrap + core + periphery (default)
    check                 Check connectivity to all hosts
    status                Check status of Komodo services

Options:
    -i, --inventory FILE    Inventory file (default: $INVENTORY)
    -v, --verbose          Enable verbose output
    -t, --tags TAGS        Run only specific tags
    -l, --limit HOSTS      Limit to specific hosts
    -h, --help            Show this help

Environment Variables:
    OP_SERVICE_ACCOUNT_TOKEN     1Password service account token (required for GitHub Actions)
    ANSIBLE_OPTS                 Additional Ansible options

Examples:
    $0                           # Full deployment (all phases)
    $0 bootstrap                 # Bootstrap nodes only
    $0 core                      # Deploy Komodo Core only
    $0 periphery                 # Deploy periphery nodes (after API keys)
    $0 periphery-update          # Update periphery to latest version
    $0 periphery-update-version v1.18.4  # Update to specific version
    $0 periphery-uninstall       # Remove periphery services
    $0 check                     # Check connectivity

Deployment Workflow:
    1. ./scripts/setup-ansible.sh  # Install dependencies
    2. $0 bootstrap              # Prepare all nodes
    3. $0 core                   # Deploy Komodo Core
    4. Generate API keys in UI   # Manual step (see docs/1password-setup.md)
    5. $0 periphery              # Deploy periphery nodes
    
See README.md for complete setup guide.
EOF
}

# Check prerequisites
check_prereqs() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"
    
    local errors=0
    
    # Check Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        echo -e "${RED}❌ Ansible not found${NC}"
        ((errors++))
    fi
    
    # Check inventory file
    if [[ ! -f "ansible/$INVENTORY" ]]; then
        echo -e "${RED}❌ Inventory file not found: ansible/$INVENTORY${NC}"
        echo "   Run: cp ansible/$INVENTORY.example ansible/$INVENTORY"
        ((errors++))
    fi
    
    # Check for 1Password CLI
    if ! command -v op &> /dev/null; then
        echo -e "${RED}❌ 1Password CLI (op) not found${NC}"
        echo "   Install from: https://developer.1password.com/docs/cli/get-started/"
        ((errors++))
    fi
    
    # Check if authenticated to 1Password
    if command -v op &> /dev/null && ! op account list &> /dev/null; then
        echo -e "${YELLOW}⚠️  Not authenticated to 1Password${NC}"
        echo "   Local: Run 'op signin'"
        echo "   CI/CD: Set OP_SERVICE_ACCOUNT_TOKEN environment variable"
        ((errors++))
    fi
    
    # Check for community.general collection
    if ! ansible-galaxy collection list 2>/dev/null | grep -q "community.general"; then
        echo -e "${YELLOW}⚠️  community.general collection not found${NC}"
        echo "   Run: ./scripts/setup-ansible.sh"
        ((errors++))
    fi
    
    # Check for external roles
    if ! ansible-galaxy role list 2>/dev/null | grep -q "geerlingguy.docker"; then
        echo -e "${YELLOW}⚠️  External roles not found${NC}"
        echo "   Run: ./scripts/setup-ansible.sh"
        ((errors++))
    fi
    
    if (( errors > 0 )); then
        echo -e "${RED}❌ Prerequisites check failed with $errors error(s)${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Run Ansible playbook with common options
run_playbook() {
    local playbook="$1"
    shift
    
    cd ansible  # Change to ansible directory
    
    # Set environment variables once, then run ansible-playbook directly
    local cmd=(
        ansible-playbook
        -i "$INVENTORY"
        "$PLAYBOOK_DIR/$playbook"
    )
    
    # Add common options
    if [[ -n "${VERBOSE:-}" ]]; then
        cmd+=(-vvv)
    fi
    
    if [[ -n "${TAGS:-}" ]]; then
        cmd+=(--tags "$TAGS")
    fi
    
    if [[ -n "${LIMIT:-}" ]]; then
        cmd+=(--limit "$LIMIT")
    fi
    
    # Add any additional arguments
    cmd+=("$@")
    
    # Add extra Ansible options if provided
    if [[ -n "${ANSIBLE_OPTS:-}" ]]; then
        # shellcheck disable=SC2086
        cmd+=($ANSIBLE_OPTS)
    fi
    
    echo -e "${BLUE}🚀 Running: ${cmd[*]}${NC}"
    "${cmd[@]}"
    local result=$?
    
    cd ..  # Return to repo root
    return $result
}

# Check connectivity
check_connectivity() {
    echo -e "${BLUE}🔍 Checking connectivity to all hosts...${NC}"
    
    cd ansible
    
    ansible all -i "$INVENTORY" -m ping --one-line
    local result=$?
    
    cd ..
    
    if [[ $result -eq 0 ]]; then
        echo -e "${GREEN}✅ All hosts are reachable${NC}"
    else
        echo -e "${RED}❌ Some hosts are unreachable${NC}"
        exit 1
    fi
}

# Bootstrap nodes
bootstrap() {
    echo -e "${BLUE}🔧 Bootstrapping nodes...${NC}"
    run_playbook "bootstrap.yml" "$@"
    echo -e "${GREEN}✅ Bootstrap completed${NC}"
}

# Deploy Komodo Core
deploy_core() {
    echo -e "${BLUE}🦎 Deploying Komodo Core...${NC}"
    run_playbook "komodo-core.yml" "$@"
    echo -e "${GREEN}✅ Komodo Core deployment completed${NC}"
}

# Deploy Komodo Periphery
deploy_periphery() {
    echo -e "${BLUE}🔗 Deploying Komodo Periphery...${NC}"
    run_playbook "komodo-periphery.yml" "$@"
    echo -e "${GREEN}✅ Komodo Periphery deployment completed${NC}"
}

# Update Komodo Periphery to latest version
update_periphery() {
    echo -e "${BLUE}🔄 Updating Komodo Periphery to latest version...${NC}"
    run_playbook "komodo-periphery.yml" -e "komodo_action=update" "$@"
    echo -e "${GREEN}✅ Komodo Periphery update completed${NC}"
}

# Update Komodo Periphery to specific version
update_periphery_version() {
    local version="$1"
    shift
    if [[ -z "$version" ]]; then
        echo -e "${RED}❌ Version parameter required${NC}"
        echo "Usage: $0 periphery-update-version VERSION [OPTIONS]"
        exit 1
    fi
    echo -e "${BLUE}🔄 Updating Komodo Periphery to version $version...${NC}"
    run_playbook "komodo-periphery.yml" -e "komodo_action=update" -e "komodo_periphery_version=$version" "$@"
    echo -e "${GREEN}✅ Komodo Periphery update to $version completed${NC}"
}

# Uninstall Komodo Periphery
uninstall_periphery() {
    echo -e "${YELLOW}⚠️  This will remove Komodo Periphery services from all periphery nodes${NC}"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled${NC}"
        exit 0
    fi
    echo -e "${BLUE}🗑️  Uninstalling Komodo Periphery...${NC}"
    run_playbook "komodo-periphery.yml" -e "komodo_action=uninstall" "$@"
    echo -e "${GREEN}✅ Komodo Periphery uninstall completed${NC}"
}

# Deploy full stack (for backwards compatibility)
deploy_full() {
    echo -e "${BLUE}🚀 Deploying complete Komodo infrastructure...${NC}"
    deploy_core "$@"
    echo -e "${YELLOW}⚠️  Manual step required before periphery deployment${NC}"
    echo -e "${YELLOW}   Generate API keys in Komodo Core UI${NC}"
    echo -e "${YELLOW}   Store them in 1Password (see docs/1password-setup.md)${NC}"
    echo -e "${YELLOW}   Then run: $0 periphery${NC}"
}

# Check service status
check_status() {
    echo -e "${BLUE}🔍 Checking Komodo service status...${NC}"
    
    cd ansible
    
    # Check Komodo Core health endpoint
    echo "Checking Komodo Core..."
    if ansible core -i "$INVENTORY" -m uri -a "url=http://localhost:9120 method=GET" --one-line > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Komodo Core is healthy${NC}"
    else
        echo -e "${RED}❌ Komodo Core is not responding${NC}"
        echo "   Try: docker logs komodo-core-komodo-1 (on core server)"
    fi
    
    # Check Komodo Periphery nodes (user-mode systemd services)
    echo "Checking Komodo Periphery nodes..."
    if ansible periphery -i "$INVENTORY" -m shell -a "sudo -u komodo systemctl --user is-active periphery" --one-line > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Komodo Periphery nodes are running${NC}"
    else
        echo -e "${YELLOW}⚠️  Some Komodo Periphery nodes may not be running${NC}"
        echo "   Try: sudo -u komodo journalctl --user -u periphery -f (on periphery servers)"
    fi
    
    # Check Docker container status for Core
    echo -e "${BLUE}Checking Komodo Core containers...${NC}"
    if ansible core -i "$INVENTORY" -m shell -a "docker ps --filter 'name=komodo-core' --format 'table {{.Names}}\\t{{.Status}}'" 2>/dev/null; then
        :  # Output will be shown
    else
        echo -e "${YELLOW}⚠️  Could not check Core containers${NC}"
    fi
    
    # Check systemd services for Periphery (user-mode services)
    echo -e "${BLUE}Checking Komodo Periphery services...${NC}"
    if ansible periphery -i "$INVENTORY" -m shell -a "sudo -u komodo systemctl --user status periphery --no-pager -l" 2>/dev/null; then
        :  # Output will be shown
    else
        echo -e "${YELLOW}⚠️  Could not check Periphery services${NC}"
    fi
    
    cd ..
}

# Show deployment information
show_info() {
    echo -e "${BLUE}📋 Deployment Information${NC}"
    echo
    
    cd ansible
    
    # Get core server info
    local core_host=$(ansible-inventory -i "$INVENTORY" --list | jq -r '.core.hosts[0]')
    if [[ -n "$core_host" && "$core_host" != "null" ]]; then
        local core_ip=$(ansible-inventory -i "$INVENTORY" --host "$core_host" | jq -r '.ansible_host // .ansible_ssh_host // "unknown"')
        echo -e "${GREEN}🖥️  Komodo Core:${NC}"
        echo "   Host: $core_host"
        echo "   IP: $core_ip"
        echo "   Web UI: http://$core_ip:9120"
        echo
    fi
    
    # Show periphery nodes
    echo -e "${GREEN}🔗 Periphery Nodes:${NC}"
    ansible-inventory -i "$INVENTORY" --list | jq -r '.periphery.hosts[]?' | while read -r host; do
        if [[ -n "$host" ]]; then
            local host_ip=$(ansible-inventory -i "$INVENTORY" --host "$host" | jq -r '.ansible_host // .ansible_ssh_host // "unknown"')
            echo "   $host ($host_ip:9001)"
        fi
    done
    echo
    
    cd ..
    
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Access Komodo Core web interface"
    echo "2. 🔑 MANUAL: Generate API keys in Komodo UI"
    echo "3. 🔗 Deploy periphery: ./deploy.sh periphery"
    echo "4. 🤖 MANUAL: Set up komodo-op integration (see docs/komodo-op-setup.md)"
    echo "5. Set up stack synchronization from homelab-stacks repository"
    echo "6. Deploy your services!"
}

# Main command processing
main() {
    cd "$(dirname "$0")/.."
    
    case "${1:-full}" in
        check)
            check_prereqs
            check_connectivity
            ;;
        bootstrap)
            shift
            check_prereqs
            bootstrap "$@"
            ;;
        core)
            shift
            check_prereqs
            deploy_core "$@"
            ;;
        periphery)
            shift
            check_prereqs
            deploy_periphery "$@"
            ;;
        periphery-update)
            shift
            check_prereqs
            update_periphery "$@"
            ;;
        periphery-update-version)
            shift
            check_prereqs
            update_periphery_version "$@"
            ;;
        periphery-uninstall)
            shift
            check_prereqs
            uninstall_periphery "$@"
            ;;
        full)
            shift
            check_prereqs
            check_connectivity
            bootstrap "$@"
            deploy_full "$@"
            show_info
            ;;
        status)
            check_status
            ;;
        info)
            show_info
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -t|--tags)
            TAGS="$2"
            shift 2
            ;;
        -l|--limit)
            LIMIT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            # Pass remaining arguments to main
            main "$@"
            exit 0
            ;;
    esac
done

# If no arguments, run full deployment
main "full"