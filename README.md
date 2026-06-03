# Advantage Master Gateway

This repository owns the program-level HTTP edge for local development and the future shared entrypoint for Advantage Master apps. It uses Traefik rather than Nginx.

The gateway routes browser and API traffic by subdomain. It does not own business workflows, authentication state, service permissions, event contracts, or service-to-service domain communication.

## Local Subdomains

The first gateway routes are:

| Host | Target | Current local target |
| --- | --- | --- |
| `calendar.advantage.localhost` | Calendar Operations Hub frontend | `http://host.docker.internal:5174` |
| `hub.advantage.localhost` | Calendar Operations Hub frontend alias | `http://host.docker.internal:5174` |
| `calendar.advantage.localhost/api/*` | Calendar API | `http://host.docker.internal:8010` |
| `identity.advantage.localhost` | Identity auth/API entrypoint | `http://host.docker.internal:18101` |
| `sales.advantage.localhost` | Sales React browser app | `http://host.docker.internal:5175` |
| `sales.advantage.localhost/api/sales/*` | Sales API facade | `http://host.docker.internal:18080` |
| `forwarding.advantage.localhost` | Forwarding app/API placeholder | `http://host.docker.internal:5180` |
| `fleet.advantage.localhost` | Fleet app/API placeholder | `http://host.docker.internal:5181` |

Projects is intentionally not routed through this gateway yet. It stays outside the first Calendar/Sales/Identity/Forwarding/Fleet integration loop until it is deliberately aligned with shared Identity, tenancy, and events.

## Local Startup

After manually cloning this gateway repository, pull the rest of the sibling
repositories from the same GitHub owner/organization:

```powershell
.\scripts\pull-repos.ps1
```

The script clones missing Advantage repositories into the workspace folder next
to Gateway and pulls existing ones with `git pull --rebase --autostash`. Gateway
itself is skipped by default so the script does not update itself while it is
running. Preview first with:

```powershell
.\scripts\pull-repos.ps1 -DryRun
```

Start everything currently available from this gateway repository:

```powershell
.\scripts\up-local.ps1 -Build
```

This command first syncs `system.local.env` into each active repository's `.env`
file. If `system.local.env` does not exist, it is created from
`system.env.example` with local-only generated secrets.

Check status:

```powershell
.\scripts\status-local.ps1
```

Stop everything:

```powershell
.\scripts\down-local.ps1
```

The scripts start Events/Redpanda, Observability, Identity, Sales, Calendar, and
the gateway in the right order. Forwarding and Fleet are routed but currently have
no compose stacks to start.

Sync environment files without starting containers:

```powershell
.\scripts\sync-env.ps1
```

Run current database migrations after the relevant containers are up:

```powershell
.\scripts\migrate-local.ps1
```

Pull, commit, and push all sibling Advantage repositories that have a `.git`
folder:

```powershell
.\scripts\git-sync-repos.ps1 -CommitMessage "chore: sync local changes"
```

Preview the operations without changing repositories:

```powershell
.\scripts\git-sync-repos.ps1 -DryRun
```

Target only a couple of repositories when needed:

```powershell
.\scripts\git-sync-repos.ps1 -Message "chore: sync gateway and sales" -Only Advantage_master_program_gateway,Advantage_master_program_sales
```

The script discovers `Advantage_master_program_*` repositories under the
workspace root, runs `git pull --rebase --autostash`, commits only repositories
with local changes, and pushes the current branch. Use `-RepoFolders` to target
specific repos, or `-SkipPull` / `-SkipPush` for partial workflows.

To start only the gateway, run:

```powershell
docker compose up -d
```

Gateway URLs:

- Calendar: `http://calendar.advantage.localhost`
- Calendar alias: `http://hub.advantage.localhost`
- Identity: `http://identity.advantage.localhost`
- Sales: `http://sales.advantage.localhost`
- Forwarding: `http://forwarding.advantage.localhost`
- Fleet: `http://fleet.advantage.localhost`
- Traefik dashboard: `http://localhost:8088`

If `*.localhost` does not resolve on a machine, add these host entries to the OS hosts file, pointing each name to `127.0.0.1`.

See `docs/local-system.md` and `docs/env-and-migrations.md` for the full local-system runbook.

## Communication Boundary

- Browser/user HTTP traffic goes through this gateway.
- Live login, token issuing, session validation, and permission checks stay with Identity and each app's backend guard.
- Cross-system business facts use Kafka-compatible events through `Advantage_master_program_events/`.
- Calendar projections consume events; they do not call private databases.
- The gateway does not replace Kafka, the Events repo, or direct request-time auth validation.

## Current Tech Choice

Traefik v3 is used because it is Docker-friendly now and maps cleanly to Kubernetes ingress/gateway patterns later. `Advantage_master_program_depl/` should own Kubernetes/Helm/Kustomize/deployment orchestration when the platform grows to that scale.
