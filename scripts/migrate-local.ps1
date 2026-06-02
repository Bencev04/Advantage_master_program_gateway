param(
    [switch]$SkipIdentity,
    [switch]$SkipSales,
    [switch]$DryRun,
    [int]$ReadyTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

function Wait-ForAlembic {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][string]$Service,
        [int]$TimeoutSeconds = 180
    )

    Push-Location $RepoPath
    try {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            & docker compose exec -T $Service python -c "import alembic" 2>$null
            if ($LASTEXITCODE -eq 0) { return }
            Start-Sleep -Seconds 3
        }
        throw "Timed out waiting for alembic to be importable in $Service after ${TimeoutSeconds}s"
    }
    finally {
        Pop-Location
    }
}

function Invoke-ComposeExec {
    param(
        [Parameter(Mandatory = $true)][string]$RepoFolder,
        [Parameter(Mandatory = $true)][string]$Service,
        [Parameter(Mandatory = $true)][string[]]$Command
    )

    $repoPath = Join-Path $workspaceRoot $RepoFolder
    if (-not (Test-Path (Join-Path $repoPath "docker-compose.yml"))) {
        Write-Warning "$RepoFolder has no docker-compose.yml. Skipping."
        return
    }

    if ($DryRun) {
        Write-Host "Would run in ${RepoFolder}: docker compose exec -T $Service $($Command -join ' ')"
        return
    }

    Wait-ForAlembic -RepoPath $repoPath -Service $Service -TimeoutSeconds $ReadyTimeoutSeconds

    Push-Location $repoPath
    try {
        & docker compose exec -T $Service @Command
        if ($LASTEXITCODE -ne 0) {
            throw "Migration command failed in $RepoFolder service $Service with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

if (-not $SkipIdentity) {
    Invoke-ComposeExec `
        -RepoFolder "Advantage_master_program_identity" `
        -Service "identity_dba" `
        -Command @("python", "-m", "alembic", "-c", "db/identity/alembic.ini", "upgrade", "head")
}

if (-not $SkipSales) {
    # PR3 hard-cut: user_dba / db/user removed. Quotation is the only Sales DB now.
    Invoke-ComposeExec `
        -RepoFolder "Advantage_master_program_sales" `
        -Service "quotation_dba" `
        -Command @("python", "-m", "alembic", "-c", "db/quotation/alembic.ini", "upgrade", "head")
}

Write-Host "Local migration orchestration complete."
Write-Host "Calendar migrations are intentionally skipped until Calendar read-model Alembic setup exists."
