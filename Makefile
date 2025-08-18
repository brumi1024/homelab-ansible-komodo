# Homelab Komodo Infrastructure Makefile
# Unified development environment and deployment management

.PHONY: help setup lint \
        deploy-bootstrap deploy-core deploy-periphery deploy-periphery-update \
        deploy-periphery-update-version deploy-periphery-uninstall deploy-syncs deploy-all \
        deploy-full deploy-init-auth deploy-bootstrap-op clean check-tools status info env

# Default target
help: ## Show this help message
	@echo "Homelab Komodo Infrastructure - Development Commands"
	@echo "=================================================="
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Quick Start:"
	@echo "  make setup           - Install all development dependencies"
	@echo "  make lint            - Run all linting checks"
	@echo "  make deploy-core     - Deploy core infrastructure"
	@echo "  make deploy-init-auth- Initialize API keys automatically"

# =============================================================================
# Development Environment Setup
# =============================================================================

setup: check-tools ## Complete development environment setup
	@echo "📦 Setting up development environment..."
	@if command -v brew >/dev/null 2>&1 && [ -f Brewfile ]; then \
		echo "📦 Installing system dependencies with Homebrew..."; \
		brew bundle; \
	else \
		echo "ℹ️  No Homebrew or Brewfile found, skipping system dependencies"; \
	fi
	@echo "📦 Installing Python development dependencies..."
	@pip3 install -r requirements-dev.txt
	@echo "📦 Installing Ansible dependencies..."
	@ansible-galaxy install -r ansible/requirements.yml --force
	@echo "✅ Development environment setup complete!"
	@echo "   Run 'make lint' to check code quality"
	@echo "   Run 'make deploy-core' to deploy core infrastructure"

check-tools: ## Verify required tools are installed
	@echo "🔍 Checking required tools..."
	@command -v python3 >/dev/null 2>&1 || { echo "❌ python3 is required but not installed"; exit 1; }
	@command -v pip3 >/dev/null 2>&1 || { echo "❌ pip3 is required but not installed"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "❌ docker is required but not installed"; exit 1; }
	@command -v op >/dev/null 2>&1 || { echo "❌ 1password CLI (op) is required but not installed"; exit 1; }
	@echo "✅ All required tools are installed"

# =============================================================================
# Code Quality
# =============================================================================

lint: ## Run all linting checks with fix (ansible-lint + yamllint)
	@echo "🔍 Running ansible-lint..."
	@cd ansible && ansible-lint --fix
	@echo "🔍 Running yamllint..."
	@yamllint ansible/ .github/workflows/
	@echo "✅ All linting checks passed!"

# =============================================================================
# Infrastructure Deployment
# =============================================================================

deploy-bootstrap: ## Bootstrap all nodes (install Docker, Tailscale)
	@echo "🚀 Bootstrapping infrastructure nodes..."
	./scripts/deploy.sh bootstrap

deploy-core: ## Deploy Komodo Core (MongoDB + Core)
	@echo "🚀 Deploying Komodo Core..."
	./scripts/deploy.sh core

deploy-init-auth: ## Initialize API keys automatically
	@echo "🔑 Initializing Komodo authentication and API keys..."
	./scripts/deploy.sh init-auth

deploy-periphery: ## Deploy Komodo Periphery nodes
	@echo "🚀 Deploying Komodo Periphery nodes..."
	./scripts/deploy.sh periphery

deploy-periphery-update: ## Update periphery nodes to latest version
	@echo "🔄 Updating Komodo Periphery to latest version..."
	./scripts/deploy.sh periphery-update

deploy-periphery-update-version: ## Update periphery to specific version (usage: make deploy-periphery-update-version VERSION=v1.18.4)
	@if [ -z "$(VERSION)" ]; then \
		echo "❌ VERSION parameter required. Usage: make deploy-periphery-update-version VERSION=v1.18.4"; \
		exit 1; \
	fi
	@echo "🔄 Updating Komodo Periphery to version $(VERSION)..."
	./scripts/deploy.sh periphery-update-version $(VERSION)

deploy-periphery-uninstall: ## Remove periphery services
	@echo "🗑️  Uninstalling Komodo Periphery..."
	./scripts/deploy.sh periphery-uninstall

deploy-bootstrap-op: ## Bootstrap Komodo variables for komodo-op
	@echo "🔧 Bootstrapping komodo-op configuration..."
	./scripts/deploy.sh bootstrap-komodo-op

deploy-syncs: ## Setup GitOps syncs and webhooks
	@echo "🔄 Setting up GitOps syncs..."
	./scripts/deploy.sh setup-syncs

deploy-full: ## Complete deployment (bootstrap + core + auth + periphery)
	@echo "🚀 Running complete Komodo infrastructure deployment..."
	./scripts/deploy.sh full

deploy-all: deploy-bootstrap deploy-core deploy-init-auth deploy-periphery deploy-bootstrap-op deploy-syncs ## Step-by-step complete deployment

# =============================================================================
# Status and Information
# =============================================================================

status: ## Check status of Komodo services
	@echo "🔍 Checking Komodo service status..."
	./scripts/deploy.sh status

info: ## Show deployment information
	@echo "📋 Showing deployment information..."
	./scripts/deploy.sh info

check: ## Check connectivity to all hosts
	@echo "🔍 Checking connectivity..."
	./scripts/deploy.sh check


# =============================================================================
# Maintenance Commands
# =============================================================================

clean: ## Clean up temporary files and caches
	@echo "🧹 Cleaning up temporary files..."
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true
	rm -rf .ansible/
	rm -rf ansible/.ansible/
	@echo "✅ Cleanup complete!"

update-deps: ## Update development dependencies
	@echo "📦 Updating development dependencies..."
	pip3 install --upgrade -r requirements-dev.txt
	ansible-galaxy install -r ansible/requirements.yml --force
	@echo "✅ Dependencies updated!"

# =============================================================================
# Environment Information
# =============================================================================

env: ## Show environment and configuration information
	@echo "🔧 Environment & Configuration"
	@echo "============================="
	@echo "OS: $$(uname -s) $$(uname -m)"
	@echo "Shell: $$SHELL"
	@echo "Working Directory: $$(pwd)"
	@echo "Git Branch: $$(git branch --show-current 2>/dev/null || echo 'Not a git repository')"
	@echo
	@echo "Tool Versions:"
	@echo "  Python: $$(python3 --version)"
	@echo "  Ansible: $$(ansible --version | head -n1)"
	@echo "  Docker: $$(docker --version)"
	@echo "  1Password CLI: $$(op --version)"
	@echo "  Git: $$(git --version)"
	@echo

# =============================================================================
# Debugging and Development
# =============================================================================

debug: ## Run ansible-playbook with debug output (usage: make debug PLAYBOOK=site.yml)
	@if [ -z "$(PLAYBOOK)" ]; then \
		echo "❌ PLAYBOOK parameter required. Usage: make debug PLAYBOOK=site.yml"; \
		exit 1; \
	fi
	@echo "🐛 Running $(PLAYBOOK) in debug mode..."
	ansible-playbook -vvv -i ansible/inventory/hosts.yml ansible/playbooks/$(PLAYBOOK)