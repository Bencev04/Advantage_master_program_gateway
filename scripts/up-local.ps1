param(
    [switch]$Build,
    [switch]$SkipEvents,
    [switch]$SkipObservability,
    [switch]$SkipIdentity,
    [switch]$SkipSales,
    [switch]$SkipCalendar,
    [switch]$SkipGateway
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

$syncEnvScript = Join-Path $PSScriptRoot "sync-env.ps1"
if (Test-Path $syncEnvScript) {
    & $syncEnvScript
}

function Set-EnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $lines = @()
    if (Test-Path $Path) {
        $lines = Get-Content $Path
    }

    $found = $false
    $updated = foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Key))=") {
            $found = $true
            "$Key=$Value"
        }
        else {
            $line
        }
    }

    if (-not $found) {
        $updated += "$Key=$Value"
    }

    Set-Content -Path $Path -Value $updated -Encoding UTF8
}

function Ensure-DevEnv {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$SetSharedAuthSecret,
        [switch]$SetDatabasePassword
    )

    $envPath = Join-Path $RepoPath ".env"
    $examplePath = Join-Path $RepoPath ".env.example"

    if (-not (Test-Path $envPath)) {
        if (-not (Test-Path $examplePath)) {
            Write-Warning "$Name has no .env or .env.example. Continuing without creating one."
            return
        }

        Copy-Item $examplePath $envPath
        Write-Host "Created $Name .env from .env.example for local development."
    }

    if ($SetSharedAuthSecret) {
        Set-EnvValue -Path $envPath -Key "SECRET_KEY" -Value $sharedDevSecret
    }

    if ($SetDatabasePassword) {
        Set-EnvValue -Path $envPath -Key "POSTGRES_PASSWORD" -Value $sharedDevPassword
    }
}

function Invoke-RepoComposeUp {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Folder,
        [switch]$UseBuild
    )

    $repoPath = Join-Path $workspaceRoot $Folder
    if (-not (Test-Path (Join-Path $repoPath "docker-compose.yml"))) {
        Write-Warning "$Name has no docker-compose.yml at $repoPath. Skipping."
        return
    }

    Write-Host "Starting $Name..."
    Push-Location $repoPath
    try {
        $composeArgs = @("compose", "up", "-d", "--remove-orphans")
        if ($UseBuild) {
            $composeArgs += "--build"
        }

        & docker @composeArgs
        if ($LASTEXITCODE -ne 0) {
            throw "$Name docker compose up failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

if (-not $SkipIdentity) {
    Ensure-DevEnv -RepoPath (Join-Path $workspaceRoot "Advantage_master_program_identity") -Name "Identity"
}

if (-not $SkipObservability) {
    Ensure-DevEnv -RepoPath (Join-Path $workspaceRoot "Advantage_master_program_observability") -Name "Observability"
}

if (-not $SkipSales) {
    Ensure-DevEnv -RepoPath (Join-Path $workspaceRoot "Advantage_master_program_sales") -Name "Sales"
}

if (-not $SkipCalendar) {
    Ensure-DevEnv -RepoPath (Join-Path $workspaceRoot "Advantage_master_program_calender") -Name "Calendar"
}

if (-not $SkipGateway) {
    Ensure-DevEnv -RepoPath (Join-Path $workspaceRoot "Advantage_master_program_gateway") -Name "Gateway"
}

if (-not $SkipEvents) {
    Invoke-RepoComposeUp -Name "Events/Redpanda" -Folder "Advantage_master_program_events"
}

if (-not $SkipObservability) {
    Invoke-RepoComposeUp -Name "Observability" -Folder "Advantage_master_program_observability" -UseBuild:$Build
}

if (-not $SkipIdentity) {
    Invoke-RepoComposeUp -Name "Identity" -Folder "Advantage_master_program_identity" -UseBuild:$Build
}

if (-not $SkipSales) {
    Invoke-RepoComposeUp -Name "Sales" -Folder "Advantage_master_program_sales" -UseBuild:$Build
}

if (-not $SkipCalendar) {
    Invoke-RepoComposeUp -Name "Calendar" -Folder "Advantage_master_program_calender" -UseBuild:$Build
}

if (-not $SkipGateway) {
    Invoke-RepoComposeUp -Name "Gateway" -Folder "Advantage_master_program_gateway"
}

Write-Host ""
Write-Host "Advantage Master local system start requested."
Write-Host "Gateway dashboard: http://localhost:8088/dashboard/"
Write-Host "Calendar:          http://calendar.advantage.localhost"
Write-Host "Hub alias:         http://hub.advantage.localhost"
Write-Host "Identity:          http://identity.advantage.localhost"
Write-Host "Sales:             http://sales.advantage.localhost"
Write-Host "Audit query API:   http://localhost:18130 (Observability)"
Write-Host "Forwarding:        http://forwarding.advantage.localhost (placeholder until repo has a compose stack)"
Write-Host "Fleet:             http://fleet.advantage.localhost (placeholder until repo has a compose stack)"
Write-Host "Redpanda Kafka:    localhost:9092"
Write-Host ""
Write-Host "This script syncs gateway/system.local.env into per-repo .env files for local development. Replace generated secrets before any non-local use."
