# Local System Startup

Use the gateway repository as the local system entrypoint. Each bounded context keeps its own `docker-compose.yml`, database volumes, and `.env`, while the gateway scripts start them in the correct order.

This is preferred over one giant compose file right now because the services are still independent repositories with separate environment files and migration ownership.

The shared local environment source is `system.local.env` in this gateway repo.
It is generated from `system.env.example` and synced into per-repository `.env`
files before startup.

## Start Everything Available

From `Advantage_master_program_gateway/`:

```powershell
.\scripts\up-local.ps1 -Build
```

The script starts:

- Events/Redpanda
- Identity
- Sales
- Calendar
- Gateway

Forwarding and Fleet are routed by the gateway but currently have no compose stacks to start.

## Stop Everything

```powershell
.\scripts\down-local.ps1
```

To remove Docker volumes as well:

```powershell
.\scripts\down-local.ps1 -Volumes
```

## Check Status

```powershell
.\scripts\status-local.ps1
```

## Sync Environment Only

```powershell
.\scripts\sync-env.ps1
```

## Run Migrations

Start the stacks first, then run:

```powershell
.\scripts\migrate-local.ps1
```

This runs Identity and Sales migrations through their own containers. Calendar is
skipped until its read-model Alembic setup exists.

## Useful URLs

- Gateway dashboard: `http://localhost:8088/dashboard/`
- Calendar: `http://calendar.advantage.localhost`
- Calendar alias: `http://hub.advantage.localhost`
- Identity: `http://identity.advantage.localhost`
- Sales React app: `http://sales.advantage.localhost`
- Sales API facade: `http://sales.advantage.localhost/api/sales/health`
- Redpanda Kafka API: `localhost:9092`

## Notes

- The startup script creates `system.local.env` when missing and syncs selected shared keys into active repo `.env` files.
- The generated `.env` values are only for local development. Replace them before non-local use.
- Browser/user traffic should go through the gateway subdomains.
- Sales uses Traefik -> React on `5175` and Traefik -> `sales_api` on `18080`; the old Sales nginx entrypoint is deprecated and not part of the default Sales compose stack.
- Inter-system business communication should use Kafka-compatible events through the Events repo contracts, not gateway HTTP calls.
