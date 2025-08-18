# Komodo Infrastructure Makefile
# Simplified deployment management with direct Ansible calls

.PHONY: help setup lint check \
        docker core auth periphery deploy \
        status clean

# Ansible configuration
INVENTORY := inventory/all.yml
ANSIBLE_OPTS := -i $(INVENTORY)

# Default target
help: ## Show this help message
	@echo "Komodo Infrastructure - Deployment Commands"
	@echo "=========================================="
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Quick Start:"
	@echo "  make setup    - Install Ansible dependencies"
	@echo "  make deploy   - Complete deployment (all steps)"
	@echo "  make lint     - Run code quality checks"

# =============================================================================
# Setup and Dependencies
# =============================================================================

setup: ## Install Ansible dependencies
	@echo "📦 Installing Ansible dependencies..."
	@./scripts/setup-ansible.sh
	@echo "✅ Setup complete!"

check: ## Check connectivity to all hosts
	@echo "🔍 Checking connectivity..."
	@cd ansible && ansible all $(ANSIBLE_OPTS) -m ping

# =============================================================================
# Code Quality
# =============================================================================

lint: ## Run ansible-lint and yamllint
	@echo "🔍 Running ansible-lint..."
	@cd ansible && ansible-lint
	@echo "🔍 Running yamllint..."
	@yamllint ansible/ .github/workflows/
	@echo "✅ Linting complete!"

# =============================================================================
# Individual Deployment Steps
# =============================================================================

docker: ## Install Docker on all nodes
	@echo "🐳 Installing Docker on all nodes..."
	@cd ansible && ansible-playbook $(ANSIBLE_OPTS) playbooks/01_docker.yml

core: ## Deploy Komodo Core (requires Docker)
	@echo "🦎 Deploying Komodo Core..."
	@cd ansible && ansible-playbook $(ANSIBLE_OPTS) playbooks/02_komodo_core.yml

auth: ## Initialize Komodo authentication (requires Core)
	@echo "🔑 Initializing Komodo authentication..."
	@cd ansible && ansible-playbook $(ANSIBLE_OPTS) playbooks/03_komodo_auth.yml

periphery: ## Deploy Komodo Periphery nodes (requires auth)
	@echo "🔗 Deploying Komodo Periphery..."
	@cd ansible && ansible-playbook $(ANSIBLE_OPTS) playbooks/04_komodo_periphery.yml

# =============================================================================
# Complete Deployment
# =============================================================================

deploy: ## Complete deployment (all steps in sequence)
	@echo "🚀 Starting complete Komodo deployment..."
	@cd ansible && ansible-playbook $(ANSIBLE_OPTS) site.yml

# =============================================================================
# Maintenance Commands
# =============================================================================

status: ## Check status of Komodo services
	@echo "🔍 Checking Komodo service status..."
	@cd ansible && ansible-playbook $(ANSIBLE_OPTS) playbooks/status.yml

clean: ## Clean up temporary files
	@echo "🧹 Cleaning up..."
	@find . -name "*.pyc" -delete
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@rm -rf ansible/.ansible/
	@echo "✅ Cleanup complete!"

# =============================================================================
# Advanced Options
# =============================================================================

# Run specific playbook with custom options
# Usage: make run PLAYBOOK=01_docker.yml OPTS="--check --diff"
run: ## Run specific playbook (requires PLAYBOOK variable)
	@if [ -z "$(PLAYBOOK)" ]; then \
		echo "❌ PLAYBOOK variable required. Usage: make run PLAYBOOK=01_docker.yml"; \
		exit 1; \
	fi
	@echo "🎯 Running $(PLAYBOOK)..."
	@cd ansible && ansible-playbook $(ANSIBLE_OPTS) playbooks/$(PLAYBOOK) $(OPTS)

# Run in check mode (dry run)
check-deploy: ## Dry run deployment (check mode)
	@echo "🔍 Dry run - checking what would change..."
	@cd ansible && ansible-playbook $(ANSIBLE_OPTS) site.yml --check --diff