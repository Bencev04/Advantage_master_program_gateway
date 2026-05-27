# Gateway Agent Guide

Read the root `AGENTS.md` before changing this repository.

This repository owns the Advantage Master program HTTP edge. It uses Traefik for subdomain routing between active subsystems during local Docker development and establishes conventions that can later be consumed by the deployment/Kubernetes repo.

## Ownership

Gateway owns:

- Browser-facing subdomain and path routing.
- Reverse proxy configuration for Calendar, Identity, Sales, Forwarding, and Fleet.
- Shared edge headers, security headers, size limits, and timeout defaults.
- Local full-system routing documentation.
- Future edge compatibility notes for production deployment.

Gateway does not own:

- Kubernetes manifests, Helm charts, Kustomize overlays, or rollout automation. Those belong in `Advantage_master_program_depl/` later.
- Users, tenants, roles, sessions, token issuance, password reset, or service access. Those belong to Identity.
- Business workflows, commands, write models, or read-model schemas.
- Kafka event envelope/schema/topic standards. Those belong to `Advantage_master_program_events/`.
- Service-to-service domain communication. Cross-system facts should use Kafka-compatible events, not gateway HTTP calls.
- Projects routing until Projects is intentionally brought into the shared Identity/tenancy/events model.

## Routing Rules

Use Traefik, not Nginx, for this program gateway.

Local subdomains:

- `calendar.advantage.localhost` and `hub.advantage.localhost` route to Calendar frontend.
- `calendar.advantage.localhost/api/*` routes to Calendar API.
- `identity.advantage.localhost` routes to Identity.
- `sales.advantage.localhost` routes to the Sales React app.
- `sales.advantage.localhost/api/sales/*` routes to the Sales API facade.
- `forwarding.advantage.localhost` routes to Forwarding.
- `fleet.advantage.localhost` routes to Fleet.

Do not add Projects routes unless the task explicitly says Projects has been brought into the first integration loop.

## Auth And SSO

- The gateway may terminate TLS and route traffic, but apps must still validate Identity-issued tokens or sessions server-side.
- Do not trust identity, tenant, role, or service-access values from frontend-only headers.
- Prefer shared cookie or OIDC-compatible browser SSO once production domains are set.
- The gateway must not use Kafka for live auth and must not make authorization decisions based on async events.

## Events And Inter-System Connectivity

- Kafka-compatible events are the default for cross-system business facts and projections.
- Use the `Advantage_master_program_events/` contracts for envelope, topic, outbox, inbox, and saga conventions.
- HTTP through the gateway is for user/browser traffic and rare synchronous request-time needs such as auth redirects, not general domain coupling.

## Local Commands

From this repository root:

- Validate config: `docker compose config`
- Start current local system: `.\scripts\up-local.ps1 -Build`
- Stop current local system: `.\scripts\down-local.ps1`
- Check local system status: `.\scripts\status-local.ps1`
- Sync shared local env into per-repo env files: `.\scripts\sync-env.ps1`
- Run current local migrations: `.\scripts\migrate-local.ps1`
- Pull, commit, and push sibling repos: `.\scripts\git-sync-repos.ps1 -CommitMessage "chore: sync local changes"`
- Start gateway only: `docker compose up -d`
- Stop gateway only: `docker compose down`
- Dashboard: `http://localhost:8088`

The scripts intentionally orchestrate each repository's own compose file rather than merging all services into one large compose file. This keeps database volumes, environment files, and service ownership inside each bounded context while still giving developers one gateway-owned command.

`git-sync-repos.ps1` is a local convenience script for multi-repo git hygiene. It discovers sibling `Advantage_master_program_*` git repositories, pulls with `--rebase --autostash`, commits dirty worktrees with the supplied message, and pushes the current branch. Use `-DryRun` before broad runs when unsure.

## Environment And Migrations

- `system.env.example` is the committed template for shared local values.
- `system.local.env` is ignored by git and is the developer's local shared source.
- `scripts/sync-env.ps1` writes compatible `.env` files into active repos.
- Individual repo `.env` files remain valid for standalone repo testing; running sync again may overwrite shared keys from `system.local.env`.
- Gateway may orchestrate migration commands, but migration files and schema ownership stay in the owning repo.
