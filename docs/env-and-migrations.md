# Environment And Migrations

The local development system uses a layered environment model.

## Layers

| Layer | File | Git status | Purpose |
| --- | --- | --- | --- |
| System template | `system.env.example` | committed | Documents shared local values and safe placeholders. |
| System local source | `system.local.env` | ignored | Developer-specific local shared values. |
| Repo template | each repo `.env.example` | committed | Documents standalone repo defaults and required keys. |
| Repo local env | each repo `.env` | ignored | What each repo's Docker Compose reads. |

Use `system.local.env` when running the program as one local system. Use an
individual repo `.env` when testing a repo in isolation.

## Shared Values

These should normally be shared across the local system:

- `SYSTEM_ENVIRONMENT`
- `SYSTEM_LOG_LEVEL`
- `SYSTEM_SECRET_KEY`
- `SYSTEM_JWT_ALGORITHM`
- `SYSTEM_ACCESS_TOKEN_EXPIRE_MINUTES`
- `SYSTEM_ACCESS_TOKEN_COOKIE_NAME`
- `SYSTEM_POSTGRES_PASSWORD` for local-only database containers
- gateway hosts and browser app URLs
- `KAFKA_BOOTSTRAP_SERVERS`

These stay service-specific:

- database names and service database users
- internal Docker service URLs
- SMTP, S3, and third-party credentials
- service-only feature flags
- migration locations and schema ownership

## Sync Flow

Run from the gateway repo:

```powershell
.\scripts\sync-env.ps1
```

The script creates `system.local.env` when missing, generates local-only shared
secrets, and writes compatible `.env` files for Gateway, Identity, Sales, and
Calendar.

Running sync again may overwrite shared keys in the repo `.env` files. Keep
standalone repo-only overrides in keys that are not managed by the sync script,
or temporarily edit the repo `.env` after syncing.

## Migration Flow

Migrations remain owned by each bounded context. The gateway only orchestrates
commands for convenience.

Run after containers are up:

```powershell
.\scripts\migrate-local.ps1
```

Current migration commands:

- Identity: `db/identity/alembic.ini` through the `identity_dba` container.
- Sales quotation DB: `db/quotation/alembic.ini` through the `quotation_dba` container. Quotation is the only Sales database; the former Sales user DB (`db/user`/`user_dba`) was removed.
- Calendar: skipped until Calendar read-model migrations are added.

Do not create cross-service migrations or shared database schemas from the
gateway. Each service owns its own schema, migrations, and data contract.