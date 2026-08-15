# Homelab Security Hardening Runbook

Point-in-time implementation notes: `2026-06-14 Europe/Budapest`.

This runbook tracks the pragmatic baseline hardening path. It avoids heavy
zero-trust or VLAN redesign and focuses on repeatable controls that reduce
obvious exposure without breaking normal homelab workflows.

## Source Of Truth

- Host baseline and checks live in this repository.
- Application stack port bindings live in the adjacent `komodo-app-stacks`
  repository.
- Runtime convergence still requires running the relevant Ansible playbooks and
  redeploying affected Komodo stacks.

## Commands

Install or refresh the external Ansible roles before applying the baseline:

```bash
make setup
```

Check the current security baseline without changing hosts:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/ansible-local make security-check
```

Apply the Linux host baseline:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/ansible-local make security-baseline
```

The baseline playbook:

- delegates generic OpenSSH hardening, fail2ban, and unattended updates to
  `geerlingguy.security`;
- keeps root key-only break-glass access with
  `PermitRootLogin prohibit-password` instead of the role default `no`;
- enables unattended Debian security updates on the non-OpenSSH Raspberry Pi
  through the imported role's Debian autoupdate task path;
- manages the `homelab-vps` nftables input overlay as a systemd service.

## Expected Follow-Up

After applying host hardening and redeploying stack changes, verify:

- `docker` no longer exposes Caddy admin `2019`, MongoDB `27017`, or
  `socky_proxy` `12375` on all interfaces;
- `docker-seq` no longer exposes Caddy admin `2019` or `socky_proxy` on all
  interfaces;
- `homelab-vps` still exposes only intentional public HTTP/HTTPS and Tailscale
  traffic outside the Tailnet;
- Proxmox firewalls are enabled and PBS storage is active on both Proxmox
  hosts;
- root Proxmox MFA still has both TOTP and WebAuthn.

## Restore And Alert Proof

Security is not complete until recovery and alerting are proven:

- run one PBS restore validation for a non-critical home guest;
- run one PBS restore validation for a non-critical Sequoia guest;
- trigger a real Uptime Kuma alert and confirm Ntfy delivery;
- document the restore target, timestamp, and outcome in a dated restore note.

## Known Intentional Tradeoffs

- Root SSH is kept as key-only break-glass instead of being removed.
- Caddy remains public on `homelab-vps` for HTTP/HTTPS ingress.
- LAN access is preserved for normal service use; admin/backend listeners are
  the main cleanup target.
- Authentik/OIDC should not be treated as a working control until an actual
  login path is verified end to end.
