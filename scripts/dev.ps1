#requires -Version 5.1
<#
.SYNOPSIS
    Single entry point for the Advantage Master local stack.

.DESCRIPTION
    Wraps sync-env / up-local / down-local / status-local / migrate-local so day-to-day
    bring-up/bring-down is one command. Each subcommand forwards remaining args
    to the underlying script.

.PARAMETER Action
    up      — sync env, start all services (add -Build for image rebuild).
    down    — stop all services (add -Volumes to drop DB data too).
    restart — down then up.
    status  — show docker compose ps for every service.
    sync    — refresh per-repo .env files from system.local.env only.
    migrate — explicit alembic upgrade head against identity + sales DBs.
              (Normal lifespan already keeps schema in sync — only useful
              after manually applying a new migration file.)

.EXAMPLE
    .\scripts\dev.ps1 up
    .\scripts\dev.ps1 up -Build
    .\scripts\dev.ps1 down
    .\scripts\dev.ps1 down -Volumes
    .\scripts\dev.ps1 restart
    .\scripts\dev.ps1 status
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('up','down','restart','status','sync','migrate')]
    [string]$Action = 'up',

    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$Rest
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot

function Invoke-Sub {
    param([string]$Name, [object[]]$Args)
    $path = Join-Path $scriptDir "$Name.ps1"
    if (-not (Test-Path $path)) { throw "Missing helper script: $path" }
    if ($Args) { & $path @Args } else { & $path }
    if ($LASTEXITCODE -ne 0) { throw "$Name.ps1 exited with code $LASTEXITCODE" }
}

switch ($Action) {
    'up'      { Invoke-Sub -Name 'up-local'      -Args $Rest }
    'down'    { Invoke-Sub -Name 'down-local'    -Args $Rest }
    'restart' {
        Invoke-Sub -Name 'down-local' -Args $Rest
        Invoke-Sub -Name 'up-local'   -Args $Rest
    }
    'status'  { Invoke-Sub -Name 'status-local'  -Args $Rest }
    'sync'    { Invoke-Sub -Name 'sync-env'      -Args $Rest }
    'migrate' { Invoke-Sub -Name 'migrate-local' -Args $Rest }
}
