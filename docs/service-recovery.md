# Service Reliability And Recovery Runbook

This runbook defines the intended steady state and the safe migration order for the homelab service layer.
It does not authorize a live deployment by itself.

## Steady-state design

`homelab-vps` is the stable control and ingress node.
It runs Caddy, Komodo Core, Authentik, Uptime Kuma, AutoKuma, ntfy, Homepage, and Beszel.

Caddy publishes public HTTP and HTTPS.
The other VPS services use the private `vps-ingress` Docker network and do not bind their application ports to a host address.
Komodo Core also publishes port `9120` on localhost for host-level recovery checks.
MongoDB remains private to the Komodo Compose network.

One AutoKuma instance on the VPS reconciles Uptime Kuma monitors from all Docker nodes.
The VPS proxy is private on `monitoring-control`.
Remote proxies publish a read-only Docker API that the host `DOCKER-USER` firewall permits only from the VPS Tailscale address.

Remote host communication uses full MagicDNS names.
No container binds to a Tailscale address, so a restart does not require `tailscaled` to win a startup race.

## Recovery order

Recover services in this order:

1. Host networking, Docker, and Tailscale.
2. VPS private Docker networks and Caddy.
3. Komodo MongoDB and Core.
4. Authentik.
5. Uptime Kuma, ntfy, and AutoKuma.
6. Homepage, Beszel, and normal application stacks.

Run the read-only recovery check after any host restart:

```bash
make recovery-check
```

The check fails on stopped Docker, stopped Tailscale, failed systemd units, unhealthy containers, or an unhealthy local Core endpoint.

## First baseline rollout

Before applying anything, capture current container status, free space, memory, swap, firewall rules, and service endpoints.
Back up the Komodo MongoDB data and the Authentik PostgreSQL database.

Apply the host reliability baseline before deploying stacks that require the shared networks:

```bash
make reliability-baseline
make security-baseline
make security-check
```

Deploy remote Docker proxy changes before starting centralized AutoKuma.
Verify each proxy from the VPS and verify that another source cannot reach it.

Back up the Uptime Kuma data directory before changing reconcilers.
Stop the old per-node AutoKuma containers before starting centralized AutoKuma so two reconcilers never manage the same monitor IDs concurrently.
Do not delete the old Komodo resources yet.

Deploy Uptime Kuma, ntfy, and centralized AutoKuma as a unit.
Confirm that AutoKuma can log in, enumerate all four Docker hosts, create its static ntfy provider, and reconcile labeled monitors.
Compare monitors tagged by the old per-node reconcilers with the centralized set and remove any superseded duplicates only after endpoint coverage matches.
Delete the old per-node AutoKuma resources from Komodo after the central reconciler and one real ntfy alert both pass.

## Authentik 2026.5 migration

The 2026.5 stack removes Redis and uses PostgreSQL for task transport.
It also uses the consolidated `/data` directory.

Before redeploying Authentik:

1. Dump the PostgreSQL database to a file outside the Compose project.
2. Copy the existing `authentik/media` contents to `authentik/data/media` without deleting the source.
3. Ensure the data, certificate, and template directories are writable by Authentik UID `1000`.
4. Record the currently running image tag and Compose definition for rollback.
5. Deploy the database, server, and worker together.

Verify `/-/health/live/`, one local login, one OIDC login, email delivery, and the Caddy forward-auth path.
Keep the old Redis volume and media directory until those checks pass and a second PostgreSQL backup succeeds.

## Komodo Core migration

The inventory keeps the current Core host in `legacy_core` and the VPS target in `core`.
The migration playbook is deliberately gated and stops legacy Core before exporting MongoDB so the restored database cannot diverge.
The reviewed VPS Caddy definition must be deployed first while legacy Core is available.
Its ordered upstream pool uses legacy Core until the verified VPS alias appears, then prefers the VPS automatically.

This is a one-off cutover rather than routine maintenance, so it has no Make target.
Run it directly, and only during an approved maintenance window:

```bash
make run PLAYBOOK=migrate_core.yml OPTS="-e confirm_komodo_core_migration=MIGRATE"
```

The playbook refuses to run without that variable, and also asserts that exactly one distinct `legacy_core` and `core` host exist.
That second assertion is what makes a repeat run safe: once the cutover is done and the groups no longer describe a pending migration, the playbook stops on its own.
Delete `ansible/playbooks/migrate_core.yml` once the cutover is complete and verified.

The playbook performs these operations:

1. Stops legacy Core while leaving legacy MongoDB running.
2. Streams a compressed MongoDB archive to the old host and fetches it to the controller.
3. Deploys target MongoDB and Core on the VPS private network.
4. Stops target Core, restores the archive with `--drop`, and restarts target Core.
5. Verifies the target localhost health endpoint.
6. Restarts legacy Core automatically if target restoration or health verification fails.

After success, verify that Caddy selected the VPS upstream, then test the public Komodo URL, API authentication, resource syncs, and every Periphery connection.
Legacy Core remains stopped but intact until rollback testing and a fresh target backup pass.

## Rollback rules

Never delete a source volume during the same maintenance window that moves it.
Never reuse a failed target database as the next migration source.
Never consider a container health check sufficient for identity, notification, or control-plane recovery.

If the Core cutover fails, stop target Core, restart legacy Core, restore the previous Caddy route, and validate the old public endpoint before investigating the target.
If the Authentik cutover fails, restore the previous Compose definition and PostgreSQL backup, then point Caddy back to the previous healthy server.

## GitOps boundary

Komodo can deploy only repository revisions it can fetch.
A local commit in `komodo-app-stacks` is not deployable by resource sync until it is pushed.
Do not work around that boundary by copying unreviewed Compose files to production.
