# CLAUDE.md

Ansible repository for a Komodo-based homelab. Public and forked: every commit is published for good.

## Where knowledge lives

Read in this order; each layer answers a different question.

1. Obsidian note `Agentic/Homelab Overview` (operator machine only): what is true right now.
2. `private/` (gitignored, operator machine only): dated audit evidence, plans with rollback steps, findings.
3. This repository: how to rebuild it. `docs/architecture.md` explains the shape without naming a deployment.

Forks have only layer 3. Anything an agent needs to operate on this repository generically belongs in layer 3.

## Shape versus state

Committed files hold reusable shape: roles, playbooks, `group_vars/` defaults, `hosts.example.yml`, docs.
Operator state stays out of git: `ansible/inventory/hosts.yml`, `private/`, `.claude/settings.local.json`.
Secrets are 1Password lookups against `homelab_op_vault`; a value never appears in a file, a log excerpt, or a commit message.
Hosts are addressed by MagicDNS short name. Tailscale addresses, the tailnet domain, and public IPs stay out of the repository.

## Working here

- `make lint` and `gitleaks git` pass before a commit. Both run in CI.
- Runtime checks are read-only unless the task is a change: `make status`, `make recovery-check`, `make security-check`, `ansible-inventory --graph`.
- After verifying or changing live infrastructure on the operator machine, update the Obsidian overview.
- Comments describe current state and rationale; history belongs to git.
- Long Markdown: one sentence per line.

## Gotchas no config confesses

- Manual compose operations on Ansible-managed stacks need `-p <komodo_compose_project_name> --env-file compose.env`; the defaults silently match nothing.
- `komodo_periphery_version: "core"` tracks whatever Core reports; `make periphery-upgrade` re-aligns after a Core bump.
- `legacy_core` exists only for `migrate_core.yml`; keep the group until the old Core's volumes are deliberately deleted.
