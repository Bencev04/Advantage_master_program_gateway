# CLAUDE.md — Gateway

> **Read `AGENTS.md` first**, and `docs/local-system.md` / `docs/routing.md` / `docs/env-and-migrations.md`. This file adds Claude-specific working notes only.

## Quick orientation

- **Stack:** Traefik v3 reverse proxy + Docker Compose + PowerShell orchestration scripts. No application code.
- **Owns:** Browser-facing subdomain and path routing for the Master Program apps, shared edge headers/timeouts/size limits, and the workspace bootstrap + multi-repo lifecycle scripts that bring the local system up/down.
- **Does NOT own:** Business logic, auth/token validation (apps validate Identity tokens server-side), event contracts (Events repo), Kubernetes/Helm rollout automation (Depl repo). Projects (TMS) is intentionally not routed here.

## Subdomain routing (Traefik, local dev)

- `calendar.advantage.localhost`, `hub.advantage.localhost` → Calendar UI (5174)
- `calendar.advantage.localhost/api/*` → Calendar API (8010)
- `identity.advantage.localhost` → Identity (18101); admin SPA mounts at `/admin/*` (5182)
- `sales.advantage.localhost` → Sales React app (5175)
- `sales.advantage.localhost/api/sales/*` → Sales API facade (18080)
- `forwarding.advantage.localhost` → Forwarding (5180) — routed but no compose stack yet
- `fleet.advantage.localhost` → Fleet (5181) — routed but no compose stack yet
- `grafana.advantage.localhost` → Grafana (3000, monitoring stack in the Observability repo)
- Traefik dashboard: `http://localhost:8088/dashboard/`
- Traefik Prometheus metrics: `http://localhost:8082/metrics` (dedicated `metrics` entrypoint; scraped by the monitoring stack). Prometheus/Alertmanager UIs are deliberately NOT routed (no auth) — use `localhost:9090`/`localhost:9093`.

## Commands you'll actually run

All scripts are PowerShell. Run from this repo's root.

```powershell
.\scripts\pull-repos.ps1            # clone/pull sibling repos (infers GH owner from origin)
.\scripts\sync-env.ps1              # write per-repo .env files from system.local.env
.\scripts\up-local.ps1 -Build       # start the full local stack in dependency order
.\scripts\status-local.ps1
.\scripts\migrate-local.ps1         # run Identity + Sales migrations
.\scripts\down-local.ps1            # ( -Volumes to also drop DB volumes )
.\scripts\git-sync-repos.ps1 -CommitMessage "chore: sync local changes"

docker compose up -d                # gateway only
docker compose config               # validate Traefik labels/config
```

## Skills that apply here

- **None directly.** Gateway is infra-only. When skill changes affect routing (a new subdomain, a new app port), make sure `traefik/dynamic/` and the scripts pick them up.

## Top gotchas

- **PowerShell-only.** All scripts use PowerShell idioms (`-Param`, `$env:`, backtick). Don't expect bash/WSL equivalents — they don't exist.
- **`pull-repos.ps1` exit codes are honest.** If it exits 1, at least one git command actually failed — don't dismiss it as PowerShell-stderr-noise. Read the per-repo "failed:" lines at the bottom of the run.
- **No top-level git repo.** The `Advantage_master` workspace root is a folder, not a monorepo. Each `Advantage_master_program_*` folder has its own `.git` and lifecycle. `pull-repos.ps1` is how you keep them in sync; it intentionally skips Gateway itself unless `-IncludeGateway` is passed.
- **`sync-env.ps1` overwrites per-repo `.env`.** Shared values live in `system.local.env` (git-ignored, generated from `system.env.example`). Edits made directly in a sibling's `.env` are lost the next time sync runs.
- **Traefik does routing only.** No token validation, no role enforcement, no Kafka. Don't push auth decisions into Traefik middlewares; apps must verify Identity-issued tokens themselves.
- **`forwarding.*.localhost` / `fleet.*.localhost` have routes but no upstream yet.** Empty scaffold repos; expect 502/connection refused when you hit them.
- **Each repo's compose file is the source of truth for its containers.** `up-local.ps1` orchestrates them in order — it does **not** merge them into one giant compose file. Don't add app services here; add them in the owning repo.
- **`*.localhost` should auto-resolve to 127.0.0.1.** If it doesn't on your machine, add hosts-file entries; don't change Traefik to listen on a different name.
- **Projects (TMS) is deliberately out of scope.** Do not add `projects.advantage.localhost` until the TMS is intentionally aligned with shared Identity/events.
