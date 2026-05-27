param(
    [switch]$SkipIdentity,
    [switch]$SkipSales,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

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

    Push-Location $repoPath
    try {
        $display = "docker compose exec -T $Service $($Command -join ' ')"
        if ($DryRun) {
            Write-Host "Would run in ${RepoFolder}: $display"
            return
        }

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
    Invoke-ComposeExec `
        -RepoFolder "Advantage_master_program_Sales" `
        -Service "user_dba" `
        -Command @("python", "-m", "alembic", "-c", "db/user/alembic.ini", "upgrade", "head")

    Invoke-ComposeExec `
        -RepoFolder "Advantage_master_program_Sales" `
        -Service "quotation_dba" `
        -Command @("python", "-m", "alembic", "-c", "db/quotation/alembic.ini", "upgrade", "head")
}

Write-Host "Local migration orchestration complete."
Write-Host "Calendar migrations are intentionally skipped until Calendar read-model Alembic setup exists."
