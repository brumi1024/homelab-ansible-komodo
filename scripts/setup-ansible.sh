#!/bin/bash
set -euo pipefail

# Ansible Setup Script
echo "🔧 Setting up Ansible dependencies for Homelab Komodo"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$(dirname "$0")/.."

# Check if ansible-galaxy is available
if ! command -v ansible-galaxy &> /dev/null; then
    echo -e "${RED}❌ ansible-galaxy not found. Please install Ansible first.${NC}"
    echo "   Install with: pip install ansible"
    exit 1
fi

echo -e "${BLUE}📦 Installing Ansible collections...${NC}"
ansible-galaxy collection install -r ansible/requirements.yml

echo -e "${BLUE}🎭 Installing external Ansible roles to ~/.ansible/roles...${NC}"
ansible-galaxy install -r ansible/requirements.yml -p ~/.ansible/roles

echo -e "${GREEN}✅ Ansible setup complete!${NC}"
echo
echo -e "${BLUE}External roles installed:${NC}"
echo "  • geerlingguy.docker (Docker installation)"
echo "  • geerlingguy.security (SSH, fail2ban, unattended upgrades)"
echo "  • bpbradley.komodo (Komodo periphery management)"
echo
echo -e "${BLUE}Collections installed:${NC}"
echo "  • community.docker (Docker management modules)"
echo "  • community.general (1Password lookups and utilities)"
echo
echo -e "${YELLOW}💡 Note: External roles are installed outside the project repository${NC}"
echo -e "${YELLOW}   and will not be committed to git.${NC}"
